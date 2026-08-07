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
        // §G4 allows three migrations and no more. A twelfth table here would mean T8's erasure
        // list — keyed to exactly this set — no longer covers the phase.
        P4aTables.Count.ShouldBe(11);

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
