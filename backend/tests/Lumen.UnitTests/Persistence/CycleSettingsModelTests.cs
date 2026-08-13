using Lumen.Domain.Entities;
using Lumen.Domain.Reference;
using Lumen.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Persistence;

/// <summary>
/// Schema-level guards for the five P4a settings/preference tables (T6): every DB default, the
/// two <b>structural</b> CHECK constraints (§G7 — positive integers only, no clinical bound in
/// DDL), the partial unique index that allows at most one <i>open</i> pause span per user, and the
/// unique keys on the three preference tables.
///
/// Every rejection is asserted on <see cref="DbUpdateException"/> only — never on
/// <c>SqliteException</c>/<c>PostgresException</c>, whose type and message differ per provider
/// (T1 probe 3/4).
/// </summary>
public sealed class CycleSettingsModelTests : IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly Guid _userId = Guid.NewGuid();
    private readonly Guid _otherUserId = Guid.NewGuid();
    private static readonly DateTimeOffset Now = new(2026, 8, 6, 9, 30, 0, TimeSpan.Zero);
    private static readonly DateOnly Day = new(2026, 8, 6);

    public CycleSettingsModelTests()
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
        EmailHash = $"vault:v1:cycle-settings-tests-{tag}",
        Locale = "es-ES",
        Timezone = "Europe/Madrid",
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    // A fresh context per attempt: a failed SaveChanges leaves the change tracker poisoned.
    private LumenDbContext NewContext() =>
        new(new DbContextOptionsBuilder<LumenDbContext>().UseSqlite(_connection).Options);

    private UserCycleSettings NewSettings(Guid? userId = null) => new()
    {
        UserId = userId ?? _userId,
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    private CycleTrackingPauseSpan NewSpan(DateOnly startedOn, DateOnly? endedOn = null, Guid? userId = null) => new()
    {
        Id = Guid.NewGuid(),
        UserId = userId ?? _userId,
        Reason = UserCycleSettings.PauseReasons.Pregnancy,
        StartedOn = startedOn,
        EndedOn = endedOn,
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    private UserGoal NewGoal(string code, Guid? userId = null) => new()
    {
        Id = Guid.NewGuid(),
        UserId = userId ?? _userId,
        GoalCode = code,
        Selected = true,
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    private UserHormonePref NewHormonePref(string code, Guid? userId = null) => new()
    {
        Id = Guid.NewGuid(),
        UserId = userId ?? _userId,
        HormoneCode = code,
        Charted = true,
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    private UserNotificationPref NewNotificationPref(string code, Guid? userId = null) => new()
    {
        Id = Guid.NewGuid(),
        UserId = userId ?? _userId,
        CategoryCode = code,
        Enabled = true,
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

    // --- DB defaults, one assertion per column ---------------------------------------------
    //
    // Read back after a RAW SQL insert that supplies only the three columns with no default.
    // That is the only way to observe a *database* default: EF is configured ValueGeneratedNever
    // on these columns (see the entity's remarks), so it always sends the CLR value.

    private UserCycleSettings InsertSettingsWithoutAnyDefaultedColumn()
    {
        using (var db = NewContext())
        {
            db.Database.ExecuteSqlInterpolated(
                $"""
                 INSERT INTO user_cycle_settings ("UserId", "CreatedAt", "UpdatedAt")
                 VALUES ({_userId}, {Now}, {Now})
                 """);
        }

        using var read = NewContext();
        return read.CycleSettings.Single(x => x.UserId == _userId);
    }

    [Fact]
    public void AvgCycleLengthDays_defaults_to_28() =>
        // definitions.md:71 — the onboarding chip marked "default selected".
        InsertSettingsWithoutAnyDefaultedColumn().AvgCycleLengthDays.ShouldBe((short)28);

    [Fact]
    public void AvgPeriodLengthDays_has_no_default_and_stays_null() =>
        // Screen 3 never collects it; inventing 5 would fabricate a self-report the user never made.
        InsertSettingsWithoutAnyDefaultedColumn().AvgPeriodLengthDays.ShouldBeNull();

    [Fact]
    public void Regularity_defaults_to_somewhat() =>
        InsertSettingsWithoutAnyDefaultedColumn().Regularity.ShouldBe("somewhat");

    [Fact]
    public void PhasePredictionEnabled_defaults_to_true() =>
        InsertSettingsWithoutAnyDefaultedColumn().PhasePredictionEnabled.ShouldBeTrue();

    [Fact]
    public void AutoDetectPeriodStartEnabled_defaults_to_true() =>
        InsertSettingsWithoutAnyDefaultedColumn().AutoDetectPeriodStartEnabled.ShouldBeTrue();

    [Fact]
    public void ShowFertilityWindowEnabled_defaults_to_false() =>
        InsertSettingsWithoutAnyDefaultedColumn().ShowFertilityWindowEnabled.ShouldBeFalse();

    [Fact]
    public void TrackingPaused_defaults_to_false() =>
        InsertSettingsWithoutAnyDefaultedColumn().TrackingPaused.ShouldBeFalse();

    [Fact]
    public void PauseReason_has_no_default_and_stays_null() =>
        InsertSettingsWithoutAnyDefaultedColumn().PauseReason.ShouldBeNull();

    [Fact]
    public void PausedSince_has_no_default_and_stays_null() =>
        InsertSettingsWithoutAnyDefaultedColumn().PausedSince.ShouldBeNull();

    [Fact]
    public void Every_defaulted_column_declares_its_default_in_the_model()
    {
        using var db = NewContext();
        var entity = db.Model.FindEntityType(typeof(UserCycleSettings)).ShouldNotBeNull();

        entity.FindProperty(nameof(UserCycleSettings.AvgCycleLengthDays)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe((short)28);
        entity.FindProperty(nameof(UserCycleSettings.Regularity)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe("somewhat");
        entity.FindProperty(nameof(UserCycleSettings.PhasePredictionEnabled)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe(true);
        entity.FindProperty(nameof(UserCycleSettings.AutoDetectPeriodStartEnabled)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe(true);
        entity.FindProperty(nameof(UserCycleSettings.ShowFertilityWindowEnabled)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe(false);
        entity.FindProperty(nameof(UserCycleSettings.TrackingPaused)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBe(false);

        // The two columns that deliberately have none.
        entity.FindProperty(nameof(UserCycleSettings.AvgPeriodLengthDays)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBeNull();
        entity.FindProperty(nameof(UserCycleSettings.PauseReason)).ShouldNotBeNull()
            .GetDefaultValue().ShouldBeNull();
    }

    [Fact]
    public void A_new_settings_row_created_through_EF_carries_the_same_defaults()
    {
        SaveAll(NewSettings());

        using var read = NewContext();
        var row = read.CycleSettings.Single(x => x.UserId == _userId);
        row.AvgCycleLengthDays.ShouldBe((short)28);
        row.AvgPeriodLengthDays.ShouldBeNull();
        row.Regularity.ShouldBe("somewhat");
        row.PhasePredictionEnabled.ShouldBeTrue();
        row.AutoDetectPeriodStartEnabled.ShouldBeTrue();
        row.ShowFertilityWindowEnabled.ShouldBeFalse();
        row.TrackingPaused.ShouldBeFalse();
        row.PauseReason.ShouldBeNull();
        row.PausedSince.ShouldBeNull();
    }

    // NOTE: an earlier revision of this file carried
    // `An_explicit_false_on_a_default_true_column_survives_the_insert`, documented as "the reason
    // the boolean columns are mapped ValueGeneratedNever()". A T6 review disproved that: removing
    // ValueGeneratedNever() from PhasePredictionEnabled alone left that test (and all 240 others)
    // green. EF Core 10 infers a property's value-generation "sentinel" (the value treated as
    // "not set") from a literal C# field initializer when one is present; PhasePredictionEnabled's
    // `= true` and AutoDetectPeriodStartEnabled's `= true` are literals, so EF already sends an
    // explicit `false` regardless of ValueGeneratedNever(), and ShowFertilityWindowEnabled /
    // TrackingPaused have no swallow to guard against because their sentinel (CLR default `false`)
    // already equals their own DB default. That test was therefore a vacuous guard for the claim
    // it carried and has been deleted rather than kept under a corrected rationale, because there
    // is no production behaviour left for it to pin: making it genuinely load-bearing would mean
    // changing the bool columns' default scheme, which nothing here requires. The two tests below
    // replace it with the columns where the swallow is real.

    [Fact]
    public void AvgCycleLengthDays_zero_is_not_swallowed_by_the_DB_default_and_the_CHECK_still_rejects_it()
    {
        // The genuine load-bearing case for ValueGeneratedNever(). AvgCycleLengthDays' CLR
        // initializer is `= DefaultAvgCycleLengthDays` -- a reference to a named const, not a
        // literal -- so EF Core's sentinel-from-initializer inference does not fire, and the
        // property's sentinel stays the plain CLR default for `short`: 0. Without
        // ValueGeneratedNever(), an explicit AvgCycleLengthDays = 0 is indistinguishable from
        // "not set": EF would omit the column from the INSERT, the DB default (28) would fire
        // silently, SaveChanges would succeed, and the "> 0" CHECK would never see the caller's
        // actual value -- defeating the one constraint it exists to enforce. Proven empirically:
        // temporarily removing ValueGeneratedNever() from AvgCycleLengthDays alone makes this
        // exact assertion fail (SaveChanges succeeds and the row reads back 28 instead of
        // throwing). See "T6 review fixes" in task-6-report.md for the pasted red/green output.
        var settings = NewSettings();
        settings.AvgCycleLengthDays = 0;

        using var db = NewContext();
        db.Add(settings);
        Should.Throw<DbUpdateException>(() => db.SaveChanges());
    }

    [Fact]
    public void Regularity_null_is_not_swallowed_by_the_DB_default_and_the_NOT_NULL_constraint_still_rejects_it()
    {
        // Same swallow, same fix, a different column and a different guarded constraint.
        // Regularity's initializer is `= RegularityValues.Default` -- again a named-const
        // reference, not a literal -- so its sentinel stays the CLR default for a reference type:
        // null. Without ValueGeneratedNever(), an explicit Regularity = null would be swallowed
        // the same way: omitted from the INSERT, silently replaced by the DB default
        // ("somewhat"), and the column's own NOT NULL constraint would never see the caller's
        // actual (invalid) value. Proven empirically the same way: temporarily removing
        // ValueGeneratedNever() from Regularity alone makes this assertion fail (SaveChanges
        // succeeds and the row reads back "somewhat" instead of throwing).
        var settings = NewSettings();
        settings.Regularity = null!;

        using var db = NewContext();
        db.Add(settings);
        Should.Throw<DbUpdateException>(() => db.SaveChanges());
    }

    // --- structural CHECKs (§G7): positive smallint, nothing clinical ----------------------

    [Theory]
    [InlineData(1)]
    [InlineData(28)]
    [InlineData(200)]
    [InlineData(365)]
    [InlineData(short.MaxValue)]
    public void AvgCycleLengthDays_accepts_any_positive_value(short days)
    {
        // §G7: the DDL check is structural (`> 0`). There is NO upper clinical bound in the schema
        // and no invented 1-365 tier — 365 is accepted here purely as a positive integer.
        var settings = NewSettings();
        settings.AvgCycleLengthDays = days;
        SaveAll(settings);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void AvgCycleLengthDays_rejects_zero_and_negatives(short days)
    {
        var settings = NewSettings();
        settings.AvgCycleLengthDays = days;
        SaveAllShouldThrow(settings);
    }

    [Theory]
    [InlineData(9)]    // below the 10-120 sanity band
    [InlineData(121)]  // above the 10-120 sanity band
    [InlineData(20)]   // below the 21-45 clinical band
    [InlineData(46)]   // above the 21-45 clinical band
    public void Neither_the_sanity_band_nor_the_clinical_bounds_exist_in_the_DDL(short days)
    {
        // §G7: the sanity band (10-120) is a non-blocking warning owned by T14, and the clinical
        // bounds (21-45) are clinician-UNSIGNED with no home in backend/src this phase. Both must
        // be storable, or the schema itself would become an entry blocker.
        var settings = NewSettings();
        settings.AvgCycleLengthDays = days;
        SaveAll(settings);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(30)]
    [InlineData(90)]
    public void AvgPeriodLengthDays_accepts_any_positive_value(short days)
    {
        var settings = NewSettings();
        settings.AvgPeriodLengthDays = days;
        SaveAll(settings);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void AvgPeriodLengthDays_rejects_zero_and_negatives(short days)
    {
        var settings = NewSettings();
        settings.AvgPeriodLengthDays = days;
        SaveAllShouldThrow(settings);
    }

    [Fact]
    public void AvgPeriodLengthDays_accepts_null() =>
        SaveAll(NewSettings());

    [Fact]
    public void A_resumed_user_keeps_the_last_PauseReason_because_no_CHECK_ties_it_to_TrackingPaused()
    {
        // Deliberate: resume clears TrackingPaused/PausedSince but preserves the reason so the
        // next pause pre-selects it. A CHECK tying the two would make that impossible.
        var settings = NewSettings();
        settings.TrackingPaused = false;
        settings.PauseReason = UserCycleSettings.PauseReasons.HormonalSuppression;
        settings.PausedSince = null;
        SaveAll(settings);

        using var read = NewContext();
        read.CycleSettings.Single(x => x.UserId == _userId)
            .PauseReason.ShouldBe("hormonal_suppression");
    }

    [Fact]
    public void No_settings_column_carries_a_CHECK_on_vocabulary_membership()
    {
        // §G10 / §D: enums are hard-coded in code, not in the DB.
        var settings = NewSettings();
        settings.Regularity = "not_a_regularity";
        settings.PauseReason = "not_a_reason";
        SaveAll(settings);
    }

    // --- cycle_tracking_pause_spans: at most one OPEN span per user ------------------------

    [Fact]
    public void The_pause_span_unique_index_is_on_UserId_and_is_filtered_on_an_open_span()
    {
        using var db = NewContext();
        var index = db.Model.FindEntityType(typeof(CycleTrackingPauseSpan)).ShouldNotBeNull()
            .GetIndexes().Single(i => i.IsUnique);

        index.Properties.Select(p => p.Name).ShouldBe([nameof(CycleTrackingPauseSpan.UserId)]);
        index.GetFilter().ShouldBe("\"EndedOn\" IS NULL");
    }

    [Fact]
    public void A_user_may_not_have_two_open_pause_spans() =>
        SaveAllShouldThrow(
            NewSpan(Day.AddDays(-60)),
            NewSpan(Day));

    [Fact]
    public void A_user_may_have_many_closed_pause_spans() =>
        SaveAll(
            NewSpan(Day.AddDays(-300), Day.AddDays(-240)),
            NewSpan(Day.AddDays(-200), Day.AddDays(-100)),
            NewSpan(Day.AddDays(-90), Day.AddDays(-30)));

    [Fact]
    public void A_user_may_have_many_closed_spans_plus_exactly_one_open_span() =>
        SaveAll(
            NewSpan(Day.AddDays(-300), Day.AddDays(-240)),
            NewSpan(Day.AddDays(-200), Day.AddDays(-100)),
            NewSpan(Day));

    [Fact]
    public void Two_different_users_may_each_have_an_open_pause_span() =>
        SaveAll(
            NewSpan(Day),
            NewSpan(Day, userId: _otherUserId));

    [Fact]
    public void Closing_the_open_span_frees_the_key_for_the_next_pause()
    {
        var open = NewSpan(Day.AddDays(-60));
        SaveAll(open);

        using (var db = NewContext())
        {
            db.CycleTrackingPauseSpans.Single(x => x.Id == open.Id).EndedOn = Day.AddDays(-10);
            db.SaveChanges();
        }

        SaveAll(NewSpan(Day));

        using var read = NewContext();
        read.CycleTrackingPauseSpans.Count(x => x.UserId == _userId).ShouldBe(2);
        read.CycleTrackingPauseSpans.Count(x => x.UserId == _userId && x.EndedOn == null).ShouldBe(1);
    }

    [Fact]
    public void The_pause_span_table_also_carries_a_UserId_StartedOn_index()
    {
        using var db = NewContext();
        db.Model.FindEntityType(typeof(CycleTrackingPauseSpan)).ShouldNotBeNull()
            .GetIndexes()
            .Any(i => !i.IsUnique && i.Properties.Select(p => p.Name).SequenceEqual(
                [nameof(CycleTrackingPauseSpan.UserId), nameof(CycleTrackingPauseSpan.StartedOn)]))
            .ShouldBeTrue("P6 reads a user's spans in chronological order");
    }

    // --- the three preference tables: UNIQUE (UserId, <code>) ------------------------------

    [Fact]
    public void UserGoal_rejects_the_same_goal_code_twice_for_one_user() =>
        SaveAllShouldThrow(
            NewGoal(UserGoal.Codes.ManageSymptoms),
            NewGoal(UserGoal.Codes.ManageSymptoms));

    [Fact]
    public void UserGoal_allows_every_distinct_code_and_the_same_code_for_another_user() =>
        SaveAll(
            NewGoal(UserGoal.Codes.ManageSymptoms),
            NewGoal(UserGoal.Codes.UnderstandHormones),
            NewGoal(UserGoal.Codes.PlanFertility),
            NewGoal(UserGoal.Codes.PrepareAppointments),
            NewGoal(UserGoal.Codes.JustCurious),
            NewGoal(UserGoal.Codes.ManageSymptoms, userId: _otherUserId));

    [Fact]
    public void UserHormonePref_rejects_the_same_hormone_twice_for_one_user() =>
        SaveAllShouldThrow(
            NewHormonePref(HormoneCatalog.Codes.Estradiol),
            NewHormonePref(HormoneCatalog.Codes.Estradiol));

    [Fact]
    public void UserHormonePref_allows_all_seven_hormones_for_one_user() =>
        SaveAll([.. HormoneCatalog.Codes.All.Select(c => (object)NewHormonePref(c))]);

    [Fact]
    public void UserNotificationPref_rejects_the_same_category_twice_for_one_user() =>
        SaveAllShouldThrow(
            NewNotificationPref(HormoneCatalog.NotificationCategories.DailyCheckin),
            NewNotificationPref(HormoneCatalog.NotificationCategories.DailyCheckin));

    [Fact]
    public void UserNotificationPref_allows_all_four_categories_for_one_user() =>
        SaveAll([.. HormoneCatalog.NotificationCategories.All.Select(c => (object)NewNotificationPref(c))]);

    [Fact]
    public void A_deselected_preference_stays_as_a_row_with_a_false_flag()
    {
        // No DeletedAt anywhere on these tables: a tombstone would occupy the unique key and block
        // re-selecting the same goal/hormone/category.
        var goal = NewGoal(UserGoal.Codes.PlanFertility);
        goal.Selected = false;
        SaveAll(goal);

        using var read = NewContext();
        read.UserGoals.Single(x => x.Id == goal.Id).Selected.ShouldBeFalse();
    }

    [Fact]
    public void The_preference_unique_keys_are_unfiltered_because_there_is_no_tombstone()
    {
        using var db = NewContext();
        foreach (var clr in new[] { typeof(UserGoal), typeof(UserHormonePref), typeof(UserNotificationPref) })
        {
            db.Model.FindEntityType(clr).ShouldNotBeNull()
                .GetIndexes().Single(i => i.IsUnique)
                .GetFilter().ShouldBeNull($"{clr.Name} has no DeletedAt, so there is nothing to filter");
        }
    }

    // --- shape of the whole T6 table set ---------------------------------------------------

    [Fact]
    public void No_T6_table_carries_a_DeletedAt_column_or_a_soft_delete_filter()
    {
        // D-13 governs *entries*. A per-user singleton and a preference row are neither: soft-
        // deleting them would strand the unique key and block re-selection.
        using var db = NewContext();
        foreach (var clr in new[]
                 {
                     typeof(UserCycleSettings), typeof(CycleTrackingPauseSpan),
                     typeof(UserGoal), typeof(UserHormonePref), typeof(UserNotificationPref),
                 })
        {
            var entity = db.Model.FindEntityType(clr).ShouldNotBeNull();
            entity.FindProperty("DeletedAt").ShouldBeNull($"{clr.Name} must not be soft-deletable");
            entity.GetDeclaredQueryFilters().ShouldBeEmpty($"{clr.Name} has no soft-delete filter");
        }
    }

    [Fact]
    public void The_five_tables_use_snake_case_names_and_PascalCase_columns()
    {
        using var db = NewContext();
        var expected = new Dictionary<Type, string>
        {
            [typeof(UserCycleSettings)] = "user_cycle_settings",
            [typeof(CycleTrackingPauseSpan)] = "cycle_tracking_pause_spans",
            [typeof(UserGoal)] = "user_goals",
            [typeof(UserHormonePref)] = "user_hormone_prefs",
            [typeof(UserNotificationPref)] = "user_notification_prefs",
        };

        foreach (var (clr, table) in expected)
        {
            var entity = db.Model.FindEntityType(clr).ShouldNotBeNull();
            entity.GetTableName().ShouldBe(table);
            // No naming convention: the CHECK and index filter literals double-quote the real
            // PascalCase identifiers, and a rename would silently invalidate them (T1 probe 3).
            entity.FindProperty("UserId").ShouldNotBeNull().GetColumnName().ShouldBe("UserId");
        }
    }

    [Fact]
    public void UserCycleSettings_is_keyed_one_to_one_on_UserId()
    {
        using var db = NewContext();
        var entity = db.Model.FindEntityType(typeof(UserCycleSettings)).ShouldNotBeNull();
        entity.FindPrimaryKey().ShouldNotBeNull()
            .Properties.Select(p => p.Name).ShouldBe([nameof(UserCycleSettings.UserId)]);
    }

    [Fact]
    public void A_second_settings_row_for_the_same_user_is_impossible()
    {
        // Two contexts: within one, the change tracker would reject the duplicate key before the
        // database ever saw it, which would prove nothing about the schema.
        SaveAll(NewSettings());
        SaveAllShouldThrow(NewSettings());
    }

    [Fact]
    public void Every_T6_row_disappears_when_its_user_row_is_hard_deleted()
    {
        // Cascade is belt-and-braces only — T8 deletes these rows explicitly, because crypto-shred
        // tombstones the users row instead of dropping it, so the cascade never fires there.
        SaveAll(
            NewSettings(),
            NewSpan(Day),
            NewGoal(UserGoal.Codes.ManageSymptoms),
            NewHormonePref(HormoneCatalog.Codes.Estradiol),
            NewNotificationPref(HormoneCatalog.NotificationCategories.DailyCheckin));

        using (var db = NewContext())
        {
            db.Users.IgnoreQueryFilters().Where(x => x.Id == _userId).ExecuteDelete();
        }

        using var read = NewContext();
        read.CycleSettings.Count(x => x.UserId == _userId).ShouldBe(0);
        read.CycleTrackingPauseSpans.Count(x => x.UserId == _userId).ShouldBe(0);
        read.UserGoals.Count(x => x.UserId == _userId).ShouldBe(0);
        read.UserHormonePrefs.Count(x => x.UserId == _userId).ShouldBe(0);
        read.UserNotificationPrefs.Count(x => x.UserId == _userId).ShouldBe(0);
    }
}
