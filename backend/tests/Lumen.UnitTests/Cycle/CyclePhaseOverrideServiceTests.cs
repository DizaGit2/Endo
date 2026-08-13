using Lumen.Api.Cycle;
using Lumen.Api.Validation;
using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Cycle;

/// <summary>
/// <c>POST /cycle/phase-override</c> (screen 14) — replace-the-set for exactly one cycle.
///
/// <para><b>P4a stores; it does not interpret (§G6).</b> Every guard asserted here is STRUCTURAL:
/// the cycle must exist as a logged <c>period_start</c>, and each boundary must fall inside that
/// cycle's window. There is deliberately NO monotonicity guard — menstrual→follicular→ovulatory→
/// luteal is the C-01 band order, clinician-UNSIGNED, and rejecting a user's own correction on that
/// basis would be exactly the clinical entry blocker rider 7 forbids.</para>
///
/// <para><b>§G9:</b> <c>cycle_phase_overrides</c> is under the UNFILTERED unique-index regime too —
/// <c>(UserId, CycleStartOn, Phase, Boundary)</c> spans tombstones — so re-correcting a boundary
/// after a retraction must revive the same row, not insert a second one.</para>
/// </summary>
public sealed class CyclePhaseOverrideServiceTests : IDisposable
{
    private static readonly DateOnly CycleStart = new(2026, 7, 10);

    /// <summary>
    /// The following logged <c>period_start</c> in the window tests. Deliberately still on or before
    /// <see cref="CycleTestHarness.Today"/> so the "next period start" rule is what rejects a date,
    /// not the future-date rule that would otherwise mask it.
    /// </summary>
    private static readonly DateOnly NextStart = CycleStart.AddDays(20);

    private readonly CycleTestHarness _harness = new();

    public CyclePhaseOverrideServiceTests() =>
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleStart);

    public void Dispose() => _harness.Dispose();

    private static PhaseOverrideInput Boundary(
        string phase = CyclePhaseOverride.Phases.Menstrual,
        string boundary = CyclePhaseOverride.Boundaries.End,
        DateOnly? occurredOn = null) =>
        new(phase, boundary, occurredOn ?? CycleStart.AddDays(5));

    private static SavePhaseOverridesRequest Request(params PhaseOverrideInput[] boundaries) =>
        new(CycleStart, boundaries);

    private static IReadOnlyList<string> MessagesFor(PhaseOverrideResult result, string field) =>
        result.ShouldBeOfType<PhaseOverrideResult.Invalid>().Errors
            .Where(e => e.Field == field).Select(e => e.Message).ToList();

    private List<CyclePhaseOverride> AllRows() =>
        _harness.NewContext().CyclePhaseOverrides.IgnoreQueryFilters()
            .Where(o => o.UserId == _harness.UserId).ToList();

    private List<CyclePhaseOverride> LiveRows() =>
        _harness.NewContext().CyclePhaseOverrides.Where(o => o.UserId == _harness.UserId).ToList();

    // --- cycleStartOn must be a live logged period_start --------------------------------

    [Fact]
    public async Task A_cycle_start_with_no_logged_period_start_is_rejected()
    {
        var result = await _harness.NewService().SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(CycleStart.AddDays(-3), [Boundary(occurredOn: CycleStart.AddDays(-1))]),
            CancellationToken.None);

        MessagesFor(result, "cycleStartOn").ShouldBe([CycleValidationMessages.NoMatchingPeriodStart]);
        AllRows().ShouldBeEmpty();
    }

    [Fact]
    public async Task A_soft_deleted_period_start_no_longer_anchors_a_cycle()
    {
        var deletedStart = new DateOnly(2026, 5, 1);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, deletedStart, deletedAt: CycleTestHarness.Now);

        var result = await _harness.NewService().SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(deletedStart, [Boundary(occurredOn: deletedStart.AddDays(2))]),
            CancellationToken.None);

        MessagesFor(result, "cycleStartOn").ShouldBe([CycleValidationMessages.NoMatchingPeriodStart]);
    }

    [Fact]
    public async Task Another_users_period_start_does_not_anchor_this_users_cycle()
    {
        var theirStart = new DateOnly(2026, 6, 1);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, theirStart, userId: _harness.OtherUserId);

        var result = await _harness.NewService().SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(theirStart, [Boundary(occurredOn: theirStart.AddDays(2))]),
            CancellationToken.None);

        MessagesFor(result, "cycleStartOn").ShouldBe([CycleValidationMessages.NoMatchingPeriodStart]);
    }

    [Fact]
    public async Task A_period_end_on_that_day_does_not_anchor_a_cycle()
    {
        var endOnly = new DateOnly(2026, 6, 20);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodEnd, endOnly);

        var result = await _harness.NewService().SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(endOnly, [Boundary(occurredOn: endOnly.AddDays(1))]),
            CancellationToken.None);

        MessagesFor(result, "cycleStartOn").ShouldBe([CycleValidationMessages.NoMatchingPeriodStart]);
    }

    [Fact]
    public async Task Missing_cycle_start_is_rejected()
    {
        var result = await _harness.NewService().SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(null, [Boundary()]), CancellationToken.None);

        MessagesFor(result, "cycleStartOn").ShouldBe([ValidationMessages.Required]);
    }

    [Fact]
    public async Task Missing_boundaries_is_rejected_rather_than_treated_as_a_reset()
    {
        // An omitted collection must never silently retract the user's corrections — the reset is
        // `boundaries: []`, and only that.
        _harness.SeedOverride(CycleStart, CyclePhaseOverride.Phases.Menstrual, CyclePhaseOverride.Boundaries.End, CycleStart.AddDays(4));

        var result = await _harness.NewService().SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(CycleStart, null), CancellationToken.None);

        MessagesFor(result, "boundaries").ShouldBe([ValidationMessages.Required]);
        LiveRows().Count.ShouldBe(1);
    }

    // --- per-boundary vocabulary --------------------------------------------------------

    [Theory]
    [InlineData(CyclePhaseOverride.Phases.Menstrual)]
    [InlineData(CyclePhaseOverride.Phases.Follicular)]
    [InlineData(CyclePhaseOverride.Phases.Ovulatory)]
    [InlineData(CyclePhaseOverride.Phases.Luteal)]
    public async Task Every_ratified_phase_is_accepted(string phase)
    {
        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(phase: phase)), CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.Saved>().Overrides.Boundaries.Single().Phase.ShouldBe(phase);
    }

    [Fact]
    public async Task An_unknown_phase_is_rejected_under_its_indexed_key()
    {
        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(phase: "postmenstrual")), CancellationToken.None);

        MessagesFor(result, "boundaries[0].phase").ShouldBe([ValidationMessages.NotAllowedValue]);
        AllRows().ShouldBeEmpty();
    }

    [Fact]
    public async Task An_unknown_boundary_is_rejected_under_its_indexed_key()
    {
        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(), Boundary(boundary: "middle")), CancellationToken.None);

        MessagesFor(result, "boundaries[1].boundary").ShouldBe([ValidationMessages.NotAllowedValue]);
        AllRows().ShouldBeEmpty();
    }

    [Fact]
    public async Task A_null_element_in_boundaries_is_a_field_error_not_a_crash()
    {
        // `boundaries: [null]` is legal JSON; dereferencing it would turn malformed input into a 500.
        var result = await _harness.NewService().SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(CycleStart, [null!]), CancellationToken.None);

        MessagesFor(result, "boundaries[0]").ShouldBe([ValidationMessages.Required]);
        AllRows().ShouldBeEmpty();
    }

    [Fact]
    public async Task A_missing_boundary_date_is_rejected()
    {
        var result = await _harness.NewService().SavePhaseOverridesAsync(
            new SavePhaseOverridesRequest(
                CycleStart,
                [new PhaseOverrideInput(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, null)]),
            CancellationToken.None);

        MessagesFor(result, "boundaries[0].occurredOn").ShouldBe([ValidationMessages.Required]);
    }

    // --- the cycle window ---------------------------------------------------------------

    [Fact]
    public async Task A_boundary_before_the_cycle_start_is_rejected()
    {
        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(occurredOn: CycleStart.AddDays(-1))), CancellationToken.None);

        MessagesFor(result, "boundaries[0].occurredOn").ShouldBe([CycleValidationMessages.BeforeCycleStart]);
        AllRows().ShouldBeEmpty();
    }

    [Fact]
    public async Task A_boundary_on_the_cycle_start_itself_is_accepted()
    {
        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(occurredOn: CycleStart)), CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.Saved>();
    }

    [Fact]
    public async Task A_boundary_after_today_is_rejected()
    {
        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(occurredOn: CycleTestHarness.Today.AddDays(1))), CancellationToken.None);

        MessagesFor(result, "boundaries[0].occurredOn").ShouldBe([ValidationMessages.FutureDate]);
        AllRows().ShouldBeEmpty();
    }

    [Fact]
    public async Task A_boundary_at_the_next_logged_period_start_is_rejected()
    {
        var nextStart = NextStart;
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, nextStart);

        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(occurredOn: nextStart)), CancellationToken.None);

        MessagesFor(result, "boundaries[0].occurredOn").ShouldBe([CycleValidationMessages.NotBeforeNextPeriodStart]);
    }

    [Fact]
    public async Task A_boundary_after_the_next_logged_period_start_is_rejected()
    {
        var nextStart = NextStart;
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, nextStart);

        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(occurredOn: nextStart.AddDays(1))), CancellationToken.None);

        MessagesFor(result, "boundaries[0].occurredOn").ShouldBe([CycleValidationMessages.NotBeforeNextPeriodStart]);
    }

    [Fact]
    public async Task The_day_before_the_next_logged_period_start_is_accepted()
    {
        var nextStart = NextStart;
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, nextStart);

        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(occurredOn: nextStart.AddDays(-1))), CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.Saved>();
    }

    [Fact]
    public async Task Only_the_NEXT_period_start_closes_the_window_not_a_later_one()
    {
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleStart.AddDays(20));
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, CycleStart.AddDays(24));

        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(Request(Boundary(occurredOn: CycleStart.AddDays(22))), CancellationToken.None);

        MessagesFor(result, "boundaries[0].occurredOn").ShouldBe([CycleValidationMessages.NotBeforeNextPeriodStart]);
    }

    // --- what P4a deliberately does NOT check -------------------------------------------

    [Fact]
    public async Task Out_of_order_boundaries_are_accepted()
    {
        // §G6/§G10: the four phases are CODES ONLY — P4a encodes no ordering. Luteal starting before
        // menstrual ends is nonsense to a clinician and perfectly storable here, because the phase
        // sequence is the clinician-UNSIGNED C-01 band order and P6 owns it.
        var result = await _harness.NewService().SavePhaseOverridesAsync(
            Request(
                Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(2)),
                Boundary(CyclePhaseOverride.Phases.Menstrual, CyclePhaseOverride.Boundaries.End, CycleStart.AddDays(9))),
            CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.Saved>().Overrides.Boundaries.Count.ShouldBe(2);
        LiveRows().Count.ShouldBe(2);
    }

    [Fact]
    public async Task Two_phases_may_share_a_boundary_day()
    {
        var result = await _harness.NewService().SavePhaseOverridesAsync(
            Request(
                Boundary(CyclePhaseOverride.Phases.Menstrual, CyclePhaseOverride.Boundaries.End, CycleStart.AddDays(5)),
                Boundary(CyclePhaseOverride.Phases.Follicular, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(5))),
            CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.Saved>();
    }

    // --- duplicates ----------------------------------------------------------------------

    [Fact]
    public async Task A_duplicate_phase_and_boundary_pair_is_rejected()
    {
        var result = await _harness.NewService().SavePhaseOverridesAsync(
            Request(
                Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(14)),
                Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(15))),
            CancellationToken.None);

        MessagesFor(result, "boundaries[1]").ShouldBe([CycleValidationMessages.DuplicateBoundary]);
        AllRows().ShouldBeEmpty();
    }

    [Fact]
    public async Task The_same_phase_with_both_boundaries_is_not_a_duplicate()
    {
        var result = await _harness.NewService().SavePhaseOverridesAsync(
            Request(
                Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(14)),
                Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.End, CycleStart.AddDays(20))),
            CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.Saved>();
        LiveRows().Count.ShouldBe(2);
    }

    // --- replace-the-set ------------------------------------------------------------------

    [Fact]
    public async Task Saving_a_smaller_set_retracts_the_boundaries_the_request_omitted()
    {
        await _harness.NewService().SavePhaseOverridesAsync(
            Request(
                Boundary(CyclePhaseOverride.Phases.Menstrual, CyclePhaseOverride.Boundaries.End, CycleStart.AddDays(5)),
                Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(14))),
            CancellationToken.None);

        await _harness.NewService().SavePhaseOverridesAsync(
            Request(Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(15))),
            CancellationToken.None);

        var live = LiveRows().ShouldHaveSingleItem();
        live.Phase.ShouldBe(CyclePhaseOverride.Phases.Luteal);
        live.OccurredOn.ShouldBe(CycleStart.AddDays(15));
        AllRows().Count.ShouldBe(2, "the retracted boundary is tombstoned, not deleted");
    }

    [Fact]
    public async Task An_empty_boundaries_list_retracts_the_whole_set()
    {
        await _harness.NewService().SavePhaseOverridesAsync(
            Request(
                Boundary(CyclePhaseOverride.Phases.Menstrual, CyclePhaseOverride.Boundaries.End, CycleStart.AddDays(5)),
                Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(14))),
            CancellationToken.None);

        var result = await _harness.NewService()
            .SavePhaseOverridesAsync(new SavePhaseOverridesRequest(CycleStart, []), CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.Saved>().Overrides.Boundaries.ShouldBeEmpty();
        LiveRows().ShouldBeEmpty();
        AllRows().Count.ShouldBe(2);
        AllRows().ShouldAllBe(o => o.DeletedAt != null);
    }

    [Fact]
    public async Task Another_cycles_overrides_are_left_alone()
    {
        var otherStart = CycleStart.AddDays(-40);
        _harness.SeedEvent(CycleEvent.Kinds.PeriodStart, otherStart);
        _harness.SeedOverride(otherStart, CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, otherStart.AddDays(14));

        await _harness.NewService()
            .SavePhaseOverridesAsync(new SavePhaseOverridesRequest(CycleStart, []), CancellationToken.None);

        LiveRows().ShouldHaveSingleItem().CycleStartOn.ShouldBe(otherStart);
    }

    // --- §G9 tombstone revival ------------------------------------------------------------

    [Fact]
    public async Task Re_correcting_after_a_retraction_revives_the_same_row()
    {
        // The failure this pins: cycle_phase_overrides' unique index spans tombstones, so a blind
        // insert on the SECOND correction of a boundary the user had reset is a 500.
        var first = await _harness.NewService().SavePhaseOverridesAsync(
            Request(Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(14))),
            CancellationToken.None);
        first.ShouldBeOfType<PhaseOverrideResult.Saved>();
        var originalId = LiveRows().ShouldHaveSingleItem().Id;

        await _harness.NewService()
            .SavePhaseOverridesAsync(new SavePhaseOverridesRequest(CycleStart, []), CancellationToken.None);
        LiveRows().ShouldBeEmpty();

        var later = CycleTestHarness.Now.AddDays(1);
        var again = await _harness.NewService(_harness.DayInfo(now: later)).SavePhaseOverridesAsync(
            Request(Boundary(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, CycleStart.AddDays(16))),
            CancellationToken.None);

        again.ShouldBeOfType<PhaseOverrideResult.Saved>();
        var revived = LiveRows().ShouldHaveSingleItem();
        revived.Id.ShouldBe(originalId, "§G9: the tombstone is revived in place, never duplicated");
        revived.OccurredOn.ShouldBe(CycleStart.AddDays(16));
        revived.CreatedAt.ShouldBe(CycleTestHarness.Now);
        revived.UpdatedAt.ShouldBe(later);
        AllRows().Count.ShouldBe(1);
    }

    [Fact]
    public async Task A_pre_existing_tombstone_is_revived_rather_than_duplicated()
    {
        var tombstone = _harness.SeedOverride(
            CycleStart,
            CyclePhaseOverride.Phases.Ovulatory,
            CyclePhaseOverride.Boundaries.End,
            CycleStart.AddDays(16),
            deletedAt: CycleTestHarness.Now.AddHours(-2));

        var result = await _harness.NewService().SavePhaseOverridesAsync(
            Request(Boundary(CyclePhaseOverride.Phases.Ovulatory, CyclePhaseOverride.Boundaries.End, CycleStart.AddDays(17))),
            CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.Saved>();
        AllRows().Count.ShouldBe(1);
        var live = LiveRows().ShouldHaveSingleItem();
        live.Id.ShouldBe(tombstone.Id);
        live.OccurredOn.ShouldBe(CycleStart.AddDays(17));
    }

    [Fact]
    public async Task Saved_rows_carry_the_user_correction_source()
    {
        await _harness.NewService().SavePhaseOverridesAsync(Request(Boundary()), CancellationToken.None);

        LiveRows().ShouldHaveSingleItem().Source.ShouldBe(CyclePhaseOverride.Sources.UserCorrection);
    }

    // --- the erased-user fence --------------------------------------------------------------

    [Fact]
    public async Task A_crypto_shredded_user_cannot_save_a_phase_correction()
    {
        var result = await _harness.NewService(null)
            .SavePhaseOverridesAsync(Request(Boundary()), CancellationToken.None);

        result.ShouldBeOfType<PhaseOverrideResult.UserNotFound>();
        AllRows().ShouldBeEmpty();
    }

    // --- the frozen wire vocabulary (§G12) ------------------------------------------------

    [Fact]
    public void Cycle_validation_messages_are_frozen()
    {
        // §G12: "endpoint-specific messages are defined in their own task and asserted verbatim
        // there" — this is that assertion for CycleContracts.cs. Every test above asserts a
        // rejection THROUGH the constant (e.g. `.ShouldBe([CycleValidationMessages.BeforeCycleStart])`),
        // which pins the service's behaviour to the constant but pins the constant to nothing: reword
        // the literal and those tests stay green. These four strings are wire text the Flutter client
        // renders verbatim, so they are pinned here against their literals, mirroring the precedent in
        // `Lumen.UnitTests.Validation.ValidationProblemBuilderTests.Shared_message_constants_are_frozen`
        // (T3), which does the same for the shared `ValidationMessages` constants.
        CycleValidationMessages.NoMatchingPeriodStart.ShouldBe("must match a logged period start");
        CycleValidationMessages.BeforeCycleStart.ShouldBe("date must not be before the cycle start");
        CycleValidationMessages.NotBeforeNextPeriodStart.ShouldBe(
            "date must be before the next logged period start");
        CycleValidationMessages.DuplicateBoundary.ShouldBe("this phase and boundary appears more than once");
    }
}
