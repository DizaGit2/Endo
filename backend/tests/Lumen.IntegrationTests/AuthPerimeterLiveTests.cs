using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Auth perimeter hardening, live-stack (Keycloak :8080 + Postgres :55432 via WebApplicationFactory —
/// same pattern as <see cref="SpineLiveTests"/>): JWT audience validation (aud=lumen-api) and rejection
/// of malformed/tampered/service-account bearer tokens on GET /me. The positive path (valid user token
/// -> 200) is already covered by SpineLiveTests and is deliberately not duplicated here.
/// </summary>
[Trait("Category", "LiveStack")]
public class AuthPerimeterLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    [Fact]
    public async Task Access_token_carries_lumen_api_audience()
    {
        var client = factory.CreateClient();
        var email = $"aud-{Guid.NewGuid():N}@example.com";
        const string password = "Sup3rSecretPassw0rd!";
        Guid userId = default;
        try
        {
            var start = await client.PostAsJsonAsync("/onboarding/start", new
            {
                email,
                password,
                displayName = "Aud Test",
                locale = "es-ES",
                timezone = "Europe/Madrid",
                policyVersion = "v1-test",
            });
            start.StatusCode.ShouldBe(HttpStatusCode.OK);
            userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();

            var token = await TestFixtures.GetUserTokenAsync(email, password);
            var payload = DecodeJwtPayload(token);

            payload.TryGetProperty("aud", out var aud).ShouldBeTrue("access token must carry an aud claim");
            var audiences = aud.ValueKind == JsonValueKind.Array
                ? aud.EnumerateArray().Select(e => e.GetString()).ToArray()
                : [aud.GetString()];
            audiences.ShouldContain("lumen-api");
        }
        finally
        {
            await DeleteUserAsync(userId);
        }
    }

    [Fact]
    public async Task Garbage_bearer_token_returns_401()
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "not-a-jwt");

        var response = await client.GetAsync("/me");

        response.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Tampered_token_returns_401()
    {
        var client = factory.CreateClient();
        var email = $"tamper-{Guid.NewGuid():N}@example.com";
        const string password = "Sup3rSecretPassw0rd!";
        Guid userId = default;
        try
        {
            var start = await client.PostAsJsonAsync("/onboarding/start", new
            {
                email,
                password,
                displayName = "Tamper Test",
                locale = "es-ES",
                timezone = "Europe/Madrid",
                policyVersion = "v1-test",
            });
            start.StatusCode.ShouldBe(HttpStatusCode.OK);
            userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();

            var token = await TestFixtures.GetUserTokenAsync(email, password);
            var tampered = FlipOneCharInPayload(token);

            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tampered);
            var response = await authed.GetAsync("/me");

            response.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        }
        finally
        {
            await DeleteUserAsync(userId);
        }
    }

    [Fact]
    public async Task Service_account_token_returns_401()
    {
        var token = await TestFixtures.GetServiceAccountTokenAsync();

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var response = await client.GetAsync("/me");

        response.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    private static async Task DeleteUserAsync(Guid userId)
    {
        if (userId == default) return;
        await using var db = new LumenDbContext(new DbContextOptionsBuilder<LumenDbContext>().UseNpgsql(TestFixtures.Db).Options);
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
    }

    /// <summary>Decodes a JWT's payload segment (base64url, unverified) to a standalone JsonElement.</summary>
    private static JsonElement DecodeJwtPayload(string jwt)
    {
        var segment = jwt.Split('.')[1].Replace('-', '+').Replace('_', '/');
        segment = segment.PadRight(segment.Length + (4 - segment.Length % 4) % 4, '=');
        using var doc = JsonDocument.Parse(Convert.FromBase64String(segment));
        return doc.RootElement.Clone();
    }

    /// <summary>
    /// Flips one character in the middle of the payload segment, staying within the base64url alphabet
    /// so the token is still structurally well-formed — the signature (computed over the original bytes)
    /// no longer matches the mutated payload.
    /// </summary>
    private static string FlipOneCharInPayload(string jwt)
    {
        var parts = jwt.Split('.');
        var payload = parts[1].ToCharArray();
        var i = payload.Length / 2;
        payload[i] = payload[i] == 'A' ? 'B' : 'A';
        parts[1] = new string(payload);
        return string.Join('.', parts);
    }
}
