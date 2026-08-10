using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Lumen.Infrastructure.Jobs;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for the three D-02 preference steps (T17):
/// <c>POST /onboarding/goals</c>, <c>POST /onboarding/hormones</c> and
/// <c>POST /onboarding/notifications</c>.
///
/// <para>Postgres is the only place the three <b>unique indexes</b> on
/// <c>user_goals (UserId, GoalCode)</c>, <c>user_hormone_prefs (UserId, HormoneCode)</c> and
/// <c>user_notification_prefs (UserId, CategoryCode)</c> are actually enforced — Sqlite proves the code
/// path, Postgres proves the constraint — and every one of these steps is one D-02 explicitly lets the
/// user revisit, so a blind insert on the second call would be a 500 on a screen the user is invited to
/// come back to. It is also the only place the composed unit of work (four preference rows <b>plus</b>
/// a <c>user_devices</c> row, one save, real transaction) can be observed end to end.</para>
///
/// <para>These tests are additionally the phase's guard that the three routes are <b>wired</b>: a later
/// <c>Program.cs</c> edit that dropped one of them from <c>MapOnboardingEndpoints()</c> would turn the
/// calls below into 404s, so the suite cannot stay green with a resource unreachable.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class OnboardingPreferencesLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";

    /// <summary>A token shaped like the real thing: long, opaque, and unique per test run.</summary>
    private static string NewToken(string prefix) => $"{prefix}:{Guid.NewGuid():N}{Guid.NewGuid():N}";

    // --- the round trip, end to end ------------------------------------------------------------------

    [Fact]
    public async Task All_three_steps_round_trip_and_write_their_complete_row_sets()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"pref-rt-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var goals = await authed.PostAsJsonAsync(
                "/onboarding/goals", new { goals = new[] { "plan_fertility", "just_curious" } });
            goals.StatusCode.ShouldBe(HttpStatusCode.OK);
            var goalBody = (await goals.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("goals");
            Codes(goalBody).ShouldBe(
                ["manage_symptoms", "understand_hormones", "plan_fertility", "prepare_appointments", "just_curious"],
                Case.Sensitive,
                "the response is in the frozen §G10 order");
            Flagged(goalBody, "selected").ShouldBe(["plan_fertility", "just_curious"], Case.Sensitive);

            var hormones = await authed.PostAsJsonAsync(
                "/onboarding/hormones", new { chartedHormones = new[] { "estradiol", "glp1" } });
            hormones.StatusCode.ShouldBe(HttpStatusCode.OK);
            var hormoneBody = (await hormones.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("hormones");
            Codes(hormoneBody).ShouldBe(
                ["estradiol", "progesterone", "lh", "fsh", "testosterone", "cortisol", "glp1"], Case.Sensitive);
            Flagged(hormoneBody, "charted").ShouldBe(["estradiol", "glp1"], Case.Sensitive);

            var notifications = await authed.PostAsJsonAsync(
                "/onboarding/notifications", new { enabledCategories = new[] { "daily_checkin", "phase_shift" } });
            notifications.StatusCode.ShouldBe(HttpStatusCode.OK);
            var notificationBody = await notifications.Content.ReadFromJsonAsync<JsonElement>();
            var categories = notificationBody.GetProperty("categories");
            Codes(categories).ShouldBe(
                ["daily_checkin", "phase_shift", "period_prediction", "medication_reminders"], Case.Sensitive);
            Flagged(categories, "enabled").ShouldBe(["daily_checkin", "phase_shift"], Case.Sensitive);
            notificationBody.GetProperty("deviceRegistered").GetBoolean().ShouldBeFalse();

            await using var db = TestFixtures.NewDb();
            (await db.UserGoals.CountAsync(g => g.UserId == userId)).ShouldBe(5);
            (await db.UserHormonePrefs.CountAsync(p => p.UserId == userId)).ShouldBe(7);
            (await db.UserNotificationPrefs.CountAsync(p => p.UserId == userId)).ShouldBe(4);
            (await db.UserDevices.CountAsync(d => d.UserId == userId)).ShouldBe(
                0, "a notifications call WITHOUT a token registers no device");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the composed write: preferences + the device row, in one unit of work -----------------------

    [Fact]
    public async Task A_notifications_call_WITH_a_token_writes_four_preference_rows_and_one_device_row()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"pref-dev-{Guid.NewGuid():N}@example.com");
            var pushToken = NewToken("fcm");

            var response = await Authed(token).PostAsJsonAsync("/onboarding/notifications", new
            {
                enabledCategories = new[] { "period_prediction" },
                pushToken,
                platform = "android",
            });

            response.StatusCode.ShouldBe(HttpStatusCode.OK);
            var raw = await response.Content.ReadAsStringAsync();
            raw.ShouldNotContain(pushToken, Case.Sensitive,
                "§F: the token is PII — echoing it puts it in every client log and support HAR file");
            JsonDocument.Parse(raw).RootElement.GetProperty("deviceRegistered").GetBoolean().ShouldBeTrue();

            await using var db = TestFixtures.NewDb();
            (await db.UserNotificationPrefs.CountAsync(p => p.UserId == userId)).ShouldBe(4);
            var device = await db.UserDevices.AsNoTracking().SingleAsync(d => d.UserId == userId);
            device.Platform.ShouldBe("android");
            device.PushToken.ShouldBe(pushToken);
            device.LastSeenAt.ShouldNotBeNull();
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- idempotency against the REAL unique indexes -------------------------------------------------

    [Fact]
    public async Task Re_submitting_every_step_is_idempotent_against_the_real_unique_indexes()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"pref-idem-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var pushToken = NewToken("apns");

            // A blind insert on the second call is a 23505 against the real index, surfacing as a 500 —
            // on steps D-02 explicitly lets the user revisit.
            for (var i = 0; i < 3; i++)
            {
                (await authed.PostAsJsonAsync("/onboarding/goals", new { goals = new[] { "manage_symptoms" } }))
                    .StatusCode.ShouldBe(HttpStatusCode.OK);
                (await authed.PostAsJsonAsync("/onboarding/hormones", new { chartedHormones = new[] { "lh" } }))
                    .StatusCode.ShouldBe(HttpStatusCode.OK);
                (await authed.PostAsJsonAsync("/onboarding/notifications", new
                {
                    enabledCategories = new[] { "medication_reminders" },
                    pushToken,
                    platform = "ios",
                })).StatusCode.ShouldBe(HttpStatusCode.OK);
            }

            await using var db = TestFixtures.NewDb();
            (await db.UserGoals.CountAsync(g => g.UserId == userId)).ShouldBe(5);
            (await db.UserHormonePrefs.CountAsync(p => p.UserId == userId)).ShouldBe(7);
            (await db.UserNotificationPrefs.CountAsync(p => p.UserId == userId)).ShouldBe(4);
            (await db.UserDevices.CountAsync(d => d.UserId == userId)).ShouldBe(1);

            // FULL REPLACE: the last answer is the whole answer, never the union of three.
            (await db.UserGoals.Where(g => g.UserId == userId && g.Selected).Select(g => g.GoalCode).ToListAsync())
                .ShouldBe(["manage_symptoms"], Case.Sensitive);
            (await db.UserHormonePrefs.Where(p => p.UserId == userId && p.Charted)
                .Select(p => p.HormoneCode).ToListAsync()).ShouldBe(["lh"], Case.Sensitive);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task The_three_steps_stay_callable_after_onboarding_is_completed()
    {
        // They are the same writes the settings screens will make, and the endpoints that would replace
        // them do not ship for several phases — 409-ing them would leave the data uneditable.
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"pref-done-{Guid.NewGuid():N}@example.com");

            await using (var complete = TestFixtures.NewDb())
            {
                var user = await complete.Users.SingleAsync(u => u.Id == userId);
                user.OnboardingCompletedAt = DateTimeOffset.UtcNow;
                await complete.SaveChangesAsync();
            }

            var authed = Authed(token);
            (await authed.PostAsJsonAsync("/onboarding/goals", new { goals = new[] { "just_curious" } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.PostAsJsonAsync("/onboarding/hormones", new { chartedHormones = Array.Empty<string>() }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.PostAsJsonAsync(
                "/onboarding/notifications", new { enabledCategories = Array.Empty<string>() }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the one 400 body ----------------------------------------------------------------------------

    [Fact]
    public async Task The_rejections_answer_the_shared_400_verbatim_and_write_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"pref-400-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var nullGoals = await authed.PostAsJsonAsync("/onboarding/goals", new { });
            nullGoals.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            nullGoals.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var nullGoalsProblem = await nullGoals.Content.ReadFromJsonAsync<JsonElement>();
            nullGoalsProblem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            nullGoalsProblem.GetProperty("errors").GetProperty("goals")[0].GetString()
                .ShouldBe("value is required");

            var emptyGoals = await authed.PostAsJsonAsync("/onboarding/goals", new { goals = Array.Empty<string>() });
            emptyGoals.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await emptyGoals.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("goals")[0].GetString()
                .ShouldBe("select at least one goal");

            var badGoal = await authed.PostAsJsonAsync(
                "/onboarding/goals", new { goals = new[] { "manage_symptoms", "get_pregnant" } });
            badGoal.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await badGoal.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("goals[1]")[0].GetString()
                .ShouldBe("value is not one of the allowed values");

            var badHormone = await authed.PostAsJsonAsync(
                "/onboarding/hormones", new { chartedHormones = new[] { "estrogen" } });
            badHormone.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await badHormone.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("chartedHormones[0]")[0].GetString()
                .ShouldBe("value is not one of the allowed values");

            var halfDevice = await authed.PostAsJsonAsync("/onboarding/notifications", new
            {
                enabledCategories = Array.Empty<string>(),
                pushToken = NewToken("fcm"),
            });
            halfDevice.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await halfDevice.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("request")[0].GetString()
                .ShouldBe("pushToken and platform must be provided together");

            var badPlatform = await authed.PostAsJsonAsync("/onboarding/notifications", new
            {
                enabledCategories = Array.Empty<string>(),
                pushToken = NewToken("fcm"),
                platform = "web",
            });
            badPlatform.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await badPlatform.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("platform")[0].GetString()
                .ShouldBe("value is not one of the allowed values");

            var longToken = await authed.PostAsJsonAsync("/onboarding/notifications", new
            {
                enabledCategories = Array.Empty<string>(),
                pushToken = new string('t', 513),
                platform = "ios",
            });
            longToken.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await longToken.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("pushToken")[0].GetString()
                .ShouldBe("text exceeds the maximum length of 512 characters");

            await using var db = TestFixtures.NewDb();
            (await db.UserGoals.CountAsync(g => g.UserId == userId))
                .ShouldBe(0, "validate-then-act: every rejected request wrote nothing");
            (await db.UserHormonePrefs.CountAsync(p => p.UserId == userId)).ShouldBe(0);
            (await db.UserNotificationPrefs.CountAsync(p => p.UserId == userId)).ShouldBe(0);
            (await db.UserDevices.CountAsync(d => d.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the perimeter --------------------------------------------------------------------------------

    [Theory]
    [InlineData("/onboarding/goals")]
    [InlineData("/onboarding/hormones")]
    [InlineData("/onboarding/notifications")]
    public async Task Every_preference_route_requires_a_bearer_token(string route)
    {
        var client = factory.CreateClient();

        (await client.PostAsJsonAsync(route, new { })).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_from_all_three_and_writes_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"pref-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync("/onboarding/goals", new { goals = new[] { "just_curious" } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            // Bodies that would otherwise be 400s still answer "no such user": the fence runs before
            // validation, so the shape of the answer leaks nothing about the request being understood.
            foreach (var (route, body) in new (string, object)[]
                     {
                         ("/onboarding/goals", new { goals = Array.Empty<string>() }),
                         ("/onboarding/hormones", new { }),
                         ("/onboarding/notifications", new { enabledCategories = new[] { "nope" }, platform = "web" }),
                     })
            {
                var write = await authed.PostAsJsonAsync(route, body);
                write.StatusCode.ShouldBe(HttpStatusCode.NotFound, route);
                write.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
                (await write.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                    .ShouldBe("The requested resource was not found.");
            }

            await using var db = TestFixtures.NewDb();
            (await db.UserGoals.CountAsync(g => g.UserId == userId))
                .ShouldBe(0, "the shred hard-deleted the rows (§F/T8) and the token wrote none back");
            (await db.UserHormonePrefs.CountAsync(p => p.UserId == userId)).ShouldBe(0);
            (await db.UserNotificationPrefs.CountAsync(p => p.UserId == userId)).ShouldBe(0);
            (await db.UserDevices.CountAsync(d => d.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task One_users_preferences_are_invisible_to_and_untouched_by_another()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"pref-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"pref-int-{Guid.NewGuid():N}@example.com");

            (await Authed(ownerToken).PostAsJsonAsync(
                "/onboarding/goals", new { goals = new[] { "plan_fertility" } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            (await Authed(intruderToken).PostAsJsonAsync(
                "/onboarding/goals", new { goals = new[] { "just_curious" } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            (await db.UserGoals.Where(g => g.UserId == ownerId && g.Selected)
                .Select(g => g.GoalCode).ToListAsync())
                .ShouldBe(["plan_fertility"], Case.Sensitive, "another tenant's write must not touch these rows");
            (await db.UserGoals.Where(g => g.UserId == intruderId && g.Selected)
                .Select(g => g.GoalCode).ToListAsync()).ShouldBe(["just_curious"], Case.Sensitive);
            (await db.UserGoals.CountAsync(g => g.UserId == ownerId)).ShouldBe(5);
            (await db.UserGoals.CountAsync(g => g.UserId == intruderId)).ShouldBe(5);
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static IReadOnlyList<string> Codes(JsonElement array) =>
        [.. array.EnumerateArray().Select(e => e.GetProperty("code").GetString()!)];

    private static IReadOnlyList<string> Flagged(JsonElement array, string flag) =>
    [
        .. array.EnumerateArray()
            .Where(e => e.GetProperty(flag).GetBoolean())
            .Select(e => e.GetProperty("code").GetString()!),
    ];

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
            displayName = "Preference Tester",
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
        await db.UserGoals.Where(g => g.UserId == userId).ExecuteDeleteAsync();
        await db.UserHormonePrefs.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.UserNotificationPrefs.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
