using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Jobs;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for <c>POST /me/devices</c> (T15) — the push-token upsert onto the
/// pre-existing <c>user_devices</c> table.
///
/// <para>Postgres is the only place the <b>unique index on <c>(UserId, PushToken)</c></b> is actually
/// enforced — Sqlite proves the code path, Postgres proves the constraint — and this endpoint is
/// called on every token refresh for the life of an install, so a non-idempotent implementation would
/// 500 on the app's most routine background call. It is also the only place the 404 fencing an erased
/// user's still-valid JWT can be driven end to end. These tests are additionally the phase's guard
/// that the route is <b>wired</b>: a later <c>Program.cs</c> edit that dropped
/// <c>MapDeviceEndpoints()</c> would turn every call below into a 404/405, so the suite cannot stay
/// green with the resource unreachable.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class DeviceRegistrationLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";

    /// <summary>A token shaped like the real thing: long, opaque, and unique per test run.</summary>
    private static string NewToken(string prefix) => $"{prefix}:{Guid.NewGuid():N}{Guid.NewGuid():N}";

    // --- the round trip, and what the response may not carry ---------------------------------------

    [Fact]
    public async Task Registering_a_device_round_trips_and_the_response_never_carries_the_token()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"dev-rt-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var pushToken = NewToken("fcm");

            var response = await authed.PostAsJsonAsync(
                "/me/devices", new { platform = "android", pushToken });

            response.StatusCode.ShouldBe(HttpStatusCode.OK);
            var raw = await response.Content.ReadAsStringAsync();
            raw.ShouldNotContain(pushToken, Case.Sensitive,
                "§F: the token is PII — echoing it puts it in every client log and support HAR file");

            var body = JsonDocument.Parse(raw).RootElement;
            body.GetProperty("platform").GetString().ShouldBe("android");
            body.GetProperty("deviceId").GetGuid().ShouldNotBe(Guid.Empty);
            body.GetProperty("lastSeenAt").ValueKind.ShouldBe(JsonValueKind.String);
            body.GetProperty("createdAt").ValueKind.ShouldBe(JsonValueKind.String);
            body.TryGetProperty("pushToken", out _).ShouldBeFalse();

            await using var db = TestFixtures.NewDb();
            var row = await db.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == userId);
            row.Id.ShouldBe(body.GetProperty("deviceId").GetGuid());
            row.PushToken.ShouldBe(pushToken);
            row.Platform.ShouldBe("android");
            row.LastSeenAt.ShouldNotBeNull();
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- idempotency against the REAL unique index -------------------------------------------------

    [Fact]
    public async Task Re_registering_the_same_token_is_idempotent_against_the_real_unique_index()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"dev-idem-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var pushToken = NewToken("fcm");

            var first = await authed.PostAsJsonAsync("/me/devices", new { platform = "ios", pushToken });
            first.StatusCode.ShouldBe(HttpStatusCode.OK);
            var firstBody = await first.Content.ReadFromJsonAsync<JsonElement>();
            var deviceId = firstBody.GetProperty("deviceId").GetGuid();
            var createdAt = firstBody.GetProperty("createdAt").GetDateTimeOffset();
            var firstSeen = firstBody.GetProperty("lastSeenAt").GetDateTimeOffset();

            // A blind insert here is a 23505 against the real index, surfacing as a 500 — which is what
            // the client would get on every token refresh for the life of the install.
            var second = await authed.PostAsJsonAsync("/me/devices", new { platform = "ios", pushToken });
            second.StatusCode.ShouldBe(HttpStatusCode.OK, "an upsert, never a 409 and never a 500");
            var secondBody = await second.Content.ReadFromJsonAsync<JsonElement>();
            secondBody.GetProperty("deviceId").GetGuid().ShouldBe(deviceId, "the same row, updated in place");

            var secondSeen = secondBody.GetProperty("lastSeenAt").GetDateTimeOffset();
            secondSeen.ShouldBeGreaterThan(firstSeen, "LastSeenAt is what a re-registration is for");

            // A millisecond of tolerance, and only here. The FIRST response projects `createdAt` from
            // the in-memory entity (100-ns ticks); the SECOND reads the row back out of Postgres, whose
            // `timestamptz` is microsecond-precision, so an exact equality compares a truncated value
            // against an untruncated one and fails on a difference of well under a microsecond. The
            // claim being made is unaffected — and the second assertion states it without any
            // tolerance at all: `createdAt` still belongs to the FIRST registration, so it sits
            // strictly before the instant this one was seen.
            var secondCreatedAt = secondBody.GetProperty("createdAt").GetDateTimeOffset();
            secondCreatedAt.ShouldBe(createdAt, TimeSpan.FromMilliseconds(1));
            secondCreatedAt.ShouldBeLessThan(secondSeen, "a re-registration must not re-stamp CreatedAt");

            // A third call from the OTHER platform: still one row, and the platform moves.
            (await authed.PostAsJsonAsync("/me/devices", new { platform = "android", pushToken }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            var rows = await db.UserDevices.AsNoTracking().Where(d => d.UserId == userId).ToListAsync();
            rows.Count.ShouldBe(1, "three registrations of one token are one row");
            rows[0].Id.ShouldBe(deviceId);
            rows[0].Platform.ShouldBe("android");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Two_different_tokens_for_one_user_are_two_rows()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"dev-multi-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var phone = NewToken("fcm");
            var tablet = NewToken("apns");
            (await authed.PostAsJsonAsync("/me/devices", new { platform = "android", pushToken = phone }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.PostAsJsonAsync("/me/devices", new { platform = "ios", pushToken = tablet }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            var rows = await db.UserDevices.AsNoTracking().Where(d => d.UserId == userId).ToListAsync();
            rows.Count.ShouldBe(2, "one account, several devices is the ordinary case");
            rows.Select(d => d.PushToken).OrderBy(t => t, StringComparer.Ordinal)
                .ShouldBe(new[] { phone, tablet }.OrderBy(t => t, StringComparer.Ordinal));
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- a token moving between users --------------------------------------------------------------

    [Fact]
    public async Task A_token_registered_by_a_second_user_is_DETACHED_from_the_first()
    {
        // The device-handover case, against real Postgres. The unique index is (UserId, PushToken), so
        // the database is perfectly happy to hold this token twice — and that state means user A's
        // "your period is predicted to start tomorrow" is delivered to a handset user B is now signed
        // in on. P4a ships no unregister endpoint, so the stale row would be permanent until P9a.
        Guid firstUserId = default;
        Guid secondUserId = default;
        try
        {
            (firstUserId, var firstToken) = await OnboardAndLoginAsync($"dev-hand1-{Guid.NewGuid():N}@example.com");
            (secondUserId, var secondToken) = await OnboardAndLoginAsync($"dev-hand2-{Guid.NewGuid():N}@example.com");
            var pushToken = NewToken("fcm");

            (await Authed(firstToken).PostAsJsonAsync("/me/devices", new { platform = "ios", pushToken }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            var handover = await Authed(secondToken)
                .PostAsJsonAsync("/me/devices", new { platform = "ios", pushToken });
            handover.StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            var rows = await db.UserDevices.AsNoTracking().Where(d => d.PushToken == pushToken).ToListAsync();
            rows.Count.ShouldBe(1, "a push token addresses one install, so it must name one account");
            rows[0].UserId.ShouldBe(secondUserId, "the account that last proved possession owns the device");
            rows[0].Id.ShouldBe((await handover.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("deviceId").GetGuid());
            (await db.UserDevices.CountAsync(d => d.UserId == firstUserId))
                .ShouldBe(0, "the previous owner's row is removed, not left to mis-deliver");
        }
        finally
        {
            if (firstUserId != default) await CleanupAsync(firstUserId);
            if (secondUserId != default) await CleanupAsync(secondUserId);
        }
    }

    [Fact]
    public async Task One_users_other_devices_are_invisible_to_and_untouched_by_another()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"dev-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"dev-int-{Guid.NewGuid():N}@example.com");

            var ownerPhone = NewToken("fcm");
            (await Authed(ownerToken).PostAsJsonAsync(
                "/me/devices", new { platform = "ios", pushToken = ownerPhone })).StatusCode.ShouldBe(HttpStatusCode.OK);

            (await Authed(intruderToken).PostAsJsonAsync(
                "/me/devices", new { platform = "android", pushToken = NewToken("fcm") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            var owner = await db.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == ownerId);
            owner.PushToken.ShouldBe(ownerPhone, "the owner's row must be untouched by another tenant's write");
            (await db.UserDevices.CountAsync(d => d.UserId == intruderId)).ShouldBe(1);
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // --- the one 400 body ---------------------------------------------------------------------------

    [Fact]
    public async Task The_rejections_answer_the_shared_400_and_write_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"dev-400-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var unknownPlatform = await authed.PostAsJsonAsync(
                "/me/devices", new { platform = "web", pushToken = NewToken("fcm") });
            unknownPlatform.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            unknownPlatform.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await unknownPlatform.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            problem.GetProperty("errors").GetProperty("platform")[0].GetString()
                .ShouldBe("value is not one of the allowed values");

            var blankToken = await authed.PostAsJsonAsync("/me/devices", new { platform = "ios", pushToken = "  " });
            blankToken.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await blankToken.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("pushToken")[0].GetString().ShouldBe("value is required");

            var tooLong = await authed.PostAsJsonAsync(
                "/me/devices", new { platform = "ios", pushToken = new string('t', UserDevice.PushTokenMaxLength + 1) });
            tooLong.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await tooLong.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("pushToken")[0].GetString()
                .ShouldBe("text exceeds the maximum length of 512 characters");

            var both = await authed.PostAsJsonAsync("/me/devices", new { platform = (string?)null, pushToken = (string?)null });
            both.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            var bothErrors = (await both.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("errors");
            bothErrors.GetProperty("platform")[0].GetString().ShouldBe("value is required");
            bothErrors.GetProperty("pushToken")[0].GetString().ShouldBe("value is required");

            await using var db = TestFixtures.NewDb();
            (await db.UserDevices.CountAsync(d => d.UserId == userId))
                .ShouldBe(0, "validate-then-act: every rejected request wrote nothing");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the perimeter -------------------------------------------------------------------------------

    [Fact]
    public async Task The_device_route_requires_a_bearer_token()
    {
        var client = factory.CreateClient();

        (await client.PostAsJsonAsync("/me/devices", new { platform = "ios", pushToken = NewToken("fcm") }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_and_registers_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"dev-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync("/me/devices", new { platform = "ios", pushToken = NewToken("fcm") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // The bearer token stays cryptographically valid until it expires; the 404 below is the only
            // thing stopping it from re-creating a device row for an account that no longer exists.
            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            // A body that would otherwise be a 400 still answers "no such user" — the fence is checked
            // before validation, so the shape of the answer leaks nothing.
            var write = await authed.PostAsJsonAsync("/me/devices", new { platform = "web", pushToken = "" });
            write.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            write.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            (await write.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            await using var db = TestFixtures.NewDb();
            (await db.UserDevices.CountAsync(d => d.UserId == userId))
                .ShouldBe(0, "the shred deleted the device row (§F) and the token wrote none back");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- §F: the token never reaches a sink ----------------------------------------------------------

    [Fact]
    public async Task No_log_line_emitted_by_a_registration_carries_the_push_token()
    {
        // The unit suite proves the enricher redacts the DTO field name. THIS proves the claim end to
        // end over real HTTP, where the middleware also attaches RequestPath, the route template and a
        // status code — the whole set of properties a registration actually emits.
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"dev-log-{Guid.NewGuid():N}@example.com");
            var pushToken = NewToken("fcm");

            var events = await CaptureAsync(async () =>
            {
                var response = await Authed(token).PostAsJsonAsync(
                    "/me/devices", new { platform = "ios", pushToken });
                response.StatusCode.ShouldBe(HttpStatusCode.OK);
            });

            events.Length.ShouldBeGreaterThan(0, "the request-completion event must have been captured");
            foreach (var rendered in events.Select(e => e.RenderMessage()))
                rendered.ShouldNotContain(pushToken, Case.Sensitive);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // ------------------------------------------------------------------ helpers

    private sealed class CapturingSink : ILogEventSink
    {
        private readonly object _gate = new();
        private readonly List<LogEvent> _events = [];

        public void Emit(LogEvent logEvent)
        {
            lock (_gate) _events.Add(logEvent);
        }

        public LogEvent[] Snapshot()
        {
            lock (_gate) return [.. _events];
        }
    }

    /// <summary>
    /// Serilog's request-logging middleware writes through the STATIC <see cref="Log.Logger"/>
    /// (<c>RequestLoggingOptions.Logger</c> is never set by <c>Program.cs</c>), so swapping that for
    /// the duration of one request is what makes the emitted events observable. This assembly disables
    /// xUnit parallelization, so the swap cannot race another test.
    /// </summary>
    private async Task<LogEvent[]> CaptureAsync(Func<Task> act)
    {
        _ = factory.CreateClient(); // building the host is what assigns Log.Logger in the first place

        var sink = new CapturingSink();
        using var capture = new LoggerConfiguration().MinimumLevel.Verbose().WriteTo.Sink(sink).CreateLogger();

        var previous = Log.Logger;
        Log.Logger = capture;
        try
        {
            await act();
        }
        finally
        {
            Log.Logger = previous;
        }

        return sink.Snapshot();
    }

    private HttpClient Authed(string token)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private async Task<(Guid userId, string token)> OnboardAndLoginAsync(string email)
    {
        var client = factory.CreateClient();
        var start = await client.PostAsJsonAsync("/onboarding/start", new
        {
            email,
            password = Password,
            displayName = "Device Tester",
            locale = "es-ES",
            timezone = "Europe/Madrid",
            policyVersion = "v1-test",
        });
        start.StatusCode.ShouldBe(HttpStatusCode.OK);
        var userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();
        return (userId, await TestFixtures.GetUserTokenAsync(email, Password));
    }

    private static async Task CleanupAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
