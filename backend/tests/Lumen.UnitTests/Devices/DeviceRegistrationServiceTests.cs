using Lumen.Api.Devices;
using Lumen.Api.Persistence;
using Lumen.Domain.Entities;
using Lumen.Domain.Reference;
using Lumen.Infrastructure.Logging;
using Lumen.UnitTests.Cycle;
using Microsoft.EntityFrameworkCore;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Devices;

/// <summary>
/// <c>POST /me/devices</c> (T15): the push-token upsert onto the pre-existing <c>user_devices</c>
/// table (migration <c>20260614150634</c> — §G4/§G14 forbid a new one).
/// </summary>
/// <remarks>
/// <para>Four claims dominate this file.</para>
///
/// <para><b>1. Re-registering the same <c>(userId, pushToken)</c> is IDEMPOTENT.</b> This endpoint is
/// called on every token refresh for the life of an install, so "one more row each time" would grow a
/// table with a unique index on exactly that pair — i.e. it would 500. One row, <c>LastSeenAt</c>
/// advanced, 200 both times, the same <c>Id</c> back. Sqlite carries the same unique index here;
/// <c>DeviceRegistrationLiveTests</c> re-proves it where Postgres actually enforces it.</para>
///
/// <para><b>2. Registering a token DETACHES it from every OTHER user.</b> The index is
/// <c>(UserId, PushToken)</c>, so the database would happily hold the same token for two accounts —
/// and that state is a push notification about one user's cycle delivered to the phone another user
/// is now signed in on. See <see cref="DeviceRegistrationService"/>'s remarks for the full argument
/// and what it obliges P9a to do.</para>
///
/// <para><b>3. <see cref="DeviceRegistrationService.StageRegistrationAsync"/> must stay COMPOSABLE</b>
/// (§G12's unit-of-work rule). T17's <c>POST /onboarding/notifications</c> reuses this service while
/// also writing <c>user_notification_prefs</c> rows, so the staging method must stage only — a
/// <c>SaveChangesAsync</c>, a <c>ChangeTracker.Clear()</c> or a <see cref="ConcurrencyRetry"/> inside
/// it would silently discard T17's other write with no exception and no failing test. Two tests below
/// fail the moment any of those is added.</para>
///
/// <para><b>4. The push token never leaves the row.</b> It is not on the response DTO and it is
/// redacted out of any log line. Both are asserted here rather than assumed.</para>
/// </remarks>
public class DeviceRegistrationServiceTests : IDisposable
{
    private const string TokenA = "fcm-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private const string TokenB = "apns-token-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    private readonly CycleTestHarness _harness = new();

    public void Dispose()
    {
        _harness.Dispose();
        GC.SuppressFinalize(this);
    }

    // ============================================================== the happy path

    [Theory]
    [InlineData("ios")]
    [InlineData("android")]
    public async Task Registering_a_device_creates_one_row_on_each_ratified_platform(string platform)
    {
        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(platform, TokenA), default);

        var device = result.ShouldBeOfType<DeviceRegistrationResult.Saved>().Device;
        device.Platform.ShouldBe(platform);
        device.LastSeenAt.ShouldBe(CycleTestHarness.Now);
        device.CreatedAt.ShouldBe(CycleTestHarness.Now);

        await using var db = _harness.NewContext();
        var row = await db.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == _harness.UserId);
        row.Id.ShouldBe(device.DeviceId);
        row.Platform.ShouldBe(platform);
        row.PushToken.ShouldBe(TokenA);
        row.LastSeenAt.ShouldBe(CycleTestHarness.Now);
    }

    [Fact]
    public async Task The_response_never_carries_the_push_token_in_any_form()
    {
        // §F: the token is PII (T8 redacts the field name and the crypto-shred hard-deletes the row).
        // Echoing it back would put it in every client log, every proxy trace and every HAR file a
        // support ticket carries — for no gain, since the caller already holds it.
        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, TokenA), default);

        var device = result.ShouldBeOfType<DeviceRegistrationResult.Saved>().Device;

        var names = typeof(RegisterDeviceResponse).GetProperties().Select(p => p.Name).ToList();
        names.ShouldNotContain("PushToken");
        names.ShouldNotContain("Token");

        // Belt and braces: no member's VALUE carries it either (a stringly-typed echo under another
        // name would pass the reflection check above and still leak).
        foreach (var value in typeof(RegisterDeviceResponse).GetProperties()
                     .Select(p => p.GetValue(device)?.ToString())
                     .Where(v => v is not null)
                     .Cast<string>())
        {
            value.ShouldNotContain(TokenA);
        }
    }

    // ============================================================== idempotency

    [Fact]
    public async Task The_same_token_twice_is_ONE_row_with_LastSeenAt_advanced()
    {
        // The whole reason this endpoint is an upsert: the client calls it on EVERY token refresh for
        // the life of the install. An append would violate the unique index on (UserId, PushToken)
        // the second time and surface as a 500 on the app's most routine background call.
        var first = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, TokenA), default);
        var firstDevice = first.ShouldBeOfType<DeviceRegistrationResult.Saved>().Device;

        var later = CycleTestHarness.Now.AddDays(30);
        var second = await _harness
            .NewDeviceRegistrationService(_harness.DayInfo(now: later, today: CycleTestHarness.Today.AddDays(30)))
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, TokenA), default);

        var secondDevice = second.ShouldBeOfType<DeviceRegistrationResult.Saved>().Device;
        secondDevice.DeviceId.ShouldBe(firstDevice.DeviceId, "a re-registration updates the row in place");
        secondDevice.CreatedAt.ShouldBe(CycleTestHarness.Now, "CreatedAt belongs to the first registration");
        secondDevice.LastSeenAt.ShouldBe(later, "LastSeenAt is what a re-registration is FOR");

        await using var db = _harness.NewContext();
        var rows = await db.UserDevices.AsNoTracking().Where(d => d.UserId == _harness.UserId).ToListAsync();
        rows.Count.ShouldBe(1, "never a duplicate, and never a 409");
        rows[0].LastSeenAt.ShouldBe(later);
    }

    [Fact]
    public async Task Re_registering_the_same_token_from_the_other_platform_moves_the_platform()
    {
        // A restore of an iOS backup onto an Android handset can carry the app's stored token across.
        // Whatever the cause, the row must describe the device that just called — a stale `ios` here
        // sends P9a's dispatcher to the wrong provider and the notification is silently dropped.
        _harness.SeedDevice(TokenA, platform: UserDevice.Platforms.Ios);

        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Android, TokenA), default);

        result.ShouldBeOfType<DeviceRegistrationResult.Saved>().Device.Platform.ShouldBe("android");

        await using var db = _harness.NewContext();
        var rows = await db.UserDevices.AsNoTracking().Where(d => d.UserId == _harness.UserId).ToListAsync();
        rows.Count.ShouldBe(1);
        rows[0].Platform.ShouldBe("android");
    }

    [Fact]
    public async Task A_different_token_for_the_same_user_is_a_SECOND_row()
    {
        // One account, several devices — a phone and a tablet — is the ordinary case, and the reason
        // the unique key is (UserId, PushToken) rather than (UserId).
        var service = _harness.NewDeviceRegistrationService();
        await service.RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, TokenA), default);

        await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Android, TokenB), default);

        await using var db = _harness.NewContext();
        var rows = await db.UserDevices.AsNoTracking()
            .Where(d => d.UserId == _harness.UserId).OrderBy(d => d.Platform).ToListAsync();
        rows.Count.ShouldBe(2);
        rows.Select(d => d.PushToken).ShouldBe([TokenB, TokenA]);
    }

    // ================================================ a token moving between users

    [Fact]
    public async Task Registering_a_token_another_user_holds_DETACHES_it_from_them()
    {
        // THE DECISION THIS TASK OWNS. The unique index is (UserId, PushToken), so the same token can
        // legitimately sit on two rows — and that state means one user's push notifications are
        // delivered to a handset the other user is now signed in on. A push token addresses an app
        // INSTALL, exactly one account is signed in on an install at a time, and P4a ships no
        // unregister endpoint at all, so a row left behind here is permanent until P9a. Detaching is
        // therefore the only way P4a can keep a cycle notification off the wrong person's lock screen.
        var theirs = _harness.SeedDevice(TokenA, userId: _harness.OtherUserId);

        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Android, TokenA), default);

        result.ShouldBeOfType<DeviceRegistrationResult.Saved>();

        await using var db = _harness.NewContext();
        var rows = await db.UserDevices.AsNoTracking().Where(d => d.PushToken == TokenA).ToListAsync();
        rows.Count.ShouldBe(1, "a push token addresses one install, so it must name one account");
        rows[0].UserId.ShouldBe(_harness.UserId);
        (await db.UserDevices.AsNoTracking().AnyAsync(d => d.Id == theirs.Id))
            .ShouldBeFalse("the previous owner's row is removed, not left to mis-deliver");
    }

    [Fact]
    public async Task A_detach_leaves_the_other_users_OTHER_devices_alone()
    {
        // The detach is keyed on the TOKEN, never on the user: handing over one phone must not
        // unregister the other tenant's tablet.
        var theirOtherDevice = _harness.SeedDevice(TokenB, userId: _harness.OtherUserId);
        _harness.SeedDevice(TokenA, userId: _harness.OtherUserId);

        await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, TokenA), default);

        await using var db = _harness.NewContext();
        var theirs = await db.UserDevices.AsNoTracking()
            .Where(d => d.UserId == _harness.OtherUserId).ToListAsync();
        theirs.Count.ShouldBe(1);
        theirs[0].Id.ShouldBe(theirOtherDevice.Id);
        theirs[0].PushToken.ShouldBe(TokenB);
    }

    [Fact]
    public async Task A_registration_that_touches_no_shared_token_leaves_every_other_tenant_untouched()
    {
        var theirs = _harness.SeedDevice(TokenB, userId: _harness.OtherUserId);

        await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, TokenA), default);

        await using var db = _harness.NewContext();
        (await db.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == _harness.OtherUserId))
            .Id.ShouldBe(theirs.Id);
        (await db.UserDevices.CountAsync()).ShouldBe(2);
    }

    // ============================================================== validation

    [Fact]
    public async Task An_unknown_platform_is_rejected_and_nothing_is_written()
    {
        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest("web", TokenA), default);

        var errors = result.ShouldBeOfType<DeviceRegistrationResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("platform");
        errors[0].Message.ShouldBe("value is not one of the allowed values");

        await using var db = _harness.NewContext();
        (await db.UserDevices.CountAsync()).ShouldBe(0, "validate-then-act: a rejected request writes nothing");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task A_missing_platform_is_rejected(string? platform)
    {
        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(platform, TokenA), default);

        var errors = result.ShouldBeOfType<DeviceRegistrationResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("platform");
        errors[0].Message.ShouldBe("value is required");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task A_blank_push_token_is_rejected(string? pushToken)
    {
        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, pushToken), default);

        var errors = result.ShouldBeOfType<DeviceRegistrationResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("pushToken");
        errors[0].Message.ShouldBe("value is required");

        await using var db = _harness.NewContext();
        (await db.UserDevices.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task A_513_character_push_token_is_rejected_and_512_is_accepted()
    {
        // The bound is the EXISTING column's, read off the entity constant rather than retyped —
        // 513 characters would be an opaque DbUpdateException instead of a field-scoped 400.
        var tooLong = new string('t', UserDevice.PushTokenMaxLength + 1);

        var rejected = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, tooLong), default);

        var errors = rejected.ShouldBeOfType<DeviceRegistrationResult.Invalid>().Errors;
        errors.Count.ShouldBe(1);
        errors[0].Field.ShouldBe("pushToken");
        errors[0].Message.ShouldBe("text exceeds the maximum length of 512 characters");

        var atTheLimit = new string('t', UserDevice.PushTokenMaxLength);
        var accepted = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, atTheLimit), default);

        accepted.ShouldBeOfType<DeviceRegistrationResult.Saved>();

        await using var db = _harness.NewContext();
        (await db.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == _harness.UserId))
            .PushToken.Length.ShouldBe(UserDevice.PushTokenMaxLength);
    }

    [Fact]
    public async Task A_surrounding_whitespace_only_token_is_measured_and_stored_trimmed()
    {
        // Trim first, then cap — the same rule `notes` follows: a 512-character token wrapped in a
        // trailing newline is a 512-character token, not a 513-character error.
        var token = new string('t', UserDevice.PushTokenMaxLength);

        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest($"  {UserDevice.Platforms.Ios} ", $"\n{token}  "), default);

        result.ShouldBeOfType<DeviceRegistrationResult.Saved>().Device.Platform.ShouldBe("ios");

        await using var db = _harness.NewContext();
        (await db.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == _harness.UserId))
            .PushToken.ShouldBe(token);
    }

    [Fact]
    public async Task Every_field_error_is_collected_before_the_first_write()
    {
        var result = await _harness.NewDeviceRegistrationService()
            .RegisterAsync(new RegisterDeviceRequest("web", null), default);

        var errors = result.ShouldBeOfType<DeviceRegistrationResult.Invalid>().Errors;
        errors.Select(e => e.Field).ShouldBe(["platform", "pushToken"]);

        await using var db = _harness.NewContext();
        (await db.UserDevices.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task A_registration_for_an_erased_user_is_404_BEFORE_validation_and_before_any_write()
    {
        // The order is the security control, not a formality: a crypto-shredded account's JWT stays
        // cryptographically valid until it expires, and there is NO write fence behind erasure — a
        // request in flight would otherwise re-create a device row for a user who no longer exists,
        // one the shred has already run past. A body that would be a 400 must still answer "no such
        // user", or the shape of the answer tells an erased token its request was understood.
        var result = await _harness.NewDeviceRegistrationService(info: null)
            .RegisterAsync(new RegisterDeviceRequest("web", null), default);

        result.ShouldBeOfType<DeviceRegistrationResult.UserNotFound>();

        await using var db = _harness.NewContext();
        (await db.UserDevices.CountAsync()).ShouldBe(0);
    }

    [Fact]
    public async Task An_erased_user_cannot_detach_a_live_users_device_either()
    {
        // The 404 fence runs before the detach, so an erased token cannot use this endpoint as an
        // unregister lever against a live account.
        var theirs = _harness.SeedDevice(TokenA, userId: _harness.OtherUserId);

        var result = await _harness.NewDeviceRegistrationService(info: null)
            .RegisterAsync(new RegisterDeviceRequest(UserDevice.Platforms.Ios, TokenA), default);

        result.ShouldBeOfType<DeviceRegistrationResult.UserNotFound>();

        await using var db = _harness.NewContext();
        (await db.UserDevices.AsNoTracking().SingleAsync()).Id.ShouldBe(theirs.Id);
    }

    // ============================================================== frozen wire strings

    [Fact]
    public void The_platform_codes_are_frozen()
    {
        // §G12: an endpoint-specific wire string is asserted VERBATIM against its literal, never
        // through the constant — an assertion routed through the constant renames with it.
        UserDevice.Platforms.Ios.ShouldBe("ios");
        UserDevice.Platforms.Android.ShouldBe("android");
        UserDevice.Platforms.All.ShouldBe(["ios", "android"]);
    }

    [Fact]
    public void The_push_token_limit_is_the_existing_columns_512()
    {
        // §G11 is explicit that this is NOT a P4a invention: `push_token varchar(512)` has existed
        // since migration 20260614150634. The constant exists so the validator and the EF
        // configuration state one number; the literal is asserted here so moving it is a decision.
        UserDevice.PushTokenMaxLength.ShouldBe(512);
    }

    // ============================================================== §F — the token never reaches a sink

    [Fact]
    public void The_push_token_is_redacted_out_of_a_log_line_under_the_DTO_spelling()
    {
        // T8 owns `PiiRedactionEnricher` and this task does not touch it — what needs proving here is
        // that THIS task's DTO field name is inside the net T8 already casts, which is not automatic:
        // T8's completeness theory is derived by reflection over the ELEVEN P4a entity types and
        // deliberately EXCLUDES `UserDevice` (it predates P4a), so `pushToken` is covered only by the
        // hand-maintained name list. A rename of the DTO member would slip out of that net silently.
        var sink = new CapturingSink();
        using var logger = new LoggerConfiguration()
            .Enrich.With(new PiiRedactionEnricher())
            .WriteTo.Sink(sink)
            .CreateLogger();

        logger.Information(
            "device registered {@Request} {PushToken} {pushToken}",
            new RegisterDeviceRequest(UserDevice.Platforms.Ios, TokenA),
            TokenA,
            TokenA);

        var rendered = sink.Events.Single().RenderMessage();
        rendered.ShouldNotContain(TokenA, Case.Sensitive);
        rendered.ShouldContain("[redacted]");
        rendered.ShouldContain("ios", Case.Sensitive, "the platform is not PII and must stay legible");
    }

    // ============================ StageRegistrationAsync (shared with T17)

    [Fact]
    public async Task StageRegistrationAsync_STAGES_ONLY_so_T17_can_compose_it_with_another_write()
    {
        // §G12's unit-of-work rule, enforced rather than documented. `ConcurrencyRetry` recovers via
        // `ChangeTracker.Clear()`, a WHOLE-CONTEXT operation on the request-scoped LumenDbContext, so
        // a `SaveChangesAsync`, a `Clear()` or a retry of its own inside this method would silently
        // discard whatever T17 staged alongside it — no exception, no failing test. THIS is that test:
        // it stages a user_notification_prefs row first (T17's other write), calls the method, and
        // fails if either write is lost.
        await using var db = _harness.NewContext();
        var service = new DeviceRegistrationService(db, new StubUserDayContext(_harness.DayInfo()));

        var stagedPref = new UserNotificationPref
        {
            Id = Guid.NewGuid(),
            UserId = _harness.UserId,
            CategoryCode = HormoneCatalog.NotificationCategories.DailyCheckin,
            Enabled = true,
            CreatedAt = CycleTestHarness.Now,
            UpdatedAt = CycleTestHarness.Now,
        };
        db.UserNotificationPrefs.Add(stagedPref);

        await service.StageRegistrationAsync(
            _harness.UserId, UserDevice.Platforms.Ios, TokenA, CycleTestHarness.Now, default);

        // 1. It did not save: nothing is in the database yet, not even the device row.
        await using (var beforeSave = _harness.NewContext())
        {
            (await beforeSave.UserDevices.CountAsync()).ShouldBe(
                0, "StageRegistrationAsync must not call SaveChangesAsync — the caller owns the save");
            (await beforeSave.UserNotificationPrefs.CountAsync()).ShouldBe(0);
        }

        // 2. It did not clear the tracker: T17's staged row is still there, still Added.
        db.Entry(stagedPref).State.ShouldBe(
            EntityState.Added,
            "StageRegistrationAsync must not call ChangeTracker.Clear() (nor ConcurrencyRetry, " +
            "which clears): doing so silently discards the caller's other staged write");

        // 3. One save lands both.
        await db.SaveChangesAsync();

        await using var read = _harness.NewContext();
        (await read.UserNotificationPrefs.CountAsync(p => p.UserId == _harness.UserId))
            .ShouldBe(1, "T17's notification-preference row survived the composition");
        (await read.UserDevices.CountAsync(d => d.UserId == _harness.UserId)).ShouldBe(1);
    }

    [Fact]
    public async Task StageRegistrationAsync_stages_the_cross_user_detach_rather_than_executing_it()
    {
        // The detach must be a TRACKED delete, not `ExecuteDeleteAsync`. ExecuteDelete issues its own
        // statement outside the caller's SaveChanges transaction, so a composed unit of work that
        // failed afterwards would have already unregistered the other user's device — a partial write
        // with no way back. Staging it means the delete and the insert commit or roll back together.
        var theirs = _harness.SeedDevice(TokenA, userId: _harness.OtherUserId);

        await using var db = _harness.NewContext();
        var service = new DeviceRegistrationService(db, new StubUserDayContext(_harness.DayInfo()));

        await service.StageRegistrationAsync(
            _harness.UserId, UserDevice.Platforms.Ios, TokenA, CycleTestHarness.Now, default);

        await using (var beforeSave = _harness.NewContext())
        {
            // Counted rather than Single()d so an executed delete fails with a readable message
            // ("should be 1 but was 0") instead of "Sequence contains no elements".
            var stillThere = await beforeSave.UserDevices.AsNoTracking().ToListAsync();
            stillThere.Count.ShouldBe(1, "the detach must not have been executed before the caller's save");
            stillThere[0].Id.ShouldBe(theirs.Id);
        }

        await db.SaveChangesAsync();

        await using var read = _harness.NewContext();
        var rows = await read.UserDevices.AsNoTracking().ToListAsync();
        rows.Count.ShouldBe(1);
        rows[0].UserId.ShouldBe(_harness.UserId);
    }

    [Fact]
    public async Task StageRegistrationAsync_composes_inside_ONE_ConcurrencyRetry_action_the_way_T17_will()
    {
        // The shape §G12 prescribes for T17: the ENDPOINT owns exactly one retried action wrapping the
        // whole unit of work, and every participant inside it stages only.
        await using var db = _harness.NewContext();
        var service = new DeviceRegistrationService(db, new StubUserDayContext(_harness.DayInfo()));

        var deviceId = await ConcurrencyRetry.ExecuteAsync(async token =>
        {
            db.ChangeTracker.Clear();

            db.UserNotificationPrefs.Add(new UserNotificationPref
            {
                Id = Guid.NewGuid(),
                UserId = _harness.UserId,
                CategoryCode = HormoneCatalog.NotificationCategories.PhaseShift,
                Enabled = true,
                CreatedAt = CycleTestHarness.Now,
                UpdatedAt = CycleTestHarness.Now,
            });

            var device = await service.StageRegistrationAsync(
                _harness.UserId, UserDevice.Platforms.Android, TokenB, CycleTestHarness.Now, token);

            await db.SaveChangesAsync(token);
            return device.Id;
        }, default);

        await using var read = _harness.NewContext();
        (await read.UserNotificationPrefs.CountAsync(p => p.UserId == _harness.UserId)).ShouldBe(1);
        (await read.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == _harness.UserId))
            .Id.ShouldBe(deviceId);
    }

    [Fact]
    public async Task StageRegistrationAsync_refuses_a_value_its_caller_should_have_rejected()
    {
        // Programming-error guards, not user input: the endpoint owns the 400. Storing an
        // out-of-vocabulary platform would send P9a's dispatcher to a provider that does not exist,
        // and an overlength token would surface as an opaque DbUpdateException from the CALLER's save.
        await using var db = _harness.NewContext();
        var service = new DeviceRegistrationService(db, new StubUserDayContext(_harness.DayInfo()));

        await Should.ThrowAsync<ArgumentException>(async () => await service.StageRegistrationAsync(
            _harness.UserId, "web", TokenA, CycleTestHarness.Now, default));

        await Should.ThrowAsync<ArgumentException>(async () => await service.StageRegistrationAsync(
            _harness.UserId, UserDevice.Platforms.Ios, "   ", CycleTestHarness.Now, default));

        await Should.ThrowAsync<ArgumentException>(async () => await service.StageRegistrationAsync(
            _harness.UserId,
            UserDevice.Platforms.Ios,
            new string('t', UserDevice.PushTokenMaxLength + 1),
            CycleTestHarness.Now,
            default));
    }

    // ------------------------------------------------------------------ helpers

    private sealed class CapturingSink : ILogEventSink
    {
        public List<LogEvent> Events { get; } = [];

        public void Emit(LogEvent logEvent) => Events.Add(logEvent);
    }
}
