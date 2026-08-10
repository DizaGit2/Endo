using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Lumen.Domain.Entities;
using Lumen.Infrastructure.Jobs;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for the day-log surface (T10): <c>POST /cycle/day/{date}</c>,
/// <c>POST /checkin/quick</c> and <c>GET /cycle/day/{date}</c>.
///
/// <para>Postgres is the only place the §G9 UNFILTERED unique index on <c>(UserId, Day)</c> is
/// actually enforced — Sqlite proves the code path, Postgres proves the constraint — and the only
/// place the 404 that fences an erased user's still-valid JWT can be driven end to end. The rest of
/// the behaviour lives in the unit suites; what is here is what a fake cannot prove.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class CycleDayLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";
    private const string Note = "cólicos por la mañana";

    private static DateOnly Today => DateOnly.FromDateTime(
        TimeZoneInfo.ConvertTime(TimeProvider.System.GetUtcNow(), TimeZoneInfo.FindSystemTimeZoneById("Europe/Madrid")).Date);

    private static string Day(int offset = 0) => Today.AddDays(offset).ToString("yyyy-MM-dd");

    // --- encryption at rest, and the read that round-trips it ---------------------------------

    [Fact]
    public async Task A_day_log_stores_the_note_as_ciphertext_a_re_post_rotates_it_and_the_read_decrypts_it()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"day-enc-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var first = await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 6, mood = 2, notes = Note });
            first.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await first.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("notes").GetString().ShouldBe(Note);
            body.GetProperty("pain").GetInt32().ShouldBe(6);
            body.GetProperty("day").GetString().ShouldBe(Day());

            await using var dbBefore = TestFixtures.NewDb();
            var before = await dbBefore.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId);
            before.NotesEnc.ShouldNotBeNull();
            Encoding.UTF8.GetString(before.NotesEnc!).ShouldNotContain("cólicos");
            before.NotesEnc!.Length.ShouldBeGreaterThanOrEqualTo(28); // 12-byte nonce + ciphertext + 16-byte tag
            var ciphertextBefore = Convert.ToBase64String(before.NotesEnc!);
            var rowId = before.Id;

            // Re-post the SAME day: one row, fresh nonce, so the stored blob must change.
            var second = await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 4, mood = 3, notes = Note });
            second.StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var dbAfter = TestFixtures.NewDb();
            var after = await dbAfter.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId);
            after.Id.ShouldBe(rowId, "the upsert must reuse the row, not mint a second one");
            Convert.ToBase64String(after.NotesEnc!).ShouldNotBe(ciphertextBefore);
            Encoding.UTF8.GetString(after.NotesEnc!).ShouldNotContain("cólicos");
            (await dbAfter.CycleDayLogs.IgnoreQueryFilters().CountAsync(l => l.UserId == userId)).ShouldBe(1);

            // GET decrypts the column back to plaintext, and carries the day's events too.
            (await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = Day(),
                flowIntensity = 3,
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            var read = await authed.GetAsync($"/cycle/day/{Day()}");
            read.StatusCode.ShouldBe(HttpStatusCode.OK);
            var day = await read.Content.ReadFromJsonAsync<JsonElement>();
            day.GetProperty("date").GetString().ShouldBe(Day());
            day.GetProperty("log").GetProperty("notes").GetString().ShouldBe(Note);
            day.GetProperty("log").GetProperty("pain").GetInt32().ShouldBe(4);
            day.GetProperty("events").GetArrayLength().ShouldBe(1);
            day.GetProperty("events")[0].GetProperty("kind").GetString().ShouldBe(CycleEvent.Kinds.PeriodStart);
            day.GetProperty("phaseOverrides").GetArrayLength().ShouldBe(0);

            // §G6: no clinical inference reaches the wire, not even as a placeholder key.
            day.TryGetProperty("phase", out _).ShouldBeFalse();
            day.TryGetProperty("cycleDay", out _).ShouldBeFalse();
            day.GetProperty("log").TryGetProperty("confidence", out _).ShouldBeFalse();

            // A day with nothing logged is 200 with a null log — 404 is reserved for "no such user".
            var empty = await authed.GetAsync($"/cycle/day/{Day(-30)}");
            empty.StatusCode.ShouldBe(HttpStatusCode.OK);
            var emptyDay = await empty.Content.ReadFromJsonAsync<JsonElement>();
            emptyDay.GetProperty("log").ValueKind.ShouldBe(JsonValueKind.Null);
            emptyDay.GetProperty("events").GetArrayLength().ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the one 400 body ------------------------------------------------------------------------

    [Fact]
    public async Task A_future_dated_day_log_returns_the_shared_400_and_writes_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"day-400-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var response = await authed.PostAsJsonAsync($"/cycle/day/{Day(1)}", new { pain = 5, notes = Note });

            response.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            response.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            problem.GetProperty("errors").GetProperty("date")[0].GetString()
                .ShouldBe("date must not be in the future");

            // An empty body is the cross-field rejection, under the reserved `request` key.
            var empty = await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { });
            empty.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await empty.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("request")[0].GetString()
                .ShouldBe("at least one of pain, mood or notes is required");

            var noCheckin = await authed.PostAsJsonAsync("/checkin/quick", new { });
            noCheckin.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await noCheckin.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("request")[0].GetString()
                .ShouldBe("at least one of pain or mood is required");

            await using var db = TestFixtures.NewDb();
            (await db.CycleDayLogs.IgnoreQueryFilters().CountAsync(l => l.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- §G9 tombstone revival against the REAL unique index --------------------------------------

    [Fact]
    public async Task Re_posting_a_soft_deleted_day_revives_the_row_against_the_real_unique_index()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"day-rev-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync($"/cycle/day/{Day(-4)}", new { pain = 7 })).StatusCode
                .ShouldBe(HttpStatusCode.OK);

            Guid originalId;
            await using (var seed = TestFixtures.NewDb())
            {
                var row = await seed.CycleDayLogs.SingleAsync(l => l.UserId == userId);
                originalId = row.Id;
                // P4a ships no DELETE for day logs, so the tombstone is written directly — the point
                // is the unfiltered index, not how the row got tombstoned. A crypto-shred is the only
                // other producer, and that one hard-deletes.
                row.DeletedAt = DateTimeOffset.UtcNow;
                await seed.SaveChangesAsync();
            }

            // The tombstone still occupies (UserId, Day): a blind insert here is a 23505 surfacing as
            // a 500. This must be a 200 reviving the SAME row.
            var again = await authed.PostAsJsonAsync($"/cycle/day/{Day(-4)}", new { pain = 2, notes = Note });
            again.StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            (await db.CycleDayLogs.IgnoreQueryFilters().CountAsync(l => l.UserId == userId)).ShouldBe(1);
            var revived = await db.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId);
            revived.Id.ShouldBe(originalId);
            revived.DeletedAt.ShouldBeNull();
            revived.Pain.ShouldBe((short)2);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- D-11: the quick check-in writes no symptom row and clears nothing it does not own ---------

    [Fact]
    public async Task A_quick_checkin_upserts_the_day_log_writes_no_symptom_row_and_keeps_the_full_forms_note()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"day-chk-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 5, mood = 2, notes = Note }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // pain 0 is a real datum (D-08), not "absent": it must be accepted and stored AS 0.
            var checkin = await authed.PostAsJsonAsync("/checkin/quick", new { pain = 0 });
            checkin.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await checkin.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("pain").GetInt32().ShouldBe(0);
            body.GetProperty("day").GetString().ShouldBe(Day());
            body.GetProperty("mood").GetInt32().ShouldBe(2, "an omitted field is left alone by the check-in");

            await using var db = TestFixtures.NewDb();
            (await db.CycleDayLogs.IgnoreQueryFilters().CountAsync(l => l.UserId == userId))
                .ShouldBe(1, "the check-in upserts the same (user, day) row");
            var row = await db.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId);
            row.Pain.ShouldBe((short)0);
            row.Mood.ShouldBe((short)2);
            row.NotesEnc.ShouldNotBeNull("a quick check-in must not delete the note the full form wrote");
            (await db.Symptoms.IgnoreQueryFilters().CountAsync(s => s.UserId == userId))
                .ShouldBe(0, "D-11: the quick check-in writes cycle_day_logs and NO symptoms row");

            // The read agrees with the column: 0, not null.
            var read = await authed.GetAsync($"/cycle/day/{Day()}");
            (await read.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("log").GetProperty("pain").GetInt32().ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- MERGE semantics on POST /cycle/day/{date} -------------------------------------------------

    [Fact]
    public async Task A_pain_only_day_post_leaves_the_mood_note_energy_and_libido_another_writer_filled()
    {
        // The unit suite constructs `LogCycleDayRequest` directly, so it can only prove that a null
        // member merges. THIS proves the rule the client actually exercises: `built_value` omits nulls,
        // so the fields below are genuinely ABSENT from the JSON on the wire, and they still must not
        // clear the row. `cycle_day_logs` is written by the day-detail form, by the quick check-in and
        // (once D-10 lifts) by the energy/libido scales — under full-upsert, any screen posting
        // without re-sending every field would silently destroy the others' data.
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"day-merge-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 2, mood = 3, notes = Note }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // Energy/libido have no writer in P4a (D-10 defers both scales), so they are seeded
            // directly — they stand in for any future writer of a column this DTO does not carry.
            await using (var seed = TestFixtures.NewDb())
            {
                var row = await seed.CycleDayLogs.SingleAsync(l => l.UserId == userId);
                row.Energy = 4;
                row.Libido = 2;
                await seed.SaveChangesAsync();
            }

            var painOnly = await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 7 });
            painOnly.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await painOnly.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("pain").GetInt32().ShouldBe(7);
            body.GetProperty("mood").GetInt32().ShouldBe(3, "an omitted field is left alone");
            body.GetProperty("notes").GetString().ShouldBe(Note, "the 200 body echoes the stored row");

            await using var db = TestFixtures.NewDb();
            var after = await db.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId);
            after.Pain.ShouldBe((short)7);
            after.Mood.ShouldBe((short)3, "mood survived a post that did not name it");
            after.Energy.ShouldBe((short)4, "energy survived");
            after.Libido.ShouldBe((short)2, "libido survived");
            after.NotesEnc.ShouldNotBeNull("the note survived");
            (await db.CycleDayLogs.IgnoreQueryFilters().CountAsync(l => l.UserId == userId)).ShouldBe(1);

            // And the read agrees with the columns.
            var read = await authed.GetAsync($"/cycle/day/{Day()}");
            var log = (await read.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("log");
            log.GetProperty("pain").GetInt32().ShouldBe(7);
            log.GetProperty("mood").GetInt32().ShouldBe(3);
            log.GetProperty("notes").GetString().ShouldBe(Note);

            // D-08 under merge: `pain: 0` is SUPPLIED and overwrites the 7; the rest still survives.
            var zero = await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 0 });
            zero.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await zero.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("pain").GetInt32().ShouldBe(0);

            await using var dbZero = TestFixtures.NewDb();
            var zeroed = await dbZero.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId);
            zeroed.Pain.ShouldBe((short)0, "0 is a datum, never 'not supplied'");
            zeroed.Mood.ShouldBe((short)3);
            zeroed.NotesEnc.ShouldNotBeNull();
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- tenant isolation --------------------------------------------------------------------------

    [Fact]
    public async Task One_users_day_is_invisible_to_another_and_their_writes_do_not_collide()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"day-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"day-int-{Guid.NewGuid():N}@example.com");

            (await Authed(ownerToken).PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 9, notes = Note }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // The same date for a different tenant is a different row, not a 23505 and not a read of
            // someone else's day.
            var theirRead = await Authed(intruderToken).GetAsync($"/cycle/day/{Day()}");
            theirRead.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await theirRead.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("log").ValueKind.ShouldBe(JsonValueKind.Null);

            (await Authed(intruderToken).PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 1 }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            var owner = await db.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == ownerId);
            owner.Pain.ShouldBe((short)9, "the owner's row must be untouched");
            owner.NotesEnc.ShouldNotBeNull();
            (await db.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == intruderId)).Pain.ShouldBe((short)1);
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // --- the perimeter -----------------------------------------------------------------------------

    [Fact]
    public async Task Every_cycle_day_route_requires_a_bearer_token()
    {
        var client = factory.CreateClient();

        (await client.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 3 }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        (await client.PostAsJsonAsync("/checkin/quick", new { pain = 3 }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        (await client.GetAsync($"/cycle/day/{Day()}"))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_from_every_cycle_day_route()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"day-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 5, notes = Note }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            // The bearer token stays cryptographically valid until it expires and nothing else fences
            // the write path, so the 404s below are the ONLY thing stopping this token from
            // re-creating plaintext health rows after erasure.
            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            var post = await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 8, notes = Note });
            post.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await post.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            (await authed.PostAsJsonAsync("/checkin/quick", new { pain = 4 })).StatusCode
                .ShouldBe(HttpStatusCode.NotFound);
            (await authed.GetAsync($"/cycle/day/{Day()}")).StatusCode.ShouldBe(HttpStatusCode.NotFound);

            await using var db = TestFixtures.NewDb();
            (await db.CycleDayLogs.IgnoreQueryFilters().CountAsync(l => l.UserId == userId))
                .ShouldBe(0, "the shred deleted the day log and the token wrote none back");
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
            displayName = "Day Tester",
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
        await db.CycleDayLogs.IgnoreQueryFilters().Where(l => l.UserId == userId).ExecuteDeleteAsync();
        await db.CycleEvents.IgnoreQueryFilters().Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await db.CyclePhaseOverrides.IgnoreQueryFilters().Where(o => o.UserId == userId).ExecuteDeleteAsync();
        await db.Symptoms.IgnoreQueryFilters().Where(s => s.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
