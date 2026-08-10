using Lumen.Api.Cycle;
using Lumen.Api.Symptoms;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Lumen.UnitTests.Cycle;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Symptoms;

/// <summary>
/// <c>POST /checkin/quick</c> (screen 9) — the app's most-tapped write, exercised through
/// <see cref="CycleDayService"/>.
///
/// <para><b>D-11 is the whole point of this suite.</b> The quick check-in <b>upserts
/// <c>cycle_day_logs</c> and writes NO <c>symptoms</c> row</b>: the day log is the headline
/// pain/mood series P6 estimates from, while <c>symptoms</c> holds classified episodes that only the
/// full form (T11) creates. Writing a symptom row here would double-count every tap of the check-in
/// sheet in every later aggregate.</para>
///
/// <para><b>It is a PARTIAL write, and that is the one place it differs from
/// <c>POST /cycle/day/{date}</c>.</b> The full form submits the whole day, so an omitted field
/// clears it; the check-in sheet only ever offers pain and mood, so it touches only the fields the
/// user actually supplied and never the note, energy or libido someone else wrote. Both halves are
/// asserted below, because the difference is invisible in the type signatures.</para>
/// </summary>
public sealed class QuickCheckinServiceTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    private Task<QuickCheckinResult> CheckinAsync(int? pain = null, int? mood = null, UserDayInfo? info = null) =>
        _harness.NewDayService(info ?? _harness.DayInfo())
            .QuickCheckinAsync(new QuickCheckinRequest(pain, mood), CancellationToken.None);

    private static IReadOnlyList<string> MessagesFor(QuickCheckinResult result, string field) =>
        result.ShouldBeOfType<QuickCheckinResult.Invalid>().Errors
            .Where(e => e.Field == field).Select(e => e.Message).ToList();

    private CycleDayLog StoredRow() =>
        _harness.NewContext().CycleDayLogs.IgnoreQueryFilters().Single(l => l.UserId == _harness.UserId);

    private int AllDayLogCount() =>
        _harness.NewContext().CycleDayLogs.IgnoreQueryFilters().Count(l => l.UserId == _harness.UserId);

    // --- at least one of {pain, mood} -------------------------------------------------------

    [Fact]
    public async Task Pain_only_is_accepted()
    {
        var result = await CheckinAsync(pain: 7);

        var checkin = result.ShouldBeOfType<QuickCheckinResult.Saved>().Checkin;
        checkin.Pain.ShouldBe(7);
        checkin.Mood.ShouldBeNull();
    }

    [Fact]
    public async Task Mood_only_is_accepted()
    {
        var result = await CheckinAsync(mood: CycleDayLog.MoodScale.Bright);

        var checkin = result.ShouldBeOfType<QuickCheckinResult.Saved>().Checkin;
        checkin.Mood.ShouldBe(CycleDayLog.MoodScale.Bright);
        checkin.Pain.ShouldBeNull();
    }

    [Fact]
    public async Task Both_together_are_accepted()
    {
        var result = await CheckinAsync(pain: 3, mood: CycleDayLog.MoodScale.Tired);

        var checkin = result.ShouldBeOfType<QuickCheckinResult.Saved>().Checkin;
        checkin.Pain.ShouldBe(3);
        checkin.Mood.ShouldBe(CycleDayLog.MoodScale.Tired);
    }

    [Fact]
    public async Task Neither_is_rejected_under_the_request_key_and_writes_nothing()
    {
        var result = await CheckinAsync();

        MessagesFor(result, ValidationProblemBuilder.RequestKey)
            .ShouldBe([SymptomValidationMessages.QuickCheckinEmpty]);
        AllDayLogCount().ShouldBe(0);
    }

    [Fact]
    public async Task Pain_zero_is_a_real_datum_and_satisfies_the_at_least_one_rule()
    {
        // D-08 / NRS-11 again, and this is the endpoint where getting it wrong hurts most: "no pain
        // today" is the answer a well user taps, and coalescing 0 into "absent" would reject it and
        // leave P6 with a series that only ever contains bad days.
        var result = await CheckinAsync(pain: 0);

        result.ShouldBeOfType<QuickCheckinResult.Saved>().Checkin.Pain.ShouldBe(0);
        StoredRow().Pain.ShouldBe((short)0);
    }

    // --- scales ------------------------------------------------------------------------------

    [Theory]
    [InlineData(-1)]
    [InlineData(11)]
    public async Task Pain_outside_the_0_to_10_scale_is_rejected(int pain)
    {
        var result = await CheckinAsync(pain: pain);

        MessagesFor(result, "pain").ShouldBe([ValidationMessages.Between(0, 10)]);
        AllDayLogCount().ShouldBe(0);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(5)]
    public async Task Mood_outside_the_1_to_4_scale_is_rejected(int mood)
    {
        var result = await CheckinAsync(mood: mood);

        MessagesFor(result, "mood").ShouldBe([ValidationMessages.Between(1, 4)]);
        AllDayLogCount().ShouldBe(0);
    }

    // --- D-11: no symptoms row, ever ----------------------------------------------------------

    [Fact]
    public async Task A_quick_checkin_writes_no_symptoms_row()
    {
        await CheckinAsync(pain: 9, mood: CycleDayLog.MoodScale.Low);

        _harness.NewContext().Symptoms.IgnoreQueryFilters().Count().ShouldBe(0);
        AllDayLogCount().ShouldBe(1);
    }

    // --- one row per day ----------------------------------------------------------------------

    [Fact]
    public async Task A_second_checkin_updates_the_same_row()
    {
        var later = CycleTestHarness.Now.AddHours(5);

        await CheckinAsync(pain: 2, mood: CycleDayLog.MoodScale.Steady);
        var second = await CheckinAsync(pain: 8, mood: CycleDayLog.MoodScale.Low, info: _harness.DayInfo(now: later));

        var checkin = second.ShouldBeOfType<QuickCheckinResult.Saved>().Checkin;
        checkin.Pain.ShouldBe(8);
        checkin.UpdatedAt.ShouldBe(later);
        AllDayLogCount().ShouldBe(1);
        var row = StoredRow();
        row.CreatedAt.ShouldBe(CycleTestHarness.Now, "CreatedAt belongs to the day, not to the latest tap");
    }

    [Fact]
    public async Task A_checkin_on_a_soft_deleted_day_revives_the_tombstone_instead_of_duplicating_it()
    {
        var tombstone = _harness.SeedDayLog(
            CycleTestHarness.Today, pain: 4, deletedAt: CycleTestHarness.Now.AddHours(-2));

        await CheckinAsync(mood: CycleDayLog.MoodScale.Steady);

        AllDayLogCount().ShouldBe(1);
        var row = StoredRow();
        row.Id.ShouldBe(tombstone.Id);
        row.DeletedAt.ShouldBeNull();
    }

    // --- the PARTIAL write ---------------------------------------------------------------------

    [Fact]
    public async Task A_quick_checkin_does_not_clear_the_notes_energy_or_libido_the_full_form_wrote()
    {
        // The user writes a note on the day-detail screen in the morning, then taps the check-in
        // sheet at night. Full-upsert semantics here would silently delete that note — which is why
        // this endpoint writes only the columns it owns.
        await _harness.NewDayService().UpsertDayAsync(
            CycleTestHarness.Today,
            new LogCycleDayRequest(2, CycleDayLog.MoodScale.Steady, "cólicos leves"),
            CancellationToken.None);
        // Energy/Libido have no writer in P4a (D-10 defers both scales), so they are seeded directly.
        await using (var seed = _harness.NewContext())
        {
            var seeded = seed.CycleDayLogs.Single(l => l.UserId == _harness.UserId);
            seeded.Energy = 3;
            seeded.Libido = 1;
            await seed.SaveChangesAsync();
        }

        await CheckinAsync(pain: 8);

        var row = StoredRow();
        row.Pain.ShouldBe((short)8, "the field the user supplied is updated");
        row.NotesEnc.ShouldNotBeNull("the note the full form wrote must survive a quick check-in");
        (await _harness.Crypto.DecryptStringAsync(row.NotesEnc!)).ShouldBe("cólicos leves");
        row.Energy.ShouldBe((short)3);
        row.Libido.ShouldBe((short)1);
    }

    [Fact]
    public async Task An_omitted_field_is_left_unchanged_rather_than_cleared()
    {
        // The partial half of the contract, stated on its own: tapping only the mood chip must not
        // erase this morning's pain score. POST /cycle/day/{date} merges too (both write the same
        // multi-writer row); the endpoint that genuinely replaces its row is POST /cycle/events.
        await CheckinAsync(pain: 6, mood: CycleDayLog.MoodScale.Low);

        var result = await CheckinAsync(mood: CycleDayLog.MoodScale.Bright);

        var checkin = result.ShouldBeOfType<QuickCheckinResult.Saved>().Checkin;
        checkin.Pain.ShouldBe(6);
        checkin.Mood.ShouldBe(CycleDayLog.MoodScale.Bright);
        StoredRow().Pain.ShouldBe((short)6);
    }

    // --- D-12: the day is the USER's day, never a re-derived UTC date -----------------------------

    [Fact]
    public async Task The_day_is_the_user_local_day_for_a_Pacific_Auckland_user()
    {
        // 2026-08-06 20:00Z is already 2026-08-07 in Auckland (UTC+12). A check-in with no date in
        // the payload must land on the user's day — writing the UTC date here would file every
        // evening check-in of every NZ user under the previous day, forever.
        var nowUtc = new DateTimeOffset(2026, 8, 6, 20, 0, 0, TimeSpan.Zero);
        var aucklandToday = new DateOnly(2026, 8, 7);
        var info = new UserDayInfo(_harness.UserId, aucklandToday, CycleTestHarness.Floor, "Pacific/Auckland", nowUtc);

        var result = await CheckinAsync(pain: 5, info: info);

        result.ShouldBeOfType<QuickCheckinResult.Saved>().Checkin.Day.ShouldBe(aucklandToday);
        var row = StoredRow();
        row.Day.ShouldBe(aucklandToday);
        row.Day.ShouldNotBe(DateOnly.FromDateTime(nowUtc.UtcDateTime));
    }

    [Fact]
    public async Task A_checkin_writes_todays_row_and_leaves_yesterdays_alone()
    {
        var yesterday = _harness.SeedDayLog(CycleTestHarness.Today.AddDays(-1), pain: 1);

        await CheckinAsync(pain: 9);

        _harness.NewContext().CycleDayLogs.Single(l => l.Id == yesterday.Id).Pain.ShouldBe((short)1);
        _harness.NewContext().CycleDayLogs.Single(l => l.Day == CycleTestHarness.Today).Pain.ShouldBe((short)9);
    }

    [Fact]
    public async Task Another_users_row_on_the_same_day_is_untouched()
    {
        var theirs = _harness.SeedDayLog(CycleTestHarness.Today, userId: _harness.OtherUserId, pain: 1);

        await CheckinAsync(pain: 9);

        _harness.NewContext().CycleDayLogs.Single(l => l.Id == theirs.Id).Pain.ShouldBe((short)1);
    }

    // --- the erased-user fence ---------------------------------------------------------------------

    [Fact]
    public async Task A_crypto_shredded_user_cannot_check_in()
    {
        var result = await _harness.NewDayService(null)
            .QuickCheckinAsync(new QuickCheckinRequest(5, null), CancellationToken.None);

        result.ShouldBeOfType<QuickCheckinResult.UserNotFound>();
        AllDayLogCount().ShouldBe(0);
    }

    [Fact]
    public async Task A_crypto_shredded_user_is_rejected_before_validation()
    {
        var result = await _harness.NewDayService(null)
            .QuickCheckinAsync(new QuickCheckinRequest(null, null), CancellationToken.None);

        result.ShouldBeOfType<QuickCheckinResult.UserNotFound>();
    }

    // --- frozen wire strings -----------------------------------------------------------------------

    [Fact]
    public void The_quick_checkin_validation_message_is_frozen()
    {
        // §G12: pinned against the literal, not only through the constant. The Flutter client renders
        // this sentence verbatim on the app's most-tapped sheet.
        SymptomValidationMessages.QuickCheckinEmpty.ShouldBe("at least one of pain or mood is required");
    }
}
