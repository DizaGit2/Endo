using System.Linq;
using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK proof that the three P4a migrations have actually been applied to the real Postgres:
/// every one of the <b>eleven</b> new tables is present and queryable under the exact physical name
/// the EF model maps it to.
///
/// <para>This exists because <c>ModelSyncTests</c> passes with no database attached — it compares the
/// model to the migration snapshot, not to a server — so an unapplied, half-applied or renamed
/// migration otherwise surfaces only as an opaque failure much later. For
/// <c>user_insight_snapshot</c> it is stronger still: §G6 gives that table no endpoint and no
/// writer at all, so <b>this is the only test in the suite that proves it exists</b>.</para>
///
/// <para>Each table name is read from the model rather than typed here, so a stray
/// <c>ToTable</c> rename fails as a missing relation instead of passing against a hard-coded string
/// the model no longer uses.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class SchemaSmokeLiveTests
{
    /// <summary>
    /// The eleven tables created by T5 (four), T6 (five) and T7 (two) — §G4's complete migration
    /// set, and the list T8's erasure path is keyed to.
    /// </summary>
    public static TheoryData<Type> P4aTables =>
    [
        // T5 — observation tables
        typeof(CycleEvent), typeof(CycleDayLog), typeof(Symptom), typeof(CyclePhaseOverride),
        // T6 — settings & preferences
        typeof(UserCycleSettings), typeof(CycleTrackingPauseSpan),
        typeof(UserGoal), typeof(UserHormonePref), typeof(UserNotificationPref),
        // T7 — body metrics & the insight-snapshot placeholder
        typeof(BodyMetric), typeof(UserInsightSnapshot),
    ];

    /// <summary>
    /// The eleven P4a table names, verbatim, independent of the CLR-typed <see cref="P4aTables"/>
    /// list above. Deliberately literal (not derived from the model) so that this file's live
    /// guards do not share a blind spot with the theory data they are cross-checking.
    /// </summary>
    private static readonly string[] ExpectedP4aTableNames =
    [
        "cycle_events", "cycle_day_logs", "symptoms", "cycle_phase_overrides",
        "user_cycle_settings", "cycle_tracking_pause_spans", "user_goals",
        "user_hormone_prefs", "user_notification_prefs",
        "body_metrics", "user_insight_snapshot",
    ];

    /// <summary>
    /// Every non-P4a table that legitimately predates this phase. Anything live or modelled outside
    /// this set union <see cref="ExpectedP4aTableNames"/> is, by definition, undocumented P4a scope.
    /// </summary>
    private static readonly string[] PreExistingNonP4aTableNames =
    [
        "users", "user_keys", "user_profile_enc", "user_devices",
        "consent_records", "admin_audit_log",
    ];

    /// <summary>
    /// Message shared by the two guards below so a future contributor sees the same instructions
    /// regardless of which one trips first.
    /// </summary>
    private const string G4Guidance =
        "§G4 caps P4a at exactly three migrations (T5, T6, T7), creating exactly eleven tables on top " +
        "of the six pre-existing ones and the migration history table (18 total live relations). " +
        "T8's crypto-shred erasure list is keyed to exactly that eleven-table set: a table that exists " +
        "here without also being added to T8's erasure list becomes health data that survives account " +
        "deletion. If this assertion now fails because a fourth migration was legitimately added " +
        "(re-planned past §G4), update, together, in the same commit: T8's erasure list, " +
        "ExpectedP4aTableNames/P4aTables in this file, and the expected counts below.";

    private static string TableNameOf(Type clr)
    {
        using var db = TestFixtures.NewDb();
        return db.Model.FindEntityType(clr).ShouldNotBeNull().GetTableName().ShouldNotBeNull();
    }

    private static async Task<long> CountRowsAsync(string table)
    {
        await using var db = TestFixtures.NewDb();
        // A count is the cheapest statement that still forces the planner to resolve the relation:
        // a missing or misnamed table raises 42P01 and fails the test with the name in the message.
        // Scalar SQL queries require the projected column to be named "Value" (EF Core 8+).
        //
        // EF1002 (raw interpolation) is suppressed deliberately: a relation NAME cannot be a query
        // parameter in any provider, and this one comes from the compiled EF model — never from a
        // request, a file or a database value — so there is no injection surface to protect.
#pragma warning disable EF1002
        return await db.Database
            .SqlQueryRaw<long>($"SELECT count(*) AS \"Value\" FROM \"{table}\"")
            .SingleAsync();
#pragma warning restore EF1002
    }

    [Theory]
    [MemberData(nameof(P4aTables))]
    public async Task Every_P4a_table_exists_and_is_queryable_in_the_live_database(Type entity)
    {
        var table = TableNameOf(entity);
        var rows = await CountRowsAsync(table);
        rows.ShouldBeGreaterThanOrEqualTo(0, $"\"{table}\" must exist in the live database");
    }

    [Fact]
    public void The_eleven_expected_tables_are_the_complete_P4a_set() =>
        // NOTE: this pins only the cardinality of the hardcoded `P4aTables` list above. It touches no
        // database and would stay green even if a fourth migration added a twelfth table, as long as
        // nobody remembered to grow this list too. The actual tripwires — the ones that compare
        // against the live Postgres catalog and the applied migration count, and so cannot be
        // satisfied by silence — are the two LIVE facts below.
        P4aTables.Count.ShouldBe(11);

    /// <summary>
    /// Pins the migration count itself. <see cref="Microsoft.EntityFrameworkCore.Storage.IMigrationsAssembly"/>
    /// (via <c>Database.GetMigrations()</c>) enumerates the migrations compiled into the assembly, so
    /// this catches a fourth migration the moment it is added, independent of whether it changed the
    /// table set at all (e.g. an index-only or column-only migration would still slip past the table-set
    /// guard below).
    /// </summary>
    [Fact]
    public void The_migration_count_is_pinned_at_eight()
    {
        using var db = TestFixtures.NewDb();
        db.Database.GetMigrations().Count().ShouldBe(8,
            "Expected exactly 8 migrations: the 5 pre-P4a migrations (InitialSpine, " +
            "SchemaHardeningFksMaxLengths, ConsentFkRestrict, AddUserDevicesAndAuditLog, " +
            "AddAdminAuditLogEntityIndex) plus P4a's three (T5 AddCycleAndSymptomTables, T6 " +
            "AddCycleSettingsPauseSpansAndPreferences, T7 AddProfileConditionsBodyMetricsAndInsightSnapshot). " +
            G4Guidance);
    }

    /// <summary>
    /// Pins the actual table set against reality: the tables the compiled EF model maps, and the
    /// tables that physically exist in the live Postgres <c>public</c> schema, must both equal exactly
    /// the P4a eleven plus the six pre-existing tables — no more, no less. Unlike
    /// <see cref="The_eleven_expected_tables_are_the_complete_P4a_set"/>, this fails the instant a new
    /// entity/table exists in either the model or the database, whether or not anyone remembered to
    /// update the hardcoded lists in this file.
    /// </summary>
    [Fact]
    public async Task The_live_database_has_exactly_the_expected_tables_and_no_more()
    {
        await using var db = TestFixtures.NewDb();

        var modelTables = db.Model.GetEntityTypes()
            .Select(e => e.GetTableName())
            .Where(name => name is not null)
            .Cast<string>()
            .ToHashSet(StringComparer.Ordinal);

        // Same EF1002 rationale as CountRowsAsync above: this SQL has zero request-derived input.
#pragma warning disable EF1002
        var liveTables = (await db.Database
                .SqlQueryRaw<string>(
                    "SELECT tablename AS \"Value\" FROM pg_tables " +
                    "WHERE schemaname = 'public' AND tablename <> '__EFMigrationsHistory'")
                .ToListAsync())
            .ToHashSet(StringComparer.Ordinal);
#pragma warning restore EF1002

        var expectedAll = ExpectedP4aTableNames
            .Concat(PreExistingNonP4aTableNames)
            .ToHashSet(StringComparer.Ordinal);

        foreach (var table in ExpectedP4aTableNames)
        {
            modelTables.ShouldContain(table, $"the EF model no longer maps \"{table}\". {G4Guidance}");
            liveTables.ShouldContain(table, $"\"{table}\" does not exist in the live database. {G4Guidance}");
        }

        var unexpectedInModel = modelTables.Except(expectedAll).OrderBy(n => n, StringComparer.Ordinal).ToList();
        unexpectedInModel.ShouldBeEmpty(
            $"the EF model maps table(s) beyond the known P4a eleven and the six pre-existing tables: " +
            $"[{string.Join(", ", unexpectedInModel)}]. {G4Guidance}");

        var unexpectedLive = liveTables.Except(expectedAll).OrderBy(n => n, StringComparer.Ordinal).ToList();
        unexpectedLive.ShouldBeEmpty(
            $"the live database contains table(s) beyond the known P4a eleven and the six pre-existing " +
            $"tables: [{string.Join(", ", unexpectedLive)}]. {G4Guidance}");

        var modelOnly = modelTables.Except(liveTables).OrderBy(n => n, StringComparer.Ordinal).ToList();
        modelOnly.ShouldBeEmpty(
            $"table(s) the EF model maps but the live database does not contain (an unapplied migration?): " +
            $"[{string.Join(", ", modelOnly)}]");
    }

    [Fact]
    public async Task The_insight_snapshot_table_holds_zero_rows()
    {
        // §G6: `user_insight_snapshot` is a placeholder. P4a computes nothing, writes nothing and
        // exposes no read endpoint, so any row here would mean clinical output leaked into a phase
        // that has no phase engine.
        var rows = await CountRowsAsync(TableNameOf(typeof(UserInsightSnapshot)));
        rows.ShouldBe(0, "P4a inserts zero rows into user_insight_snapshot (§G6)");
    }
}
