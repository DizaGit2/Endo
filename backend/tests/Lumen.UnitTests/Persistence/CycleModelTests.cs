using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Persistence;

/// <summary>
/// Schema-level guards for the four P4a observation tables (T5): the numeric CHECK constraints,
/// the §G9 unique-index regime, and the onboarding-seed merge rule the schema forces on T18.
///
/// Every rejection is asserted on <see cref="DbUpdateException"/> only — never on
/// <c>SqliteException</c>/<c>PostgresException</c>, whose type and message differ per provider
/// (T1 probe 3/4: SQLite Error 19 vs SqlState 23514/23505).
/// </summary>
public sealed class CycleModelTests : IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly Guid _userId = Guid.NewGuid();
    private static readonly DateTimeOffset Now = new(2026, 8, 6, 9, 30, 0, TimeSpan.Zero);
    private static readonly DateOnly Day = new(2026, 8, 6);

    public CycleModelTests()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        using var db = NewContext();
        db.Database.EnsureCreated();
        db.Users.Add(new User
        {
            Id = _userId,
            EmailHash = "vault:v1:cycle-model-tests",
            Locale = "es-ES",
            Timezone = "Europe/Madrid",
            CreatedAt = Now,
            UpdatedAt = Now,
        });
        db.SaveChanges();
    }

    public void Dispose() => _connection.Dispose();

    // A fresh context per attempt: a failed SaveChanges leaves the change tracker poisoned.
    private LumenDbContext NewContext() =>
        new(new DbContextOptionsBuilder<LumenDbContext>().UseSqlite(_connection).Options);

    private CycleEvent NewEvent(
        string kind, DateOnly on, short? flow = null, string? source = null, DateTimeOffset? deletedAt = null) => new()
        {
            Id = Guid.NewGuid(),
            UserId = _userId,
            Kind = kind,
            OccurredOn = on,
            FlowIntensity = flow,
            Source = source ?? CycleEvent.Sources.User,
            CreatedAt = Now,
            UpdatedAt = Now,
            DeletedAt = deletedAt,
        };

    private CycleDayLog NewDayLog(DateOnly day, short? pain = null, short? mood = null) => new()
    {
        Id = Guid.NewGuid(),
        UserId = _userId,
        Day = day,
        Pain = pain,
        Mood = mood,
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    private Symptom NewSymptom(short intensity) => new()
    {
        Id = Guid.NewGuid(),
        UserId = _userId,
        SymptomCode = Symptom.Codes.Pain,
        Intensity = intensity,
        Region = Symptom.Regions.Unspecified,
        OccurredAt = Now,
        OccurredOn = Day,
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    private CyclePhaseOverride NewOverride(string phase, string boundary, DateOnly cycleStartOn) => new()
    {
        Id = Guid.NewGuid(),
        UserId = _userId,
        CycleStartOn = cycleStartOn,
        Phase = phase,
        Boundary = boundary,
        OccurredOn = cycleStartOn,
        Source = CyclePhaseOverride.Sources.UserCorrection,
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

    // --- CHECK constraints: numeric ranges only (no vocabulary CHECKs) --------------------

    [Theory]
    [InlineData(0)]   // D-08: 0 is a real datum, not "no data"
    [InlineData(10)]
    public void CycleDayLog_accepts_Pain_inside_the_0_to_10_scale(short pain) =>
        SaveAll(NewDayLog(Day.AddDays(pain), pain: pain));

    [Theory]
    [InlineData(11)]
    [InlineData(-1)]
    public void CycleDayLog_rejects_Pain_outside_the_0_to_10_scale(short pain) =>
        SaveAllShouldThrow(NewDayLog(Day.AddDays(20 + pain), pain: pain));

    [Theory]
    [InlineData(1)]
    [InlineData(4)]
    public void CycleDayLog_accepts_Mood_inside_the_1_to_4_scale(short mood) =>
        SaveAll(NewDayLog(Day.AddDays(40 + mood), mood: mood));

    [Theory]
    [InlineData(5)]
    [InlineData(0)]
    public void CycleDayLog_rejects_Mood_outside_the_1_to_4_scale(short mood) =>
        SaveAllShouldThrow(NewDayLog(Day.AddDays(60 + mood), mood: mood));

    [Fact]
    public void CycleDayLog_accepts_null_Pain_and_null_Mood() =>
        SaveAll(NewDayLog(Day.AddDays(80)));

    [Theory]
    [InlineData(-5)]
    [InlineData(99)]
    public void CycleDayLog_has_no_CHECK_on_the_reserved_Energy_and_Libido_columns(short reserved)
    {
        // D-10 defers both scales: §D keeps the columns, T5 deliberately adds no constraint.
        var log = NewDayLog(Day.AddDays(100 + reserved));
        log.Energy = reserved;
        log.Libido = reserved;
        SaveAll(log);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(4)]
    public void CycleEvent_accepts_FlowIntensity_inside_the_1_to_4_scale(short flow) =>
        SaveAll(NewEvent(CycleEvent.Kinds.PeriodStart, Day.AddDays(flow), flow));

    [Theory]
    [InlineData(5)]
    [InlineData(0)]
    public void CycleEvent_rejects_FlowIntensity_outside_the_1_to_4_scale(short flow) =>
        SaveAllShouldThrow(NewEvent(CycleEvent.Kinds.PeriodStart, Day.AddDays(200 + flow), flow));

    [Fact]
    public void CycleEvent_accepts_null_FlowIntensity() =>
        SaveAll(NewEvent(CycleEvent.Kinds.PeriodEnd, Day.AddDays(210)));

    [Theory]
    [InlineData(0)]   // D-08: 0 is a real datum
    [InlineData(10)]
    public void Symptom_accepts_Intensity_inside_the_0_to_10_scale(short intensity) =>
        SaveAll(NewSymptom(intensity));

    [Theory]
    [InlineData(11)]
    [InlineData(-1)]
    public void Symptom_rejects_Intensity_outside_the_0_to_10_scale(short intensity) =>
        SaveAllShouldThrow(NewSymptom(intensity));

    [Fact]
    public void No_table_carries_a_CHECK_on_vocabulary_membership()
    {
        // §G10 / §D: enums are hard-coded in code, not in the DB. An unrecognised code must be
        // storable at the schema level — validation is the endpoint's job, and freezing membership
        // in DDL would make the append-only vocabularies a migration each.
        SaveAll(NewEvent("not_a_kind", Day.AddDays(220)));
        var symptom = NewSymptom(3);
        symptom.SymptomCode = "not_a_symptom";
        symptom.Region = "not_a_region";
        symptom.Side = "up";
        SaveAll(symptom);
    }

    // --- §G9 unique-index regime: UNFILTERED on cycle_events / cycle_day_logs -------------

    [Fact]
    public void CycleEvent_unique_index_is_on_UserId_Kind_OccurredOn_and_is_unfiltered()
    {
        using var db = NewContext();
        var index = db.Model.FindEntityType(typeof(CycleEvent)).ShouldNotBeNull()
            .GetIndexes().Single(i => i.IsUnique);

        index.Properties.Select(p => p.Name)
            .ShouldBe([nameof(CycleEvent.UserId), nameof(CycleEvent.Kind), nameof(CycleEvent.OccurredOn)]);
        index.GetFilter().ShouldBeNull("§G9: cycle_events uses an UNFILTERED unique index + revive-the-tombstone");
    }

    [Fact]
    public void CycleDayLog_unique_index_is_on_UserId_Day_and_is_unfiltered()
    {
        using var db = NewContext();
        var index = db.Model.FindEntityType(typeof(CycleDayLog)).ShouldNotBeNull()
            .GetIndexes().Single(i => i.IsUnique);

        index.Properties.Select(p => p.Name)
            .ShouldBe([nameof(CycleDayLog.UserId), nameof(CycleDayLog.Day)]);
        index.GetFilter().ShouldBeNull("§G9: cycle_day_logs uses an UNFILTERED unique index + revive-the-tombstone");
    }

    [Fact]
    public void CycleEvent_rejects_a_second_live_row_for_the_same_user_kind_and_day() =>
        SaveAllShouldThrow(
            NewEvent(CycleEvent.Kinds.PeriodStart, Day),
            NewEvent(CycleEvent.Kinds.PeriodStart, Day));

    [Fact]
    public void CycleEvent_allows_the_same_day_for_a_different_kind() =>
        SaveAll(
            NewEvent(CycleEvent.Kinds.PeriodStart, Day),
            NewEvent(CycleEvent.Kinds.Spotting, Day));

    [Fact]
    public void CycleEvent_unfiltered_index_makes_a_tombstone_block_a_duplicate_insert()
    {
        // The behavioural definition of "unfiltered": a soft-deleted row still occupies the key,
        // so an upsert MUST revive it rather than insert a second row.
        SaveAll(NewEvent(CycleEvent.Kinds.PeriodStart, Day, deletedAt: Now));
        SaveAllShouldThrow(NewEvent(CycleEvent.Kinds.PeriodStart, Day));
    }

    [Fact]
    public void CycleDayLog_unfiltered_index_makes_a_tombstone_block_a_duplicate_insert()
    {
        var tombstone = NewDayLog(Day);
        tombstone.DeletedAt = Now;
        SaveAll(tombstone);
        SaveAllShouldThrow(NewDayLog(Day));
    }

    [Fact]
    public void CycleDayLog_tombstone_is_revived_in_place_never_duplicated()
    {
        var tombstone = NewDayLog(Day, pain: 4);
        tombstone.DeletedAt = Now;
        SaveAll(tombstone);

        using (var db = NewContext())
        {
            var found = db.CycleDayLogs.IgnoreQueryFilters()
                .Single(x => x.UserId == _userId && x.Day == Day);
            found.DeletedAt = null;
            found.Pain = 6;
            found.UpdatedAt = Now.AddHours(1);
            db.SaveChanges();
        }

        using var read = NewContext();
        read.CycleDayLogs.IgnoreQueryFilters().Count(x => x.UserId == _userId && x.Day == Day).ShouldBe(1);
        var live = read.CycleDayLogs.Single(x => x.UserId == _userId && x.Day == Day);
        live.Pain.ShouldBe((short)6);
        live.Id.ShouldBe(tombstone.Id);
    }

    // --- the onboarding-seed merge rule the schema forces on T18 --------------------------

    [Fact]
    public void Naively_moving_the_onboarding_seed_onto_an_occupied_day_violates_the_unique_index()
    {
        var target = Day;
        var seedDay = Day.AddDays(-30);
        SaveAll(
            NewEvent(CycleEvent.Kinds.PeriodStart, target),
            NewEvent(CycleEvent.Kinds.PeriodStart, seedDay, source: CycleEvent.Sources.Onboarding));

        using var db = NewContext();
        var seed = db.CycleEvents.IgnoreQueryFilters().Single(x =>
            x.UserId == _userId && x.Kind == CycleEvent.Kinds.PeriodStart && x.Source == CycleEvent.Sources.Onboarding);
        seed.OccurredOn = target;
        Should.Throw<DbUpdateException>(() => db.SaveChanges());
    }

    [Fact]
    public void Moving_the_onboarding_seed_onto_an_occupied_day_adopts_the_existing_row()
    {
        var target = Day;
        var seedDay = Day.AddDays(-30);
        var existingCreatedAt = Now.AddDays(-3);

        var existing = NewEvent(CycleEvent.Kinds.PeriodStart, target);
        existing.CreatedAt = existingCreatedAt;
        var seed = NewEvent(CycleEvent.Kinds.PeriodStart, seedDay, source: CycleEvent.Sources.Onboarding);
        SaveAll(existing, seed);

        MergeOnboardingSeedOnto(target);

        using var read = NewContext();
        var all = read.CycleEvents.IgnoreQueryFilters()
            .Where(x => x.UserId == _userId && x.Kind == CycleEvent.Kinds.PeriodStart)
            .OrderBy(x => x.OccurredOn).ToList();

        var live = all.Where(x => x.DeletedAt == null).ShouldHaveSingleItem();
        live.Id.ShouldBe(existing.Id, "the target row is adopted, not replaced");
        live.OccurredOn.ShouldBe(target);
        live.Source.ShouldBe(CycleEvent.Sources.User, "the adopted row keeps its own Source");
        live.CreatedAt.ShouldBe(existingCreatedAt, "the adopted row keeps its own CreatedAt");
        all.Single(x => x.Id == seed.Id).DeletedAt.ShouldNotBeNull("the stale onboarding row is retired");
    }

    [Fact]
    public void Moving_the_onboarding_seed_onto_a_tombstoned_day_revives_it_never_duplicates()
    {
        var target = Day;
        var seedDay = Day.AddDays(-30);

        var tombstone = NewEvent(CycleEvent.Kinds.PeriodStart, target, deletedAt: Now.AddDays(-1));
        var seed = NewEvent(CycleEvent.Kinds.PeriodStart, seedDay, source: CycleEvent.Sources.Onboarding);
        SaveAll(tombstone, seed);

        MergeOnboardingSeedOnto(target);

        using var read = NewContext();
        read.CycleEvents.IgnoreQueryFilters()
            .Count(x => x.UserId == _userId && x.Kind == CycleEvent.Kinds.PeriodStart && x.OccurredOn == target)
            .ShouldBe(1, "the tombstone is revived, never duplicated");
        var live = read.CycleEvents.Single(x => x.UserId == _userId && x.OccurredOn == target);
        live.Id.ShouldBe(tombstone.Id);
        live.DeletedAt.ShouldBeNull();
    }

    [Fact]
    public void Moving_the_onboarding_seed_onto_a_free_day_just_moves_it()
    {
        var target = Day;
        var seedDay = Day.AddDays(-30);
        var seed = NewEvent(CycleEvent.Kinds.PeriodStart, seedDay, source: CycleEvent.Sources.Onboarding);
        SaveAll(seed);

        MergeOnboardingSeedOnto(target);

        using var read = NewContext();
        var live = read.CycleEvents.Where(x => x.UserId == _userId).ToList().ShouldHaveSingleItem();
        live.Id.ShouldBe(seed.Id);
        live.OccurredOn.ShouldBe(target);
        live.Source.ShouldBe(CycleEvent.Sources.Onboarding);
    }

    /// <summary>
    /// The merge rule pinned on <see cref="CycleEvent"/>'s XML doc, executed against the real
    /// schema. T18 owns the production implementation; this is the schema-level proof that the
    /// documented procedure never violates the unfiltered unique index.
    /// </summary>
    private void MergeOnboardingSeedOnto(DateOnly target)
    {
        using var db = NewContext();
        var seed = db.CycleEvents.IgnoreQueryFilters().Single(x =>
            x.UserId == _userId
            && x.Kind == CycleEvent.Kinds.PeriodStart
            && x.Source == CycleEvent.Sources.Onboarding);

        var occupant = db.CycleEvents.IgnoreQueryFilters().SingleOrDefault(x =>
            x.UserId == _userId && x.Kind == CycleEvent.Kinds.PeriodStart && x.OccurredOn == target);

        if (occupant is null)
        {
            seed.OccurredOn = target;
            seed.UpdatedAt = Now.AddHours(1);
        }
        else if (occupant.Id != seed.Id)
        {
            occupant.DeletedAt = null;              // adopt/revive; keep Source and CreatedAt
            occupant.UpdatedAt = Now.AddHours(1);
            seed.DeletedAt = Now.AddHours(1);       // retire the stale onboarding row
            seed.UpdatedAt = Now.AddHours(1);
        }

        db.SaveChanges();
    }

    // --- cycle_phase_overrides ------------------------------------------------------------

    [Fact]
    public void CyclePhaseOverride_unique_index_is_on_UserId_CycleStartOn_Phase_Boundary_and_is_unfiltered()
    {
        using var db = NewContext();
        var index = db.Model.FindEntityType(typeof(CyclePhaseOverride)).ShouldNotBeNull()
            .GetIndexes().Single(i => i.IsUnique);

        index.Properties.Select(p => p.Name).ShouldBe([
            nameof(CyclePhaseOverride.UserId),
            nameof(CyclePhaseOverride.CycleStartOn),
            nameof(CyclePhaseOverride.Phase),
            nameof(CyclePhaseOverride.Boundary),
        ]);
        index.GetFilter().ShouldBeNull();
    }

    [Fact]
    public void CyclePhaseOverride_rejects_a_duplicate_phase_boundary_for_the_same_cycle() =>
        SaveAllShouldThrow(
            NewOverride(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, Day),
            NewOverride(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, Day));

    [Fact]
    public void CyclePhaseOverride_allows_both_boundaries_of_the_same_phase() =>
        SaveAll(
            NewOverride(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.Start, Day),
            NewOverride(CyclePhaseOverride.Phases.Luteal, CyclePhaseOverride.Boundaries.End, Day));

    // --- soft-delete filter on all four tables --------------------------------------------

    [Fact]
    public void All_four_tables_carry_the_soft_delete_query_filter()
    {
        using var db = NewContext();
        foreach (var clr in new[]
                 {
                     typeof(CycleEvent), typeof(CycleDayLog), typeof(Symptom), typeof(CyclePhaseOverride),
                 })
        {
            db.Model.FindEntityType(clr).ShouldNotBeNull().GetDeclaredQueryFilters()
                .ShouldNotBeEmpty($"{clr.Name} must exclude soft-deleted rows from every read (D-13)");
        }
    }

    [Fact]
    public void The_four_tables_use_snake_case_names_and_PascalCase_columns()
    {
        using var db = NewContext();
        var expected = new Dictionary<Type, string>
        {
            [typeof(CycleEvent)] = "cycle_events",
            [typeof(CycleDayLog)] = "cycle_day_logs",
            [typeof(Symptom)] = "symptoms",
            [typeof(CyclePhaseOverride)] = "cycle_phase_overrides",
        };

        foreach (var (clr, table) in expected)
        {
            var entity = db.Model.FindEntityType(clr).ShouldNotBeNull();
            entity.GetTableName().ShouldBe(table);
            // No naming convention: the column identifiers inside the CHECK literals are
            // double-quoted PascalCase, and a rename would silently invalidate them (T1 probe 3).
            entity.FindProperty("UserId").ShouldNotBeNull()
                .GetColumnName().ShouldBe("UserId");
        }
    }
}
