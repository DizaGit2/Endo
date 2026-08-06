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
