using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Jobs;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for the §C.9 cycle-settings resource (T14):
/// <c>GET /settings/cycle</c> and <c>PATCH /settings/cycle</c>.
///
/// <para>Postgres is the only place the <b>partial unique index</b>
/// <c>(UserId) WHERE "EndedOn" IS NULL</c> on <c>cycle_tracking_pause_spans</c> is actually enforced —
/// Sqlite proves the code path, Postgres proves the constraint — and the only place the 404 fencing an
/// erased user's still-valid JWT can be driven end to end. These tests are also the phase's guard that
/// the routes are <b>wired</b>: a later <c>Program.cs</c> edit that dropped
/// <c>MapCycleSettingsEndpoints()</c> would turn every call below into a 404/405, so the suite cannot
/// stay green with the resource unreachable.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class CycleSettingsLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";

    private static DateOnly Today => DateOnly.FromDateTime(
        TimeZoneInfo.ConvertTime(TimeProvider.System.GetUtcNow(), TimeZoneInfo.FindSystemTimeZoneById("Europe/Madrid")).Date);

    // --- the defaults answer, and that it writes nothing ------------------------------------------

    [Fact]
    public async Task Get_answers_the_T6_defaults_for_a_user_with_no_row_and_creates_none()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cs-def-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var response = await authed.GetAsync("/settings/cycle");

            response.StatusCode.ShouldBe(HttpStatusCode.OK, "'no row' is never a 404 — 404 means 'no such user'");
            var body = await response.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("avgCycleLengthDays").GetInt32().ShouldBe(28);
            body.GetProperty("avgPeriodLengthDays").ValueKind.ShouldBe(JsonValueKind.Null);
            body.GetProperty("regularity").GetString().ShouldBe("somewhat");
            body.GetProperty("phasePredictionEnabled").GetBoolean().ShouldBeTrue();
            body.GetProperty("autoDetectPeriodStartEnabled").GetBoolean().ShouldBeTrue();
            body.GetProperty("showFertilityWindowEnabled").GetBoolean().ShouldBeFalse();
            body.GetProperty("trackingPaused").GetBoolean().ShouldBeFalse();
            body.GetProperty("phasesUnavailable").GetBoolean().ShouldBeFalse();
            body.GetProperty("warnings").GetArrayLength().ShouldBe(0);
            body.GetProperty("createdAt").ValueKind.ShouldBe(JsonValueKind.Null);
            body.GetProperty("updatedAt").ValueKind.ShouldBe(JsonValueKind.Null);

            // §G6: no clinical inference reaches the wire, not even as a placeholder key.
            body.TryGetProperty("phase", out _).ShouldBeFalse();
            body.TryGetProperty("cycleDay", out _).ShouldBeFalse();
            body.TryGetProperty("confidence", out _).ShouldBeFalse();
            body.TryGetProperty("hormoneRangeInterpretationEnabled", out _).ShouldBeFalse();

            await using var db = TestFixtures.NewDb();
            (await db.CycleSettings.CountAsync(s => s.UserId == userId))
                .ShouldBe(0, "a GET must not materialise a row");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- §G7: the sanity band never blocks a save, over real HTTP ---------------------------------

    [Fact]
    public async Task A_self_report_the_clinical_bounds_would_refuse_is_accepted_and_persisted()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cs-g7-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            // 15 and 47 are the two values the PO named: both outside the clinician-UNSIGNED clinical
            // band, both inside the sanity band, so both must be 200, STORED and UNWARNED.
            foreach (var days in new[] { 15, 47 })
            {
                var response = await authed.PatchAsJsonAsync("/settings/cycle", new { avgCycleLengthDays = days });
                response.StatusCode.ShouldBe(HttpStatusCode.OK);
                var body = await response.Content.ReadFromJsonAsync<JsonElement>();
                body.GetProperty("avgCycleLengthDays").GetInt32().ShouldBe(days);
                body.GetProperty("warnings").GetArrayLength().ShouldBe(0);

                await using var db = TestFixtures.NewDb();
                (await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == userId))
                    .AvgCycleLengthDays.ShouldBe((short)days);
            }

            // Outside the SANITY band: still 200, still stored, plus one non-blocking warning code.
            var far = await authed.PatchAsJsonAsync(
                "/settings/cycle", new { avgCycleLengthDays = 200, avgPeriodLengthDays = 90 });
            far.StatusCode.ShouldBe(HttpStatusCode.OK);
            var warned = await far.Content.ReadFromJsonAsync<JsonElement>();
            warned.GetProperty("avgCycleLengthDays").GetInt32().ShouldBe(200);
            warned.GetProperty("warnings").EnumerateArray().Select(w => w.GetString()).ShouldBe([
                "avg_cycle_length_out_of_sanity_band",
                "avg_period_length_out_of_sanity_band",
            ]);

            await using (var db = TestFixtures.NewDb())
            {
                var row = await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == userId);
                row.AvgCycleLengthDays.ShouldBe((short)200, "a sanity warning is non-blocking — the value is persisted");
                row.AvgPeriodLengthDays.ShouldBe((short)90);
            }

            // The GET recomputes the same warnings, because screen 32 shows the hint on load.
            var read = await authed.GetAsync("/settings/cycle");
            (await read.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("warnings").GetArrayLength().ShouldBe(2);

            // The ONLY rejection on these fields is structural.
            var zero = await authed.PatchAsJsonAsync("/settings/cycle", new { avgCycleLengthDays = 0 });
            zero.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            zero.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await zero.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            problem.GetProperty("errors").GetProperty("avgCycleLengthDays")[0].GetString()
                .ShouldBe("value must be between 1 and 32767");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the pause state machine against the REAL partial unique index ----------------------------

    [Fact]
    public async Task A_double_pause_leaves_exactly_one_open_span_against_the_real_partial_unique_index()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cs-pause-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var first = await authed.PatchAsJsonAsync("/settings/cycle", new
            {
                trackingPaused = true,
                pauseReason = UserCycleSettings.PauseReasons.Pregnancy,
            });
            first.StatusCode.ShouldBe(HttpStatusCode.OK);
            var paused = await first.Content.ReadFromJsonAsync<JsonElement>();
            paused.GetProperty("trackingPaused").GetBoolean().ShouldBeTrue();
            paused.GetProperty("pauseReason").GetString().ShouldBe("pregnancy");
            paused.GetProperty("pausedSince").GetString().ShouldBe(Today.ToString("yyyy-MM-dd"));
            paused.GetProperty("phasesUnavailable").GetBoolean()
                .ShouldBeTrue("a paused user must never be shown a confidently wrong phase");

            Guid spanId;
            await using (var db = TestFixtures.NewDb())
                spanId = (await db.CycleTrackingPauseSpans.AsNoTracking().SingleAsync(s => s.UserId == userId)).Id;

            // The double tap. A blind second insert here is a 23505 against the partial unique index,
            // surfacing as a 500 — the whole point of updating the open span in place.
            var second = await authed.PatchAsJsonAsync("/settings/cycle", new
            {
                trackingPaused = true,
                pauseReason = UserCycleSettings.PauseReasons.Surgical,
            });
            second.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await second.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("pauseReason").GetString().ShouldBe("surgical");

            await using (var db = TestFixtures.NewDb())
            {
                var spans = await db.CycleTrackingPauseSpans.AsNoTracking()
                    .Where(s => s.UserId == userId).ToListAsync();
                spans.Count.ShouldBe(1, "a double pause must not fork the history into two spans");
                spans[0].Id.ShouldBe(spanId, "the open span was updated IN PLACE");
                spans[0].Reason.ShouldBe("surgical");
                spans[0].EndedOn.ShouldBeNull();
            }

            // Resume is unconditional for every reason. It closes the span and clears the flag and the
            // date, but PRESERVES the reason (ARCHITECTURE.md §D — no CHECK ties the two columns).
            var resume = await authed.PatchAsJsonAsync("/settings/cycle", new { trackingPaused = false });
            resume.StatusCode.ShouldBe(HttpStatusCode.OK);
            var resumed = await resume.Content.ReadFromJsonAsync<JsonElement>();
            resumed.GetProperty("trackingPaused").GetBoolean().ShouldBeFalse();
            resumed.GetProperty("pausedSince").ValueKind.ShouldBe(JsonValueKind.Null);
            resumed.GetProperty("pauseReason").GetString().ShouldBe("surgical");
            resumed.GetProperty("phasesUnavailable").GetBoolean().ShouldBeFalse();

            // Resuming when not paused is an idempotent 200, not a 400 and not a 500.
            (await authed.PatchAsJsonAsync("/settings/cycle", new { trackingPaused = false }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // Pausing again opens a SECOND span — the history P6 excludes from its estimators.
            (await authed.PatchAsJsonAsync("/settings/cycle", new
            {
                trackingPaused = true,
                pauseReason = UserCycleSettings.PauseReasons.Menopause,
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var read = TestFixtures.NewDb();
            var all = await read.CycleTrackingPauseSpans.AsNoTracking()
                .Where(s => s.UserId == userId).ToListAsync();
            all.Count.ShouldBe(2);
            all.Count(s => s.EndedOn == null).ShouldBe(1, "at most one OPEN span per user, DB-enforced");
            all.Single(s => s.EndedOn != null).EndedOn.ShouldBe(Today);

            var settings = await read.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == userId);
            settings.TrackingPaused.ShouldBeTrue();
            settings.PauseReason.ShouldBe("menopause");
            settings.PausedSince.ShouldBe(Today);
            all.Single(s => s.EndedOn == null).StartedOn.ShouldBe(settings.PausedSince!.Value);
            all.Single(s => s.EndedOn == null).Reason.ShouldBe(settings.PauseReason);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the one 400 body, with the endpoint's own wire strings -----------------------------------

    [Fact]
    public async Task The_pause_rejections_answer_the_shared_400_and_write_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cs-400-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var noReason = await authed.PatchAsJsonAsync("/settings/cycle", new { trackingPaused = true });
            noReason.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await noReason.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("pauseReason")[0].GetString()
                .ShouldBe("value is required");

            var unknown = await authed.PatchAsJsonAsync(
                "/settings/cycle", new { trackingPaused = true, pauseReason = "lactation" });
            unknown.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await unknown.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("pauseReason")[0].GetString()
                .ShouldBe("value is not one of the allowed values");

            var reasonWhileResumed = await authed.PatchAsJsonAsync(
                "/settings/cycle", new { trackingPaused = false, pauseReason = "pregnancy" });
            reasonWhileResumed.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await reasonWhileResumed.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("pauseReason")[0].GetString()
                .ShouldBe("value is only allowed while cycle tracking is paused");

            var empty = await authed.PatchAsJsonAsync("/settings/cycle", new { });
            empty.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await empty.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("request")[0].GetString()
                .ShouldBe("at least one settings field is required");

            var future = await authed.PatchAsJsonAsync("/settings/cycle", new
            {
                trackingPaused = true,
                pauseReason = "other",
                pausedSince = Today.AddDays(1).ToString("yyyy-MM-dd"),
            });
            future.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await future.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("pausedSince")[0].GetString()
                .ShouldBe("date must not be in the future");

            await using var db = TestFixtures.NewDb();
            (await db.CycleSettings.CountAsync(s => s.UserId == userId))
                .ShouldBe(0, "validate-then-act: every rejected request wrote nothing");
            (await db.CycleTrackingPauseSpans.CountAsync(s => s.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- MERGE semantics on the wire, where `built_value` genuinely omits nulls --------------------

    [Fact]
    public async Task A_patch_naming_one_field_leaves_the_others_alone_on_the_wire()
    {
        // The unit suite constructs the DTO directly, so it can only prove that a null member merges.
        // THIS proves the rule the client exercises: the omitted fields are genuinely ABSENT from the
        // JSON, and `user_cycle_settings` is a multi-writer row — the pause card must not reset the
        // self-report the cycle block wrote.
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cs-merge-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PatchAsJsonAsync("/settings/cycle", new
            {
                avgCycleLengthDays = 31,
                avgPeriodLengthDays = 6,
                regularity = "irregular",
                phasePredictionEnabled = false,
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            var pauseOnly = await authed.PatchAsJsonAsync("/settings/cycle", new
            {
                trackingPaused = true,
                pauseReason = "hormonal_suppression",
            });
            pauseOnly.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await pauseOnly.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("avgCycleLengthDays").GetInt32().ShouldBe(31, "the pause card must not reset the self-report");
            body.GetProperty("avgPeriodLengthDays").GetInt32().ShouldBe(6);
            body.GetProperty("regularity").GetString().ShouldBe("irregular");
            body.GetProperty("phasePredictionEnabled").GetBoolean().ShouldBeFalse();
            body.GetProperty("phasesUnavailable").GetBoolean().ShouldBeTrue();

            await using var db = TestFixtures.NewDb();
            var row = await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == userId);
            row.AvgCycleLengthDays.ShouldBe((short)31);
            row.AvgPeriodLengthDays.ShouldBe((short)6);
            row.Regularity.ShouldBe("irregular");
            row.PhasePredictionEnabled.ShouldBeFalse();
            row.TrackingPaused.ShouldBeTrue();
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- tenant isolation --------------------------------------------------------------------------

    [Fact]
    public async Task One_users_cycle_settings_and_pause_span_are_invisible_to_another()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"cs-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"cs-int-{Guid.NewGuid():N}@example.com");

            (await Authed(ownerToken).PatchAsJsonAsync("/settings/cycle", new
            {
                avgCycleLengthDays = 40,
                trackingPaused = true,
                pauseReason = "pregnancy",
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            // The intruder sees their OWN unsaved defaults, never the owner's row.
            var theirRead = await Authed(intruderToken).GetAsync("/settings/cycle");
            theirRead.StatusCode.ShouldBe(HttpStatusCode.OK);
            var theirs = await theirRead.Content.ReadFromJsonAsync<JsonElement>();
            theirs.GetProperty("avgCycleLengthDays").GetInt32().ShouldBe(28);
            theirs.GetProperty("trackingPaused").GetBoolean().ShouldBeFalse();
            theirs.GetProperty("createdAt").ValueKind.ShouldBe(JsonValueKind.Null);

            // Both users may hold an open span at once — the partial unique index is per user.
            (await Authed(intruderToken).PatchAsJsonAsync("/settings/cycle", new
            {
                trackingPaused = true,
                pauseReason = "other",
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            (await Authed(intruderToken).PatchAsJsonAsync("/settings/cycle", new { trackingPaused = false }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            var owner = await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == ownerId);
            owner.AvgCycleLengthDays.ShouldBe((short)40, "the owner's row must be untouched");
            owner.TrackingPaused.ShouldBeTrue("the intruder's resume must not close the owner's pause");
            (await db.CycleTrackingPauseSpans.AsNoTracking()
                .SingleAsync(s => s.UserId == ownerId)).EndedOn.ShouldBeNull();
            (await db.CycleTrackingPauseSpans.AsNoTracking()
                .SingleAsync(s => s.UserId == intruderId)).EndedOn.ShouldBe(Today);
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // --- the perimeter -----------------------------------------------------------------------------

    [Fact]
    public async Task Both_settings_cycle_routes_require_a_bearer_token()
    {
        var client = factory.CreateClient();

        (await client.GetAsync("/settings/cycle")).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        (await client.PatchAsJsonAsync("/settings/cycle", new { avgCycleLengthDays = 28 }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_from_both_settings_routes()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cs-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PatchAsJsonAsync("/settings/cycle", new
            {
                avgCycleLengthDays = 30,
                trackingPaused = true,
                pauseReason = "pregnancy",
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            // The bearer token stays cryptographically valid until it expires; the 404s below are the
            // only thing stopping it from reading settings back or writing new ones after erasure.
            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            var read = await authed.GetAsync("/settings/cycle");
            read.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            read.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            (await read.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            // A body that would otherwise be a 400 still answers "no such user" — the fence is checked
            // before validation, so the shape of the answer leaks nothing.
            var write = await authed.PatchAsJsonAsync("/settings/cycle", new { avgCycleLengthDays = 0 });
            write.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await write.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            await using var db = TestFixtures.NewDb();
            (await db.CycleSettings.CountAsync(s => s.UserId == userId))
                .ShouldBe(0, "the shred deleted the settings row and the token wrote none back");
            (await db.CycleTrackingPauseSpans.CountAsync(s => s.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // ------------------------------------------------------------------ helpers

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
            displayName = "Settings Tester",
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
        await db.CycleTrackingPauseSpans.Where(s => s.UserId == userId).ExecuteDeleteAsync();
        await db.CycleSettings.Where(s => s.UserId == userId).ExecuteDeleteAsync();
        await db.CycleEvents.IgnoreQueryFilters().Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await db.CycleDayLogs.IgnoreQueryFilters().Where(l => l.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
