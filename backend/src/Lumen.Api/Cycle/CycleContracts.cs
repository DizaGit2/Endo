using System.ComponentModel;

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
// duplicate-schemaId error at document generation, so every name below is globally unique — including
// T13's `CycleCalendarResponse`, `CyclePhaseAvailabilityResponse` and `CycleCalendarDay`.

/// <summary>
/// Body of <c>POST /cycle/events</c> — an upsert keyed on <c>(user, kind, occurredOn)</c>, not an
/// append. Re-posting the same kind and day updates that one row (which is what makes the
/// online-only client's retry safe).
///
/// <para><b>FULL-UPSERT semantics — one of the two write rules in this phase.</b> Every member
/// describes the row's desired FINAL state: a <see langword="null"/> <see cref="Notes"/> or
/// <see cref="FlowIntensity"/> <b>clears</b> the stored value rather than leaving it alone. That is
/// safe here and only here, because <c>cycle_events</c> is a <b>single-writer, small row</b> — one
/// screen owns all four fields and always submits them together, so the body genuinely does describe
/// the row's whole state, and clearing is the only way the user can take a flow level back off an
/// event.</para>
///
/// <para><b>That writer is screen 11's period editor</b> (Flutter
/// <c>PeriodEditorScreen</c> / <c>PeriodEditorController</c>, P4b-T16c), a bottom sheet over the day
/// detail. It seeds every control from the day's existing event and its save sends all four fields
/// unconditionally — there are deliberately no "touched" flags on that surface, because on this
/// endpoint an omitted field is a delete. Screen 10 (the cycle calendar) writes nothing: ruling R-10
/// keeps this endpoint to a single writer.
/// <b>Corrected at P4b-T16c.</b> Until that task shipped, this paragraph named
/// <i>"screen 10/11's period controls"</i> — and a re-survey of all 38 mockups found that Lumen had
/// no period-logging surface of any kind. The safety argument for FULL UPSERT rested on controls that
/// did not exist; building them is what made it true.</para>
///
/// <para><b>The other rule is on <see cref="LogCycleDayRequest"/> (<c>POST /cycle/day/{date}</c>),
/// which MERGES</b> — an omitted field there is left alone. The two are deliberately different and
/// the difference is invisible in the generated Dart client (both are nullable members on a
/// <c>built_value</c> class), so it is stated on both DTOs rather than in one place. The deciding
/// question is not the HTTP verb, it is <b>how many surfaces write the row</b>.</para>
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
/// Body of <c>POST /cycle/day/{date}</c> (screen 11, day detail) — the one-row-per-day upsert of
/// D-11. The day itself is the route parameter, never a field here.
///
/// <para><b>MERGE semantics — the other of the two write rules in this phase, and the opposite of
/// <see cref="LogCycleEventRequest"/>. An absent or <see langword="null"/> member leaves the stored
/// value UNCHANGED; only a supplied value writes.</b> <c>cycle_day_logs</c> is a <b>multi-writer
/// row</b>: <c>POST /checkin/quick</c> writes pain and mood, this endpoint writes pain, mood and the
/// note, and D-10's <c>energy</c>/<c>libido</c> scales land on the same row later. Under full-upsert,
/// any screen that posted without re-sending every field would silently destroy what the user entered
/// on another screen — which is exactly why the check-in had to be special-cased as partial in the
/// first place. Merging makes the two consistent instead of leaving one endpoint as the exception.</para>
///
/// <para><b>The documented cost: P4a ships no way to clear an individual field.</b>
/// <c>int?</c>/<c>string?</c> on a positional record cannot distinguish an absent property from an
/// explicit <c>null</c> under <c>System.Text.Json</c> (and <c>built_value</c> omits nulls on the
/// wire), so "leave alone" and "clear" cannot both be expressed without an <c>Optional&lt;T&gt;</c>
/// wrapper in the generated Dart client. Screens 9 and 11 offer no clear affordance, so nothing is
/// lost today — and a limitation the user can see beats a wipe they cannot. A blank or whitespace-only
/// <see cref="Notes"/> is absent text, not an erase instruction.</para>
///
/// <para>The two columns this DTO does <i>not</i> expose — <c>energy</c> and <c>libido</c> — are
/// untouched by either endpoint for a stronger reason still: D-10 defers both scales, so P4a has no
/// writer for them at all (§D).</para>
///
/// <para>At least one of <see cref="Pain"/>, <see cref="Mood"/> and <see cref="Notes"/> must be
/// present: under merge an empty body would be a pure no-op that still stamped <c>updatedAt</c> and
/// revived a tombstone, so it is a 400 rather than a silently successful write of nothing.</para>
/// </summary>
/// <param name="Pain">
/// Headline pain on the 0–10 NRS-11 scale (D-08). <b>0 is a real datum</b> ("none today"): it
/// satisfies the at-least-one rule, and because it is <i>supplied</i> it overwrites a stored value
/// like any other. Only <see langword="null"/> means "leave whatever is recorded alone".
/// </param>
/// <param name="Mood">Mood on the 1–4 scale {low, tired, steady, bright} (§G10).</param>
/// <param name="Notes">Optional free text, ≤ 2000 characters after trimming (D-13). Stored encrypted.</param>
public record LogCycleDayRequest(
    int? Pain,
    int? Mood,
    string? Notes);

/// <summary>
/// One stored <c>cycle_day_logs</c> row: the 200 body of <c>POST /cycle/day/{date}</c> and the
/// <c>log</c> member of <see cref="CycleDayResponse"/>, with <see cref="Notes"/> echoed back in
/// plaintext (the column itself holds only AES-256-GCM ciphertext).
/// </summary>
/// <remarks>
/// No <c>id</c>: the row is addressed by <c>(user, day)</c> and §C.2 exposes no endpoint that takes a
/// day-log id, so publishing one would be an identifier the client can only misuse. No <c>phase</c>,
/// <c>cycleDay</c> or <c>confidence</c> either (§G6) — P4a computes none of them, and a placeholder
/// key is exactly how a not-yet-implemented estimate gets rendered as a clinical fact.
/// </remarks>
public record CycleDayLogResponse(
    DateOnly Day,
    int? Pain,
    int? Mood,
    string? Notes,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>
/// The 200 body of <c>GET /cycle/day/{date}</c> (screen 11): everything the user has recorded
/// <i>on</i> one day.
/// </summary>
/// <remarks>
/// A day with nothing on it is a <b>200</b> with <c>log: null</c> and empty collections, not a 404 —
/// 404 is reserved for "no such user" (§G12), and "nothing logged" is the empty state the screen
/// renders rather than an error. The read has no range validation: a future or long-past date is a
/// legitimate question with an empty answer.
/// </remarks>
/// <param name="Date">The requested day, echoed back.</param>
/// <param name="Log">The day's headline pain/mood/note, or <see langword="null"/> when unlogged.</param>
/// <param name="Events">The day's live <c>cycle_events</c>, notes decrypted.</param>
/// <param name="PhaseOverrides">
/// The user's own live phase corrections <b>dated on this day</b> (screen 14). Named for the table,
/// not for a phase, because that is what they are: <b>observed, user-asserted data</b>, never an
/// inference. P4a computes no phase for any day (§G6), so nothing here is derived from anything.
/// </param>
public record CycleDayResponse(
    DateOnly Date,
    CycleDayLogResponse? Log,
    IReadOnlyList<CycleEventResponse> Events,
    IReadOnlyList<PhaseOverrideBoundary> PhaseOverrides);

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

    /// <summary>
    /// A <c>POST /cycle/day/{date}</c> body carried none of pain, mood or notes. Reported under
    /// <see cref="Validation.ValidationProblemBuilder.RequestKey"/> because it belongs to the
    /// combination rather than to any one field. Note that <c>pain: 0</c> <b>does</b> satisfy the
    /// rule (D-08) — only a blank note counts as absent text.
    /// </summary>
    public const string DayLogEmpty = "at least one of pain, mood or notes is required";

    // `MaxWindowDays` lived here until the T12 defect fix, when `GET /symptoms` became the second
    // windowed read to need the same 366-day cap. It now lives on
    // `Validation.ValidationMessages.MaxWindowDays` — the shared home for a message more than one
    // feature genuinely uses — with the identical literal, so nothing on the wire changed. See
    // `Validation.ReadWindow` for the constant it used to pair with here.
}

// `CycleCalendarWindow` lived here until the T12 defect fix, when `GET /symptoms` became the second
// windowed read to need the same 366-day cap. The constant now lives on `Validation.ReadWindow.MaxDays`
// — the shared home for a bound more than one feature genuinely uses, the same rule that hoisted
// `Validation.FieldLimits.MaxNotesLength`. Still a bounded DATE WINDOW, not the D-13 50/100 offset page:
// `GET /cycle/calendar` takes no `limit`/`offset` and does not touch `Symptoms.SymptomPaging` — the
// response is one sparse row per day, so the window itself is the only thing that can make it large.

/// <summary>
/// The 200 body of <c>GET /cycle/calendar?from&amp;to</c> — the bounded, <b>sparse</b> aggregation
/// behind screen 10 (cycle calendar) and screen 8 (dashboard).
/// </summary>
/// <remarks>
/// <para><b>The window is stated in USER-LOCAL DAYS and both ends are inclusive</b>, matched against
/// the day-keyed columns (<c>cycle_day_logs.Day</c>, <c>cycle_events.OccurredOn</c>,
/// <c>symptoms.OccurredOn</c>) — never against a UTC instant recomputed from the bounds. Those columns
/// exist so a range read is a day-keyed index scan rather than a per-row timezone conversion (D-12),
/// and they already hold the user's own day: converting the bounds back into instants here would
/// re-introduce the conversion the columns removed, and would answer differently for a row logged
/// before the user last changed timezone. <b>This is the same rule
/// <c>GET /symptoms</c> follows</b> (T12), deliberately, so the two windowed reads can never disagree
/// about which rows a month contains.</para>
///
/// <para><b>Both parameters are optional and default independently</b> to the corresponding edge of
/// the user's current month, so a bare <c>GET /cycle/calendar</c> is "this month" and <c>?from=</c>
/// alone is "from that day to the end of my month". There is no unbounded read to fall into: whatever
/// the client omits, the response echoes back the bounds actually applied.</para>
///
/// <para><b>A future <c>to</c> is legitimate here</b>, as it is on <c>GET /symptoms</c> and nowhere
/// else in this phase: every WRITE is capped by today (§G8), but a month view spans forward and
/// clamping the window the client had just drawn would make the calendar disagree with itself.</para>
///
/// <para><b>No <c>*_enc</c> column is decrypted on this path.</b> The day row carries
/// <see cref="CycleCalendarDay.HasNotes"/>, a flag, and never the note — a month of notes on the wire
/// to answer a boolean the screen renders as a dot would be plaintext health data spent for nothing.
/// <c>CycleCalendarService</c> takes no <c>IUserCryptoContext</c> at all, which is what keeps it that
/// way.</para>
/// </remarks>
/// <param name="From">The first day of the window actually applied, echoed back.</param>
/// <param name="To">The last day of the window actually applied, echoed back.</param>
/// <param name="Today">
/// The user's local today (D-12), computed server-side. Screen 8 highlights it and screen 10 draws it,
/// and the server's answer is the one that keyed every row — so the client never re-derives it from
/// its own clock.
/// </param>
/// <param name="Timezone">The IANA zone <see cref="Today"/> and the window were resolved in.</param>
/// <param name="Phase">
/// <b>The §G6 envelope, and the only phase-shaped member anywhere in this contract.</b> See
/// <see cref="CyclePhaseAvailabilityResponse"/>.
/// </param>
/// <param name="Days">
/// <b>One row per day that has something on it, ascending.</b> A day with nothing logged is
/// <b>absent</b>, not a zero row: a month view is mostly empty, and 31 empty rows per request is
/// payload the client throws away. An empty window is a <b>200</b> with an empty list — 404 on this
/// route means "no such user" and nothing else (§G12).
/// </param>
public record CycleCalendarResponse(
    DateOnly From,
    DateOnly To,
    DateOnly Today,
    string Timezone,
    CyclePhaseAvailabilityResponse Phase,
    IReadOnlyList<CycleCalendarDay> Days);

/// <summary>
/// Whether the calendar could tell the client what cycle phase its days are in — and in P4a it never
/// can. <b>This is the §G6 envelope: <c>{ available: false, unavailableReason:
/// "phase_engine_not_implemented" }</c>, every time.</b>
/// </summary>
/// <remarks>
/// <para><b>Why the response says anything at all about a phase it does not compute.</b> P4b has to
/// render <i>something</i> where screens 8 and 10 show a phase band, and the two honest options are
/// "we do not know" and silence. Silence is the dangerous one: a client that receives no phase key has
/// to invent its own reading of the gap, and the reading it will pick is the one the mockups imply —
/// that the phase is simply missing for these particular days. An explicit, machine-readable
/// <i>reason</i> is what lets the client draw an unavailable state instead of an empty one, and it is
/// what stops a placeholder from being mistaken for a clinical output later.</para>
///
/// <para><b>Why it lives here rather than on a day row.</b> There is exactly one reason for the whole
/// window, because the reason is a property of the server, not of any day: the engine does not exist
/// yet. Repeating it per day would give the shape of a per-day judgement to something that is not one —
/// and would put a <c>phase</c> key on a day row, which §G6 forbids outright. <b>No
/// <see cref="CycleCalendarDay"/> carries a <c>phase</c>, <c>cycleDay</c> or <c>confidence</c>
/// key.</b></para>
///
/// <para><b>Why it is in the P4a contract at all, given P4a computes nothing.</b> The Dart client is
/// generated exactly once in this phase (T21). <b>What buys P6 its freedom is that these two members
/// EXIST</b>: <see cref="UnavailableReason"/> is a plain nullable string, so P6 answering
/// <c>tracking_paused</c> — or <see langword="null"/> alongside <c>available: true</c> — is a change
/// of VALUE on a field the client already binds, not a schema change, and no regeneration is needed.
/// The reason codes themselves are backend constants (<see cref="CyclePhaseAvailability"/>) and are
/// <b>not</b> exported to Dart: the generated client has no symbol for any of them and compares the
/// string it receives. Nothing in this record should try to smuggle one into the schema — see the
/// remark on <see cref="UnavailableReason"/>.</para>
/// </remarks>
/// <param name="Available">
/// <b>Always <see langword="false"/> in P4a.</b> When P6 ships the engine this becomes true and
/// <see cref="UnavailableReason"/> becomes <see langword="null"/>; the client must branch on this flag
/// and never on the presence of a phase value.
/// </param>
/// <param name="UnavailableReason">
/// One of <see cref="CyclePhaseAvailability"/> when <see cref="Available"/> is
/// <see langword="false"/>; <see langword="null"/> when it is true. <b>P4a can only ever answer
/// <see cref="CyclePhaseAvailability.PhaseEngineNotImplemented"/></b>, which the service sets at its
/// one construction site.
///
/// <para><b>This member must never carry a <c>[DefaultValue]</c>.</b> A schema <c>default</c> on a
/// nullable member is a lie in this toolchain: openapi-generator's dart-dio + built_value output turns
/// it into a builder default and its deserializer skips explicit nulls, so the client could never
/// observe <see langword="null"/> here and would keep reading the P4a code after P6 shipped —
/// contradicting the sentence above it. Pinned by
/// <c>OpenApiContractTests.OpenApi_unavailable_reason_declares_no_default_so_null_survives_into_the_client</c>.</para>
/// </param>
public record CyclePhaseAvailabilityResponse(
    [property: DefaultValue(false)] bool Available,
    string? UnavailableReason);

/// <summary>
/// One day of the calendar that has something on it: the day log's headline scales, plus how many
/// <c>cycle_events</c> and <c>symptoms</c> rows fall on it.
/// </summary>
/// <remarks>
/// <b>No <c>phase</c>, <c>cycleDay</c> or <c>confidence</c> key (§G6)</b> — P4a computes none of them,
/// and a placeholder key is exactly how a not-yet-implemented estimate gets rendered as a clinical
/// fact. The one thing this contract says about phases is the response-level
/// <see cref="CyclePhaseAvailabilityResponse"/>, which says the engine does not exist.
///
/// <para><b>No <c>notes</c> either</b>: the row carries <see cref="HasNotes"/>, and the note text is
/// read one day at a time through <c>GET /cycle/day/{date}</c>.</para>
///
/// <para>The counts are of <b>live</b> rows only: soft-deleted rows (D-13) are excluded from both, as
/// they are from the day's very presence. A day whose every row is a tombstone does not appear.</para>
/// </remarks>
/// <param name="Date">The user-local day (D-12) these values belong to.</param>
/// <param name="Pain">
/// The day log's headline pain, 0–10 (D-08), or <see langword="null"/> when no day log exists or none
/// was recorded. <b>0 is a real datum</b> ("none today") and must never be read as an absence.
/// </param>
/// <param name="Mood">The day log's mood, 1–4, or <see langword="null"/>.</param>
/// <param name="HasNotes">
/// Whether the day log carries an encrypted note. <b>A flag, never the note</b> — see the remarks on
/// <see cref="CycleCalendarResponse"/>.
/// </param>
/// <param name="EventCount">How many live <c>cycle_events</c> rows fall on this day (0–3 in practice: the key is <c>(user, kind, day)</c>).</param>
/// <param name="SymptomCount">How many live <c>symptoms</c> rows fall on this day. D-09 makes one save multi-row, so this is routinely &gt; 1.</param>
public record CycleCalendarDay(
    DateOnly Date,
    int? Pain,
    int? Mood,
    bool HasNotes,
    int EventCount,
    int SymptomCount);

/// <summary>
/// Why a cycle day carries no phase. <b>P4a can only ever answer
/// <see cref="PhaseEngineNotImplemented"/></b> — the phase engine is P6 (§G6), so the calendar
/// reports <c>phase: { available: false, unavailableReason: "phase_engine_not_implemented" }</c> and
/// no day row carries a <c>phase</c>, <c>cycleDay</c> or <c>confidence</c> key at all.
///
/// <para>The other three are declared now and <b>reserved for P6</b>, deliberately: fixing the whole
/// vocabulary up front is what stops P6 from inventing a fifth spelling of a reason P4a already had a
/// word for. They are a <b>P4a invention</b> (§G11), not part of the 2026-07-08 ratification block.
/// Append-only, like every other vocabulary in this codebase.</para>
///
/// <para><b>These are BACKEND constants and none of them is exported to Dart.</b> The generated
/// client's window into this vocabulary is
/// <see cref="CyclePhaseAvailabilityResponse.UnavailableReason"/> — a plain nullable string — so P6
/// emitting <see cref="TrackingPaused"/> is a change of value on a field the T21-generated client
/// already binds, and needs no regeneration. That is the entire mechanism; the strings below reach no
/// Dart symbol, and a client that wants to branch on one compares the literal it received. (The
/// earlier claim that a schema <c>default</c> carried the code into the client was wrong twice over:
/// a default is not an exported constant, and on a nullable member it makes the client unable to read
/// <see langword="null"/> at all — see <see cref="CyclePhaseAvailabilityResponse.UnavailableReason"/>.)</para>
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
