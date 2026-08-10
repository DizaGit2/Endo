using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Jobs;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for <c>POST /onboarding/baseline</c> and the profile-condition read
/// path on <c>GET /me</c> (T16).
///
/// <para>Postgres is the only place the <b>filtered</b> unique index on
/// <c>body_metrics (UserId, Metric, MeasuredOn) WHERE "DeletedAt" IS NULL</c> is actually enforced —
/// §G9's one deliberate tombstone exception, which exists so D-02's baseline step stays
/// re-submittable after a delete. Sqlite proves the code path; only this file proves the constraint,
/// and the delete-then-resubmit below is the exact sequence an unfiltered index would 500 on. It is
/// also the only place the real Vault-wrapped DEK encrypts these columns, so "the weight digits are
/// not in the row" is a claim about production crypto rather than a test cipher.</para>
///
/// <para>These tests are additionally the phase's guard that the route is <b>wired</b>: a later
/// <c>Program.cs</c> edit that dropped the baseline endpoint from <c>MapOnboardingEndpoints()</c>, or
/// that stopped splicing the condition fields into <c>MeResponse</c>, would turn the calls below into
/// 404s and nulls — so the suite cannot stay green with the resource unreachable.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class OnboardingBaselineLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";

    // --- the round trip, end to end ------------------------------------------------------------------

    [Fact]
    public async Task The_baseline_round_trips_through_GET_me_and_nothing_is_readable_in_the_database()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"base-rt-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var response = await authed.PostAsJsonAsync("/onboarding/baseline", new
            {
                dob = "1994-03-17",
                heightCm = 165,
                weightKg = 60.4,
                endoStatus = "diagnosed",
                rasrmStage = 3,
                diagnosedOn = "2023-08",
            });

            response.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await response.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("dob").GetString().ShouldBe("1994-03-17");
            body.GetProperty("heightCm").GetInt32().ShouldBe(165);
            body.GetProperty("endoStatus").GetString().ShouldBe("diagnosed");
            body.GetProperty("rasrmStage").GetInt32().ShouldBe(3);
            body.GetProperty("diagnosedOn").GetString().ShouldBe("2023-08");
            body.GetProperty("latestWeightKg").GetDecimal().ShouldBe(60.4m);

            // GET /me is the read path screen 31 binds to. Without it every column T7 added would be
            // write-only for the rest of the phase.
            var me = await (await authed.GetAsync("/me")).Content.ReadFromJsonAsync<JsonElement>();
            me.GetProperty("dob").GetString().ShouldBe("1994-03-17");
            me.GetProperty("heightCm").GetInt32().ShouldBe(165);
            me.GetProperty("endoStatus").GetString().ShouldBe("diagnosed");
            me.GetProperty("rasrmStage").GetInt32().ShouldBe(3);
            me.GetProperty("diagnosedOn").GetString().ShouldBe("2023-08");
            me.GetProperty("latestWeightKg").GetDecimal().ShouldBe(60.4m);
            // The pre-existing members are untouched: extending MeResponse is additive, never a rename.
            me.GetProperty("id").GetGuid().ShouldBe(userId);
            me.GetProperty("displayName").GetString().ShouldBe("Baseline Tester");
            me.GetProperty("locale").GetString().ShouldBe("es-ES");
            me.GetProperty("timezone").GetString().ShouldBe("Europe/Madrid");
            me.GetProperty("onboardingCompleted").GetBoolean().ShouldBeFalse();

            // At rest, under the REAL Vault-wrapped DEK: every one of these columns is ciphertext.
            await using var db = TestFixtures.NewDb();
            var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            var metric = await db.BodyMetrics.AsNoTracking().SingleAsync(m => m.UserId == userId);

            AssertOpaque(profile.DobEnc, "1994-03-17", nameof(profile.DobEnc));
            AssertOpaque(profile.HeightCmEnc, "165", nameof(profile.HeightCmEnc));
            AssertOpaque(profile.EndoStatusEnc, "diagnosed", nameof(profile.EndoStatusEnc));
            AssertOpaque(profile.RasrmStageEnc, "3", nameof(profile.RasrmStageEnc));
            AssertOpaque(profile.DiagnosedOnEnc, "2023-08", nameof(profile.DiagnosedOnEnc));
            AssertOpaque(metric.ValueEnc, "60.4", nameof(metric.ValueEnc));

            metric.Metric.ShouldBe(BodyMetric.Metrics.WeightKg);
            metric.Source.ShouldBe(BodyMetric.Sources.Manual);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task The_condition_fields_are_null_on_GET_me_before_the_step_has_run()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"base-null-{Guid.NewGuid():N}@example.com");

            var me = await (await Authed(token).GetAsync("/me")).Content.ReadFromJsonAsync<JsonElement>();

            foreach (var field in new[] { "dob", "heightCm", "endoStatus", "rasrmStage", "diagnosedOn", "latestWeightKg" })
            {
                me.GetProperty(field).ValueKind.ShouldBe(
                    JsonValueKind.Null, $"'{field}' must be null until the user answers — never fabricated");
            }
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- idempotency against the REAL filtered unique index ------------------------------------------

    [Fact]
    public async Task Re_submitting_the_step_is_idempotent_against_the_real_filtered_unique_index()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"base-idem-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            // A blind insert on the second call is a 23505 against the real index, surfacing as a 500 —
            // on a step D-02 explicitly lets the user revisit.
            (await authed.PostAsJsonAsync("/onboarding/baseline", new { weightKg = 60.4, heightCm = 165 }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            var second = await authed.PostAsJsonAsync("/onboarding/baseline", new { weightKg = 61.2 });
            second.StatusCode.ShouldBe(HttpStatusCode.OK, "an upsert, never a 409 and never a 500");

            var body = await second.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("latestWeightKg").GetDecimal().ShouldBe(61.2m);
            body.GetProperty("heightCm").GetInt32().ShouldBe(165, "an omitted field is left unchanged, never cleared");

            await using var db = TestFixtures.NewDb();
            (await db.BodyMetrics.CountAsync(m => m.UserId == userId))
                .ShouldBe(1, "rider 4: the weight has ONE source of truth, and it does not stack");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task The_step_stays_re_submittable_after_the_weight_row_is_soft_deleted()
    {
        // §G9's one deliberate FILTERED-index exception, proven where it is actually enforced. Under an
        // unfiltered index the tombstone would keep occupying the key and this would be a 500 on a row
        // the user believes they deleted.
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"base-del-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync("/onboarding/baseline", new { weightKg = 60.4 }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            Guid tombstonedId;
            await using (var delete = TestFixtures.NewDb())
            {
                var row = await delete.BodyMetrics.SingleAsync(m => m.UserId == userId);
                tombstonedId = row.Id;
                row.DeletedAt = DateTimeOffset.UtcNow;
                await delete.SaveChangesAsync();
            }

            var resubmit = await authed.PostAsJsonAsync("/onboarding/baseline", new { weightKg = 62.5 });
            resubmit.StatusCode.ShouldBe(HttpStatusCode.OK, "the filtered index frees the key a tombstone held");
            (await resubmit.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("latestWeightKg").GetDecimal().ShouldBe(62.5m);

            await using var db = TestFixtures.NewDb();
            var live = await db.BodyMetrics.AsNoTracking().SingleAsync(m => m.UserId == userId);
            live.Id.ShouldNotBe(tombstonedId, "a NEW row, not a revived tombstone");
            (await db.BodyMetrics.IgnoreQueryFilters().CountAsync(m => m.UserId == userId)).ShouldBe(2);
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
            (userId, var token) = await OnboardAndLoginAsync($"base-400-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var empty = await authed.PostAsJsonAsync("/onboarding/baseline", new { });
            empty.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            empty.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var emptyProblem = await empty.Content.ReadFromJsonAsync<JsonElement>();
            emptyProblem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            emptyProblem.GetProperty("errors").GetProperty("request")[0].GetString()
                .ShouldBe("provide at least one baseline field");

            var everything = await authed.PostAsJsonAsync("/onboarding/baseline", new
            {
                dob = "2099-01-01",
                heightCm = 0,
                weightKg = 60.44,
                endoStatus = "Diagnosed",
                rasrmStage = 5,
                diagnosedOn = "2023-13",
            });
            everything.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            var errors = (await everything.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("errors");
            errors.GetProperty("dob")[0].GetString().ShouldBe("date must not be in the future");
            errors.GetProperty("heightCm")[0].GetString().ShouldBe("value must be between 1 and 32767");
            errors.GetProperty("weightKg")[0].GetString().ShouldBe("value must have at most 1 decimal place");
            errors.GetProperty("endoStatus")[0].GetString().ShouldBe("value is not one of the allowed values");
            errors.GetProperty("rasrmStage")[0].GetString().ShouldBe("value must be between 1 and 4");
            errors.GetProperty("diagnosedOn")[0].GetString().ShouldBe("value must be a month in the form yyyy-MM");

            var weightRange = await authed.PostAsJsonAsync("/onboarding/baseline", new { weightKg = 0 });
            weightRange.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await weightRange.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("weightKg")[0].GetString()
                .ShouldBe("value must be greater than 0 and at most 9999.9");

            await using var db = TestFixtures.NewDb();
            (await db.BodyMetrics.CountAsync(m => m.UserId == userId))
                .ShouldBe(0, "validate-then-act: every rejected request wrote nothing");
            var profile = await db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            profile.HeightCmEnc.ShouldBeNull();
            profile.EndoStatusEnc.ShouldBeNull();
            profile.RasrmStageEnc.ShouldBeNull();
            profile.DiagnosedOnEnc.ShouldBeNull();
            profile.DobEnc.ShouldBeNull();
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the perimeter --------------------------------------------------------------------------------

    [Fact]
    public async Task The_baseline_route_requires_a_bearer_token()
    {
        var client = factory.CreateClient();

        (await client.PostAsJsonAsync("/onboarding/baseline", new { heightCm = 165 }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_and_writes_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"base-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync("/onboarding/baseline", new { weightKg = 60.4 }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            // A body that would otherwise be a 400 still answers "no such user": the fence runs before
            // validation, so the shape of the answer leaks nothing about the request being understood.
            var write = await authed.PostAsJsonAsync("/onboarding/baseline", new { rasrmStage = 99 });
            write.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            write.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            (await write.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            await using var db = TestFixtures.NewDb();
            (await db.BodyMetrics.IgnoreQueryFilters().CountAsync(m => m.UserId == userId))
                .ShouldBe(0, "the shred hard-deleted the metric row (§F/T8) and the token wrote none back");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task One_users_baseline_is_invisible_to_another()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"base-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"base-int-{Guid.NewGuid():N}@example.com");

            (await Authed(ownerToken).PostAsJsonAsync("/onboarding/baseline", new
            {
                heightCm = 165,
                weightKg = 60.4,
                endoStatus = "diagnosed",
                rasrmStage = 3,
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            var intruderMe = await (await Authed(intruderToken).GetAsync("/me"))
                .Content.ReadFromJsonAsync<JsonElement>();
            intruderMe.GetProperty("heightCm").ValueKind.ShouldBe(JsonValueKind.Null);
            intruderMe.GetProperty("latestWeightKg").ValueKind.ShouldBe(JsonValueKind.Null);
            intruderMe.GetProperty("rasrmStage").ValueKind.ShouldBe(JsonValueKind.Null);

            (await Authed(intruderToken).PostAsJsonAsync("/onboarding/baseline", new { heightCm = 180 }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            var ownerMe = await (await Authed(ownerToken).GetAsync("/me")).Content.ReadFromJsonAsync<JsonElement>();
            ownerMe.GetProperty("heightCm").GetInt32().ShouldBe(165, "another tenant's write must not touch this row");

            await using var db = TestFixtures.NewDb();
            (await db.BodyMetrics.CountAsync(m => m.UserId == intruderId)).ShouldBe(0);
            (await db.BodyMetrics.CountAsync(m => m.UserId == ownerId)).ShouldBe(1);
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static void AssertOpaque(byte[]? cipher, string plaintext, string column)
    {
        cipher.ShouldNotBeNull(column);
        Encoding.UTF8.GetString(cipher!).ShouldNotContain(
            plaintext, Case.Sensitive, $"{column} must be AES-GCM ciphertext, never the plaintext");
        cipher!.ShouldNotBe(Encoding.UTF8.GetBytes(plaintext), column);
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
            displayName = "Baseline Tester",
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
        await db.BodyMetrics.IgnoreQueryFilters().Where(m => m.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
