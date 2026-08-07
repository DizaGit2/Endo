using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Persistence;

/// <summary>
/// Pins the T1 probe-2 verdict for the shipped <see cref="Symptom"/> entity: the two
/// <c>List&lt;string&gt;</c> primitive collections (<see cref="Symptom.PainTypes"/>,
/// <see cref="Symptom.Triggers"/>) round-trip through the SQLite provider with **no** value
/// converter, **no** <c>HasColumnType</c> and **no** <c>ValueComparer</c>. If a later change
/// pins a provider-specific column type (e.g. <c>text[]</c> or <c>jsonb</c>), that literal leaks
/// into SQLite's <c>CREATE TABLE</c> and this suite is the first thing that breaks — which is the
/// point, because every unit test in the repo builds the whole model on SQLite.
/// </summary>
public sealed class SymptomSqliteModelTests : IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly Guid _userId = Guid.NewGuid();
    private static readonly DateTimeOffset Now = new(2026, 8, 6, 9, 30, 0, TimeSpan.Zero);

    public SymptomSqliteModelTests()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        using var db = NewContext();
        db.Database.EnsureCreated();
        db.Users.Add(new User
        {
            Id = _userId,
            EmailHash = "vault:v1:symptom-sqlite-model-tests",
            Locale = "es-ES",
            Timezone = "Europe/Madrid",
            CreatedAt = Now,
            UpdatedAt = Now,
        });
        db.SaveChanges();
    }

    public void Dispose() => _connection.Dispose();

    private LumenDbContext NewContext() =>
        new(new DbContextOptionsBuilder<LumenDbContext>().UseSqlite(_connection).Options);

    private Symptom NewSymptom(List<string> painTypes, List<string> triggers) => new()
    {
        Id = Guid.NewGuid(),
        UserId = _userId,
        SymptomCode = Symptom.Codes.Pain,
        Intensity = 7,
        Region = Symptom.Regions.LowerAbdomen,
        Side = Symptom.Sides.Front,
        PainTypes = painTypes,
        Triggers = triggers,
        OccurredAt = Now,
        OccurredOn = new DateOnly(2026, 8, 6),
        CreatedAt = Now,
        UpdatedAt = Now,
    };

    [Fact]
    public void PainTypes_and_Triggers_round_trip_as_plain_string_lists()
    {
        var id = Guid.NewGuid();

        using (var write = NewContext())
        {
            var symptom = NewSymptom(["cramping", "sharp"], ["stress"]);
            symptom.Id = id;
            write.Symptoms.Add(symptom);
            write.SaveChanges();
        }

        using var read = NewContext();
        var loaded = read.Symptoms.Single(x => x.Id == id);

        loaded.PainTypes.ShouldBe(["cramping", "sharp"]);
        loaded.Triggers.ShouldBe(["stress"]);
    }

    [Fact]
    public void Empty_collections_round_trip_as_empty_not_null()
    {
        var id = Guid.NewGuid();

        using (var write = NewContext())
        {
            var symptom = NewSymptom([], []);
            symptom.Id = id;
            symptom.SymptomCode = Symptom.NonPainCodes.Bloating;
            symptom.Side = null;
            write.Symptoms.Add(symptom);
            write.SaveChanges();
        }

        using var read = NewContext();
        var loaded = read.Symptoms.Single(x => x.Id == id);

        loaded.PainTypes.ShouldNotBeNull().ShouldBeEmpty();
        loaded.Triggers.ShouldNotBeNull().ShouldBeEmpty();
        loaded.Side.ShouldBeNull();
    }

    [Fact]
    public void The_collection_columns_carry_no_provider_specific_store_type()
    {
        using var db = NewContext();
        var entity = db.Model.FindEntityType(typeof(Symptom)).ShouldNotBeNull();

        // No explicit HasColumnType: the configured store type must be whatever the *provider*
        // chooses, never a hard-coded "text[]"/"jsonb" that SQLite would emit verbatim.
        entity.FindProperty(nameof(Symptom.PainTypes)).ShouldNotBeNull()
            .GetColumnType().ShouldNotBe("text[]");
        entity.FindProperty(nameof(Symptom.Triggers)).ShouldNotBeNull()
            .GetColumnType().ShouldNotBe("text[]");
    }

    [Fact]
    public void OccurredOn_is_a_DateOnly_day_column_and_OccurredAt_is_an_instant()
    {
        using var db = NewContext();
        var entity = db.Model.FindEntityType(typeof(Symptom)).ShouldNotBeNull();

        entity.FindProperty(nameof(Symptom.OccurredOn)).ShouldNotBeNull()
            .ClrType.ShouldBe(typeof(DateOnly));
        entity.FindProperty(nameof(Symptom.OccurredAt)).ShouldNotBeNull()
            .ClrType.ShouldBe(typeof(DateTimeOffset));
    }

    [Fact]
    public void Soft_deleted_symptoms_are_excluded_from_reads()
    {
        var id = Guid.NewGuid();

        using (var write = NewContext())
        {
            var symptom = NewSymptom(["dull"], []);
            symptom.Id = id;
            symptom.DeletedAt = Now;
            write.Symptoms.Add(symptom);
            write.SaveChanges();
        }

        using var read = NewContext();
        read.Symptoms.Any(x => x.Id == id).ShouldBeFalse();
        read.Symptoms.IgnoreQueryFilters().Any(x => x.Id == id).ShouldBeTrue();
    }
}
