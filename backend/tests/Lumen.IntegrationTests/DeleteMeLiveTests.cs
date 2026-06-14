using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Hangfire;
using Hangfire.Common;
using Hangfire.States;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Persistence;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// A WAF fixture that replaces <see cref="IBackgroundJobClient"/> with a
/// <see cref="RecordingBackgroundJobClient"/> so enqueues are captured deterministically without
/// the Hangfire server ever executing the job. Extends <see cref="LumenApiFactory"/> to inherit
/// the Hangfire server-disable config without duplication.
/// </summary>
public sealed class RecordingJobFactory : LumenApiFactory
{
    public RecordingBackgroundJobClient Stub { get; } = new();

    protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.ConfigureTestServices(s => s.AddSingleton<IBackgroundJobClient>(Stub));
    }
}

/// <summary>
/// LIVE-STACK integration tests for <c>DELETE /me</c> — the GDPR right-to-erasure trigger.
/// Verifies that the endpoint enqueues <see cref="CryptoShredJob"/>, disables the Keycloak user
/// (so they can no longer authenticate), and returns 202 Accepted. Uses
/// <see cref="RecordingBackgroundJobClient"/> so the real shred job never runs during endpoint
/// tests and the enqueue assertion is deterministic.
/// </summary>
[Trait("Category", "LiveStack")]
public class DeleteMeLiveTests(RecordingJobFactory factory) : IClassFixture<RecordingJobFactory>
{
    // ------------------------------------------------------------------ helpers

    private async Task<(Guid userId, string token)> OnboardAndLoginAsync(string email, string password)
    {
        var client = factory.CreateClient();
        var start = await client.PostAsJsonAsync("/onboarding/start", new
        {
            email,
            password,
            displayName = "Test User",
            locale = "es-ES",
            timezone = "Europe/Madrid",
            policyVersion = "v1-test",
        });
        start.StatusCode.ShouldBe(HttpStatusCode.OK);
        var userId = (await start.Content.ReadFromJsonAsync<JsonElement>())
            .GetProperty("userId").GetGuid();

        var token = await TestFixtures.GetUserTokenAsync(email, password);
        return (userId, token);
    }

    private static async Task CleanupAsync(Guid userId)
    {
        // Best-effort: delete the Keycloak user via admin API, then all Lumen rows.
        try
        {
            using var http = new HttpClient();
            using var form = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "client_credentials",
                ["client_id"] = "api",
                ["client_secret"] = "dev-api-secret",
            });
            var tokenResp = await http.PostAsync(
                "http://localhost:8080/realms/lumen/protocol/openid-connect/token", form);
            if (tokenResp.IsSuccessStatusCode)
            {
                using var doc = JsonDocument.Parse(await tokenResp.Content.ReadAsStringAsync());
                var adminToken = doc.RootElement.GetProperty("access_token").GetString()!;
                using var del = new HttpRequestMessage(
                    HttpMethod.Delete,
                    $"http://localhost:8080/admin/realms/lumen/users/{userId}");
                del.Headers.Authorization = new AuthenticationHeaderValue("Bearer", adminToken);
                await http.SendAsync(del); // best-effort
            }
        }
        catch (Exception ex) { Console.Error.WriteLine($"[DeleteMeLiveTests cleanup] {ex.Message}"); }

        await using var db = TestFixtures.NewDb();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }

    // ------------------------------------------------------------------ tests

    [Fact]
    public async Task Delete_me_returns_202_enqueues_shred_job_and_disables_keycloak_user()
    {
        var email = $"del-{Guid.NewGuid():N}@example.com";
        const string password = "Sup3rSecretPassw0rd!";
        Guid userId = default;
        // Reset the shared stub (xUnit runs tests in a class sequentially).
        factory.Stub.Captured.Clear();

        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, password);

            // Act: DELETE /me with bearer
            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            var response = await authed.DeleteAsync("/me");

            // Assert: 202 Accepted
            response.StatusCode.ShouldBe(HttpStatusCode.Accepted);

            // Assert: exactly ONE enqueue targeting CryptoShredJob.ExecuteAsync with the correct userId
            factory.Stub.Captured.Count.ShouldBe(1);
            var (job, state) = factory.Stub.Captured[0];
            job.Type.ShouldBe(typeof(CryptoShredJob));
            job.Method.Name.ShouldBe("ExecuteAsync");
            ((Guid)job.Args[0]).ShouldBe(userId);
            state.ShouldBeOfType<EnqueuedState>();

            // Assert: Keycloak user is now disabled — password-grant must fail for a disabled account.
            var tokenStatus = await TestFixtures.TryGetUserTokenStatusAsync(email, password);
            tokenStatus.ShouldNotBe(HttpStatusCode.OK,
                "A disabled Keycloak user must not be able to obtain a token.");
            ((int)tokenStatus).ShouldBeGreaterThanOrEqualTo(400,
                "Keycloak returns a 4xx for a disabled user's password-grant attempt.");
        }
        finally
        {
            if (userId != default)
                await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Delete_me_without_bearer_returns_401()
    {
        var client = factory.CreateClient();
        var response = await client.DeleteAsync("/me");
        response.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Delete_me_when_already_tombstoned_returns_202_without_enqueue()
    {
        var email = $"del-tomb-{Guid.NewGuid():N}@example.com";
        const string password = "Sup3rSecretPassw0rd!";
        Guid userId = default;
        // Reset the shared stub (xUnit runs tests in a class sequentially).
        factory.Stub.Captured.Clear();

        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, password);

            // Simulate a completed shred: manually set DeletedAt on the user row.
            await using var db = TestFixtures.NewDb();
            await db.Users.IgnoreQueryFilters()
                .Where(u => u.Id == userId)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(u => u.DeletedAt, DateTimeOffset.UtcNow)
                    .SetProperty(u => u.UpdatedAt, DateTimeOffset.UtcNow));

            // Act: DELETE /me with bearer
            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            var response = await authed.DeleteAsync("/me");

            // Assert: 202 Accepted (idempotent)
            response.StatusCode.ShouldBe(HttpStatusCode.Accepted);

            // Assert: NO enqueue — the guard short-circuited
            factory.Stub.Captured.Count.ShouldBe(0,
                "Already-tombstoned user must not trigger another shred enqueue.");
        }
        finally
        {
            if (userId != default)
                await CleanupAsync(userId);
        }
    }
}

/// <summary>
/// Test double for <see cref="IBackgroundJobClient"/> that records every
/// <see cref="Create"/> call so tests can assert on the enqueued jobs without
/// running the real Hangfire server.
/// </summary>
public sealed class RecordingBackgroundJobClient : IBackgroundJobClient
{
    public List<(Job Job, IState State)> Captured { get; } = [];

    public string Create(Job job, IState state)
    {
        Captured.Add((job, state));
        return Guid.NewGuid().ToString(); // dummy job id
    }

    public bool ChangeState(string jobId, IState state, string? expectedStateName) => false;
}
