using Lumen.Api.Cycle;
using Lumen.Api.Persistence;
using Lumen.Api.Symptoms;
using Lumen.Domain.Entities;
using Lumen.UnitTests.Cycle;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Npgsql;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Api;

/// <summary>
/// The other half of <see cref="ConcurrencyRetry"/>, and the half <c>ConcurrencyRetryTests</c>
/// deliberately cannot reach: not <b>whether</b> a lost race is retried, but whether the retry
/// actually <b>RECOVERS</b>.
///
/// <para><b>Why this file exists.</b> <c>ConcurrencyRetryTests</c> proves the helper's POLICY — one
/// retry on <c>23505</c>, nothing else, ever — against a fake delegate. It says nothing about the
/// service actions the helper wraps, because a fake has no change tracker. The recovery mechanism
/// lives on the caller's side: a failed <c>SaveChanges</c> leaves the losing INSERT staged in
/// <see cref="Microsoft.EntityFrameworkCore.ChangeTracking.ChangeTracker"/>, so a second attempt that
/// only re-queried would re-stage that same insert and fail identically. Every retried action
/// therefore begins with <c>db.ChangeTracker.Clear()</c>. Deleting that one line breaks recovery and
/// changes <b>no other observable behaviour</b> — which is exactly why it needs a test that fails
/// when it is gone, rather than tests that merely execute it.</para>
///
/// <para><b>How the race is staged without a race.</b> A genuine interleaving of two requests between
/// the same two statements is not something a test can arrange deterministically — which is the very
/// reason the retry was extracted behind a delegate in the first place.
/// <see cref="LostRaceOnFirstSaveInterceptor"/> replaces the timing with a script: on the <i>first</i>
/// <c>SaveChanges</c> of the action it inserts the winner's row out of band (through a separate
/// context on the same connection, so the row is genuinely in the database and the real unique index
/// is genuinely occupied) and then throws precisely the exception Npgsql raises for a duplicate key —
/// a <see cref="DbUpdateException"/> wrapping <see cref="PostgresException"/> with
/// <c>SqlState = 23505</c>. EF does not touch the change tracker on a failed save, so the loser's
/// insert is left staged in exactly the state a real lost race leaves it in. From there everything is
/// the production path: <see cref="ConcurrencyRetry"/> catches, the action runs a second time for
/// real, and the assertions below say what the user must get.</para>
///
/// <para><b>What a failure looks like.</b> With the <c>Clear()</c> removed, the second attempt finds
/// the winner's row (identity resolution matches on the primary key, and the loser's is a different
/// Guid) and merges onto it correctly — but the orphaned Added entry is still queued, so
/// <c>SaveChanges</c> emits an INSERT alongside the UPDATE and Sqlite's unique index rejects it. The
/// resulting <c>DbUpdateException</c> has a Sqlite inner exception, so it is deliberately NOT retried
/// (a foreign provider's error must never be retried on a guess) and it propagates out of the service
/// as the 500 the retry existed to prevent.</para>
///
/// <para><b>The one <c>Clear()</c> these tests do not pin</b> is
/// <c>CycleService.DeleteEventAsync</c>'s, and that is a statement about the code, not a gap here. A
/// soft delete stages an UPDATE, never an INSERT, and changes no unique key: its retry can never
/// fire, and if it somehow did, the re-query would return the same already-modified tracked instance
/// and save identically with or without the clear. There is no behaviour to assert. It is kept for
/// uniformity — every write on that service going through one shape — and its remarks say so.</para>
/// </summary>
public sealed class ConcurrencyRecoveryTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    // --- POST /cycle/day/{date} -----------------------------------------------------------------

    [Fact]
    public async Task A_lost_race_on_the_day_upsert_recovers_onto_the_winners_row()
    {
        // The shape this protects: the phone re-sends a day-log post the user thinks timed out, and
        // both copies miss the (UserId, Day) lookup. Recovery means the retry merges onto whichever
        // row committed — not that it tries its own insert again.
        CycleDayLog? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
            winner = _harness.SeedDayLog(CycleTestHarness.Today, mood: CycleDayLog.MoodScale.Steady));

        var result = await _harness.NewDayService(_harness.DayInfo(), interceptor).UpsertDayAsync(
            CycleTestHarness.Today,
            new LogCycleDayRequest(7, null, null),
            CancellationToken.None);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var log = result.ShouldBeOfType<CycleDayResult.Saved>().Log;
        log.Pain.ShouldBe(7);
        log.Mood.ShouldBe(
            CycleDayLog.MoodScale.Steady,
            "the second attempt merged onto the WINNER's row, so its mood survived");

        var rows = AllDayLogs();
        rows.Count.ShouldBe(1, "the loser's staged insert must not reach the database");
        rows[0].Id.ShouldBe(winner!.Id);
        rows[0].Pain.ShouldBe((short)7);
    }

    [Fact]
    public async Task A_lost_race_on_the_quick_checkin_recovers_onto_the_winners_row()
    {
        // The app's most-tapped write, and the one most likely to be double-submitted: screen 9's
        // sheet under a shaky connection. Same row, same mechanism, asserted on its own path because
        // it is the path a user actually double-taps.
        CycleDayLog? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
            winner = _harness.SeedDayLog(CycleTestHarness.Today, pain: 2));

        var result = await _harness.NewDayService(_harness.DayInfo(), interceptor)
            .QuickCheckinAsync(new QuickCheckinRequest(null, CycleDayLog.MoodScale.Bright), CancellationToken.None);

        interceptor.Saves.ShouldBe(2);
        var checkin = result.ShouldBeOfType<QuickCheckinResult.Saved>().Checkin;
        checkin.Mood.ShouldBe(CycleDayLog.MoodScale.Bright);
        checkin.Pain.ShouldBe(2, "merged onto the winner's row, which already carried a pain score");

        var rows = AllDayLogs();
        rows.Count.ShouldBe(1);
        rows[0].Id.ShouldBe(winner!.Id);
    }

    // --- POST /cycle/events (the T9 retrofit) ---------------------------------------------------

    [Fact]
    public async Task A_lost_race_on_a_cycle_event_recovers_onto_the_winners_row()
    {
        CycleEvent? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
            winner = _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today, flow: 1));

        var result = await _harness.NewService(_harness.DayInfo(), interceptor).LogEventAsync(
            new LogCycleEventRequest(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today, 3, null),
            CancellationToken.None);

        interceptor.Saves.ShouldBe(2);
        var saved = result.ShouldBeOfType<CycleEventResult.Saved>().Event;
        saved.Id.ShouldBe(winner!.Id, "the response must describe the row that actually exists");
        saved.FlowIntensity.ShouldBe(3);

        var rows = _harness.NewContext().CycleEvents.IgnoreQueryFilters()
            .Where(e => e.UserId == _harness.UserId).ToList();
        rows.Count.ShouldBe(1, "the loser's staged insert must not reach the database");
        rows[0].FlowIntensity.ShouldBe((short)3);
    }

    // --- POST /cycle/phase-override (the T9 retrofit) -------------------------------------------

    [Fact]
    public async Task A_lost_race_on_a_phase_override_save_recovers_onto_the_winners_row()
    {
        var cycleStart = CycleTestHarness.Today.AddDays(-20);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, cycleStart);
        var corrected = cycleStart.AddDays(5);

        CyclePhaseOverride? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() => winner = _harness.SeedOverride(
            cycleStart,
            CyclePhaseOverride.Phases.Menstrual,
            CyclePhaseOverride.Boundaries.End,
            cycleStart.AddDays(2)));

        var result = await _harness.NewService(_harness.DayInfo(), interceptor).SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(
                cycleStart,
                [new PhaseOverrideInput(
                    CyclePhaseOverride.Phases.Menstrual, CyclePhaseOverride.Boundaries.End, corrected)]),
            CancellationToken.None);

        interceptor.Saves.ShouldBe(2);
        result.ShouldBeOfType<PhaseOverrideResult.Saved>();

        var rows = _harness.NewContext().CyclePhaseOverrides.IgnoreQueryFilters()
            .Where(o => o.UserId == _harness.UserId).ToList();
        rows.Count.ShouldBe(1, "the loser's staged insert must not reach the database");
        rows[0].Id.ShouldBe(winner!.Id);
        rows[0].OccurredOn.ShouldBe(corrected, "the second attempt applied the correction to the winner's row");
    }

    private List<CycleDayLog> AllDayLogs() =>
        _harness.NewContext().CycleDayLogs.IgnoreQueryFilters()
            .Where(l => l.UserId == _harness.UserId).ToList();
}

/// <summary>
/// Turns the first <c>SaveChanges</c> of a retried action into a lost unique-key race, on a schedule
/// instead of on timing.
/// </summary>
/// <param name="seedWinner">
/// Inserts the row the other writer "won" with. Called from inside the interception, i.e. after the
/// action has already staged its own insert and before that insert is attempted — the only window in
/// which the race is real. It must write through a separate context so the row is committed
/// independently of the one about to fail.
/// </param>
/// <remarks>
/// <see cref="SavingChangesAsync"/> runs before EF has opened a transaction or touched the change
/// tracker, so throwing here reproduces a failed save faithfully: nothing is accepted, and every
/// staged entry stays exactly where it was. The exception is built to the shape
/// <see cref="ConcurrencyRetry"/> matches on — a <see cref="DbUpdateException"/> whose inner is a
/// <see cref="PostgresException"/> with <c>SqlState = 23505</c> — because a Sqlite unique violation is
/// deliberately not retried, and the point here is to exercise the production retry path rather than
/// to invent a second one.
/// </remarks>
internal sealed class LostRaceOnFirstSaveInterceptor(Action seedWinner) : SaveChangesInterceptor
{
    /// <summary>How many times the action reached <c>SaveChanges</c>. Exactly 2 means "retried once".</summary>
    public int Saves { get; private set; }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        Saves++;

        if (Saves == 1)
        {
            seedWinner();
            throw new DbUpdateException(
                "An error occurred while saving the entity changes.",
                new PostgresException(
                    "duplicate key value violates unique constraint",
                    "ERROR",
                    "ERROR",
                    ConcurrencyRetry.UniqueViolationSqlState));
        }

        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }
}
