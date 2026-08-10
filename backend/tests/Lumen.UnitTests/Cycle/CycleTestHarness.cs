using Lumen.Api.Cycle;
using Lumen.Api.CycleSettings;
using Lumen.Api.Devices;
using Lumen.Api.Symptoms;
using Lumen.Api.Time;
using Lumen.Application.Crypto;
using Lumen.Application.Time;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Crypto;
using Lumen.Infrastructure.Persistence;
using Lumen.Infrastructure.Time;
using Lumen.UnitTests.Time;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using Microsoft.Extensions.Logging.Abstractions;

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
/// Makes every <see cref="DateTimeOffset"/> column <b>sortable on Sqlite</b>, which the provider
/// otherwise refuses: <c>ORDER BY</c> on a <c>DateTimeOffset</c> throws
/// <c>NotSupportedException</c> because the default mapping is text carrying an offset, and
/// lexicographic order over mixed offsets is wrong.
/// </summary>
/// <remarks>
/// <b>This is a TEST-PROVIDER workaround and must stay one.</b> Postgres stores these columns as
/// <c>timestamptz</c> and orders them natively, so <c>GET /symptoms</c>'s
/// <c>ORDER BY OccurredAt DESC, Id DESC</c> (T12) is correct in production; degrading that query to
/// something Sqlite can sort — dropping to day granularity, say — would reorder a user's history to
/// suit a database the app never runs on. Applying the converter here instead keeps the real query
/// under test on the real model, and leaves <c>LumenDbContext</c> with no knowledge of the unit
/// suite's provider.
///
/// <para><b>Cost, stated so it cannot surprise anyone:</b>
/// <see cref="DateTimeOffsetToBinaryConverter"/> round-trips to <b>millisecond</b> precision. Every
/// instant this harness deals in comes from <see cref="CycleTestHarness.Now"/> or an offset of it, all
/// whole seconds, so nothing is lost today — but a future test asserting tick-precision equality on a
/// round-tripped timestamp would fail here and nowhere else.</para>
/// </remarks>
internal sealed class SqliteSortableTimestamps(ModelCustomizerDependencies dependencies)
    : ModelCustomizer(dependencies)
{
    public override void Customize(ModelBuilder modelBuilder, DbContext context)
    {
        base.Customize(modelBuilder, context); // runs LumenDbContext.OnModelCreating first

        var timestamps = modelBuilder.Model.GetEntityTypes()
            .SelectMany(entity => entity.GetProperties())
            .Where(p => p.ClrType == typeof(DateTimeOffset) || p.ClrType == typeof(DateTimeOffset?));

        foreach (var property in timestamps) property.SetValueConverter(new DateTimeOffsetToBinaryConverter());
    }
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

    /// <summary>
    /// The REAL <see cref="UserDayResolver"/> over a clock frozen at <see cref="Now"/> (T11). Not a
    /// stub: <c>occurredAt → occurredOn</c> is the one D-12 conversion a symptom write performs, and a
    /// fake that echoed the UTC date back would make every user-local-day assertion below vacuous.
    /// </summary>
    public IUserDayResolver DayResolver { get; } =
        new UserDayResolver(new FixedTimeProvider(Now), NullLogger<UserDayResolver>.Instance);

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

    /// <summary>
    /// A day context for the given user and instant. <paramref name="today"/> is separate from
    /// <paramref name="now"/> on purpose: <see cref="Today"/> is a fixed constant here, so a test that
    /// only advanced <paramref name="now"/> would leave the user's calendar day unchanged and could not
    /// observe anything day-keyed moving (T14's pause spans close on the user's TODAY, not on an
    /// instant). Supply both when the point of the test is that a later day behaves differently.
    /// </summary>
    public UserDayInfo DayInfo(Guid? userId = null, DateTimeOffset? now = null, DateOnly? today = null) =>
        new(userId ?? UserId, today ?? Today, Floor, Madrid, now ?? Now);

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
    /// A <see cref="CycleCalendarService"/> over a fresh context (T13), for the given day info
    /// (<see langword="null"/> = erased user). It takes NO <see cref="IUserCryptoContext"/> on
    /// purpose — the calendar decrypts no <c>*_enc</c> column, and the missing dependency is what
    /// keeps it that way.
    /// </summary>
    public CycleCalendarService NewCalendarService(UserDayInfo? info) =>
        new(NewContext(), new StubUserDayContext(info));

    /// <summary>A <see cref="CycleCalendarService"/> for the harness's primary user at <see cref="Now"/>.</summary>
    public CycleCalendarService NewCalendarService() => NewCalendarService(DayInfo());

    /// <summary>
    /// A <see cref="SymptomService"/> over a fresh context (T11), for the given day info
    /// (<see langword="null"/> = erased user). Same lifetime story as the two above; it additionally
    /// takes <see cref="DayResolver"/>, which is what turns a client instant into the user's day.
    /// </summary>
    public SymptomService NewSymptomService(UserDayInfo? info) =>
        new(NewContext(), new StubUserDayContext(info), Crypto, DayResolver);

    /// <summary>A <see cref="SymptomService"/> for the harness's primary user at <see cref="Now"/>.</summary>
    public SymptomService NewSymptomService() => NewSymptomService(DayInfo());

    /// <summary>
    /// A <see cref="CycleSettingsService"/> over a fresh context (T14), for the given day info
    /// (<see langword="null"/> = erased user). It takes NO <see cref="IUserCryptoContext"/>: every
    /// column on <c>user_cycle_settings</c> is plaintext by design (§D — the P6 estimator queries
    /// them in SQL), so there is nothing here to encrypt and the missing dependency keeps it that way.
    /// </summary>
    /// <remarks>
    /// Tests that need to reach the service's OWN context — the composability guards around
    /// <c>ApplyOnboardingCycleAsync</c> — construct it directly over <see cref="NewContext"/> instead,
    /// because staging a foreign write on the same context is the whole point of those assertions.
    /// </remarks>
    public CycleSettingsService NewCycleSettingsService(UserDayInfo? info) =>
        new(NewContext(), new StubUserDayContext(info));

    /// <summary>A <see cref="CycleSettingsService"/> for the harness's primary user at <see cref="Now"/>.</summary>
    public CycleSettingsService NewCycleSettingsService() => NewCycleSettingsService(DayInfo());

    /// <summary>
    /// A <see cref="DeviceRegistrationService"/> over a fresh context (T15), for the given day info
    /// (<see langword="null"/> = erased user). It takes NO <see cref="IUserCryptoContext"/>:
    /// <c>user_devices.push_token</c> is stored in plaintext (at-rest encryption is an open P9a
    /// precondition, out of scope here), so there is nothing on this path to encrypt.
    /// </summary>
    /// <remarks>
    /// Tests that need to reach the service's OWN context — the composability guards around
    /// <c>StageRegistrationAsync</c> — construct it directly over <see cref="NewContext"/> instead,
    /// because staging a foreign write on the same context is the whole point of those assertions.
    /// </remarks>
    public DeviceRegistrationService NewDeviceRegistrationService(UserDayInfo? info, IInterceptor? interceptor = null) =>
        new(NewContext(interceptor), new StubUserDayContext(info));

    /// <summary>A <see cref="DeviceRegistrationService"/> for the harness's primary user at <see cref="Now"/>.</summary>
    public DeviceRegistrationService NewDeviceRegistrationService() => NewDeviceRegistrationService(DayInfo());

    /// <summary>
    /// Seeds a <c>user_devices</c> row directly (T15). <paramref name="lastSeenAt"/> defaults to
    /// <see langword="null"/> — the state a row written before this endpoint existed is in — so a test
    /// can prove the upsert stamps it rather than inheriting a value the seed already set.
    /// </summary>
    public UserDevice SeedDevice(
        string pushToken,
        string? platform = null,
        Guid? userId = null,
        DateTimeOffset? lastSeenAt = null,
        DateTimeOffset? createdAt = null)
    {
        var row = new UserDevice
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? UserId,
            Platform = platform ?? UserDevice.Platforms.Ios,
            PushToken = pushToken,
            LastSeenAt = lastSeenAt,
            CreatedAt = createdAt ?? Now.AddDays(-30),
        };
        using var db = NewOwnedContext();
        db.UserDevices.Add(row);
        db.SaveChanges();
        return row;
    }

    /// <summary>
    /// Seeds a <c>symptoms</c> row directly, for tenant-isolation, list-ordering and no-op assertions.
    /// </summary>
    /// <remarks>
    /// Every classification field is settable (T12) because the replace surface must be proven to
    /// CLEAR each one, and a row seeded with everything null could not tell a clear from a no-op.
    /// <paramref name="occurredAt"/> defaults to <see cref="Now"/> rather than being derived from
    /// <paramref name="occurredOn"/>: the list orders by the instant and tie-breaks on the id, so the
    /// paging tests need several rows to share one instant while sitting on different days.
    /// </remarks>
    public Symptom SeedSymptom(
        string symptomCode,
        short intensity,
        DateOnly occurredOn,
        Guid? userId = null,
        DateTimeOffset? occurredAt = null,
        string? region = null,
        string? side = null,
        IEnumerable<string>? painTypes = null,
        IEnumerable<string>? triggers = null,
        byte[]? notesEnc = null,
        DateTimeOffset? deletedAt = null)
    {
        var row = new Symptom
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? UserId,
            SymptomCode = symptomCode,
            Intensity = intensity,
            Region = region ?? Symptom.Regions.Default,
            Side = side,
            PainTypes = painTypes?.ToList() ?? [],
            Triggers = triggers?.ToList() ?? [],
            OccurredAt = occurredAt ?? Now,
            OccurredOn = occurredOn,
            NotesEnc = notesEnc,
            CreatedAt = Now,
            UpdatedAt = Now,
            DeletedAt = deletedAt,
        };
        using var db = NewOwnedContext();
        db.Symptoms.Add(row);
        db.SaveChanges();
        return row;
    }

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

    /// <summary>
    /// Seeds the user's <c>user_cycle_settings</c> row directly (T14). Every column is settable so a
    /// test can arrange a state the endpoint would not itself produce — a divergent pause triple, a
    /// self-report outside the sanity band — which is what makes the reconciliation assertions real.
    /// </summary>
    public UserCycleSettings SeedCycleSettings(
        Guid? userId = null,
        short avgCycleLengthDays = UserCycleSettings.DefaultAvgCycleLengthDays,
        short? avgPeriodLengthDays = null,
        string? regularity = null,
        bool phasePredictionEnabled = true,
        bool autoDetectPeriodStartEnabled = true,
        bool showFertilityWindowEnabled = false,
        bool trackingPaused = false,
        string? pauseReason = null,
        DateOnly? pausedSince = null)
    {
        var row = new UserCycleSettings
        {
            UserId = userId ?? UserId,
            AvgCycleLengthDays = avgCycleLengthDays,
            AvgPeriodLengthDays = avgPeriodLengthDays,
            Regularity = regularity ?? UserCycleSettings.RegularityValues.Default,
            PhasePredictionEnabled = phasePredictionEnabled,
            AutoDetectPeriodStartEnabled = autoDetectPeriodStartEnabled,
            ShowFertilityWindowEnabled = showFertilityWindowEnabled,
            TrackingPaused = trackingPaused,
            PauseReason = pauseReason,
            PausedSince = pausedSince,
            CreatedAt = Now,
            UpdatedAt = Now,
        };
        using var db = NewOwnedContext();
        db.CycleSettings.Add(row);
        db.SaveChanges();
        return row;
    }

    /// <summary>
    /// Seeds one <c>cycle_tracking_pause_spans</c> row directly (T14). <paramref name="endedOn"/> null
    /// is an OPEN span — at most one per user, enforced by the partial unique index.
    /// </summary>
    public CycleTrackingPauseSpan SeedPauseSpan(
        string reason,
        DateOnly startedOn,
        DateOnly? endedOn = null,
        Guid? userId = null)
    {
        var row = new CycleTrackingPauseSpan
        {
            Id = Guid.NewGuid(),
            UserId = userId ?? UserId,
            Reason = reason,
            StartedOn = startedOn,
            EndedOn = endedOn,
            CreatedAt = Now,
            UpdatedAt = Now,
        };
        using var db = NewOwnedContext();
        db.CycleTrackingPauseSpans.Add(row);
        db.SaveChanges();
        return row;
    }

    private LumenDbContext NewOwnedContext(IInterceptor? interceptor = null)
    {
        var options = new DbContextOptionsBuilder<LumenDbContext>()
            .UseSqlite(_connection)
            // See SqliteSortableTimestamps: without it, ORDER BY on a DateTimeOffset throws on Sqlite
            // and GET /symptoms could not be unit-tested at all.
            .ReplaceService<IModelCustomizer, SqliteSortableTimestamps>();

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
