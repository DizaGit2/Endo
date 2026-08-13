using Hangfire;
using Hangfire.Storage;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Pins <c>RouteHandlerOptions.ThrowOnBadRequest = true</c> (T3) by reading the built host's options
/// rather than by exercising an endpoint (T3 review round 2, finding 2).
///
/// <para>
/// That one line is why a minimal-API binding failure reaches
/// <see cref="Lumen.Api.ProblemExceptionHandler"/> at all instead of short-circuiting into a bodyless
/// 400 — and it had no coverage. The framework default is <c>IsDevelopment()</c>, and
/// <see cref="LumenApiFactory"/> runs in Development, so the whole suite answered identically with the
/// line deleted (verified: with it commented out, only the Production row below turns red). Its entire
/// value is in Production, so that is where the assertion bites. The Development row rides along to
/// state the invariant the §A P4a row claims — the two environments must not diverge — and is
/// deliberately not load-bearing.
/// </para>
///
/// <para>
/// Fifteen downstream P4a tasks edit <c>Program.cs</c>; this fails the moment one of them drops the line.
/// (Static host — needs no DB/Keycloak; not a [Category=LiveStack] test.)
/// </para>
/// </summary>
public class RouteHandlerOptionsTests
{
    /// <summary>
    /// Hangfire's Postgres storage is built eagerly during startup and retries for ~45 s against a
    /// database that is not there, which is the only slow thing about booting this host. The test
    /// never enqueues a job, so the storage is replaced with a stub that fails loudly if anything
    /// tries to use it. <see cref="IGlobalConfiguration"/> goes too: resolving it is what runs
    /// <c>UsePostgreSqlStorage(...)</c> in the first place, so leaving it in place would pay the cost
    /// even with <see cref="JobStorage"/> already stubbed.
    /// </summary>
    private sealed class StubJobStorage : JobStorage
    {
        public override IMonitoringApi GetMonitoringApi() =>
            throw new NotSupportedException("This host exists only to read options; no job storage is available.");

        public override IStorageConnection GetConnection() =>
            throw new NotSupportedException("This host exists only to read options; no job storage is available.");
    }

    private sealed class EnvironmentApiFactory(string environment) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder
                .UseEnvironment(environment)
                .UseSetting("Hangfire:EnableServer", "false")
                // Explicit, non-sentinel, unreachable. StartupGuards refuses to start outside
                // Development on a missing or dev-default secret, and only inspects the strings —
                // nothing here is ever dialled, because the host is built and never called.
                .UseSetting("ConnectionStrings:Lumen", "Host=127.0.0.1;Port=1;Database=lumen;Username=lumen_app;Password=not-a-dev-sentinel")
                .UseSetting("Vault:Address", "https://vault.unreachable.invalid")
                .UseSetting("Vault:Token", "not-a-dev-sentinel")
                .UseSetting("Keycloak:BaseUrl", "https://auth.unreachable.invalid")
                .UseSetting("Keycloak:AdminClientSecret", "not-a-dev-sentinel");

            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<JobStorage>();
                services.RemoveAll<IGlobalConfiguration>();
                services.AddSingleton<IGlobalConfiguration>(GlobalConfiguration.Configuration);
                services.AddSingleton<JobStorage>(new StubJobStorage());
            });
        }
    }

    // Literals rather than Environments.Production/Development: those are static readonly, not const,
    // so they cannot be attribute arguments.
    [Theory]
    [InlineData("Production")]
    [InlineData("Development")]
    public void ThrowOnBadRequest_is_on_in_every_environment(string environment)
    {
        using var factory = new EnvironmentApiFactory(environment);

        var services = factory.Services;

        // Guard the guard: if the host silently fell back to Development, the Production row would
        // pass on the framework default and prove nothing.
        services.GetRequiredService<IHostEnvironment>().EnvironmentName.ShouldBe(environment);

        services.GetRequiredService<IOptions<RouteHandlerOptions>>().Value.ThrowOnBadRequest.ShouldBeTrue(
            $"Program.cs must configure RouteHandlerOptions.ThrowOnBadRequest explicitly: in '{environment}' " +
            "the framework default would otherwise let a binding failure short-circuit into a bodyless " +
            "400 instead of reaching ProblemExceptionHandler's one 400 body.");
    }
}
