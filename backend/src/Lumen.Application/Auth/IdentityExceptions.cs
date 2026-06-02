namespace Lumen.Application.Auth;

/// <summary>The email/username already exists in the identity provider (maps to HTTP 409).</summary>
public sealed class DuplicateUserException(string message) : Exception(message);

/// <summary>The identity provider (Keycloak) returned an unexpected error (maps to HTTP 502).</summary>
public sealed class IdentityProviderException(string message) : Exception(message);
