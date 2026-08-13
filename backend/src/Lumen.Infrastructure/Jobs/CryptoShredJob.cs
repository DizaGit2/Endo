using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace Lumen.Infrastructure.Jobs;

/// <summary>
/// Hangfire background job that performs GDPR right-to-erasure (§F) for one user. Deleting the user's
/// <c>user_keys</c> row crypto-shreds ALL their AES-256-GCM ciphertext — the DEK can no longer be
/// unwrapped, so the data is permanently unreadable. The job also <b>physically deletes every
/// plaintext row the user owns</b> (see below), deletes the user's device rows (push tokens) in
/// <c>user_devices</c>, tombstones the user row, and records the erasure in the audit log. It is
/// idempotent (the <c>DeletedAt</c> tombstone is the completion sentinel) and emits NO PII in logs.
/// Disabling the Keycloak user is the API endpoint's responsibility, NOT this job's.
///
/// <para><b>Why crypto-shred alone is no longer enough (P4a, §F amended 2026-08-06).</b> P4a is the
/// first phase to persist special-category health data in PLAINTEXT columns — §D mandates it so the
/// P6 inference engine can query symptom codes, regions, intensities, flow levels, pain/mood
/// ordinals, <c>pause_reason</c> and <c>goal_code</c> in SQL. Destroying the DEK does nothing to a
/// plaintext column, so those rows must be DELETED, not shredded. The plan-§2 invariant
/// "erasure = crypto-shred" now reads "crypto-shred for ciphertext, physical delete for plaintext".</para>
///
/// <para><b>Why the cascade cannot be relied on.</b> All eleven P4a tables carry
/// <c>UserId … ON DELETE CASCADE</c> to <c>users("Id")</c>, but this job <b>tombstones</b> the
/// <c>users</c> row rather than deleting it (the id is kept for FK integrity and for the audit
/// record), so the cascade never fires. Each table is therefore deleted EXPLICITLY below.</para>
///
/// <para><b>Two tables deliberately survive</b> and must NOT be added to the deletes:
/// <c>consent_records</c> (consent proof, GDPR Art. 7(1) accountability) and <c>admin_audit_log</c>
/// (no user FK — the erasure record itself). <c>user_profile_enc</c> also stays: it is ciphertext
/// only, and the <c>user_keys</c> delete already makes it permanently unreadable.</para>
/// </summary>
public sealed class CryptoShredJob(
    LumenDbContext db,
    TimeProvider timeProvider,
    ILogger<CryptoShredJob> logger)
{
    // Explicit retry policy (matches Hangfire's default of 10). Retries are SAFE because the guarded
    // tombstone-claim below (ExecuteUpdate WHERE DeletedAt == null) makes the job idempotent: a retry
    // after a partial/failed run either re-claims an un-tombstoned row or matches 0 rows and bails,
    // so the crypto-shred and its single audit entry happen at most once.
    [Hangfire.AutomaticRetry(Attempts = 10)]
    public async Task ExecuteAsync(Guid userId, CancellationToken ct = default)
    {
        // Bypass the soft-delete query filter so an already-tombstoned user is still found (idempotency).
        var user = await db.Users.IgnoreQueryFilters().FirstOrDefaultAsync(u => u.Id == userId, ct);

        if (user is null)
        {
            // Nothing to erase. Never log the user id or any PII — only a non-identifying outcome (§F).
            logger.LogInformation("CryptoShredJob finished with outcome {Outcome}", "user-not-found");
            return;
        }

        if (user.DeletedAt is not null)
        {
            // Already shredded. DeletedAt being set is the completion marker, so re-runs never write a
            // second audit row. Return WITHOUT a new audit entry.
            // INVARIANT: this sentinel is valid only because CryptoShredJob is the SOLE writer of
            // DeletedAt. If any other path ever tombstones a user, DeletedAt no longer implies the
            // crypto-shred ran, and this early-return must also verify user_keys absence before bailing.
            logger.LogInformation("CryptoShredJob finished with outcome {Outcome}", "already-shredded");
            return;
        }

        // Single captured instant — reused for the tombstone update AND the audit At so they're equal.
        var now = timeProvider.GetUtcNow();

        // Keys + devices + tombstone + audit must commit together or not at all.
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        // Atomic claim: only the first run whose row still has DeletedAt == null proceeds. A racing run
        // blocks on this row's lock and, once the winner commits, matches 0 rows and bails — so exactly
        // one audit entry is ever written, without relying on Hangfire to serialize retries.
        // Use the injected TimeProvider for determinism (never DateTime.UtcNow — architecture rule).
        // Clearing Locale/Timezone here also erases the residual non-encrypted quasi-identifiers: they are
        // plain NOT-NULL text columns the DEK deletion can't make unreadable, so blank them as part of the
        // erasure (empty string satisfies the required/NOT-NULL constraint). EmailHash retention stays
        // deferred as documented below (unresolved re-registration product decision).
        var claimed = await db.Users.IgnoreQueryFilters()
            .Where(u => u.Id == userId && u.DeletedAt == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.DeletedAt, now)
                .SetProperty(u => u.UpdatedAt, now)
                .SetProperty(u => u.Locale, "")
                .SetProperty(u => u.Timezone, ""), ct);
        if (claimed == 0)
        {
            // A concurrent run already shredded this user between our outer check and here. Bail without
            // a second audit row; tx disposes -> rollback (nothing committed). PII-free outcome only (§F).
            logger.LogInformation("CryptoShredJob finished with outcome {Outcome}", "already-shredded");
            return;
        }

        // THE crypto-shred: delete the DEK row so every ciphertext for this user becomes unreadable.
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync(ct);

        // Empty push tokens by deleting the device rows entirely.
        await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync(ct);

        // ── The eleven P4a plaintext tables (§F, amended for P4a) ────────────────────────────────
        // Same precedent as user_devices immediately above: plaintext rows are DELETED, not made
        // unreadable. The user row is only tombstoned, so the ON DELETE CASCADE FKs never fire — a
        // table missing from this list keeps its rows for ever, in the database and in every nightly
        // pg_dump, and no later fix can recall a backup that already shipped. The completeness of
        // this list is enforced by Lumen.SecurityTests'
        // GdprErasurePlaintextCompletenessTests, which enumerates every entity type carrying a
        // UserId from the EF model: a future phase adding a user-owned table fails there by name.
        //
        // IgnoreQueryFilters() is MANDATORY on the five soft-deletable tables below. Their global
        // query filter is DeletedAt == null, so without it a delete silently skips every tombstoned
        // row — exactly the rows an ordinary read already hides, which is what makes the leak
        // invisible. body_metrics can hold SEVERAL tombstones per (metric, day) by design (§G9's one
        // filtered-unique exception), so it is the worst offender.
        await db.Symptoms.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.CycleDayLogs.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.CycleEvents.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.CyclePhaseOverrides.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.BodyMetrics.IgnoreQueryFilters().Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);

        // The remaining six carry no DeletedAt at all (a tombstone on a per-user singleton or a
        // preference row would strand its unique key), so no filter to bypass.
        await db.UserInsightSnapshots.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.UserGoals.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.UserHormonePrefs.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.UserNotificationPrefs.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.CycleTrackingPauseSpans.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.CycleSettings.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);

        // TODO(P7a): delete MinIO objects under {user_id}/ once labs/object-storage lands. Erasure of
        // stored objects is NOT yet complete.

        // NOTE: email-hash retention / re-registration is deferred — whether erasure frees the email for
        // re-registration is an unresolved product decision out of scope here, so EmailHash is NOT cleared.

        // Exactly ONE audit entry. EntityId carries the bare user GUID (the intended erasure record); the
        // audit table has no user_id FK and survives the tombstone. Before/After stay null — no PII.
        db.AdminAuditLogs.Add(new AdminAuditLog
        {
            Id = Guid.NewGuid(),
            ActorId = null, // system/job actor
            Action = AdminAuditLog.Actions.CryptoShred,
            EntityType = AdminAuditLog.EntityTypes.User,
            EntityId = userId.ToString(),
            BeforeJson = null,
            AfterJson = null,
            At = now,
        });

        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        logger.LogInformation("CryptoShredJob finished with outcome {Outcome}", "shredded");
    }
}
