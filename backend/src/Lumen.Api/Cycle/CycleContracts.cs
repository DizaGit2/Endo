namespace Lumen.Api.Cycle;

// The DTOs, wire strings and code vocabulary of the cycle feature, per the T3 convention
// `<Feature>/<Feature>Contracts.cs`.
//
// On the `namespace` above (§G12, corrected after T4's review): `AddSwaggerGen()` is bare — no
// `CustomSchemaIds` — so the OpenAPI schema id is `type.Name` and is namespace-INDEPENDENT. Declaring
// one here does NOT rename a schema (verified against the regenerated snapshot in this commit: the
// ids are `LogCycleEventRequest`, `CycleEventResponse`, `SavePhaseOverridesRequest`,
// `PhaseOverrideInput`, `PhaseOverridesResponse`, `PhaseOverrideBoundary` — no namespace prefix).
// The real hazard is a short-type-name COLLISION across feature folders, which throws a
// duplicate-schemaId error at document generation, so every name below is globally unique.

/// <summary>
/// Body of <c>POST /cycle/events</c> — an upsert keyed on <c>(user, kind, occurredOn)</c>, not an
/// append. Re-posting the same kind and day updates that one row (which is what makes the
/// online-only client's retry safe), so every member describes the row's desired final state: a
/// <see langword="null"/> <see cref="Notes"/> or <see cref="FlowIntensity"/> clears the stored value
/// rather than leaving it alone.
/// </summary>
/// <param name="Kind">One of the three ratified cycle-event kinds (§G10).</param>
/// <param name="OccurredOn">
/// The user-local day of the observation. <b>The only P4a write with a floor (§G8):</b> it must fall
/// on or before the user's today AND on or after their backdate floor (account creation − 2 y, D-13).
/// </param>
/// <param name="FlowIntensity">
/// Optional 1–4 flow level, <b>accepted on every kind</b>. There is deliberately no cross-field rule
/// tying it to <c>period_start</c>: "flow ≥ 2 is period-qualifying" is C-04, clinician-UNSIGNED, and
/// belongs to P6's estimator — never to an entry validator (§G7).
/// </param>
/// <param name="Notes">Optional free text, ≤ 2000 characters after trimming (D-13). Stored encrypted.</param>
public record LogCycleEventRequest(
    string? Kind,
    DateOnly? OccurredOn,
    int? FlowIntensity,
    string? Notes);

/// <summary>
/// The 200 body of <c>POST /cycle/events</c>: the stored row, with <see cref="Notes"/> echoed back in
/// plaintext (the column itself holds only AES-256-GCM ciphertext).
/// </summary>
/// <param name="Id">The id <c>DELETE /cycle/events/{id}</c> takes. Stable across upserts.</param>
/// <param name="Source">
/// How the row got here (§G11: <c>user</c> or <c>onboarding</c>). An existing onboarding-seeded row
/// keeps its provenance when the user edits it, so this is not always <c>user</c>.
/// </param>
public record CycleEventResponse(
    Guid Id,
    string Kind,
    DateOnly OccurredOn,
    int? FlowIntensity,
    string? Notes,
    string Source,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>
/// Body of <c>POST /cycle/phase-override</c> (screen 14) — <b>replace the whole set</b> for one
/// cycle. Whatever this request lists becomes the user's live corrections for that cycle; every
/// boundary it omits is retracted (soft-deleted).
/// </summary>
/// <param name="CycleStartOn">
/// The day of a <b>live logged <c>period_start</c></b> belonging to the caller. This is the only key
/// tying a correction to a cycle, so it is checked structurally against the user's own events — not
/// against any computed cycle, of which P4a has none (§G6).
/// </param>
/// <param name="Boundaries">
/// The corrections to keep. An <b>empty list is "reset to predicted"</b> and retracts them all;
/// omitting the field entirely is a validation error, because an accidental omission must never
/// silently wipe the user's corrections.
/// </param>
public record SavePhaseOverridesRequest(
    DateOnly? CycleStartOn,
    IReadOnlyList<PhaseOverrideInput>? Boundaries);

/// <summary>
/// One requested phase-boundary correction. Errors against it are reported under the indexed key
/// <c>boundaries[i].&lt;field&gt;</c> so the client can attach each message to the right row.
/// </summary>
/// <param name="Phase">One of the four ratified phase codes (§G10). <b>Codes only</b> — no ordering.</param>
/// <param name="Boundary">Which end of the phase moves: <c>start</c> or <c>end</c>.</param>
/// <param name="OccurredOn">
/// The corrected day. Must sit inside the cycle's window: on or after <see cref="SavePhaseOverridesRequest.CycleStartOn"/>,
/// on or before the user's today, and strictly before the next logged <c>period_start</c>.
/// </param>
public record PhaseOverrideInput(
    string? Phase,
    string? Boundary,
    DateOnly? OccurredOn);

/// <summary>The 200 body of <c>POST /cycle/phase-override</c>: the cycle's live correction set after the write.</summary>
public record PhaseOverridesResponse(
    DateOnly CycleStartOn,
    IReadOnlyList<PhaseOverrideBoundary> Boundaries);

/// <summary>One stored phase-boundary correction.</summary>
public record PhaseOverrideBoundary(
    string Phase,
    string Boundary,
    DateOnly OccurredOn);

/// <summary>
/// Messages owned by the cycle endpoints alone (§G12: only genuinely cross-cutting strings belong on
/// <see cref="Validation.ValidationMessages"/>). These are <b>wire strings</b> asserted verbatim in
/// <c>CyclePhaseOverrideServiceTests</c> — rewording one is a contract change, not a copy edit.
/// </summary>
/// <remarks>
/// House style (T3): a field-scoped message starts lowercase and never names its own field, because
/// the <c>errors</c> map key already does and the client renders "&lt;key&gt;: &lt;message&gt;".
/// </remarks>
public static class CycleValidationMessages
{
    /// <summary>No live <c>period_start</c> of the caller's falls on the requested <c>cycleStartOn</c>.</summary>
    public const string NoMatchingPeriodStart = "must match a logged period start";

    /// <summary>A boundary was dated before the cycle it corrects began.</summary>
    public const string BeforeCycleStart = "date must not be before the cycle start";

    /// <summary>A boundary was dated on or after the next logged <c>period_start</c>, i.e. into the following cycle.</summary>
    public const string NotBeforeNextPeriodStart = "date must be before the next logged period start";

    /// <summary>The same <c>(phase, boundary)</c> pair appears twice in one request.</summary>
    public const string DuplicateBoundary = "this phase and boundary appears more than once";
}

/// <summary>
/// Why a cycle day carries no phase. <b>P4a can only ever answer
/// <see cref="PhaseEngineNotImplemented"/></b> — the phase engine is P6 (§G6), so the calendar
/// reports <c>phase: { available: false, unavailableReason: "phase_engine_not_implemented" }</c> and
/// no day row carries a <c>phase</c>, <c>cycleDay</c> or <c>confidence</c> key at all.
///
/// <para>The other three are declared now and <b>reserved for P6</b>, deliberately: the codes reach
/// the Flutter client through the generated contract, which P4a regenerates exactly once (T21), so
/// declaring the full set here means P6 can start emitting them without a client-visible vocabulary
/// change. They are a <b>P4a invention</b> (§G11), not part of the 2026-07-08 ratification block.
/// Append-only, like every other vocabulary in this codebase.</para>
/// </summary>
public static class CyclePhaseAvailability
{
    /// <summary>P4a's only answer: no phase engine exists yet.</summary>
    public const string PhaseEngineNotImplemented = "phase_engine_not_implemented";

    /// <summary>Reserved (P6): the user has paused cycle tracking, so predictions are suppressed (C-12).</summary>
    public const string TrackingPaused = "tracking_paused";

    /// <summary>Reserved (P6): too few in-bounds cycles to estimate from (C-03).</summary>
    public const string InsufficientData = "insufficient_data";

    /// <summary>Reserved (P6): no <c>period_start</c> has ever been logged, so no cycle exists to phase.</summary>
    public const string NoPeriodLogged = "no_period_logged";

    public static readonly IReadOnlyList<string> All =
        [PhaseEngineNotImplemented, TrackingPaused, InsufficientData, NoPeriodLogged];
}
