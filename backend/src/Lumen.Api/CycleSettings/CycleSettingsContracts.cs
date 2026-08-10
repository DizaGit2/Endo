using Lumen.Domain.Entities;

namespace Lumen.Api.CycleSettings;

// The DTOs, wire strings and bounds of the cycle-settings feature, per the T3 convention
// `<Feature>/<Feature>Contracts.cs`.
//
// On the `namespace` above (§G12, corrected after T4's review): `AddSwaggerGen()` is bare — no
// `CustomSchemaIds` — so the OpenAPI schema id is `type.Name` and is namespace-INDEPENDENT. The real
// hazard is a short-type-name COLLISION across feature folders, which throws a duplicate-schemaId
// error at document generation, so every name below is globally unique: `UpdateCycleSettingsRequest`
// and `CycleSettingsResponse` appear nowhere else in the tree.
//
// NOTE — no `[DefaultValue]` anywhere in this file, deliberately. T13 shipped one on a NULLABLE member
// and it made the property un-nullable in the generated Dart client forever (openapi-generator's
// dart-dio + built_value output turns a schema `default` into a builder default, and its deserializer
// skips explicit nulls). Four members here are nullable — `avgPeriodLengthDays`, `pauseReason`,
// `pausedSince`, and both timestamps — and a default on any of them would be the same lie.

/// <summary>
/// Body of <c>PATCH /settings/cycle</c> (screen 32). <b>Every member is optional and
/// <see langword="null"/> means "leave unchanged"</b> — this is a PATCH, so an absent field is never a
/// request to reset it.
///
/// <para><b>MERGE semantics, and the reasoning is the phase's standard one (§G12): the deciding test
/// is not the HTTP verb, it is how many surfaces write the row.</b> <c>user_cycle_settings</c> is a
/// <b>multi-writer row</b> — screen 32's self-report block writes the three cycle fields, screen 32's
/// pause card writes the pause triple, and T18's <c>POST /onboarding/cycle</c> (B15) writes the cycle
/// fields again through <c>CycleSettingsService.ApplyOnboardingCycleAsync</c>. Under full replace, the
/// pause card posting <c>{ trackingPaused: true, pauseReason: "pregnancy" }</c> would silently reset
/// <see cref="AvgCycleLengthDays"/> to its default and destroy a self-report the user made on a
/// different control. That is the exact cross-surface wipe merge exists to prevent, and it is why
/// <c>POST /cycle/day/{date}</c> merges too.</para>
///
/// <para><b>The verb agrees with the rule, which is not a coincidence.</b> T12 renamed the symptom
/// update from <c>PATCH</c> to <c>PUT</c> precisely so the verb never contradicts the semantics: full
/// replace under <c>PATCH</c> means a client author who sends only the changed field suffers silent
/// data loss. Here the semantics ARE merge, so <c>PATCH</c> is honest.</para>
///
/// <para><b>The documented cost, identical to <c>LogCycleDayRequest</c>'s: P4a ships no way to CLEAR
/// <see cref="AvgPeriodLengthDays"/> back to null.</b> A positional record with <c>int?</c> cannot
/// distinguish an absent property from an explicit null under <c>System.Text.Json</c> (and
/// <c>built_value</c> omits nulls on the wire), so "leave alone" and "clear" cannot both be expressed
/// without an <c>Optional&lt;T&gt;</c> wrapper the generated Dart client has no way to produce. Screen
/// 32 offers no clear affordance, so nothing is lost today.</para>
///
/// <para><b>An entirely empty body is a 400</b> (<see cref="CycleSettingsValidationMessages.NoFieldsSupplied"/>),
/// not a silently successful write of nothing: under merge it would materialise a defaults row for a
/// user who never asked for one.</para>
/// </summary>
/// <param name="AvgCycleLengthDays">
/// The user's self-reported average cycle length. <b>§G7 — a typed self-report gets a STRUCTURAL check
/// and nothing more:</b> a positive integer that fits <c>smallint</c>. A value outside the sanity band
/// is <b>persisted</b> and answered with a non-blocking <see cref="CycleSettingsResponse.Warnings"/>
/// code; the C-03 clinical bounds are clinician-UNSIGNED, live in no validator, and never block entry.
/// Typed <c>int?</c> rather than <c>short?</c> on purpose, so an out-of-domain value reaches the
/// validator and comes back attached to its own field instead of failing at the model binder as T3's
/// one <c>request</c>-keyed 400.
/// </param>
/// <param name="AvgPeriodLengthDays">The self-reported average period length. Same §G7 treatment.</param>
/// <param name="Regularity">One of the three ratified codes (§G10); anything else is a 400.</param>
/// <param name="PhasePredictionEnabled">
/// Whether the user wants phase predictions rendered. P4a stores it and folds it into
/// <see cref="CycleSettingsResponse.PhasesUnavailable"/>; P6 honours it.
/// </param>
/// <param name="AutoDetectPeriodStartEnabled">
/// Whether C-04 <c>period_start</c> auto-detection may run. <b>P4a ships no auto-detect (§G6)</b> —
/// the preference is captured now so it is already there when P6 turns the feature on.
/// </param>
/// <param name="ShowFertilityWindowEnabled">
/// Whether the C-02 fertile-window overlay is shown. Defaults off: the overlay is clinician-UNSIGNED
/// and carries a mandatory non-contraceptive disclaimer. P4a renders nothing either way.
/// </param>
/// <param name="TrackingPaused">
/// The C-12 pause switch. <c>true</c> requires a <see cref="PauseReason"/> (unless the user is already
/// paused, in which case the current reason is kept) and opens a <c>cycle_tracking_pause_spans</c> row;
/// <c>false</c> closes the open span. <b>Resume is unconditional for every reason</b> — no gate, no
/// confirmation, not even for <c>pregnancy</c>.
/// </param>
/// <param name="PauseReason">
/// One of the <b>five</b> C-12 members (<see cref="UserCycleSettings.PauseReasons"/>). Supplying it
/// while the effective state is not paused is a 400
/// (<see cref="CycleSettingsValidationMessages.PauseFieldRequiresPause"/>): pausing must be an explicit
/// act, so a remembered reason is a UI pre-selection and never consent to pause again.
/// </param>
/// <param name="PausedSince">
/// The user-local day the pause began; defaults to the user's today. Capped by today and <b>given no
/// backdate floor (§G8)</b> — a menopause or surgical pause that began years ago is real history, and
/// D-13 gives a floor to <c>cycle_events</c> alone.
/// </param>
public record UpdateCycleSettingsRequest(
    int? AvgCycleLengthDays = null,
    int? AvgPeriodLengthDays = null,
    string? Regularity = null,
    bool? PhasePredictionEnabled = null,
    bool? AutoDetectPeriodStartEnabled = null,
    bool? ShowFertilityWindowEnabled = null,
    bool? TrackingPaused = null,
    string? PauseReason = null,
    DateOnly? PausedSince = null);

/// <summary>
/// The 200 body of both <c>GET /settings/cycle</c> and <c>PATCH /settings/cycle</c> — the whole
/// resource, every time.
/// </summary>
/// <remarks>
/// <para><b>Why the PATCH answers 200 with the full resource rather than 204 like <c>PATCH /me</c>.</b>
/// The body carries two things the request cannot predict: the non-blocking
/// <see cref="Warnings"/> and the derived <see cref="PhasesUnavailable"/>. The client is online-only,
/// so a 204 would force an immediate re-GET on every save just to render the hint under the field the
/// user has just left.</para>
///
/// <para><b>Nothing here is computed from health data (§G6).</b> <see cref="PhasesUnavailable"/> is a
/// boolean OR of two stored flags and <see cref="Warnings"/> is a range check on two self-reported
/// numbers. No phase, no cycle day, no prediction, no confidence — and no property for any of them, so
/// a later edit cannot start filling one in.</para>
/// </remarks>
/// <param name="AvgCycleLengthDays">The stored self-report (the T6 default when no row exists).</param>
/// <param name="AvgPeriodLengthDays">
/// The stored self-report, or <see langword="null"/>: onboarding screen 3 never collects it, so a
/// seeded value would be a self-report the user never made.
/// </param>
/// <param name="Regularity">One of the three ratified codes (§G10).</param>
/// <param name="PhasePredictionEnabled">See <see cref="UpdateCycleSettingsRequest.PhasePredictionEnabled"/>.</param>
/// <param name="AutoDetectPeriodStartEnabled">See <see cref="UpdateCycleSettingsRequest.AutoDetectPeriodStartEnabled"/>.</param>
/// <param name="ShowFertilityWindowEnabled">See <see cref="UpdateCycleSettingsRequest.ShowFertilityWindowEnabled"/>.</param>
/// <param name="TrackingPaused">
/// <b>The one field that means "is this user paused".</b> Read this, never
/// <see cref="PauseReason"/> — see the remark there.
/// </param>
/// <param name="PauseReason">
/// The reason for the <b>most recent</b> pause, which <b>survives a resume on purpose</b> so screen
/// 32 can pre-select it next time (ARCHITECTURE.md §D: there is deliberately no CHECK tying it to
/// <see cref="TrackingPaused"/>). <b>A non-null value therefore does NOT mean the user is paused</b>,
/// and any consumer that reads it as one — P6's estimator exclusion, P7b's rule that
/// <c>pregnancy</c> disables hormone-range interpretation — must gate on
/// <see cref="TrackingPaused"/> first.
/// </param>
/// <param name="PausedSince">
/// The user-local day the CURRENT pause began, or <see langword="null"/> when not paused. Unlike
/// <see cref="PauseReason"/> this moves in lockstep with <see cref="TrackingPaused"/>.
/// </param>
/// <param name="PhasesUnavailable">
/// <b>The explicit "phases unavailable" state ARCHITECTURE.md §A:59 requires</b>, derived and never
/// persisted: <c>trackingPaused || !phasePredictionEnabled</c>. A boolean OR of two stored flags — no
/// engine, no inference, no clinical judgement (§G6). It exists so a paused user is shown an
/// unavailable state rather than a confidently wrong phase, which is the whole clinical point of the
/// pause. P4a's calendar independently answers
/// <c>phase: { available: false, unavailableReason: "phase_engine_not_implemented" }</c> because no
/// engine exists yet at all; this flag is what stays true for a paused user once P6 ships one.
/// <para><b>Not emitted: <c>hormoneRangeInterpretationEnabled</c>.</b> It would encode the
/// clinician-UNSIGNED C-12 rule that <c>pregnancy</c> disables hormone-range interpretation, and its
/// only consumers (P6/P7b) do not exist. P4a persists <see cref="TrackingPaused"/> and
/// <see cref="PauseReason"/>, which is everything they will need. Recorded as a deferral in T22.</para>
/// </param>
/// <param name="Warnings">
/// Zero or more frozen <see cref="CycleSettingsWarnings"/> codes — <b>non-blocking hints, never
/// rejections (§G7)</b>. Computed on GET as well as PATCH, because screen 32 shows the hint when it
/// loads and not only after a save. Order is stable: cycle length before period length.
/// <para>Plain strings rather than a second schema, following
/// <c>CyclePhaseAvailabilityResponse.UnavailableReason</c>: the code names its own field, the
/// vocabulary is append-only, and a client that wants to branch compares the literal it received. No
/// Dart symbol is generated for any of them.</para>
/// </param>
/// <param name="CreatedAt">
/// <see langword="null"/> when no row has ever been saved. Together with <see cref="UpdatedAt"/> this
/// is the ONLY thing that distinguishes "these are the untouched defaults" from "a row was saved that
/// happens to equal them" — which is why <c>GET</c> can honestly answer 200 without writing anything.
/// </param>
/// <param name="UpdatedAt">See <see cref="CreatedAt"/>.</param>
public record CycleSettingsResponse(
    int AvgCycleLengthDays,
    int? AvgPeriodLengthDays,
    string Regularity,
    bool PhasePredictionEnabled,
    bool AutoDetectPeriodStartEnabled,
    bool ShowFertilityWindowEnabled,
    bool TrackingPaused,
    string? PauseReason,
    DateOnly? PausedSince,
    bool PhasesUnavailable,
    IReadOnlyList<string> Warnings,
    DateTimeOffset? CreatedAt,
    DateTimeOffset? UpdatedAt);

/// <summary>
/// The frozen, <b>non-blocking</b> warning codes of <c>GET</c>/<c>PATCH /settings/cycle</c> (§G7).
/// <b>Wire strings</b>: they travel in <see cref="CycleSettingsResponse.Warnings"/> and are asserted
/// verbatim in <c>CycleSettingsServiceTests</c> and <c>CycleSettingsLiveTests</c>, so renaming one is a
/// contract change rather than a copy edit. Append-only.
/// </summary>
/// <remarks>
/// A warning is emitted, the value is <b>saved</b>, and the response is a 200. This is the entire
/// difference between the two tiers §G7 defines: the structural type-domain check is the only thing
/// that can produce a 400 on these two fields, and the sanity band can only ever produce one of these.
/// </remarks>
public static class CycleSettingsWarnings
{
    /// <summary><see cref="CycleSettingsResponse.AvgCycleLengthDays"/> is outside the sanity band — stored anyway.</summary>
    public const string AvgCycleLengthOutOfSanityBand = "avg_cycle_length_out_of_sanity_band";

    /// <summary><see cref="CycleSettingsResponse.AvgPeriodLengthDays"/> is outside the sanity band — stored anyway.</summary>
    public const string AvgPeriodLengthOutOfSanityBand = "avg_period_length_out_of_sanity_band";

    public static readonly IReadOnlyList<string> All =
        [AvgCycleLengthOutOfSanityBand, AvgPeriodLengthOutOfSanityBand];
}

/// <summary>
/// The <b>sanity band</b> for the two typed self-reports (§G7 / ARCHITECTURE.md §D
/// <c>user_cycle_settings</c>): the range outside which the endpoint attaches a
/// <see cref="CycleSettingsWarnings"/> code — and <b>saves the value regardless</b>.
/// </summary>
/// <remarks>
/// <para><b>These are not clinical bounds and must never become one.</b> The C-03/C-04 clinical figures
/// are clinician-UNSIGNED PO-interim values whose only lawful home is P6's <c>ref_insight_rule</c> seed;
/// §G6 keeps that out of P4a, so they appear <b>nowhere in <c>backend/src</c></b> — not in DDL, not in a
/// validator, not as a constant, not as a numeral in a comment. The behavioural guard is
/// <c>CycleSettingsServiceTests.An_avg_cycle_length_outside_the_clinical_band_is_accepted_stored_and_UNWARNED</c>.</para>
///
/// <para><b>Why a band at all.</b> A number this far out is almost always a typo (a stray digit, days
/// entered as hours), and the user is the only one who can tell. A hint under the field lets them fix
/// it; a rejection would lose a real answer from the minority for whom it is not a typo. Rider 7 is
/// verbatim on this: sanity bounds are <i>"never entry blockers (PO requirement)"</i>.</para>
///
/// <para>Both ends are INCLUSIVE, and this lives beside the endpoint that owns it rather than on
/// <c>Validation.FieldLimits</c>, which is reserved for genuinely cross-cutting numbers.</para>
/// </remarks>
public static class CycleSettingsSanityBand
{
    /// <summary>Inclusive lower edge for <c>avgCycleLengthDays</c>.</summary>
    public const int MinAvgCycleLengthDays = 10;

    /// <summary>Inclusive upper edge for <c>avgCycleLengthDays</c>.</summary>
    public const int MaxAvgCycleLengthDays = 120;

    /// <summary>Inclusive lower edge for <c>avgPeriodLengthDays</c>.</summary>
    public const int MinAvgPeriodLengthDays = 1;

    /// <summary>Inclusive upper edge for <c>avgPeriodLengthDays</c>.</summary>
    public const int MaxAvgPeriodLengthDays = 30;

    /// <summary>Whether a stored average cycle length sits inside the band.</summary>
    public static bool ContainsCycleLength(int days) =>
        days >= MinAvgCycleLengthDays && days <= MaxAvgCycleLengthDays;

    /// <summary>Whether a stored average period length sits inside the band.</summary>
    public static bool ContainsPeriodLength(int days) =>
        days >= MinAvgPeriodLengthDays && days <= MaxAvgPeriodLengthDays;
}

/// <summary>
/// The <b>structural type-domain</b> of the two typed self-reports (§G7) — the only thing on these two
/// fields that can produce a 400. A positive integer that fits the <c>smallint</c> column, matching the
/// <c>&gt; 0</c> CHECKs T6 put in the DDL and nothing more.
/// </summary>
/// <remarks>
/// Named rather than inlined so the endpoint and its tests state the same domain, and expressed against
/// <see cref="short.MaxValue"/> so it tracks the column's type instead of a transcribed number. There
/// is <b>no third tier</b>: the intermediate range that appeared in an earlier draft between this
/// domain and the sanity band is invented, is in no source document, and — like the clinical bounds —
/// appears nowhere in this codebase, not even as a numeral in a comment.
/// </remarks>
public static class CycleSettingsStructuralDomain
{
    /// <summary>The smallest storable self-report: the DDL CHECK is <c>&gt; 0</c>.</summary>
    public const int Min = 1;

    /// <summary>The largest storable self-report: the width of the <c>smallint</c> column.</summary>
    public const int Max = short.MaxValue;

    /// <summary>Whether the value can be stored at all.</summary>
    public static bool Contains(int days) => days >= Min && days <= Max;
}

/// <summary>
/// Messages owned by <c>/settings/cycle</c> alone (§G12: only genuinely cross-cutting strings belong on
/// <see cref="Validation.ValidationMessages"/>). These are <b>wire strings</b> asserted verbatim in
/// <c>CycleSettingsServiceTests</c> and <c>CycleSettingsLiveTests</c> — rewording one is a contract
/// change, not a copy edit.
/// </summary>
/// <remarks>
/// House style (T3): a field-scoped message starts lowercase and never names its own field, because the
/// <c>errors</c> map key already does and the client renders "&lt;key&gt;: &lt;message&gt;".
/// </remarks>
public static class CycleSettingsValidationMessages
{
    /// <summary>
    /// <c>pauseReason</c> or <c>pausedSince</c> arrived while the effective state is not paused.
    /// Refused rather than stored: a reason is meaningful only for an actual pause, and accepting one
    /// alongside <c>trackingPaused: false</c> would let a client believe it had paused the user.
    /// </summary>
    public const string PauseFieldRequiresPause = "value is only allowed while cycle tracking is paused";

    /// <summary>
    /// The PATCH body named no field at all. Reported under
    /// <see cref="Validation.ValidationProblemBuilder.RequestKey"/> because it belongs to the whole
    /// request. Under merge an empty body is a pure no-op that would still materialise a defaults row
    /// and stamp <c>updatedAt</c>, so it is a 400 rather than a silently successful write of nothing —
    /// the same rule <c>POST /cycle/day/{date}</c> applies.
    /// </summary>
    public const string NoFieldsSupplied = "at least one settings field is required";
}
