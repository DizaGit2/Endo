using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for the <c>user_devices</c> and <c>admin_audit_log</c> tables
/// added in P3a. Require the dev compose stack up (Postgres :55432).
/// </summary>
[Trait("Category", "LiveStack")]
public class UserDevicesAuditLogLiveTests
{
    private const string Db = "Host=localhost;Port=55432;Database=lumen;Username=postgres;Password=postgres";
    private static LumenDbContext NewDb() => new(new DbContextOptionsBuilder<LumenDbContext>().UseNpgsql(Db).Options);

    private static User NewUser(Guid id) => new()
    {
        Id = id,
        EmailHash = "hash-" + id.ToString("N"),
        Locale = "es-ES",
        Timezone = "Europe/Madrid",
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow,
    };

    [Fact]
    public async Task No_pending_model_changes_after_migration()
    {
        await using var db = NewDb();
        // HasPendingModelChanges() checks that the EF model matches the applied migration snapshot.
        db.Database.HasPendingModelChanges().ShouldBeFalse();
        await Task.CompletedTask; // keep async signature consistent with other tests
    }

    [Fact]
    public async Task Can_insert_and_read_back_UserDevice_and_AdminAuditLog()
    {
        var userId = Guid.NewGuid();
        await using var db = NewDb();
        try
        {
            // Need a parent User for the UserDevice FK.
            db.Users.Add(NewUser(userId));
            await db.SaveChangesAsync();

            var device = new UserDevice
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Platform = "ios",
                PushToken = "tok-" + Guid.NewGuid().ToString("N"),
                LastSeenAt = DateTimeOffset.UtcNow,
                CreatedAt = DateTimeOffset.UtcNow,
            };
            db.UserDevices.Add(device);
            await db.SaveChangesAsync();

            var log = new AdminAuditLog
            {
                Id = Guid.NewGuid(),
                ActorId = null,             // system actor — no FK to User
                Action = "crypto_shred",
                EntityType = "User",
                EntityId = userId.ToString(),
                BeforeJson = null,
                AfterJson = """{"shredded":true}""",
                At = DateTimeOffset.UtcNow,
            };
            db.AdminAuditLogs.Add(log);
            await db.SaveChangesAsync();

            await using var read = NewDb();
            var deviceBack = await read.UserDevices.AsNoTracking().SingleAsync(d => d.Id == device.Id);
            deviceBack.Platform.ShouldBe("ios");
            deviceBack.UserId.ShouldBe(userId);

            var logBack = await read.AdminAuditLogs.AsNoTracking().SingleAsync(l => l.Id == log.Id);
            logBack.ActorId.ShouldBeNull();
            logBack.Action.ShouldBe("crypto_shred");
            logBack.AfterJson.ShouldNotBeNull();
            logBack.AfterJson!.ShouldContain("shredded");
        }
        finally
        {
            await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
            await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
            await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
        }
    }

    [Fact]
    public async Task Unique_index_on_UserId_PushToken_is_enforced()
    {
        var userId = Guid.NewGuid();
        var token = "dup-tok-" + Guid.NewGuid().ToString("N");
        await using var db = NewDb();
        try
        {
            db.Users.Add(NewUser(userId));
            await db.SaveChangesAsync();

            db.UserDevices.Add(new UserDevice
            {
                Id = Guid.NewGuid(), UserId = userId, Platform = "android",
                PushToken = token, CreatedAt = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();

            db.UserDevices.Add(new UserDevice
            {
                Id = Guid.NewGuid(), UserId = userId, Platform = "android",
                PushToken = token, CreatedAt = DateTimeOffset.UtcNow,
            });
            await Should.ThrowAsync<DbUpdateException>(async () => await db.SaveChangesAsync());
        }
        finally
        {
            await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
            await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
        }
    }

    [Fact]
    public async Task AdminAuditLog_null_actor_survives_round_trip()
    {
        var logId = Guid.NewGuid();
        await using var db = NewDb();
        try
        {
            db.AdminAuditLogs.Add(new AdminAuditLog
            {
                Id = logId,
                ActorId = null,
                Action = "system_job",
                EntityType = "UserKey",
                EntityId = Guid.NewGuid().ToString(),
                At = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();

            await using var read = NewDb();
            var back = await read.AdminAuditLogs.AsNoTracking().SingleAsync(l => l.Id == logId);
            back.ActorId.ShouldBeNull();
            back.Action.ShouldBe("system_job");
        }
        finally
        {
            await db.AdminAuditLogs.Where(l => l.Id == logId).ExecuteDeleteAsync();
        }
    }
}
