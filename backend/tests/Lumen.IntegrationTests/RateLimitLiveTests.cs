using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Proves the global rate limiter is enforced (audit fix: costly endpoints like POST /onboarding/start
/// must be born protected, not merely scaffolded). Uses a low per-window limit via config override.
/// </summary>
[Trait("Category", "LiveStack")]
public class RateLimitLiveTests
{
    [Fact]
    public async Task Global_limiter_returns_429_after_limit()
    {
        await using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder => builder.UseSetting("RateLimit:PermitPerMinute", "3"));
        var client = factory.CreateClient();

        var statuses = new List<HttpStatusCode>();
        for (var i = 0; i < 6; i++)
            statuses.Add((await client.GetAsync("/me")).StatusCode); // anonymous: 401 until the limiter trips

        statuses.ShouldContain(HttpStatusCode.TooManyRequests);
        statuses.Count(s => s == HttpStatusCode.Unauthorized).ShouldBe(3); // first 3 allowed through to authz
    }
}
