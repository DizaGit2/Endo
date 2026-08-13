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
/// LIVE-STACK integration tests for the cycle write surface (T9): <c>POST /cycle/events</c>,
/// <c>DELETE /cycle/events/{id}</c> and <c>POST /cycle/phase-override</c>.
///
/// <para>These run against real Postgres, so they are the only place the §G9 UNFILTERED unique
/// indexes are actually enforced — Sqlite proves the code path, Postgres proves the constraint. They
/// also pin the three facts the unit suites cannot reach: notes really are ciphertext in the column,
/// the 400 really is <c>application/problem+json</c> with the frozen message, and a crypto-shredded
/// user's still-valid bearer token really is inert.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class CycleEventsLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";
    private const string Note = "dolor pélvico por la mañana";

    private static DateOnly Today => DateOnly.FromDateTime(
        TimeZoneInfo.ConvertTime(TimeProvider.System.GetUtcNow(), TimeZoneInfo.FindSystemTimeZoneById("Europe/Madrid")).Date);

    // --- encryption at rest ---------------------------------------------------------------

    [Fact]
    public async Task Logging_an_event_stores_the_note_as_ciphertext_and_a_re_post_rotates_it()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cyc-enc-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var first = await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = Today.ToString("yyyy-MM-dd"),
                flowIntensity = 3,
                notes = Note,
            });
            first.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await first.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("notes").GetString().ShouldBe(Note);
            body.GetProperty("source").GetString().ShouldBe(CycleEvent.Sources.User);
            var eventId = body.GetProperty("id").GetGuid();

            await using var dbBefore = TestFixtures.NewDb();
            var before = await dbBefore.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId);
            before.NotesEnc.ShouldNotBeNull();
            Encoding.UTF8.GetString(before.NotesEnc!).ShouldNotContain("dolor");
            before.NotesEnc!.Length.ShouldBeGreaterThanOrEqualTo(28); // 12-byte nonce + ciphertext + 16-byte tag
            var ciphertextBefore = Convert.ToBase64String(before.NotesEnc!);

            // Re-post the SAME (kind, day): one row, fresh nonce, so the stored blob must change.
            var second = await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = Today.ToString("yyyy-MM-dd"),
                flowIntensity = 4,
                notes = Note,
            });
            second.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await second.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid()
                .ShouldBe(eventId, "the upsert must reuse the row, not mint a second one");

            await using var dbAfter = TestFixtures.NewDb();
            var after = await dbAfter.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId);
            Convert.ToBase64String(after.NotesEnc!).ShouldNotBe(ciphertextBefore);
            Encoding.UTF8.GetString(after.NotesEnc!).ShouldNotContain("dolor");
            after.FlowIntensity.ShouldBe((short)4);
            (await dbAfter.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId)).ShouldBe(1);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the one 400 body -------------------------------------------------------------------

    [Fact]
    public async Task A_future_dated_event_returns_the_shared_400_and_writes_nothing()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cyc-400-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var response = await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = Today.AddDays(2).ToString("yyyy-MM-dd"),
                notes = Note,
            });

            response.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            response.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            problem.GetProperty("errors").GetProperty("occurredOn")[0].GetString()
                .ShouldBe("date must not be in the future");

            await using var db = TestFixtures.NewDb();
            (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- tenant isolation ---------------------------------------------------------------------

    [Fact]
    public async Task One_user_cannot_delete_another_users_event()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"cyc-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"cyc-int-{Guid.NewGuid():N}@example.com");

            var created = await Authed(ownerToken).PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.Spotting,
                occurredOn = Today.ToString("yyyy-MM-dd"),
            });
            created.StatusCode.ShouldBe(HttpStatusCode.OK);
            var eventId = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

            // 404, never 403: a 403 would confirm the id exists.
            var intrusion = await Authed(intruderToken).DeleteAsync($"/cycle/events/{eventId}");
            intrusion.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            var problem = await intrusion.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("title").GetString().ShouldBe("The requested resource was not found.");

            await using var db = TestFixtures.NewDb();
            var row = await db.CycleEvents.IgnoreQueryFilters().AsNoTracking().SingleAsync(e => e.Id == eventId);
            row.DeletedAt.ShouldBeNull("the owner's row must be untouched");
            row.UserId.ShouldBe(ownerId);

            // The owner can delete it, and the second attempt is a 404 (the tombstone is hidden).
            (await Authed(ownerToken).DeleteAsync($"/cycle/events/{eventId}")).StatusCode
                .ShouldBe(HttpStatusCode.NoContent);
            (await Authed(ownerToken).DeleteAsync($"/cycle/events/{eventId}")).StatusCode
                .ShouldBe(HttpStatusCode.NotFound);

            await using var after = TestFixtures.NewDb();
            (await after.CycleEvents.IgnoreQueryFilters().AsNoTracking().SingleAsync(e => e.Id == eventId))
                .DeletedAt.ShouldNotBeNull("DELETE is a soft delete (D-13), not a row removal");
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // --- §G9 tombstone revival, against the REAL Postgres unique indexes ------------------------

    [Fact]
    public async Task Re_logging_a_deleted_event_revives_the_row_against_the_real_unique_index()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cyc-rev-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var day = Today.AddDays(-3).ToString("yyyy-MM-dd");

            var created = await authed.PostAsJsonAsync("/cycle/events", new { kind = CycleEvent.Kinds.PeriodEnd, occurredOn = day });
            created.StatusCode.ShouldBe(HttpStatusCode.OK);
            var eventId = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

            (await authed.DeleteAsync($"/cycle/events/{eventId}")).StatusCode.ShouldBe(HttpStatusCode.NoContent);

            // The tombstone still occupies (UserId, Kind, OccurredOn), so a blind insert here is a
            // 23505 unique violation surfacing as a 500. This must be a 200 reviving the SAME row.
            var again = await authed.PostAsJsonAsync("/cycle/events", new { kind = CycleEvent.Kinds.PeriodEnd, occurredOn = day, flowIntensity = 2 });
            again.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await again.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid().ShouldBe(eventId);

            await using var db = TestFixtures.NewDb();
            (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId)).ShouldBe(1);
            (await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId)).DeletedAt.ShouldBeNull();
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Re_correcting_a_retracted_phase_boundary_revives_the_row_against_the_real_unique_index()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cyc-pho-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var cycleStart = Today.AddDays(-20);

            (await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = cycleStart.ToString("yyyy-MM-dd"),
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            var saved = await authed.PostAsJsonAsync("/cycle/phase-override", new
            {
                cycleStartOn = cycleStart.ToString("yyyy-MM-dd"),
                boundaries = new[]
                {
                    new
                    {
                        phase = CyclePhaseOverride.Phases.Menstrual,
                        boundary = CyclePhaseOverride.Boundaries.End,
                        occurredOn = cycleStart.AddDays(5).ToString("yyyy-MM-dd"),
                    },
                },
            });
            saved.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await saved.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("boundaries").GetArrayLength().ShouldBe(1);

            await using (var seed = TestFixtures.NewDb())
            {
                var row = await seed.CyclePhaseOverrides.AsNoTracking().SingleAsync(o => o.UserId == userId);
                row.Source.ShouldBe(CyclePhaseOverride.Sources.UserCorrection);
            }

            // "Reset to predicted" — soft-deletes the whole set.
            var reset = await authed.PostAsJsonAsync("/cycle/phase-override", new
            {
                cycleStartOn = cycleStart.ToString("yyyy-MM-dd"),
                boundaries = Array.Empty<object>(),
            });
            reset.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await reset.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("boundaries").GetArrayLength().ShouldBe(0);

            Guid originalId;
            await using (var mid = TestFixtures.NewDb())
            {
                var row = await mid.CyclePhaseOverrides.IgnoreQueryFilters().AsNoTracking().SingleAsync(o => o.UserId == userId);
                row.DeletedAt.ShouldNotBeNull();
                originalId = row.Id;
            }

            // Re-correcting the SAME (cycleStartOn, phase, boundary) after a retraction: the unfiltered
            // unique index means this is a 500 unless the tombstone is revived in place.
            var again = await authed.PostAsJsonAsync("/cycle/phase-override", new
            {
                cycleStartOn = cycleStart.ToString("yyyy-MM-dd"),
                boundaries = new[]
                {
                    new
                    {
                        phase = CyclePhaseOverride.Phases.Menstrual,
                        boundary = CyclePhaseOverride.Boundaries.End,
                        occurredOn = cycleStart.AddDays(6).ToString("yyyy-MM-dd"),
                    },
                },
            });
            again.StatusCode.ShouldBe(HttpStatusCode.OK);

            await using var db = TestFixtures.NewDb();
            (await db.CyclePhaseOverrides.IgnoreQueryFilters().CountAsync(o => o.UserId == userId)).ShouldBe(1);
            var revived = await db.CyclePhaseOverrides.AsNoTracking().SingleAsync(o => o.UserId == userId);
            revived.Id.ShouldBe(originalId);
            revived.DeletedAt.ShouldBeNull();
            revived.OccurredOn.ShouldBe(cycleStart.AddDays(6));
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the perimeter -------------------------------------------------------------------------

    [Fact]
    public async Task Every_cycle_route_requires_a_bearer_token()
    {
        var client = factory.CreateClient();

        (await client.PostAsJsonAsync("/cycle/events", new { kind = CycleEvent.Kinds.Spotting, occurredOn = Today.ToString("yyyy-MM-dd") }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        (await client.DeleteAsync($"/cycle/events/{Guid.NewGuid()}"))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        (await client.PostAsJsonAsync("/cycle/phase-override", new { cycleStartOn = Today.ToString("yyyy-MM-dd"), boundaries = Array.Empty<object>() }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_from_every_cycle_route()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cyc-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var day = Today.ToString("yyyy-MM-dd");

            var created = await authed.PostAsJsonAsync("/cycle/events", new { kind = CycleEvent.Kinds.PeriodStart, occurredOn = day });
            created.StatusCode.ShouldBe(HttpStatusCode.OK);
            var eventId = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

            // Erase the account. The bearer token stays cryptographically valid until it expires and
            // nothing else fences the write path, so the 404 below is the ONLY thing stopping this
            // token from re-creating plaintext health rows after erasure.
            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            var log = await authed.PostAsJsonAsync("/cycle/events", new { kind = CycleEvent.Kinds.PeriodEnd, occurredOn = day });
            log.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await log.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            (await authed.DeleteAsync($"/cycle/events/{eventId}")).StatusCode.ShouldBe(HttpStatusCode.NotFound);

            var override_ = await authed.PostAsJsonAsync("/cycle/phase-override", new
            {
                cycleStartOn = day,
                boundaries = Array.Empty<object>(),
            });
            override_.StatusCode.ShouldBe(HttpStatusCode.NotFound);

            // Nothing was re-created: the shred deleted every cycle row and the token wrote none back.
            await using var db = TestFixtures.NewDb();
            (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId)).ShouldBe(0);
            (await db.CyclePhaseOverrides.IgnoreQueryFilters().CountAsync(o => o.UserId == userId)).ShouldBe(0);
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
            displayName = "Cycle Tester",
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
        await db.CycleEvents.IgnoreQueryFilters().Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await db.CyclePhaseOverrides.IgnoreQueryFilters().Where(o => o.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
