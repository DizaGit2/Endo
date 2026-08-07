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
            e.Property(x => x.PushToken).IsRequired().HasMaxLength(512);
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
    }
}
