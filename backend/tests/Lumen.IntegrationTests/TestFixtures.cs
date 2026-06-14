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
}
