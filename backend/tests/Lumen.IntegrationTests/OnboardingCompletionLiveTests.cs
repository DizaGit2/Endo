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
/// LIVE-STACK integration tests for T18 — the three endpoints that close the D-02 state machine:
/// <c>POST /onboarding/cycle</c> (B15), <c>POST /onboarding/complete</c> and
/// <c>GET /onboarding/state</c>.
///
/// <para>Postgres is the only place three of this task's claims are actually testable. The
/// <b>unfiltered unique index</b> on <c>cycle_events (UserId, Kind, OccurredOn)</c> is enforced here and
/// nowhere else, and the whole T5 merge rule exists to stay off it — Sqlite proves the code path, the
/// real index proves the rule. The <b>transaction</b> that carries the completion stamp and the four
/// default sets together is a real one here, so "GET /me can never report onboardingCompleted:true while
/// the defaults are missing" is observed rather than reasoned about. And the <b>§G6 exit criterion</b> —
/// <c>user_insight_snapshot</c> stays empty on the happy path — is a statement about the real
/// database.</para>
///
/// <para>These tests are additionally the phase's guard that the three routes are <b>wired</b>: a later
/// <c>Program.cs</c> edit that dropped one of them from <c>MapOnboardingEndpoints()</c> would turn the
/// calls below into 404s, so the suite cannot stay green with a resource unreachable.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class OnboardingCompletionLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";

    // --- the full happy path ---------------------------------------------------------------------

    [Fact]
    public async Task The_full_onboarding_path_flips_onboardingCompleted_EXACTLY_at_complete()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"done-full-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var anchor = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-9);

            (await OnboardingCompletedAsync(authed)).ShouldBeFalse("a fresh account is not onboarded");

            (await authed.PostAsJsonAsync("/onboarding/baseline", new { heightCm = 167, weightKg = 61.5 }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await OnboardingCompletedAsync(authed)).ShouldBeFalse();

            var cycle = await authed.PostAsJsonAsync("/onboarding/cycle", new
            {
                lastPeriodStart = anchor.ToString("yyyy-MM-dd"),
                avgCycleLengthDays = 47,
                avgPeriodLengthDays = 12,
                regularity = "irregular",
            });
            cycle.StatusCode.ShouldBe(HttpStatusCode.OK);
            var cycleBody = await cycle.Content.ReadFromJsonAsync<JsonElement>();
            cycleBody.GetProperty("avgCycleLengthDays").GetInt32().ShouldBe(
                47, "§G7: the clinical band is not code — a self-report is never an entry blocker");
            cycleBody.GetProperty("avgPeriodLengthDays").GetInt32().ShouldBe(12);
            cycleBody.GetProperty("regularity").GetString().ShouldBe("irregular");
            cycleBody.GetProperty("warnings").GetArrayLength().ShouldBe(0);
            (await OnboardingCompletedAsync(authed)).ShouldBeFalse();

            (await authed.PostAsJsonAsync("/onboarding/goals", new { goals = new[] { "plan_fertility" } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.PostAsJsonAsync("/onboarding/hormones", new { chartedHormones = new[] { "lh", "fsh" } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.PostAsJsonAsync(
                    "/onboarding/notifications", new { enabledCategories = new[] { "medication_reminders" } }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            (await OnboardingCompletedAsync(authed)).ShouldBeFalse(
                "every step is answered and the flag is STILL false — only /complete sets it");

            var complete = await authed.PostAsJsonAsync("/onboarding/complete", new { });
            complete.StatusCode.ShouldBe(HttpStatusCode.OK);
            var completeBody = await complete.Content.ReadFromJsonAsync<JsonElement>();
            completeBody.GetProperty("alreadyCompleted").GetBoolean().ShouldBeFalse();
            var completedAt = completeBody.GetProperty("completedAt").GetDateTimeOffset();

            (await OnboardingCompletedAsync(authed)).ShouldBeTrue("the flag flips here and only here");

            var state = await (await authed.GetAsync("/onboarding/state")).Content
                .ReadFromJsonAsync<JsonElement>();
            state.GetProperty("completed").GetBoolean().ShouldBeTrue();
            state.GetProperty("missingMandatorySteps").GetArrayLength().ShouldBe(0);
            state.GetProperty("lastPeriodStart").GetDateTime().ShouldBe(
                anchor.ToDateTime(TimeOnly.MinValue));
            Flagged(state.GetProperty("goals"), "selected").ShouldBe(["plan_fertility"], Case.Sensitive);

            await using var db = TestFixtures.NewDb();

            // The answered steps are untouched by the backfill.
            (await db.UserGoals.Where(g => g.UserId == userId && g.Selected)
                .Select(g => g.GoalCode).ToListAsync()).ShouldBe(["plan_fertility"], Case.Sensitive);
            (await db.UserHormonePrefs.Where(p => p.UserId == userId && p.Charted)
                    .Select(p => p.HormoneCode).OrderBy(c => c).ToListAsync())
                .ShouldBe(["fsh", "lh"], Case.Sensitive);

            // The anchor is one row, seeded by onboarding, against the REAL unique index.
            var events = await db.CycleEvents.IgnoreQueryFilters()
                .Where(e => e.UserId == userId).ToListAsync();
            events.Count.ShouldBe(1);
            events[0].Kind.ShouldBe("period_start");
            events[0].Source.ShouldBe("onboarding");
            events[0].OccurredOn.ShouldBe(anchor);
            events[0].FlowIntensity.ShouldBeNull("onboarding never asks for flow");

            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId);
            user.OnboardingCompletedAt.ShouldNotBeNull();
            user.OnboardingCompletedAt!.Value.ToUniversalTime()
                .ShouldBe(completedAt.ToUniversalTime(), TimeSpan.FromSeconds(1));

            // §G6, the phase's zero-clinical-inference exit criterion, actually asserted.
            (await db.UserInsightSnapshots.CountAsync(s => s.UserId == userId)).ShouldBe(
                0, "P4a ships ZERO clinical inference — the happy path computes nothing");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the skip path: every optional step skipped ----------------------------------------------

    [Fact]
    public async Task The_skip_path_backfills_the_four_default_sets_in_the_same_transaction_as_the_stamp()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"done-skip-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var anchor = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-3);

            // start → cycle → complete. Baseline, goals, hormones and notifications are all skipped,
            // which under T17's rule means they have persisted NOTHING at this point.
            (await authed.PostAsJsonAsync(
                    "/onboarding/cycle", new { lastPeriodStart = anchor.ToString("yyyy-MM-dd") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using (var beforeComplete = TestFixtures.NewDb())
            {
                (await beforeComplete.UserGoals.CountAsync(g => g.UserId == userId)).ShouldBe(
                    0, "a skipped step persists nothing — the seed lives on the read side until completion");
                (await beforeComplete.UserHormonePrefs.CountAsync(p => p.UserId == userId)).ShouldBe(0);
                (await beforeComplete.UserNotificationPrefs.CountAsync(p => p.UserId == userId)).ShouldBe(0);
            }

            (await authed.PostAsJsonAsync("/onboarding/complete", new { }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();

            (await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId))
                .OnboardingCompletedAt.ShouldNotBeNull();

            // Set 1 — goals: the D-14 seed, from UserGoal.DefaultSelected.
            var goals = await db.UserGoals.Where(g => g.UserId == userId).ToListAsync();
            goals.Count.ShouldBe(5);
            goals.Where(g => g.Selected).Select(g => g.GoalCode).Order(StringComparer.Ordinal)
                .ShouldBe(UserGoal.DefaultSelected.Order(StringComparer.Ordinal), Case.Sensitive);

            // Set 2 — hormones: ALL SEVEN charted (D-14).
            var hormones = await db.UserHormonePrefs.Where(p => p.UserId == userId).ToListAsync();
            hormones.Count.ShouldBe(7);
            hormones.Where(p => p.Charted).Select(p => p.HormoneCode).Order(StringComparer.Ordinal)
                .ShouldBe(UserHormonePref.DefaultCharted.Order(StringComparer.Ordinal), Case.Sensitive);

            // Set 3 — notifications: the ON/ON/OFF/OFF seed. A direct SELECT returning zero rows would
            // otherwise read as "all notifications off" and silently cost a user their check-in reminder.
            var categories = await db.UserNotificationPrefs.Where(p => p.UserId == userId).ToListAsync();
            categories.Count.ShouldBe(4);
            categories.Where(p => p.Enabled).Select(p => p.CategoryCode).Order(StringComparer.Ordinal)
                .ShouldBe(UserNotificationPref.DefaultEnabled.Order(StringComparer.Ordinal), Case.Sensitive);

            // Set 4 — the cycle settings row, from the T6 entity defaults.
            var settings = await db.CycleSettings.AsNoTracking().SingleAsync(s => s.UserId == userId);
            settings.AvgCycleLengthDays.ShouldBe(UserCycleSettings.DefaultAvgCycleLengthDays);
            settings.AvgPeriodLengthDays.ShouldBeNull("screen 3 never collects it");
            settings.Regularity.ShouldBe(UserCycleSettings.RegularityValues.Default);

            (await db.UserInsightSnapshots.CountAsync(s => s.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the T5 merge rule, against the REAL unfiltered unique index -----------------------------

    [Fact]
    public async Task Re_posting_the_cycle_step_never_violates_the_real_unique_index()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"done-merge-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            var first = today.AddDays(-20);
            var moved = today.AddDays(-18);
            var userLogged = today.AddDays(-6);

            (await authed.PostAsJsonAsync(
                    "/onboarding/cycle", new { lastPeriodStart = first.ToString("yyyy-MM-dd") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // (a) MOVE — a re-post with a different date relocates the single onboarding row.
            (await authed.PostAsJsonAsync(
                    "/onboarding/cycle", new { lastPeriodStart = moved.ToString("yyyy-MM-dd") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using (var afterMove = TestFixtures.NewDb())
            {
                var rows = await afterMove.CycleEvents.IgnoreQueryFilters()
                    .Where(e => e.UserId == userId).ToListAsync();
                rows.Count.ShouldBe(1, "moved, never duplicated");
                rows[0].OccurredOn.ShouldBe(moved);
                rows[0].Source.ShouldBe("onboarding");
            }

            // (b) ADOPT — the user logs a real period start elsewhere, then corrects onboarding onto it.
            // A blind insert here is a 23505 against the real index, surfacing as a 500.
            (await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = "period_start",
                occurredOn = userLogged.ToString("yyyy-MM-dd"),
                flowIntensity = 3,
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            (await authed.PostAsJsonAsync(
                    "/onboarding/cycle", new { lastPeriodStart = userLogged.ToString("yyyy-MM-dd") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            Guid adoptedId;
            DateTimeOffset adoptedCreatedAt;
            await using (var afterAdopt = TestFixtures.NewDb())
            {
                var live = await afterAdopt.CycleEvents.Where(e => e.UserId == userId).ToListAsync();
                live.Count.ShouldBe(1, "exactly one live anchor survives the collision");
                live[0].OccurredOn.ShouldBe(userLogged);
                live[0].Source.ShouldBe("user", "the adopted row keeps its provenance");
                live[0].FlowIntensity.ShouldBe((short)3, "and its flow — onboarding clears nothing");
                adoptedId = live[0].Id;
                adoptedCreatedAt = live[0].CreatedAt;

                var all = await afterAdopt.CycleEvents.IgnoreQueryFilters()
                    .Where(e => e.UserId == userId).ToListAsync();
                all.Count.ShouldBe(2, "the stale onboarding row is retired as a tombstone, not deleted");
                all.Single(e => e.OccurredOn == moved).DeletedAt.ShouldNotBeNull();
            }

            // (c) REVIVE — the user deletes that row; the same date is then re-posted. The tombstone
            // still occupies the unfiltered key, so this is the second 23505 the merge rule prevents.
            (await authed.DeleteAsync($"/cycle/events/{adoptedId}")).StatusCode
                .ShouldBe(HttpStatusCode.NoContent);

            (await authed.PostAsJsonAsync(
                    "/onboarding/cycle", new { lastPeriodStart = userLogged.ToString("yyyy-MM-dd") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using (var afterRevive = TestFixtures.NewDb())
            {
                var live = await afterRevive.CycleEvents.Where(e => e.UserId == userId).ToListAsync();
                live.Count.ShouldBe(1);
                live[0].Id.ShouldBe(adoptedId, "revived in place — same row, same identity");
                live[0].CreatedAt.ShouldBe(adoptedCreatedAt, "and the original creation instant");
                live[0].Source.ShouldBe("user");
            }
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the two 409s --------------------------------------------------------------------------

    [Fact]
    public async Task Completing_before_the_cycle_step_is_a_409_naming_the_missing_step()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"done-409a-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var response = await authed.PostAsJsonAsync("/onboarding/complete", new { });

            response.StatusCode.ShouldBe(HttpStatusCode.Conflict);
            response.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("title").GetString()
                .ShouldBe("The request conflicts with the current onboarding state.");
            problem.GetProperty("detail").GetString()
                .ShouldBe("Onboarding cannot be completed until every mandatory step is answered.");
            problem.GetProperty("code").GetString().ShouldBe("onboarding_incomplete");
            problem.GetProperty("missingSteps").EnumerateArray().Select(e => e.GetString()!)
                .ShouldBe(["cycle"], Case.Sensitive);

            (await OnboardingCompletedAsync(authed)).ShouldBeFalse();

            await using var db = TestFixtures.NewDb();
            (await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId))
                .OnboardingCompletedAt.ShouldBeNull();
            (await db.UserGoals.CountAsync(g => g.UserId == userId)).ShouldBe(
                0, "a refused completion backfills nothing");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task The_cycle_step_is_409_after_completion_and_a_second_complete_is_200()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"done-409b-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var anchor = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-5);

            (await authed.PostAsJsonAsync(
                    "/onboarding/cycle", new { lastPeriodStart = anchor.ToString("yyyy-MM-dd") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            var first = await authed.PostAsJsonAsync("/onboarding/complete", new { });
            first.StatusCode.ShouldBe(HttpStatusCode.OK);
            var firstStamp = (await first.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("completedAt").GetDateTimeOffset();

            // Moving the seeded anchor post-hoc is a data-integrity hazard: every later cycle is
            // measured from it. Post-completion edits go through POST /cycle/events + PATCH /settings/cycle.
            var reopened = await authed.PostAsJsonAsync("/onboarding/cycle", new
            {
                lastPeriodStart = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-1).ToString("yyyy-MM-dd"),
            });
            reopened.StatusCode.ShouldBe(HttpStatusCode.Conflict);
            var problem = await reopened.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("code").GetString().ShouldBe("onboarding_already_completed");
            problem.GetProperty("detail").GetString()
                .ShouldBe("Onboarding is already complete; the cycle anchor can no longer be moved here.");

            // A second /complete is a 200 carrying the ORIGINAL timestamp — the guarded claim in action.
            var second = await authed.PostAsJsonAsync("/onboarding/complete", new { });
            second.StatusCode.ShouldBe(HttpStatusCode.OK);
            var secondBody = await second.Content.ReadFromJsonAsync<JsonElement>();
            secondBody.GetProperty("alreadyCompleted").GetBoolean().ShouldBeTrue();
            secondBody.GetProperty("completedAt").GetDateTimeOffset().ToUniversalTime()
                .ShouldBe(firstStamp.ToUniversalTime(), TimeSpan.FromMilliseconds(1));

            await using var db = TestFixtures.NewDb();
            (await db.CycleEvents.CountAsync(e => e.UserId == userId))
                .ShouldBe(1, "the anchor did not move and no second row appeared");
            (await db.CycleEvents.Where(e => e.UserId == userId).Select(e => e.OccurredOn).SingleAsync())
                .ShouldBe(anchor);
            (await db.UserGoals.CountAsync(g => g.UserId == userId))
                .ShouldBe(5, "the second completion backfilled no duplicates");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the one 400 body -------------------------------------------------------------------------

    [Fact]
    public async Task The_cycle_step_rejections_answer_the_shared_400_verbatim_and_write_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"done-400-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var missing = await authed.PostAsJsonAsync("/onboarding/cycle", new { });
            missing.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            missing.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var missingProblem = await missing.Content.ReadFromJsonAsync<JsonElement>();
            missingProblem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            missingProblem.GetProperty("errors").GetProperty("lastPeriodStart")[0].GetString()
                .ShouldBe("value is required");

            var future = await authed.PostAsJsonAsync("/onboarding/cycle", new
            {
                lastPeriodStart = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(2).ToString("yyyy-MM-dd"),
            });
            future.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await future.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("lastPeriodStart")[0].GetString()
                .ShouldBe("date must not be in the future");

            // §G8: the floor is account creation − 2 y, and these accounts were created seconds ago.
            var belowFloor = await authed.PostAsJsonAsync("/onboarding/cycle", new
            {
                lastPeriodStart = DateOnly.FromDateTime(DateTime.UtcNow).AddYears(-3).ToString("yyyy-MM-dd"),
            });
            belowFloor.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await belowFloor.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("lastPeriodStart")[0].GetString()
                .ShouldBe("date is before the earliest allowed date");

            var badRegularity = await authed.PostAsJsonAsync("/onboarding/cycle", new
            {
                lastPeriodStart = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-4).ToString("yyyy-MM-dd"),
                regularity = "sometimes",
            });
            badRegularity.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await badRegularity.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("regularity")[0].GetString()
                .ShouldBe("value is not one of the allowed values");

            var zeroLength = await authed.PostAsJsonAsync("/onboarding/cycle", new
            {
                lastPeriodStart = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-4).ToString("yyyy-MM-dd"),
                avgCycleLengthDays = 0,
            });
            zeroLength.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await zeroLength.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("avgCycleLengthDays")[0].GetString()
                .ShouldBe("value must be between 1 and 32767");

            await using var db = TestFixtures.NewDb();
            (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId))
                .ShouldBe(0, "validate-then-act: every rejected request wrote nothing");
            (await db.CycleSettings.CountAsync(s => s.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- GET /onboarding/state --------------------------------------------------------------------

    [Fact]
    public async Task The_state_read_is_a_resume_read_for_a_partially_onboarded_user()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"done-state-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var fresh = await (await authed.GetAsync("/onboarding/state")).Content
                .ReadFromJsonAsync<JsonElement>();
            fresh.GetProperty("completed").GetBoolean().ShouldBeFalse();
            fresh.GetProperty("completedAt").ValueKind.ShouldBe(JsonValueKind.Null);
            fresh.GetProperty("missingMandatorySteps").EnumerateArray().Select(e => e.GetString()!)
                .ShouldBe(["cycle"], Case.Sensitive);
            fresh.GetProperty("cycleProvided").GetBoolean().ShouldBeFalse();
            fresh.GetProperty("baselineProvided").GetBoolean().ShouldBeFalse();
            fresh.GetProperty("goalsProvided").GetBoolean().ShouldBeFalse();
            fresh.GetProperty("lastPeriodStart").ValueKind.ShouldBe(JsonValueKind.Null);

            // The projections still answer with the documented seed, which is what makes this a resume
            // read rather than a checklist — the client can render every toggle correctly mid-flow.
            Codes(fresh.GetProperty("hormones")).ShouldBe(
                ["estradiol", "progesterone", "lh", "fsh", "testosterone", "cortisol", "glp1"], Case.Sensitive);
            Flagged(fresh.GetProperty("hormones"), "charted").Count.ShouldBe(7, "D-14: all seven ON");
            Flagged(fresh.GetProperty("notifications"), "enabled")
                .ShouldBe(["daily_checkin", "phase_shift"], Case.Sensitive);

            await using (var db = TestFixtures.NewDb())
            {
                (await db.UserHormonePrefs.CountAsync(p => p.UserId == userId)).ShouldBe(
                    0, "the state read applies the seed; it never materialises it");
            }

            var anchor = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-14);
            (await authed.PostAsJsonAsync(
                    "/onboarding/cycle", new { lastPeriodStart = anchor.ToString("yyyy-MM-dd") }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            var seeded = await (await authed.GetAsync("/onboarding/state")).Content
                .ReadFromJsonAsync<JsonElement>();
            seeded.GetProperty("cycleProvided").GetBoolean().ShouldBeTrue();
            seeded.GetProperty("missingMandatorySteps").GetArrayLength().ShouldBe(0);
            seeded.GetProperty("lastPeriodStart").GetDateTime().ShouldBe(anchor.ToDateTime(TimeOnly.MinValue));
            seeded.GetProperty("completed").GetBoolean().ShouldBeFalse();
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the perimeter ----------------------------------------------------------------------------

    [Fact]
    public async Task Every_T18_route_requires_a_bearer_token()
    {
        var client = factory.CreateClient();

        (await client.PostAsJsonAsync("/onboarding/cycle", new { })).StatusCode
            .ShouldBe(HttpStatusCode.Unauthorized);
        (await client.PostAsJsonAsync("/onboarding/complete", new { })).StatusCode
            .ShouldBe(HttpStatusCode.Unauthorized);
        (await client.GetAsync("/onboarding/state")).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_from_all_three()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"done-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync("/onboarding/cycle", new
            {
                lastPeriodStart = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-2).ToString("yyyy-MM-dd"),
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            await using (var jobDb = TestFixtures.NewDb())
            {
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance)
                    .ExecuteAsync(userId);
            }

            // A body that would otherwise be a 400 still answers "no such user": the fence runs before
            // validation AND before the completion probe, so the answer leaks nothing.
            var write = await authed.PostAsJsonAsync("/onboarding/cycle", new { regularity = "sometimes" });
            write.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            write.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            (await write.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            (await authed.PostAsJsonAsync("/onboarding/complete", new { })).StatusCode
                .ShouldBe(HttpStatusCode.NotFound);
            (await authed.GetAsync("/onboarding/state")).StatusCode.ShouldBe(HttpStatusCode.NotFound);

            await using var db = TestFixtures.NewDb();
            (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId))
                .ShouldBe(0, "the shred hard-deleted the rows (§F/T8) and the token wrote none back");
            (await db.CycleSettings.CountAsync(s => s.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
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

    private static async Task<bool> OnboardingCompletedAsync(HttpClient authed)
    {
        var me = await authed.GetAsync("/me");
        me.StatusCode.ShouldBe(HttpStatusCode.OK);
        return (await me.Content.ReadFromJsonAsync<JsonElement>())
            .GetProperty("onboardingCompleted").GetBoolean();
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
            displayName = "Completion Tester",
            locale = "es-ES",
            timezone = "Europe/Madrid",
            policyVersion = "v1-test",
        });
        start.StatusCode.ShouldBe(HttpStatusCode.OK);
        var userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();
        return (userId, await TestFixtures.GetUserTokenAsync(email, Password));
    }

    /// <summary>
    /// FK order: the P4a leaf tables first, then <c>user_profile_enc</c>, then <c>consent_records</c>
    /// (a <b>Restrict</b> FK — deleting the user first would fail), then <c>user_keys</c>, then the
    /// <c>users</c> row itself with the soft-delete filter bypassed.
    /// </summary>
    private static async Task CleanupAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        await db.CycleEvents.IgnoreQueryFilters().Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await db.CyclePhaseOverrides.IgnoreQueryFilters().Where(o => o.UserId == userId).ExecuteDeleteAsync();
        await db.CycleDayLogs.IgnoreQueryFilters().Where(l => l.UserId == userId).ExecuteDeleteAsync();
        await db.CycleTrackingPauseSpans.Where(s => s.UserId == userId).ExecuteDeleteAsync();
        await db.CycleSettings.Where(s => s.UserId == userId).ExecuteDeleteAsync();
        await db.UserGoals.Where(g => g.UserId == userId).ExecuteDeleteAsync();
        await db.UserHormonePrefs.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.UserNotificationPrefs.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.BodyMetrics.IgnoreQueryFilters().Where(m => m.UserId == userId).ExecuteDeleteAsync();
        await db.UserInsightSnapshots.Where(s => s.UserId == userId).ExecuteDeleteAsync();
        await db.UserDevices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
