using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Proves <c>POST /onboarding/start</c> — the most expensive anonymous endpoint (Keycloak + Vault +
/// DB work) — carries its OWN per-IP rate-limit policy on top of the global limiter (see
/// <see cref="RateLimitLiveTests"/>). Every request below sends an INVALID body (blank password) so
/// <c>OnboardingService</c>'s own validation rejects it with 400 BEFORE any Keycloak/Vault/DB call —
/// this proves the limiter guards the endpoint itself (not merely its expensive tail) and needs zero
/// cleanup, since no Keycloak user or DB row is ever created.
/// </summary>
[Trait("Category", "LiveStack")]
public class OnboardingRateLimitLiveTests
{
    [Fact]
    public async Task Onboarding_start_limiter_returns_429_after_limit()
    {
        await using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseSetting("RateLimit:OnboardingStartPermitPerMinute", "2");
                builder.UseSetting("Hangfire:EnableServer", "false");
            });
        var client = factory.CreateClient();

        var statuses = new List<HttpStatusCode>();
        for (var i = 0; i < 4; i++)
        {
            var response = await client.PostAsJsonAsync("/onboarding/start", new
            {
                email = "abuse@example.com",
                password = "", // blank -> OnboardingService.StartAsync's own validation returns 400, before Keycloak/Vault
            });
            statuses.Add(response.StatusCode);
        }

        statuses.Take(2).ShouldAllBe(s => s == HttpStatusCode.BadRequest);
        statuses.Skip(2).ShouldAllBe(s => s == HttpStatusCode.TooManyRequests);
    }
}
