using System.Security.Claims;
using System.Text.Json;
using Lumen.Api.Hangfire;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Hangfire;

/// <summary>
/// Pure unit tests for <see cref="HangfireDashboardAuthorizationFilter.IsLumenAdmin"/>.
/// No LiveStack — no Hangfire DashboardContext required; the logic is extracted into a
/// testable static method.
/// </summary>
public class HangfireDashboardAuthorizationFilterTests
{
    // --- helpers ----------------------------------------------------------

    private static ClaimsPrincipal AuthenticatedPrincipal(string? realmAccessJson)
    {
        var claims = new List<Claim>();
        if (realmAccessJson is not null)
            claims.Add(new Claim("realm_access", realmAccessJson));

        // Supplying an authenticationType makes IsAuthenticated == true.
        var identity = new ClaimsIdentity(claims, authenticationType: "Bearer");
        return new ClaimsPrincipal(identity);
    }

    private static string RolesJson(params string[] roles) =>
        JsonSerializer.Serialize(new { roles });

    // --- test cases -------------------------------------------------------

    [Fact]
    public void Null_principal_returns_false()
    {
        HangfireDashboardAuthorizationFilter.IsLumenAdmin(null).ShouldBeFalse();
    }

    [Fact]
    public void Unauthenticated_principal_returns_false()
    {
        // No authenticationType → IsAuthenticated == false.
        var identity = new ClaimsIdentity();
        var principal = new ClaimsPrincipal(identity);

        HangfireDashboardAuthorizationFilter.IsLumenAdmin(principal).ShouldBeFalse();
    }

    [Fact]
    public void Authenticated_principal_without_lumen_admin_role_returns_false()
    {
        var principal = AuthenticatedPrincipal(RolesJson("default-roles-lumen", "offline_access"));

        HangfireDashboardAuthorizationFilter.IsLumenAdmin(principal).ShouldBeFalse();
    }

    [Fact]
    public void Authenticated_principal_with_lumen_admin_in_realm_access_returns_true()
    {
        var principal = AuthenticatedPrincipal(RolesJson("default-roles-lumen", "lumen-admin"));

        HangfireDashboardAuthorizationFilter.IsLumenAdmin(principal).ShouldBeTrue();
    }

    [Fact]
    public void Authenticated_principal_with_missing_realm_access_claim_returns_false()
    {
        var principal = AuthenticatedPrincipal(realmAccessJson: null);

        HangfireDashboardAuthorizationFilter.IsLumenAdmin(principal).ShouldBeFalse();
    }

    [Fact]
    public void Authenticated_principal_with_malformed_realm_access_claim_returns_false()
    {
        var principal = AuthenticatedPrincipal(realmAccessJson: "not-valid-json{{{");

        // Must not throw — deny by default on malformed input.
        var act = () => HangfireDashboardAuthorizationFilter.IsLumenAdmin(principal);
        act.ShouldNotThrow();
        act().ShouldBeFalse();
    }

    [Fact]
    public void Authenticated_principal_with_empty_roles_array_returns_false()
    {
        var principal = AuthenticatedPrincipal(RolesJson(/* empty */));

        HangfireDashboardAuthorizationFilter.IsLumenAdmin(principal).ShouldBeFalse();
    }
}
