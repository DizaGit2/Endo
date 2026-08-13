using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Shouldly;
using Xunit.Abstractions;

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

/// <summary>
/// SAFETY-CRITICAL — <b>P4a erasure completeness</b> (T8).
///
/// <para>P4a is the first phase to persist special-category health data in <b>PLAINTEXT</b> columns:
/// §D mandates it so the P6 inference engine can query symptom codes, regions, intensities, flow
/// levels, pain/mood ordinals, <c>pause_reason = 'pregnancy'</c> and <c>goal_code =
/// 'plan_fertility'</c> in SQL. That breaks the plan-§2 invariant that erasure <i>is</i>
/// crypto-shred: deleting <c>user_keys</c> only makes <i>ciphertext</i> unreadable, and it does
/// nothing at all to a plaintext column. The eleven P4a tables also cannot be reached by their
/// <c>ON DELETE CASCADE</c> FKs, because the job <b>tombstones</b> the <c>users</c> row rather than
/// deleting it — the cascade never fires. So the job must delete them explicitly, and this suite is
/// what proves it did.</para>
///
/// <para><b>Why the assertions are model-derived, not a typed list.</b> A hand-maintained list of
/// tables in a test is exactly what rots when a later phase adds a user-owned table: the test keeps
/// passing while the new table's rows quietly survive account deletion, into the database and into
/// every subsequent <c>pg_dump</c>. So the table set here is enumerated from the EF model — every
/// entity type carrying a <c>UserId</c> property — and each one must be classified as either erased
/// or deliberately retained. Add a user-owned table without touching this file and
/// <see cref="Every_user_owned_table_in_the_model_is_either_erased_or_documented_as_retained"/>
/// fails by name.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class GdprErasurePlaintextCompletenessTests(ITestOutputHelper output)
{
    /// <summary>The scalar property whose presence defines "this table belongs to a user".</summary>
    private const string UserIdPropertyName = "UserId";

    /// <summary>
    /// The soft-delete tombstone column. Its presence on a user-owned entity is EXACTLY what makes
    /// <c>IgnoreQueryFilters()</c> mandatory in the erasure path, so the set of tables that need it is
    /// read from the model here rather than typed out.
    /// </summary>
    private const string DeletedAtPropertyName = "DeletedAt";

    // Deterministic fixture ids (not Guid.NewGuid()): the purge below runs BEFORE the seed as well as
    // after it, so a crashed previous run cannot leave rows that poison this one, and the ids can be
    // quoted verbatim in the erasure evidence. The assembly disables test parallelisation, so no two
    // tests in this project contend for them.
    private static readonly Guid ErasedUserId = new("e8a5e000-0000-4000-8000-000000000001");
    private static readonly Guid OtherUserId = new("e8a5e000-0000-4000-8000-000000000002");

    private static readonly DateTimeOffset SeedAt = new(2026, 8, 6, 9, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset TombstonedAt = new(2026, 8, 6, 10, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly SeedDay = new(2026, 8, 6);

    /// <summary>
    /// The PRIOR audit entry every fixture user gets — an action that is NOT <c>crypto_shred</c>,
    /// stamped before <see cref="SeedAt"/>. Without a row like this "the audit trail survived" is
    /// unfalsifiable: the only row left to count is the one the job inserts on its way out.
    /// </summary>
    private const string PriorAuditAction = AdminAuditLog.Actions.SystemJob;

    private static readonly DateTimeOffset PriorAuditAt = SeedAt.AddDays(-30);

    /// <summary>
    /// User-owned tables the erasure MUST empty. Every one of these is also seeded by
    /// <see cref="SeedFullUserAsync"/>, and the "before" counts assert each actually held rows — so a
    /// zero-rows-after assertion can never pass vacuously.
    /// </summary>
    private static readonly IReadOnlyList<Type> MustBeErased =
    [
        // pre-existing (P2 behaviour, re-pinned here so the sweep covers the whole model)
        typeof(UserKey),                   // THE crypto-shred
        typeof(UserDevice),                // push tokens
        // T5 — plaintext observation tables (four; the first four are soft-deletable)
        typeof(CycleEvent), typeof(CycleDayLog), typeof(Symptom), typeof(CyclePhaseOverride),
        // T6 — plaintext settings & preferences (five)
        typeof(UserCycleSettings), typeof(CycleTrackingPauseSpan),
        typeof(UserGoal), typeof(UserHormonePref), typeof(UserNotificationPref),
        // T7 — body metrics (soft-deletable) and the insight-snapshot placeholder
        typeof(BodyMetric), typeof(UserInsightSnapshot),
    ];

    /// <summary>
    /// The soft-deletable tables this suite EXPECTS, checked for set-equality against the model by
    /// <see cref="Every_user_owned_table_in_the_model_is_either_erased_or_documented_as_retained"/>.
    /// A tombstoned row is invisible to every ordinary read, so a delete written without
    /// <c>IgnoreQueryFilters()</c> silently leaves it behind — which is the precise defect this suite
    /// exists to prevent. <c>body_metrics</c> can legitimately hold several tombstones for the same
    /// <c>(metric, day)</c> (§G9's one filtered-unique exception), so the seed plants two of them.
    ///
    /// <para>Set-equality, never a count. The first version asserted <c>SoftDeletable.Count == 5</c>,
    /// a literal compared to a literal in the same file: a future soft-deletable table could be added
    /// to the model, seeded live-only, and pass every assertion here while a missing
    /// <c>IgnoreQueryFilters()</c> left its tombstoned health rows behind for ever.</para>
    /// </summary>
    private static readonly IReadOnlyList<Type> SoftDeletable =
    [
        typeof(CycleEvent), typeof(CycleDayLog), typeof(Symptom),
        typeof(CyclePhaseOverride), typeof(BodyMetric),
    ];

    /// <summary>
    /// User-owned tables erasure deliberately does NOT delete, each with the reason it survives.
    /// Anything added here is a conscious §F decision, not an oversight.
    /// </summary>
    private static readonly IReadOnlyDictionary<Type, string> RetainedByDesign =
        new Dictionary<Type, string>
        {
            [typeof(UserProfileEnc)] =
                "AES-256-GCM ciphertext only — the user_keys delete makes it permanently unreadable (§F).",
            [typeof(ConsentRecord)] =
                "consent proof must survive erasure — GDPR Art. 7(1) accountability (§F).",
        };

    // ── model-derived helpers ─────────────────────────────────────────────────────────────────

    /// <summary>Every mapped entity type that carries a <c>UserId</c> — i.e. belongs to one user.</summary>
    private static IReadOnlyList<IEntityType> UserOwnedEntityTypes(LumenDbContext db) =>
        [.. db.Model.GetEntityTypes()
            .Where(et => et.FindProperty(UserIdPropertyName) is not null)
            .OrderBy(et => et.GetTableName(), StringComparer.Ordinal)];

    /// <summary>
    /// Every user-owned entity type that ALSO carries a <c>DeletedAt</c> — i.e. every table whose
    /// erasure delete must run under <c>IgnoreQueryFilters()</c>. Derived, so a soft-deletable table
    /// added by a later phase enters this suite without anyone remembering to type it in.
    /// </summary>
    private static IReadOnlyList<IEntityType> SoftDeletableUserOwnedEntityTypes(LumenDbContext db) =>
        [.. UserOwnedEntityTypes(db).Where(et => et.FindProperty(DeletedAtPropertyName) is not null)];

    /// <summary>
    /// Row count straight from Postgres for one user and one table — no EF query filter, no change
    /// tracker, no navigation. Table and column names come from the compiled model, so a
    /// <c>ToTable</c>/column rename surfaces as a missing relation rather than a silent pass.
    /// <paramref name="tombstonedOnly"/> narrows the count to rows whose <c>DeletedAt</c> is set: the
    /// rows an ordinary read hides, and therefore the only ones whose survival is invisible.
    /// </summary>
    private static async Task<long> RowCountAsync(
        LumenDbContext db, IEntityType entityType, Guid userId, bool tombstonedOnly = false)
    {
        var table = entityType.GetTableName().ShouldNotBeNull();
        var schema = entityType.GetSchema();
        var store = StoreObjectIdentifier.Table(table, schema);
        var column = entityType.FindProperty(UserIdPropertyName).ShouldNotBeNull()
            .GetColumnName(store).ShouldNotBeNull();
        var relation = schema is null ? $"\"{table}\"" : $"\"{schema}\".\"{table}\"";

        var tombstoneClause = string.Empty;
        if (tombstonedOnly)
        {
            var deletedAtColumn = entityType.FindProperty(DeletedAtPropertyName)
                .ShouldNotBeNull($"{entityType.ClrType.Name} has no {DeletedAtPropertyName} to count")
                .GetColumnName(store).ShouldNotBeNull();
            tombstoneClause = $" AND \"{deletedAtColumn}\" IS NOT NULL";
        }

        // EF1002 suppressed deliberately: relation and column names cannot be query parameters in any
        // provider, and both come from the compiled EF model — never from a request or stored value.
        // The user id IS a real parameter ({0}).
#pragma warning disable EF1002
        return await db.Database
            .SqlQueryRaw<long>(
                $"SELECT count(*) AS \"Value\" FROM {relation} WHERE \"{column}\" = {{0}}{tombstoneClause}",
                userId)
            .SingleAsync();
#pragma warning restore EF1002
    }

    private static async Task<Dictionary<Type, long>> RowCountsAsync(
        LumenDbContext db, IReadOnlyList<IEntityType> entityTypes, Guid userId, bool tombstonedOnly = false)
    {
        var counts = new Dictionary<Type, long>();
        foreach (var et in entityTypes)
            counts[et.ClrType] = await RowCountAsync(db, et, userId, tombstonedOnly);
        return counts;
    }

    // ── fixture ───────────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Plants a row in EVERY user-owned table, including tombstoned rows in all five soft-deletable
    /// ones. The values are deliberately the special-category facts §D calls out (a pelvic pain
    /// episode with pain types and an intercourse trigger, a pregnancy tracking pause, a fertility
    /// goal) so a survivor is unmistakably health data rather than an anonymous test row.
    /// </summary>
    private static async Task SeedFullUserAsync(LumenDbContext db, Guid userId)
    {
        db.Users.Add(SecurityTestFixtures.NewUser(userId));
        await db.SaveChangesAsync();

        // user_keys — THE crypto-shred target.
        await SecurityTestFixtures.ProvisionDekForTestAsync(
            db, new VaultTransitKeyWrapper(SecurityTestFixtures.Vault()), userId);

        // Retained by design.
        db.UserProfiles.Add(new UserProfileEnc
        {
            UserId = userId,
            DisplayNameEnc = [0x01, 0x02, 0x03],
            CreatedAt = SeedAt,
            UpdatedAt = SeedAt,
        });
        db.ConsentRecords.Add(new ConsentRecord
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            PolicyVersion = "t8-erasure-fixture",
            Locale = "es-ES",
            ConsentedAt = SeedAt,
        });

        db.UserDevices.Add(new UserDevice
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Platform = "ios",
            PushToken = "t8-" + userId.ToString("N"),
            CreatedAt = SeedAt,
        });

        // Prior audit history — retained by design, and the only thing that makes the post-erasure
        // audit assertion falsifiable (see PriorAuditAction). EntityId is the bare user GUID, the same
        // key CryptoShredJob writes its own record under, because admin_audit_log has no user FK.
        db.AdminAuditLogs.Add(new AdminAuditLog
        {
            Id = Guid.NewGuid(),
            ActorId = null,
            Action = PriorAuditAction,
            EntityType = AdminAuditLog.EntityTypes.User,
            EntityId = userId.ToString(),
            BeforeJson = null,
            AfterJson = null,
            At = PriorAuditAt,
        });

        // ── T5: plaintext observations, each with a live row AND a tombstone ──
        db.CycleEvents.AddRange(
            new CycleEvent
            {
                Id = Guid.NewGuid(), UserId = userId, Kind = CycleEvent.Kinds.PeriodStart,
                OccurredOn = SeedDay, FlowIntensity = CycleEvent.FlowIntensityScale.Heavy,
                Source = CycleEvent.Sources.User, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new CycleEvent
            {
                Id = Guid.NewGuid(), UserId = userId, Kind = CycleEvent.Kinds.Spotting,
                OccurredOn = SeedDay.AddDays(-3), FlowIntensity = CycleEvent.FlowIntensityScale.Spotting,
                Source = CycleEvent.Sources.User, CreatedAt = SeedAt, UpdatedAt = SeedAt,
                DeletedAt = TombstonedAt, // tombstone
            });

        db.CycleDayLogs.AddRange(
            new CycleDayLog
            {
                Id = Guid.NewGuid(), UserId = userId, Day = SeedDay, Pain = 7,
                Mood = CycleDayLog.MoodScale.Low, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new CycleDayLog
            {
                Id = Guid.NewGuid(), UserId = userId, Day = SeedDay.AddDays(-1), Pain = 3,
                Mood = CycleDayLog.MoodScale.Tired, CreatedAt = SeedAt, UpdatedAt = SeedAt,
                DeletedAt = TombstonedAt, // tombstone
            });

        db.Symptoms.AddRange(
            new Symptom
            {
                Id = Guid.NewGuid(), UserId = userId, SymptomCode = Symptom.Codes.Pain, Intensity = 8,
                Region = Symptom.Regions.Pelvis, Side = Symptom.Sides.Front,
                PainTypes = [Symptom.PainTypeCodes.Cramping, Symptom.PainTypeCodes.Stabbing],
                Triggers = [Symptom.TriggerCodes.Intercourse],
                OccurredAt = SeedAt, OccurredOn = SeedDay, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new Symptom
            {
                Id = Guid.NewGuid(), UserId = userId,
                SymptomCode = Symptom.NonPainCodes.PainfulIntercourse, Intensity = 6,
                Region = Symptom.Regions.Vaginal, PainTypes = [Symptom.PainTypeCodes.Burning],
                Triggers = [], OccurredAt = SeedAt, OccurredOn = SeedDay,
                CreatedAt = SeedAt, UpdatedAt = SeedAt,
                DeletedAt = TombstonedAt, // tombstone
            });

        db.CyclePhaseOverrides.AddRange(
            new CyclePhaseOverride
            {
                Id = Guid.NewGuid(), UserId = userId, CycleStartOn = SeedDay,
                Phase = CyclePhaseOverride.Phases.Menstrual, Boundary = CyclePhaseOverride.Boundaries.Start,
                OccurredOn = SeedDay, Source = CyclePhaseOverride.Sources.UserCorrection,
                CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new CyclePhaseOverride
            {
                Id = Guid.NewGuid(), UserId = userId, CycleStartOn = SeedDay,
                Phase = CyclePhaseOverride.Phases.Menstrual, Boundary = CyclePhaseOverride.Boundaries.End,
                OccurredOn = SeedDay.AddDays(4), Source = CyclePhaseOverride.Sources.UserCorrection,
                CreatedAt = SeedAt, UpdatedAt = SeedAt,
                DeletedAt = TombstonedAt, // tombstone
            });

        // ── T6: plaintext settings & preferences (no DeletedAt at all) ──
        db.CycleSettings.Add(new UserCycleSettings
        {
            UserId = userId, AvgCycleLengthDays = 30, AvgPeriodLengthDays = 6,
            Regularity = UserCycleSettings.RegularityValues.Irregular,
            TrackingPaused = true, PauseReason = UserCycleSettings.PauseReasons.Pregnancy,
            PausedSince = SeedDay, CreatedAt = SeedAt, UpdatedAt = SeedAt,
        });

        db.CycleTrackingPauseSpans.AddRange(
            new CycleTrackingPauseSpan
            {
                Id = Guid.NewGuid(), UserId = userId, Reason = UserCycleSettings.PauseReasons.Surgical,
                StartedOn = SeedDay.AddDays(-90), EndedOn = SeedDay.AddDays(-60),
                CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new CycleTrackingPauseSpan // the one OPEN span (partial unique index on EndedOn IS NULL)
            {
                Id = Guid.NewGuid(), UserId = userId, Reason = UserCycleSettings.PauseReasons.Pregnancy,
                StartedOn = SeedDay, EndedOn = null, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            });

        db.UserGoals.AddRange(
            new UserGoal
            {
                Id = Guid.NewGuid(), UserId = userId, GoalCode = UserGoal.Codes.PlanFertility,
                Selected = true, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new UserGoal
            {
                Id = Guid.NewGuid(), UserId = userId, GoalCode = UserGoal.Codes.ManageSymptoms,
                Selected = true, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            });

        db.UserHormonePrefs.AddRange(
            new UserHormonePref
            {
                Id = Guid.NewGuid(), UserId = userId, HormoneCode = "estradiol",
                Charted = true, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new UserHormonePref
            {
                Id = Guid.NewGuid(), UserId = userId, HormoneCode = "progesterone",
                Charted = false, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            });

        db.UserNotificationPrefs.AddRange(
            new UserNotificationPref
            {
                Id = Guid.NewGuid(), UserId = userId, CategoryCode = "daily_checkin",
                Enabled = true, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new UserNotificationPref
            {
                Id = Guid.NewGuid(), UserId = userId, CategoryCode = "period_prediction",
                Enabled = false, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            });

        // ── T7: body metrics (one live + TWO tombstones on the same key) and the snapshot ──
        db.BodyMetrics.AddRange(
            new BodyMetric
            {
                Id = Guid.NewGuid(), UserId = userId, Metric = BodyMetric.Metrics.WeightKg,
                ValueEnc = [0x0A, 0x0B], Source = BodyMetric.Sources.Manual,
                MeasuredAt = SeedAt, MeasuredOn = SeedDay, CreatedAt = SeedAt, UpdatedAt = SeedAt,
            },
            new BodyMetric
            {
                Id = Guid.NewGuid(), UserId = userId, Metric = BodyMetric.Metrics.WeightKg,
                ValueEnc = [0x0C], Source = BodyMetric.Sources.Manual,
                MeasuredAt = SeedAt, MeasuredOn = SeedDay, CreatedAt = SeedAt, UpdatedAt = SeedAt,
                DeletedAt = TombstonedAt, // tombstone #1 on the SAME (metric, day)
            },
            new BodyMetric
            {
                Id = Guid.NewGuid(), UserId = userId, Metric = BodyMetric.Metrics.WeightKg,
                ValueEnc = [0x0D], Source = BodyMetric.Sources.AppleHealth,
                MeasuredAt = SeedAt, MeasuredOn = SeedDay, CreatedAt = SeedAt, UpdatedAt = SeedAt,
                DeletedAt = TombstonedAt, // tombstone #2 — §G9's filtered-unique exception allows it
            });

        db.UserInsightSnapshots.Add(new UserInsightSnapshot
        {
            UserId = userId, CreatedAt = SeedAt, UpdatedAt = SeedAt,
        });

        await db.SaveChangesAsync();
    }

    /// <summary>Removes every trace of the fixture users — run BEFORE the seed as well as after.</summary>
    private static async Task PurgeAsync(params Guid[] userIds)
    {
        await using var db = SecurityTestFixtures.NewDb();
        foreach (var id in userIds)
        {
            await db.Symptoms.IgnoreQueryFilters().Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.CycleDayLogs.IgnoreQueryFilters().Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.CycleEvents.IgnoreQueryFilters().Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.CyclePhaseOverrides.IgnoreQueryFilters().Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.BodyMetrics.IgnoreQueryFilters().Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.UserInsightSnapshots.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.UserGoals.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.UserHormonePrefs.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.UserNotificationPrefs.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.CycleTrackingPauseSpans.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.CycleSettings.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.UserProfiles.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.ConsentRecords.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.UserDevices.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.UserKeys.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.AdminAuditLogs.Where(l => l.EntityId == id.ToString()).ExecuteDeleteAsync();
            await db.Users.IgnoreQueryFilters().Where(u => u.Id == id).ExecuteDeleteAsync();
        }
    }

    // ── Test 5: the structural completeness guard ─────────────────────────────────────────────

    [Fact]
    public void Every_user_owned_table_in_the_model_is_either_erased_or_documented_as_retained()
    {
        // This is the guard that must survive P5+. It reads the table set from the EF MODEL, so a
        // future phase that adds a user-owned table without extending the erasure path fails HERE, by
        // name, instead of silently leaking that table's rows past account deletion for ever.
        using var db = SecurityTestFixtures.NewDb(); // model only — no connection is opened
        var modelled = UserOwnedEntityTypes(db).Select(et => et.ClrType).ToHashSet();
        var accounted = MustBeErased.Concat(RetainedByDesign.Keys).ToHashSet();

        var unaccounted = modelled.Except(accounted).Select(t => t.Name).OrderBy(n => n, StringComparer.Ordinal);
        unaccounted.ShouldBeEmpty(
            "these mapped entity types carry a UserId but are neither in MustBeErased nor in " +
            "RetainedByDesign. Every user-owned table must be one or the other: add its " +
            "ExecuteDeleteAsync to CryptoShredJob and list it in MustBeErased (seeding it in " +
            "SeedFullUserAsync too), or record in RetainedByDesign the §F reason it survives.");

        var stale = accounted.Except(modelled).Select(t => t.Name).OrderBy(n => n, StringComparer.Ordinal);
        stale.ShouldBeEmpty(
            "these types are classified here but no longer carry a UserId in the EF model — the " +
            "erasure classification has drifted from the schema.");

        // Cross-check the classification against the phase's own arithmetic: 11 P4a tables + user_keys
        // + user_devices erased, 2 retained. A silent re-balancing between the two lists would keep the
        // set-difference assertions above green.
        MustBeErased.Count.ShouldBe(13);
        RetainedByDesign.Count.ShouldBe(2);

        // The SOFT-DELETE axis, also read from the model. This is the structural half of the tombstone
        // guard: every user-owned table carrying a DeletedAt must be one this suite knows to seed a
        // tombstone into and to count tombstones on after the erasure. Set-equality in BOTH directions
        // — a count would let a sixth soft-deletable table appear, be seeded live-only, and sail
        // through the end-to-end test while a missing IgnoreQueryFilters() left its tombstones behind.
        var modelledSoftDeletable = SoftDeletableUserOwnedEntityTypes(db).Select(et => et.ClrType).ToHashSet();

        modelledSoftDeletable.Except(SoftDeletable).Select(t => t.Name).OrderBy(n => n, StringComparer.Ordinal)
            .ShouldBeEmpty(
                $"these user-owned entity types carry a {DeletedAtPropertyName} but are missing from " +
                "SoftDeletable. Add them there AND seed a tombstoned row for them in SeedFullUserAsync, " +
                "or their tombstones are never counted and a CryptoShredJob delete written without " +
                "IgnoreQueryFilters() leaves invisible health rows behind for ever.");

        SoftDeletable.Except(modelledSoftDeletable).Select(t => t.Name).OrderBy(n => n, StringComparer.Ordinal)
            .ShouldBeEmpty(
                $"these types are listed as soft-deletable but no longer carry a {DeletedAtPropertyName} " +
                "in the EF model — the tombstone classification has drifted from the schema.");
    }

    // ── Test 6: end-to-end erasure completeness + tenant isolation ────────────────────────────

    [Fact]
    public async Task Erasure_physically_deletes_every_user_owned_plaintext_row_and_spares_the_other_tenant()
    {
        await using var fixtureLock = await InsightSnapshotFixtureLock.AcquireAsync();
        await PurgeAsync(ErasedUserId, OtherUserId);
        try
        {
            await using var seed = SecurityTestFixtures.NewDb();
            await SeedFullUserAsync(seed, ErasedUserId);
            await SeedFullUserAsync(seed, OtherUserId);

            await using var probe = SecurityTestFixtures.NewDb();
            var userOwned = UserOwnedEntityTypes(probe);
            var softDeletable = SoftDeletableUserOwnedEntityTypes(probe);
            var erasedBefore = await RowCountsAsync(probe, userOwned, ErasedUserId);
            var otherBefore = await RowCountsAsync(probe, userOwned, OtherUserId);
            var tombstonesBefore = await RowCountsAsync(probe, softDeletable, ErasedUserId, tombstonedOnly: true);

            // Non-vacuity: the sweep below can only mean something if every table actually held rows.
            foreach (var t in MustBeErased)
                erasedBefore[t].ShouldBeGreaterThan(0,
                    $"the fixture must seed {t.Name} — a zero-rows-after assertion on an empty table " +
                    "proves nothing");

            // Non-vacuity, tombstone axis. Every soft-deletable table must hold at least one row with
            // DeletedAt SET before the erasure runs, or "no tombstones survived" is a statement about
            // rows that never existed. This is the assertion whose absence made the whole soft-delete
            // half of this suite decorative.
            foreach (var et in softDeletable)
                tombstonesBefore[et.ClrType].ShouldBeGreaterThan(0,
                    $"the fixture must seed a TOMBSTONED (DeletedAt IS NOT NULL) row in " +
                    $"{et.GetTableName()} — without one, the post-erasure tombstone count is trivially " +
                    "zero and a missing IgnoreQueryFilters() would pass unnoticed");

            // The pre-existing audit history the erasure must NOT touch (fix 4). Seeded with At before
            // SeedAt and an action that is not crypto_shred, so "the audit trail survived" cannot be
            // satisfied by the single row the job writes for itself.
            var auditBefore = await probe.AdminAuditLogs.AsNoTracking()
                .CountAsync(l => l.EntityId == ErasedUserId.ToString());
            auditBefore.ShouldBe(1, "the fixture seeds exactly one PRIOR audit row for the erased user");

            // Act — erase user 1 only.
            await using var jobDb = SecurityTestFixtures.NewDb();
            await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance)
                .ExecuteAsync(ErasedUserId);

            await using var read = SecurityTestFixtures.NewDb();
            var erasedAfter = await RowCountsAsync(read, userOwned, ErasedUserId);
            var otherAfter = await RowCountsAsync(read, userOwned, OtherUserId);
            var tombstonesAfter = await RowCountsAsync(read, softDeletable, ErasedUserId, tombstonedOnly: true);

            // Live-database evidence, straight from Postgres, for the erasure record.
            output.WriteLine($"erased user  = {ErasedUserId}");
            output.WriteLine($"other tenant = {OtherUserId}");
            output.WriteLine($"{"table",-28} {"erased:before",13} {"after",7}   {"other:before",12} {"after",7}");
            foreach (var et in userOwned)
            {
                var t = et.ClrType;
                output.WriteLine(
                    $"{et.GetTableName(),-28} {erasedBefore[t],13} {erasedAfter[t],7}   " +
                    $"{otherBefore[t],12} {otherAfter[t],7}");
            }

            // 1. TOMBSTONES — asserted FIRST, and on a tombstone-specific count. It has to come before
            //    the total-rows sweep below to be a guard at all: `erasedAfter` is a raw count(*) that
            //    already includes tombstones, so the general "survivors" assertion always throws first
            //    and the tombstone message could never be the one an engineer read. The pre-counts
            //    above prove each of these tables actually held a tombstone going in.
            var tombstoneSurvivors = softDeletable
                .Where(et => tombstonesAfter[et.ClrType] > 0)
                .Select(et => $"{et.GetTableName()}={tombstonesAfter[et.ClrType]} of {tombstonesBefore[et.ClrType]}")
                .OrderBy(s => s, StringComparer.Ordinal);
            tombstoneSurvivors.ShouldBeEmpty(
                "TOMBSTONED rows survived erasure — the delete for these tables must run under " +
                "IgnoreQueryFilters(). This is the invisible leak: every ordinary read already hides " +
                "these rows, so nothing but this assertion would ever reveal that the health data of a " +
                "deleted account is still in Postgres and in every nightly pg_dump.");

            // 2. COMPLETENESS — nothing user-owned survives except what §F deliberately retains.
            var survivors = MustBeErased
                .Where(t => erasedAfter[t] > 0)
                .Select(t => $"{t.Name}={erasedAfter[t]}")
                .OrderBy(s => s, StringComparer.Ordinal);
            survivors.ShouldBeEmpty(
                "these user-owned tables still hold rows for the erased user. Plaintext health data " +
                "that survives DELETE /me is unrecoverable by a later fix: it is already in every " +
                "nightly pg_dump.");

            // 3. RETENTION — the two deliberate §F exceptions are untouched, and the audit trail stands.
            foreach (var (type, why) in RetainedByDesign)
                erasedAfter[type].ShouldBe(erasedBefore[type], $"must survive erasure: {why}");

            // admin_audit_log has no user FK and is never deleted: the PRIOR history survives and the
            // job adds exactly one crypto_shred row. Counting only the crypto_shred rows would be a
            // guard that cannot fail — the job inserts that row itself, so a job that wiped the user's
            // entire audit trail before writing it would still show exactly one.
            var audit = await read.AdminAuditLogs.AsNoTracking()
                .Where(l => l.EntityId == ErasedUserId.ToString())
                .ToListAsync();
            audit.Count.ShouldBe(auditBefore + 1,
                "erasure must ADD its crypto_shred row to the audit trail, not replace it — the prior " +
                "history is GDPR Art. 7(1)/recital-65 accountability evidence and has no user FK (§F)");
            audit.Count(l => l.Action == AdminAuditLog.Actions.CryptoShred).ShouldBe(1,
                "exactly one erasure record (§F)");
            audit.ShouldContain(l => l.Action == PriorAuditAction && l.At == PriorAuditAt,
                $"the pre-existing '{PriorAuditAction}' row seeded at {PriorAuditAt:O} must still be there");

            // 4. TENANT ISOLATION — the other user lost nothing at all, in any table.
            var collateral = userOwned
                .Where(et => otherAfter[et.ClrType] != otherBefore[et.ClrType])
                .Select(et => $"{et.GetTableName()}: {otherBefore[et.ClrType]} -> {otherAfter[et.ClrType]}")
                .OrderBy(s => s, StringComparer.Ordinal);
            collateral.ShouldBeEmpty("erasing one user must not touch a single row belonging to another");
        }
        finally
        {
            await PurgeAsync(ErasedUserId, OtherUserId);
        }
    }
}

/// <summary>
/// Cross-suite mutex for the transient <c>user_insight_snapshot</c> rows the erasure fixture plants.
/// <c>Lumen.IntegrationTests.SchemaSmokeLiveTests.The_insight_snapshot_table_holds_zero_rows</c>
/// asserts a GLOBAL zero count on that table (§G6: P4a computes nothing, so any row there is
/// clinical output leaking into a phase with no engine). The erasure fixture must insert one to prove
/// the table is actually erased, so the two would race whenever both suites run in the same
/// <c>dotnet test</c> invocation. A Postgres session advisory lock on the shared key below makes the
/// window unobservable without weakening either assertion or adding a sleep.
///
/// <para>The key is duplicated verbatim in that file rather than shared — test projects must not
/// reference each other (same rule as <see cref="SecurityTestFixtures"/>).</para>
/// </summary>
internal sealed class InsightSnapshotFixtureLock : IAsyncDisposable
{
    /// <summary>ASCII "LUMEN8" as a bigint — arbitrary, but stable and unlikely to collide.</summary>
    public const long Key = 0x4C554D454E38;

    private readonly LumenDbContext _db;

    private InsightSnapshotFixtureLock(LumenDbContext db) => _db = db;

    public static async Task<InsightSnapshotFixtureLock> AcquireAsync()
    {
        var db = SecurityTestFixtures.NewDb();
        await db.Database.OpenConnectionAsync(); // session lock — must hold ONE physical connection
        await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_lock({0})", Key);
        return new InsightSnapshotFixtureLock(db);
    }

    public async ValueTask DisposeAsync()
    {
        await _db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_unlock({0})", Key);
        await _db.Database.CloseConnectionAsync();
        await _db.DisposeAsync();
    }
}
