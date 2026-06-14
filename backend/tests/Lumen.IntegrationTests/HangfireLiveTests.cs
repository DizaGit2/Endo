using Hangfire;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Integration tests (LiveStack) verifying that Hangfire is registered and its Postgres
/// schema is initialised, and that the dashboard at /hangfire is not publicly accessible.
/// </summary>
[Trait("Category", "LiveStack")]
public class HangfireLiveTests(LumenApiFactory factory)
    : IClassFixture<LumenApiFactory>
{
    [Fact]
    public async Task Hangfire_services_are_registered_in_DI()
    {
        // IBackgroundJobClient and JobStorage must be resolvable — they prove Hangfire was wired.
        factory.Services.GetService<IBackgroundJobClient>().ShouldNotBeNull();
        factory.Services.GetService<JobStorage>().ShouldNotBeNull();
        await Task.CompletedTask;
    }

    [Fact]
    public async Task Hangfire_postgres_schema_exists_after_startup()
    {
        // The Hangfire schema is created during app startup; verify it exists via a direct Postgres query.
        _ = factory.Services.GetRequiredService<JobStorage>(); // ensure app has started

        await using var conn = new NpgsqlConnection(TestFixtures.Db);
        await conn.OpenAsync();

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            SELECT 1
            FROM information_schema.schemata
            WHERE schema_name = 'hangfire'
            """;
        var result = await cmd.ExecuteScalarAsync();

        result.ShouldBe(1, "The 'hangfire' schema must be created by Hangfire.PostgreSql on app startup.");
    }

    [Fact]
    public async Task Dashboard_is_not_publicly_accessible_without_a_bearer_token()
    {
        // The auth filter denies anonymous requests. Hangfire returns 401 when authorization
        // is denied. Accept 401 / 403 / 302 / 404 — anything that is NOT 200 OK.
        var client = factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            // Do NOT follow redirects so a 302 is visible rather than a redirect chain.
            AllowAutoRedirect = false,
        });

        var response = await client.GetAsync("/hangfire");

        ((int)response.StatusCode).ShouldNotBe(200,
            $"GET /hangfire without a token returned {response.StatusCode} — dashboard must not be publicly accessible.");
    }
}
