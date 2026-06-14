using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Lumen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// The walking-skeleton spine, end-to-end through the live stack (Caddy bypassed; API in-process via
/// WebApplicationFactory, talking to real Keycloak :8080 + Vault :8200 + Postgres :55432):
/// POST /onboarding/start (Keycloak user + Vault DEK + encrypted profile) → password-grant login →
/// GET /me decrypts and returns the profile. T12 converts to Testcontainers for CI.
/// </summary>
[Trait("Category", "LiveStack")]
public class SpineLiveTests(WebApplicationFactory<Program> factory) : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task Walking_skeleton_spine_end_to_end()
    {
        var client = factory.CreateClient();
        var email = $"user-{Guid.NewGuid():N}@example.com";
        const string password = "Sup3rSecretPassw0rd!";
        const string displayName = "María José";
        Guid userId = default;

        try
        {
            // 1. onboarding/start — anonymous; creates Keycloak user + DEK + encrypted profile
            var start = await client.PostAsJsonAsync("/onboarding/start", new
            {
                email,
                password,
                displayName,
                locale = "es-ES",
                timezone = "Europe/Madrid",
                policyVersion = "v1-test",
            });
            start.StatusCode.ShouldBe(HttpStatusCode.OK);
            userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();

            // 2. GET /me without a token -> 401
            (await client.GetAsync("/me")).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);

            // 3. log in (password grant) to obtain a real Keycloak access token
            var token = await GetUserTokenAsync(email, password);

            // 4. GET /me with the token -> 200 + decrypted profile
            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            var me = await authed.GetAsync("/me");
            me.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await me.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("id").GetGuid().ShouldBe(userId);
            body.GetProperty("displayName").GetString().ShouldBe(displayName);
            body.GetProperty("locale").GetString().ShouldBe("es-ES");

            // 5. the stored display name is ciphertext at rest
            await using var db = new LumenDbContext(new DbContextOptionsBuilder<LumenDbContext>().UseNpgsql(TestFixtures.Db).Options);
            var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            System.Text.Encoding.UTF8.GetString(profile.DisplayNameEnc!).ShouldNotContain("María");
        }
        finally
        {
            if (userId != default)
            {
                await using var db = new LumenDbContext(new DbContextOptionsBuilder<LumenDbContext>().UseNpgsql(TestFixtures.Db).Options);
                await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
                await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
                await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
                await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
            }
        }
    }

    [Fact]
    public async Task Onboarding_duplicate_email_returns_409_not_500()
    {
        var client = factory.CreateClient();
        var email = $"dup-{Guid.NewGuid():N}@example.com";
        const string password = "Sup3rSecretPassw0rd!";
        Guid userId = default;
        try
        {
            var first = await client.PostAsJsonAsync("/onboarding/start", new
            { email, password, displayName = "Dup", locale = "es-ES", timezone = "Europe/Madrid", policyVersion = "v1-test" });
            first.StatusCode.ShouldBe(HttpStatusCode.OK);
            userId = (await first.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();

            var second = await client.PostAsJsonAsync("/onboarding/start", new
            { email, password, displayName = "Dup", locale = "es-ES", timezone = "Europe/Madrid", policyVersion = "v1-test" });
            second.StatusCode.ShouldBe(HttpStatusCode.Conflict); // DuplicateUserException -> 409 via ProblemExceptionHandler
        }
        finally
        {
            if (userId != default)
            {
                await using var db = new LumenDbContext(new DbContextOptionsBuilder<LumenDbContext>().UseNpgsql(TestFixtures.Db).Options);
                await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
                await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync(); // Restrict FK — delete explicitly
                await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
                await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
            }
        }
    }

    private static async Task<string> GetUserTokenAsync(string email, string password)
    {
        using var http = new HttpClient();
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "password",
            ["client_id"] = "api",
            ["client_secret"] = "dev-api-secret",
            ["username"] = email,
            ["password"] = password,
            ["scope"] = "openid",
        });
        var response = await http.PostAsync("http://localhost:8080/realms/lumen/protocol/openid-connect/token", form);
        response.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return doc.RootElement.GetProperty("access_token").GetString()!;
    }
}
