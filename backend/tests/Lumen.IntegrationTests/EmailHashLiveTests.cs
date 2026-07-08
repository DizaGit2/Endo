using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK: proves the real Vault Transit HMAC round-trip end-to-end. POST /onboarding/start
/// against the live stack (Keycloak :8080, Vault :8200, Postgres :55432), then reads the persisted
/// <c>users.EmailHash</c> raw and confirms it is a Vault HMAC token — not the pre-P3c-T3 unsalted
/// SHA-256 hex digest a stolen DB could reproduce offline.
/// </summary>
[Trait("Category", "LiveStack")]
public class EmailHashLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    [Fact]
    public async Task Onboarded_user_email_hash_is_a_vault_hmac_token_not_raw_sha256()
    {
        var client = factory.CreateClient();
        var email = $"user-{Guid.NewGuid():N}@example.com";
        const string password = "Sup3rSecretPassw0rd!";
        Guid userId = default;

        try
        {
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
            userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();

            await using var db = TestFixtures.NewDb();
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId);

            user.EmailHash.ShouldStartWith("vault:v1:");
            user.EmailHash.ShouldNotBe(Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(email))));
        }
        finally
        {
            if (userId != default)
            {
                await using var db = TestFixtures.NewDb();
                await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
                await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
                await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
                await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
            }
        }
    }
}
