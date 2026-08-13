using System.Text;
using Lumen.Api.Cycle;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Cycle;

/// <summary>
/// <c>POST /cycle/day/{date}</c> and <c>GET /cycle/day/{date}</c> (T10), exercised through
/// <see cref="CycleDayService"/> against the real model on Sqlite with the real
/// <c>AesGcmFieldCipher</c> and a frozen clock.
///
/// <para>Four facts here are load-bearing beyond this endpoint. <b>§G9:</b> <c>cycle_day_logs</c>
/// carries an UNFILTERED unique index on <c>(UserId, Day)</c>, so the upsert revives a tombstone
/// rather than inserting a second row. <b>§G8:</b> this write is capped by the user's today and has
/// <b>no backdate floor</b> — the floor is <c>cycle_events</c>-only, and applying it here would
/// reject the historical logging D-13 explicitly permits. <b>D-08:</b> <c>pain = 0</c> is a real
/// datum ("none today"), never "absent", so it must satisfy the "at least one field" rule and be
/// stored as 0. <b>MERGE:</b> this row has several writers, so an absent or <see langword="null"/>
/// field is left unchanged — the opposite of <c>POST /cycle/events</c>, whose row has one writer and
/// is a full upsert. The two rules sit side by side on their DTOs in <c>CycleContracts.cs</c>.</para>
/// </summary>
public sealed class CycleDayServiceTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    private static LogCycleDayRequest Request(int? pain = null, int? mood = null, string? notes = null) =>
        new(pain, mood, notes);

    private static IReadOnlyList<string> MessagesFor(CycleDayResult result, string field) =>
        result.ShouldBeOfType<CycleDayResult.Invalid>().Errors
            .Where(e => e.Field == field).Select(e => e.Message).ToList();

    private Task<CycleDayResult> PostAsync(LogCycleDayRequest request, DateOnly? date = null) =>
        _harness.NewDayService().UpsertDayAsync(date ?? CycleTestHarness.Today, request, CancellationToken.None);

    private int AllDayLogCount() =>
        _harness.NewContext().CycleDayLogs.IgnoreQueryFilters().Count(l => l.UserId == _harness.UserId);

    private int LiveDayLogCount() =>
        _harness.NewContext().CycleDayLogs.Count(l => l.UserId == _harness.UserId);

    private CycleDayLog StoredRow() =>
        _harness.NewContext().CycleDayLogs.IgnoreQueryFilters().Single(l => l.UserId == _harness.UserId);

    // --- validation: at least one of {pain, mood, notes} ----------------------------------

    [Fact]
    public async Task An_empty_payload_is_rejected_under_the_request_key()
    {
        var result = await PostAsync(Request());

        MessagesFor(result, ValidationProblemBuilder.RequestKey)
            .ShouldBe([CycleValidationMessages.DayLogEmpty]);
        AllDayLogCount().ShouldBe(0);
    }

    [Fact]
    public async Task Whitespace_only_notes_do_not_satisfy_the_at_least_one_rule()
    {
        var result = await PostAsync(Request(notes: "   "));

        MessagesFor(result, ValidationProblemBuilder.RequestKey)
            .ShouldBe([CycleValidationMessages.DayLogEmpty]);
        AllDayLogCount().ShouldBe(0);
    }

    [Fact]
    public async Task Pain_zero_alone_satisfies_the_at_least_one_rule_and_is_stored_as_zero()
    {
        // D-08 / NRS-11: 0 is "no pain today", a real answer the user gave. Treating it as "absent"
        // would both reject this request and lose the datum — the single most consequential
        // off-by-one in the logging surface.
        var result = await PostAsync(Request(pain: 0));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Pain.ShouldBe(0);
        StoredRow().Pain.ShouldBe((short)0);
    }

    [Fact]
    public async Task Mood_alone_satisfies_the_at_least_one_rule()
    {
        var result = await PostAsync(Request(mood: CycleDayLog.MoodScale.Steady));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Mood.ShouldBe(CycleDayLog.MoodScale.Steady);
    }

    [Fact]
    public async Task Notes_alone_satisfy_the_at_least_one_rule()
    {
        var result = await PostAsync(Request(notes: "un día tranquilo"));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Notes.ShouldBe("un día tranquilo");
    }

    // --- validation: pain 0–10 (NRS-11) ---------------------------------------------------

    [Theory]
    [InlineData(-1)]
    [InlineData(11)]
    [InlineData(100)]
    public async Task Pain_outside_the_0_to_10_scale_is_rejected(int pain)
    {
        var result = await PostAsync(Request(pain: pain));

        MessagesFor(result, "pain").ShouldBe([ValidationMessages.Between(0, 10)]);
        AllDayLogCount().ShouldBe(0);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(5)]
    [InlineData(10)]
    public async Task Every_value_on_the_pain_scale_is_accepted(int pain)
    {
        var result = await PostAsync(Request(pain: pain));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Pain.ShouldBe(pain);
    }

    // --- validation: mood 1–4 -------------------------------------------------------------

    [Theory]
    [InlineData(0)]
    [InlineData(5)]
    [InlineData(-2)]
    public async Task Mood_outside_the_1_to_4_scale_is_rejected(int mood)
    {
        var result = await PostAsync(Request(mood: mood));

        MessagesFor(result, "mood").ShouldBe([ValidationMessages.Between(1, 4)]);
        AllDayLogCount().ShouldBe(0);
    }

    [Theory]
    [InlineData(CycleDayLog.MoodScale.Low)]
    [InlineData(CycleDayLog.MoodScale.Tired)]
    [InlineData(CycleDayLog.MoodScale.Steady)]
    [InlineData(CycleDayLog.MoodScale.Bright)]
    public async Task Every_value_on_the_mood_scale_is_accepted(short mood)
    {
        var result = await PostAsync(Request(mood: mood));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Mood.ShouldBe(mood);
    }

    // --- validation: notes -----------------------------------------------------------------

    [Fact]
    public async Task Notes_of_exactly_2000_characters_are_accepted()
    {
        var result = await PostAsync(Request(notes: new string('a', 2000)));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Notes!.Length.ShouldBe(2000);
    }

    [Fact]
    public async Task Notes_of_2001_characters_are_rejected()
    {
        var result = await PostAsync(Request(notes: new string('a', 2001)));

        MessagesFor(result, "notes").ShouldBe([ValidationMessages.MaxLength(FieldLimits.MaxNotesLength)]);
        AllDayLogCount().ShouldBe(0);
    }

    [Fact]
    public async Task Notes_are_measured_after_trimming()
    {
        var result = await PostAsync(Request(notes: "  " + new string('a', 2000) + "  "));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Notes!.Length.ShouldBe(2000);
    }

    [Fact]
    public async Task Notes_are_stored_as_ciphertext_never_plaintext()
    {
        const string note = "dolor sordo todo el día";

        var result = await PostAsync(Request(pain: 4, notes: note));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Notes.ShouldBe(note);
        var row = StoredRow();
        row.NotesEnc.ShouldNotBeNull();
        Encoding.UTF8.GetString(row.NotesEnc!).ShouldNotContain("dolor");
        row.NotesEnc!.Length.ShouldBeGreaterThanOrEqualTo(28); // 12-byte nonce + ciphertext + 16-byte tag
        (await _harness.Crypto.DecryptStringAsync(row.NotesEnc!)).ShouldBe(note);
    }

    // --- validation: the §G8 date window (capped by today, NO floor) -----------------------

    [Fact]
    public async Task A_future_date_is_rejected()
    {
        var result = await PostAsync(Request(pain: 3), CycleTestHarness.Today.AddDays(1));

        MessagesFor(result, "date").ShouldBe([ValidationMessages.FutureDate]);
        AllDayLogCount().ShouldBe(0);
    }

    [Fact]
    public async Task Today_is_accepted_so_the_ceiling_is_inclusive()
    {
        var result = await PostAsync(Request(pain: 3), CycleTestHarness.Today);

        result.ShouldBeOfType<CycleDayResult.Saved>();
    }

    [Fact]
    public async Task A_date_before_the_cycle_events_backdate_floor_is_ACCEPTED()
    {
        // §G8, stated as a test because it is the easiest rule in the phase to get wrong by copying
        // T9: D-13 gives ONLY cycle_events a floor. A day log five years back is legitimate history
        // (a user transcribing an old paper diary), and rejecting it would lose real data.
        var wayBack = CycleTestHarness.Floor.AddYears(-3);

        var result = await _harness.NewDayService().UpsertDayAsync(wayBack, Request(pain: 6), CancellationToken.None);

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Day.ShouldBe(wayBack);
        StoredRow().Day.ShouldBe(wayBack);
    }

    // --- validate-then-act ------------------------------------------------------------------

    [Fact]
    public async Task Every_field_error_is_collected_before_any_write()
    {
        var result = await _harness.NewDayService().UpsertDayAsync(
            CycleTestHarness.Today.AddDays(4),
            Request(pain: 42, mood: 9, notes: new string('a', 2001)),
            CancellationToken.None);

        var invalid = result.ShouldBeOfType<CycleDayResult.Invalid>();
        invalid.Errors.Select(e => e.Field).ShouldBe(["date", "pain", "mood", "notes"], ignoreOrder: true);
        AllDayLogCount().ShouldBe(0);
    }

    // --- upsert on (UserId, Day) — §G9 UNFILTERED index regime -------------------------------

    [Fact]
    public async Task Posting_the_same_day_twice_updates_one_row_keeping_CreatedAt()
    {
        var later = CycleTestHarness.Now.AddHours(6);

        var first = (await PostAsync(Request(pain: 2, mood: 2))).ShouldBeOfType<CycleDayResult.Saved>().Log;
        var second = (await _harness.NewDayService(_harness.DayInfo(now: later))
                .UpsertDayAsync(CycleTestHarness.Today, Request(pain: 7, mood: 4), CancellationToken.None))
            .ShouldBeOfType<CycleDayResult.Saved>().Log;

        first.CreatedAt.ShouldBe(CycleTestHarness.Now);
        second.CreatedAt.ShouldBe(CycleTestHarness.Now, "CreatedAt belongs to the original observation");
        second.UpdatedAt.ShouldBe(later);
        second.Pain.ShouldBe(7);
        AllDayLogCount().ShouldBe(1);
    }

    [Fact]
    public async Task A_second_post_that_omits_a_field_LEAVES_IT_UNCHANGED()
    {
        // MERGE semantics, and the opposite of T9's `POST /cycle/events` on purpose. `cycle_day_logs`
        // is a MULTI-WRITER row: the quick check-in writes pain+mood, the day-detail form writes pain,
        // mood and the note, and D-10's energy/libido land on it later. A body read as "the row's
        // desired FINAL state" would let whichever screen posted last silently destroy what the other
        // one recorded — the same wipe `POST /checkin/quick` was already special-cased to avoid.
        // The cost is that P4a ships NO way to clear an individual field, which is an explicit,
        // documented limitation (and matches screens 9 and 11, neither of which offers a clear
        // affordance) rather than an invisible cross-surface data loss.
        await PostAsync(Request(pain: 8, mood: 1, notes: "mal día"));

        var result = await PostAsync(Request(mood: 4));

        var log = result.ShouldBeOfType<CycleDayResult.Saved>().Log;
        log.Mood.ShouldBe(4);
        log.Pain.ShouldBe(8, "an omitted field is left alone, never cleared");
        log.Notes.ShouldBe("mal día", "the 200 body echoes the stored row, not only what this request supplied");
        var row = StoredRow();
        row.Pain.ShouldBe((short)8);
        row.NotesEnc.ShouldNotBeNull();
        (await _harness.Crypto.DecryptStringAsync(row.NotesEnc!)).ShouldBe("mal día");
        AllDayLogCount().ShouldBe(1);
    }

    [Fact]
    public async Task Posting_only_pain_leaves_every_other_column_another_writer_filled()
    {
        // The multi-writer survival case stated end to end, because it is the whole reason the rule
        // is MERGE: one row, several surfaces, none of which re-sends the others' fields.
        var notesEnc = await _harness.Crypto.EncryptStringAsync("cólicos leves");
        _harness.SeedDayLog(
            CycleTestHarness.Today,
            pain: 2,
            mood: CycleDayLog.MoodScale.Steady,
            energy: 4,
            libido: 2,
            notesEnc: notesEnc);

        var result = await PostAsync(Request(pain: 7));

        var log = result.ShouldBeOfType<CycleDayResult.Saved>().Log;
        log.Pain.ShouldBe(7, "the field the user supplied moves");
        log.Mood.ShouldBe(CycleDayLog.MoodScale.Steady);
        log.Notes.ShouldBe("cólicos leves");
        var row = StoredRow();
        row.Mood.ShouldBe(CycleDayLog.MoodScale.Steady);
        row.Energy.ShouldBe((short)4);
        row.Libido.ShouldBe((short)2);
        (await _harness.Crypto.DecryptStringAsync(row.NotesEnc!)).ShouldBe("cólicos leves");
        AllDayLogCount().ShouldBe(1);
    }

    [Fact]
    public async Task A_second_post_of_pain_zero_overwrites_the_stored_pain_because_zero_is_SUPPLIED()
    {
        // D-08 gets SHARPER under merge, not softer. "Absent means leave alone" has to be tested with
        // `is null` and never with falsiness: `pain: 0` is a supplied datum ("none today") and must
        // overwrite this morning's 8, while everything the request did not name survives. A
        // `row.Pain = request.Pain ?? row.Pain` written over a truthiness check would keep every other
        // test in this file green and lose exactly this value.
        await PostAsync(Request(pain: 8, mood: 2));

        var result = await PostAsync(Request(pain: 0));

        var log = result.ShouldBeOfType<CycleDayResult.Saved>().Log;
        log.Pain.ShouldBe(0, "0 is a supplied value, not an absence");
        log.Mood.ShouldBe(2, "and it is the only field this request supplied");
        StoredRow().Pain.ShouldBe((short)0);
    }

    [Fact]
    public async Task The_full_form_never_touches_the_deferred_energy_and_libido_columns()
    {
        // D-10 defers both scales: there is no DTO field at all, so neither write path may "complete"
        // the row with nulls. Distinct from the merge rule above — a field that cannot be sent is a
        // stronger guarantee than a field that may be omitted.
        _harness.SeedDayLog(CycleTestHarness.Today, energy: 3, libido: 2);

        await PostAsync(Request(pain: 5));

        var row = StoredRow();
        row.Energy.ShouldBe((short)3);
        row.Libido.ShouldBe((short)2);
    }

    [Fact]
    public async Task Re_posting_a_soft_deleted_day_revives_the_tombstone_instead_of_duplicating_it()
    {
        // The unfiltered unique index means the tombstone still occupies (UserId, Day): a blind
        // insert here is a 23505 surfacing as a 500, not a duplicate row.
        var tombstone = _harness.SeedDayLog(
            CycleTestHarness.Today, pain: 9, deletedAt: CycleTestHarness.Now.AddHours(-1));

        var result = await PostAsync(Request(pain: 3));

        result.ShouldBeOfType<CycleDayResult.Saved>().Log.Pain.ShouldBe(3);
        AllDayLogCount().ShouldBe(1);
        LiveDayLogCount().ShouldBe(1);
        var row = StoredRow();
        row.Id.ShouldBe(tombstone.Id, "the upsert must revive the row, not mint a second one");
        row.DeletedAt.ShouldBeNull();
        row.CreatedAt.ShouldBe(CycleTestHarness.Now, "a revived row keeps its original CreatedAt");
    }

    [Fact]
    public async Task Different_days_are_separate_rows()
    {
        await PostAsync(Request(pain: 1), CycleTestHarness.Today);
        await PostAsync(Request(pain: 2), CycleTestHarness.Today.AddDays(-1));

        LiveDayLogCount().ShouldBe(2);
    }

    [Fact]
    public async Task Another_users_row_on_the_same_day_is_untouched()
    {
        var theirs = _harness.SeedDayLog(CycleTestHarness.Today, userId: _harness.OtherUserId, pain: 1);

        await PostAsync(Request(pain: 9));

        _harness.NewContext().CycleDayLogs.Single(l => l.Id == theirs.Id).Pain.ShouldBe((short)1);
        LiveDayLogCount().ShouldBe(1);
    }

    // --- GET /cycle/day/{date} ----------------------------------------------------------------

    [Fact]
    public async Task An_unlogged_day_reads_back_as_200_with_a_null_log_and_empty_collections()
    {
        // 404 is reserved for "no such user" (§G12). "Nothing logged" is a perfectly good answer and
        // the day-detail screen renders it as an empty state, not as an error.
        var result = await _harness.NewDayService().GetDayAsync(CycleTestHarness.Today, CancellationToken.None);

        var day = result.ShouldBeOfType<CycleDayReadResult.Found>().Day;
        day.Date.ShouldBe(CycleTestHarness.Today);
        day.Log.ShouldBeNull();
        day.Events.ShouldBeEmpty();
        day.PhaseOverrides.ShouldBeEmpty();
    }

    [Fact]
    public async Task A_logged_day_reads_back_with_the_decrypted_note()
    {
        const string note = "cólicos por la tarde";
        await PostAsync(Request(pain: 6, mood: 2, notes: note));

        var result = await _harness.NewDayService().GetDayAsync(CycleTestHarness.Today, CancellationToken.None);

        var log = result.ShouldBeOfType<CycleDayReadResult.Found>().Day.Log.ShouldNotBeNull();
        log.Pain.ShouldBe(6);
        log.Mood.ShouldBe(2);
        log.Notes.ShouldBe(note);
    }

    [Fact]
    public async Task A_soft_deleted_day_log_is_not_returned()
    {
        _harness.SeedDayLog(CycleTestHarness.Today, pain: 5, deletedAt: CycleTestHarness.Now);

        var result = await _harness.NewDayService().GetDayAsync(CycleTestHarness.Today, CancellationToken.None);

        result.ShouldBeOfType<CycleDayReadResult.Found>().Day.Log.ShouldBeNull();
    }

    [Fact]
    public async Task The_day_carries_that_days_events_with_their_notes_decrypted()
    {
        await _harness.NewService().LogEventAsync(
            new LogCycleEventRequest(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today, 3, "flujo abundante"),
            CancellationToken.None);
        // A neighbouring day must not leak into this one.
        await _harness.NewService().LogEventAsync(
            new LogCycleEventRequest(CycleEvent.Kinds.Spotting, CycleTestHarness.Today.AddDays(-1), 1, null),
            CancellationToken.None);

        var result = await _harness.NewDayService().GetDayAsync(CycleTestHarness.Today, CancellationToken.None);

        var day = result.ShouldBeOfType<CycleDayReadResult.Found>().Day;
        day.Events.Count.ShouldBe(1);
        day.Events[0].Kind.ShouldBe(CycleEvent.Kinds.PeriodStart);
        day.Events[0].FlowIntensity.ShouldBe(3);
        day.Events[0].Notes.ShouldBe("flujo abundante");
    }

    [Fact]
    public async Task A_soft_deleted_event_is_not_returned_on_the_day()
    {
        var saved = (await _harness.NewService().LogEventAsync(
                new LogCycleEventRequest(CycleEvent.Kinds.Spotting, CycleTestHarness.Today, null, null),
                CancellationToken.None))
            .ShouldBeOfType<CycleEventResult.Saved>().Event;
        await _harness.NewService().DeleteEventAsync(saved.Id, CancellationToken.None);

        var result = await _harness.NewDayService().GetDayAsync(CycleTestHarness.Today, CancellationToken.None);

        result.ShouldBeOfType<CycleDayReadResult.Found>().Day.Events.ShouldBeEmpty();
    }

    [Fact]
    public async Task The_day_carries_the_live_phase_overrides_that_fall_on_it()
    {
        var cycleStart = CycleTestHarness.Today.AddDays(-6);
        _harness.SeedOverride(cycleStart, CyclePhaseOverride.Phases.Menstrual, CyclePhaseOverride.Boundaries.End, CycleTestHarness.Today);
        _harness.SeedOverride(cycleStart, CyclePhaseOverride.Phases.Follicular, CyclePhaseOverride.Boundaries.Start, CycleTestHarness.Today.AddDays(-1));
        _harness.SeedOverride(cycleStart, CyclePhaseOverride.Phases.Ovulatory, CyclePhaseOverride.Boundaries.Start, CycleTestHarness.Today, deletedAt: CycleTestHarness.Now);

        var result = await _harness.NewDayService().GetDayAsync(CycleTestHarness.Today, CancellationToken.None);

        var overrides = result.ShouldBeOfType<CycleDayReadResult.Found>().Day.PhaseOverrides;
        overrides.Count.ShouldBe(1, "only live corrections dated on this day");
        overrides[0].Phase.ShouldBe(CyclePhaseOverride.Phases.Menstrual);
        overrides[0].Boundary.ShouldBe(CyclePhaseOverride.Boundaries.End);
        overrides[0].OccurredOn.ShouldBe(CycleTestHarness.Today);
    }

    [Fact]
    public async Task The_read_never_returns_another_users_day()
    {
        _harness.SeedDayLog(CycleTestHarness.Today, userId: _harness.OtherUserId, pain: 7);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today, userId: _harness.OtherUserId);
        _harness.SeedOverride(
            CycleTestHarness.Today, CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start,
            CycleTestHarness.Today, userId: _harness.OtherUserId);

        var result = await _harness.NewDayService().GetDayAsync(CycleTestHarness.Today, CancellationToken.None);

        var day = result.ShouldBeOfType<CycleDayReadResult.Found>().Day;
        day.Log.ShouldBeNull();
        day.Events.ShouldBeEmpty();
        day.PhaseOverrides.ShouldBeEmpty();
    }

    [Fact]
    public async Task A_future_date_is_readable_because_the_read_has_no_range_validation()
    {
        var result = await _harness.NewDayService()
            .GetDayAsync(CycleTestHarness.Today.AddYears(1), CancellationToken.None);

        result.ShouldBeOfType<CycleDayReadResult.Found>().Day.Log.ShouldBeNull();
    }

    // --- §G6: the read exposes no clinical inference -------------------------------------------

    [Fact]
    public void The_day_response_carries_no_phase_cycleDay_or_confidence_field()
    {
        // §G6, asserted structurally rather than promised in a comment: P4a computes no phase, no
        // cycle day and no confidence, so the read surface must not carry a key that a client could
        // bind a placeholder to. `phaseOverrides` is NOT such a key — it is the user's own stored
        // corrections (observed data), which is why it is named for the table and not for a phase.
        string[] forbidden = ["Phase", "CycleDay", "Confidence"];

        foreach (var type in new[] { typeof(CycleDayResponse), typeof(CycleDayLogResponse) })
        {
            var names = type.GetProperties().Select(p => p.Name).ToList();
            foreach (var name in forbidden) names.ShouldNotContain(name, $"{type.Name} must expose no {name}");
        }

        // ...and the one member whose name is close enough to matter is the corrections list, kept
        // distinct so this guard cannot be satisfied by renaming an inference into it.
        typeof(CycleDayResponse).GetProperties().Select(p => p.Name).ShouldContain("PhaseOverrides");
    }

    // --- the erased-user fence ------------------------------------------------------------------

    [Fact]
    public async Task A_crypto_shredded_user_cannot_post_a_day_log()
    {
        var result = await _harness.NewDayService(null)
            .UpsertDayAsync(CycleTestHarness.Today, Request(pain: 5), CancellationToken.None);

        result.ShouldBeOfType<CycleDayResult.UserNotFound>();
        AllDayLogCount().ShouldBe(0);
    }

    [Fact]
    public async Task A_crypto_shredded_user_is_rejected_before_validation_so_nothing_leaks()
    {
        // The 404 wins over the 400: an erased token learns nothing about its own payload, and — far
        // more importantly — the check runs before the write, which is the ONLY fence between a
        // still-valid JWT and a fresh plaintext health row (see CycleService's remarks).
        var result = await _harness.NewDayService(null)
            .UpsertDayAsync(CycleTestHarness.Today.AddDays(30), Request(pain: 99, mood: 99), CancellationToken.None);

        result.ShouldBeOfType<CycleDayResult.UserNotFound>();
        AllDayLogCount().ShouldBe(0);
    }

    [Fact]
    public async Task A_crypto_shredded_user_cannot_read_a_day()
    {
        var result = await _harness.NewDayService(null).GetDayAsync(CycleTestHarness.Today, CancellationToken.None);

        result.ShouldBeOfType<CycleDayReadResult.UserNotFound>();
    }

    // --- frozen wire strings ---------------------------------------------------------------------

    [Fact]
    public void The_cycle_day_validation_message_is_frozen()
    {
        // §G12: every test above asserts the rejection THROUGH the constant, which pins the service
        // to the constant but pins the constant to nothing — reword the literal and they all stay
        // green. This is the assertion that makes rewording it a failing test, as it should be: the
        // Flutter client renders this sentence verbatim.
        CycleValidationMessages.DayLogEmpty.ShouldBe("at least one of pain, mood or notes is required");
    }

    [Fact]
    public void The_shared_note_cap_is_the_D_13_value()
    {
        // Hoisted out of CycleService (T9) so cycle_day_logs, cycle_events and T11's symptoms all
        // read one number instead of three copies of the literal 2000.
        FieldLimits.MaxNotesLength.ShouldBe(2000);
    }
}
