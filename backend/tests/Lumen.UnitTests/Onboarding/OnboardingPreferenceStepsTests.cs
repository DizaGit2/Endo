using Lumen.Api.Devices;
using Lumen.Api.Onboarding;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Lumen.Domain.Reference;
using Lumen.Infrastructure.Logging;
using Lumen.UnitTests.Cycle;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Onboarding;

/// <summary>
/// Unit tests for <see cref="OnboardingStepsService"/>'s three preference steps (T17) — screens 5, 6
/// and 7: <c>POST /onboarding/goals</c>, <c>POST /onboarding/hormones</c> and
/// <c>POST /onboarding/notifications</c>.
///
/// <para>Five claims dominate this file.</para>
///
/// <para><b>1. The three frozen vocabularies and their SEED states (§G10).</b> Five goals seeded
/// ON/ON/OFF/OFF/OFF, seven hormones seeded ALL ON (D-14), four notification categories seeded
/// ON/ON/OFF/OFF. Every step writes its <b>complete</b> row set, so "provided" is never partial and a
/// stored row always exists for every code in the vocabulary.</para>
///
/// <para><b>2. A SKIPPED step persists NOTHING, and the seed is applied on the READ side.</b> D-02
/// makes all three skippable, and the entities say a missing row is "never saw the question" while
/// <c>Selected = false</c> is "was asked and said no" — two different facts, so seeding at
/// <c>/onboarding/start</c> would destroy one of them. The three read projections are the single place
/// that turns "no rows" into the documented default, which is what stops T18's
/// <c>/onboarding/complete</c> and any later <c>GET</c> from disagreeing about what "skipped"
/// means.</para>
///
/// <para><b>3. Re-submission is a FULL REPLACE of the set, and it is idempotent.</b> Three calls leave
/// exactly 5 / 7 / 4 rows, never 15 / 21 / 12 and never a 23505 against
/// <c>(UserId, &lt;Code&gt;)</c>.</para>
///
/// <para><b>4. The notification step COMPOSES T15's device staging into ONE unit of work.</b> The four
/// preference rows and the <c>user_devices</c> row commit or roll back together, in exactly one
/// <c>SaveChanges</c>, inside exactly one <see cref="Api.Persistence.ConcurrencyRetry"/> action.</para>
///
/// <para><b>5. The push token is optional and never logged.</b> A user may decline the OS permission
/// prompt, so notification preferences and device registration are separable.</para>
/// </summary>
public sealed class OnboardingPreferenceStepsTests : IDisposable
{
    private const string TokenA = "fcm-token-onboarding-aaaaaaaaaaaaaaaaaaaa";
    private const string TokenB = "apns-token-onboarding-bbbbbbbbbbbbbbbbbbb";

    private readonly CycleTestHarness _harness = new();

    public void Dispose() => _harness.Dispose();

    // ---------------------------------------------------------------- shorthand

    private static IReadOnlyList<OnboardingFieldError> ErrorsOf(SaveGoalsResult result) =>
        result.ShouldBeOfType<SaveGoalsResult.Invalid>().Errors;

    private static IReadOnlyList<OnboardingFieldError> ErrorsOf(SaveHormonePrefsResult result) =>
        result.ShouldBeOfType<SaveHormonePrefsResult.Invalid>().Errors;

    private static IReadOnlyList<OnboardingFieldError> ErrorsOf(SaveNotificationPrefsResult result) =>
        result.ShouldBeOfType<SaveNotificationPrefsResult.Invalid>().Errors;

    private static string MessageFor(IReadOnlyList<OnboardingFieldError> errors, string field) =>
        errors.Single(e => string.Equals(e.Field, field, StringComparison.Ordinal)).Message;

    private static IReadOnlyList<GoalSelection> SavedOf(SaveGoalsResult result) =>
        result.ShouldBeOfType<SaveGoalsResult.Saved>().Goals.Goals;

    private static IReadOnlyList<HormoneSelection> SavedOf(SaveHormonePrefsResult result) =>
        result.ShouldBeOfType<SaveHormonePrefsResult.Saved>().Hormones.Hormones;

    private static NotificationPrefsResponse SavedOf(SaveNotificationPrefsResult result) =>
        result.ShouldBeOfType<SaveNotificationPrefsResult.Saved>().Notifications;

    private static IReadOnlyList<string> SelectedCodes(IEnumerable<GoalSelection> goals) =>
        [.. goals.Where(g => g.Selected).Select(g => g.Code)];

    private static IReadOnlyList<string> ChartedCodes(IEnumerable<HormoneSelection> hormones) =>
        [.. hormones.Where(h => h.Charted).Select(h => h.Code)];

    private static IReadOnlyList<string> EnabledCodes(IEnumerable<NotificationCategorySelection> categories) =>
        [.. categories.Where(c => c.Enabled).Select(c => c.Code)];

    // ================================================================ the frozen wire strings (§G12)

    [Fact]
    public void The_preference_step_wire_strings_are_frozen()
    {
        // These reach the Flutter client through the OpenAPI contract and are rendered verbatim, so a
        // reword is a contract change, not a copy edit. Asserted against the literal, never against
        // the constant, or the test would move with the code it is meant to pin.
        OnboardingValidationMessages.GoalsEmpty.ShouldBe("select at least one goal");
        OnboardingValidationMessages.DeviceFieldsIncomplete
            .ShouldBe("pushToken and platform must be provided together");

        // The shared messages these three endpoints reuse rather than restating (T3/§G12).
        ValidationMessages.Required.ShouldBe("value is required");
        ValidationMessages.NotAllowedValue.ShouldBe("value is not one of the allowed values");
        ValidationMessages.MaxLength(UserDevice.PushTokenMaxLength)
            .ShouldBe("text exceeds the maximum length of 512 characters");
    }

    // ================================================================ the frozen vocabularies + seeds

    [Fact]
    public async Task A_skipped_goals_step_reads_back_the_five_ratified_codes_with_the_D14_seed()
    {
        // §G10, proven behaviourally rather than as a constant: a user who never answered screen 5
        // reads back all five codes in the frozen display order, with the first two ON.
        var goals = await _harness.NewOnboardingStepsService().ReadGoalsAsync(_harness.UserId, default);

        goals.Select(g => g.Code).ShouldBe(
            ["manage_symptoms", "understand_hormones", "plan_fertility", "prepare_appointments", "just_curious"],
            Case.Sensitive);
        SelectedCodes(goals).ShouldBe(["manage_symptoms", "understand_hormones"], Case.Sensitive);

        await using var db = _harness.NewContext();
        (await db.UserGoals.CountAsync(g => g.UserId == _harness.UserId)).ShouldBe(
            0, "a SKIPPED step writes nothing — 'never saw the question' is a different fact from 'said no'");
    }

    [Fact]
    public async Task A_skipped_hormones_step_reads_back_the_seven_ratified_codes_with_ALL_SEVEN_charted()
    {
        // D-14: the charted default is ALL SEVEN. Screen 6 is authoritative; screen 33's mixed state is
        // a populated sample, not the spec.
        var hormones = await _harness.NewOnboardingStepsService().ReadHormonePrefsAsync(_harness.UserId, default);

        hormones.Select(h => h.Code).ShouldBe(
            ["estradiol", "progesterone", "lh", "fsh", "testosterone", "cortisol", "glp1"], Case.Sensitive);
        ChartedCodes(hormones).ShouldBe(
            ["estradiol", "progesterone", "lh", "fsh", "testosterone", "cortisol", "glp1"],
            Case.Sensitive,
            "D-14 seeds every hormone charted; hiding one is an explicit user act, never a default");

        await using var db = _harness.NewContext();
        (await db.UserHormonePrefs.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(0);
    }

    [Fact]
    public async Task A_skipped_notifications_step_reads_back_the_four_categories_seeded_ON_ON_OFF_OFF()
    {
        var categories = await _harness.NewOnboardingStepsService()
            .ReadNotificationPrefsAsync(_harness.UserId, default);

        categories.Select(c => c.Code).ShouldBe(
            ["daily_checkin", "phase_shift", "period_prediction", "medication_reminders"], Case.Sensitive);
        categories.Select(c => c.Enabled).ShouldBe(
            [true, true, false, false], "screen 7's seed is ON / ON / OFF / OFF, in category order");

        // The canonical display label is singular — screen 7's "Phase shifts" is the drift (B16/§G10).
        HormoneCatalog.NotificationCategories.Labels["phase_shift"].ShouldBe("Phase shift");

        await using var db = _harness.NewContext();
        (await db.UserNotificationPrefs.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(0);
    }

    [Fact]
    public async Task A_stored_preference_row_beats_the_seed_on_every_read_path()
    {
        // Otherwise "I turned everything off" would silently read back as the default the next time a
        // consumer asked — which is exactly the disagreement T18 must not be able to have.
        var service = _harness.NewOnboardingStepsService();
        await service.SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.JustCurious]), default);
        await service.SaveHormonePrefsAsync(new SaveHormonePrefsRequest([]), default);
        await service.SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest([], null, null), default);

        var reader = _harness.NewOnboardingStepsService();
        SelectedCodes(await reader.ReadGoalsAsync(_harness.UserId, default))
            .ShouldBe(["just_curious"], Case.Sensitive);
        ChartedCodes(await reader.ReadHormonePrefsAsync(_harness.UserId, default)).ShouldBeEmpty();
        EnabledCodes(await reader.ReadNotificationPrefsAsync(_harness.UserId, default)).ShouldBeEmpty();
    }

    // ================================================================ goals (screen 5)

    [Fact]
    public async Task A_null_goal_list_is_rejected_as_a_missing_field()
    {
        var result = await _harness.NewOnboardingStepsService().SaveGoalsAsync(new SaveGoalsRequest(null), default);

        MessageFor(ErrorsOf(result), "goals").ShouldBe(ValidationMessages.Required);
    }

    [Fact]
    public async Task An_empty_goal_list_is_rejected_because_D14_requires_at_least_one()
    {
        // Unlike hormones and notifications, "none" is not an answer here: the goals drive the P6
        // insight copy, and a user with no goal at all is a state screen 5 cannot produce.
        var result = await _harness.NewOnboardingStepsService().SaveGoalsAsync(new SaveGoalsRequest([]), default);

        MessageFor(ErrorsOf(result), "goals").ShouldBe(OnboardingValidationMessages.GoalsEmpty);

        await using var db = _harness.NewContext();
        (await db.UserGoals.CountAsync()).ShouldBe(0, "validate-then-act: a rejected request wrote nothing");
    }

    [Theory]
    [InlineData("manage_symptom")]      // near-miss singular
    [InlineData("Manage_Symptoms")]     // wrong case — the vocabulary is matched case-sensitively
    [InlineData("get_pregnant")]
    public async Task An_unknown_goal_code_is_rejected_and_keyed_to_its_own_index(string code)
    {
        var result = await _harness.NewOnboardingStepsService()
            .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.ManageSymptoms, code]), default);

        // Keyed per member, the way `painTypes[1]` is (T12): the client renders these as chips and has
        // to know which one to flag.
        MessageFor(ErrorsOf(result), "goals[1]").ShouldBe(ValidationMessages.NotAllowedValue);
    }

    [Fact]
    public async Task A_valid_subset_writes_ALL_FIVE_rows_with_only_the_requested_ones_selected()
    {
        var result = await _harness.NewOnboardingStepsService().SaveGoalsAsync(
            new SaveGoalsRequest([UserGoal.Codes.PlanFertility, UserGoal.Codes.JustCurious]), default);

        var saved = SavedOf(result);
        saved.Count.ShouldBe(5, "the step writes its COMPLETE row set, so 'provided' is never partial");
        saved.Select(g => g.Code).ShouldBe(UserGoal.Codes.All, Case.Sensitive, "response in frozen order");
        SelectedCodes(saved).ShouldBe(["plan_fertility", "just_curious"], Case.Sensitive);

        await using var db = _harness.NewContext();
        var rows = await db.UserGoals.AsNoTracking().Where(g => g.UserId == _harness.UserId).ToListAsync();
        rows.Count.ShouldBe(5);
        rows.Where(r => r.Selected).Select(r => r.GoalCode).OrderBy(c => c, StringComparer.Ordinal)
            .ShouldBe(["just_curious", "plan_fertility"], Case.Sensitive);
        rows.ShouldAllBe(r => r.CreatedAt == CycleTestHarness.Now && r.UpdatedAt == CycleTestHarness.Now);
    }

    [Fact]
    public async Task Duplicate_goal_codes_are_de_duplicated_silently_and_still_yield_five_rows()
    {
        var result = await _harness.NewOnboardingStepsService().SaveGoalsAsync(
            new SaveGoalsRequest(
                [UserGoal.Codes.ManageSymptoms, UserGoal.Codes.ManageSymptoms, UserGoal.Codes.ManageSymptoms]),
            default);

        SelectedCodes(SavedOf(result)).ShouldBe(["manage_symptoms"], Case.Sensitive);

        await using var db = _harness.NewContext();
        (await db.UserGoals.CountAsync(g => g.UserId == _harness.UserId)).ShouldBe(
            5, "a duplicate is UI noise, not a second row — the unique key would reject it anyway");
    }

    [Fact]
    public async Task Re_submitting_goals_REPLACES_the_set_rather_than_merging_it()
    {
        // FULL REPLACE, decided the way T11 decided `symptoms`: ONE surface writes this row (screen 5
        // now, screen 32 later — never both at once), and CLEARING IS THE AFFORDANCE, because the goals
        // are toggle chips. Under a merge a goal would be addable but never removable.
        var service = _harness.NewOnboardingStepsService();
        await service.SaveGoalsAsync(
            new SaveGoalsRequest([UserGoal.Codes.ManageSymptoms, UserGoal.Codes.PlanFertility]), default);

        var result = await _harness.NewOnboardingStepsService()
            .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.JustCurious]), default);

        SelectedCodes(SavedOf(result)).ShouldBe(
            ["just_curious"], Case.Sensitive, "the omitted goals are DESELECTED, not left standing");
    }

    [Fact]
    public async Task Posting_goals_three_times_leaves_exactly_five_rows()
    {
        for (var i = 0; i < 3; i++)
        {
            (await _harness.NewOnboardingStepsService()
                .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.PrepareAppointments]), default))
                .ShouldBeOfType<SaveGoalsResult.Saved>();
        }

        await using var db = _harness.NewContext();
        (await db.UserGoals.CountAsync(g => g.UserId == _harness.UserId)).ShouldBe(
            5, "an upsert on (UserId, GoalCode), never an append — the unique index would 23505 otherwise");
    }

    // ================================================================ hormones (screen 6)

    [Fact]
    public async Task A_null_charted_hormone_list_is_rejected_as_a_missing_field()
    {
        var result = await _harness.NewOnboardingStepsService()
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest(null), default);

        MessageFor(ErrorsOf(result), "chartedHormones").ShouldBe(ValidationMessages.Required);
    }

    [Fact]
    public async Task An_empty_hormone_list_is_ALLOWED_and_writes_seven_uncharted_rows()
    {
        // "Chart nothing" is a real answer, and it is NOT the same as skipping the step. It also does
        // not stop extraction: hidden ≠ not-extracted (D-14) — P7b still extracts every hormone.
        var result = await _harness.NewOnboardingStepsService()
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([]), default);

        var saved = SavedOf(result);
        saved.Count.ShouldBe(7);
        saved.ShouldAllBe(h => !h.Charted);

        await using var db = _harness.NewContext();
        var rows = await db.UserHormonePrefs.AsNoTracking().Where(p => p.UserId == _harness.UserId).ToListAsync();
        rows.Count.ShouldBe(7, "the complete row set, so 'the user answered' is recorded for every code");
        rows.ShouldAllBe(r => !r.Charted);
    }

    [Theory]
    [InlineData("estrogen")]     // the DISPLAY label — the code is `estradiol` (B16)
    [InlineData("glp-1")]        // the display label — the code is `glp1`
    [InlineData("LH")]           // wrong case
    [InlineData("insulin")]
    public async Task An_unknown_hormone_code_is_rejected_and_keyed_to_its_own_index(string code)
    {
        var result = await _harness.NewOnboardingStepsService()
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([HormoneCatalog.Codes.Estradiol, code]), default);

        MessageFor(ErrorsOf(result), "chartedHormones[1]").ShouldBe(ValidationMessages.NotAllowedValue);
    }

    [Fact]
    public async Task All_seven_hormones_are_accepted_and_answered_in_the_frozen_order()
    {
        var result = await _harness.NewOnboardingStepsService()
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([.. HormoneCatalog.Codes.All.Reverse()]), default);

        var saved = SavedOf(result);
        saved.Select(h => h.Code).ShouldBe(
            ["estradiol", "progesterone", "lh", "fsh", "testosterone", "cortisol", "glp1"],
            Case.Sensitive,
            "the response is in the frozen display order, never in the order the client happened to send");
        saved.ShouldAllBe(h => h.Charted);
    }

    [Fact]
    public async Task Re_submitting_hormones_REPLACES_the_set_and_three_posts_leave_seven_rows()
    {
        var service = _harness.NewOnboardingStepsService();
        await service.SaveHormonePrefsAsync(new SaveHormonePrefsRequest([.. HormoneCatalog.Codes.All]), default);

        for (var i = 0; i < 3; i++)
        {
            (await _harness.NewOnboardingStepsService().SaveHormonePrefsAsync(
                new SaveHormonePrefsRequest([HormoneCatalog.Codes.Estradiol, HormoneCatalog.Codes.Lh]), default))
                .ShouldBeOfType<SaveHormonePrefsResult.Saved>();
        }

        await using var db = _harness.NewContext();
        var rows = await db.UserHormonePrefs.AsNoTracking().Where(p => p.UserId == _harness.UserId).ToListAsync();
        rows.Count.ShouldBe(7);
        rows.Where(r => r.Charted).Select(r => r.HormoneCode).OrderBy(c => c, StringComparer.Ordinal)
            .ShouldBe(["estradiol", "lh"], Case.Sensitive, "the five omitted hormones are un-charted, not left on");
    }

    // ================================================================ notifications (screen 7)

    [Fact]
    public async Task A_null_category_list_is_rejected_as_a_missing_field()
    {
        var result = await _harness.NewOnboardingStepsService()
            .SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest(null, null, null), default);

        MessageFor(ErrorsOf(result), "enabledCategories").ShouldBe(ValidationMessages.Required);
    }

    [Theory]
    [InlineData("phase_shifts")]   // the screen-7 plural — the code is singular
    [InlineData("daily_check_in")]
    [InlineData("lab_reminders")]
    public async Task An_unknown_notification_category_is_rejected_and_keyed_to_its_own_index(string code)
    {
        var result = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                [HormoneCatalog.NotificationCategories.DailyCheckin, code], null, null), default);

        MessageFor(ErrorsOf(result), "enabledCategories[1]").ShouldBe(ValidationMessages.NotAllowedValue);
    }

    [Fact]
    public async Task An_empty_category_list_is_ALLOWED_and_mutes_everything()
    {
        var result = await _harness.NewOnboardingStepsService()
            .SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest([], null, null), default);

        var saved = SavedOf(result);
        saved.Categories.Count.ShouldBe(4);
        saved.Categories.ShouldAllBe(c => !c.Enabled);
        saved.DeviceRegistered.ShouldBeFalse();

        await using var db = _harness.NewContext();
        (await db.UserNotificationPrefs.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(4);
    }

    [Fact]
    public async Task The_step_works_WITHOUT_a_push_token_and_registers_no_device()
    {
        // A user may decline the OS permission prompt, so the preference and the registration are
        // separable. "Not now" on screen 7 must still record what the user chose to be notified about.
        var result = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                [HormoneCatalog.NotificationCategories.DailyCheckin,
                 HormoneCatalog.NotificationCategories.PhaseShift],
                null,
                null),
            default);

        var saved = SavedOf(result);
        EnabledCodes(saved.Categories).ShouldBe(["daily_checkin", "phase_shift"], Case.Sensitive);
        saved.DeviceRegistered.ShouldBeFalse();

        await using var db = _harness.NewContext();
        (await db.UserNotificationPrefs.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(4);
        (await db.UserDevices.CountAsync(d => d.UserId == _harness.UserId)).ShouldBe(
            0, "no token means no device row — never a placeholder registration");
    }

    [Fact]
    public async Task The_step_registers_the_device_WITH_a_push_token_in_the_same_call()
    {
        // §C.1 lists `user_devices` among onboarding's writes — screen 7's "Allow & finish".
        var result = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                [HormoneCatalog.NotificationCategories.PeriodPrediction], TokenA, UserDevice.Platforms.Ios),
            default);

        SavedOf(result).DeviceRegistered.ShouldBeTrue();

        await using var db = _harness.NewContext();
        var device = await db.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == _harness.UserId);
        device.Platform.ShouldBe(UserDevice.Platforms.Ios);
        device.PushToken.ShouldBe(TokenA);
        device.LastSeenAt.ShouldBe(CycleTestHarness.Now);
        (await db.UserNotificationPrefs.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(4);
    }

    [Fact]
    public async Task The_token_upsert_INSERTS_then_UPDATES_and_leaves_exactly_one_device_row()
    {
        var first = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest([], TokenA, UserDevice.Platforms.Ios), default);
        SavedOf(first).DeviceRegistered.ShouldBeTrue();

        Guid deviceId;
        await using (var read = _harness.NewContext())
            deviceId = (await read.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == _harness.UserId)).Id;

        var later = CycleTestHarness.Now.AddDays(30);
        var second = await _harness.NewOnboardingStepsService(_harness.DayInfo(now: later)).SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest([], TokenA, UserDevice.Platforms.Android), default);
        SavedOf(second).DeviceRegistered.ShouldBeTrue();

        await using var db = _harness.NewContext();
        var rows = await db.UserDevices.AsNoTracking().Where(d => d.UserId == _harness.UserId).ToListAsync();
        rows.Count.ShouldBe(1, "an upsert on the existing unique (UserId, PushToken), never an append");
        rows[0].Id.ShouldBe(deviceId, "the row's identity survives a re-registration");
        rows[0].Platform.ShouldBe(UserDevice.Platforms.Android, "a restored install can genuinely change platform");
        rows[0].LastSeenAt.ShouldBe(later);
    }

    [Fact]
    public async Task A_push_token_without_a_platform_is_rejected_under_the_request_key()
    {
        var result = await _harness.NewOnboardingStepsService()
            .SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest([], TokenA, null), default);

        // Under `request` rather than a field: the message names BOTH fields, so it belongs to the
        // combination. The house style is that a field-scoped message never names its own field.
        MessageFor(ErrorsOf(result), ValidationProblemBuilder.RequestKey)
            .ShouldBe(OnboardingValidationMessages.DeviceFieldsIncomplete);
    }

    [Fact]
    public async Task A_platform_without_a_push_token_is_rejected_under_the_request_key()
    {
        var result = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest([], null, UserDevice.Platforms.Android), default);

        MessageFor(ErrorsOf(result), ValidationProblemBuilder.RequestKey)
            .ShouldBe(OnboardingValidationMessages.DeviceFieldsIncomplete);
    }

    [Fact]
    public async Task A_blank_token_or_platform_counts_as_absent_rather_than_as_a_value()
    {
        // Same rule PATCH /me, POST /me/devices and the baseline step follow: whitespace is not an
        // answer. Both blank means "no device", not a half-supplied pair.
        var result = await _harness.NewOnboardingStepsService()
            .SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest([], "   ", "  "), default);

        SavedOf(result).DeviceRegistered.ShouldBeFalse();

        await using var db = _harness.NewContext();
        (await db.UserDevices.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task A_platform_outside_the_ratified_vocabulary_is_rejected()
    {
        // `web` is the tempting third value and it is NOT ratified: the code decides which provider
        // P9a dispatches through, so storing it would be a device that can never be reached.
        var result = await _harness.NewOnboardingStepsService()
            .SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest([], TokenA, "web"), default);

        MessageFor(ErrorsOf(result), "platform").ShouldBe(ValidationMessages.NotAllowedValue);
    }

    [Fact]
    public async Task A_push_token_longer_than_the_column_is_rejected()
    {
        var result = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                [], new string('t', UserDevice.PushTokenMaxLength + 1), UserDevice.Platforms.Ios),
            default);

        MessageFor(ErrorsOf(result), "pushToken")
            .ShouldBe(ValidationMessages.MaxLength(UserDevice.PushTokenMaxLength));
    }

    [Fact]
    public async Task A_token_of_exactly_the_column_width_is_accepted()
    {
        var result = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                [], new string('t', UserDevice.PushTokenMaxLength), UserDevice.Platforms.Ios),
            default);

        SavedOf(result).DeviceRegistered.ShouldBeTrue();
    }

    [Fact]
    public async Task Every_bad_notification_field_is_reported_in_one_response_and_nothing_is_written()
    {
        var result = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                ["phase_shifts"], new string('t', UserDevice.PushTokenMaxLength + 1), "web"),
            default);

        ErrorsOf(result).Select(e => e.Field).OrderBy(k => k, StringComparer.Ordinal).ShouldBe(
            ["enabledCategories[0]", "platform", "pushToken"],
            Case.Sensitive,
            "validate-then-act: a form with three bad fields must not take three round trips to fix");

        await using var db = _harness.NewContext();
        (await db.UserNotificationPrefs.CountAsync()).ShouldBe(0);
        (await db.UserDevices.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task Posting_notifications_three_times_leaves_four_preference_rows_and_one_device()
    {
        for (var i = 0; i < 3; i++)
        {
            (await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
                new SaveNotificationPrefsRequest(
                    [HormoneCatalog.NotificationCategories.MedicationReminders],
                    TokenA,
                    UserDevice.Platforms.Ios),
                default))
                .ShouldBeOfType<SaveNotificationPrefsResult.Saved>();
        }

        await using var db = _harness.NewContext();
        var rows = await db.UserNotificationPrefs.AsNoTracking()
            .Where(p => p.UserId == _harness.UserId).ToListAsync();
        rows.Count.ShouldBe(4, "an upsert on (UserId, CategoryCode), never an append");
        rows.Where(r => r.Enabled).Select(r => r.CategoryCode)
            .ShouldBe(["medication_reminders"], Case.Sensitive);
        (await db.UserDevices.CountAsync(d => d.UserId == _harness.UserId)).ShouldBe(1);
    }

    // ================================================================ the composed unit of work (§G12)

    [Fact]
    public async Task The_preference_rows_and_the_device_row_land_in_EXACTLY_ONE_save()
    {
        // §G12's unit-of-work rule, enforced rather than documented. `ConcurrencyRetry` recovers via a
        // WHOLE-CONTEXT `ChangeTracker.Clear()`, so composing T15's `RegisterAsync` — which owns its
        // own retry and save — would silently discard the four staged preference rows, with no
        // exception and no failing test. Only `StageRegistrationAsync` may be composed. Two counts
        // catch a regression to `RegisterAsync`: the save count would be 2, and (depending on the
        // order) one of the two writes would be gone.
        var saves = new CountingSaveInterceptor();
        await using var db = _harness.NewContext(saves);
        var dayContext = new StubUserDayContext(_harness.DayInfo());
        var service = new OnboardingStepsService(
            db, dayContext, _harness.Crypto, new DeviceRegistrationService(db, dayContext));

        await service.SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                [HormoneCatalog.NotificationCategories.DailyCheckin], TokenA, UserDevice.Platforms.Ios),
            default);

        saves.Saves.ShouldBe(
            1, "the endpoint owns exactly ONE retried action wrapping the whole unit of work");

        // Nothing is left UNSAVED. (Saved entities stay tracked as `Unchanged` — that is EF's identity
        // map, not pending work — so the claim is about pending states, not about the map being empty.)
        db.ChangeTracker.Entries()
            .Where(e => e.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .ShouldBeEmpty("the method saves everything it stages, in one unit of work");

        await using var read = _harness.NewContext();
        (await read.UserNotificationPrefs.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(
            4, "the preference rows survived the composition with the device stage");
        (await read.UserDevices.CountAsync(d => d.UserId == _harness.UserId)).ShouldBe(1);
    }

    [Fact]
    public async Task A_failed_save_loses_the_device_row_and_the_preference_rows_TOGETHER()
    {
        // The other half of "one unit of work": they commit or roll back together. A device row left
        // behind by a half-failed onboarding step would make P9a dispatch to a handset whose owner
        // never finished saying what they wanted to be notified about.
        await using var db = _harness.NewContext(new FailEverySaveInterceptor());
        var dayContext = new StubUserDayContext(_harness.DayInfo());
        var service = new OnboardingStepsService(
            db, dayContext, _harness.Crypto, new DeviceRegistrationService(db, dayContext));

        await Should.ThrowAsync<DbUpdateException>(async () => await service.SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                [HormoneCatalog.NotificationCategories.DailyCheckin], TokenA, UserDevice.Platforms.Ios),
            default));

        await using var read = _harness.NewContext();
        (await read.UserNotificationPrefs.CountAsync()).ShouldBe(0);
        (await read.UserDevices.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task The_goals_and_hormones_steps_also_own_ONE_save_each()
    {
        var goalSaves = new CountingSaveInterceptor();
        await using (var db = _harness.NewContext(goalSaves))
        {
            var dayContext = new StubUserDayContext(_harness.DayInfo());
            await new OnboardingStepsService(db, dayContext, _harness.Crypto, new DeviceRegistrationService(db, dayContext))
                .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.JustCurious]), default);
            goalSaves.Saves.ShouldBe(1);
        }

        var hormoneSaves = new CountingSaveInterceptor();
        await using var db2 = _harness.NewContext(hormoneSaves);
        var dayContext2 = new StubUserDayContext(_harness.DayInfo());
        await new OnboardingStepsService(db2, dayContext2, _harness.Crypto, new DeviceRegistrationService(db2, dayContext2))
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([HormoneCatalog.Codes.Fsh]), default);
        hormoneSaves.Saves.ShouldBe(1);
    }

    // ================================================================ §F — the token never reaches a sink

    [Fact]
    public void The_push_token_is_redacted_out_of_a_log_line_under_this_steps_DTO_spelling()
    {
        // T8 owns `PiiRedactionEnricher` and this task does not touch it — what needs proving is that
        // THIS task's DTO member name is inside the net T8 already casts. T8's completeness theory is
        // derived by reflection over the eleven P4a ENTITY types and deliberately excludes
        // `UserDevice`, so `pushToken` is covered only by the hand-maintained name list, and a new DTO
        // carrying the token could slip out of it silently.
        var sink = new CapturingSink();
        using var logger = new LoggerConfiguration()
            .Enrich.With(new PiiRedactionEnricher())
            .WriteTo.Sink(sink)
            .CreateLogger();

        logger.Information(
            "notification step {@Request} {PushToken} {pushToken}",
            new SaveNotificationPrefsRequest(
                [HormoneCatalog.NotificationCategories.DailyCheckin], TokenB, UserDevice.Platforms.Ios),
            TokenB,
            TokenB);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldNotContain(TokenB, Case.Sensitive);
        rendered.ShouldContain("[redacted]");
        rendered.ShouldContain("ios", Case.Sensitive, "the platform is not PII and must stay legible");
    }

    [Fact]
    public async Task The_notification_response_never_carries_the_push_token_in_any_form()
    {
        var result = await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest([], TokenA, UserDevice.Platforms.Ios), default);

        var names = typeof(NotificationPrefsResponse).GetProperties().Select(p => p.Name).ToList();
        names.ShouldNotContain("PushToken");
        names.ShouldNotContain("Token");

        // Belt and braces: no member's VALUE carries it either.
        var saved = SavedOf(result);
        foreach (var category in saved.Categories) category.Code.ShouldNotContain(TokenA);
        saved.DeviceRegistered.ShouldBeTrue();
    }

    // ================================================================ the 404 fence

    [Fact]
    public async Task A_crypto_shredded_user_gets_404_from_all_three_steps_before_validation()
    {
        // The fence that makes an erased account's still-valid JWT inert. Checked BEFORE validation, so
        // a body that would otherwise be a 400 still answers "no such user" and leaks nothing about the
        // shape the server understood — and, on the notification step, before the cross-user device
        // detach, so an erased token cannot be used as an unregister lever.
        var goals = await _harness.NewOnboardingStepsService(info: null)
            .SaveGoalsAsync(new SaveGoalsRequest([]), default);
        goals.ShouldBeOfType<SaveGoalsResult.UserNotFound>();

        var hormones = await _harness.NewOnboardingStepsService(info: null)
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest(null), default);
        hormones.ShouldBeOfType<SaveHormonePrefsResult.UserNotFound>();

        var notifications = await _harness.NewOnboardingStepsService(info: null)
            .SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest(["phase_shifts"], TokenA, "web"), default);
        notifications.ShouldBeOfType<SaveNotificationPrefsResult.UserNotFound>();

        await using var db = _harness.NewContext();
        (await db.UserGoals.CountAsync()).ShouldBe(0);
        (await db.UserHormonePrefs.CountAsync()).ShouldBe(0);
        (await db.UserNotificationPrefs.CountAsync()).ShouldBe(0);
        (await db.UserDevices.CountAsync()).ShouldBe(0);
    }

    // ================================================================ post-completion policy

    [Fact]
    public async Task All_three_steps_stay_callable_AFTER_onboarding_is_completed()
    {
        // These are the same writes the settings screens will make, and the endpoints that would
        // replace them do not ship for several phases (`/settings/hormones` → P6,
        // `/settings/notifications` → P9a). 409-ing them would leave the data uneditable.
        await using (var complete = _harness.NewContext())
        {
            var user = await complete.Users.SingleAsync(u => u.Id == _harness.UserId);
            user.OnboardingCompletedAt = CycleTestHarness.Now;
            await complete.SaveChangesAsync();
        }

        (await _harness.NewOnboardingStepsService()
            .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.JustCurious]), default))
            .ShouldBeOfType<SaveGoalsResult.Saved>();
        (await _harness.NewOnboardingStepsService()
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([HormoneCatalog.Codes.Cortisol]), default))
            .ShouldBeOfType<SaveHormonePrefsResult.Saved>();
        (await _harness.NewOnboardingStepsService()
            .SaveNotificationPrefsAsync(new SaveNotificationPrefsRequest([], null, null), default))
            .ShouldBeOfType<SaveNotificationPrefsResult.Saved>();
    }

    // ================================================================ tenant isolation

    [Fact]
    public async Task One_users_preferences_are_invisible_to_and_untouched_by_another()
    {
        await _harness.NewOnboardingStepsService()
            .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.PlanFertility]), default);
        await _harness.NewOnboardingStepsService()
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([HormoneCatalog.Codes.Lh]), default);
        await _harness.NewOnboardingStepsService().SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest(
                [HormoneCatalog.NotificationCategories.DailyCheckin], TokenA, UserDevice.Platforms.Ios),
            default);

        var other = _harness.DayInfo(userId: _harness.OtherUserId);
        await _harness.NewOnboardingStepsService(other)
            .SaveGoalsAsync(new SaveGoalsRequest([UserGoal.Codes.JustCurious]), default);
        await _harness.NewOnboardingStepsService(other)
            .SaveHormonePrefsAsync(new SaveHormonePrefsRequest([]), default);
        await _harness.NewOnboardingStepsService(other).SaveNotificationPrefsAsync(
            new SaveNotificationPrefsRequest([], TokenB, UserDevice.Platforms.Android), default);

        var reader = _harness.NewOnboardingStepsService();
        SelectedCodes(await reader.ReadGoalsAsync(_harness.UserId, default))
            .ShouldBe(["plan_fertility"], Case.Sensitive);
        ChartedCodes(await reader.ReadHormonePrefsAsync(_harness.UserId, default))
            .ShouldBe(["lh"], Case.Sensitive);
        EnabledCodes(await reader.ReadNotificationPrefsAsync(_harness.UserId, default))
            .ShouldBe(["daily_checkin"], Case.Sensitive);

        SelectedCodes(await reader.ReadGoalsAsync(_harness.OtherUserId, default))
            .ShouldBe(["just_curious"], Case.Sensitive);
        ChartedCodes(await reader.ReadHormonePrefsAsync(_harness.OtherUserId, default)).ShouldBeEmpty();

        await using var db = _harness.NewContext();
        (await db.UserGoals.CountAsync(g => g.UserId == _harness.UserId)).ShouldBe(5);
        (await db.UserGoals.CountAsync(g => g.UserId == _harness.OtherUserId)).ShouldBe(5);
        (await db.UserDevices.CountAsync(d => d.UserId == _harness.UserId)).ShouldBe(1);
        (await db.UserDevices.CountAsync(d => d.UserId == _harness.OtherUserId)).ShouldBe(1);
    }

    // ------------------------------------------------------------------ helpers

    private sealed class CapturingSink : ILogEventSink
    {
        public List<LogEvent> Events { get; } = [];

        public void Emit(LogEvent logEvent) => Events.Add(logEvent);
    }
}

/// <summary>
/// Counts how many times a context reached <c>SaveChanges</c>. Exactly 1 is what §G12's unit-of-work
/// rule requires of a composed write: the endpoint owns ONE retried action and every participant
/// inside it stages only.
/// </summary>
internal sealed class CountingSaveInterceptor : SaveChangesInterceptor
{
    public int Saves { get; private set; }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        Saves++;
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }
}

/// <summary>
/// Fails every <c>SaveChanges</c> with a <see cref="DbUpdateException"/> that is deliberately NOT a
/// Postgres <c>23505</c>, so <see cref="Api.Persistence.ConcurrencyRetry"/> does not retry it and the
/// composed unit of work is observed rolling back whole.
/// </summary>
internal sealed class FailEverySaveInterceptor : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default) =>
        throw new DbUpdateException("the save failed for a reason that is not a lost race");
}
