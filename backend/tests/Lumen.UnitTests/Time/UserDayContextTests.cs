using Lumen.Api.Time;
using Lumen.Application.Auth;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Persistence;
using Lumen.Infrastructure.Time;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Logging.Abstractions;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Time;

/// <summary>
/// The request-scoped half of the D-12 helper — where the load-bearing behaviour lives. DbContext is
/// Sqlite in-memory (kept alive by an open connection for the test's lifetime), matching
/// <c>OnboardingServiceTests</c>. Two contracts are pinned here that every P4a endpoint depends on:
/// the <c>User</c> soft-delete query filter is HONOURED (a crypto-shredded user resolves to null, so
/// their still-valid JWT yields 404), and the users row is read exactly once per request scope.
/// </summary>
public sealed class UserDayContextTests : IDisposable
{
    private const string Madrid = "Europe/Madrid";
    private const string LosAngeles = "America/Los_Angeles";

    /// <summary>23:30Z on 2028-03-15 — already the 16th in Madrid, still the 15th in UTC and in LA.</summary>
    private static readonly DateTimeOffset Now = new(2028, 3, 15, 23, 30, 0, TimeSpan.Zero);

    private static readonly DateTimeOffset CreatedAt = new(2027, 1, 10, 12, 0, 0, TimeSpan.Zero);

    private readonly SqliteConnection _connection;
    private readonly LumenDbContext _db;
    private readonly List<string> _commands = [];

    public UserDayContextTests()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();
        var options = new DbContextOptionsBuilder<LumenDbContext>()
            .UseSqlite(_connection)
            .LogTo(_commands.Add, new[] { RelationalEventId.CommandExecuted })
            .Options;
        _db = new LumenDbContext(options);
        _db.Database.EnsureCreated();
        _commands.Clear(); // schema creation is not part of what these tests count
    }

    public void Dispose()
    {
        _db.Dispose();
        _connection.Dispose();
    }

    // --- helpers -------------------------------------------------------------------

    private UserDayContext CreateSut(Guid userId) => new(
        new StubCurrentUser(userId),
        _db,
        new UserDayResolver(new FixedTimeProvider(Now), NullLogger<UserDayResolver>.Instance),
        new FixedTimeProvider(Now));

    private async Task<Guid> SeedUserAsync(string timezone, DateTimeOffset createdAt, DateTimeOffset? deletedAt = null)
    {
        var id = Guid.NewGuid();
        _db.Users.Add(new User
        {
            Id = id,
            EmailHash = $"vault:v1:{id:N}",
            Locale = "es-ES",
            Timezone = timezone,
            CreatedAt = createdAt,
            UpdatedAt = createdAt,
            DeletedAt = deletedAt,
        });
        await _db.SaveChangesAsync();
        _db.ChangeTracker.Clear();
        _commands.Clear(); // seeding is not part of what these tests count
        return id;
    }

    private sealed class StubCurrentUser(Guid userId) : ICurrentUserAccessor
    {
        public bool IsAuthenticated => true;
        public Guid UserId => userId;
    }

    // --- happy path ----------------------------------------------------------------

    [Fact]
    public async Task Live_user_resolves_to_a_populated_UserDayInfo()
    {
        var userId = await SeedUserAsync(Madrid, CreatedAt);

        var info = await CreateSut(userId).GetAsync(CancellationToken.None);

        info.ShouldNotBeNull();
        info.UserId.ShouldBe(userId);
        info.TimezoneId.ShouldBe(Madrid);
        info.NowUtc.ShouldBe(Now);
        info.Today.ShouldBe(new DateOnly(2028, 3, 16));
        info.BackdateFloor.ShouldBe(new DateOnly(2025, 1, 10));
    }

    [Fact]
    public async Task Today_is_the_user_local_day_not_the_UTC_day()
    {
        var madridUser = await SeedUserAsync(Madrid, CreatedAt);
        var losAngelesUser = await SeedUserAsync(LosAngeles, CreatedAt);

        var madrid = await CreateSut(madridUser).GetAsync(CancellationToken.None);
        var losAngeles = await CreateSut(losAngelesUser).GetAsync(CancellationToken.None);

        // One instant, two users, two different "today"s — the whole point of D-12.
        madrid.ShouldNotBeNull().Today.ShouldBe(new DateOnly(2028, 3, 16));
        losAngeles.ShouldNotBeNull().Today.ShouldBe(new DateOnly(2028, 3, 15));
    }

    [Fact]
    public async Task BackdateFloor_is_two_years_before_the_user_local_creation_day_including_the_29_February_clamp()
    {
        // 2028-03-01T02:30Z is still 2028-02-29 (18:30 PST) in Los Angeles. Two years before that
        // user-local day would be 2026-02-29, which does not exist, so it clamps to 2026-02-28.
        // Deriving the floor from the UTC day instead would have produced 2026-03-01 — this single
        // fixture pins BOTH the timezone-correctness and the leap-day clamp.
        var userId = await SeedUserAsync(LosAngeles, new DateTimeOffset(2028, 3, 1, 2, 30, 0, TimeSpan.Zero));

        var info = await CreateSut(userId).GetAsync(CancellationToken.None);

        info.ShouldNotBeNull();
        info.BackdateFloor.ShouldBe(new DateOnly(2026, 2, 28));
        info.BackdateFloor.ShouldNotBe(new DateOnly(2026, 3, 1)); // the UTC-derived wrong answer
    }

    // --- the null contract (=> 404 at every P4a endpoint) ---------------------------

    [Fact]
    public async Task Soft_deleted_user_resolves_to_null_so_a_shredded_users_token_stops_working()
    {
        var userId = await SeedUserAsync(Madrid, CreatedAt, deletedAt: new DateTimeOffset(2028, 1, 1, 0, 0, 0, TimeSpan.Zero));

        var info = await CreateSut(userId).GetAsync(CancellationToken.None);

        info.ShouldBeNull();
        // Negative control: the row IS present. It is the query filter that hides it, so this test
        // fails the moment someone "helpfully" adds IgnoreQueryFilters() to UserDayContext.
        (await _db.Users.IgnoreQueryFilters().CountAsync(u => u.Id == userId)).ShouldBe(1);
    }

    [Fact]
    public async Task Unknown_user_resolves_to_null_and_the_miss_is_memoised()
    {
        var sut = CreateSut(Guid.NewGuid());

        (await sut.GetAsync(CancellationToken.None)).ShouldBeNull();
        (await sut.GetAsync(CancellationToken.None)).ShouldBeNull();

        _commands.Count.ShouldBe(1);
    }

    // --- one read per scope ---------------------------------------------------------

    [Fact]
    public async Task Two_calls_in_one_scope_issue_a_single_query()
    {
        var userId = await SeedUserAsync(Madrid, CreatedAt);
        var sut = CreateSut(userId);

        var first = await sut.GetAsync(CancellationToken.None);
        var second = await sut.GetAsync(CancellationToken.None);

        first.ShouldNotBeNull();
        second.ShouldBeSameAs(first);
        _commands.Count.ShouldBe(1);
    }
}
