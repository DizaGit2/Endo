using System.Security.Claims;
using Lumen.Application.Auth;

namespace Lumen.Api.Auth;

/// <summary>
/// <see cref="ICurrentUserAccessor"/> over the validated Keycloak JWT on the current request.
/// The user id is the token <c>sub</c> (JwtBearer is configured with MapInboundClaims=false).
/// </summary>
public sealed class CurrentUserAccessor(IHttpContextAccessor accessor) : ICurrentUserAccessor
{
    public bool IsAuthenticated => accessor.HttpContext?.User.Identity?.IsAuthenticated ?? false;

    public Guid UserId
    {
        get
        {
            var sub = accessor.HttpContext?.User.FindFirst("sub")?.Value
                      ?? accessor.HttpContext?.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            return Guid.TryParse(sub, out var id)
                ? id
                : throw new InvalidOperationException("No authenticated user on the current request.");
        }
    }
}
