using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Persistence;

/// <summary>
/// Schema-level guards for the T7 additions: <c>body_metrics</c> (the §G9 <b>filtered</b>
/// tombstone case — the only one), the non-clinical <c>user_insight_snapshot</c> placeholder,
/// the four encrypted condition columns on <c>user_profile_enc</c>, and the D-06 reserved
/// <c>users.unit_system</c> column.
///
/// Every rejection is asserted on <see cref="DbUpdateException"/> only — never on
/// <c>SqliteException</c>/<c>PostgresException</c>, whose type and message differ per provider
/// (T1 probe 3/4).
/// </summary>
public sealed class BodyMetricModelTests : IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _otherUserId = Guid.NewGuid();
    private static readonly DateTimeOffset Now = new(2026, 8, 6, 9, 30, 0, TimeSpan.Zero);
    private static readonly DateOnly Day = new(2026, 8, 6);

    // A value that is deliberately NOT a member of BodyMetric.Metrics: §G10/§D keep vocabulary
    // membership in code, so the database must accept it (proving there is no CHECK).
    private const string NotAMetric = "not_a_metric";

    public BodyMetricModelTests()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        using var db = NewContext();
        db.Database.EnsureCreated();
        db.Users.AddRange(NewUser(_userId, "a"), NewUser(_otherUserId, "b"));
        db.SaveChanges();
    }

    public void Dispose() => _connection.Dispose();

    private static User NewUser(Guid id, string tag) => new()
    {
        Id = id,
        EmailHash = $"vault:v1:body-metric-tests-{tag}",
        Locale = "es-ES",
        Timezone = "Europe/Madrid",
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    // A fresh context per attempt: a failed SaveChanges leaves the change tracker poisoned.
    private LumenDbContext NewContext() =>
        new(new DbContextOptionsBuilder<LumenDbContext>().UseSqlite(_connection).Options);

    private BodyMetric NewMetric(
        DateOnly measuredOn,
        string? metric = null,
        Guid? userId = null,
        DateTimeOffset? deletedAt = null) => new()
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? _userId,
            Metric = metric ?? BodyMetric.Metrics.WeightKg,
            ValueEnc = [1, 2, 3, 4],
            MeasuredAt = Now,
            MeasuredOn = measuredOn,
            CreatedAt = Now,
            UpdatedAt = Now,
            DeletedAt = deletedAt,
        };

    private UserInsightSnapshot NewSnapshot(Guid? userId = null) => new()
    {
        UserId = userId ?? _userId,
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    private void SaveAll(params object[] entities)
    {
        using var db = NewContext();
        db.AddRange(entities);
        db.SaveChanges();
    }

    private void SaveAllShouldThrow(params object[] entities)
    {
        using var db = NewContext();
        db.AddRange(entities);
        Should.Throw<DbUpdateException>(() => db.SaveChanges());
    }

    // --- body_metrics: the ONE §G9 filtered-tombstone case ---------------------------------

    [Fact]
    public void The_body_metric_unique_index_is_filtered_on_the_soft_delete_tombstone()
    {
        using var db = NewContext();
        var index = db.Model.FindEntityType(typeof(BodyMetric)).ShouldNotBeNull()
            .GetIndexes().Single(i => i.IsUnique);

        index.Properties.Select(p => p.Name).ShouldBe([
            nameof(BodyMetric.UserId), nameof(BodyMetric.Metric), nameof(BodyMetric.MeasuredOn),
        ]);
        index.GetFilter().ShouldBe("\"DeletedAt\" IS NULL");
    }

    [Fact]
    public void A_second_LIVE_weight_row_on_the_same_day_is_rejected() =>
        SaveAllShouldThrow(NewMetric(Day), NewMetric(Day));

    [Fact]
    public void A_new_weight_row_is_accepted_once_the_previous_one_is_tombstoned()
    {
        // §G9's one deliberate exception. Under the UNFILTERED regime the tombstone would keep
        // occupying the key and this insert would fail — which would make the D-02 baseline step
        // un-re-submittable after the user deletes their weight entry.
        var first = NewMetric(Day);
        SaveAll(first);

        using (var db = NewContext())
        {
            db.BodyMetrics.Single(x => x.Id == first.Id).DeletedAt = Now;
            db.SaveChanges();
        }

        SaveAll(NewMetric(Day));

        using var read = NewContext();
        read.BodyMetrics.Count(x => x.UserId == _userId).ShouldBe(1);
        read.BodyMetrics.IgnoreQueryFilters().Count(x => x.UserId == _userId).ShouldBe(2);
    }

    [Fact]
    public void Many_tombstoned_rows_may_coexist_with_one_live_row_on_the_same_day()
    {
        SaveAll(
            NewMetric(Day, deletedAt: Now),
            NewMetric(Day, deletedAt: Now.AddMinutes(1)),
            NewMetric(Day, deletedAt: Now.AddMinutes(2)));
        SaveAll(NewMetric(Day));

        using var read = NewContext();
        read.BodyMetrics.Count(x => x.UserId == _userId).ShouldBe(1);
        read.BodyMetrics.IgnoreQueryFilters().Count(x => x.UserId == _userId).ShouldBe(4);
    }

    [Fact]
    public void The_same_metric_on_different_days_is_allowed() =>
        SaveAll(NewMetric(Day), NewMetric(Day.AddDays(-1)), NewMetric(Day.AddDays(-2)));

    [Fact]
    public void Two_users_may_each_log_the_same_metric_on_the_same_day() =>
        SaveAll(NewMetric(Day), NewMetric(Day, userId: _otherUserId));

    [Fact]
    public void Different_metrics_on_the_same_day_are_allowed() =>
        SaveAll(NewMetric(Day), NewMetric(Day, metric: NotAMetric));

    [Fact]
    public void The_metric_column_carries_no_CHECK_on_vocabulary_membership() =>
        // §G10 / §D: enums are hard-coded in code, not in the DB — P5 adds members (D-15) without
        // a migration. The same holds for Source.
        SaveAll(NewMetric(Day, metric: NotAMetric));

    [Fact]
    public void Source_defaults_to_manual()
    {
        var metric = NewMetric(Day);
        SaveAll(metric);

        using var read = NewContext();
        read.BodyMetrics.Single(x => x.Id == metric.Id).Source.ShouldBe("manual");
    }

    [Fact]
    public void Source_declares_its_default_in_the_model()
    {
        using var db = NewContext();
        db.Model.FindEntityType(typeof(BodyMetric)).ShouldNotBeNull()
            .FindProperty(nameof(BodyMetric.Source)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe("manual");
    }

    [Fact]
    public void Source_null_is_not_swallowed_by_the_DB_default_and_the_NOT_NULL_constraint_still_rejects_it()
    {
        // The T6 sentinel trap. Source's CLR initializer is `= Sources.Default` — a reference to a
        // named const, not a literal — so EF Core 10 does NOT infer a value-generation sentinel
        // from it and falls back to the CLR default for a reference type: null. Without
        // ValueGeneratedNever(), an explicit Source = null would be indistinguishable from
        // "not set": EF would omit the column, the DB default ('manual') would fire silently, and
        // the column's own NOT NULL constraint would never see the caller's actual value.
        var metric = NewMetric(Day);
        metric.Source = null!;

        using var db = NewContext();
        db.Add(metric);
        Should.Throw<DbUpdateException>(() => db.SaveChanges());
    }

    [Fact]
    public void Body_metrics_is_soft_deletable_and_hidden_by_a_query_filter()
    {
        using var db = NewContext();
        var entity = db.Model.FindEntityType(typeof(BodyMetric)).ShouldNotBeNull();
        entity.FindProperty(nameof(BodyMetric.DeletedAt)).ShouldNotBeNull();
        entity.GetDeclaredQueryFilters().ShouldNotBeEmpty();
    }

    [Fact]
    public void Body_metric_rows_disappear_when_the_user_row_is_hard_deleted()
    {
        SaveAll(NewMetric(Day));

        using (var db = NewContext())
            db.Users.IgnoreQueryFilters().Where(x => x.Id == _userId).ExecuteDelete();

        using var read = NewContext();
        read.BodyMetrics.IgnoreQueryFilters().Count(x => x.UserId == _userId).ShouldBe(0);
    }

    // --- user_insight_snapshot: a placeholder that cannot be mistaken for clinical output ----

    private UserInsightSnapshot InsertSnapshotWithoutAnyDefaultedColumn()
    {
        using (var db = NewContext())
        {
            db.Database.ExecuteSqlInterpolated(
                $"""
                 INSERT INTO user_insight_snapshot ("UserId", "CreatedAt", "UpdatedAt")
                 VALUES ({_userId}, {Now}, {Now})
                 """);
        }

        using var read = NewContext();
        return read.UserInsightSnapshots.Single(x => x.UserId == _userId);
    }

    [Fact]
    public void ComputedBy_defaults_to_placeholder() =>
        // §G6: P4a computes nothing. The default is the schema saying so out loud.
        InsertSnapshotWithoutAnyDefaultedColumn().ComputedBy.ShouldBe("placeholder");

    [Fact]
    public void Every_other_snapshot_column_has_no_default_and_stays_null()
    {
        var row = InsertSnapshotWithoutAnyDefaultedColumn();
        row.CurrentPhase.ShouldBeNull();
        row.PhaseStart.ShouldBeNull();
        row.DataCompleteness.ShouldBeNull();
        row.MissingDataCardsEnc.ShouldBeNull();
        row.RefreshedAt.ShouldBeNull();
    }

    [Fact]
    public void ComputedBy_declares_its_default_in_the_model()
    {
        using var db = NewContext();
        db.Model.FindEntityType(typeof(UserInsightSnapshot)).ShouldNotBeNull()
            .FindProperty(nameof(UserInsightSnapshot.ComputedBy)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe("placeholder");
    }

    [Fact]
    public void ComputedBy_null_is_not_swallowed_by_the_DB_default_and_the_NOT_NULL_constraint_still_rejects_it()
    {
        // Same T6 sentinel trap as BodyMetric.Source: `= ComputedByValues.Placeholder` is a
        // named-const reference, so the sentinel stays null and ValueGeneratedNever() is what
        // makes an explicit null reach the database at all.
        var snapshot = NewSnapshot();
        snapshot.ComputedBy = null!;

        using var db = NewContext();
        db.Add(snapshot);
        Should.Throw<DbUpdateException>(() => db.SaveChanges());
    }

    [Fact]
    public void A_snapshot_created_through_EF_carries_the_placeholder_marker()
    {
        SaveAll(NewSnapshot());

        using var read = NewContext();
        read.UserInsightSnapshots.Single(x => x.UserId == _userId).ComputedBy.ShouldBe("placeholder");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(50)]
    [InlineData(99)]
    [InlineData(100)]
    public void DataCompleteness_accepts_the_whole_zero_to_hundred_scale(short score)
    {
        var snapshot = NewSnapshot();
        snapshot.DataCompleteness = score;
        SaveAll(snapshot);
    }

    [Theory]
    [InlineData(101)]
    [InlineData(-1)]
    [InlineData(short.MaxValue)]
    public void DataCompleteness_rejects_anything_outside_zero_to_hundred(short score)
    {
        // C-09 renamed §D's `confidence` to the data-completeness score; the CHECK pins the
        // percentage SHAPE only. P4a computes no score at all (§G6).
        var snapshot = NewSnapshot();
        snapshot.DataCompleteness = score;
        SaveAllShouldThrow(snapshot);
    }

    [Fact]
    public void DataCompleteness_accepts_null_because_nothing_computes_it_in_P4a() =>
        SaveAll(NewSnapshot());

    [Fact]
    public void CurrentPhase_carries_no_CHECK_on_vocabulary_membership()
    {
        var snapshot = NewSnapshot();
        snapshot.CurrentPhase = "not_a_phase";
        SaveAll(snapshot);
    }

    [Fact]
    public void MissingDataCards_is_a_bytea_column_not_jsonb()
    {
        // §D:173 — "'Enc' columns are bytea, encrypted with the per-user DEK". AES-GCM ciphertext
        // cannot live in jsonb; §D:219's `jsonb` predates the encryption rule and is corrected.
        using var db = NewContext();
        db.Model.FindEntityType(typeof(UserInsightSnapshot)).ShouldNotBeNull()
            .FindProperty(nameof(UserInsightSnapshot.MissingDataCardsEnc)).ShouldNotBeNull()
            .ClrType.ShouldBe(typeof(byte[]));
    }

    [Fact]
    public void The_snapshot_is_keyed_one_to_one_on_UserId()
    {
        using var db = NewContext();
        db.Model.FindEntityType(typeof(UserInsightSnapshot)).ShouldNotBeNull()
            .FindPrimaryKey().ShouldNotBeNull()
            .Properties.Select(p => p.Name).ShouldBe([nameof(UserInsightSnapshot.UserId)]);
    }

    [Fact]
    public void A_second_snapshot_row_for_the_same_user_is_impossible()
    {
        SaveAll(NewSnapshot());
        SaveAllShouldThrow(NewSnapshot());
    }

    [Fact]
    public void The_snapshot_has_no_DeletedAt_because_it_is_a_derived_per_user_singleton()
    {
        using var db = NewContext();
        var entity = db.Model.FindEntityType(typeof(UserInsightSnapshot)).ShouldNotBeNull();
        entity.FindProperty("DeletedAt").ShouldBeNull();
        entity.GetDeclaredQueryFilters().ShouldBeEmpty();
    }

    [Fact]
    public void Snapshot_rows_disappear_when_the_user_row_is_hard_deleted()
    {
        SaveAll(NewSnapshot());

        using (var db = NewContext())
            db.Users.IgnoreQueryFilters().Where(x => x.Id == _userId).ExecuteDelete();

        using var read = NewContext();
        read.UserInsightSnapshots.Count(x => x.UserId == _userId).ShouldBe(0);
    }

    // --- users.unit_system: the D-06 reserved column ----------------------------------------

    private User InsertUserWithoutUnitSystem(Guid id)
    {
        using (var db = NewContext())
        {
            db.Database.ExecuteSqlInterpolated(
                $"""
                 INSERT INTO users ("Id", "EmailHash", "Locale", "Timezone", "CreatedAt", "UpdatedAt")
                 VALUES ({id}, {"vault:v1:body-metric-tests-raw"}, {"es-ES"}, {"Europe/Madrid"}, {Now}, {Now})
                 """);
        }

        using var read = NewContext();
        return read.Users.Single(x => x.Id == id);
    }

    [Fact]
    public void UnitSystem_defaults_to_metric() =>
        InsertUserWithoutUnitSystem(Guid.NewGuid()).UnitSystem.ShouldBe("metric");

    [Fact]
    public void UnitSystem_declares_its_default_in_the_model()
    {
        using var db = NewContext();
        db.Model.FindEntityType(typeof(User)).ShouldNotBeNull()
            .FindProperty(nameof(User.UnitSystem)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe("metric");
    }

    [Fact]
    public void UnitSystem_null_is_not_swallowed_by_the_DB_default_and_the_NOT_NULL_constraint_still_rejects_it()
    {
        // The third instance of the T6 sentinel trap: `= UnitSystems.Default` is a named-const
        // reference, so without ValueGeneratedNever() an explicit null would be dropped from the
        // INSERT and silently replaced by 'metric'.
        var user = NewUser(Guid.NewGuid(), "unit-system");
        user.UnitSystem = null!;

        using var db = NewContext();
        db.Add(user);
        Should.Throw<DbUpdateException>(() => db.SaveChanges());
    }

    [Fact]
    public void A_user_created_through_EF_carries_the_metric_unit_system()
    {
        using var read = NewContext();
        read.Users.Single(x => x.Id == _userId).UnitSystem.ShouldBe("metric");
    }

    // --- user_profile_enc: the four encrypted condition columns ------------------------------

    [Fact]
    public void The_four_new_profile_condition_columns_are_all_encrypted_bytea_and_nullable()
    {
        // Encrypted rather than plaintext because none is ever a SQL predicate, sort or aggregate
        // (C-14: rASRM "does NOT correlate with pain, never inferred"), and a new plaintext
        // quasi-identifier would have to join the T8 shred blanking list.
        using var db = NewContext();
        var entity = db.Model.FindEntityType(typeof(UserProfileEnc)).ShouldNotBeNull();

        foreach (var name in new[]
                 {
                     nameof(UserProfileEnc.EndoStatusEnc), nameof(UserProfileEnc.RasrmStageEnc),
                     nameof(UserProfileEnc.DiagnosedOnEnc), nameof(UserProfileEnc.HeightCmEnc),
                 })
        {
            var property = entity.FindProperty(name).ShouldNotBeNull();
            property.ClrType.ShouldBe(typeof(byte[]));
            property.IsNullable.ShouldBeTrue($"{name} is optional — onboarding may skip it (D-02)");
        }
    }

    [Fact]
    public void There_is_no_weight_column_on_the_profile_and_no_surgeries_column()
    {
        // Rider 4: onboarding weight seeds a body_metrics row so weight has ONE source of truth.
        // Surgeries are deferred (C-14, clinician-UNSIGNED).
        using var db = NewContext();
        var entity = db.Model.FindEntityType(typeof(UserProfileEnc)).ShouldNotBeNull();
        entity.FindProperty("WeightKgEnc").ShouldBeNull();
        entity.FindProperty("SurgeriesEnc").ShouldBeNull();
    }

    [Fact]
    public void The_four_condition_columns_round_trip_as_opaque_ciphertext()
    {
        byte[] endoStatus = [10, 20, 30];
        byte[] rasrm = [40, 50];
        byte[] diagnosedOn = [60];
        byte[] height = [70, 80, 90, 100];

        SaveAll(new UserProfileEnc
        {
            UserId = _userId,
            EndoStatusEnc = endoStatus,
            RasrmStageEnc = rasrm,
            DiagnosedOnEnc = diagnosedOn,
            HeightCmEnc = height,
            CreatedAt = Now,
            UpdatedAt = Now,
        });

        using var read = NewContext();
        var row = read.UserProfiles.Single(x => x.UserId == _userId);
        row.EndoStatusEnc.ShouldBe(endoStatus);
        row.RasrmStageEnc.ShouldBe(rasrm);
        row.DiagnosedOnEnc.ShouldBe(diagnosedOn);
        row.HeightCmEnc.ShouldBe(height);
    }

    // --- shape of the whole T7 table set -----------------------------------------------------

    [Fact]
    public void The_two_new_tables_use_snake_case_names_and_PascalCase_columns()
    {
        using var db = NewContext();
        var expected = new Dictionary<Type, string>
        {
            [typeof(BodyMetric)] = "body_metrics",
            [typeof(UserInsightSnapshot)] = "user_insight_snapshot",
        };

        foreach (var (clr, table) in expected)
        {
            var entity = db.Model.FindEntityType(clr).ShouldNotBeNull();
            entity.GetTableName().ShouldBe(table);
            // No naming convention: the CHECK and index-filter literals double-quote the real
            // PascalCase identifiers, and a rename would silently invalidate them (T1 probe 3).
            entity.FindProperty("UserId").ShouldNotBeNull().GetColumnName().ShouldBe("UserId");
        }
    }

    [Fact]
    public void Body_metrics_is_the_only_table_in_the_model_with_a_tombstone_filtered_unique_index()
    {
        // §G9's inventory: exactly one filtered SOFT-DELETE unique index. (A DB-level audit also
        // finds cycle_tracking_pause_spans' partial unique index, but its predicate is EndedOn —
        // a domain lifecycle column, not a tombstone — so it is outside this regime.)
        using var db = NewContext();
        var filtered = db.Model.GetEntityTypes()
            .SelectMany(e => e.GetIndexes().Select(i => (Entity: e, Index: i)))
            .Where(x => x.Index.IsUnique && x.Index.GetFilter() == "\"DeletedAt\" IS NULL")
            .Select(x => x.Entity.ClrType)
            .ToList();

        filtered.ShouldBe([typeof(BodyMetric)]);
    }
}
