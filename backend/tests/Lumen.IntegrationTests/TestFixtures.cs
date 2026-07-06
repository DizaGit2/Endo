using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.IntegrationTests;

/// <summary>
/// Shared helpers for live-stack integration tests. Keeps connection strings and seed-data
/// factories in one place so they cannot drift between test files.
/// </summary>
internal static class TestFixtures
{
    public const string Db = "Host=localhost;Port=55432;Database=lumen;Username=postgres;Password=postgres";

    public const string KeycloakTokenUrl = "http://localhost:8080/realms/lumen/protocol/openid-connect/token";
    public const string ApiClientId = "api";
    public const string ApiClientSecret = "dev-api-secret";

    public static VaultOptions Vault() => new() { Address = "http://127.0.0.1:8200", Token = "root", KeyName = "lumen-dev-kek" };
    public static LumenDbContext NewDb() => new(new DbContextOptionsBuilder<LumenDbContext>().UseNpgsql(Db).Options);

    public static User NewUser(Guid id) => new()
    {
        Id = id,
        EmailHash = "hash-" + id.ToString("N"),
        Locale = "es-ES",
        Timezone = "Europe/Madrid",
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow,
    };

    /// <summary>
    /// Test-only DEK seeding helper (P3c-T4 — production now provisions DEKs inline in
    /// <c>OnboardingService</c>, so this reproduces the same logic purely for test setup):
    /// generate a 256-bit DEK, wrap it, persist the <c>user_keys</c> row, and zero the plaintext
    /// DEK in a <c>finally</c>. Idempotent — a second call for an already-provisioned user is a
    /// no-op — because some tests call it twice to prove idempotency.
    /// </summary>
    public static async Task ProvisionDekForTestAsync(
        LumenDbContext db, IKeyWrapper wrapper, Guid userId, CancellationToken ct = default)
    {
        var exists = await db.UserKeys.AsNoTracking().AnyAsync(k => k.UserId == userId, ct);
        if (exists) return;

        var dek = RandomNumberGenerator.GetBytes(32);
        try
        {
            var wrapped = await wrapper.WrapAsync(dek, ct);
            db.UserKeys.Add(new UserKey
            {
                UserId = userId,
                WrappedDek = wrapped,
                KeyVersion = 1,
                VaultKeyName = Vault().KeyName,
                CreatedAt = TimeProvider.System.GetUtcNow(),
            });
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // A concurrent provision call may have inserted the key first — idempotent if it now exists.
            if (!await db.UserKeys.AsNoTracking().AnyAsync(k => k.UserId == userId, ct))
                throw;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(dek);
        }
    }

    /// <summary>
    /// Password-grant for a test user; throws if the grant fails (user enabled &amp; valid creds).
    /// </summary>
    public static async Task<string> GetUserTokenAsync(string email, string password)
    {
        using var http = new HttpClient();
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "password",
            ["client_id"] = ApiClientId,
            ["client_secret"] = ApiClientSecret,
            ["username"] = email,
            ["password"] = password,
            ["scope"] = "openid",
        });
        var response = await http.PostAsync(KeycloakTokenUrl, form);
        response.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return doc.RootElement.GetProperty("access_token").GetString()!;
    }

    /// <summary>
    /// Password-grant that returns the raw HTTP status (used to prove a disabled user can no longer log in).
    /// </summary>
    public static async Task<HttpStatusCode> TryGetUserTokenStatusAsync(string email, string password)
    {
        using var http = new HttpClient();
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "password",
            ["client_id"] = ApiClientId,
            ["client_secret"] = ApiClientSecret,
            ["username"] = email,
            ["password"] = password,
            ["scope"] = "openid",
        });
        var response = await http.PostAsync(KeycloakTokenUrl, form);
        return response.StatusCode;
    }

    /// <summary>
    /// Client-credentials grant on the <c>api</c> client — a service-account token (no end user), used to
    /// prove the API rejects non-end-user tokens even though they now carry the same <c>aud=lumen-api</c>.
    /// </summary>
    public static async Task<string> GetServiceAccountTokenAsync()
    {
        using var http = new HttpClient();
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "client_credentials",
            ["client_id"] = ApiClientId,
            ["client_secret"] = ApiClientSecret,
        });
        var response = await http.PostAsync(KeycloakTokenUrl, form);
        response.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return doc.RootElement.GetProperty("access_token").GetString()!;
    }
}
