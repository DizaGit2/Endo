using Hangfire;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK tests for two paths that are not exercised by the core <see cref="CryptoShredJobLiveTests"/>:
/// <list type="bullet">
///   <item>Concurrent execution of <see cref="CryptoShredJob"/> from two independent
///         <see cref="LumenDbContext"/> connections — proves the <c>claimed == 0</c> guard
///         at CryptoShredJob.cs lines 52-63 suppresses the second audit entry.</item>
///   <item>Real Hangfire enqueue→execute path — proves the
///         <see cref="Hangfire.AspNetCore.AspNetCoreJobActivator"/> DI-scope + Guid-argument
///         deserialisation work end-to-end with a live <see cref="BackgroundJobServer"/>.</item>
/// </list>
/// </summary>
[Trait("Category", "LiveStack")]
public class CryptoShredConcurrencyAndHangfireLiveTests
{
    // -------------------------------------------------------------------------
    // Test 1 — concurrent race: only ONE audit row, regardless of which caller
    // wins the atomic UPDATE … WHERE DeletedAt IS NULL claim.
    // -------------------------------------------------------------------------

    [Fact]
    public async Task Concurrent_shred_writes_exactly_one_audit_row()
    {
        var userId = Guid.NewGuid();

        // Seed: fresh non-tombstoned user + DEK so both callers start from a live row.
        await using var seed = TestFixtures.NewDb();
        seed.Users.Add(TestFixtures.NewUser(userId));
        await seed.SaveChangesAsync();

        await TestFixtures.ProvisionDekForTestAsync(seed, new VaultTransitKeyWrapper(TestFixtures.Vault()), userId);

        // Gate: both tasks wait here before executing so they truly race to the DB.
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        static async Task RunJob(Guid id, Task release)
        {
            // Each caller owns its own DbContext / connection — exactly how Hangfire spawns jobs.
            await using var db = TestFixtures.NewDb();
            var job = new CryptoShredJob(db, TimeProvider.System, NullLogger<CryptoShredJob>.Instance);
            await release; // synchronise before touching the DB
            await job.ExecuteAsync(id);
        }

        try
        {
            // Release both tasks at once; xUnit disables inter-test parallelism but intra-test
            // Task.WhenAll is fine.
            var t1 = RunJob(userId, gate.Task);
            var t2 = RunJob(userId, gate.Task);

            gate.SetResult(); // start both simultaneously
            await Task.WhenAll(t1, t2);

            // Assert against a fresh context — nothing served from any change tracker.
            await using var read = TestFixtures.NewDb();

            // DEK deleted.
            (await read.UserKeys.AsNoTracking().AnyAsync(k => k.UserId == userId)).ShouldBeFalse();

            // User tombstoned.
            var user = await read.Users.IgnoreQueryFilters().AsNoTracking().SingleAsync(u => u.Id == userId);
            user.DeletedAt.ShouldNotBeNull();

            // EXACTLY ONE audit row — the claimed==0 branch silenced the loser.
            var count = await read.AdminAuditLogs.AsNoTracking()
                .CountAsync(l => l.EntityId == userId.ToString() && l.Action == AdminAuditLog.Actions.CryptoShred);
            count.ShouldBe(1, "concurrent shred must produce exactly one audit row regardless of which task wins");
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }

    // -------------------------------------------------------------------------
    // Test 2 — real Hangfire enqueue → execute: DI activator + Guid deserialisation
    // -------------------------------------------------------------------------

    /// <summary>
    /// <see cref="LumenApiFactory"/> forces <c>Hangfire:EnableServer=false</c> so tests are
    /// deterministic. This variant keeps the default (<c>true</c>) so a real
    /// <see cref="BackgroundJobServer"/> starts and processes enqueued jobs.
    /// </summary>
    private sealed class HangfireServerFactory : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder) =>
            builder.ConfigureAppConfiguration((_, cfg) =>
                // Do NOT override Hangfire:EnableServer — let it default to true so the
                // background server starts. Keep Development environment for dev secrets.
                cfg.AddInMemoryCollection(new Dictionary<string, string?>()));
    }

    [Fact]
    public async Task Hangfire_enqueue_executes_shred_job_end_to_end()
    {
        var userId = Guid.NewGuid();

        await using var appFactory = new HangfireServerFactory();

        // Seed: user + DEK via a raw DbContext (faster than going through the API).
        await using var seed = TestFixtures.NewDb();
        seed.Users.Add(TestFixtures.NewUser(userId));
        await seed.SaveChangesAsync();

        await TestFixtures.ProvisionDekForTestAsync(seed, new VaultTransitKeyWrapper(TestFixtures.Vault()), userId);

        try
        {
            // Resolve the IBackgroundJobClient from the live application — this exercises the
            // AspNetCoreJobActivator scope + Guid-arg JSON round-trip through Hangfire.
            var jobClient = appFactory.Services.GetRequiredService<IBackgroundJobClient>();
            jobClient.Enqueue<CryptoShredJob>(j => j.ExecuteAsync(userId, CancellationToken.None));

            // Poll (bounded: up to 15 s in 300 ms increments) until the shred completes.
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            bool deleted;
            do
            {
                await Task.Delay(300, cts.Token);
                await using var poll = TestFixtures.NewDb();
                var u = await poll.Users.IgnoreQueryFilters().AsNoTracking()
                    .FirstOrDefaultAsync(u => u.Id == userId, cts.Token);
                deleted = u?.DeletedAt is not null;
            }
            while (!deleted && !cts.IsCancellationRequested);

            cts.Token.ThrowIfCancellationRequested(); // timed out — job never ran

            // Verify the full shred outcome.
            await using var read = TestFixtures.NewDb();

            (await read.UserKeys.AsNoTracking().AnyAsync(k => k.UserId == userId))
                .ShouldBeFalse("DEK must be deleted after Hangfire shred");

            var user = await read.Users.IgnoreQueryFilters().AsNoTracking().SingleAsync(u => u.Id == userId);
            user.DeletedAt.ShouldNotBeNull("user must be tombstoned after Hangfire shred");

            var auditCount = await read.AdminAuditLogs.AsNoTracking()
                .CountAsync(l => l.EntityId == userId.ToString() && l.Action == AdminAuditLog.Actions.CryptoShred);
            auditCount.ShouldBe(1, "Hangfire shred must write exactly one audit row");
        }
        finally
        {
            await CleanupAsync(userId);
        }
    }

    // -------------------------------------------------------------------------
    // Shared cleanup
    // -------------------------------------------------------------------------

    private static async Task CleanupAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
