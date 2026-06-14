using System.Text.Json;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Verifies Swashbuckle emits an OpenAPI document covering the spine endpoints. The committed
/// snapshot (<c>backend/contract/openapi.json</c>) + the CI drift-guard land with T12.
/// (Static doc — needs no DB/Keycloak.)
/// </summary>
public class OpenApiContractTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    [Fact]
    public async Task OpenApi_documents_the_spine_endpoints()
    {
        var client = factory.CreateClient();

        var json = await client.GetStringAsync("/swagger/v1/swagger.json");
        using var doc = JsonDocument.Parse(json);
        var paths = doc.RootElement.GetProperty("paths");

        paths.TryGetProperty("/onboarding/start", out _).ShouldBeTrue();
        paths.TryGetProperty("/me", out _).ShouldBeTrue();
        paths.TryGetProperty("/health", out _).ShouldBeTrue();
    }

    [Fact]
    public async Task OpenApi_DELETE_me_documents_202_as_success_response()
    {
        var client = factory.CreateClient();

        var json = await client.GetStringAsync("/swagger/v1/swagger.json");
        using var doc = JsonDocument.Parse(json);
        var paths = doc.RootElement.GetProperty("paths");

        // DELETE /me must be present in the contract.
        paths.TryGetProperty("/me", out var mePath).ShouldBeTrue("/me path must exist");
        mePath.TryGetProperty("delete", out var deleteOp).ShouldBeTrue("DELETE /me operation must be documented");

        // The documented success status must be 202 Accepted, not 200.
        deleteOp.GetProperty("responses").TryGetProperty("202", out _)
            .ShouldBeTrue("DELETE /me must document 202 Accepted as its success response");

        // 401 must be documented because the endpoint requires authorization.
        deleteOp.GetProperty("responses").TryGetProperty("401", out _)
            .ShouldBeTrue("DELETE /me must document 401 Unauthorized");
    }
}
