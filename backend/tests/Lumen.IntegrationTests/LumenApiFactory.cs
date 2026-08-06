using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Lumen.IntegrationTests;

/// <summary>
/// Shared WebApplicationFactory for live-stack tests. Keeps the app in the Development environment
/// (so dev secrets + plaintext OIDC metadata work) but disables the Hangfire background server so
/// enqueued jobs never execute mid-test.
/// </summary>
/// <remarks>
/// The flag is set via <see cref="IWebHostBuilder.UseSetting"/>, not <c>ConfigureAppConfiguration</c>:
/// top-level <c>Program.cs</c> reads <c>builder.Configuration.GetValue("Hangfire:EnableServer")</c>
/// during service registration, which runs before a <c>ConfigureAppConfiguration</c> source would be
/// layered in at <c>Build()</c> — so that override was silently ignored and Hangfire's Postgres-backed
/// storage was still constructed, connecting to Postgres at startup. <c>UseSetting</c> writes host
/// configuration that is visible at registration time.
/// </remarks>
public class LumenApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder
            .UseSetting("Hangfire:EnableServer", "false")
            // The production default is 5 sign-ups per minute per IP, and every request from this
            // in-process host lands in the same partition (RemoteIpAddress is null → "anonymous").
            // A test class that onboards more than five users therefore starts failing with 429s that
            // say nothing about the behaviour under test — which is exactly what happened once T4 added
            // its PATCH /me cases, and would keep happening as P4a's remaining tasks add theirs.
            // Raised only here: BOTH limiter tests (RateLimitLiveTests, OnboardingRateLimitLiveTests)
            // build their own WebApplicationFactory with explicit low limits, so the coverage that
            // actually asserts the limiter is untouched.
            .UseSetting("RateLimit:OnboardingStartPermitPerMinute", "100");
}
