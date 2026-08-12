using Lumen.Api.Onboarding;
using Lumen.Domain.Entities;

// No `namespace` declaration here — these types stayed in the GLOBAL namespace when T4 moved them out
// of Program.cs, and leaving them there kept that move a provable no-op at the contract level.
//
// CORRECTED BY T22 (§G12; the original comment here stated the opposite and was wrong): the absence of
// a namespace is a STYLE CHOICE, NOT a contract guarantee. `AddSwaggerGen()` is bare — no
// `CustomSchemaIds` — so the OpenAPI schema id is `type.Name` and is namespace-INDEPENDENT. Adding a
// namespace to this file would NOT rename `OnboardingStartRequest`, and the claim that it would break
// `client/lib/core/network/` was never true. Verified empirically twice: T4 confirmed the snapshot was
// byte-identical across the move, and `Lumen.Api/Cycle/CycleContracts.cs` DOES declare a namespace
// while still emitting bare ids (`LogCycleEventRequest`, `CycleEventResponse`, …).
//
// THE REAL HAZARD is a short-type-name COLLISION between two feature folders: two types called
// `SaveRequest` in different namespaces throw a duplicate-schemaId error at document generation. So the
// rule that actually binds is that every DTO short name is globally unique across all feature folders.
// The file-per-feature shape `<Feature>/<Feature>Contracts.cs` is the T3 convention and still stands.

/// <summary>
/// Sign-up payload for <c>POST /onboarding/start</c>. <c>Email</c>/<c>Password</c> are required;
/// everything else is optional and falls back to the column defaults (<c>locale</c> es-ES,
/// <c>timezone</c> Europe/Madrid, <c>policyVersion</c> v1-draft).
/// </summary>
/// <remarks>
/// Moved verbatim out of <c>Program.cs</c> by T4 — the member list, their order and their nullability
/// are unchanged, so the emitted schema is identical.
/// </remarks>
public record OnboardingStartRequest(
    string Email,
    string Password,
    string? DisplayName,
    string? Locale,
    string? Timezone,
    string? PolicyVersion);

/// <summary>
/// The 200 body of <c>POST /onboarding/start</c>: the new user's id, which is also the Keycloak
/// subject.
/// </summary>
/// <remarks>
/// Exists because the handler used to answer with an anonymous <c>new { userId }</c>. That is
/// invisible to Swashbuckle, which emitted <c>"schema": {}</c> — an untyped 200 the generated Dart
/// client cannot bind to anything. The wire shape is unchanged: <c>{ "userId": "..." }</c>.
/// </remarks>
public record OnboardingStartResponse(Guid UserId);

// --- T16: the D-02 baseline step (screen 4) -------------------------------------------------------
//
// NOTE — no `[DefaultValue]` anywhere below, deliberately. T13 shipped one on a NULLABLE member and it
// made the property un-nullable in the generated Dart client forever (openapi-generator's dart-dio +
// built_value output turns a schema `default` into a builder default, and its deserializer skips
// explicit nulls). EVERY member here is nullable, because D-02 makes each answer skippable, so a
// default on any of them would be that same defect six times over.

/// <summary>
/// Body of <c>POST /onboarding/baseline</c> — screen 4's answers, landing in their §A-mandated homes:
/// five <b>encrypted</b> <c>user_profile_enc</c> columns plus <b>one</b> <c>body_metrics.weight_kg</c>
/// row (rider 4 — weight has one source of truth and is never duplicated onto the profile).
///
/// <para><b>MERGE semantics: <see langword="null"/> means "leave unchanged", never "clear".</b> Same
/// rule as <c>PATCH /me</c>, and it is what makes this a step the user can revisit — D-02 lets them
/// skip it, come back to it, and answer one more question at a time. "Skip" means not calling the
/// endpoint at all, so a body carrying <b>no</b> field is a 400 under <c>request</c>: a no-op POST is
/// a client bug and answering 200 would let it ship.</para>
///
/// <para><b>Bounds are structural only (§G7/§G11).</b> There is <b>no age gate and no clinical
/// height/weight range</b>: C-12 makes the population a design target, explicitly <i>"NOT a
/// data-entry/age gate"</i>, and L-01 is unresolved. What the fields do carry is a storage-domain
/// guard — see <see cref="BaselineStructuralDomain"/> — that refuses only what cannot be a
/// measurement at all.</para>
///
/// <para><b>For P4b:</b> screen 4 collects <b>Age</b>, but §A:60 fixes storage as <b>DOB</b>. This API
/// takes a date of birth; the client must not synthesise one from an age stepper.</para>
/// </summary>
/// <param name="Dob">
/// Date of birth. Capped by the user's local today and by <b>nothing else</b> (§G8 — the backdate
/// floor is <c>cycle_events</c>-only, and every real DOB is decades below it).
/// </param>
/// <param name="HeightCm">
/// Height in whole centimetres (D-06: metric-only v1). Stored on the profile rather than in
/// <c>body_metrics</c> because height is a stable attribute, not a tracked time series.
/// </param>
/// <param name="WeightKg">
/// Weight in kilograms, at most one decimal place. <b>Not a profile column</b> — it seeds a
/// <c>body_metrics.weight_kg</c> row keyed on the user's local day, upserted so a re-submitted step
/// never stacks duplicates.
/// <para><b>Obligation on P4b:</b> this is a <c>decimal</c> here but the schema is
/// <c>number/format:double</c>, so the generated Dart client binds a <c>double</c>. Send a value the
/// user actually typed — a <i>computed</i> double serialises as <c>0.30000000000000004</c> and is
/// rejected by the one-decimal rule. Screen 4 collects a single decimal, so the client must not
/// arrive here via unit arithmetic.</para>
/// </param>
/// <param name="EndoStatus">
/// One of <see cref="UserProfileEnc.EndoStatuses"/> — <c>diagnosed</c>, <c>suspected</c> or
/// <c>not_applicable</c>. Matched case-sensitively; there is no default, because an unanswered
/// question must stay null rather than be recorded as <c>not_applicable</c>, which is a real answer.
/// </param>
/// <param name="RasrmStage">
/// The rASRM stage, <c>1</c>–<c>4</c> (rendered I–IV). <b>Independent of
/// <paramref name="EndoStatus"/></b>: a diagnosed user often does not know their stage, so null is a
/// normal answer for a diagnosed user rather than a contradiction.
/// </param>
/// <param name="DiagnosedOn">
/// The diagnosis month as <b><c>"yyyy-MM"</c></b>. A <b>string</b>, not a date, and it must stay one:
/// typing it as a date would make the generated Dart client parse it into a full <c>DateTime</c> and
/// send back a day the user never gave.
/// </param>
public record SaveBaselineRequest(
    DateOnly? Dob,
    int? HeightCm,
    decimal? WeightKg,
    string? EndoStatus,
    int? RasrmStage,
    string? DiagnosedOn);

/// <summary>
/// The 200 body of <c>POST /onboarding/baseline</c>, and the same projection <c>GET /me</c> splices
/// into <c>MeResponse</c>: the caller's stored baseline, <b>decrypted back out of the row</b>.
/// </summary>
/// <remarks>
/// <para><b>It re-reads rather than echoing the request</b>, so a round-trip failure — a bad encoder,
/// a lost merge, a weight that landed on the wrong day — is visible in the response to the very call
/// that caused it, instead of at the next <c>GET /me</c>.</para>
///
/// <para><b>Every member is nullable and stays nullable.</b> D-02 makes each answer skippable, so
/// "not answered" has to be expressible; see the no-<c>[DefaultValue]</c> note above this file's
/// contracts.</para>
/// </remarks>
/// <param name="Dob">The stored date of birth, or null.</param>
/// <param name="HeightCm">The stored height in centimetres, or null.</param>
/// <param name="EndoStatus">The stored endo status code, or null.</param>
/// <param name="RasrmStage">The stored rASRM stage 1–4, or null.</param>
/// <param name="DiagnosedOn">The stored diagnosis month as <c>"yyyy-MM"</c>, or null.</param>
/// <param name="LatestWeightKg">
/// The value of the user's <b>most recent live</b> <c>weight_kg</c> row — not necessarily the one this
/// request wrote, and never a tombstoned one. Named <c>latest</c> rather than <c>weight</c> because
/// P5 turns this column into a series the user edits and deletes independently of onboarding.
/// </param>
public record BaselineResponse(
    DateOnly? Dob,
    int? HeightCm,
    string? EndoStatus,
    int? RasrmStage,
    string? DiagnosedOn,
    decimal? LatestWeightKg);

// --- T17: the three D-02 preference steps (screens 5, 6, 7) ---------------------------------------
//
// Three rules bind every DTO below.
//
// 1. NO `[DefaultValue]`, for the same reason as the baseline block above — and here the temptation is
//    sharper, because each of these sets HAS a documented default (§G10). Documenting it as a schema
//    `default` would put it on a NULLABLE member, which is exactly T13's defect: openapi-generator's
//    dart-dio + built_value output turns a schema `default` into a builder default and its deserializer
//    skips explicit nulls, so `goals: null` would become un-observable in the generated client forever
//    and "the user has not answered" would arrive as "the user picked the defaults".
//
// 2. THE DEFAULTS ARE SEEDS, NOT IMPLICIT STATE. A skipped step writes NO rows, and the seed is applied
//    by the READ projection (`OnboardingStepsService.ReadGoalsAsync` and friends). That is the whole
//    reason "no row" and "row with the flag false" are different states: the entities say so
//    ("records that the user was asked and said no, which is a different fact from never having seen
//    the question"), and one shared projection is what stops T18's `/onboarding/complete` and any later
//    `GET` from disagreeing about what "skipped" means.
//
// 3. EVERY RESPONSE LISTS THE COMPLETE VOCABULARY, in the frozen §G10 order, with a boolean per code —
//    never "the selected ones". The client renders these as a fixed list of toggles, and a sparse
//    answer would make it re-derive the vocabulary locally and drift from the server on the first
//    append.

/// <summary>
/// Body of <c>POST /onboarding/goals</c> — screen 5's multi-select.
/// </summary>
/// <remarks>
/// <para><b>FULL REPLACE, not merge.</b> The body is the row set's whole desired state: a goal the user
/// leaves out is <b>deselected</b>, not left standing. Decided the way T11 decided <c>symptoms</c> and
/// on the same test §G12 names — <i>how many surfaces write the row</i>, not the verb. Exactly one
/// surface writes <c>user_goals</c> (screen 5 now, its settings twin later, never both in one request),
/// and <b>clearing is the affordance</b>: the goals are toggle chips, so under a merge a goal would be
/// addable but never removable. <c>POST</c> is semantically neutral (§C.3), so <c>POST</c> = replace
/// misleads nobody the way <c>PATCH</c> = replace would.</para>
/// </remarks>
/// <param name="Goals">
/// The selected goal codes, from <see cref="UserGoal.Codes"/>. <b>Required, and at least one</b> (D-14):
/// unlike hormones and notifications, "none" is not a state screen 5 can produce, and a user with no
/// goal at all has nothing for P6's insight copy to address. Duplicates are de-duplicated silently —
/// chip order and repetition are UI noise — and there is no maximum, because the maximum is the
/// vocabulary. Matched case-sensitively; an unknown code is a 400 keyed <c>goals[i]</c>.
/// </param>
public record SaveGoalsRequest(IReadOnlyList<string>? Goals);

/// <summary>
/// The 200 body of <c>POST /onboarding/goals</c>, and the projection T18's <c>GET /onboarding/state</c>
/// reads: <b>all five</b> ratified goals in frozen order, each with its stored (or seeded) flag.
/// </summary>
/// <param name="Goals">Every code in <see cref="UserGoal.Codes.All"/> order, never only the selected ones.</param>
public record GoalsResponse(IReadOnlyList<GoalSelection> Goals);

/// <summary>One goal code and whether the user currently has it selected.</summary>
/// <param name="Code">A member of <see cref="UserGoal.Codes"/> — the wire/DB code, never a display label.</param>
/// <param name="Selected">
/// <see langword="false"/> is a real answer ("asked, said no"), not an absence. A user who has never
/// answered the step reads back <see cref="UserGoal.DefaultSelected"/> instead.
/// </param>
public record GoalSelection(string Code, bool Selected);

/// <summary>
/// Body of <c>POST /onboarding/hormones</c> — screen 6's chart selection.
/// </summary>
/// <remarks>
/// <para><b>Charted ≠ extracted (D-14), and that is the load-bearing semantic of this whole step.</b>
/// The flag decides only whether a series is <i>drawn</i>. P7b still extracts every one of the seven
/// hormones from every lab, so un-charting one hides a line on a chart and destroys nothing — which is
/// why an empty selection is allowed here and a 400 on goals.</para>
///
/// <para><b>FULL REPLACE</b>, for the same reason as <see cref="SaveGoalsRequest"/>.</para>
/// </remarks>
/// <param name="ChartedHormones">
/// The hormone codes to chart, from <see cref="Lumen.Domain.Reference.HormoneCatalog.Codes"/>.
/// <b>Required, but an empty array is valid</b> — "chart nothing" is a real answer and is not the same
/// state as skipping the step. The codes are <c>estradiol</c> and <c>glp1</c>; the display labels
/// "Estrogen" and "GLP-1" are i18n source strings and are never accepted here (B16).
/// </param>
public record SaveHormonePrefsRequest(IReadOnlyList<string>? ChartedHormones);

/// <summary>
/// The 200 body of <c>POST /onboarding/hormones</c>: <b>all seven</b> hormones in frozen order, each
/// with its stored (or seeded) charted flag.
/// </summary>
/// <param name="Hormones">Every code in the §G10 display order, never only the charted ones.</param>
public record HormonePrefsResponse(IReadOnlyList<HormoneSelection> Hormones);

/// <summary>One hormone code and whether its series is drawn.</summary>
/// <param name="Code">A member of <see cref="Lumen.Domain.Reference.HormoneCatalog.Codes"/>.</param>
/// <param name="Charted">
/// Whether the series is drawn. <b>Never whether the hormone is extracted</b> — P7b extracts all seven
/// regardless.
/// </param>
public record HormoneSelection(string Code, bool Charted);

/// <summary>
/// Body of <c>POST /onboarding/notifications</c> — screen 7, which is two things at once: the
/// category preferences, and (behind "Allow &amp; finish") the push-token registration §C.1 lists among
/// onboarding's writes.
/// </summary>
/// <remarks>
/// <para><b>The two halves are SEPARABLE.</b> A user may decline the OS permission prompt, or the
/// client may not have a token yet, and either way the categories they chose must still be recorded —
/// so <see cref="PushToken"/> and <see cref="Platform"/> are optional. What they may not be is
/// <i>half</i> supplied: a token with no platform is a device P9a could never dispatch to, and a
/// platform with no token is not a registration at all, so one without the other is a 400 under
/// <c>request</c>.</para>
///
/// <para><b>When both are present the write is COMPOSED with T15's device upsert</b>, in one unit of
/// work: the four preference rows and the <c>user_devices</c> row commit or roll back together. See
/// <see cref="OnboardingStepsService.SaveNotificationPrefsAsync"/>.</para>
/// </remarks>
/// <param name="EnabledCategories">
/// The categories that may notify, from
/// <see cref="Lumen.Domain.Reference.HormoneCatalog.NotificationCategories"/>. <b>Required, but an empty
/// array is valid</b> — muting everything is a real answer. The code is <c>phase_shift</c>, singular;
/// screen 7's plural "Phase shifts" is display drift and the canonical label is "Phase shift" (B16).
/// </param>
/// <param name="PushToken">
/// The FCM/APNs registration token, 1–<see cref="UserDevice.PushTokenMaxLength"/> characters (the
/// existing column's width — <b>not a P4a invention</b>, §G11). Optional; blank counts as absent.
/// <b>PII (§F):</b> never logged, never echoed back — there is deliberately no corresponding member on
/// <see cref="NotificationPrefsResponse"/>.
/// </param>
/// <param name="Platform">
/// One of <see cref="UserDevice.Platforms"/> — <c>ios</c> or <c>android</c>. Optional, but required
/// whenever <paramref name="PushToken"/> is present; anything outside the vocabulary is a 400, because
/// the code decides which provider P9a dispatches through.
/// </param>
public record SaveNotificationPrefsRequest(
    IReadOnlyList<string>? EnabledCategories,
    string? PushToken,
    string? Platform);

/// <summary>
/// The 200 body of <c>POST /onboarding/notifications</c>: <b>all four</b> categories in frozen order,
/// plus whether this call also registered a device.
/// </summary>
/// <remarks>
/// <b>There is no <c>pushToken</c> member and there must never be one</b> — the same rule
/// <c>RegisterDeviceResponse</c> follows (§F): the caller already holds the token, and echoing it would
/// put PII into client logs, proxy traces and every HAR file a support ticket carries.
/// </remarks>
/// <param name="Categories">Every code in the screen-7 order, never only the enabled ones.</param>
/// <param name="DeviceRegistered">
/// Whether a <c>user_devices</c> row was written by this call. <see langword="false"/> whenever the
/// request carried no token — which is a normal outcome, not a failure, so it is reported rather than
/// rejected.
/// </param>
public record NotificationPrefsResponse(
    IReadOnlyList<NotificationCategorySelection> Categories,
    bool DeviceRegistered);

/// <summary>One notification category and whether it may notify.</summary>
/// <param name="Code">
/// A member of <see cref="Lumen.Domain.Reference.HormoneCatalog.NotificationCategories"/>.
/// </param>
/// <param name="Enabled">
/// Whether the category may notify. <b>P4a stores this and dispatches nothing</b> (§G14); the rows
/// exist so D-19's per-user schedule has something to read.
/// </param>
public record NotificationCategorySelection(string Code, bool Enabled);

// --- T18: the cycle seed (B15), the completion gate and the resume read ---------------------------
//
// The no-`[DefaultValue]` rule from the two blocks above binds here too, and the temptation is at its
// sharpest on `SaveOnboardingCycleRequest`: three of its four members HAVE a documented default. Putting
// any of them in the schema is T13's defect — dart-dio/built_value turns a schema `default` into a
// builder default and its deserializer skips explicit nulls, so "the user did not answer the regularity
// question" would arrive as "the user chose `somewhat`", and the server could never tell them apart.
// The defaults are applied on the SERVER, from the entity constants, and stated only in these XML docs.

/// <summary>
/// Body of <c>POST /onboarding/cycle</c> — screen 3, the one <b>mandatory</b> step of D-02.
///
/// <para><b>It writes two tables in one unit of work</b> (§G12): the <c>user_cycle_settings</c> row,
/// through T14's stage-only <c>CycleSettingsService.ApplyOnboardingCycleAsync</c>, and the single
/// onboarding-seeded <c>cycle_events.period_start</c> row that anchors every cycle the app will ever
/// draw. They commit or roll back together — a settings row without its anchor would make the user look
/// onboarded to <c>GET /settings/cycle</c> while <c>/onboarding/complete</c> still refused them.</para>
///
/// <para><b>409 after completion.</b> Once <c>POST /onboarding/complete</c> has stamped the account this
/// endpoint is closed: moving the seeded anchor post-hoc silently re-dates every cycle measured from it.
/// Post-completion edits go through <c>POST /cycle/events</c> and <c>PATCH /settings/cycle</c>, which
/// are the surfaces built for exactly that. The other four steps stay open (T17) — this is the only one
/// that owns a value later data is measured against.</para>
///
/// <para><b>Re-posting BEFORE completion is normal, and the three self-report members MERGE.</b> Screen
/// 3 is where a user goes back to fix a mistyped date, and that correction sends
/// <c>lastPeriodStart</c> and nothing else. So an omitted member <b>leaves the stored value
/// unchanged</b>; the documented defaults below apply only when the <c>user_cycle_settings</c> row is
/// being CREATED. <c>lastPeriodStart</c> itself is REQUIRED on every post — it is the one field the
/// step exists to collect. The consequence for P4b: this endpoint is safe to call with a partial body,
/// and it has to be, because <c>GET /onboarding/state</c> returns <c>lastPeriodStart</c> and none of
/// the other three, so a client resuming a partial onboarding could not re-send them if it tried.</para>
/// </summary>
/// <param name="LastPeriodStart">
/// The day the user's last period began — <b>required</b>, and the only required field on the whole
/// onboarding flow. <c>default(DateOnly)</c> (0001-01-01, what an unset date binds to) is refused as
/// "required" rather than as a floor violation, because that is what it means.
/// <para><b>The floor applies here (§G8).</b> This and <c>POST /cycle/events</c> are the <b>only two</b>
/// P4a writes bounded below: <c>&gt;= UserDayInfo.BackdateFloor</c> (account creation − 2 y, D-13) as
/// well as <c>&lt;=</c> the user's local today. Every other dated write is capped by today alone.</para>
/// </param>
/// <param name="AvgCycleLengthDays">
/// The user's self-reported average cycle length. Omitted on the FIRST post → the T6 default of
/// <b>28</b>; omitted on a RE-POST → the stored value is left alone (see the merge note above).
/// <para><b>§G7: this is never clinically validated.</b> The only rejection is structural — a positive
/// integer that fits the <c>smallint</c> column. A value outside the sanity band is <b>stored</b> and
/// answered with a non-blocking code in <see cref="OnboardingCycleResponse.Warnings"/>; the C-03
/// clinical band is clinician-UNSIGNED and has no home in <c>backend/src</c> this phase.</para>
/// </param>
/// <param name="AvgPeriodLengthDays">
/// The user's self-reported average period length. Omitted on the FIRST post → <b>null</b>,
/// deliberately and not 5 or any other figure: screen 3 never asks, and a seeded value would be a
/// self-report the user never made. Omitted on a RE-POST → the stored value is left alone.
/// </param>
/// <param name="Regularity">
/// One of <see cref="UserCycleSettings.RegularityValues"/> — <c>regular</c>, <c>somewhat</c> or
/// <c>irregular</c>. Omitted on the FIRST post → <c>somewhat</c>; omitted on a RE-POST → the stored
/// code is left alone. Matched case-sensitively; the near-miss "sometimes" is a 400 rather than data P6
/// cannot read.
/// </param>
public record SaveOnboardingCycleRequest(
    DateOnly? LastPeriodStart,
    int? AvgCycleLengthDays,
    int? AvgPeriodLengthDays,
    string? Regularity);

/// <summary>
/// The 200 body of <c>POST /onboarding/cycle</c>: what was <b>stored</b>, with every omitted field
/// resolved to the default the server applied.
/// </summary>
/// <remarks>
/// Answering with the resolved values rather than echoing the request is what lets screen 3 show the
/// user the 28 they never typed, and it is how a client learns the defaults without hard-coding them.
/// </remarks>
/// <param name="LastPeriodStart">The stored anchor day — the <c>cycle_events.period_start</c> row's date.</param>
/// <param name="AvgCycleLengthDays">The stored self-report, or the applied default.</param>
/// <param name="AvgPeriodLengthDays">The stored self-report, or null when it was not asked for.</param>
/// <param name="Regularity">The stored code, or the applied default.</param>
/// <param name="Warnings">
/// Non-blocking sanity codes from <c>CycleSettingsWarnings</c> (§G7) — <b>empty on the common path</b>,
/// and never a reason the save did not happen. The same list <c>GET/PATCH /settings/cycle</c> returns,
/// computed by the same method so the two cannot drift.
/// </param>
public record OnboardingCycleResponse(
    DateOnly LastPeriodStart,
    int AvgCycleLengthDays,
    int? AvgPeriodLengthDays,
    string Regularity,
    IReadOnlyList<string> Warnings);

/// <summary>
/// The 200 body of <c>POST /onboarding/complete</c> — the D-02 terminal state.
/// </summary>
/// <param name="CompletedAt">
/// When onboarding was completed. On a repeat call this is the <b>original</b> instant, never the
/// current one: the stamp is claimed under <c>WHERE OnboardingCompletedAt IS NULL</c>, so two
/// simultaneous "Finish" taps agree on one answer instead of racing the column forward.
/// </param>
/// <param name="AlreadyCompleted">
/// Whether this call found the account already stamped. Reported rather than turned into a 409, because
/// a repeated <c>/complete</c> is a normal outcome of a retried request and the user's intent is already
/// satisfied — but the client still needs to know it was not the one that finished the flow.
/// </param>
public record OnboardingCompleteResponse(DateTimeOffset CompletedAt, bool AlreadyCompleted);

/// <summary>
/// The 200 body of <c>GET /onboarding/state</c> — P4b's single <b>resume read</b>: where the user got
/// to, what is still owed, and the current value of every preference set so a half-finished flow can be
/// re-rendered without five more calls.
/// </summary>
/// <remarks>
/// <para><b>The three preference lists come from T17's read projections</b>
/// (<c>OnboardingStepsService.ReadGoalsAsync</c> and friends) and are never re-derived here. Those
/// projections are the single place "a skipped step" is given a meaning — a skipped step persists no
/// rows, so the documented seed is applied on read — and a second, independent restatement of it is
/// exactly the drift they exist to prevent (§G12).</para>
///
/// <para><b>§G6: nothing here is computed.</b> There is no phase, no cycle day, no prediction and no
/// confidence, and there must never be one: every member below is either a stored value or the presence
/// of a row.</para>
/// </remarks>
/// <param name="Completed">Whether <c>users.onboarding_completed_at</c> is set. The same fact <c>GET /me.onboardingCompleted</c> reports.</param>
/// <param name="CompletedAt">When it was set, or null.</param>
/// <param name="MissingMandatorySteps">
/// The mandatory steps still unanswered — <c>["cycle"]</c> or empty. The same list a premature
/// <c>POST /onboarding/complete</c> returns in its 409, so the client can pre-empt that conflict.
/// <b>Gated on <see cref="Completed"/></b>: once the account is stamped, this is always empty, even if
/// the underlying anchor is later retracted (<c>CycleProvided</c> can still go back to <see
/// langword="false"/> — only this list, and the 409 it mirrors, are frozen by completion).
/// </param>
/// <param name="CycleProvided">Whether the user has at least one live <c>period_start</c> — by either route.</param>
/// <param name="BaselineProvided">
/// Whether screen 4 has been answered: any stored <c>user_profile_enc</c> condition field <b>or</b> a
/// live <c>body_metrics.weight_kg</c> row (rider 4 keeps weight off the profile, so the profile alone
/// cannot answer this).
/// </param>
/// <param name="GoalsProvided">Whether screen 5 was answered — i.e. whether any <c>user_goals</c> row exists.</param>
/// <param name="HormonesProvided">Whether screen 6 was answered.</param>
/// <param name="NotificationsProvided">Whether screen 7 was answered.</param>
/// <param name="LastPeriodStart">
/// The most recent <b>live</b> <c>period_start</c> day, or null. A retracted row is not a last period
/// start, so the soft-delete filter is load-bearing here.
/// </param>
/// <param name="Goals">All five goals in frozen order, with the stored — or seeded — flag.</param>
/// <param name="Hormones">All seven hormones in frozen order, with the stored or seeded charted flag.</param>
/// <param name="Notifications">All four categories in frozen order, with the stored or seeded flag.</param>
public record OnboardingStateResponse(
    bool Completed,
    DateTimeOffset? CompletedAt,
    IReadOnlyList<string> MissingMandatorySteps,
    bool CycleProvided,
    bool BaselineProvided,
    bool GoalsProvided,
    bool HormonesProvided,
    bool NotificationsProvided,
    DateOnly? LastPeriodStart,
    IReadOnlyList<GoalSelection> Goals,
    IReadOnlyList<HormoneSelection> Hormones,
    IReadOnlyList<NotificationCategorySelection> Notifications);
