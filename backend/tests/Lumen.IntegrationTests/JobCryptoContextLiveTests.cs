using System.Security.Cryptography;
using System.Text;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for <see cref="IJobCryptoContext"/> and
/// <see cref="IJobCryptoContextFactory"/>. Require the dev compose stack up (Postgres :55432, Vault :8200).
/// They prove the job-scoped envelope round-trip through Vault Transit + Postgres and the tenant-isolation
/// and crypto-shred invariants at the job layer.
/// </summary>
[Trait("Category", "LiveStack")]
public class JobCryptoContextLiveTests
{
    private static JobCryptoContextFactory NewFactory(LumenDbContext db)
        => new(db, new VaultTransitKeyWrapper(TestFixtures.Vault()), new AesGcmFieldCipher());

    [Fact]
    public async Task Round_trip_job_context_encrypts_and_decrypts_field_correctly()
    {
        var userId = Guid.NewGuid();
        await using var db = TestFixtures.NewDb();
        try
        {
            db.Users.Add(TestFixtures.NewUser(userId));
            await db.SaveChangesAsync();

            await new DekProvisioner(db, new VaultTransitKeyWrapper(TestFixtures.Vault()), TestFixtures.Vault(), TimeProvider.System).ProvisionAsync(userId);

            const string displayName = "María José";
            var factory = NewFactory(db);
            byte[] enc;

            await using (var ctx = factory.Create(userId))
            {
                enc = await ctx.EncryptStringAsync(displayName);
                db.UserProfiles.Add(new UserProfileEnc
                {
                    UserId = userId,
                    DisplayNameEnc = enc,
                    CreatedAt = DateTimeOffset.UtcNow,
                    UpdatedAt = DateTimeOffset.UtcNow,
                });
                await db.SaveChangesAsync();
            }

            // Ciphertext at rest must not contain the plaintext.
            await using var raw = TestFixtures.NewDb();
            var stored = await raw.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            stored.DisplayNameEnc.ShouldNotBeNull();
            Encoding.UTF8.GetString(stored.DisplayNameEnc!).ShouldNotContain("María");

            // A FRESH job context must unwrap and decrypt back to the original string.
            var factory2 = NewFactory(raw);
            await using var ctx2 = factory2.Create(userId);
            (await ctx2.DecryptStringAsync(stored.DisplayNameEnc!)).ShouldBe(displayName);
        }
        finally
        {
            await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
            await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
            await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
        }
    }

    [Fact]
    public async Task Tenant_isolation_job_contexts_for_different_users_produce_non_interchangeable_ciphertexts()
    {
        var userAId = Guid.NewGuid();
        var userBId = Guid.NewGuid();
        await using var db = TestFixtures.NewDb();
        try
        {
            db.Users.Add(TestFixtures.NewUser(userAId));
            db.Users.Add(TestFixtures.NewUser(userBId));
            await db.SaveChangesAsync();

            var provisioner = new DekProvisioner(db, new VaultTransitKeyWrapper(TestFixtures.Vault()), TestFixtures.Vault(), TimeProvider.System);
            await provisioner.ProvisionAsync(userAId);
            await provisioner.ProvisionAsync(userBId);

            const string plaintext = "shared plaintext";
            var factory = NewFactory(db);

            byte[] encA, encB;
            await using (var ctxA = factory.Create(userAId))
                encA = await ctxA.EncryptStringAsync(plaintext);
            await using (var ctxB = factory.Create(userBId))
                encB = await ctxB.EncryptStringAsync(plaintext);

            // Ciphertexts must differ (different DEKs + random nonces).
            encA.ShouldNotBe(encB);

            // Decrypting userA's blob with userB's job context must fail (GCM tag mismatch).
            await using var ctxBForA = factory.Create(userBId);
            await Should.ThrowAsync<CryptographicException>(async () => await ctxBForA.DecryptAsync(encA));
        }
        finally
        {
            await db.UserKeys.Where(k => k.UserId == userAId || k.UserId == userBId).ExecuteDeleteAsync();
            await db.Users.Where(u => u.Id == userAId || u.Id == userBId).ExecuteDeleteAsync();
        }
    }

    [Fact]
    public async Task CryptoShred_precondition_deleting_user_key_makes_job_context_throw_InvalidOperationException()
    {
        var userId = Guid.NewGuid();
        await using var db = TestFixtures.NewDb();
        try
        {
            db.Users.Add(TestFixtures.NewUser(userId));
            await db.SaveChangesAsync();

            await new DekProvisioner(db, new VaultTransitKeyWrapper(TestFixtures.Vault()), TestFixtures.Vault(), TimeProvider.System).ProvisionAsync(userId);

            byte[] enc;
            var factory = NewFactory(db);
            await using (var ctx = factory.Create(userId))
                enc = await ctx.EncryptStringAsync("secret value");

            // Crypto-shred precondition: destroy the user_keys row.
            await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();

            // Decryption is now impossible — no DEK exists to unwrap.
            await using var ctx2 = factory.Create(userId);
            await Should.ThrowAsync<InvalidOperationException>(async () => await ctx2.DecryptAsync(enc));
        }
        finally
        {
            await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
            await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
        }
    }

    [Fact]
    public async Task DI_registration_IJobCryptoContextFactory_resolves_from_app_services()
    {
        await using var factory = new LumenApiFactory();
        using var scope = factory.Services.CreateScope();
        var resolved = scope.ServiceProvider.GetService<IJobCryptoContextFactory>();
        resolved.ShouldNotBeNull();
    }
}
