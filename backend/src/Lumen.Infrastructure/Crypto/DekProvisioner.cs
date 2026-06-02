using System.Security.Cryptography;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Infrastructure.Crypto;

/// <summary>
/// Generates and persists a per-user DEK, wrapped by Vault. Idempotent: if the user already has a
/// <c>user_keys</c> row it returns without generating a new key. The plaintext DEK is zeroed before return.
/// </summary>
public sealed class DekProvisioner(
    LumenDbContext db,
    IKeyWrapper keyWrapper,
    VaultOptions vaultOptions,
    TimeProvider timeProvider) : IDekProvisioner
{
    public async Task ProvisionAsync(Guid userId, CancellationToken ct = default)
    {
        var exists = await db.UserKeys.AsNoTracking().AnyAsync(k => k.UserId == userId, ct);
        if (exists) return;

        var dek = RandomNumberGenerator.GetBytes(32);
        try
        {
            var wrapped = await keyWrapper.WrapAsync(dek, ct);
            db.UserKeys.Add(new UserKey
            {
                UserId = userId,
                WrappedDek = wrapped,
                KeyVersion = 1,
                VaultKeyName = vaultOptions.KeyName,
                CreatedAt = timeProvider.GetUtcNow(),
            });
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // A concurrent ProvisionAsync may have inserted the key first — idempotent if it now exists.
            if (!await db.UserKeys.AsNoTracking().AnyAsync(k => k.UserId == userId, ct))
                throw;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(dek);
        }
    }
}
