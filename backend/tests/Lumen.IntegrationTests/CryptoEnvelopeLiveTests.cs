using System.Text;
using Lumen.Application.Auth;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests: require the dev compose stack up (Postgres :55432, Vault :8200).
/// They prove the real envelope round-trip through Vault Transit + Postgres. T12 converts these
/// to Testcontainers (Postgres + Vault + Keycloak) for CI isolation.
/// </summary>
[Trait("Category", "LiveStack")]
public class CryptoEnvelopeLiveTests
{
    private sealed class StubUser(Guid id) : ICurrentUserAccessor
    {
        public bool IsAuthenticated => true;
        public Guid UserId { get; } = id;
    }

    [Fact]
    public async Task Full_envelope_roundtrip_through_vault_and_postgres()
    {
        var userId = Guid.NewGuid();
        var wrapper = new VaultTransitKeyWrapper(TestFixtures.Vault());
        var cipher = new AesGcmFieldCipher();
        await using var db = TestFixtures.NewDb();
        try
        {
            db.Users.Add(TestFixtures.NewUser(userId));
            await db.SaveChangesAsync();

            // T5 — provision DEK (twice, to prove idempotency)
            var provisioner = new DekProvisioner(db, wrapper, TestFixtures.Vault(), TimeProvider.System);
            await provisioner.ProvisionAsync(userId);
            await provisioner.ProvisionAsync(userId);

            var keyRow = await db.UserKeys.AsNoTracking().SingleAsync(k => k.UserId == userId);
            Encoding.ASCII.GetString(keyRow.WrappedDek).ShouldStartWith("vault:v1:"); // wrapped, not raw
            (await db.UserKeys.CountAsync(k => k.UserId == userId)).ShouldBe(1);        // idempotent

            // T4 — encrypt a profile field through the request-scoped context
            const string displayName = "María José";
            await using (var crypto = new UserCryptoContext(db, wrapper, cipher, new StubUser(userId)))
            {
                var enc = await crypto.EncryptStringAsync(displayName);
                db.UserProfiles.Add(new UserProfileEnc
                {
                    UserId = userId,
                    DisplayNameEnc = enc,
                    CreatedAt = DateTimeOffset.UtcNow,
                    UpdatedAt = DateTimeOffset.UtcNow,
                });
                await db.SaveChangesAsync();
            }

            await using var raw = TestFixtures.NewDb();
            var stored = await raw.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            stored.DisplayNameEnc.ShouldNotBeNull();
            Encoding.UTF8.GetString(stored.DisplayNameEnc!).ShouldNotContain("María"); // ciphertext at rest

            // a FRESH request-scoped context unwraps and decrypts
            await using var crypto2 = new UserCryptoContext(raw, wrapper, cipher, new StubUser(userId));
            (await crypto2.DecryptStringAsync(stored.DisplayNameEnc!)).ShouldBe(displayName);
        }
        finally
        {
            await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
            await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
            await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
        }
    }

    [Fact]
    public async Task CryptoShred_precondition_deleting_user_key_makes_field_undecryptable()
    {
        var userId = Guid.NewGuid();
        var wrapper = new VaultTransitKeyWrapper(TestFixtures.Vault());
        var cipher = new AesGcmFieldCipher();
        await using var db = TestFixtures.NewDb();
        try
        {
            db.Users.Add(TestFixtures.NewUser(userId));
            await db.SaveChangesAsync();
            await new DekProvisioner(db, wrapper, TestFixtures.Vault(), TimeProvider.System).ProvisionAsync(userId);

            byte[] enc;
            await using (var crypto = new UserCryptoContext(db, wrapper, cipher, new StubUser(userId)))
                enc = await crypto.EncryptStringAsync("secret value");

            // crypto-shred precondition: destroy the user_keys row
            await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();

            // decryption is now impossible — no DEK exists to unwrap
            await using var crypto2 = new UserCryptoContext(db, wrapper, cipher, new StubUser(userId));
            await Should.ThrowAsync<InvalidOperationException>(async () => await crypto2.DecryptAsync(enc));
        }
        finally
        {
            await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
            await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
        }
    }
}
