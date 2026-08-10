using Lumen.Api.Onboarding;
using Lumen.Domain.Entities;

// DELIBERATELY NO `namespace` DECLARATION (§G12). These types live in the GLOBAL namespace, exactly
// where they lived at the bottom of Program.cs. Swashbuckle derives an OpenAPI schema name from the
// type name, and the generated Dart client binds to that name — so giving these records a namespace
// would rename `OnboardingStartRequest` in the contract and break `client/lib/core/network/`. Every
// P4a feature-contract file follows this shape: `<Feature>/<Feature>Contracts.cs`, no namespace.

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
