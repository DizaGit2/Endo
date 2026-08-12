using Lumen.Api.Cycle;
using Lumen.Api.CycleSettings;
using Lumen.Api.Devices;
using Lumen.Api.Onboarding;
using Lumen.Api.Persistence;
using Lumen.Api.Symptoms;
using Lumen.Domain.Entities;
using Lumen.Domain.Reference;
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
/// <para><b>What is in scope here, stated as a RULE rather than as a list.</b> Two earlier attempts to
/// enumerate the call sites went stale within one task each — the count in
/// <see cref="ConcurrencyRetry"/>'s own remarks first, then a naming of "the one <c>Clear()</c> these
/// tests do not pin" that was simply false by the time it was read, because
/// <c>CycleSettingsService.UpdateAsync</c> had shipped with an unpinned one and nothing said so. So:
/// <b>every <see cref="ConcurrencyRetry"/> action that can stage an INSERT owes this file a test, and
/// the obligation is discharged by the test, never by the inventory.</b> The way to check the file is
/// current is to delete a <c>db.ChangeTracker.Clear()</c> and watch a test named after that write
/// fail — not to count entries in a paragraph.</para>
///
/// <para><b>The one exemption, and it is a property of the code.</b>
/// <c>CycleService.DeleteEventAsync</c> stages an UPDATE and never an INSERT, and changes no unique
/// key: its retry can never fire, and if it somehow did, the re-query would return the same
/// already-modified tracked instance and save identically with or without the clear. There is no
/// behaviour to assert, so no test is written rather than a vacuous one. The <c>Clear()</c> is kept for
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

    // --- POST /me/devices (T15) -----------------------------------------------------------------

    [Fact]
    public async Task A_lost_race_on_a_device_registration_recovers_onto_the_winners_row()
    {
        // The single most race-prone write in P4a: the client calls this on every push-token refresh
        // for the life of the install, and two app processes waking together (a notification tap while
        // the app cold-starts) both miss the (UserId, PushToken) lookup and both insert. The loser gets
        // 23505 on a unique index the user cannot see and has no way to work around.
        const string PushToken = "fcm-token-raced-0000000000000000";

        UserDevice? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
            winner = _harness.SeedDevice(PushToken, platform: UserDevice.Platforms.Ios));

        var result = await _harness.NewDeviceRegistrationService(_harness.DayInfo(), interceptor)
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Android, PushToken), CancellationToken.None);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var device = result.ShouldBeOfType<DeviceRegistrationResult.Saved>().Device;
        device.DeviceId.ShouldBe(winner!.Id, "the response must describe the row that actually exists");
        device.Platform.ShouldBe("android", "the second attempt applied this request to the winner's row");

        var rows = _harness.NewContext().UserDevices
            .Where(d => d.UserId == _harness.UserId).ToList();
        rows.Count.ShouldBe(1, "the loser's staged insert must not reach the database");
        rows[0].LastSeenAt.ShouldBe(CycleTestHarness.Now);
    }

    // --- POST /onboarding/goals, /hormones, /notifications (T17 review fix) ---------------------
    //
    // T17 shipped three more ConcurrencyRetry actions — the full-replace preference steps — and its
    // review found none of their db.ChangeTracker.Clear() lines pinned: the suite stayed green with
    // all three deleted. The shape here is the same double-tap that motivates every test above,
    // transposed onto a full-replace batch: two copies of the same "Continue" tap both miss the
    // (UserId, <Code>) lookup for a given code because neither row exists yet, one commits, the
    // other's retry must apply ITS OWN request onto the row that won — not re-attempt its own insert
    // — for every code in the vocabulary, not just the one that collided.

    [Fact]
    public async Task A_lost_race_on_the_goals_step_recovers_onto_the_winners_row()
    {
        // The winner seeds ONE row (manage_symptoms, selected). This request's own answer omits that
        // code, so recovery must DESELECT the winner's row rather than leave it alone or duplicate it
        // — full replace applies to every code, including the one that raced.
        UserGoal? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
            winner = _harness.SeedGoal(UserGoal.Codes.ManageSymptoms, selected: true));

        var result = await _harness.NewOnboardingStepsService(_harness.DayInfo(), interceptor).SaveGoalsAsync(
            new SaveGoalsRequest([UserGoal.Codes.PlanFertility, UserGoal.Codes.JustCurious]),
            CancellationToken.None);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var saved = result.ShouldBeOfType<SaveGoalsResult.Saved>().Goals.Goals;
        saved.Single(g => g.Code == UserGoal.Codes.ManageSymptoms).Selected.ShouldBeFalse(
            "the second attempt applied THIS request onto the winner's row, deselecting it");
        saved.Where(g => g.Selected).Select(g => g.Code).ShouldBe(
            [UserGoal.Codes.PlanFertility, UserGoal.Codes.JustCurious], Case.Sensitive);

        var rows = _harness.NewContext().UserGoals.Where(g => g.UserId == _harness.UserId).ToList();
        rows.Count.ShouldBe(5, "the loser's staged insert must not reach the database as a duplicate row");
        rows.Single(r => r.GoalCode == UserGoal.Codes.ManageSymptoms).Id.ShouldBe(winner!.Id);
    }

    [Fact]
    public async Task A_lost_race_on_the_hormones_step_recovers_onto_the_winners_row()
    {
        UserHormonePref? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
            winner = _harness.SeedHormonePref(HormoneCatalog.Codes.Estradiol, charted: true));

        var result = await _harness.NewOnboardingStepsService(_harness.DayInfo(), interceptor)
            .SaveHormonePrefsAsync(
                new SaveHormonePrefsRequest([HormoneCatalog.Codes.Lh, HormoneCatalog.Codes.Fsh]),
                CancellationToken.None);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var saved = result.ShouldBeOfType<SaveHormonePrefsResult.Saved>().Hormones.Hormones;
        saved.Single(h => h.Code == HormoneCatalog.Codes.Estradiol).Charted.ShouldBeFalse(
            "the second attempt applied THIS request onto the winner's row, un-charting it");
        saved.Where(h => h.Charted).Select(h => h.Code).ShouldBe(
            [HormoneCatalog.Codes.Lh, HormoneCatalog.Codes.Fsh], Case.Sensitive);

        var rows = _harness.NewContext().UserHormonePrefs.Where(p => p.UserId == _harness.UserId).ToList();
        rows.Count.ShouldBe(7, "the loser's staged insert must not reach the database as a duplicate row");
        rows.Single(r => r.HormoneCode == HormoneCatalog.Codes.Estradiol).Id.ShouldBe(winner!.Id);
    }

    [Fact]
    public async Task A_lost_race_on_the_notifications_step_recovers_onto_the_winners_row_with_its_composed_device()
    {
        // This is T17's COMPOSING action (§G12): the retried closure stages the four preference rows
        // AND, in the same unit of work, the device row behind a push token. A token is included here
        // so the recovery is proven on the full shape, not a slice of it — a Clear() bug here would
        // discard a real device registration alongside the preference rows.
        const string PushToken = "fcm-token-onboarding-raced-00000000000";

        UserNotificationPref? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() => winner = _harness.SeedNotificationPref(
            HormoneCatalog.NotificationCategories.DailyCheckin, enabled: true));

        var result = await _harness.NewOnboardingStepsService(_harness.DayInfo(), interceptor)
            .SaveNotificationPrefsAsync(
                new SaveNotificationPrefsRequest(
                    [HormoneCatalog.NotificationCategories.PeriodPrediction], PushToken, UserDevice.Platforms.Ios),
                CancellationToken.None);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var saved = result.ShouldBeOfType<SaveNotificationPrefsResult.Saved>().Notifications;
        saved.DeviceRegistered.ShouldBeTrue();
        saved.Categories.Single(c => c.Code == HormoneCatalog.NotificationCategories.DailyCheckin).Enabled
            .ShouldBeFalse("the second attempt applied THIS request onto the winner's row, disabling it");
        saved.Categories.Where(c => c.Enabled).Select(c => c.Code).ShouldBe(
            [HormoneCatalog.NotificationCategories.PeriodPrediction], Case.Sensitive);

        using var db = _harness.NewContext();
        var rows = db.UserNotificationPrefs.Where(p => p.UserId == _harness.UserId).ToList();
        rows.Count.ShouldBe(4, "the loser's staged insert must not reach the database as a duplicate row");
        rows.Single(r => r.CategoryCode == HormoneCatalog.NotificationCategories.DailyCheckin).Id
            .ShouldBe(winner!.Id);
        db.UserDevices.Count(d => d.UserId == _harness.UserId).ShouldBe(
            1, "the composed device write survives the retry alongside the preference rows");
    }

    // --- POST /onboarding/baseline (T16, pinned in T18) -----------------------------------------
    //
    // T16 shipped `SaveBaselineAsync`'s ConcurrencyRetry action with a db.ChangeTracker.Clear() and
    // pinned only its NON-composability — a different claim, about what a CALLER may do. Nothing
    // failed when the Clear() itself was deleted, so the recovery was documented rather than proven.
    // The shape below is the one that motivates it: a double-tapped "Continue" on screen 4, where
    // `user_profile_enc`'s primary key is the contended key on a first save.

    [Fact]
    public async Task A_lost_race_on_the_baseline_step_recovers_onto_the_winners_row()
    {
        // The winner commits a profile carrying a HEIGHT. This request supplies only a DOB, so recovery
        // must MERGE onto the winner's row — the baseline step's null-means-unchanged rule applied to a
        // row this request has never seen. Re-attempting its own insert would be a PK violation instead.
        var winnerHeight = await _harness.Crypto.EncryptStringAsync(UserProfileEnc.EncodeHeightCm(171));

        UserProfileEnc? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
            winner = _harness.SeedProfile(heightCmEnc: winnerHeight));

        var dob = new DateOnly(1994, 3, 17);
        var result = await _harness.NewOnboardingStepsService(_harness.DayInfo(), interceptor)
            .SaveBaselineAsync(new SaveBaselineRequest(dob, null, null, null, null, null), default);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var baseline = result.ShouldBeOfType<SaveBaselineResult.Saved>().Baseline;
        baseline.Dob.ShouldBe(dob);
        baseline.HeightCm.ShouldBe(
            171, "the second attempt merged onto the WINNER's row, so its height survived");

        using var db = _harness.NewContext();
        var rows = db.UserProfiles.Where(p => p.UserId == _harness.UserId).ToList();
        rows.Count.ShouldBe(1, "the loser's staged insert must not reach the database");
        rows[0].CreatedAt.ShouldBe(winner!.CreatedAt, "the winner's row was updated, not replaced");
    }

    // --- POST /onboarding/cycle (T18) -----------------------------------------------------------

    [Fact]
    public async Task A_lost_race_on_the_onboarding_cycle_step_recovers_onto_the_winners_row()
    {
        // T18's retried action is the phase's most composed one: it stages the seeded `cycle_events`
        // row AND T14's `user_cycle_settings` row, then saves once. Both are inserts on a first run, so
        // a lost race leaves TWO orphaned Added entries — and recovery has to discard both, not one.
        var anchor = CycleTestHarness.Today.AddDays(-9);

        CycleEvent? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
        {
            winner = _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, anchor, flow: 2);
            _harness.SeedCycleSettings(avgCycleLengthDays: 26);
        });

        var result = await _harness.NewOnboardingStepsService(_harness.DayInfo(), interceptor)
            .SaveCycleAsync(new SaveOnboardingCycleRequest(anchor, 31, null, null), default);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var saved = result.ShouldBeOfType<SaveOnboardingCycleResult.Saved>().Cycle;
        saved.LastPeriodStart.ShouldBe(anchor);
        saved.AvgCycleLengthDays.ShouldBe(31, "the second attempt applied THIS request onto the winner's row");

        using var db = _harness.NewContext();
        var events = db.CycleEvents.IgnoreQueryFilters().Where(e => e.UserId == _harness.UserId).ToList();
        events.Count.ShouldBe(1, "the loser's staged event insert must not reach the database");
        events[0].Id.ShouldBe(winner!.Id, "the winner's row was adopted, keeping its provenance");
        events[0].Source.ShouldBe(CycleEvent.Sources.User);
        events[0].FlowIntensity.ShouldBe((short)2, "onboarding never asks for flow, so it clears none");

        var settings = db.CycleSettings.Where(s => s.UserId == _harness.UserId).ToList();
        settings.Count.ShouldBe(1, "the loser's staged settings insert must not reach the database either");
        settings[0].AvgCycleLengthDays.ShouldBe((short)31);
    }

    // --- PATCH /settings/cycle (T14) ------------------------------------------------------------
    //
    // The 12th ConcurrencyRetry call site, and the one whose Clear() shipped unpinned: the whole unit
    // suite stayed green — 1003 passed, 0 failed — with `CycleSettingsService.cs`'s
    // `db.ChangeTracker.Clear()` deleted.
    //
    // `UpdateAsync` stages TWO different inserts, they fail for two different reasons, and one test
    // could not honestly claim both — so there are two, each arranged so that the OTHER insert cannot
    // occur:
    //
    //   * `db.CycleSettings.Add` on a first save. The worst instance in the phase, because
    //     `user_cycle_settings`'s PRIMARY KEY *is* `UserId`: the loser's orphaned Added entity carries
    //     the winner's exact key, so identity resolution hands the second attempt its own dead insert
    //     back INSTEAD of the committed row, and the re-save is a key violation.
    //   * `db.CycleTrackingPauseSpans.Add` on a first pause. Identity resolution cannot help here at
    //     all: `ReconcilePauseAsync` looks the open span up in SQL, does not see the still-unsaved
    //     staged row, and adds a SECOND one — which the partial unique index
    //     `(UserId) WHERE "EndedOn" IS NULL` rejects.
    //
    // Either way the escaping `DbUpdateException` is not a 23505-shaped Npgsql one, so `ConcurrencyRetry`
    // correctly declines to retry it and it leaves the service as the 500 the retry exists to prevent.

    [Fact]
    public async Task A_lost_race_on_the_cycle_settings_update_recovers_onto_the_winners_row()
    {
        // Screen 32's "average cycle length" field, saved twice by a user who has never opened the
        // settings screen before: neither copy finds a `user_cycle_settings` row and both insert.
        // Nothing here pauses, so the settings insert is the ONLY staged insert in the action.
        UserCycleSettings? winner = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() =>
            winner = _harness.SeedCycleSettings(avgCycleLengthDays: 26, regularity: UserCycleSettings.RegularityValues.Irregular));

        // Constructed directly: CycleTestHarness.NewCycleSettingsService takes no interceptor.
        var service = new CycleSettingsService(
            _harness.NewContext(interceptor), new StubUserDayContext(_harness.DayInfo()));

        var result = await service.UpdateAsync(
            new UpdateCycleSettingsRequest(AvgCycleLengthDays: 31), CancellationToken.None);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var saved = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        saved.AvgCycleLengthDays.ShouldBe(31, "the second attempt applied THIS request onto the winner's row");
        saved.Regularity.ShouldBe(
            UserCycleSettings.RegularityValues.Irregular,
            "merge semantics: the winner's untouched field survived rather than reverting to a default");

        using var db = _harness.NewContext();
        var rows = db.CycleSettings.Where(s => s.UserId == _harness.UserId).ToList();
        rows.Count.ShouldBe(1, "the loser's staged insert must not reach the database");
        rows[0].CreatedAt.ShouldBe(winner!.CreatedAt, "the winner's row was updated, not replaced");
        rows[0].AvgCycleLengthDays.ShouldBe((short)31);
    }

    [Fact]
    public async Task A_lost_race_on_the_first_pause_recovers_onto_the_winners_open_span()
    {
        // The second insert, isolated: the settings row already exists and is unpaused, so the retried
        // action stages NO settings insert and the only Added entity is the pause span. The shape is a
        // double-tapped "pause tracking" switch — the one the partial unique index would otherwise turn
        // into an error page.
        _harness.SeedCycleSettings();

        CycleTrackingPauseSpan? winnerSpan = null;
        var interceptor = new LostRaceOnFirstSaveInterceptor(() => winnerSpan = _harness.SeedPauseSpan(
            UserCycleSettings.PauseReasons.Pregnancy, CycleTestHarness.Today));

        var service = new CycleSettingsService(
            _harness.NewContext(interceptor), new StubUserDayContext(_harness.DayInfo()));

        var result = await service.UpdateAsync(
            new UpdateCycleSettingsRequest(
                TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Surgical),
            CancellationToken.None);

        interceptor.Saves.ShouldBe(2, "one failed save, one that recovered");
        var saved = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        saved.TrackingPaused.ShouldBeTrue();
        saved.PauseReason.ShouldBe(UserCycleSettings.PauseReasons.Surgical);

        using var db = _harness.NewContext();
        var spans = db.CycleTrackingPauseSpans.Where(s => s.UserId == _harness.UserId).ToList();
        spans.Count.ShouldBe(
            1, "the loser's staged span insert must not reach the database — a second OPEN span "
            + "violates the partial unique index and surfaces as a 500");
        spans[0].Id.ShouldBe(winnerSpan!.Id, "the winner's open span was updated in place");
        spans[0].Reason.ShouldBe(
            UserCycleSettings.PauseReasons.Surgical,
            "the second attempt applied THIS request's reason onto the winner's span");
        spans[0].EndedOn.ShouldBeNull();

        db.CycleSettings.Count(s => s.UserId == _harness.UserId).ShouldBe(1);
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
