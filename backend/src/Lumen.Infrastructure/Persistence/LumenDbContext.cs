using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Lumen.Infrastructure.Persistence;

public class LumenDbContext(DbContextOptions<LumenDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<UserKey> UserKeys => Set<UserKey>();
    public DbSet<UserProfileEnc> UserProfiles => Set<UserProfileEnc>();
    public DbSet<ConsentRecord> ConsentRecords => Set<ConsentRecord>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>(e =>
        {
            e.ToTable("users");
            e.HasKey(x => x.Id);
            e.Property(x => x.EmailHash).IsRequired();
            e.HasIndex(x => x.EmailHash).IsUnique();
            e.Property(x => x.Locale).IsRequired();
            e.Property(x => x.Timezone).IsRequired();
        });

        b.Entity<UserKey>(e =>
        {
            e.ToTable("user_keys");
            e.HasKey(x => x.UserId);
            e.Property(x => x.WrappedDek).IsRequired();
            e.Property(x => x.VaultKeyName).IsRequired();
        });

        b.Entity<UserProfileEnc>(e =>
        {
            e.ToTable("user_profile_enc");
            e.HasKey(x => x.UserId);
        });

        b.Entity<ConsentRecord>(e =>
        {
            e.ToTable("consent_records");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.UserId);
            e.Property(x => x.PolicyVersion).IsRequired();
        });
    }
}
