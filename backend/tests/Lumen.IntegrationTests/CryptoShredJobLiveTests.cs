using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for <see cref="CryptoShredJob"/> — the GDPR right-to-erasure job.
/// Require the dev compose stack up (Postgres :55432, Vault :8200). They prove the crypto-shred
/// (delete <c>user_keys</c> so ciphertext is permanently unreadable), device-row deletion, tombstone,
/// the single audit entry, and idempotency on re-run. SAFETY-CRITICAL: incomplete erasure is a
/// compliance failure.
/// </summary>
[Trait("Category", "LiveStack")]
public class CryptoShredJobLiveTests
{
    private static CryptoShredJob NewJob(LumenDbContext db)
        => new(db, TimeProvider.System, NullLogger<CryptoShredJob>.Instance);

    private static JobCryptoContextFactory NewFactory(LumenDbContext db)
        => new(db, new VaultTransitKeyWrapper(TestFixtures.Vault()), new AesGcmFieldCipher());

    [Fact]
    public async Task Full_shred_deletes_keys_and_devices_tombstones_user_and_audits_once()
    {
        var userId = Guid.NewGuid();
        await using var db = TestFixtures.NewDb();
        try
        {
            db.Users.Add(TestFixtures.NewUser(userId));
            await db.SaveChangesAsync();

            await new DekProvisioner(db, new VaultTransitKeyWrapper(TestFixtures.Vault()), TestFixtures.Vault(), TimeProvider.System).ProvisionAsync(userId);

            // Seed an encrypted profile row so we can prove it becomes undecryptable after the shred.
            byte[] enc;
            await using (var ctx = NewFactory(db).Create(userId))
            {
                enc = await ctx.EncryptStringAsync("María José");
                db.UserProfiles.Add(new UserProfileEnc
                {
                    UserId = userId,
                    DisplayNameEnc = enc,
                    CreatedAt = DateTimeOffset.UtcNow,
                    UpdatedAt = DateTimeOffset.UtcNow,
                });
                await db.SaveChangesAsync();
            }

            // Seed a push-token device row.
            db.UserDevices.Add(new UserDevice
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Platform = "ios",
                PushToken = "tok-" + Guid.NewGuid().ToString("N"),
                LastSeenAt = DateTimeOffset.UtcNow,
                CreatedAt = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();

            // Act — run the erasure job.
            await NewJob(db).ExecuteAsync(userId);

            // Assert against a FRESH context so nothing is served from the change tracker.
            await using var read = TestFixtures.NewDb();

            // Crypto-shred: the DEK row is gone — ciphertext is now permanently unreadable.
            (await read.UserKeys.AsNoTracking().AnyAsync(k => k.UserId == userId)).ShouldBeFalse();

            // Push tokens emptied: device rows deleted.
            (await read.UserDevices.AsNoTracking().AnyAsync(d => d.UserId == userId)).ShouldBeFalse();

            // User row still EXISTS (FK integrity) but is tombstoned — must bypass the soft-delete filter.
            var user = await read.Users.IgnoreQueryFilters().AsNoTracking().SingleAsync(u => u.Id == userId);
            user.DeletedAt.ShouldNotBeNull();

            // Exactly one audit row, system actor, bare user GUID as EntityId, no PII in Before/After.
            var logs = await read.AdminAuditLogs.AsNoTracking()
                .Where(l => l.EntityId == userId.ToString() && l.Action == "crypto_shred")
                .ToListAsync();
            logs.Count.ShouldBe(1);
            logs[0].EntityType.ShouldBe("user");
            logs[0].ActorId.ShouldBeNull();
            logs[0].BeforeJson.ShouldBeNull();
            logs[0].AfterJson.ShouldBeNull();

            // The encrypted profile row still exists but is now undecryptable — no DEK to unwrap.
            var stored = await read.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            stored.DisplayNameEnc.ShouldNotBeNull();
            await using var ctx2 = NewFactory(read).Create(userId);
            await Should.ThrowAsync<InvalidOperationException>(async () => await ctx2.DecryptAsync(stored.DisplayNameEnc!));
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Re_run_is_idempotent_and_does_not_write_a_second_audit_row()
    {
        var userId = Guid.NewGuid();
        await using var db = TestFixtures.NewDb();
        try
        {
            db.Users.Add(TestFixtures.NewUser(userId));
            await db.SaveChangesAsync();
            await new DekProvisioner(db, new VaultTransitKeyWrapper(TestFixtures.Vault()), TestFixtures.Vault(), TimeProvider.System).ProvisionAsync(userId);

            // First shred.
            await NewJob(db).ExecuteAsync(userId);

            // Second shred on the same (already-tombstoned) user must not throw and must not duplicate state.
            await using var db2 = TestFixtures.NewDb();
            await Should.NotThrowAsync(async () => await NewJob(db2).ExecuteAsync(userId));

            await using var read = TestFixtures.NewDb();
            (await read.UserKeys.AsNoTracking().AnyAsync(k => k.UserId == userId)).ShouldBeFalse();

            var user = await read.Users.IgnoreQueryFilters().AsNoTracking().SingleAsync(u => u.Id == userId);
            user.DeletedAt.ShouldNotBeNull();

            // Still exactly ONE crypto_shred audit row — the DeletedAt sentinel suppresses a second entry.
            var count = await read.AdminAuditLogs.AsNoTracking()
                .CountAsync(l => l.EntityId == userId.ToString() && l.Action == "crypto_shred");
            count.ShouldBe(1);
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Unknown_user_is_a_no_op_and_writes_no_audit_row()
    {
        var userId = Guid.NewGuid(); // never inserted
        await using var db = TestFixtures.NewDb();
        try
        {
            await Should.NotThrowAsync(async () => await NewJob(db).ExecuteAsync(userId));

            await using var read = TestFixtures.NewDb();
            var count = await read.AdminAuditLogs.AsNoTracking()
                .CountAsync(l => l.EntityId == userId.ToString() && l.Action == "crypto_shred");
            count.ShouldBe(0);
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }

    // Remove every row this fixture can touch for the given user, regardless of which assertions ran.
    private static async Task CleanupAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
