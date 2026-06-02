using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Verifies Swashbuckle emits an OpenAPI document covering the spine endpoints. The committed
/// snapshot (<c>backend/contract/openapi.json</c>) + the CI drift-guard land with T12.
/// (Static doc — needs no DB/Keycloak.)
/// </summary>
public class OpenApiContractTests(WebApplicationFactory<Program> factory) : IClassFixture<WebApplicationFactory<Program>>
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
}
