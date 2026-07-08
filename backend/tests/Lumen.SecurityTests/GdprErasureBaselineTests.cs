using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Jobs;
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
///
/// The pure in-memory negative control for the PII-scan mechanism lives in
/// <see cref="PiiLogScanNegativeControlTests"/> below (same file) — it needs no compose stack, so
/// it deliberately does NOT carry the LiveStack trait. Both classes share capture plumbing via
/// <see cref="PiiLogScanCapture"/>.
/// </summary>
[Trait("Category", "LiveStack")]
public class GdprErasureBaselineTests
{
    // ── helpers ───────────────────────────────────────────────────────────────────────────────

    private static CryptoShredJob NewJob(LumenDbContext db, ILogger<CryptoShredJob>? logger = null)
        => new(db, TimeProvider.System, logger ?? NullLogger<CryptoShredJob>.Instance);

    private static JobCryptoContext NewCryptoContext(LumenDbContext db, Guid userId)
        => new(db, new VaultTransitKeyWrapper(SecurityTestFixtures.Vault()), new AesGcmFieldCipher(), userId);

    private static async Task SeedUserWithDekAndProfileAsync(LumenDbContext db, Guid userId)
    {
        db.Users.Add(SecurityTestFixtures.NewUser(userId));
        await db.SaveChangesAsync();

        await SecurityTestFixtures.ProvisionDekForTestAsync(
            db, new VaultTransitKeyWrapper(SecurityTestFixtures.Vault()), userId);

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

            // Residual non-encrypted quasi-identifiers must be blanked on the retained tombstone row:
            // Locale/Timezone are plain NOT-NULL text the crypto-shred cannot make unreadable, so erasure
            // clears them to empty strings (which still satisfy the required/NOT-NULL constraint).
            var tombstoned = await read.Users.IgnoreQueryFilters().AsNoTracking().SingleAsync(u => u.Id == userId);
            tombstoned.Locale.ShouldBe("");
            tombstoned.Timezone.ShouldBe("");

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
                .CountAsync(l => l.EntityId == userId.ToString() && l.Action == AdminAuditLog.Actions.CryptoShred);
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
        //
        // The capture pipeline is deliberately wired WITHOUT the production PiiRedactionEnricher:
        // the enricher redacts GUID scalars to "[id]" and emails to "[redacted-email]" BEFORE they
        // reach the sink, which would mask the most likely regression — the job logging userId as a
        // structured property ("...{UserId}", userId) — and let this test pass vacuously. Scanning the
        // RAW events proves the job itself never emits PII (interpolated OR structured). The enricher's
        // own redaction behaviour is separately covered by PiiRedactionEnricherTests (unit).
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

            await SecurityTestFixtures.ProvisionDekForTestAsync(
                db, new VaultTransitKeyWrapper(SecurityTestFixtures.Vault()), userId);

            // Capture the wrapped DEK BEFORE the job runs so we know what to search for.
            var keyRow = await db.UserKeys.AsNoTracking().SingleAsync(k => k.UserId == userId);
            var wrappedDekStr = System.Text.Encoding.ASCII.GetString(keyRow.WrappedDek);

            var (msLogger, sink) = PiiLogScanCapture.NewRawCapturingLogger<CryptoShredJob>();

            // Act — run the job with the raw (un-enriched) capturing logger.
            await NewJob(db, msLogger).ExecuteAsync(userId);

            sink.Events.ShouldNotBeEmpty("job must emit at least one log event (outcome message)");

            // Assert: scan every raw event for the userId, email, and wrapped-DEK material.
            PiiLogScanCapture.EventsContainAny(sink.Events, userId.ToString(), userEmail, wrappedDekStr)
                .ShouldBeFalse("job log output must contain no userId, email, or wrapped-DEK material");
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }
}

/// <summary>
/// Pure in-memory negative control for the PII-scan mechanism used by
/// <see cref="GdprErasureBaselineTests.Job_logs_contain_no_userId_email_or_dek_material"/>. No DB, no
/// Vault — deliberately NOT tagged <c>[Trait("Category","LiveStack")]</c> so it runs without the dev
/// compose stack.
/// </summary>
public class PiiLogScanNegativeControlTests
{
    // ── Test 4b (negative control): the capture+scan mechanism can actually detect a leak ────────

    [Fact]
    public void Capture_and_scan_detects_a_deliberate_pii_leak()
    {
        // Proves Test 4 is NOT vacuous: a logger that DOES leak userId and email — through the same
        // un-enriched CapturingSink and the same EventsContainAny scan — must be detected. Without this
        // control a broken capture (or an accidental enricher in the pipeline) would let Test 4 pass for
        // the wrong reason.
        var userId = Guid.NewGuid();
        const string userEmail = "leak@example.com";

        var (logger, sink) = PiiLogScanCapture.NewRawCapturingLogger<PiiLogScanNegativeControlTests>();

        // Interpolated leak (in the rendered message) AND structured leak (a {UserId} property).
        logger.LogInformation("leaking userId={UserId} and {Email}", userId, userEmail);

        sink.Events.ShouldNotBeEmpty();
        PiiLogScanCapture.EventsContainAny(sink.Events, userId.ToString(), userEmail, wrappedDek: "n/a")
            .ShouldBeTrue("the capture+scan mechanism must detect a deliberate userId/email leak");
    }
}

/// <summary>
/// PII-scan capture plumbing shared by <see cref="GdprErasureBaselineTests"/>'s Test 4 (LiveStack)
/// and <see cref="PiiLogScanNegativeControlTests"/>'s negative control (stackless) — extracted here,
/// outside both classes, so the stackless test does not need to inherit the LiveStack-tagged class.
/// </summary>
internal static class PiiLogScanCapture
{
    public sealed class CapturingSink : ILogEventSink
    {
        private readonly System.Collections.Concurrent.ConcurrentBag<LogEvent> _events = [];
        public IReadOnlyCollection<LogEvent> Events => _events;
        public void Emit(LogEvent logEvent) => _events.Add(logEvent);
    }

    /// <summary>
    /// Builds an <see cref="ILogger{T}"/> writing to a fresh <see cref="CapturingSink"/> with NO
    /// PiiRedactionEnricher in the pipeline, so captured events are the RAW events the caller emitted.
    /// </summary>
    public static (ILogger<T> logger, CapturingSink sink) NewRawCapturingLogger<T>()
    {
        var sink = new CapturingSink();
        Serilog.ILogger serilogLogger = new LoggerConfiguration()
            .WriteTo.Sink(sink)
            .CreateLogger();
        var msLoggerFactory = new Serilog.Extensions.Logging.SerilogLoggerFactory(serilogLogger);
        return (msLoggerFactory.CreateLogger<T>(), sink);
    }

    /// <summary>
    /// True if ANY captured event's rendered message OR any structured property value contains the
    /// userId, email, or wrapped-DEK material. Catches both interpolated and structured-property leaks.
    /// </summary>
    public static bool EventsContainAny(
        IReadOnlyCollection<LogEvent> events, string userId, string email, string wrappedDek)
    {
        foreach (var ev in events)
        {
            var rendered = ev.RenderMessage();
            if (rendered.Contains(userId) || rendered.Contains(email) || rendered.Contains(wrappedDek))
                return true;

            foreach (var prop in ev.Properties.Values)
            {
                var propStr = prop.ToString();
                if (propStr.Contains(userId) || propStr.Contains(email) || propStr.Contains(wrappedDek))
                    return true;
            }
        }
        return false;
    }
}
