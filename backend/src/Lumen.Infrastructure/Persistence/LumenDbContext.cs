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
    }
}
