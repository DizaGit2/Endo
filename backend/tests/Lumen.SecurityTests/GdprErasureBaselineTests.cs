using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Logging;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Shouldly;

namespace Lumen.SecurityTests;

/// <summary>
/// SAFETY-CRITICAL — GDPR right-to-erasure baseline suite (<c>Lumen.SecurityTests</c>).
/// These tests pin the erasure guarantees that CryptoShredJob must uphold: once user_keys
/// is deleted the ciphertext is permanently unreadable, the erasure is idempotent (exactly one
/// audit row), and the job never emits userId, email, or DEK material in its log output.
/// Require the dev compose stack (Postgres :55432, Vault :8200).
/// </summary>
[Trait("Category", "LiveStack")]
public class GdprErasureBaselineTests
{
    // ── in-memory Serilog sink used by the PII-scrub test ────────────────────────────────────

    private sealed class CapturingSink : ILogEventSink
    {
        private readonly System.Collections.Concurrent.ConcurrentBag<LogEvent> _events = [];
        public IReadOnlyCollection<LogEvent> Events => _events;
        public void Emit(LogEvent logEvent) => _events.Add(logEvent);
    }

    // ── helpers ───────────────────────────────────────────────────────────────────────────────

    private static CryptoShredJob NewJob(LumenDbContext db, ILogger<CryptoShredJob>? logger = null)
        => new(db, TimeProvider.System, logger ?? NullLogger<CryptoShredJob>.Instance);

    private static JobCryptoContext NewCryptoContext(LumenDbContext db, Guid userId)
        => new(db, new VaultTransitKeyWrapper(SecurityTestFixtures.Vault()), new AesGcmFieldCipher(), userId);

    private static async Task SeedUserWithDekAndProfileAsync(LumenDbContext db, Guid userId)
    {
        db.Users.Add(SecurityTestFixtures.NewUser(userId));
        await db.SaveChangesAsync();

        var provisioner = new DekProvisioner(
            db,
            new VaultTransitKeyWrapper(SecurityTestFixtures.Vault()),
            SecurityTestFixtures.Vault(),
            TimeProvider.System);
        await provisioner.ProvisionAsync(userId);

        await using var ctx = NewCryptoContext(db, userId);
        var enc = await ctx.EncryptStringAsync("María José");
        db.UserProfiles.Add(new UserProfileEnc
        {
            UserId = userId,
            DisplayNameEnc = enc,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        });
        await db.SaveChangesAsync();
    }

    private static async Task CleanupAsync(Guid userId)
    {
        await using var db = SecurityTestFixtures.NewDb();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }

    // ── Test 1: erasure makes ciphertext permanently unreadable ──────────────────────────────

    [Fact]
    public async Task Erasure_makes_ciphertext_unreadable_via_fresh_crypto_context()
    {
        // GDPR §17 guarantee: once user_keys is deleted no client can unwrap the DEK and the
        // ciphertext stored in user_profile_enc is permanently inaccessible.
        var userId = Guid.NewGuid();
        await using var db = SecurityTestFixtures.NewDb();
        try
        {
            await SeedUserWithDekAndProfileAsync(db, userId);

            // Act — crypto-shred the user.
            await NewJob(db).ExecuteAsync(userId);

            // Assert — fresh db + fresh crypto context (nothing from the change tracker).
            await using var read = SecurityTestFixtures.NewDb();
            var stored = await read.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            stored.DisplayNameEnc.ShouldNotBeNull("profile row must still exist after shred");

            // A fresh JobCryptoContext for this user must throw — there is no DEK to unwrap.
            await using var ctx = NewCryptoContext(read, userId);
            await Should.ThrowAsync<InvalidOperationException>(
                async () => await ctx.DecryptAsync(stored.DisplayNameEnc!));
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }

    // ── Test 2: backup bytes captured before the shred cannot be decrypted afterwards ────────

    [Fact]
    public async Task Backup_bytes_captured_before_shred_are_permanently_unreadable_afterwards()
    {
        // Simulates an attacker (or legitimate DBA backup) that has a copy of user_profile_enc
        // rows but NOT user_keys.  The ciphertext must remain opaque after the DEK is destroyed.
        var userId = Guid.NewGuid();
        await using var db = SecurityTestFixtures.NewDb();
        try
        {
            await SeedUserWithDekAndProfileAsync(db, userId);

            // Capture ciphertext bytes BEFORE the shred (simulates a data-table backup).
            await using var preShred = SecurityTestFixtures.NewDb();
            var stored = await preShred.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            var backupBytes = stored.DisplayNameEnc!.ToArray(); // copy, not a reference

            // Act — destroy the DEK.
            await NewJob(db).ExecuteAsync(userId);

            // Assert — backup bytes + fresh crypto context (no DEK available) → must throw.
            await using var read = SecurityTestFixtures.NewDb();
            await using var ctx = NewCryptoContext(read, userId);
            await Should.ThrowAsync<InvalidOperationException>(
                async () => await ctx.DecryptAsync(backupBytes));
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }

    // ── Test 3: idempotent — second run produces no additional audit rows ─────────────────────

    [Fact]
    public async Task Idempotent_second_run_produces_exactly_one_audit_row()
    {
        // The DeletedAt sentinel must suppress a second crypto_shred entry so the audit log
        // remains a reliable single-fact record of when the erasure occurred.
        var userId = Guid.NewGuid();
        await using var db = SecurityTestFixtures.NewDb();
        try
        {
            await SeedUserWithDekAndProfileAsync(db, userId);

            // First shred.
            await NewJob(db).ExecuteAsync(userId);

            // Second shred on a fresh context — must not throw and must not add a second row.
            await using var db2 = SecurityTestFixtures.NewDb();
            await Should.NotThrowAsync(async () => await NewJob(db2).ExecuteAsync(userId));

            // Assert exactly ONE crypto_shred audit row for this user.
            await using var read = SecurityTestFixtures.NewDb();
            var count = await read.AdminAuditLogs.AsNoTracking()
                .CountAsync(l => l.EntityId == userId.ToString() && l.Action == "crypto_shred");
            count.ShouldBe(1, "idempotent re-run must not produce a second audit entry");
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }

    // ── Test 4: job log output contains no PII or DEK material ───────────────────────────────

    [Fact]
    public async Task Job_logs_contain_no_userId_email_or_dek_material()
    {
        // §F: the job must emit ZERO PII in structured log properties or rendered messages.
        // This test guards against future regressions (e.g. someone accidentally logging userId).
        var userId = Guid.NewGuid();
        const string userEmail = "piitest@example.com";

        await using var db = SecurityTestFixtures.NewDb();
        try
        {
            // EmailHash is deliberately set to the raw email (not a real hash) so the assertion
            // can prove the job never logs it; real hashes aren't reversible to the email anyway.
            var u = SecurityTestFixtures.NewUser(userId);
            u.EmailHash = userEmail;
            db.Users.Add(u);
            await db.SaveChangesAsync();

            var provisioner = new DekProvisioner(
                db,
                new VaultTransitKeyWrapper(SecurityTestFixtures.Vault()),
                SecurityTestFixtures.Vault(),
                TimeProvider.System);
            await provisioner.ProvisionAsync(userId);

            // Capture the wrapped DEK BEFORE the job runs so we know what to search for.
            var keyRow = await db.UserKeys.AsNoTracking().SingleAsync(k => k.UserId == userId);
            var wrappedDekStr = System.Text.Encoding.ASCII.GetString(keyRow.WrappedDek);

            // Build a Serilog logger wired through the production PiiRedactionEnricher, writing
            // to an in-memory sink so we can inspect every structured log event afterwards.
            var sink = new CapturingSink();
            Serilog.ILogger serilogLogger = new LoggerConfiguration()
                .Enrich.With(new PiiRedactionEnricher())
                .WriteTo.Sink(sink)
                .CreateLogger();

            // Bridge Serilog → ILogger<CryptoShredJob> via ILoggerFactory extension method.
            using ILoggerFactory msLoggerFactory = new Serilog.Extensions.Logging.SerilogLoggerFactory(serilogLogger);
            var msLogger = msLoggerFactory.CreateLogger<CryptoShredJob>();

            // Act — run the job with the capturing logger.
            await NewJob(db, msLogger).ExecuteAsync(userId);

            sink.Events.ShouldNotBeEmpty("job must emit at least one log event (outcome message)");

            // Assert: scan every rendered message AND every structured property value for PII.
            var userIdStr = userId.ToString();
            foreach (var ev in sink.Events)
            {
                var rendered = ev.RenderMessage();
                rendered.ShouldNotContain(userIdStr);
                rendered.ShouldNotContain(userEmail);
                rendered.ShouldNotContain(wrappedDekStr);

                // Walk all structured property values as rendered strings.
                foreach (var prop in ev.Properties.Values)
                {
                    var propStr = prop.ToString();
                    propStr.ShouldNotContain(userIdStr);
                    propStr.ShouldNotContain(userEmail);
                    propStr.ShouldNotContain(wrappedDekStr);
                }
            }
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }
}
