using System.Security.Claims;
using System.Text.Json;
using Hangfire.Dashboard;
using Microsoft.AspNetCore.Http;

namespace Lumen.Api.Hangfire;

/// <summary>
/// Hangfire dashboard authorization filter that restricts access to users who are
/// authenticated and hold the <c>lumen-admin</c> Keycloak realm role.
///
/// <para>
/// Keycloak realm roles arrive in the JWT under the <c>realm_access</c> claim as a JSON
/// object <c>{"roles":["lumen-admin", ...]}</c>.  Because <c>MapInboundClaims=false</c> is
/// configured on the JWT bearer handler the claim is NOT flattened into .NET role claims —
/// we parse the JSON ourselves.
/// </para>
///
/// <para>
/// The authorization decision is extracted into the public static <see cref="IsLumenAdmin"/>
/// method so it can be unit-tested without constructing Hangfire's <see cref="DashboardContext"/>.
/// </para>
/// </summary>
public sealed class HangfireDashboardAuthorizationFilter : IDashboardAuthorizationFilter
{
    /// <inheritdoc />
    public bool Authorize(DashboardContext context)
    {
        var httpContext = context.GetHttpContext();
        return IsLumenAdmin(httpContext.User);
    }

    /// <summary>
    /// Returns <see langword="true"/> if <paramref name="principal"/> is authenticated and
    /// the <c>realm_access.roles</c> array in the Keycloak JWT contains <c>"lumen-admin"</c>.
    /// Returns <see langword="false"/> for a null, unauthenticated, or malformed principal —
    /// it never throws.
    /// </summary>
    public static bool IsLumenAdmin(ClaimsPrincipal? principal)
    {
        if (principal?.Identity?.IsAuthenticated is not true)
            return false;

        var realmAccess = principal.FindFirst("realm_access")?.Value;
        if (string.IsNullOrEmpty(realmAccess))
            return false;

        try
        {
            using var doc = JsonDocument.Parse(realmAccess);
            if (!doc.RootElement.TryGetProperty("roles", out var rolesElement) ||
                rolesElement.ValueKind != JsonValueKind.Array)
                return false;

            foreach (var role in rolesElement.EnumerateArray())
            {
                if (role.ValueKind == JsonValueKind.String &&
                    role.GetString() == "lumen-admin")
                    return true;
            }
        }
        catch (JsonException)
        {
            // Malformed claim — deny by default, never throw.
            return false;
        }

        return false;
    }
}
