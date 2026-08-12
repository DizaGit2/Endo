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
/// <para><b>The UNATTENDED sweep is opt-in, and loud.</b>
/// <see cref="RunOnceAsync"/> — the whole-database, whole-realm pass the assembly's test-framework hook
/// starts — does nothing unless the run sets <see cref="EnableVariable"/><c>=1</c>. It used to run on
/// every <c>dotnet test</c> of this assembly — including a <c>--filter</c> run of a single test that
/// never opens a connection, and every IDE "run test" — and it reported only to xUnit's diagnostic
/// sink, which prints nothing without an <c>xunit.runner.json</c> this repo does not have. The
/// combination is what made it dangerous: on 2026-08-11 a filtered run of thirty pure in-memory tests
/// reclaimed 194 Keycloak accounts and printed not one line about it. Everything the unattended sweep
/// does now goes to the console as well as the sink, because a delete nobody can see is both how a
/// broken sweep survives (the prefix-search bug was found by hand, not by a test) and how a working one
/// surprises somebody.</para>
///
/// <para><b>"Opt-in" is a statement about <see cref="RunOnceAsync"/> ONLY — do not read it as a
/// property of this file.</b> <see cref="SweepDatabaseAsync"/> is public and
/// <c>TestResidueSweepLiveTests</c> calls it directly from plain <c>[Fact]</c>s, which run on every
/// ordinary integration-test invocation with the gate unset. Those calls carry none of the three
/// safeguards below, so their bound is a different one: they must name the ids they planted via
/// <c>restrictTo</c>, and the delete then cannot reach a row the test did not create. The coverage
/// added alongside the opt-in gate re-opened the very hole the gate had just closed — a whole-database
/// sweep on every ordinary run, silently — which is why the bound now lives in the signature instead
/// of in a convention.</para>
///
/// <para><b>The rule, and what each part of it is worth.</b> A row is swept only if it is BOTH:</para>
/// <list type="number">
/// <item><b>Test-shaped</b> — either its <c>consent_records</c> row carries
/// <see cref="TestPolicyVersion"/> (a CONVENTION: <c>policyVersion</c> is caller-controlled free text,
/// so this identifies rows this suite wrote but does not prove nothing else wrote them), or its
/// <c>EmailHash</c> starts with <see cref="DirectInsertEmailHashPrefix"/> — the plaintext marker
/// <c>TestFixtures.NewUser</c>/<c>SecurityTestFixtures.NewUser</c> write, which is a genuine INVARIANT,
/// because no production path can produce it: a real hash is Vault ciphertext (<c>vault:v1:…</c>).
/// Keycloak's half is narrower still: only the <c>@example.com</c> SUFFIX, an RFC 2606 reserved
/// domain.</item>
/// <item><b>Older than <see cref="MinimumAge"/></b> — residue is by definition from an EARLIER run, so
/// the age floor makes the sweep safe under any concurrency. Without it a run starting while another
/// is in flight (the two live test assemblies are separate <c>dotnet test</c> invocations) would delete
/// the other's users mid-assertion. Both halves evaluate it FAIL-CLOSED: an age that cannot be
/// established keeps the row.</item>
/// </list>
///
/// <para><b>And it must be the dev stack.</b> The endpoints below are hard-coded, which prevents a
/// reconfiguration but not a tunnel — an address is not an identity. So before either half of
/// <see cref="RunOnceAsync"/> runs, <see cref="EnsureDevStackAsync"/> proves positively that the realm
/// behind the address is the one <c>deploy/keycloak/realm-lumen.json</c> imports, and
/// <see cref="MaxPostgresDeletesPerRun"/> bounds the damage if the marker rule ever matches more than
/// it was written for. A DIRECT <see cref="SweepDatabaseAsync"/> caller gets neither the gate nor the
/// identity proof — <c>restrictTo</c> is what stands in for both.</para>
///
/// <para><b>Fail-soft, always.</b> An enabled sweep that cannot reach its stack must not fail the run
/// it is only tidying up for, so every failure here is swallowed and printed rather than thrown.</para>
/// </summary>
internal static class TestResidueSweep
{
    /// <summary>
    /// The <c>policyVersion</c> every live test posts to <c>/onboarding/start</c>.
    ///
    /// <para><b>A convention, not an invariant — do not over-trust it.</b> <c>policyVersion</c> is
    /// caller-controlled free text on <c>POST /onboarding/start</c>: nothing stops another client, or a
    /// stray script, from posting this literal, and if one did, its aged row would look like residue to
    /// the rule below. Contrast <see cref="DirectInsertEmailHashPrefix"/>, which production genuinely
    /// cannot produce because a real hash is Vault ciphertext. That asymmetry is why the marker rule is
    /// not the only thing standing between this sweep and a row it should not touch — the opt-in gate,
    /// the environment identity proof, the age floor and
    /// <see cref="MaxPostgresDeletesPerRun"/> all sit in front of it.</para>
    /// </summary>
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

    /// <summary>
    /// Blast-radius cap on the Postgres half: more candidates than this and the sweep REFUSES rather
    /// than deleting. A normal aborted run strands a handful of rows, so this is never reached in
    /// ordinary use — it exists because <see cref="TestPolicyVersion"/> is a convention rather than an
    /// invariant, so an unexpectedly large match means the rule is matching something it was not
    /// written for, and "delete more than I have ever deleted" is the wrong response to that surprise.
    /// </summary>
    public const int MaxPostgresDeletesPerRun = 200;

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

    /// <summary>
    /// The confidential client, and its committed dev-only secret, that
    /// <c>deploy/keycloak/realm-lumen.json</c> imports into the <c>lumen</c> realm. Used by
    /// <see cref="EnsureDevStackAsync"/> as positive proof of which realm is actually there — not as an
    /// authentication step; the deletes use the admin-cli token. Same literal
    /// <c>TestFixtures.ApiClientSecret</c> already carries.
    /// </summary>
    private const string DevRealmClientId = "api";

    /// <inheritdoc cref="DevRealmClientId"/>
    private const string DevRealmClientSecret = "dev-api-secret";

    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static bool _swept;

    /// <summary>
    /// Environment variable a run must set to <c>1</c> (or <c>true</c>) to opt into the sweep.
    /// </summary>
    public const string EnableVariable = "LUMEN_SWEEP_TEST_RESIDUE";

    /// <summary>
    /// Whether <paramref name="value"/> is an explicit opt-in. Deliberately narrow — only the two
    /// documented literals — because everything this gate protects is a delete.
    /// </summary>
    public static bool IsEnabled(string? value) =>
        value?.Trim() is { } v && (v == "1" || v.Equals("true", StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Whether one candidate account may be reclaimed. Pure, so the riskiest rule in this file can be
    /// proven without a Keycloak and without deleting anything (<c>TestResidueSweepRuleTests</c>).
    /// </summary>
    /// <param name="username">The account's username, or <c>null</c> if the representation omits it.</param>
    /// <param name="createdTimestampMs">Its creation instant, or <c>null</c> if it cannot be read.</param>
    /// <param name="cutoffMs">Accounts created before this instant are old enough to be residue.</param>
    public static bool IsReclaimableKeycloakAccount(string? username, long? createdTimestampMs, long cutoffMs)
    {
        if (username is null) return false;

        // A SUFFIX test, never Contains(): `search` matches infixes and also matches first/last name,
        // so `x@example.com.evil.net` is a candidate the perimeter has to reject.
        if (!username.EndsWith(TestEmailDomain, StringComparison.OrdinalIgnoreCase)) return false;

        // FAIL-CLOSED. An age we could not establish is not evidence of age: `null` here means the
        // representation had no readable createdTimestamp, and the only safe reading of "I do not know
        // how old this is" is "keep it". Deleting instead would make the age floor fail-OPEN — one
        // Keycloak serialization change (or a briefRepresentation that drops the field) and the floor
        // silently switches off for EVERY account at once, which is the single worst failure this file
        // has, because the floor is what makes the sweep safe against a concurrently running suite.
        // The Postgres half is fail-closed by construction (`u.CreatedAt < cutoff`, evaluated in SQL on
        // a NOT NULL column, matches nothing when it cannot compare); this half now matches it.
        if (createdTimestampMs is not { } created) return false;

        return created < cutoffMs;
    }

    /// <summary>
    /// Reads <c>createdTimestamp</c> off a user representation, or <c>null</c> when it is absent or is
    /// not something an <c>int64</c> can be read from. Never throws: a representation that serializes
    /// the field as a string, a double or an ISO instant must degrade to an UNKNOWN age (which
    /// <see cref="IsReclaimableKeycloakAccount"/> keeps), never to an exception and never to a zero.
    /// </summary>
    public static long? ReadCreatedTimestamp(JsonElement account) =>
        account.TryGetProperty("createdTimestamp", out var created)
        && created.ValueKind == JsonValueKind.Number
        && created.TryGetInt64(out var ms)
            ? ms
            : null;

    /// <summary>
    /// Runs the sweep at most once per process, and only if this run explicitly opted in. Never throws.
    /// </summary>
    /// <param name="report">
    /// One of three sinks the sweep announces itself on, and in practice xUnit's diagnostic message
    /// sink. Never the only one — see the comment on <c>Say</c> for why each is needed.
    /// </param>
    /// <param name="ct">Cancellation.</param>
    public static async Task RunOnceAsync(Action<string> report, CancellationToken ct = default)
    {
        await Gate.WaitAsync(ct);
        try
        {
            if (_swept) return;
            _swept = true;

            // THE OPT-IN GATE. Everything past this line deletes rows and accounts, so an ordinary
            // `dotnet test` — a --filter run of one unrelated test, an IDE's "run test", a CI job that
            // only wanted the static contract checks — must get past it without touching anything.
            if (!IsEnabled(Environment.GetEnvironmentVariable(EnableVariable))) return;

            // Say it THREE times, on purpose, because no single channel here is reliably visible:
            //
            //   * the console is what an IDE test pane and an interactive run show. Measured: the VSTest
            //     console logger swallows the test host's stdout AND stderr at its default (minimal)
            //     verbosity, so this one alone shows nothing on `dotnet test --nologo`.
            //   * `report` reaches xUnit's DiagnosticMessage sink. That sink printed NOTHING for the
            //     whole life of this sweep, because `diagnosticMessages` defaults to false and there was
            //     no xunit.runner.json in the repo — so every line it "reported" went nowhere. The file
            //     now exists (see the csproj); this channel prints from `verbosity=normal` up.
            //   * the log file survives the run regardless of any verbosity setting (see AppendToLog).
            //
            // A delete that leaves no trace is how a permanently broken sweep survives (the
            // prefix-search bug was found by hand, not by a test) and how a working one deletes 194
            // accounts during a filtered run of pure in-memory tests without anyone noticing.
            void Say(string line)
            {
                Console.WriteLine($"[residue-sweep] {line}");
                Console.Out.Flush();
                report(line);
                AppendToLog(line);
            }

            var cutoff = DateTimeOffset.UtcNow - MinimumAge;
            Say($"ENABLED by {EnableVariable} — reclaiming test residue created before {cutoff:u}");

            // The endpoints below are hard-coded, which stops a RECONFIGURATION but not a TUNNEL:
            // `kubectl port-forward svc/keycloak 8080:8080` or `ssh -L 55432:staging-db:5432` puts
            // something else entirely behind the same address, and an address is not an identity.
            // So prove the identity positively before deleting anything, and skip BOTH halves if the
            // proof fails — the two endpoints are one compose stack, and if that stack is not there,
            // there is nothing here worth reclaiming.
            try
            {
                await EnsureDevStackAsync(ct);
                Say($"environment identity confirmed: realm '{Realm}' accepted the compose stack's "
                    + $"sentinel '{DevRealmClientId}' client secret");
            }
            catch (Exception ex)
            {
                Say($"environment identity check FAILED ({ex.GetType().Name}: {ex.Message}) — "
                    + "NOTHING was swept");
                return;
            }

            try
            {
                // The ONE unrestricted call in the repo, and the three safeguards above are what buys
                // it: opted in, identity-proven, and announced on three channels.
                var rows = await SweepDatabaseAsync(cutoff, restrictTo: null, ct);
                Say($"{rows} orphan test user(s) reclaimed from Postgres");
            }
            catch (Exception ex)
            {
                Say($"Postgres half skipped ({ex.GetType().Name}: {ex.Message})");
            }

            try
            {
                var accounts = await SweepKeycloakAsync(cutoff, ct);
                Say($"{accounts} test account(s) reclaimed from Keycloak realm '{Realm}'");
            }
            catch (Exception ex)
            {
                Say($"Keycloak half skipped ({ex.GetType().Name}: {ex.Message})");
            }
        }
        finally
        {
            Gate.Release();
        }
    }

    /// <summary>
    /// Positive proof that the stack behind the hard-coded endpoints is THIS repo's dev stack: the
    /// <c>lumen</c> realm must accept the <c>api</c> client secret that
    /// <c>deploy/keycloak/realm-lumen.json</c> imports verbatim. The secret is a committed dev sentinel
    /// that exists nowhere else — any real environment injects its own via sops (<c>ARCHITECTURE.md
    /// §G</c>) — so a successful grant identifies the realm, where the address only located it.
    /// Throws if the proof fails.
    /// </summary>
    private static async Task EnsureDevStackAsync(CancellationToken ct)
    {
        using var http = NewKeycloakClient();
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "client_credentials",
            ["client_id"] = DevRealmClientId,
            ["client_secret"] = DevRealmClientSecret,
        });

        using var response = await http.PostAsync($"/realms/{Realm}/protocol/openid-connect/token", form, ct);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"the realm behind {KeycloakBaseUrl} rejected the dev stack's sentinel client secret "
                + $"(HTTP {(int)response.StatusCode}); whatever is listening there, it is not the realm "
                + "deploy/keycloak/realm-lumen.json imports");
        }
    }

    /// <summary>
    /// The third channel, and the only one that survives the run: append to
    /// <c>TestResults/residue-sweep.log</c> at the repo root (already gitignored). It exists because
    /// `dotnet test`'s console logger is MINIMAL by default and drops the test host's stdout, stderr
    /// and xUnit diagnostics alike (all three measured) — so on the canonical command the other two
    /// channels can still show nobody anything. A file cannot be swallowed by a verbosity setting, so
    /// after any sweep there is always something to read that says what was deleted.
    /// Never throws: a log that fails must not fail the run it is only annotating.
    /// </summary>
    private static void AppendToLog(string line)
    {
        try
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, ".git"))) dir = dir.Parent;
            if (dir is null) return;

            var results = Directory.CreateDirectory(Path.Combine(dir.FullName, "TestResults"));
            File.AppendAllText(
                Path.Combine(results.FullName, "residue-sweep.log"),
                $"{DateTimeOffset.UtcNow:u}  {line}{Environment.NewLine}");
        }
        catch
        {
            // Deliberately swallowed — see the summary.
        }
    }

    private static HttpClient NewKeycloakClient() =>
        new() { BaseAddress = new Uri(KeycloakBaseUrl), Timeout = TimeSpan.FromSeconds(30) };

    /// <summary>
    /// Deletes every aged, test-shaped user and everything that belongs to it. Returns the number of
    /// <c>users</c> rows removed. Exposed (rather than private) so
    /// <c>TestResidueSweepLiveTests</c> can prove both halves of the rule on seeded fixtures.
    /// </summary>
    /// <param name="cutoff">Rows created before this instant are old enough to be residue.</param>
    /// <param name="restrictTo">
    /// <b>The blast-radius bound, and every direct caller must supply one.</b> When non-null the sweep
    /// can delete only rows whose id appears here — an empty collection therefore deletes nothing,
    /// never "everything". Only <see cref="RunOnceAsync"/> passes <see langword="null"/>, and it earns
    /// that by carrying three safeguards this method has none of: the
    /// <see cref="EnableVariable"/> opt-in gate, <see cref="EnsureDevStackAsync"/>'s positive proof of
    /// WHICH stack is behind the hard-coded <c>localhost:55432</c>, and the three announcement channels.
    ///
    /// <para>This parameter exists because that asymmetry was invisible and cost real rows. The live
    /// tests call this method DIRECTLY, from plain <c>[Fact]</c>s, so on an ordinary <c>dotnet test</c>
    /// — no opt-in, no identity proof, nothing printed — an unrestricted call is a whole-database sweep
    /// with only <see cref="MaxPostgresDeletesPerRun"/> left standing. It was measured deleting an aged,
    /// rule-matching <c>users</c> row that no test had planted, along with every user-owned health row
    /// hanging off it. Naming the ids makes a delete the caller did not intend unreachable rather than
    /// unlikely, and it costs the tests nothing: the rule still decides about every row they plant.</para>
    /// </param>
    /// <param name="ct">Cancellation.</param>
    public static async Task<int> SweepDatabaseAsync(
        DateTimeOffset cutoff,
        IReadOnlyCollection<Guid>? restrictTo = null,
        CancellationToken ct = default)
    {
        // Empty means "no row is in scope". Checked before the connection is opened so the reading
        // cannot be confused with `null`, which is the one case that means "no restriction".
        if (restrictTo is { Count: 0 }) return 0;

        await using var db = TestFixtures.NewDb();

        // IgnoreQueryFilters: a crypto-shred test that aborted mid-flight leaves a TOMBSTONED user,
        // which an ordinary read hides — exactly the residue hardest to notice.
        var candidates = db.Users.IgnoreQueryFilters()
            .Where(u => u.CreatedAt < cutoff)
            .Where(u => u.EmailHash.StartsWith(DirectInsertEmailHashPrefix)
                        || db.ConsentRecords.Any(c => c.UserId == u.Id && c.PolicyVersion == TestPolicyVersion));

        if (restrictTo is not null)
        {
            // Applied as an EXTRA predicate rather than in place of the marker rule: a named id still
            // has to be aged and test-shaped to be swept, so this can only ever narrow the match.
            var named = restrictTo.ToArray();
            candidates = candidates.Where(u => named.Contains(u.Id));
        }

        var residue = await candidates.Select(u => u.Id).ToListAsync(ct);

        if (residue.Count == 0) return 0;

        if (residue.Count > MaxPostgresDeletesPerRun)
        {
            throw new InvalidOperationException(
                $"{residue.Count} candidate rows exceeds the {MaxPostgresDeletesPerRun}-row cap — "
                + "refusing to sweep. Either this is not the dev database, or the marker rule is "
                + "matching rows it was not written for; inspect them before raising the cap.");
        }

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
        using var http = NewKeycloakClient();

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
            if (!IsReclaimableKeycloakAccount(username, ReadCreatedTimestamp(account), cutoffMs)) continue;

            using var delete = await http.DeleteAsync($"/admin/realms/{Realm}/users/{account.GetProperty("id").GetString()}", ct);
            if (delete.IsSuccessStatusCode) deleted++;
        }

        return deleted;
    }
}
