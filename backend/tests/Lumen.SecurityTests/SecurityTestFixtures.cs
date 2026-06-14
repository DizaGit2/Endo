using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.SecurityTests;

/// <summary>
/// Local dev-stack helpers for the security/GDPR test project.  The connection values are
/// intentionally identical to <c>TestFixtures</c> in Lumen.IntegrationTests — they must track
/// the same dev-compose stack.  This duplication is deliberate: SecurityTests cannot take a
/// ProjectReference on Lumen.IntegrationTests (test projects must not reference each other).
/// </summary>
internal static class SecurityTestFixtures
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
