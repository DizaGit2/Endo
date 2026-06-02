namespace Lumen.Application.Auth;

/// <summary>
/// Provisions identities in Keycloak via its admin REST API (the API's confidential client uses a
/// scoped <c>realm-management</c> service account). Returns the new user's id, which becomes the
/// Lumen <see cref="Domain.Entities.User"/> id (= Keycloak subject).
/// </summary>
public interface IKeycloakAdmin
{
    Task<Guid> CreateUserAsync(string email, string password, CancellationToken ct = default);

    /// <summary>Deletes a Keycloak user. Used to compensate a failed multi-system onboarding. No-op if absent.</summary>
    Task DeleteUserAsync(Guid userId, CancellationToken ct = default);
}
