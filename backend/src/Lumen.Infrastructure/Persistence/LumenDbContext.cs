using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Lumen.Infrastructure.Persistence;

public class LumenDbContext(DbContextOptions<LumenDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<UserKey> UserKeys => Set<UserKey>();
    public DbSet<UserProfileEnc> UserProfiles => Set<UserProfileEnc>();
    public DbSet<ConsentRecord> ConsentRecords => Set<ConsentRecord>();
    public DbSet<UserDevice> UserDevices => Set<UserDevice>();
    public DbSet<AdminAuditLog> AdminAuditLogs => Set<AdminAuditLog>();
    public DbSet<CycleEvent> CycleEvents => Set<CycleEvent>();
    public DbSet<CycleDayLog> CycleDayLogs => Set<CycleDayLog>();
    public DbSet<Symptom> Symptoms => Set<Symptom>();
    public DbSet<CyclePhaseOverride> CyclePhaseOverrides => Set<CyclePhaseOverride>();

    // Named CycleSettings, not UserCycleSettings, so the property does not shadow the entity type.
    public DbSet<UserCycleSettings> CycleSettings => Set<UserCycleSettings>();
    public DbSet<CycleTrackingPauseSpan> CycleTrackingPauseSpans => Set<CycleTrackingPauseSpan>();
    public DbSet<UserGoal> UserGoals => Set<UserGoal>();
    public DbSet<UserHormonePref> UserHormonePrefs => Set<UserHormonePref>();
    public DbSet<UserNotificationPref> UserNotificationPrefs => Set<UserNotificationPref>();
    public DbSet<BodyMetric> BodyMetrics => Set<BodyMetric>();
    public DbSet<UserInsightSnapshot> UserInsightSnapshots => Set<UserInsightSnapshot>();

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        // The soft-delete query filter on User intentionally coexists with required dependents.
        => optionsBuilder.ConfigureWarnings(w =>
            w.Ignore(CoreEventId.PossibleIncorrectRequiredNavigationWithQueryFilterInteractionWarning));

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>(e =>
        {
            e.ToTable("users");
            e.HasKey(x => x.Id);
            e.Property(x => x.EmailHash).IsRequired().HasMaxLength(64); // Vault Transit HMAC ("vault:v1:<b64>"); ≤64 chars
            e.HasIndex(x => x.EmailHash).IsUnique();
            e.Property(x => x.Locale).IsRequired().HasMaxLength(35);    // BCP-47
            e.Property(x => x.Timezone).IsRequired().HasMaxLength(64);  // IANA tz id
            // D-06 reserved (T7): metric-only v1, no write path. ValueGeneratedNever() for the same
            // reason as the T6 settings columns — the CLR initializer references a named const, so
            // EF infers no sentinel and an explicit null would otherwise be swallowed by the default.
            e.Property(x => x.UnitSystem).IsRequired().HasMaxLength(8)
                .HasDefaultValue(User.UnitSystems.Default).ValueGeneratedNever();
            e.HasQueryFilter(x => x.DeletedAt == null);                 // soft-deleted users excluded from reads (D-13)
        });

        b.Entity<UserKey>(e =>
        {
            e.ToTable("user_keys");
            e.HasKey(x => x.UserId);
            e.Property(x => x.WrappedDek).IsRequired();
            e.Property(x => x.VaultKeyName).IsRequired().HasMaxLength(128);
            e.HasOne<User>().WithOne().HasForeignKey<UserKey>(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<UserProfileEnc>(e =>
        {
            e.ToTable("user_profile_enc");
            e.HasKey(x => x.UserId);
            e.HasOne<User>().WithOne().HasForeignKey<UserProfileEnc>(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<ConsentRecord>(e =>
        {
            e.ToTable("consent_records");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.UserId);
            e.Property(x => x.PolicyVersion).IsRequired().HasMaxLength(64);
            e.Property(x => x.Locale).HasMaxLength(35);
            // Consent proof must survive erasure (crypto-shred, not a row delete) — do NOT cascade.
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<UserDevice>(e =>
        {
            e.ToTable("user_devices");
            e.HasKey(x => x.Id);
            e.Property(x => x.Platform).IsRequired().HasMaxLength(16);
            // Off the entity constant, never a second copy of the number: T15's validator states the
            // same limit inside a wire string the client renders, and two literals could only drift.
            e.Property(x => x.PushToken).IsRequired().HasMaxLength(UserDevice.PushTokenMaxLength);
            e.HasIndex(x => new { x.UserId, x.PushToken }).IsUnique();
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<AdminAuditLog>(e =>
        {
            e.ToTable("admin_audit_log");
            e.HasKey(x => x.Id);
            e.Property(x => x.Action).IsRequired().HasMaxLength(64);
            e.Property(x => x.EntityType).IsRequired().HasMaxLength(64);
            e.Property(x => x.EntityId).HasMaxLength(128);
            e.Property(x => x.BeforeJson).HasColumnType("jsonb");
            e.Property(x => x.AfterJson).HasColumnType("jsonb");
            e.HasIndex(x => x.At);
            e.HasIndex(x => new { x.EntityId, x.Action }); // GDPR/DSAR erasure-proof lookup: WHERE EntityId = ? AND Action = 'crypto_shred'
            // No FK to User — audit history must survive crypto-shred (§F).
        });

        // --- P4a observation tables (T5) ---------------------------------------------------
        // snake_case table names, PascalCase column names, no naming convention: the CHECK literals
        // below double-quote the real column identifiers, and any HasColumnName rename would
        // silently invalidate them on BOTH providers (T1 probe 3).
        // CHECKs are for frozen NUMERIC scales only — vocabulary membership is enforced in code
        // (§D: "Enums hard-coded in code, not in DB"), because the sets are append-only and a DB
        // enum would make every new member a migration.

        b.Entity<CycleEvent>(e =>
        {
            e.ToTable("cycle_events", t => t.HasCheckConstraint(
                "ck_cycle_events_flow_intensity_range", "\"FlowIntensity\" >= 1 AND \"FlowIntensity\" <= 4"));
            e.HasKey(x => x.Id);
            e.Property(x => x.Kind).IsRequired().HasMaxLength(16);
            e.Property(x => x.Source).IsRequired().HasMaxLength(16);
            // §G9 UNFILTERED: tombstones keep occupying the key, so upserts revive rather than insert.
            e.HasIndex(x => new { x.UserId, x.Kind, x.OccurredOn }).IsUnique();
            e.HasIndex(x => new { x.UserId, x.OccurredOn }); // calendar/range reads
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
            e.HasQueryFilter(x => x.DeletedAt == null);
        });

        b.Entity<CycleDayLog>(e =>
        {
            e.ToTable("cycle_day_logs", t =>
            {
                t.HasCheckConstraint("ck_cycle_day_logs_pain_range", "\"Pain\" >= 0 AND \"Pain\" <= 10");
                t.HasCheckConstraint("ck_cycle_day_logs_mood_range", "\"Mood\" >= 1 AND \"Mood\" <= 4");
                // No CHECK on Energy/Libido: D-10 defers both scales, so there is nothing to pin yet.
            });
            e.HasKey(x => x.Id);
            // §G9 UNFILTERED: one row per (user, day) forever — the upsert revives its own tombstone.
            e.HasIndex(x => new { x.UserId, x.Day }).IsUnique();
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
            e.HasQueryFilter(x => x.DeletedAt == null);
        });

        b.Entity<Symptom>(e =>
        {
            e.ToTable("symptoms", t => t.HasCheckConstraint(
                "ck_symptoms_intensity_range", "\"Intensity\" >= 0 AND \"Intensity\" <= 10"));
            e.HasKey(x => x.Id);
            e.Property(x => x.SymptomCode).IsRequired().HasMaxLength(32);
            e.Property(x => x.Region).IsRequired().HasMaxLength(32).HasDefaultValue(Symptom.Regions.Default);
            e.Property(x => x.Side).HasMaxLength(8);
            // Primitive collections: IsRequired() only. No HasColumnType — a "text[]" literal would
            // leak into SQLite's CREATE TABLE — and no DB default; the CLR `= []` covers it (T1 probe 2).
            e.Property(x => x.PainTypes).IsRequired();
            e.Property(x => x.Triggers).IsRequired();
            e.HasIndex(x => new { x.UserId, x.OccurredOn, x.OccurredAt });
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
            e.HasQueryFilter(x => x.DeletedAt == null);
        });

        b.Entity<CyclePhaseOverride>(e =>
        {
            e.ToTable("cycle_phase_overrides");
            e.HasKey(x => x.Id);
            e.Property(x => x.Phase).IsRequired().HasMaxLength(16);
            e.Property(x => x.Boundary).IsRequired().HasMaxLength(8);
            e.Property(x => x.Source).IsRequired().HasMaxLength(24);
            // §G9 UNFILTERED: re-correcting a boundary revives the existing row.
            e.HasIndex(x => new { x.UserId, x.CycleStartOn, x.Phase, x.Boundary }).IsUnique();
            e.HasIndex(x => new { x.UserId, x.CycleStartOn }); // "all overrides for this cycle"
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
            e.HasQueryFilter(x => x.DeletedAt == null);
        });

        // --- P4a settings & preference tables (T6) -----------------------------------------
        // None of these carry DeletedAt: D-13's soft-delete governs individual *entries*, and a
        // tombstone on a per-user singleton or a preference row would strand its unique key and
        // block re-selecting. Account deletion hard-deletes them (§F, T8).
        //
        // Every column with a DB default is also mapped ValueGeneratedNever(). HasDefaultValue()
        // alone leaves EF's value-generation "sentinel" (the value treated as "not set") wherever
        // the model build inferred it. AvgCycleLengthDays' and Regularity's CLR initializers
        // reference a named const rather than a literal, so EF does NOT infer the sentinel from
        // them and falls back to the plain CLR type default (0 / null): without
        // ValueGeneratedNever() an explicit AvgCycleLengthDays = 0 or Regularity = null would be
        // dropped from the INSERT and silently replaced by the DB default (28 / "somewhat"),
        // which for AvgCycleLengthDays defeats the "> 0" CHECK below entirely (see
        // CycleSettingsModelTests.AvgCycleLengthDays_zero_is_not_swallowed_by_the_DB_default_and_the_CHECK_still_rejects_it
        // and the Regularity/NOT-NULL sibling). The four bool columns do NOT have this problem —
        // EF Core 10 infers their sentinel from their literal `= true` initializers (or, for the
        // two `default false` columns, the CLR default already equals the DB default) — but they
        // are mapped ValueGeneratedNever() too, for consistency across every defaulted column on
        // this entity and as defence-in-depth against that inference changing later. The DDL
        // default still ships regardless (it is what a non-EF writer gets); EF simply always sends
        // the CLR value once ValueGeneratedNever() is set.

        b.Entity<UserCycleSettings>(e =>
        {
            e.ToTable("user_cycle_settings", t =>
            {
                // §G7 structural only: a positive integer that fits smallint. NOT the sanity band
                // (a non-blocking endpoint warning) and NOT the C-03/C-04 clinical bound (see
                // ARCHITECTURE.md §A; clinician-UNSIGNED, estimator-only, P6). Bounds never block
                // entry. The actual numerals are deliberately not repeated here — per §G7 they
                // live only in the STATUS block and the ARCHITECTURE.md §A P4a row.
                t.HasCheckConstraint(
                    "ck_user_cycle_settings_avg_cycle_length_positive", "\"AvgCycleLengthDays\" > 0");
                t.HasCheckConstraint(
                    "ck_user_cycle_settings_avg_period_length_positive",
                    "\"AvgPeriodLengthDays\" IS NULL OR \"AvgPeriodLengthDays\" > 0");
                // No CHECK tying PauseReason to TrackingPaused: resume preserves the last reason.
            });
            e.HasKey(x => x.UserId);
            e.Property(x => x.AvgCycleLengthDays)
                .HasDefaultValue(UserCycleSettings.DefaultAvgCycleLengthDays).ValueGeneratedNever();
            // AvgPeriodLengthDays: nullable, deliberately no default (screen 3 never collects it).
            e.Property(x => x.Regularity).IsRequired().HasMaxLength(16)
                .HasDefaultValue(UserCycleSettings.RegularityValues.Default).ValueGeneratedNever();
            e.Property(x => x.PhasePredictionEnabled).HasDefaultValue(true).ValueGeneratedNever();
            e.Property(x => x.AutoDetectPeriodStartEnabled).HasDefaultValue(true).ValueGeneratedNever();
            e.Property(x => x.ShowFertilityWindowEnabled).HasDefaultValue(false).ValueGeneratedNever();
            e.Property(x => x.TrackingPaused).HasDefaultValue(false).ValueGeneratedNever();
            e.Property(x => x.PauseReason).HasMaxLength(32);
            e.HasOne<User>().WithOne().HasForeignKey<UserCycleSettings>(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<CycleTrackingPauseSpan>(e =>
        {
            e.ToTable("cycle_tracking_pause_spans");
            e.HasKey(x => x.Id);
            e.Property(x => x.Reason).IsRequired().HasMaxLength(32);
            // At most one OPEN pause per user. The filter is on EndedOn — a domain lifecycle
            // column, not a soft-delete marker — so this is outside the §G9 tombstone regime.
            e.HasIndex(x => x.UserId).IsUnique().HasFilter("\"EndedOn\" IS NULL");
            e.HasIndex(x => new { x.UserId, x.StartedOn }); // a user's spans in chronological order
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<UserGoal>(e =>
        {
            e.ToTable("user_goals");
            e.HasKey(x => x.Id);
            e.Property(x => x.GoalCode).IsRequired().HasMaxLength(32);
            e.HasIndex(x => new { x.UserId, x.GoalCode }).IsUnique();
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<UserHormonePref>(e =>
        {
            e.ToTable("user_hormone_prefs");
            e.HasKey(x => x.Id);
            e.Property(x => x.HormoneCode).IsRequired().HasMaxLength(32);
            e.HasIndex(x => new { x.UserId, x.HormoneCode }).IsUnique();
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<UserNotificationPref>(e =>
        {
            e.ToTable("user_notification_prefs");
            e.HasKey(x => x.Id);
            e.Property(x => x.CategoryCode).IsRequired().HasMaxLength(32);
            e.HasIndex(x => new { x.UserId, x.CategoryCode }).IsUnique();
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        // --- P4a body metrics & the insight-snapshot placeholder (T7) -----------------------
        // Same physical conventions as T5/T6: snake_case tables, PascalCase column identifiers,
        // no naming convention (the CHECK and index-filter literals double-quote the real
        // identifiers), CHECKs on frozen numeric scales only, no CHECK on vocabulary membership.

        b.Entity<BodyMetric>(e =>
        {
            e.ToTable("body_metrics");
            e.HasKey(x => x.Id);
            e.Property(x => x.Metric).IsRequired().HasMaxLength(24);
            e.Property(x => x.ValueEnc).IsRequired();
            // Same sentinel guard as the T6 defaulted columns: `= Sources.Default` is a named-const
            // reference, so EF infers no sentinel and an explicit null would be swallowed by the
            // DB default instead of hitting the NOT NULL constraint.
            e.Property(x => x.Source).IsRequired().HasMaxLength(16)
                .HasDefaultValue(BodyMetric.Sources.Default).ValueGeneratedNever();
            // §G9 FILTERED — the ONE deliberate tombstone exception. D-02's baseline step must stay
            // re-submittable after a delete, so a tombstone frees the key instead of occupying it.
            // (cycle_tracking_pause_spans also has a partial unique index, but its predicate is
            // EndedOn — a domain lifecycle column, not a soft-delete marker — so a DB-level audit
            // correctly finds two filtered unique indexes while §G9's tombstone inventory stays at
            // exactly one.)
            e.HasIndex(x => new { x.UserId, x.Metric, x.MeasuredOn }).IsUnique()
                .HasFilter("\"DeletedAt\" IS NULL");
            e.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
            e.HasQueryFilter(x => x.DeletedAt == null);
        });

        b.Entity<UserInsightSnapshot>(e =>
        {
            // §G6 placeholder: zero rows, no read endpoint, nothing computed. The CHECK pins the
            // 0..100 percentage SHAPE of the C-09 data-completeness score (§D's `confidence`,
            // renamed) — no clinical threshold lives in this schema.
            e.ToTable("user_insight_snapshot", t => t.HasCheckConstraint(
                "ck_user_insight_snapshot_data_completeness_range",
                "\"DataCompleteness\" >= 0 AND \"DataCompleteness\" <= 100"));
            e.HasKey(x => x.UserId);
            e.Property(x => x.CurrentPhase).HasMaxLength(16);
            // MissingDataCardsEnc stays bytea (the CLR byte[] default) — NOT jsonb: §D:173 makes
            // every "Enc" column AES-GCM ciphertext, which cannot live in a jsonb column.
            e.Property(x => x.ComputedBy).IsRequired().HasMaxLength(24)
                .HasDefaultValue(UserInsightSnapshot.ComputedByValues.Placeholder).ValueGeneratedNever();
            e.HasOne<User>().WithOne().HasForeignKey<UserInsightSnapshot>(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            // No DeletedAt and no query filter: every column is derived output, not a user entry.
        });
    }
}
