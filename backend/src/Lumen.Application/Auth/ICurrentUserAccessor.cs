namespace Lumen.Application.Auth;

/// <summary>
/// The authenticated user for the current request, derived from the validated Keycloak JWT
/// (<c>sub</c> → user id). Implemented in the API layer over <c>HttpContext</c>.
/// </summary>
public interface ICurrentUserAccessor
{
    bool IsAuthenticated { get; }

    /// <summary>The current user's id (Keycloak subject). Throws if unauthenticated.</summary>
    Guid UserId { get; }
}
