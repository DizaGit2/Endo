using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// Proof that <see cref="TestResidueSweep"/> reclaims what an aborted run leaves and nothing else.
/// Both halves matter: a sweep that missed residue would leave the dev stack exactly as it was, and a
/// sweep that over-matched would delete a developer's dev-stack account — or another run's user
/// mid-assertion — which is far worse than the residue it was written to clean up.
/// <b>[Category=LiveStack]</b> — needs Postgres only. The Keycloak half is covered by
/// <see cref="TestResidueSweepRuleTests"/> instead, which proves the per-account rule as a pure
/// predicate: asserting it live would mean creating, in a developer's own realm, the very accounts the
/// assertion then deletes. (It used to be "covered" by running on every startup, which is not coverage —
/// nothing asserted the outcome, and the sweep is opt-in now.)
/// </summary>
public class TestResidueSweepLiveTests
{
    /// <summary>Marks this file's own non-test-shaped fixture so it can reclaim its own leftovers.</summary>
    private const string NegativeFixtureHashPrefix = "vault:v1:residue-sweep-negative-";

    [Fact]
    public async Task Sweep_reclaims_an_aborted_runs_onboarded_user_and_everything_that_belongs_to_it()
    {
        var userId = Guid.NewGuid();
        var aborted = DateTimeOffset.UtcNow.AddHours(-3);

        try
        {
            await using (var db = TestFixtures.NewDb())
            {
                // Shaped exactly like a user POST /onboarding/start created three hours ago and never
                // cleaned up: a Vault-hashed email (so ONLY the consent marker identifies it), the
                // consent row, and the two dependents every onboarding leaves behind.
                db.Users.Add(new User
                {
                    Id = userId,
                    EmailHash = "vault:v1:" + Convert.ToBase64String(Guid.NewGuid().ToByteArray()),
                    Locale = "es-ES",
                    Timezone = "Europe/Madrid",
                    CreatedAt = aborted,
                    UpdatedAt = aborted,
                });
                db.ConsentRecords.Add(new ConsentRecord
                {
                    Id = Guid.NewGuid(),
                    UserId = userId,
                    PolicyVersion = TestResidueSweep.TestPolicyVersion,
                    Locale = "es-ES",
                    ConsentedAt = aborted,
                });
                db.UserProfiles.Add(new UserProfileEnc { UserId = userId, CreatedAt = aborted, UpdatedAt = aborted });
                await db.SaveChangesAsync();
            }

            var reclaimed = await TestResidueSweep.SweepDatabaseAsync(DateTimeOffset.UtcNow.AddHours(-1));
            reclaimed.ShouldBeGreaterThanOrEqualTo(1);

            await using var check = TestFixtures.NewDb();
            (await check.Users.IgnoreQueryFilters().AnyAsync(u => u.Id == userId)).ShouldBeFalse(
                "the orphan users row must be gone");
            (await check.ConsentRecords.AnyAsync(c => c.UserId == userId)).ShouldBeFalse(
                "consent_records is model-derived like every other dependent — leaving it would also "
                + "leave the users row undeletable behind its RESTRICT foreign key");
            (await check.UserProfiles.AnyAsync(p => p.UserId == userId)).ShouldBeFalse(
                "user_profile_enc must go with it");
        }
        finally
        {
            await HardDeleteAsync(userId);
        }
    }

    [Fact]
    public async Task Sweep_reclaims_an_aborted_runs_directly_inserted_user()
    {
        // The OTHER creation path: SecurityTests and several fixtures insert a users row straight into
        // Postgres with no Keycloak account and no consent row, so the consent marker cannot see them.
        // The plaintext "hash-" EmailHash is their marker, and no production path can produce it —
        // a real hash is Vault ciphertext.
        var userId = Guid.NewGuid();
        var aborted = DateTimeOffset.UtcNow.AddHours(-3);

        try
        {
            await using (var db = TestFixtures.NewDb())
            {
                var user = TestFixtures.NewUser(userId);
                user.CreatedAt = aborted;
                user.UpdatedAt = aborted;
                db.Users.Add(user);
                await db.SaveChangesAsync();
            }

            await TestResidueSweep.SweepDatabaseAsync(DateTimeOffset.UtcNow.AddHours(-1));

            await using var check = TestFixtures.NewDb();
            (await check.Users.IgnoreQueryFilters().AnyAsync(u => u.Id == userId)).ShouldBeFalse();
        }
        finally
        {
            await HardDeleteAsync(userId);
        }
    }

    [Fact]
    public async Task Sweep_leaves_a_recent_user_and_a_non_test_user_alone()
    {
        // The two ways this could do damage, asserted together.
        var inFlightId = Guid.NewGuid();   // test-shaped, but young: could be another run's live user
        var devAccountId = Guid.NewGuid(); // aged, but not test-shaped: a developer's dev-stack account

        // Reclaim any leftover of this file's OWN negative fixture first. It is deliberately shaped so
        // the sweep will not take it, which means an abort here would strand it — so the test that
        // creates it is also the thing that cleans it up.
        await ReclaimNegativeFixturesAsync();

        try
        {
            var now = DateTimeOffset.UtcNow;
            await using (var db = TestFixtures.NewDb())
            {
                var inFlight = TestFixtures.NewUser(inFlightId); // "hash-…" — test-shaped
                inFlight.CreatedAt = now;
                inFlight.UpdatedAt = now;
                db.Users.Add(inFlight);

                db.Users.Add(new User
                {
                    Id = devAccountId,
                    EmailHash = NegativeFixtureHashPrefix + devAccountId.ToString("N"),
                    Locale = "es-ES",
                    Timezone = "Europe/Madrid",
                    CreatedAt = now.AddDays(-30),
                    UpdatedAt = now.AddDays(-30),
                });
                db.ConsentRecords.Add(new ConsentRecord
                {
                    Id = Guid.NewGuid(),
                    UserId = devAccountId,
                    PolicyVersion = "v1-draft", // what the Flutter client posts — NOT the test marker
                    Locale = "es-ES",
                    ConsentedAt = now.AddDays(-30),
                });
                await db.SaveChangesAsync();
            }

            await TestResidueSweep.SweepDatabaseAsync(DateTimeOffset.UtcNow.AddHours(-1));

            await using var check = TestFixtures.NewDb();
            (await check.Users.IgnoreQueryFilters().AnyAsync(u => u.Id == inFlightId)).ShouldBeTrue(
                "a user younger than TestResidueSweep.MinimumAge may belong to a run that is still "
                + "executing — the age floor is the only thing making this sweep safe to start "
                + "unconditionally");
            (await check.Users.IgnoreQueryFilters().AnyAsync(u => u.Id == devAccountId)).ShouldBeTrue(
                "an aged user with neither marker is somebody's dev-stack account, not residue");
        }
        finally
        {
            await HardDeleteAsync(inFlightId);
            await HardDeleteAsync(devAccountId);
        }
    }

    private static async Task HardDeleteAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }

    private static async Task ReclaimNegativeFixturesAsync()
    {
        await using var db = TestFixtures.NewDb();
        var stranded = await db.Users.IgnoreQueryFilters()
            .Where(u => u.EmailHash.StartsWith(NegativeFixtureHashPrefix))
            .Select(u => u.Id)
            .ToListAsync();

        foreach (var id in stranded) await HardDeleteAsync(id);
    }
}
