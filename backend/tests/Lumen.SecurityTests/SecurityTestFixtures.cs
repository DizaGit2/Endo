using System.Security.Cryptography;
using Lumen.Application.Crypto;
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

    /// <summary>
    /// Test-only DEK seeding helper — mirrors <c>TestFixtures.ProvisionDekForTestAsync</c> in
    /// Lumen.IntegrationTests (duplicated, not shared, for the same reason as the rest of this
    /// file: SecurityTests cannot reference the IntegrationTests project). Reproduces the same
    /// logic production used to provision DEKs before it moved inline into
    /// <c>OnboardingService</c> (P3c-T4): generate a 256-bit DEK, wrap it, persist the
    /// <c>user_keys</c> row, and zero the plaintext DEK in a <c>finally</c>. Idempotent — a
    /// second call for an already-provisioned user is a no-op.
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
}
