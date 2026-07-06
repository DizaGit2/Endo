using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for the <c>user_devices</c> and <c>admin_audit_log</c> tables
/// added in P2. Require the dev compose stack up (Postgres :55432).
/// </summary>
[Trait("Category", "LiveStack")]
public class UserDevicesAuditLogLiveTests
{
    [Fact]
    public async Task Tables_exist_in_live_postgres()
    {
        await using var db = TestFixtures.NewDb();
        // Throws if the tables are absent — proves the migration was applied to the live stack.
        var deviceCount = await db.UserDevices.AsNoTracking().CountAsync();
        var logCount = await db.AdminAuditLogs.AsNoTracking().CountAsync();
        deviceCount.ShouldBeGreaterThanOrEqualTo(0);
        logCount.ShouldBeGreaterThanOrEqualTo(0);
    }

    [Fact]
    public async Task Can_insert_and_read_back_UserDevice_and_AdminAuditLog()
    {
        var userId = Guid.NewGuid();
        await using var db = TestFixtures.NewDb();
        try
        {
            // Need a parent User for the UserDevice FK.
            db.Users.Add(TestFixtures.NewUser(userId));
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
                Action = AdminAuditLog.Actions.CryptoShred,
                EntityType = AdminAuditLog.EntityTypes.User,
                EntityId = userId.ToString(),
                BeforeJson = null,
                AfterJson = """{"shredded":true}""",
                At = DateTimeOffset.UtcNow,
            };
            db.AdminAuditLogs.Add(log);
            await db.SaveChangesAsync();

            await using var read = TestFixtures.NewDb();
            var deviceBack = await read.UserDevices.AsNoTracking().SingleAsync(d => d.Id == device.Id);
            deviceBack.Platform.ShouldBe("ios");
            deviceBack.UserId.ShouldBe(userId);

            var logBack = await read.AdminAuditLogs.AsNoTracking().SingleAsync(l => l.Id == log.Id);
            logBack.ActorId.ShouldBeNull();
            logBack.Action.ShouldBe(AdminAuditLog.Actions.CryptoShred);
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
        await using var db = TestFixtures.NewDb();
        try
        {
            db.Users.Add(TestFixtures.NewUser(userId));
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
        await using var db = TestFixtures.NewDb();
        try
        {
            db.AdminAuditLogs.Add(new AdminAuditLog
            {
                Id = logId,
                ActorId = null,
                Action = AdminAuditLog.Actions.SystemJob,
                EntityType = AdminAuditLog.EntityTypes.UserKey,
                EntityId = Guid.NewGuid().ToString(),
                At = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();

            await using var read = TestFixtures.NewDb();
            var back = await read.AdminAuditLogs.AsNoTracking().SingleAsync(l => l.Id == logId);
            back.ActorId.ShouldBeNull();
            back.Action.ShouldBe(AdminAuditLog.Actions.SystemJob);
        }
        finally
        {
            await db.AdminAuditLogs.Where(l => l.Id == logId).ExecuteDeleteAsync();
        }
    }
}
