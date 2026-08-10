using Lumen.Api.Cycle;
using Lumen.Api.CycleSettings;
using Lumen.Api.Devices;
using Lumen.Api.Onboarding;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Lumen.Domain.Reference;
using Lumen.UnitTests.Cycle;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Onboarding;

/// <summary>
/// Unit tests for T18 — the three endpoints that close the D-02 state machine:
/// <c>POST /onboarding/cycle</c> (B15), <c>POST /onboarding/complete</c> and
/// <c>GET /onboarding/state</c>.
///
/// <para>Six claims dominate this file.</para>
///
/// <para><b>1. The cycle step is a COMPOSED unit of work (§G12).</b> It writes
/// <c>user_cycle_settings</c> through T14's stage-only <c>ApplyOnboardingCycleAsync</c> <i>and</i>
/// upserts the seeded <c>cycle_events.period_start</c> row, in exactly ONE
/// <see cref="Api.Persistence.ConcurrencyRetry"/> action and exactly ONE save. Calling
/// <c>CycleService.LogEventAsync</c> instead would clear the whole change tracker and discard the
/// staged settings row with no exception and no failing test — which is why the save count, not the
/// row counts alone, is asserted.</para>
///
/// <para><b>2. The T5 merge rule on the seeded <c>period_start</c>.</b> <c>cycle_events</c> is under
/// §G9's UNFILTERED unique index on <c>(UserId, Kind, OccurredOn)</c>, so a re-post must MOVE the
/// single <c>Source=onboarding</c> row, ADOPT a live row that already holds the target day (preserving
/// its <c>Source</c> and <c>CreatedAt</c>), or REVIVE a tombstone on it. A blind insert is a 23505
/// surfacing as a 500.</para>
///
/// <para><b>3. §G8 — this is the SECOND and LAST floored write.</b> <c>lastPeriodStart</c> is capped by
/// the user's local today and floored at <c>BackdateFloor</c>. No other P4a write may read that floor;
/// <see cref="Architecture.BackdateFloorAndCompletionStampTests"/> pins the count.</para>
///
/// <para><b>4. §G7 — the self-reports are never clinically validated.</b>
/// <c>avgCycleLengthDays = 47</c> and <c>avgPeriodLengthDays = 12</c> are stored and answered
/// <b>unwarned</b>: both sit inside the sanity band, and the clinical band that would refuse them has
/// no home in <c>backend/src</c> this phase.</para>
///
/// <para><b>5. Completion is stamped EXACTLY ONCE, and the backfill rides the same transaction.</b> The
/// stamp is a guarded claim (<c>WHERE OnboardingCompletedAt IS NULL</c>, the <c>CryptoShredJob</c>
/// idiom), so a second caller reports the winner's timestamp instead of overwriting it; and the four
/// default sets land in the same transaction, so <c>GET /me</c> can never report <c>true</c> while the
/// defaults are missing.</para>
///
/// <para><b>6. The seed comes from the ENTITY CONSTANTS, and the read projections are consumed rather
/// than re-derived.</b> T17 gives "a skipped step" its meaning on the read side; T18 materialises the
/// same seed at completion. The two are only coherent because neither restates the other's literals —
/// <see cref="The_backfill_and_the_read_projections_cannot_disagree"/> is the test that says so.</para>
/// </summary>
public sealed class OnboardingCompletionTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    // ---------------------------------------------------------------- shorthand

    private static IReadOnlyList<OnboardingFieldError> ErrorsOf(SaveOnboardingCycleResult result) =>
        result.ShouldBeOfType<SaveOnboardingCycleResult.Invalid>().Errors;

    private static string MessageFor(IReadOnlyList<OnboardingFieldError> errors, string field) =>
        errors.Single(e => string.Equals(e.Field, field, StringComparison.Ordinal)).Message;

    private static OnboardingCycleResponse SavedOf(SaveOnboardingCycleResult result) =>
        result.ShouldBeOfType<SaveOnboardingCycleResult.Saved>().Cycle;

    private static OnboardingCompleteResponse CompletedOf(CompleteOnboardingResult result) =>
        result.ShouldBeOfType<CompleteOnboardingResult.Completed>().Completion;

    private static OnboardingStateResponse StateOf(OnboardingStateResult result) =>
        result.ShouldBeOfType<OnboardingStateResult.Found>().State;

    private static SaveOnboardingCycleRequest Cycle(
        DateOnly? lastPeriodStart,
        int? avgCycleLengthDays = null,
        int? avgPeriodLengthDays = null,
        string? regularity = null) =>
        new(lastPeriodStart, avgCycleLengthDays, avgPeriodLengthDays, regularity);

    /// <summary>Every live <c>period_start</c> row for the harness's primary user, oldest first.</summary>
    private List<CycleEvent> LivePeriodStarts() =>
        [.. _harness.NewContext().CycleEvents
            .Where(e => e.UserId == _harness.UserId && e.Kind == CycleEvent.Kinds.PeriodStart)
            .OrderBy(e => e.OccurredOn)];

    /// <summary>Every <c>period_start</c> row, tombstones included — the §G9 view of the unique key.</summary>
    private List<CycleEvent> AllPeriodStarts() =>
        [.. _harness.NewContext().CycleEvents.IgnoreQueryFilters()
            .Where(e => e.UserId == _harness.UserId && e.Kind == CycleEvent.Kinds.PeriodStart)
            .OrderBy(e => e.OccurredOn)];

    // ================================================================ the frozen wire strings (§G12)

    [Fact]
    public void The_completion_wire_strings_are_frozen()
    {
        // These reach the Flutter client through the OpenAPI contract and are rendered verbatim, so a
        // reword is a contract change, not a copy edit. Asserted against the literal, never against the
        // constant, or the test would move with the code it is meant to pin.
        OnboardingConflict.Title.ShouldBe("The request conflicts with the current onboarding state.");
        OnboardingConflict.IncompleteCode.ShouldBe("onboarding_incomplete");
        OnboardingConflict.IncompleteDetail
            .ShouldBe("Onboarding cannot be completed until every mandatory step is answered.");
        OnboardingConflict.AlreadyCompletedCode.ShouldBe("onboarding_already_completed");
        OnboardingConflict.AlreadyCompletedDetail
            .ShouldBe("Onboarding is already complete; the cycle anchor can no longer be moved here.");

        // The step code travels in `missingSteps` / `missingMandatorySteps`, so it is wire vocabulary too.
        OnboardingSteps.Cycle.ShouldBe("cycle");
        OnboardingSteps.Mandatory.ShouldBe(["cycle"], Case.Sensitive);

        // The shared messages this endpoint reuses rather than restating (T3/§G12).
        ValidationMessages.Required.ShouldBe("value is required");
        ValidationMessages.FutureDate.ShouldBe("date must not be in the future");
        ValidationMessages.BeforeFloor.ShouldBe("date is before the earliest allowed date");
        ValidationMessages.NotAllowedValue.ShouldBe("value is not one of the allowed values");
        ValidationMessages.Between(CycleSettingsStructuralDomain.Min, CycleSettingsStructuralDomain.Max)
            .ShouldBe("value must be between 1 and 32767");

        // The §G6 unavailability code is NOT restated by any T18 response: nothing here reports a phase.
        NotFoundProblem.Title.ShouldBe("The requested resource was not found.");
    }

    // ================================================================ POST /onboarding/cycle — validation

    [Fact]
    public async Task A_missing_or_default_lastPeriodStart_is_required()
    {
        // `default(DateOnly)` is 0001-01-01, which a client that binds an unset date field sends as a
        // real value. Reported as "required" rather than as a floor violation: the user did not type a
        // date in the year 1, they failed to answer the mandatory question.
        MessageFor(ErrorsOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(null), default)),
                "lastPeriodStart")
            .ShouldBe(ValidationMessages.Required);

        MessageFor(
                ErrorsOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(default(DateOnly)), default)),
                "lastPeriodStart")
            .ShouldBe(ValidationMessages.Required);

        await using var db = _harness.NewContext();
        (await db.CycleEvents.CountAsync()).ShouldBe(0, "validate-then-act: a rejected request wrote nothing");
        (await db.CycleSettings.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task Tomorrow_in_the_users_own_timezone_is_rejected_while_a_UTC_future_date_is_accepted()
    {
        // D-12: "today" is the USER's calendar day, never the server's. A Madrid user cannot log
        // tomorrow…
        var madrid = await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(1)), default);
        MessageFor(ErrorsOf(madrid), "lastPeriodStart").ShouldBe(ValidationMessages.FutureDate);

        // …while a Pacific/Kiritimati user (UTC+14) legitimately logs a day that is still in the future
        // by UTC. A cap computed from the server clock would reject the whole country for ten hours a day.
        var kiritimati = new UserDayInfo(
            _harness.UserId,
            Today: new DateOnly(2026, 8, 7),
            BackdateFloor: CycleTestHarness.Floor,
            TimezoneId: "Pacific/Kiritimati",
            NowUtc: new DateTimeOffset(2026, 8, 6, 22, 0, 0, TimeSpan.Zero));

        var saved = SavedOf(await _harness.NewOnboardingStepsService(kiritimati)
            .SaveCycleAsync(Cycle(new DateOnly(2026, 8, 7)), default));
        saved.LastPeriodStart.ShouldBe(new DateOnly(2026, 8, 7));
    }

    [Fact]
    public async Task The_backdate_floor_binds_this_write_and_the_floor_day_itself_is_accepted()
    {
        // §G8: `POST /cycle/events` and this endpoint are the ONLY two floored writes in the phase.
        // The floor is inclusive — an account created exactly two years ago must still be able to seed
        // the oldest day D-13 permits.
        var below = await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Floor.AddDays(-1)), default);
        MessageFor(ErrorsOf(below), "lastPeriodStart").ShouldBe(ValidationMessages.BeforeFloor);

        var atFloor = await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Floor), default);
        SavedOf(atFloor).LastPeriodStart.ShouldBe(CycleTestHarness.Floor);

        LivePeriodStarts().Count.ShouldBe(1, "only the accepted request wrote a row");
    }

    [Fact]
    public async Task Omitted_fields_resolve_to_the_T6_defaults_and_nothing_else()
    {
        // Screen 3 collects a cycle length but never a period length, so the one that is not asked stays
        // NULL rather than being invented. The two defaults come off the entity, never retyped here.
        var anchor = CycleTestHarness.Today.AddDays(-5);
        var saved = SavedOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(anchor), default));

        saved.AvgCycleLengthDays.ShouldBe(UserCycleSettings.DefaultAvgCycleLengthDays);
        saved.AvgCycleLengthDays.ShouldBe(28, "the T6 default, stated once here so a silent change fails");
        saved.AvgPeriodLengthDays.ShouldBeNull("onboarding never asks for it — a seeded value would be a lie");
        saved.Regularity.ShouldBe(UserCycleSettings.RegularityValues.Default);
        saved.Regularity.ShouldBe("somewhat");
        saved.Warnings.ShouldBeEmpty();

        await using var db = _harness.NewContext();
        var row = await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId);
        row.AvgCycleLengthDays.ShouldBe((short)28);
        row.AvgPeriodLengthDays.ShouldBeNull();
        row.Regularity.ShouldBe("somewhat");
        row.TrackingPaused.ShouldBeFalse("onboarding never opens, closes or clears a pause");
        (await db.CycleTrackingPauseSpans.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task An_unratified_regularity_is_rejected()
    {
        // "sometimes" is the plausible misspelling of the ratified `somewhat`; matching is Ordinal, so a
        // near-miss is a 400 rather than silently stored data P6 cannot read.
        var result = await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today, regularity: "sometimes"), default);

        MessageFor(ErrorsOf(result), "regularity").ShouldBe(ValidationMessages.NotAllowedValue);

        await using var db = _harness.NewContext();
        (await db.CycleSettings.CountAsync()).ShouldBe(0);
        (await db.CycleEvents.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task A_self_report_the_clinical_bounds_would_refuse_is_ACCEPTED_stored_and_UNWARNED()
    {
        // §G7, the behavioural guard: the C-03/C-04 clinical bands (which would refuse both of these)
        // are clinician-UNSIGNED and have NO home in backend/src this phase. Both values sit inside the
        // sanity band, so there is not even a non-blocking hint — the only thing that could reject them
        // would be a clinical branch, and there is none to find.
        var saved = SavedOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(
            Cycle(CycleTestHarness.Today.AddDays(-2), avgCycleLengthDays: 47, avgPeriodLengthDays: 12), default));

        saved.AvgCycleLengthDays.ShouldBe(47);
        saved.AvgPeriodLengthDays.ShouldBe(12);
        saved.Warnings.ShouldBeEmpty("47 and 12 are inside the SANITY band; the clinical band is not code");

        await using var db = _harness.NewContext();
        var row = await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId);
        row.AvgCycleLengthDays.ShouldBe((short)47);
        row.AvgPeriodLengthDays.ShouldBe((short)12);
    }

    [Fact]
    public async Task The_only_400_on_the_two_lengths_is_the_structural_storage_domain()
    {
        // The one thing that CAN reject a self-report: a value the smallint column cannot hold. A value
        // outside the sanity band is stored and merely hinted at, which the next assertion proves.
        var zero = await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today, avgCycleLengthDays: 0, avgPeriodLengthDays: 0), default);
        var errors = ErrorsOf(zero);
        MessageFor(errors, "avgCycleLengthDays").ShouldBe(
            ValidationMessages.Between(CycleSettingsStructuralDomain.Min, CycleSettingsStructuralDomain.Max));
        MessageFor(errors, "avgPeriodLengthDays").ShouldBe(
            ValidationMessages.Between(CycleSettingsStructuralDomain.Min, CycleSettingsStructuralDomain.Max));

        var tooWide = await _harness.NewOnboardingStepsService().SaveCycleAsync(
            Cycle(CycleTestHarness.Today, avgCycleLengthDays: short.MaxValue + 1), default);
        MessageFor(ErrorsOf(tooWide), "avgCycleLengthDays").ShouldBe(
            ValidationMessages.Between(CycleSettingsStructuralDomain.Min, CycleSettingsStructuralDomain.Max));

        // Outside the sanity band: STORED, and answered with the non-blocking code (§G7).
        var wild = SavedOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(
            Cycle(CycleTestHarness.Today, avgCycleLengthDays: 400, avgPeriodLengthDays: 90), default));
        wild.AvgCycleLengthDays.ShouldBe(400);
        wild.Warnings.ShouldBe(
            [
                CycleSettingsWarnings.AvgCycleLengthOutOfSanityBand,
                CycleSettingsWarnings.AvgPeriodLengthOutOfSanityBand,
            ],
            Case.Sensitive);
    }

    // ================================================================ the composed unit of work (§G12)

    [Fact]
    public async Task The_settings_row_and_the_seeded_period_start_land_in_EXACTLY_ONE_save()
    {
        // §G12's unit-of-work rule, and the task it was written for. `ConcurrencyRetry` recovers via a
        // WHOLE-CONTEXT `ChangeTracker.Clear()`, so calling `CycleService.LogEventAsync` here — which
        // owns its own retry and clear — would silently discard the staged `user_cycle_settings` row,
        // with no exception and no failing test. Only T14's stage-only `ApplyOnboardingCycleAsync` may
        // be composed. Two counts catch a regression: the save count would be 2, and (depending on the
        // order) one of the two writes would be gone.
        var saves = new CountingSaveInterceptor();
        await using var db = _harness.NewContext(saves);
        var dayContext = new StubUserDayContext(_harness.DayInfo());
        var service = new OnboardingStepsService(
            db,
            dayContext,
            _harness.Crypto,
            new DeviceRegistrationService(db, dayContext),
            new CycleSettingsService(db, dayContext));

        await service.SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(-3), 30, 5, "regular"), default);

        saves.Saves.ShouldBe(1, "the endpoint owns exactly ONE retried action wrapping the whole unit of work");

        // Nothing is left UNSAVED. (Saved entities stay tracked as `Unchanged` — that is EF's identity
        // map, not pending work — so the claim is about pending states, not about the map being empty.)
        db.ChangeTracker.Entries()
            .Where(e => e.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .ShouldBeEmpty("the method saves everything it stages, in one unit of work");

        await using var read = _harness.NewContext();
        (await read.CycleSettings.CountAsync(s => s.UserId == _harness.UserId)).ShouldBe(1);
        (await read.CycleEvents.CountAsync(e => e.UserId == _harness.UserId)).ShouldBe(1);
    }

    [Fact]
    public async Task A_failed_save_loses_the_settings_row_and_the_seeded_event_TOGETHER()
    {
        // The other half of "one unit of work". A settings row without its anchor event would make the
        // user look onboarded to `GET /settings/cycle` while `/onboarding/complete` still 409s — the
        // exact half-written state the single save exists to make unreachable.
        await using var db = _harness.NewContext(new FailEverySaveInterceptor());
        var dayContext = new StubUserDayContext(_harness.DayInfo());
        var service = new OnboardingStepsService(
            db,
            dayContext,
            _harness.Crypto,
            new DeviceRegistrationService(db, dayContext),
            new CycleSettingsService(db, dayContext));

        await Should.ThrowAsync<DbUpdateException>(async () =>
            await service.SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(-3)), default));

        await using var read = _harness.NewContext();
        (await read.CycleSettings.CountAsync()).ShouldBe(0);
        (await read.CycleEvents.IgnoreQueryFilters().CountAsync()).ShouldBe(0);
    }

    // ================================================================ the T5 merge rule (§G9 UNFILTERED)

    [Fact]
    public async Task A_re_post_with_a_different_date_MOVES_the_single_onboarding_row()
    {
        // Collision (a). The user corrects the date on screen 3 and re-submits. A blind insert would
        // leave TWO period starts for one cycle, which the P6 estimator has no sane reading of.
        var first = CycleTestHarness.Today.AddDays(-10);
        var corrected = CycleTestHarness.Today.AddDays(-8);

        await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(first), default);
        var seeded = LivePeriodStarts().Single();

        var saved = SavedOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(corrected), default));
        saved.LastPeriodStart.ShouldBe(corrected);

        var rows = AllPeriodStarts();
        rows.Count.ShouldBe(1, "the seed MOVED; a second row would be a duplicate the index cannot hold");
        rows[0].Id.ShouldBe(seeded.Id, "the same row moved, so nothing downstream loses its identity");
        rows[0].OccurredOn.ShouldBe(corrected);
        rows[0].Source.ShouldBe(CycleEvent.Sources.Onboarding);
        rows[0].DeletedAt.ShouldBeNull();
    }

    [Fact]
    public async Task A_re_post_onto_a_LIVE_user_row_ADOPTS_it_and_retires_the_stale_seed()
    {
        // Collision (b), and the one that is a 23505 → 500 without the merge rule: the user seeded one
        // day at onboarding, logged a real period start on another day from the cycle module, then
        // corrected onboarding onto THAT day. The user's own row wins — its Source and CreatedAt are
        // its provenance, and overwriting them would relabel a hand-logged observation as machine seed.
        var seededDay = CycleTestHarness.Today.AddDays(-20);
        var userDay = CycleTestHarness.Today.AddDays(-12);

        await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(seededDay), default);
        var userRow = _harness.SeedEvent(
            CycleEvent.Kinds.PeriodStart, userDay, flow: CycleEvent.FlowIntensityScale.Medium);

        var saved = SavedOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(userDay), default));
        saved.LastPeriodStart.ShouldBe(userDay);

        LivePeriodStarts().Count.ShouldBe(1, "exactly one live period start survives the collision");

        var adopted = LivePeriodStarts().Single();
        adopted.Id.ShouldBe(userRow.Id);
        adopted.Source.ShouldBe(CycleEvent.Sources.User, "the adopted row keeps its provenance");
        adopted.CreatedAt.ShouldBe(userRow.CreatedAt, "and its original creation instant");
        adopted.FlowIntensity.ShouldBe(
            CycleEvent.FlowIntensityScale.Medium, "onboarding never asks for flow, so it clears none");

        var stale = AllPeriodStarts().Single(e => e.OccurredOn == seededDay);
        stale.DeletedAt.ShouldNotBeNull("the stale onboarding row is retired, not left as a second anchor");
        stale.Source.ShouldBe(CycleEvent.Sources.Onboarding);
    }

    [Fact]
    public async Task A_re_post_onto_a_TOMBSTONED_row_REVIVES_it()
    {
        // Collision (c). §G9's unfiltered index means a tombstone still occupies its key, so a blind
        // insert here is the same 23505 — invisible until the first user who deletes a period start and
        // then re-runs the onboarding step.
        var deletedDay = CycleTestHarness.Today.AddDays(-15);
        var tombstone = _harness.SeedEvent(
            CycleEvent.Kinds.PeriodStart, deletedDay, deletedAt: CycleTestHarness.Now.AddDays(-1));

        var saved = SavedOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(deletedDay), default));
        saved.LastPeriodStart.ShouldBe(deletedDay);

        var rows = AllPeriodStarts();
        rows.Count.ShouldBe(1, "revived in place — never a second row beside the tombstone");
        rows[0].Id.ShouldBe(tombstone.Id);
        rows[0].DeletedAt.ShouldBeNull();
        rows[0].Source.ShouldBe(CycleEvent.Sources.User, "revive preserves provenance, exactly like adopt");
        rows[0].CreatedAt.ShouldBe(tombstone.CreatedAt);
    }

    [Fact]
    public async Task Re_posting_the_SAME_date_three_times_is_idempotent()
    {
        var anchor = CycleTestHarness.Today.AddDays(-6);

        for (var i = 0; i < 3; i++)
            SavedOf(await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(anchor), default));

        AllPeriodStarts().Count.ShouldBe(1);

        await using var db = _harness.NewContext();
        (await db.CycleSettings.CountAsync(s => s.UserId == _harness.UserId)).ShouldBe(1);
    }

    // ================================================================ POST /onboarding/complete

    [Fact]
    public async Task Completing_without_a_period_start_is_a_conflict_and_stamps_nothing()
    {
        var result = await _harness.NewOnboardingStepsService().CompleteAsync(default);

        result.ShouldBeOfType<CompleteOnboardingResult.Incomplete>()
            .MissingSteps.ShouldBe([OnboardingSteps.Cycle], Case.Sensitive);

        await using var db = _harness.NewContext();
        (await db.Users.AsNoTracking().SingleAsync(u => u.Id == _harness.UserId))
            .OnboardingCompletedAt.ShouldBeNull();
        (await db.UserGoals.CountAsync()).ShouldBe(0, "a refused completion backfills nothing");
        (await db.UserHormonePrefs.CountAsync()).ShouldBe(0);
        (await db.UserNotificationPrefs.CountAsync()).ShouldBe(0);
        (await db.CycleSettings.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task A_period_start_logged_through_the_CYCLE_module_also_satisfies_the_mandatory_set()
    {
        // The check is on the DATA, not on "did this user call /onboarding/cycle". A user who logged a
        // period from screen 10 has answered the mandatory question by any reading that matters.
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today.AddDays(-4));

        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default))
            .CompletedAt.ShouldBe(CycleTestHarness.Now);
    }

    [Fact]
    public async Task A_tombstoned_period_start_does_NOT_satisfy_the_mandatory_set()
    {
        // The soft-delete query filter is load-bearing here: a retracted period start is not an answer.
        _harness.SeedEvent(
            CycleEvent.Kinds.PeriodStart,
            CycleTestHarness.Today.AddDays(-4),
            deletedAt: CycleTestHarness.Now.AddDays(-1));

        (await _harness.NewOnboardingStepsService().CompleteAsync(default))
            .ShouldBeOfType<CompleteOnboardingResult.Incomplete>();
    }

    [Fact]
    public async Task Completing_stamps_once_and_backfills_exactly_the_four_default_sets()
    {
        await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(-7)), default);

        var completion = CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));
        completion.CompletedAt.ShouldBe(CycleTestHarness.Now);
        completion.AlreadyCompleted.ShouldBeFalse();

        await using var db = _harness.NewContext();
        (await db.Users.AsNoTracking().SingleAsync(u => u.Id == _harness.UserId))
            .OnboardingCompletedAt.ShouldBe(CycleTestHarness.Now);

        // The four sets, each written from its entity's own seed constant — never a re-stated literal.
        var goals = await db.UserGoals.AsNoTracking().Where(g => g.UserId == _harness.UserId).ToListAsync();
        goals.Count.ShouldBe(UserGoal.Codes.All.Count);
        goals.Where(g => g.Selected).Select(g => g.GoalCode).Order(StringComparer.Ordinal)
            .ShouldBe(UserGoal.DefaultSelected.Order(StringComparer.Ordinal), Case.Sensitive);

        var hormones = await db.UserHormonePrefs.AsNoTracking()
            .Where(p => p.UserId == _harness.UserId).ToListAsync();
        hormones.Count.ShouldBe(HormoneCatalog.Codes.All.Count);
        hormones.Where(p => p.Charted).Select(p => p.HormoneCode).Order(StringComparer.Ordinal)
            .ShouldBe(UserHormonePref.DefaultCharted.Order(StringComparer.Ordinal), Case.Sensitive);

        var notifications = await db.UserNotificationPrefs.AsNoTracking()
            .Where(p => p.UserId == _harness.UserId).ToListAsync();
        notifications.Count.ShouldBe(HormoneCatalog.NotificationCategories.All.Count);
        notifications.Where(p => p.Enabled).Select(p => p.CategoryCode).Order(StringComparer.Ordinal)
            .ShouldBe(UserNotificationPref.DefaultEnabled.Order(StringComparer.Ordinal), Case.Sensitive);

        (await db.CycleSettings.CountAsync(s => s.UserId == _harness.UserId))
            .ShouldBe(1, "the fourth set: user_cycle_settings, already written by the cycle step");

        // §G6, actually asserted: the happy path computes nothing clinical.
        (await db.UserInsightSnapshots.CountAsync()).ShouldBe(
            0, "P4a ships ZERO clinical inference — user_insight_snapshot stays empty");
    }

    [Fact]
    public async Task The_cycle_settings_row_is_backfilled_for_a_user_who_never_ran_the_cycle_STEP()
    {
        // The fourth default set earns its place here: this user qualified through the cycle module, so
        // nothing has written `user_cycle_settings` yet. Leaving it absent would make a direct SELECT
        // read as "no self-report" for the rest of the product's life.
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today.AddDays(-9));

        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));

        await using var db = _harness.NewContext();
        var settings = await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId);
        settings.AvgCycleLengthDays.ShouldBe(UserCycleSettings.DefaultAvgCycleLengthDays);
        settings.AvgPeriodLengthDays.ShouldBeNull();
        settings.Regularity.ShouldBe(UserCycleSettings.RegularityValues.Default);
    }

    [Fact]
    public async Task The_backfill_does_not_overwrite_a_user_supplied_preference()
    {
        // "Backfill" means "for a table with zero rows". A user who answered screen 6 with nothing
        // charted must not have all seven turned back on by pressing Finish — that would be the app
        // overruling an explicit answer.
        await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(-7), avgCycleLengthDays: 35), default);
        await _harness.NewOnboardingStepsService()
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([]), default);
        await _harness.NewOnboardingStepsService()
            .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.JustCurious]), default);

        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));

        await using var db = _harness.NewContext();
        (await db.UserHormonePrefs.CountAsync(p => p.UserId == _harness.UserId && p.Charted))
            .ShouldBe(0, "an explicit 'chart nothing' survives completion");
        (await db.UserGoals.Where(g => g.UserId == _harness.UserId && g.Selected)
            .Select(g => g.GoalCode).ToListAsync()).ShouldBe([UserGoal.Codes.JustCurious], Case.Sensitive);

        // The notification step was skipped, so THAT one is seeded.
        (await db.UserNotificationPrefs.Where(p => p.UserId == _harness.UserId && p.Enabled)
                .Select(p => p.CategoryCode).ToListAsync())
            .Order(StringComparer.Ordinal)
            .ShouldBe(UserNotificationPref.DefaultEnabled.Order(StringComparer.Ordinal), Case.Sensitive);

        // And the settings row the cycle step wrote is not reset to the default.
        (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId))
            .AvgCycleLengthDays.ShouldBe((short)35);
    }

    [Fact]
    public async Task A_second_completion_returns_the_ORIGINAL_timestamp_with_no_duplicate_rows()
    {
        await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(-7)), default);

        var first = CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));
        first.AlreadyCompleted.ShouldBeFalse();

        // A LATER instant, so an unguarded UPDATE would visibly move the stamp.
        var later = _harness.DayInfo(now: CycleTestHarness.Now.AddHours(3));
        var second = CompletedOf(await _harness.NewOnboardingStepsService(later).CompleteAsync(default));

        second.CompletedAt.ShouldBe(
            first.CompletedAt, "the guarded claim means the second caller reports the winner's stamp");
        second.AlreadyCompleted.ShouldBeTrue();

        await using var db = _harness.NewContext();
        (await db.Users.AsNoTracking().SingleAsync(u => u.Id == _harness.UserId))
            .OnboardingCompletedAt.ShouldBe(CycleTestHarness.Now);
        (await db.UserGoals.CountAsync(g => g.UserId == _harness.UserId)).ShouldBe(UserGoal.Codes.All.Count);
        (await db.UserHormonePrefs.CountAsync(p => p.UserId == _harness.UserId))
            .ShouldBe(HormoneCatalog.Codes.All.Count);
        (await db.UserNotificationPrefs.CountAsync(p => p.UserId == _harness.UserId))
            .ShouldBe(HormoneCatalog.NotificationCategories.All.Count);
    }

    [Fact]
    public async Task A_completion_that_loses_the_stamp_race_reports_the_WINNERS_timestamp()
    {
        // The concurrency claim, staged rather than raced: the guard `WHERE OnboardingCompletedAt IS
        // NULL` is what makes two simultaneous "Finish" taps stamp exactly once. Here the winner has
        // already committed a stamp at an EARLIER instant; the losing call must report that instant and
        // leave the column alone. Without the guard it would overwrite, and `completedAt` would drift
        // forward every time the client retried.
        await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(-7)), default);

        var winnerStamp = CycleTestHarness.Now.AddDays(-2);
        await using (var arrange = _harness.NewContext())
        {
            var user = await arrange.Users.SingleAsync(u => u.Id == _harness.UserId);
            user.OnboardingCompletedAt = winnerStamp;
            await arrange.SaveChangesAsync();
        }

        var loser = CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));
        loser.CompletedAt.ShouldBe(winnerStamp);
        loser.AlreadyCompleted.ShouldBeTrue();

        await using var db = _harness.NewContext();
        (await db.Users.AsNoTracking().SingleAsync(u => u.Id == _harness.UserId))
            .OnboardingCompletedAt.ShouldBe(winnerStamp);
    }

    [Fact]
    public async Task An_already_completed_user_with_no_live_period_start_still_gets_200_not_409()
    {
        // The stamp is a fact about the past. A user who completed onboarding and later deleted their
        // period start has not become un-onboarded, and a 409 here would tell the client to send them
        // back through screen 3.
        var seeded = _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today.AddDays(-7));
        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));

        await using (var arrange = _harness.NewContext())
        {
            var row = await arrange.CycleEvents.SingleAsync(e => e.Id == seeded.Id);
            row.DeletedAt = CycleTestHarness.Now;
            await arrange.SaveChangesAsync();
        }

        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default))
            .AlreadyCompleted.ShouldBeTrue();
    }

    [Fact]
    public async Task The_backfill_and_the_read_projections_cannot_disagree()
    {
        // The reconciliation this task owes T17, stated as a behavioural equality rather than as prose.
        // BEFORE completion the three projections give absence its meaning; AT completion the same seed
        // is materialised. If either side ever restated the other's literals the two would drift, and
        // this is the assertion that would notice.
        await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(-7)), default);

        var before = StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default));

        await using (var db = _harness.NewContext())
        {
            (await db.UserGoals.CountAsync()).ShouldBe(0, "nothing is persisted before completion");
            (await db.UserHormonePrefs.CountAsync()).ShouldBe(0);
            (await db.UserNotificationPrefs.CountAsync()).ShouldBe(0);
        }

        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));

        var after = StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default));

        after.Goals.ShouldBe(before.Goals);
        after.Hormones.ShouldBe(before.Hormones);
        after.Notifications.ShouldBe(before.Notifications);

        // The accepted cost, asserted so it is documented in code as well as in prose: the
        // never-asked/said-no distinction does NOT survive completion.
        before.GoalsProvided.ShouldBeFalse();
        after.GoalsProvided.ShouldBeTrue("after completion, absence is no longer distinguishable");
    }

    // ================================================================ POST /onboarding/cycle after completion

    [Fact]
    public async Task The_cycle_step_is_409_after_completion_even_with_a_body_that_would_be_a_400()
    {
        // Moving the seeded anchor post-hoc is a data-integrity hazard: every later cycle is measured
        // from it. Post-completion edits go through `POST /cycle/events` + `PATCH /settings/cycle`.
        // Checked BEFORE validation, because the step is closed — a 400 would invite the client to
        // "fix" a body that can never be accepted.
        await _harness.NewOnboardingStepsService()
            .SaveCycleAsync(Cycle(CycleTestHarness.Today.AddDays(-7)), default);
        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));

        (await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(CycleTestHarness.Today), default))
            .ShouldBeOfType<SaveOnboardingCycleResult.AlreadyCompleted>();

        (await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(null, regularity: "sometimes"), default))
            .ShouldBeOfType<SaveOnboardingCycleResult.AlreadyCompleted>();

        AllPeriodStarts().Single().OccurredOn.ShouldBe(
            CycleTestHarness.Today.AddDays(-7), "the anchor did not move");
    }

    // ================================================================ GET /onboarding/state

    [Fact]
    public async Task The_state_of_a_brand_new_account_is_all_false_and_cycle_is_missing()
    {
        var state = StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default));

        state.Completed.ShouldBeFalse();
        state.CompletedAt.ShouldBeNull();
        state.MissingMandatorySteps.ShouldBe([OnboardingSteps.Cycle], Case.Sensitive);
        state.CycleProvided.ShouldBeFalse();
        state.BaselineProvided.ShouldBeFalse();
        state.GoalsProvided.ShouldBeFalse();
        state.HormonesProvided.ShouldBeFalse();
        state.NotificationsProvided.ShouldBeFalse();
        state.LastPeriodStart.ShouldBeNull();

        // The projections still answer with the documented seed, which is what makes this a resume read
        // rather than a checklist: a partially-onboarded client can render every toggle correctly.
        state.Goals.Where(g => g.Selected).Select(g => g.Code).Order(StringComparer.Ordinal)
            .ShouldBe(UserGoal.DefaultSelected.Order(StringComparer.Ordinal), Case.Sensitive);
        state.Hormones.Select(h => h.Code).ShouldBe(HormoneCatalog.Codes.All, Case.Sensitive);
        state.Notifications.Where(c => c.Enabled).Select(c => c.Code).Order(StringComparer.Ordinal)
            .ShouldBe(UserNotificationPref.DefaultEnabled.Order(StringComparer.Ordinal), Case.Sensitive);
    }

    [Fact]
    public async Task Every_state_boolean_flips_at_the_moment_its_step_is_answered()
    {
        var service = _harness.NewOnboardingStepsService();

        await service.SaveBaselineAsync(new SaveBaselineRequest(null, 168, null, null, null, null), default);
        var afterBaseline = StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default));
        afterBaseline.BaselineProvided.ShouldBeTrue();
        afterBaseline.CycleProvided.ShouldBeFalse();
        afterBaseline.MissingMandatorySteps.ShouldBe([OnboardingSteps.Cycle], Case.Sensitive);

        var anchor = CycleTestHarness.Today.AddDays(-11);
        await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(anchor), default);
        var afterCycle = StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default));
        afterCycle.CycleProvided.ShouldBeTrue();
        afterCycle.LastPeriodStart.ShouldBe(anchor);
        afterCycle.MissingMandatorySteps.ShouldBeEmpty();
        afterCycle.Completed.ShouldBeFalse("the mandatory set being answered is not the same as completing");

        await _harness.NewOnboardingStepsService()
            .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.PlanFertility]), default);
        StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default))
            .GoalsProvided.ShouldBeTrue();

        await _harness.NewOnboardingStepsService()
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([HormoneCatalog.Codes.Lh]), default);
        StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default))
            .HormonesProvided.ShouldBeTrue();

        await _harness.NewOnboardingStepsService()
            .SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest([], null, null), default);
        StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default))
            .NotificationsProvided.ShouldBeTrue();

        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));
        var final = StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default));
        final.Completed.ShouldBeTrue();
        final.CompletedAt.ShouldBe(CycleTestHarness.Now);
        final.MissingMandatorySteps.ShouldBeEmpty();
    }

    [Fact]
    public async Task The_state_reports_the_LATEST_live_period_start()
    {
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today.AddDays(-40));
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleTestHarness.Today.AddDays(-12));
        _harness.SeedEvent(
            CycleEvent.Kinds.PeriodStart,
            CycleTestHarness.Today.AddDays(-3),
            deletedAt: CycleTestHarness.Now);

        StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default))
            .LastPeriodStart.ShouldBe(
                CycleTestHarness.Today.AddDays(-12), "a retracted row is not the user's last period start");
    }

    [Fact]
    public async Task A_weight_only_baseline_still_counts_as_answered()
    {
        // Rider 4 puts weight in `body_metrics`, not on the profile, so "did the user answer screen 4"
        // cannot be read off `user_profile_enc` alone.
        await _harness.NewOnboardingStepsService()
            .SaveBaselineAsync(new SaveBaselineRequest(null, null, 62.5m, null, null, null), default);

        StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default))
            .BaselineProvided.ShouldBeTrue();
    }

    // ================================================================ the 404 fence and tenant isolation

    [Fact]
    public async Task A_crypto_shredded_user_gets_404_from_all_three_endpoints_before_anything_else()
    {
        // The fence that makes an erased account's still-valid JWT inert. Checked BEFORE validation and
        // before the completion probe, so a body that would otherwise be a 400 — or a 409 — still
        // answers "no such user" and leaks nothing about the shape the server understood.
        (await _harness.NewOnboardingStepsService(info: null)
                .SaveCycleAsync(Cycle(null, regularity: "sometimes"), default))
            .ShouldBeOfType<SaveOnboardingCycleResult.UserNotFound>();

        (await _harness.NewOnboardingStepsService(info: null).CompleteAsync(default))
            .ShouldBeOfType<CompleteOnboardingResult.UserNotFound>();

        (await _harness.NewOnboardingStepsService(info: null).ReadStateAsync(default))
            .ShouldBeOfType<OnboardingStateResult.UserNotFound>();

        await using var db = _harness.NewContext();
        (await db.CycleEvents.IgnoreQueryFilters().CountAsync()).ShouldBe(0);
        (await db.CycleSettings.CountAsync()).ShouldBe(0);
        (await db.UserGoals.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task One_users_cycle_seed_and_completion_are_invisible_to_and_untouched_by_another()
    {
        var mine = CycleTestHarness.Today.AddDays(-9);
        var theirs = CycleTestHarness.Today.AddDays(-21);
        var other = _harness.DayInfo(userId: _harness.OtherUserId);

        await _harness.NewOnboardingStepsService().SaveCycleAsync(Cycle(mine), default);
        await _harness.NewOnboardingStepsService(other).SaveCycleAsync(Cycle(theirs, avgCycleLengthDays: 33), default);
        CompletedOf(await _harness.NewOnboardingStepsService().CompleteAsync(default));

        var theirState = StateOf(await _harness.NewOnboardingStepsService(other).ReadStateAsync(default));
        theirState.LastPeriodStart.ShouldBe(theirs);
        theirState.Completed.ShouldBeFalse("completing one account must not complete another");
        theirState.GoalsProvided.ShouldBeFalse("nor backfill another account's preference rows");

        StateOf(await _harness.NewOnboardingStepsService().ReadStateAsync(default))
            .LastPeriodStart.ShouldBe(mine);

        await using var db = _harness.NewContext();
        (await db.CycleEvents.CountAsync(e => e.UserId == _harness.OtherUserId)).ShouldBe(1);
        (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.OtherUserId))
            .AvgCycleLengthDays.ShouldBe((short)33);
        (await db.UserGoals.CountAsync(g => g.UserId == _harness.OtherUserId)).ShouldBe(0);
    }
}
