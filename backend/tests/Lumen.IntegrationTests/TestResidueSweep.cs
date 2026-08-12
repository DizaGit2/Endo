using System.Net.Http.Json;
using System.Text.Json;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;

namespace Lumen.IntegrationTests;

/// <summary>
/// Reclaims the rows an <b>aborted</b> live-stack run leaves behind, in Postgres and in Keycloak.
///
/// <para><b>Why this exists.</b> Every live test cleans up in a <c>finally</c>, and nothing in the
/// suite leaks on a completed run. A <c>finally</c> cannot run when the test HOST dies, though — a
/// cancelled run, a killed debugger, a crashed runner — and by T19 eight orphan <c>users</c> rows had
/// accumulated in the dev database, each dragging a <c>user_keys</c>, <c>consent_records</c> and
/// <c>user_profile_enc</c> row with it. Keycloak was worse and did not need an abort at all:
/// <b>nothing has ever deleted a Keycloak user</b>, so the realm had grown to ~4,600 accounts, one per
/// onboarding test ever run. Neither is a correctness bug — every test scopes its assertions to its own
/// user id — but both make the dev stack progressively slower and hide real residue in noise.</para>
///
/// <para><b>The rule, and why it cannot delete something it should not.</b> A row is swept only if it
/// is BOTH:</para>
/// <list type="number">
/// <item><b>Test-shaped</b> — either its <c>consent_records</c> row carries
/// <see cref="TestPolicyVersion"/> (the literal only this suite posts to <c>/onboarding/start</c>; the
/// Flutter client sends <c>v1-draft</c> and production a real version), or its <c>EmailHash</c> starts
/// with <see cref="DirectInsertEmailHashPrefix"/> — the plaintext marker
/// <c>TestFixtures.NewUser</c>/<c>SecurityTestFixtures.NewUser</c> write, which no production path can
/// produce because a real hash is Vault ciphertext (<c>vault:v1:…</c>). Keycloak's half is narrower
/// still: only <c>@example.com</c>, an RFC 2606 reserved domain.</item>
/// <item><b>Older than <see cref="MinimumAge"/></b> — residue is by definition from an EARLIER run, so
/// the age floor makes the sweep safe under any concurrency. Without it a run starting while another
/// is in flight (the two live test assemblies are separate <c>dotnet test</c> invocations) would delete
/// the other's users mid-assertion.</item>
/// </list>
///
/// <para><b>Fail-soft, always.</b> This runs from the assembly's test-framework hook, which means it
/// also runs for the CI <c>openapi-contract</c> job — a docker-less run of the static contract tests.
/// A sweep that threw there would fail every test in the assembly for want of a database it never
/// needed, so every failure here is swallowed and reported to the diagnostic sink instead.</para>
/// </summary>
internal static class TestResidueSweep
{
    /// <summary>The <c>policyVersion</c> every live test posts to <c>/onboarding/start</c>.</summary>
    public const string TestPolicyVersion = "v1-test";

    /// <summary>The <c>EmailHash</c> prefix of a directly-inserted test user (never a real hash).</summary>
    public const string DirectInsertEmailHashPrefix = "hash-";

    /// <summary>The reserved (RFC 2606) domain every test email uses.</summary>
    public const string TestEmailDomain = "@example.com";

    /// <summary>
    /// How old residue must be before it is reclaimed. One hour comfortably exceeds a full live run
    /// while keeping the dev stack from accumulating more than a run's worth.
    /// </summary>
    public static readonly TimeSpan MinimumAge = TimeSpan.FromHours(1);

    /// <summary>
    /// Upper bound on Keycloak deletions per run, so a stack with a large backlog does not turn test
    /// startup into a multi-minute purge. A normal run creates a few dozen users, so the steady state
    /// is reclaimed in full and a backlog drains over a few runs.
    /// </summary>
    public const int MaxKeycloakDeletesPerRun = 500;

    private const string UserIdPropertyName = "UserId";
    /// <summary>
    /// The IPv4 literal, not <c>localhost</c> — the compose stack publishes Keycloak on
    /// <c>127.0.0.1:8080</c> only, so a resolver that tries <c>::1</c> first pays a ~2 s connect
    /// timeout per request (measured). At up to <see cref="MaxKeycloakDeletesPerRun"/> deletes that is
    /// the difference between a sub-second sweep and a quarter-hour one. Same choice
    /// <c>TestFixtures.Vault()</c> already makes.
    /// </summary>
    private const string KeycloakBaseUrl = "http://127.0.0.1:8080";
    private const string Realm = "lumen";

    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static bool _swept;

    /// <summary>Runs the sweep at most once per process. Never throws.</summary>
    public static async Task RunOnceAsync(Action<string> report, CancellationToken ct = default)
    {
        await Gate.WaitAsync(ct);
        try
        {
            if (_swept) return;
            _swept = true;

            var cutoff = DateTimeOffset.UtcNow - MinimumAge;

            try
            {
                var rows = await SweepDatabaseAsync(cutoff, ct);
                report($"residue sweep: {rows} orphan test user(s) reclaimed from Postgres");
            }
            catch (Exception ex)
            {
                report($"residue sweep: Postgres half skipped ({ex.GetType().Name}: {ex.Message})");
            }

            try
            {
                var accounts = await SweepKeycloakAsync(cutoff, ct);
                report($"residue sweep: {accounts} test account(s) reclaimed from Keycloak");
            }
            catch (Exception ex)
            {
                report($"residue sweep: Keycloak half skipped ({ex.GetType().Name}: {ex.Message})");
            }
        }
        finally
        {
            Gate.Release();
        }
    }

    /// <summary>
    /// Deletes every aged, test-shaped user and everything that belongs to it. Returns the number of
    /// <c>users</c> rows removed. Exposed (rather than private) so
    /// <c>TestResidueSweepLiveTests</c> can prove both halves of the rule on seeded fixtures.
    /// </summary>
    public static async Task<int> SweepDatabaseAsync(DateTimeOffset cutoff, CancellationToken ct = default)
    {
        await using var db = TestFixtures.NewDb();

        // IgnoreQueryFilters: a crypto-shred test that aborted mid-flight leaves a TOMBSTONED user,
        // which an ordinary read hides — exactly the residue hardest to notice.
        var residue = await db.Users.IgnoreQueryFilters()
            .Where(u => u.CreatedAt < cutoff)
            .Where(u => u.EmailHash.StartsWith(DirectInsertEmailHashPrefix)
                        || db.ConsentRecords.Any(c => c.UserId == u.Id && c.PolicyVersion == TestPolicyVersion))
            .Select(u => u.Id)
            .ToListAsync(ct);

        if (residue.Count == 0) return 0;

        // Dependents are derived from the COMPILED EF MODEL — every entity type carrying a `UserId` —
        // rather than typed out. A hand list is the failure mode this sweep is cleaning up after: it
        // silently stops covering the table a later phase adds, and the residue comes straight back.
        // (Same model walk GdprErasureBaselineTests uses to keep CryptoShredJob's erasure list honest.)
        foreach (var entityType in db.Model.GetEntityTypes()
                     .Where(et => et.ClrType != typeof(User))
                     .Where(et => et.FindProperty(UserIdPropertyName) is not null)
                     .OrderBy(et => et.GetTableName(), StringComparer.Ordinal))
        {
            await DeleteByUserIdAsync(db, entityType, residue, ct);
        }

        // The audit log has no FK to users (it must survive erasure) and keys the user by string id.
        var ids = residue.Select(id => id.ToString()).ToList();
        await db.AdminAuditLogs.Where(l => ids.Contains(l.EntityId!)).ExecuteDeleteAsync(ct);

        return await db.Users.IgnoreQueryFilters().Where(u => residue.Contains(u.Id)).ExecuteDeleteAsync(ct);
    }

    /// <summary>
    /// Raw DELETE against one user-owned table. Relation and column names come from the compiled model
    /// (never from input), so a <c>ToTable</c>/column rename surfaces as a missing relation instead of
    /// a silent no-op; the ids are real parameters. Raw SQL rather than LINQ because the table set is
    /// discovered at runtime and there is no <c>DbSet</c> to name.
    /// </summary>
    private static async Task DeleteByUserIdAsync(
        LumenDbContext db,
        IEntityType entityType,
        List<Guid> userIds,
        CancellationToken ct)
    {
        var table = entityType.GetTableName();
        if (table is null) return; // owned/keyless types map into their owner's table

        var schema = entityType.GetSchema();
        var store = StoreObjectIdentifier.Table(table, schema);
        var column = entityType.FindProperty(UserIdPropertyName)!.GetColumnName(store);
        if (column is null) return;

        var relation = schema is null ? $"\"{table}\"" : $"\"{schema}\".\"{table}\"";

#pragma warning disable EF1002 // identifiers come from the compiled model; the ids are parameterized
        await db.Database.ExecuteSqlRawAsync(
            $"DELETE FROM {relation} WHERE \"{column}\" = ANY({{0}})", [userIds.ToArray()], ct);
#pragma warning restore EF1002
    }

    /// <summary>
    /// Deletes aged <c>@example.com</c> accounts from the <c>lumen</c> realm. Returns the number
    /// removed. Nothing else has ever deleted these, so without this the realm grows without bound.
    /// </summary>
    private static async Task<int> SweepKeycloakAsync(DateTimeOffset cutoff, CancellationToken ct)
    {
        using var http = new HttpClient { BaseAddress = new Uri(KeycloakBaseUrl), Timeout = TimeSpan.FromSeconds(30) };

        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "password",
            ["client_id"] = "admin-cli",
            ["username"] = "admin",
            ["password"] = "admin",
        });

        using var tokenResponse = await http.PostAsync("/realms/master/protocol/openid-connect/token", form, ct);
        tokenResponse.EnsureSuccessStatusCode();
        var token = (await tokenResponse.Content.ReadFromJsonAsync<JsonElement>(ct))
            .GetProperty("access_token").GetString();

        http.DefaultRequestHeaders.Authorization = new("Bearer", token);

        // The leading '*' is load-bearing and was measured, not assumed: Keycloak's `search` is a
        // PREFIX match per field, so `search=@example.com` returns zero rows and the sweep would
        // silently reclaim nothing forever. `search=*@example.com` returns the infix matches. The
        // suffix re-check below is deliberate belt-and-braces — `search` also matches first/last name,
        // so a wildcard hit is a candidate, never a decision.
        var candidates = await http.GetFromJsonAsync<JsonElement>(
            $"/admin/realms/{Realm}/users?max={MaxKeycloakDeletesPerRun}" +
            $"&search={Uri.EscapeDataString("*" + TestEmailDomain)}",
            ct);

        var cutoffMs = cutoff.ToUnixTimeMilliseconds();
        var deleted = 0;

        foreach (var account in candidates.EnumerateArray())
        {
            var username = account.TryGetProperty("username", out var u) ? u.GetString() : null;
            if (username is null || !username.EndsWith(TestEmailDomain, StringComparison.OrdinalIgnoreCase)) continue;

            // No createdTimestamp means an account older than Keycloak started recording them; treat it
            // as aged rather than skipping it forever.
            if (account.TryGetProperty("createdTimestamp", out var created) &&
                created.TryGetInt64(out var createdMs) &&
                createdMs >= cutoffMs)
            {
                continue;
            }

            using var delete = await http.DeleteAsync($"/admin/realms/{Realm}/users/{account.GetProperty("id").GetString()}", ct);
            if (delete.IsSuccessStatusCode) deleted++;
        }

        return deleted;
    }
}
