using Lumen.Api.Cycle;
using Lumen.Api.Time;
using Lumen.Application.Crypto;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Lumen.UnitTests.Cycle;

/// <summary>
/// <see cref="IUserDayContext"/> frozen at whatever the test hands it — including
/// <see langword="null"/>, the contract that makes a crypto-shredded user's still-valid JWT inert
/// (every P4a write turns it into 404).
/// </summary>
internal sealed class StubUserDayContext(UserDayInfo? info) : IUserDayContext
{
    public Task<UserDayInfo?> GetAsync(CancellationToken ct) => Task.FromResult(info);
}

/// <summary>
/// Real AES-256-GCM (<see cref="AesGcmFieldCipher"/>) over a fixed 32-byte test DEK. Deliberately not
/// a pass-through fake: the notes column must be proven to hold genuine ciphertext of a genuine
/// length, and a fake cipher would make every "is this really encrypted" assertion vacuous. Vault is
/// the only thing stubbed out (the key is a constant instead of an unwrapped DEK).
/// </summary>
internal sealed class TestUserCryptoContext : IUserCryptoContext
{
    private readonly AesGcmFieldCipher _cipher = new();
    private readonly byte[] _dek = Enumerable.Range(0, 32).Select(i => (byte)(i * 7 + 1)).ToArray();

    public Task<byte[]> EncryptAsync(byte[] plaintext, CancellationToken ct = default) =>
        Task.FromResult(_cipher.Encrypt(plaintext, _dek));

    public Task<byte[]> DecryptAsync(byte[] blob, CancellationToken ct = default) =>
        Task.FromResult(_cipher.Decrypt(blob, _dek));

    public Task<byte[]> EncryptStringAsync(string plaintext, CancellationToken ct = default) =>
        Task.FromResult(_cipher.EncryptString(plaintext, _dek));

    public Task<string> DecryptStringAsync(byte[] blob, CancellationToken ct = default) =>
        Task.FromResult(_cipher.DecryptString(blob, _dek));

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}

/// <summary>
/// Shared fixture for the two <c>CycleService</c> suites: a Sqlite in-memory database carrying the
/// real model (kept alive by one open connection), two seeded users so tenant isolation can be
/// asserted, and a factory that hands every service call its OWN <see cref="LumenDbContext"/> —
/// mirroring the scoped-per-request lifetime, and keeping a failed <c>SaveChanges</c> from poisoning
/// the next assertion's change tracker.
/// </summary>
internal sealed class CycleTestHarness : IDisposable
{
    public const string Madrid = "Europe/Madrid";

    /// <summary>The single instant every service call is given, unless a test asks for a later one.</summary>
    public static readonly DateTimeOffset Now = new(2026, 8, 6, 9, 30, 0, TimeSpan.Zero);

    /// <summary>The user's local day at <see cref="Now"/>.</summary>
    public static readonly DateOnly Today = new(2026, 8, 6);

    /// <summary>Account creation − 2 y (§G8). The only floor in P4a, and only <c>cycle_events</c> has it.</summary>
    public static readonly DateOnly Floor = new(2024, 8, 6);

    private readonly SqliteConnection _connection;
    private readonly List<LumenDbContext> _contexts = [];

    public Guid UserId { get; } = Guid.NewGuid();
    public Guid OtherUserId { get; } = Guid.NewGuid();
    public TestUserCryptoContext Crypto { get; } = new();

    public CycleTestHarness()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        using var db = NewOwnedContext();
        db.Database.EnsureCreated();
        db.Users.AddRange(NewUser(UserId), NewUser(OtherUserId));
        db.SaveChanges();
    }

    public void Dispose()
    {
        foreach (var context in _contexts) context.Dispose();
        _connection.Dispose();
    }

    /// <summary>
    /// A context the harness tracks and disposes; use it for arrange/assert reads.
    /// </summary>
    /// <param name="interceptor">
    /// Optional EF interceptor. Only <c>ConcurrencyRecoveryTests</c> passes one — it is how a lost
    /// unique-key race is staged deterministically, without two interleaved requests.
    /// </param>
    public LumenDbContext NewContext(IInterceptor? interceptor = null)
    {
        var db = NewOwnedContext(interceptor);
        _contexts.Add(db);
        return db;
    }

    public UserDayInfo DayInfo(Guid? userId = null, DateTimeOffset? now = null) =>
        new(userId ?? UserId, Today, Floor, Madrid, now ?? Now);

    /// <summary>A service over a fresh context, for the given day info (<see langword="null"/> = erased user).</summary>
    public CycleService NewService(UserDayInfo? info, IInterceptor? interceptor = null) =>
        new(NewContext(interceptor), new StubUserDayContext(info), Crypto);

    /// <summary>A service for the harness's primary user at <see cref="Now"/>.</summary>
    public CycleService NewService() => NewService(DayInfo());

    /// <summary>
    /// A <see cref="CycleDayService"/> over a fresh context (T10), for the given day info
    /// (<see langword="null"/> = erased user). Same lifetime story as <see cref="NewService(UserDayInfo?,IInterceptor?)"/>.
    /// </summary>
    public CycleDayService NewDayService(UserDayInfo? info, IInterceptor? interceptor = null) =>
        new(NewContext(interceptor), new StubUserDayContext(info), Crypto);

    /// <summary>A <see cref="CycleDayService"/> for the harness's primary user at <see cref="Now"/>.</summary>
    public CycleDayService NewDayService() => NewDayService(DayInfo());

    /// <summary>
    /// Seeds a <c>cycle_day_logs</c> row directly. <see cref="CycleDayLog.Energy"/> and
    /// <see cref="CycleDayLog.Libido"/> are settable here even though P4a ships no writer for them
    /// (D-10 defers both scales), because the quick check-in must be proven not to clear columns it
    /// does not own.
    /// </summary>
    public CycleDayLog SeedDayLog(
        DateOnly day,
        Guid? userId = null,
        short? pain = null,
        short? mood = null,
        short? energy = null,
        short? libido = null,
        byte[]? notesEnc = null,
        DateTimeOffset? deletedAt = null)
    {
        var row = new CycleDayLog
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? UserId,
            Day = day,
            Pain = pain,
            Mood = mood,
            Energy = energy,
            Libido = libido,
            NotesEnc = notesEnc,
            CreatedAt = Now,
            UpdatedAt = Now,
            DeletedAt = deletedAt,
        };
        using var db = NewOwnedContext();
        db.CycleDayLogs.Add(row);
        db.SaveChanges();
        return row;
    }

    public CycleEvent SeedEvent(
        string kind,
        DateOnly on,
        Guid? userId = null,
        short? flow = null,
        string? source = null,
        DateTimeOffset? deletedAt = null)
    {
        var row = new CycleEvent
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? UserId,
            Kind = kind,
            OccurredOn = on,
            FlowIntensity = flow,
            Source = source ?? CycleEvent.Sources.User,
            CreatedAt = Now,
            UpdatedAt = Now,
            DeletedAt = deletedAt,
        };
        using var db = NewOwnedContext();
        db.CycleEvents.Add(row);
        db.SaveChanges();
        return row;
    }

    public CyclePhaseOverride SeedOverride(
        DateOnly cycleStartOn,
        string phase,
        string boundary,
        DateOnly occurredOn,
        Guid? userId = null,
        DateTimeOffset? deletedAt = null)
    {
        var row = new CyclePhaseOverride
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? UserId,
            CycleStartOn = cycleStartOn,
            Phase = phase,
            Boundary = boundary,
            OccurredOn = occurredOn,
            Source = CyclePhaseOverride.Sources.UserCorrection,
            CreatedAt = Now,
            UpdatedAt = Now,
            DeletedAt = deletedAt,
        };
        using var db = NewOwnedContext();
        db.CyclePhaseOverrides.Add(row);
        db.SaveChanges();
        return row;
    }

    private LumenDbContext NewOwnedContext(IInterceptor? interceptor = null)
    {
        var options = new DbContextOptionsBuilder<LumenDbContext>().UseSqlite(_connection);
        if (interceptor is not null) options.AddInterceptors(interceptor);
        return new LumenDbContext(options.Options);
    }

    private static User NewUser(Guid id) => new()
    {
        Id = id,
        EmailHash = $"vault:v1:{id:N}",
        Locale = "es-ES",
        Timezone = Madrid,
        CreatedAt = Now.AddYears(-2),
        UpdatedAt = Now.AddYears(-2),
    };
}
