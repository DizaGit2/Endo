using Lumen.Api.Cycle;
using Lumen.Api.CycleSettings;
using Lumen.Api.Persistence;
using Lumen.Api.Symptoms;
using Lumen.Api.Time;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Lumen.UnitTests.Cycle;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.CycleSettings;

/// <summary>
/// The §C.9 cycle-settings resource (T14): <c>GET</c>/<c>PATCH /settings/cycle</c>, the C-12
/// tracking-pause state machine, and the phase's behavioural proof that <b>clinical bounds never
/// block entry</b> (§G7).
/// </summary>
/// <remarks>
/// <para>Three claims dominate this file.</para>
///
/// <para><b>1. §G7 — the sanity bounds are SOFT.</b> The only rejection is structural (a positive
/// integer that fits <c>smallint</c>). Everything else is <b>stored</b>, with a non-blocking warning
/// code when it falls outside the sanity band. The clinical bounds are clinician-UNSIGNED and appear
/// nowhere in <c>backend/src</c>, so the guard that they never became an entry blocker has to be
/// BEHAVIOURAL: <c>avgCycleLengthDays = 15</c> and <c>= 47</c> are both outside the clinical band and
/// both must come back 200, stored, with an EMPTY warnings list.</para>
///
/// <para><b>2. The settings row and the pause-span history cannot diverge.</b> The three fields on
/// <c>user_cycle_settings</c> are the CURRENT state; <c>cycle_tracking_pause_spans</c> is the history
/// P6 reads. Every write reconciles them, and <see cref="AssertPauseStateIsConsistentAsync"/> is
/// asserted after every transition below rather than at the end of one happy path.</para>
///
/// <para><b>3. <c>ApplyOnboardingCycleAsync</c> must stay COMPOSABLE</b> (§G12's unit-of-work rule).
/// T18's <c>POST /onboarding/cycle</c> calls it while also writing a <c>cycle_events</c> row, so the
/// method must stage only — a <c>SaveChangesAsync</c>, a <c>ChangeTracker.Clear()</c> or a
/// <see cref="ConcurrencyRetry"/> inside it would silently discard T18's other write with no exception
/// and no failing test. Two tests below fail the moment any of those is added.</para>
/// </remarks>
public class CycleSettingsServiceTests : IDisposable
{
    private readonly CycleTestHarness _harness = new();

    public void Dispose()
    {
        _harness.Dispose();
        GC.SuppressFinalize(this);
    }

    // ============================================================== GET /settings/cycle

    [Fact]
    public async Task Get_returns_the_T6_defaults_when_no_row_exists_and_persists_nothing()
    {
        // The choice this endpoint makes: "no row" is NOT a 404. 404 means "no such user" everywhere
        // in P4a (§G12), so spending it on a missing settings row would make an erased account
        // indistinguishable from one whose onboarding cycle step (T18) has not run — and screen 32
        // has to render for both. A GET must also stay safe: materialising a row on read would turn
        // every settings screen open into a write.
        var result = await _harness.NewCycleSettingsService().GetAsync(default);

        var settings = result.ShouldBeOfType<CycleSettingsReadResult.Found>().Settings;
        settings.AvgCycleLengthDays.ShouldBe(28);
        settings.AvgPeriodLengthDays.ShouldBeNull();
        settings.Regularity.ShouldBe("somewhat");
        settings.PhasePredictionEnabled.ShouldBeTrue();
        settings.AutoDetectPeriodStartEnabled.ShouldBeTrue();
        settings.ShowFertilityWindowEnabled.ShouldBeFalse();
        settings.TrackingPaused.ShouldBeFalse();
        settings.PauseReason.ShouldBeNull();
        settings.PausedSince.ShouldBeNull();
        settings.PhasesUnavailable.ShouldBeFalse();
        settings.Warnings.ShouldBeEmpty();

        // Nullable, and null here: the two timestamps are the ONLY thing distinguishing "these are
        // the defaults, nothing was ever saved" from "a row was saved that happens to match them".
        settings.CreatedAt.ShouldBeNull();
        settings.UpdatedAt.ShouldBeNull();

        await using var db = _harness.NewContext();
        (await db.CycleSettings.CountAsync(s => s.UserId == _harness.UserId))
            .ShouldBe(0, "a GET must not write a row");
    }

    [Fact]
    public async Task Get_returns_the_stored_row_when_one_exists()
    {
        _harness.SeedCycleSettings(
            avgCycleLengthDays: 31,
            avgPeriodLengthDays: 6,
            regularity: UserCycleSettings.RegularityValues.Irregular,
            phasePredictionEnabled: false,
            showFertilityWindowEnabled: true);

        var result = await _harness.NewCycleSettingsService().GetAsync(default);

        var settings = result.ShouldBeOfType<CycleSettingsReadResult.Found>().Settings;
        settings.AvgCycleLengthDays.ShouldBe(31);
        settings.AvgPeriodLengthDays.ShouldBe(6);
        settings.Regularity.ShouldBe("irregular");
        settings.PhasePredictionEnabled.ShouldBeFalse();
        settings.ShowFertilityWindowEnabled.ShouldBeTrue();
        settings.CreatedAt.ShouldNotBeNull();
        settings.UpdatedAt.ShouldNotBeNull();
    }

    [Fact]
    public async Task Get_computes_the_sanity_warnings_too_so_screen_32_shows_the_hint_on_load()
    {
        _harness.SeedCycleSettings(avgCycleLengthDays: 200, avgPeriodLengthDays: 45);

        var result = await _harness.NewCycleSettingsService().GetAsync(default);

        result.ShouldBeOfType<CycleSettingsReadResult.Found>().Settings.Warnings.ShouldBe([
            "avg_cycle_length_out_of_sanity_band",
            "avg_period_length_out_of_sanity_band",
        ]);
    }

    [Fact]
    public async Task Get_reads_only_the_callers_row()
    {
        _harness.SeedCycleSettings(userId: _harness.OtherUserId, avgCycleLengthDays: 40);

        var result = await _harness.NewCycleSettingsService().GetAsync(default);

        // Another tenant's row is invisible: the caller sees the unsaved defaults, not 40.
        var settings = result.ShouldBeOfType<CycleSettingsReadResult.Found>().Settings;
        settings.AvgCycleLengthDays.ShouldBe(28);
        settings.CreatedAt.ShouldBeNull();
    }

    [Fact]
    public async Task Get_for_an_erased_user_is_a_404_and_not_a_defaults_body()
    {
        // A crypto-shredded account's JWT stays cryptographically valid until it expires. Answering
        // it with a 200 defaults body would confirm the account exists.
        var result = await _harness.NewCycleSettingsService(info: null).GetAsync(default);

        result.ShouldBeOfType<CycleSettingsReadResult.UserNotFound>();
    }

    // ================================================ §G7 — bounds NEVER block entry

    [Theory]
    [InlineData(15)]  // below the clinical band, inside the sanity band
    [InlineData(47)]  // above the clinical band, inside the sanity band
    [InlineData(10)]  // the sanity band's lower edge, inclusive
    [InlineData(120)] // the sanity band's upper edge, inclusive
    [InlineData(21)]
    [InlineData(45)]
    public async Task An_avg_cycle_length_outside_the_clinical_band_is_accepted_stored_and_UNWARNED(int days)
    {
        // THE PHASE'S BEHAVIOURAL PROOF (§G7). The clinical bounds are clinician-UNSIGNED PO-interim
        // values with no home in backend/src, so nothing here can assert their absence structurally —
        // what can be asserted is that a value they would reject is saved without so much as a hint.
        // 15 and 47 are the two the PO named.
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(AvgCycleLengthDays: days), default);

        var settings = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.AvgCycleLengthDays.ShouldBe(days);
        settings.Warnings.ShouldBeEmpty();

        await using var db = _harness.NewContext();
        (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId))
            .AvgCycleLengthDays.ShouldBe((short)days);
    }

    [Theory]
    [InlineData(9)]
    [InlineData(121)]
    [InlineData(200)]
    [InlineData(365)]
    [InlineData(32767)]
    public async Task An_avg_cycle_length_outside_the_SANITY_band_is_still_STORED_with_one_warning(int days)
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(AvgCycleLengthDays: days), default);

        var settings = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.AvgCycleLengthDays.ShouldBe(days);
        settings.Warnings.ShouldBe(["avg_cycle_length_out_of_sanity_band"]);

        await using var db = _harness.NewContext();
        (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId))
            .AvgCycleLengthDays.ShouldBe((short)days, "a sanity warning is non-blocking — the value is persisted");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(32768)] // one past smallint
    public async Task An_avg_cycle_length_outside_the_STRUCTURAL_domain_is_the_only_rejection(int days)
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(AvgCycleLengthDays: days), default);

        var errors = result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("avgCycleLengthDays");
        errors[0].Message.ShouldBe("value must be between 1 and 32767");

        await using var db = _harness.NewContext();
        (await db.CycleSettings.CountAsync(s => s.UserId == _harness.UserId))
            .ShouldBe(0, "validate-then-act: a rejected request writes nothing");
    }

    [Theory]
    [InlineData(1)]
    [InlineData(10)]
    [InlineData(30)]
    public async Task An_avg_period_length_inside_the_sanity_band_is_stored_unwarned(int days)
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(AvgPeriodLengthDays: days), default);

        var settings = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.AvgPeriodLengthDays.ShouldBe(days);
        settings.Warnings.ShouldBeEmpty();
    }

    [Theory]
    [InlineData(31)]
    [InlineData(90)]
    public async Task An_avg_period_length_outside_the_sanity_band_is_still_STORED_with_one_warning(int days)
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(AvgPeriodLengthDays: days), default);

        var settings = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.AvgPeriodLengthDays.ShouldBe(days);
        settings.Warnings.ShouldBe(["avg_period_length_out_of_sanity_band"]);

        await using var db = _harness.NewContext();
        (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId))
            .AvgPeriodLengthDays.ShouldBe((short)days);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(32768)]
    public async Task An_avg_period_length_outside_the_structural_domain_is_rejected(int days)
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(AvgPeriodLengthDays: days), default);

        var errors = result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("avgPeriodLengthDays");
        errors[0].Message.ShouldBe("value must be between 1 and 32767");
    }

    [Fact]
    public async Task Both_sanity_warnings_arrive_together_in_a_stable_order()
    {
        var result = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(AvgCycleLengthDays: 365, AvgPeriodLengthDays: 90), default);

        result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings.Warnings.ShouldBe([
            "avg_cycle_length_out_of_sanity_band",
            "avg_period_length_out_of_sanity_band",
        ]);
    }

    [Fact]
    public void The_warning_codes_are_frozen()
    {
        // §G12: an endpoint-specific wire string is asserted VERBATIM against its literal, never
        // through the constant — an assertion routed through the constant renames with it.
        CycleSettingsWarnings.AvgCycleLengthOutOfSanityBand.ShouldBe("avg_cycle_length_out_of_sanity_band");
        CycleSettingsWarnings.AvgPeriodLengthOutOfSanityBand.ShouldBe("avg_period_length_out_of_sanity_band");
        CycleSettingsWarnings.All.ShouldBe([
            "avg_cycle_length_out_of_sanity_band",
            "avg_period_length_out_of_sanity_band",
        ]);
    }

    [Fact]
    public void The_endpoint_owned_validation_messages_are_frozen()
    {
        CycleSettingsValidationMessages.PauseFieldRequiresPause
            .ShouldBe("value is only allowed while cycle tracking is paused");
        CycleSettingsValidationMessages.NoFieldsSupplied
            .ShouldBe("at least one settings field is required");
    }

    // ==================================================== PATCH merge semantics

    [Fact]
    public async Task A_patch_naming_one_field_leaves_every_other_field_alone()
    {
        // MERGE, and deliberately so. `user_cycle_settings` is a MULTI-writer row — screen 32's
        // self-report block, screen 32's pause card, and T18's onboarding cycle step all write it —
        // so the deciding test from §G12 ("how many surfaces write the row") lands on merge, and the
        // verb agrees: PATCH's defined meaning is a partial modification. T12 renamed the symptom
        // update to PUT precisely so the verb never lies about which rule applies.
        _harness.SeedCycleSettings(
            avgCycleLengthDays: 31,
            avgPeriodLengthDays: 6,
            regularity: UserCycleSettings.RegularityValues.Regular,
            phasePredictionEnabled: false,
            autoDetectPeriodStartEnabled: false,
            showFertilityWindowEnabled: true);

        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(AvgCycleLengthDays: 29), default);

        var settings = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.AvgCycleLengthDays.ShouldBe(29);
        settings.AvgPeriodLengthDays.ShouldBe(6);
        settings.Regularity.ShouldBe("regular");
        settings.PhasePredictionEnabled.ShouldBeFalse();
        settings.AutoDetectPeriodStartEnabled.ShouldBeFalse();
        settings.ShowFertilityWindowEnabled.ShouldBeTrue();
    }

    [Fact]
    public async Task A_patch_for_a_user_with_no_row_creates_one_carrying_the_T6_defaults()
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(ShowFertilityWindowEnabled: true), default);

        var settings = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.ShowFertilityWindowEnabled.ShouldBeTrue();
        settings.AvgCycleLengthDays.ShouldBe(28);
        settings.Regularity.ShouldBe("somewhat");
        settings.CreatedAt.ShouldBe(CycleTestHarness.Now);
        settings.UpdatedAt.ShouldBe(CycleTestHarness.Now);
    }

    [Fact]
    public async Task An_empty_patch_body_is_rejected_rather_than_materialising_a_row_of_nothing()
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(), default);

        var errors = result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("request");
        errors[0].Message.ShouldBe("at least one settings field is required");

        await using var db = _harness.NewContext();
        (await db.CycleSettings.CountAsync(s => s.UserId == _harness.UserId)).ShouldBe(0);
    }

    [Fact]
    public async Task An_unknown_regularity_is_rejected_and_the_three_ratified_codes_are_accepted()
    {
        var service = _harness.NewCycleSettingsService();
        var rejected = await service.UpdateAsync(
            new UpdateCycleSettingsRequest(Regularity: "chaotic"), default);

        var errors = rejected.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("regularity");
        errors[0].Message.ShouldBe("value is not one of the allowed values");

        foreach (var code in UserCycleSettings.RegularityValues.All)
        {
            var accepted = await _harness.NewCycleSettingsService()
                .UpdateAsync(new UpdateCycleSettingsRequest(Regularity: code), default);
            accepted.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings.Regularity.ShouldBe(code);
        }
    }

    [Fact]
    public async Task Every_field_error_is_collected_before_the_first_write()
    {
        var result = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(
                AvgCycleLengthDays: 0,
                AvgPeriodLengthDays: -3,
                Regularity: "chaotic"),
            default);

        var errors = result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Select(e => e.Field).ShouldBe(["avgCycleLengthDays", "avgPeriodLengthDays", "regularity"]);

        await using var db = _harness.NewContext();
        (await db.CycleSettings.CountAsync(s => s.UserId == _harness.UserId)).ShouldBe(0);
    }

    [Fact]
    public async Task A_patch_for_an_erased_user_is_404_BEFORE_validation_and_before_any_write()
    {
        // The order is the security control, not a formality: a body that would otherwise be a 400
        // must still come back as "no such user", or the shape of the answer tells an erased token
        // that its request was understood.
        var result = await _harness.NewCycleSettingsService(info: null).UpdateAsync(
            new UpdateCycleSettingsRequest(AvgCycleLengthDays: 0, Regularity: "chaotic"), default);

        result.ShouldBeOfType<CycleSettingsUpdateResult.UserNotFound>();

        await using var db = _harness.NewContext();
        (await db.CycleSettings.CountAsync()).ShouldBe(0);
        (await db.CycleTrackingPauseSpans.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task A_patch_writes_only_the_callers_row()
    {
        _harness.SeedCycleSettings(userId: _harness.OtherUserId, avgCycleLengthDays: 40);

        await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(AvgCycleLengthDays: 22), default);

        await using var db = _harness.NewContext();
        (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.OtherUserId))
            .AvgCycleLengthDays.ShouldBe((short)40, "another tenant's settings are untouched");
        (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId))
            .AvgCycleLengthDays.ShouldBe((short)22);
    }

    // ============================================ the C-12 pause state machine

    public static TheoryData<string> AllPauseReasons() =>
        [.. UserCycleSettings.PauseReasons.All];

    [Theory]
    [MemberData(nameof(AllPauseReasons))]
    public async Task Pausing_with_each_of_the_FIVE_reasons_opens_a_span_and_resume_closes_it(string reason)
    {
        // FIVE members (ARCHITECTURE.md §A:59 / C-12, PO-extended 2026-07-14). The r15 three-member
        // list is superseded, and `surgical`/`menopause` are exercised here like any other.
        var paused = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: reason), default);

        var afterPause = paused.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        afterPause.TrackingPaused.ShouldBeTrue();
        afterPause.PauseReason.ShouldBe(reason);
        afterPause.PausedSince.ShouldBe(CycleTestHarness.Today);
        afterPause.PhasesUnavailable.ShouldBeTrue("a paused user must never be shown a phase");
        await AssertPauseStateIsConsistentAsync();

        await using (var db = _harness.NewContext())
        {
            var span = await db.CycleTrackingPauseSpans.AsNoTracking()
                .SingleAsync(s => s.UserId == _harness.UserId);
            span.Reason.ShouldBe(reason);
            span.StartedOn.ShouldBe(CycleTestHarness.Today);
            span.EndedOn.ShouldBeNull();
        }

        // RESUME IS UNCONDITIONAL FOR EVERY REASON — no gate, no confirmation, not even for
        // `pregnancy`. The user owns the switch.
        var resumed = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: false), default);

        var afterResume = resumed.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        afterResume.TrackingPaused.ShouldBeFalse();
        afterResume.PausedSince.ShouldBeNull();
        afterResume.PhasesUnavailable.ShouldBeFalse();
        await AssertPauseStateIsConsistentAsync();

        await using var read = _harness.NewContext();
        var closed = await read.CycleTrackingPauseSpans.AsNoTracking()
            .SingleAsync(s => s.UserId == _harness.UserId);
        closed.EndedOn.ShouldBe(CycleTestHarness.Today);
        closed.Reason.ShouldBe(reason, "the history keeps the reason the pause was taken for");
    }

    [Fact]
    public async Task Resume_preserves_the_pause_reason_so_the_next_pause_can_pre_select_it()
    {
        // ARCHITECTURE.md §D (`user_cycle_settings`, authoritative): "resume clears the flag and the
        // date but preserves the reason so the next pause can pre-select it", which is exactly why
        // there is deliberately no CHECK tying `pause_reason` to `tracking_paused`. So the invariant
        // this service holds is `TrackingPaused == (PausedSince != null)` and
        // `TrackingPaused ⇒ PauseReason != null` — NOT that all three are null together.
        var service = _harness.NewCycleSettingsService();
        await service.UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Surgical),
            default);

        var resumed = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: false), default);

        var settings = resumed.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.TrackingPaused.ShouldBeFalse();
        settings.PausedSince.ShouldBeNull();
        settings.PauseReason.ShouldBe("surgical", "remembered for the next pause, never read as 'is paused'");
        await AssertPauseStateIsConsistentAsync();
    }

    [Fact]
    public async Task Pausing_without_a_reason_is_rejected()
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: true), default);

        var errors = result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("pauseReason");
        errors[0].Message.ShouldBe("value is required");

        await using var db = _harness.NewContext();
        (await db.CycleTrackingPauseSpans.CountAsync()).ShouldBe(0);
        (await db.CycleSettings.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task Pausing_with_a_reason_outside_the_five_member_set_is_rejected()
    {
        var result = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: "lactation"), default);

        var errors = result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("pauseReason");
        errors[0].Message.ShouldBe("value is not one of the allowed values");
    }

    [Fact]
    public async Task Supplying_a_pause_reason_with_trackingPaused_false_is_rejected()
    {
        var result = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(
                TrackingPaused: false,
                PauseReason: UserCycleSettings.PauseReasons.Pregnancy),
            default);

        var errors = result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("pauseReason");
        errors[0].Message.ShouldBe("value is only allowed while cycle tracking is paused");
    }

    [Fact]
    public async Task Supplying_pausedSince_with_trackingPaused_false_is_rejected()
    {
        var result = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: false, PausedSince: CycleTestHarness.Today),
            default);

        var errors = result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("pausedSince");
        errors[0].Message.ShouldBe("value is only allowed while cycle tracking is paused");
    }

    [Fact]
    public async Task Supplying_a_pause_field_while_not_paused_and_not_pausing_is_rejected()
    {
        // `trackingPaused` omitted and the user is not paused: a bare reason would set a "remembered"
        // reason nobody asked for, so it is refused rather than silently stored.
        var result = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(PauseReason: UserCycleSettings.PauseReasons.Other), default);

        result.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors[0]
            .Message.ShouldBe("value is only allowed while cycle tracking is paused");
    }

    [Fact]
    public async Task A_future_pausedSince_is_rejected_and_there_is_no_backdate_floor()
    {
        var future = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(
                TrackingPaused: true,
                PauseReason: UserCycleSettings.PauseReasons.Menopause,
                PausedSince: CycleTestHarness.Today.AddDays(1)),
            default);

        var errors = future.ShouldBeOfType<CycleSettingsUpdateResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("pausedSince");
        errors[0].Message.ShouldBe("date must not be in the future");

        // §G8: the backdate floor is cycle_events-only. A pause that began years ago is real history
        // and must not be refused — the floor here would reject a genuine menopause start date.
        var old = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(
                TrackingPaused: true,
                PauseReason: UserCycleSettings.PauseReasons.Menopause,
                PausedSince: CycleTestHarness.Floor.AddYears(-5)),
            default);

        old.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings
            .PausedSince.ShouldBe(CycleTestHarness.Floor.AddYears(-5));
        await AssertPauseStateIsConsistentAsync();
    }

    [Fact]
    public async Task A_second_pause_while_already_paused_updates_the_open_span_IN_PLACE()
    {
        // The double-tap. `cycle_tracking_pause_spans` carries a partial UNIQUE on
        // `(UserId) WHERE "EndedOn" IS NULL`, so a blind second insert is a 23505 surfacing as a 500.
        // The index is the backstop; this is the behaviour.
        var service = _harness.NewCycleSettingsService();
        await service.UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Pregnancy),
            default);

        Guid firstSpanId;
        await using (var db = _harness.NewContext())
            firstSpanId = (await db.CycleTrackingPauseSpans.AsNoTracking().SingleAsync()).Id;

        var again = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Pregnancy),
            default);

        again.ShouldBeOfType<CycleSettingsUpdateResult.Saved>();
        await AssertPauseStateIsConsistentAsync();

        await using var read = _harness.NewContext();
        var spans = await read.CycleTrackingPauseSpans.AsNoTracking()
            .Where(s => s.UserId == _harness.UserId).ToListAsync();
        spans.Count.ShouldBe(1, "a double pause must not fork the history into two spans");
        spans[0].Id.ShouldBe(firstSpanId);
        spans[0].EndedOn.ShouldBeNull();
    }

    [Fact]
    public async Task Re_pausing_while_paused_with_a_NEW_pausedSince_moves_the_open_spans_StartedOn()
    {
        // Pins the reconciliation's most fragile line (CycleSettingsService.ReconcilePauseAsync,
        // `openSpan.StartedOn = startedOn;` in the "already open" branch). Every OTHER re-pause test in
        // this file either omits `pausedSince` or repeats the value already on the row, so `startedOn`
        // always equals the open span's existing `StartedOn` and deleting that one assignment does not
        // fail a single one of them. This is the one case where they differ: an already-paused user
        // PATCHes a `pausedSince` on a DIFFERENT day. If the span does not move with it,
        // `user_cycle_settings.PausedSince` and `cycle_tracking_pause_spans.StartedOn` silently
        // diverge in exactly the history P6 estimates from — caught below by the shared
        // AssertPauseStateIsConsistentAsync invariant, not a hand-rolled equality.
        var originalStart = CycleTestHarness.Today.AddDays(-10);
        _harness.SeedCycleSettings(
            trackingPaused: true,
            pauseReason: UserCycleSettings.PauseReasons.Surgical,
            pausedSince: originalStart);
        _harness.SeedPauseSpan(UserCycleSettings.PauseReasons.Surgical, originalStart);

        // `trackingPaused`/`pauseReason` omitted on purpose — this is the brief's "or `pausedSince`
        // alone" variant, and merge keeps the already-paused user paused with the same reason.
        var newStart = CycleTestHarness.Today.AddDays(-3);
        var moved = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(PausedSince: newStart), default);

        moved.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings.PausedSince.ShouldBe(newStart);
        await AssertPauseStateIsConsistentAsync();
    }

    [Fact]
    public async Task Changing_the_reason_while_paused_updates_the_open_span_in_place()
    {
        await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.HormonalSuppression),
            default);

        // `trackingPaused` omitted: under merge that leaves the flag alone, and the reason still moves.
        var changed = await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(PauseReason: UserCycleSettings.PauseReasons.Surgical), default);

        var settings = changed.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.TrackingPaused.ShouldBeTrue();
        settings.PauseReason.ShouldBe("surgical");
        await AssertPauseStateIsConsistentAsync();

        await using var db = _harness.NewContext();
        var spans = await db.CycleTrackingPauseSpans.AsNoTracking()
            .Where(s => s.UserId == _harness.UserId).ToListAsync();
        spans.Count.ShouldBe(1);
        spans[0].Reason.ShouldBe("surgical");
        spans[0].EndedOn.ShouldBeNull();
    }

    [Fact]
    public async Task Re_pausing_while_paused_without_a_reason_keeps_the_current_one()
    {
        await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Other),
            default);

        var again = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: true), default);

        again.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings.PauseReason.ShouldBe("other");
        await AssertPauseStateIsConsistentAsync();
    }

    [Fact]
    public async Task Resuming_when_not_paused_is_an_idempotent_200_that_touches_no_span()
    {
        var result = await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: false), default);

        var settings = result.ShouldBeOfType<CycleSettingsUpdateResult.Saved>().Settings;
        settings.TrackingPaused.ShouldBeFalse();
        settings.PauseReason.ShouldBeNull();
        settings.PausedSince.ShouldBeNull();

        await using var db = _harness.NewContext();
        (await db.CycleTrackingPauseSpans.CountAsync()).ShouldBe(0, "there was no span to close");
        await AssertPauseStateIsConsistentAsync();
    }

    [Fact]
    public async Task Resuming_twice_closes_the_span_once_and_does_not_reopen_or_re_close_it()
    {
        await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Pregnancy),
            default);
        await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: false), default);

        // A genuinely LATER day, not just a later instant: if the second resume re-closed the span it
        // would stamp this date, and the assertion below would catch it.
        await _harness.NewCycleSettingsService(_harness.DayInfo(
                now: CycleTestHarness.Now.AddDays(10), today: CycleTestHarness.Today.AddDays(10)))
            .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: false), default);

        await using var db = _harness.NewContext();
        var spans = await db.CycleTrackingPauseSpans.AsNoTracking()
            .Where(s => s.UserId == _harness.UserId).ToListAsync();
        spans.Count.ShouldBe(1);
        spans[0].EndedOn.ShouldBe(CycleTestHarness.Today, "the second resume must not move the close date");
        await AssertPauseStateIsConsistentAsync();
    }

    [Fact]
    public async Task Resume_closes_the_span_on_the_LATER_of_today_and_the_start()
    {
        // Defensive: `EndedOn = max(today, StartedOn)`. A span can only start in the past through this
        // endpoint, but a row seeded by another path must never produce EndedOn < StartedOn, which
        // would be a negative-length span in the history P6 estimates from.
        _harness.SeedCycleSettings(
            trackingPaused: true,
            pauseReason: UserCycleSettings.PauseReasons.Pregnancy,
            pausedSince: CycleTestHarness.Today.AddDays(30));
        _harness.SeedPauseSpan(UserCycleSettings.PauseReasons.Pregnancy, CycleTestHarness.Today.AddDays(30));

        await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: false), default);

        await using var db = _harness.NewContext();
        var span = await db.CycleTrackingPauseSpans.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId);
        span.EndedOn.ShouldBe(CycleTestHarness.Today.AddDays(30));
        span.EndedOn!.Value.ShouldBeGreaterThanOrEqualTo(span.StartedOn);
    }

    [Fact]
    public async Task Pausing_again_after_a_resume_opens_a_SECOND_span_and_leaves_the_first_closed()
    {
        var service = _harness.NewCycleSettingsService();
        await service.UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Pregnancy),
            default);
        await _harness.NewCycleSettingsService()
            .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: false), default);

        var laterDay = CycleTestHarness.Today.AddDays(200);
        await _harness.NewCycleSettingsService(_harness.DayInfo(
                now: CycleTestHarness.Now.AddDays(200), today: laterDay)).UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Menopause),
            default);

        await using var db = _harness.NewContext();
        var spans = await db.CycleTrackingPauseSpans.AsNoTracking()
            .Where(s => s.UserId == _harness.UserId).OrderBy(s => s.StartedOn).ToListAsync();
        spans.Count.ShouldBe(2, "the pause HISTORY is what P6 excludes from its estimators");
        spans[0].EndedOn.ShouldBe(CycleTestHarness.Today);
        spans[0].Reason.ShouldBe("pregnancy");
        spans[1].EndedOn.ShouldBeNull();
        spans[1].StartedOn.ShouldBe(laterDay, "a fresh pause starts on the day it was taken");
        spans[1].Reason.ShouldBe("menopause");
        await AssertPauseStateIsConsistentAsync();
    }

    [Fact]
    public async Task The_settings_row_and_the_pause_span_cannot_diverge_across_a_whole_pause_lifecycle()
    {
        var reasons = UserCycleSettings.PauseReasons.All;

        for (var step = 0; step < reasons.Count; step++)
        {
            var offset = step * 30;
            var day = _harness.DayInfo(
                now: CycleTestHarness.Now.AddDays(offset), today: CycleTestHarness.Today.AddDays(offset));

            await _harness.NewCycleSettingsService(day).UpdateAsync(
                new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: reasons[step]), default);
            await AssertPauseStateIsConsistentAsync();

            // Double-tap in the same state, then resume, then resume again from the resumed state.
            await _harness.NewCycleSettingsService(day).UpdateAsync(
                new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: reasons[step]), default);
            await AssertPauseStateIsConsistentAsync();

            var nextDay = _harness.DayInfo(
                now: CycleTestHarness.Now.AddDays(offset + 1), today: CycleTestHarness.Today.AddDays(offset + 1));
            await _harness.NewCycleSettingsService(nextDay)
                .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: false), default);
            await AssertPauseStateIsConsistentAsync();

            await _harness.NewCycleSettingsService(nextDay)
                .UpdateAsync(new UpdateCycleSettingsRequest(TrackingPaused: false), default);
            await AssertPauseStateIsConsistentAsync();
        }

        await using var db = _harness.NewContext();
        var spans = await db.CycleTrackingPauseSpans.AsNoTracking()
            .Where(s => s.UserId == _harness.UserId).OrderBy(s => s.StartedOn).ToListAsync();
        spans.Count.ShouldBe(reasons.Count, "one closed span per pause/resume cycle, and not one more");
        spans.ShouldAllBe(s => s.EndedOn != null);
        spans.Select(s => s.Reason).ShouldBe(reasons);
    }

    [Fact]
    public async Task A_pause_span_belongs_to_its_own_tenant()
    {
        _harness.SeedCycleSettings(
            userId: _harness.OtherUserId,
            trackingPaused: true,
            pauseReason: UserCycleSettings.PauseReasons.Pregnancy,
            pausedSince: CycleTestHarness.Today.AddDays(-5));
        _harness.SeedPauseSpan(
            UserCycleSettings.PauseReasons.Pregnancy,
            CycleTestHarness.Today.AddDays(-5),
            userId: _harness.OtherUserId);

        await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Other),
            default);

        await using var db = _harness.NewContext();
        var theirs = await db.CycleTrackingPauseSpans.AsNoTracking()
            .SingleAsync(s => s.UserId == _harness.OtherUserId);
        theirs.EndedOn.ShouldBeNull("the other tenant's open span is untouched");
        theirs.Reason.ShouldBe("pregnancy");
        (await db.CycleTrackingPauseSpans.CountAsync(s => s.UserId == _harness.UserId)).ShouldBe(1);
    }

    // ============================================ the one derived flag (no engine)

    [Theory]
    [InlineData(false, true, false)]
    [InlineData(true, true, true)]
    [InlineData(false, false, true)]
    [InlineData(true, false, true)]
    public async Task PhasesUnavailable_is_the_boolean_OR_of_paused_and_prediction_disabled(
        bool trackingPaused, bool phasePredictionEnabled, bool expected)
    {
        // The explicit "phases unavailable" state ARCHITECTURE.md §A:59 requires — and NOTHING more:
        // an OR of two stored flags, derived on the way out, persisted nowhere. §G6 bars any engine,
        // so this must stay incapable of inferring anything.
        _harness.SeedCycleSettings(
            phasePredictionEnabled: phasePredictionEnabled,
            trackingPaused: trackingPaused,
            pauseReason: trackingPaused ? UserCycleSettings.PauseReasons.Pregnancy : null,
            pausedSince: trackingPaused ? CycleTestHarness.Today : null);

        var result = await _harness.NewCycleSettingsService().GetAsync(default);

        result.ShouldBeOfType<CycleSettingsReadResult.Found>().Settings
            .PhasesUnavailable.ShouldBe(expected);
    }

    [Fact]
    public async Task The_response_carries_no_hormone_range_flag_and_no_phase_or_confidence_key()
    {
        // §G6 / the T14 scope note: `hormoneRangeInterpretationEnabled` is NOT emitted — it encodes
        // the clinician-UNSIGNED C-12 pregnancy rule, and its only consumers (P6/P7b hormone ranges)
        // do not exist. P4a persists `trackingPaused` + `pauseReason`, which is all they need.
        await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Pregnancy),
            default);

        var names = typeof(CycleSettingsResponse).GetProperties().Select(p => p.Name).ToList();
        names.ShouldNotContain("HormoneRangeInterpretationEnabled");
        names.ShouldNotContain("Phase");
        names.ShouldNotContain("CycleDay");
        names.ShouldNotContain("Confidence");
        names.ShouldNotContain("NextPeriodPredictedOn");
    }

    // ================================ C-12's other half: a pause never blocks entry

    [Fact]
    public async Task A_paused_user_can_still_log_a_cycle_event_a_day_a_checkin_and_symptoms()
    {
        // C-12: "while paused, no predictions" — NOT "while paused, no logging". The whole reason the
        // pause exists is that the user is still living in their body; refusing their entries would
        // lose the observations P6 needs the moment the pause ends.
        await _harness.NewCycleSettingsService().UpdateAsync(
            new UpdateCycleSettingsRequest(TrackingPaused: true, PauseReason: UserCycleSettings.PauseReasons.Pregnancy),
            default);

        var day = CycleTestHarness.Today;

        (await _harness.NewService().LogEventAsync(
            new LogCycleEventRequest(CycleEvent.Kinds.Spotting, day, 2, null), default))
            .ShouldBeOfType<CycleEventResult.Saved>();

        (await _harness.NewDayService().UpsertDayAsync(day, new LogCycleDayRequest(5, 3, null), default))
            .ShouldBeOfType<CycleDayResult.Saved>();

        (await _harness.NewDayService().QuickCheckinAsync(new QuickCheckinRequest(4, null), default))
            .ShouldBeOfType<QuickCheckinResult.Saved>();

        (await _harness.NewSymptomService().CreateAsync(
            new CreateSymptomsRequest([new SymptomEntryInput("bloating", 6, null, null, null, null, null, null)]),
            default))
            .ShouldBeOfType<SymptomCreateResult.Saved>();

        await using var db = _harness.NewContext();
        (await db.CycleEvents.CountAsync(e => e.UserId == _harness.UserId)).ShouldBe(1);
        (await db.CycleDayLogs.CountAsync(l => l.UserId == _harness.UserId)).ShouldBe(1);
        (await db.Symptoms.CountAsync(s => s.UserId == _harness.UserId)).ShouldBe(1);
        (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId))
            .TrackingPaused.ShouldBeTrue("the pause survived the logging");
    }

    // ============================ ApplyOnboardingCycleAsync (shared with T18/B15)

    [Fact]
    public async Task ApplyOnboardingCycleAsync_creates_the_row_applying_the_T6_defaults_for_omitted_values()
    {
        await using var db = _harness.NewContext();
        var service = new CycleSettingsService(db, new StubUserDayContext(_harness.DayInfo()));

        var row = await service.ApplyOnboardingCycleAsync(
            _harness.UserId, null, null, null, CycleTestHarness.Now, default);
        await db.SaveChangesAsync();

        row.AvgCycleLengthDays.ShouldBe((short)28);
        row.AvgPeriodLengthDays.ShouldBeNull();
        row.Regularity.ShouldBe("somewhat");
        row.CreatedAt.ShouldBe(CycleTestHarness.Now);

        await using var read = _harness.NewContext();
        var stored = await read.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId);
        stored.AvgCycleLengthDays.ShouldBe((short)28);
        stored.Regularity.ShouldBe("somewhat");
    }

    [Fact]
    public async Task ApplyOnboardingCycleAsync_updates_an_existing_row_without_touching_the_pause_triple()
    {
        _harness.SeedCycleSettings(
            avgCycleLengthDays: 40,
            trackingPaused: true,
            pauseReason: UserCycleSettings.PauseReasons.Surgical,
            pausedSince: CycleTestHarness.Today.AddDays(-9));
        _harness.SeedPauseSpan(UserCycleSettings.PauseReasons.Surgical, CycleTestHarness.Today.AddDays(-9));

        await using (var db = _harness.NewContext())
        {
            var service = new CycleSettingsService(db, new StubUserDayContext(_harness.DayInfo()));
            await service.ApplyOnboardingCycleAsync(
                _harness.UserId, 30, 5, UserCycleSettings.RegularityValues.Regular, CycleTestHarness.Now, default);
            await db.SaveChangesAsync();
        }

        await using var read = _harness.NewContext();
        var stored = await read.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId);
        stored.AvgCycleLengthDays.ShouldBe((short)30);
        stored.AvgPeriodLengthDays.ShouldBe((short)5);
        stored.Regularity.ShouldBe("regular");
        stored.TrackingPaused.ShouldBeTrue("no PauseReason side effects — onboarding does not resume a pause");
        stored.PauseReason.ShouldBe("surgical");
        stored.PausedSince.ShouldBe(CycleTestHarness.Today.AddDays(-9));
        (await read.CycleTrackingPauseSpans.CountAsync(s => s.UserId == _harness.UserId && s.EndedOn == null))
            .ShouldBe(1, "no span was opened or closed");
        await AssertPauseStateIsConsistentAsync();
    }

    [Fact]
    public async Task ApplyOnboardingCycleAsync_STAGES_ONLY_so_T18_can_compose_it_with_another_write()
    {
        // §G12's unit-of-work rule, enforced rather than documented. `ConcurrencyRetry` recovers via
        // `ChangeTracker.Clear()`, a WHOLE-CONTEXT operation on the request-scoped LumenDbContext, so
        // a `SaveChangesAsync`, a `Clear()` or a retry of its own inside this method would silently
        // discard whatever T18 staged alongside it — no exception, no failing test. THIS is that test:
        // it stages a cycle_events row first (T18's `lastPeriodStart` write), calls the method, and
        // fails if either write is lost.
        await using var db = _harness.NewContext();
        var service = new CycleSettingsService(db, new StubUserDayContext(_harness.DayInfo()));

        var stagedEvent = new CycleEvent
        {
            Id = Guid.NewGuid(),
            UserId = _harness.UserId,
            Kind = CycleEvent.Kinds.PeriodStart,
            OccurredOn = CycleTestHarness.Today.AddDays(-3),
            Source = CycleEvent.Sources.Onboarding,
            CreatedAt = CycleTestHarness.Now,
            UpdatedAt = CycleTestHarness.Now,
        };
        db.CycleEvents.Add(stagedEvent);

        await service.ApplyOnboardingCycleAsync(
            _harness.UserId, 30, 5, UserCycleSettings.RegularityValues.Regular, CycleTestHarness.Now, default);

        // 1. It did not save: nothing is in the database yet, not even the settings row.
        await using (var beforeSave = _harness.NewContext())
        {
            (await beforeSave.CycleSettings.CountAsync()).ShouldBe(
                0, "ApplyOnboardingCycleAsync must not call SaveChangesAsync — the caller owns the save");
            (await beforeSave.CycleEvents.CountAsync()).ShouldBe(0);
        }

        // 2. It did not clear the tracker: T18's staged row is still there, still Added.
        db.Entry(stagedEvent).State.ShouldBe(
            EntityState.Added,
            "ApplyOnboardingCycleAsync must not call ChangeTracker.Clear() (nor ConcurrencyRetry, " +
            "which clears): doing so silently discards the caller's other staged write");

        // 3. One save lands both.
        await db.SaveChangesAsync();

        await using var read = _harness.NewContext();
        (await read.CycleEvents.CountAsync(e => e.UserId == _harness.UserId))
            .ShouldBe(1, "T18's cycle_events row survived the composition");
        (await read.CycleSettings.CountAsync(s => s.UserId == _harness.UserId)).ShouldBe(1);
    }

    [Fact]
    public async Task ApplyOnboardingCycleAsync_composes_inside_ONE_ConcurrencyRetry_action_the_way_T18_will()
    {
        // The shape §G12 prescribes for T18: the ENDPOINT owns exactly one retried action wrapping the
        // whole unit of work, and every participant inside it stages only.
        await using var db = _harness.NewContext();
        var service = new CycleSettingsService(db, new StubUserDayContext(_harness.DayInfo()));

        var saved = await ConcurrencyRetry.ExecuteAsync(async token =>
        {
            db.ChangeTracker.Clear();

            db.CycleEvents.Add(new CycleEvent
            {
                Id = Guid.NewGuid(),
                UserId = _harness.UserId,
                Kind = CycleEvent.Kinds.PeriodStart,
                OccurredOn = CycleTestHarness.Today.AddDays(-3),
                Source = CycleEvent.Sources.Onboarding,
                CreatedAt = CycleTestHarness.Now,
                UpdatedAt = CycleTestHarness.Now,
            });

            var settings = await service.ApplyOnboardingCycleAsync(
                _harness.UserId, 27, null, null, CycleTestHarness.Now, token);

            await db.SaveChangesAsync(token);
            return settings.AvgCycleLengthDays;
        }, default);

        saved.ShouldBe((short)27);

        await using var read = _harness.NewContext();
        (await read.CycleEvents.CountAsync(e => e.UserId == _harness.UserId)).ShouldBe(1);
        (await read.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == _harness.UserId))
            .AvgCycleLengthDays.ShouldBe((short)27);
    }

    [Fact]
    public async Task ApplyOnboardingCycleAsync_refuses_a_value_its_caller_should_have_rejected()
    {
        // A programming-error guard, not user input: T18 owns the 400. Storing garbage silently would
        // corrupt a column P6 reads, so this throws loudly and T18's own tests catch it immediately.
        await using var db = _harness.NewContext();
        var service = new CycleSettingsService(db, new StubUserDayContext(_harness.DayInfo()));

        await Should.ThrowAsync<ArgumentException>(async () => await service.ApplyOnboardingCycleAsync(
            _harness.UserId, 28, null, "chaotic", CycleTestHarness.Now, default));

        await Should.ThrowAsync<ArgumentOutOfRangeException>(async () => await service.ApplyOnboardingCycleAsync(
            _harness.UserId, 0, null, null, CycleTestHarness.Now, default));

        await Should.ThrowAsync<ArgumentOutOfRangeException>(async () => await service.ApplyOnboardingCycleAsync(
            _harness.UserId, 28, 0, null, CycleTestHarness.Now, default));
    }

    [Fact]
    public async Task ApplyOnboardingCycleAsync_accepts_a_self_report_the_clinical_bounds_would_refuse()
    {
        // §G7 again, on the other write path: onboarding screen 3 must not be an entry blocker either.
        await using var db = _harness.NewContext();
        var service = new CycleSettingsService(db, new StubUserDayContext(_harness.DayInfo()));

        var row = await service.ApplyOnboardingCycleAsync(
            _harness.UserId, 15, 12, null, CycleTestHarness.Now, default);
        await db.SaveChangesAsync();

        row.AvgCycleLengthDays.ShouldBe((short)15);
        row.AvgPeriodLengthDays.ShouldBe((short)12);
    }

    // ------------------------------------------------------------------ helpers

    /// <summary>
    /// The invariants the settings row and the pause-span history must satisfy after EVERY write.
    /// </summary>
    /// <remarks>
    /// <para><c>TrackingPaused == (PausedSince != null)</c> and <c>TrackingPaused ⇒ PauseReason != null</c>.
    /// <b>Not</b> "all three are null together": ARCHITECTURE.md §D states that resume clears the flag
    /// and the date but PRESERVES the reason so the next pause can pre-select it, which is why there is
    /// deliberately no CHECK tying the two columns.</para>
    ///
    /// <para>Exactly one OPEN span while paused and none while resumed, with the open span's
    /// <c>Reason</c>/<c>StartedOn</c> equal to the settings row's — so the current state and the
    /// history P6 reads can never disagree — and no closed span of negative length.</para>
    /// </remarks>
    private async Task AssertPauseStateIsConsistentAsync()
    {
        await using var db = _harness.NewContext();
        var row = await db.CycleSettings.AsNoTracking().FirstOrDefaultAsync(s => s.UserId == _harness.UserId);
        var spans = await db.CycleTrackingPauseSpans.AsNoTracking()
            .Where(s => s.UserId == _harness.UserId).ToListAsync();
        var open = spans.Where(s => s.EndedOn is null).ToList();

        foreach (var closed in spans.Where(s => s.EndedOn is not null))
            closed.EndedOn!.Value.ShouldBeGreaterThanOrEqualTo(closed.StartedOn, "a span cannot end before it began");

        if (row is null)
        {
            open.ShouldBeEmpty("no settings row means the user was never paused");
            return;
        }

        (row.PausedSince is not null).ShouldBe(row.TrackingPaused, "the flag and the date move together");
        open.Count.ShouldBe(row.TrackingPaused ? 1 : 0, "at most one OPEN span, and only while paused");

        if (!row.TrackingPaused) return;

        row.PauseReason.ShouldNotBeNull("a paused user always has a reason");
        open[0].Reason.ShouldBe(row.PauseReason);
        open[0].StartedOn.ShouldBe(row.PausedSince!.Value);
    }
}
