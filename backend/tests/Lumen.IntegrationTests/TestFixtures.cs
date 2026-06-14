using System.Net;
using System.Text.Json;
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
}
