using System.Reflection;
using Lumen.Api.Cycle;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Cycle;

/// <summary>
/// <c>GET /cycle/calendar?from&amp;to</c> (T13), exercised through <see cref="CycleCalendarService"/>
/// against the real model on Sqlite with a frozen clock.
///
/// <para><b>This is the bounded sparse aggregation behind screens 8 and 10.</b> It counts rows in the
/// three observation tables — <c>cycle_day_logs</c>, <c>cycle_events</c> and <c>symptoms</c> — and
/// emits <b>one row per day that has something on it</b>. A day with nothing logged is absent, not a
/// zero row: a month view is mostly empty, and 31 empty rows per request is payload the client throws
/// away.</para>
///
/// <para><b>§G6 is the whole shape of this response.</b> P4a computes no phase, no cycle day and no
/// confidence, so <b>no day row carries any of those keys</b>; the single
/// <c>phase: { available: false, unavailableReason: "phase_engine_not_implemented" }</c> envelope on
/// the response is the only phase-shaped thing here, and it exists precisely to say the engine is not
/// implemented. Both facts are asserted structurally below (by reflection over the DTOs), because a
/// value assertion would pass just as happily on a DTO that had grown a <c>phase</c> property nobody
/// filled in yet.</para>
///
/// <para><b>The window is expressed in USER-LOCAL DAYS and matched on the day-keyed columns</b>
/// (<c>Day</c>, <c>OccurredOn</c>), exactly as <c>GET /symptoms</c> does (T12) — never on a UTC
/// instant recomputed from the bounds, which would answer differently for rows logged before the user
/// last changed timezone.</para>
///
/// <para><b>The ≤366-day cap is a P4a INVENTION (§G11).</b> It bounds a date window; it is not the
/// D-13 50/100 offset page, and this read is deliberately not paginated.</para>
/// </summary>
public sealed class CycleCalendarServiceTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    /// <summary>The user's local today in the harness: 2026-08-06, so the default window is August 2026.</summary>
    private static readonly DateOnly Today = CycleTestHarness.Today;

    private static readonly DateOnly MonthStart = new(2026, 8, 1);
    private static readonly DateOnly MonthEnd = new(2026, 8, 31);

    // --- helpers ------------------------------------------------------------------------------

    private CycleCalendarService Service(UserDayInfo? info = null, bool erased = false) =>
        _harness.NewCalendarService(erased ? null : info ?? _harness.DayInfo());

    private Task<CycleCalendarResult> GetAsync(
        DateOnly? from = null,
        DateOnly? to = null,
        UserDayInfo? info = null,
        bool erased = false) =>
        Service(info, erased).GetCalendarAsync(from, to, CancellationToken.None);

    private static CycleCalendarResponse Found(CycleCalendarResult result) =>
        result.ShouldBeOfType<CycleCalendarResult.Found>().Calendar;

    private static IReadOnlyList<string> MessagesFor(CycleCalendarResult result, string field) =>
        result.ShouldBeOfType<CycleCalendarResult.Invalid>().Errors
            .Where(e => e.Field == field).Select(e => e.Message).ToList();

    private static CycleCalendarDay DayOf(CycleCalendarResponse calendar, DateOnly date) =>
        calendar.Days.SingleOrDefault(d => d.Date == date)
        ?? throw new InvalidOperationException($"no day row for {date:yyyy-MM-dd}");

    // --- §G6: the phase envelope, and NOTHING phase-shaped on a day row -------------------------

    [Fact]
    public async Task The_calendar_reports_that_no_phase_engine_exists_yet()
    {
        // The ONE reason this endpoint may say anything phase-shaped at all. P6 ships the engine;
        // until then the honest answer is "not implemented", stated once for the whole window rather
        // than guessed per day.
        var calendar = Found(await GetAsync());

        calendar.Phase.Available.ShouldBeFalse();
        calendar.Phase.UnavailableReason.ShouldBe(CyclePhaseAvailability.PhaseEngineNotImplemented);
    }

    [Fact]
    public void The_unavailable_reason_is_the_frozen_wire_string()
    {
        // §G12: asserted against the LITERAL, never through the constant — this string reaches the
        // Flutter client through the generated contract, so rewording it is a contract change.
        CyclePhaseAvailability.PhaseEngineNotImplemented.ShouldBe("phase_engine_not_implemented");
    }

    [Fact]
    public void No_day_row_can_carry_a_phase_a_cycle_day_or_a_confidence()
    {
        // Structural, not value-based, and deliberately so: asserting `day.Phase == null` would pass
        // on a DTO that had grown the property, which is exactly the failure §G6 names — a
        // not-yet-implemented estimate rendered as a clinical fact because the key was there first.
        var forbidden = new[] { "phase", "cycleday", "confidence" };

        foreach (var property in typeof(CycleCalendarDay).GetProperties())
        {
            forbidden.ShouldNotContain(
                property.Name.ToLowerInvariant(),
                $"CycleCalendarDay.{property.Name} is clinical inference P4a does not compute (§G6)");
        }
    }

    [Fact]
    public void The_response_carries_no_cycle_day_and_no_confidence_either()
    {
        // `phase` IS present on the response — that is the envelope. `cycleDay` and `confidence` have
        // no such not-implemented form, so they must not exist at all.
        var names = typeof(CycleCalendarResponse).GetProperties().Select(p => p.Name).ToList();

        names.ShouldNotContain("CycleDay");
        names.ShouldNotContain("Confidence");
        names.ShouldContain("Phase");
    }

    // --- the default window: the user's current month ------------------------------------------

    [Fact]
    public async Task An_absent_from_and_to_default_to_the_user_local_current_month()
    {
        var calendar = Found(await GetAsync());

        calendar.From.ShouldBe(MonthStart);
        calendar.To.ShouldBe(MonthEnd);
    }

    [Fact]
    public async Task The_default_month_is_the_users_month_not_the_servers_utc_month()
    {
        // The bounds come from UserDayInfo.Today (D-12), which is already the user's local day. A
        // month derived from a UTC clock would put a Madrid user on the wrong month for the first and
        // last hours of it.
        var newYearsDay = new DateOnly(2027, 1, 1);
        var info = new UserDayInfo(
            _harness.UserId, newYearsDay, CycleTestHarness.Floor, CycleTestHarness.Madrid,
            new DateTimeOffset(2026, 12, 31, 23, 30, 0, TimeSpan.Zero));

        var calendar = Found(await GetAsync(info: info));

        calendar.From.ShouldBe(new DateOnly(2027, 1, 1));
        calendar.To.ShouldBe(new DateOnly(2027, 1, 31));
    }

    [Fact]
    public async Task Only_the_supplied_bound_overrides_its_own_edge_of_the_month()
    {
        // Each parameter defaults independently, so `?from=` alone is "from this day to the end of my
        // month" rather than a 400. There is no unbounded read to fall into: the far edge is still a
        // real, bounded date the response echoes back.
        var fromOnly = Found(await GetAsync(from: new DateOnly(2026, 7, 15)));
        fromOnly.From.ShouldBe(new DateOnly(2026, 7, 15));
        fromOnly.To.ShouldBe(MonthEnd);

        var toOnly = Found(await GetAsync(to: new DateOnly(2026, 8, 10)));
        toOnly.From.ShouldBe(MonthStart);
        toOnly.To.ShouldBe(new DateOnly(2026, 8, 10));
    }

    [Fact]
    public async Task Both_ends_of_the_window_are_inclusive()
    {
        _harness.SeedDayLog(MonthStart, pain: 1);
        _harness.SeedDayLog(MonthEnd, pain: 2);
        _harness.SeedDayLog(MonthStart.AddDays(-1), pain: 3);
        _harness.SeedDayLog(MonthEnd.AddDays(1), pain: 4);

        var calendar = Found(await GetAsync());

        calendar.Days.Select(d => d.Date).ShouldBe([MonthStart, MonthEnd]);
    }

    [Fact]
    public async Task The_echoed_bounds_are_the_ones_actually_applied()
    {
        var calendar = Found(await GetAsync(from: Today.AddDays(-3), to: Today));

        calendar.From.ShouldBe(Today.AddDays(-3));
        calendar.To.ShouldBe(Today);
    }

    // --- window validation: inverted, and the §G11 366-day cap ----------------------------------

    [Fact]
    public async Task A_to_before_from_is_rejected_rather_than_answered_with_an_empty_calendar()
    {
        // Same rule and the same wire string as GET /symptoms (T12): an inverted window is a client
        // bug, and answering it with an empty calendar is indistinguishable from "you logged nothing
        // that month" — the reading that hides the bug forever.
        var result = await GetAsync(from: Today, to: Today.AddDays(-1));

        MessagesFor(result, "to").ShouldBe([ValidationMessages.RangeEndBeforeStart]);
    }

    [Fact]
    public async Task A_single_day_window_is_accepted()
    {
        _harness.SeedDayLog(Today, pain: 5);

        var calendar = Found(await GetAsync(from: Today, to: Today));

        calendar.Days.Count.ShouldBe(1);
    }

    [Fact]
    public async Task A_window_of_exactly_366_days_is_accepted()
    {
        // The cap is INCLUSIVE and both ends of the window count, so the widest legal window is
        // `from + 365`. 366 rather than 365 so a leap year's full calendar fits in one request.
        var from = new DateOnly(2026, 1, 1);
        var to = from.AddDays(CycleCalendarWindow.MaxDays - 1);

        var calendar = Found(await GetAsync(from: from, to: to));

        calendar.From.ShouldBe(from);
        calendar.To.ShouldBe(to);
    }

    [Fact]
    public async Task A_window_of_367_days_is_rejected()
    {
        var from = new DateOnly(2026, 1, 1);
        var to = from.AddDays(CycleCalendarWindow.MaxDays);

        var result = await GetAsync(from: from, to: to);

        MessagesFor(result, "to")
            .ShouldBe([CycleValidationMessages.MaxWindowDays(CycleCalendarWindow.MaxDays)]);
    }

    [Fact]
    public async Task An_inverted_window_is_reported_as_inverted_and_not_also_as_too_long()
    {
        // A negative span is not a 400,000-day one. Reporting both would give the client two messages
        // on one field, only one of which is actionable.
        var result = await GetAsync(from: new DateOnly(2026, 8, 1), to: new DateOnly(2020, 1, 1));

        MessagesFor(result, "to").ShouldBe([ValidationMessages.RangeEndBeforeStart]);
    }

    [Fact]
    public void The_window_cap_is_the_P4a_invented_366_and_is_frozen()
    {
        // §G11: a P4a INVENTION, recorded here and in the T22 STATUS block so a later phase does not
        // mistake it for a ratified clinical or product number. Asserted against the literal (§G12).
        CycleCalendarWindow.MaxDays.ShouldBe(366);
    }

    [Fact]
    public void The_window_messages_are_frozen()
    {
        // Wire strings the Flutter client renders verbatim.
        ValidationMessages.RangeEndBeforeStart.ShouldBe("date must not be before the start of the range");
        CycleValidationMessages.MaxWindowDays(366).ShouldBe("the range must not exceed 366 days");
    }

    // --- sparse rows: only days that have something ---------------------------------------------

    [Fact]
    public async Task Days_with_no_data_are_absent_rather_than_returned_as_empty_rows()
    {
        _harness.SeedDayLog(Today, pain: 4);

        var calendar = Found(await GetAsync());

        calendar.Days.Count.ShouldBe(1, "a month view is mostly empty; empty rows are payload the client discards");
        calendar.Days.Single().Date.ShouldBe(Today);
    }

    [Fact]
    public async Task An_entirely_empty_window_is_a_200_with_no_days()
    {
        // Nothing logged is the empty state screen 10 renders, never a 404 — 404 on this route means
        // "no such user" and nothing else (§G12).
        var calendar = Found(await GetAsync());

        calendar.Days.ShouldBeEmpty();
        calendar.Today.ShouldBe(Today);
    }

    [Fact]
    public async Task Day_rows_come_back_in_ascending_date_order()
    {
        // Seeded out of order, and the last of the three (Aug 11) is a FUTURE day — the sort is over
        // the union of all three tables' keys, not over insertion order and not over "up to today".
        _harness.SeedDayLog(Today, pain: 1);
        _harness.SeedDayLog(MonthStart, pain: 2);
        _harness.SeedEvent(CycleEvent.Kinds.Spotting, MonthStart.AddDays(10));

        var calendar = Found(await GetAsync());

        calendar.Days.Select(d => d.Date)
            .ShouldBe([MonthStart, Today, MonthStart.AddDays(10)]);
    }

    [Fact]
    public async Task A_day_that_only_has_an_event_or_only_has_a_symptom_still_appears()
    {
        // The three tables are independent sources: a user who taps "period started" and logs nothing
        // else has still marked that day, and screen 10 must draw it.
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, MonthStart);
        _harness.SeedSymptom(Symptom.Codes.Pain, 6, MonthStart.AddDays(5));

        var calendar = Found(await GetAsync());

        calendar.Days.Select(d => d.Date).ShouldBe([MonthStart, MonthStart.AddDays(5)]);
        DayOf(calendar, MonthStart).EventCount.ShouldBe(1);
        DayOf(calendar, MonthStart).Pain.ShouldBeNull("no day log was written for that day");
        DayOf(calendar, MonthStart.AddDays(5)).SymptomCount.ShouldBe(1);
    }

    // --- what a day row carries -----------------------------------------------------------------

    [Fact]
    public async Task A_day_row_carries_the_log_scales_and_the_counts_from_all_three_tables()
    {
        var notesEnc = await _harness.Crypto.EncryptStringAsync("cólicos por la mañana");
        _harness.SeedDayLog(Today, pain: 7, mood: 2, notesEnc: notesEnc);
        // (UserId, Kind, OccurredOn) is unique, so two events on one day means two different kinds.
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, Today, flow: 3);
        _harness.SeedEvent(CycleEvent.Kinds.Spotting, Today);
        _harness.SeedSymptom(Symptom.Codes.Pain, 6, Today);
        _harness.SeedSymptom(Symptom.NonPainCodes.Bloating, 4, Today);
        _harness.SeedSymptom(Symptom.NonPainCodes.Nausea, 2, Today);

        var day = DayOf(Found(await GetAsync()), Today);

        day.Pain.ShouldBe(7);
        day.Mood.ShouldBe(2);
        day.HasNotes.ShouldBeTrue();
        day.EventCount.ShouldBe(2);
        day.SymptomCount.ShouldBe(3);
    }

    [Fact]
    public async Task Pain_zero_is_a_datum_and_survives_as_zero_rather_than_as_an_absence()
    {
        // D-08: "none today" is the answer a well user taps, and coalescing it to null would drop
        // every pain-free day out of the series screen 8 draws.
        _harness.SeedDayLog(Today, pain: 0);

        DayOf(Found(await GetAsync()), Today).Pain.ShouldBe(0);
    }

    [Fact]
    public async Task Has_notes_is_a_flag_and_the_note_itself_never_leaves_the_column()
    {
        // No `*_enc` column is decrypted on this path. A calendar is a month of rows on a screen that
        // shows no note text at all — decrypting 31 notes to answer a boolean would be a month of
        // plaintext health data on the wire for nothing.
        _harness.SeedDayLog(Today, notesEnc: await _harness.Crypto.EncryptStringAsync("dolor al caminar"));
        _harness.SeedDayLog(Today.AddDays(-1), pain: 3);

        var calendar = Found(await GetAsync());

        DayOf(calendar, Today).HasNotes.ShouldBeTrue();
        DayOf(calendar, Today.AddDays(-1)).HasNotes.ShouldBeFalse();

        typeof(CycleCalendarDay).GetProperties().Select(p => p.Name)
            .ShouldNotContain("Notes", "the calendar exposes a flag, never the note");
    }

    [Fact]
    public void The_service_cannot_decrypt_anything_because_it_takes_no_crypto_context()
    {
        // Structural guard for the rule above: without an IUserCryptoContext there is no way for a
        // later edit to start decrypting notes on this path by accident.
        typeof(CycleCalendarService).GetConstructors(BindingFlags.Public | BindingFlags.Instance)
            .SelectMany(c => c.GetParameters())
            .Select(p => p.ParameterType)
            .ShouldNotContain(typeof(IUserCryptoContext));
    }

    [Fact]
    public async Task Future_days_inside_the_window_are_returned()
    {
        // The one read in this phase that legitimately looks forward: every WRITE is capped by today
        // (§G8), but screen 10 renders the rest of the month, and clamping the window the client just
        // drew would make the calendar disagree with itself. Seeded directly, because no P4a write
        // can create a future-dated row.
        _harness.SeedDayLog(Today.AddDays(3), pain: 5);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodEnd, Today.AddDays(4));

        var calendar = Found(await GetAsync(from: Today, to: Today.AddDays(10)));

        calendar.Days.Select(d => d.Date).ShouldBe([Today.AddDays(3), Today.AddDays(4)]);
    }

    // --- soft-deleted rows are invisible (D-13) --------------------------------------------------

    [Fact]
    public async Task A_tombstoned_day_log_event_and_symptom_are_all_excluded()
    {
        _harness.SeedDayLog(Today, pain: 9, deletedAt: CycleTestHarness.Now);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, Today, deletedAt: CycleTestHarness.Now);
        _harness.SeedSymptom(Symptom.Codes.Pain, 8, Today, deletedAt: CycleTestHarness.Now);

        var calendar = Found(await GetAsync());

        calendar.Days.ShouldBeEmpty("a day whose every row is a tombstone has nothing on it");
    }

    [Fact]
    public async Task A_tombstoned_row_does_not_inflate_a_count_on_a_day_that_survives()
    {
        _harness.SeedDayLog(Today, pain: 4);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, Today);
        _harness.SeedEvent(CycleEvent.Kinds.Spotting, Today, deletedAt: CycleTestHarness.Now);
        _harness.SeedSymptom(Symptom.Codes.Pain, 6, Today);
        _harness.SeedSymptom(Symptom.NonPainCodes.Fatigue, 3, Today, deletedAt: CycleTestHarness.Now);

        var day = DayOf(Found(await GetAsync()), Today);

        day.EventCount.ShouldBe(1);
        day.SymptomCount.ShouldBe(1);
    }

    [Fact]
    public async Task A_row_deleted_through_the_service_disappears_from_the_calendar()
    {
        var row = _harness.SeedEvent(CycleEvent.Kinds.Spotting, Today);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, Today);

        (await _harness.NewService().DeleteEventAsync(row.Id, CancellationToken.None))
            .ShouldBeOfType<CycleEventDeleteResult.Deleted>();

        DayOf(Found(await GetAsync()), Today).EventCount.ShouldBe(1);
    }

    // --- tenant scoping ---------------------------------------------------------------------------

    [Fact]
    public async Task Another_users_rows_are_absent_from_the_days_and_from_every_count()
    {
        _harness.SeedDayLog(Today, pain: 4);
        _harness.SeedDayLog(Today.AddDays(-1), pain: 9, userId: _harness.OtherUserId);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, Today, userId: _harness.OtherUserId);
        _harness.SeedSymptom(Symptom.Codes.Pain, 7, Today, userId: _harness.OtherUserId);

        var calendar = Found(await GetAsync());

        calendar.Days.Count.ShouldBe(1);
        var day = DayOf(calendar, Today);
        day.Pain.ShouldBe(4);
        day.EventCount.ShouldBe(0, "another tenant's event must not be counted onto this user's day");
        day.SymptomCount.ShouldBe(0);
    }

    // --- the erased-user fence --------------------------------------------------------------------

    [Fact]
    public async Task A_crypto_shredded_user_cannot_read_the_calendar()
    {
        _harness.SeedDayLog(Today, pain: 5);

        (await GetAsync(erased: true)).ShouldBeOfType<CycleCalendarResult.UserNotFound>();
    }

    [Fact]
    public async Task A_crypto_shredded_user_is_rejected_BEFORE_validation()
    {
        // Order matters on a read too: a 400 would confirm the request shape was understood, and any
        // branch that validated first would be one refactor away from also reading. The window below
        // is inverted, so a validate-first implementation would answer 400 instead of 404.
        var result = await _harness.NewCalendarService(null)
            .GetCalendarAsync(Today, Today.AddDays(-30), CancellationToken.None);

        result.ShouldBeOfType<CycleCalendarResult.UserNotFound>();
    }

    // --- read hygiene ------------------------------------------------------------------------------

    [Fact]
    public async Task The_read_tracks_nothing_so_a_later_write_in_the_same_scope_cannot_pick_it_up()
    {
        _harness.SeedDayLog(Today, pain: 5);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, Today);
        _harness.SeedSymptom(Symptom.Codes.Pain, 5, Today);

        var db = _harness.NewContext();
        var service = new CycleCalendarService(db, new StubUserDayContext(_harness.DayInfo()));

        Found(await service.GetCalendarAsync(null, null, CancellationToken.None)).Days.Count.ShouldBe(1);

        db.ChangeTracker.Entries<CycleDayLog>().ShouldBeEmpty();
        db.ChangeTracker.Entries<CycleEvent>().ShouldBeEmpty();
        db.ChangeTracker.Entries<Symptom>().ShouldBeEmpty();
    }

    [Fact]
    public async Task The_response_echoes_the_users_today_and_timezone()
    {
        // Screen 8 highlights "today" and screen 10 draws it: the server's answer is the one that
        // keyed every row, so the client never re-derives it from its own clock (D-12).
        var calendar = Found(await GetAsync());

        calendar.Today.ShouldBe(Today);
        calendar.Timezone.ShouldBe(CycleTestHarness.Madrid);
    }
}
