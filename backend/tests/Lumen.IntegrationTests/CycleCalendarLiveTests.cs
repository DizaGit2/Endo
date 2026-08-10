using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
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
/// LIVE-STACK integration tests for the windowed cycle calendar (T13): <c>GET /cycle/calendar?from&amp;to</c>.
///
/// <para>What only the live stack can prove: that the route is actually <b>wired into
/// <c>Program.cs</c></b> (a later edit could silently unwire it and every unit test would stay
/// green); that the aggregation runs on <b>Postgres</b>, where the <c>GROUP BY</c> over the day-keyed
/// indexes is the query that ships; that the <b>JSON on the wire</b> carries the §G6 phase envelope
/// once and carries <b>no <c>phase</c>, <c>cycleDay</c> or <c>confidence</c> key on any day row</b>;
/// that <b>no note plaintext appears anywhere in the response</b>; and that an erased account's
/// still-valid JWT is fenced out with a 404. The rest of the behaviour lives in
/// <c>CycleCalendarServiceTests</c>.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class CycleCalendarLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";
    private const string Timezone = "Europe/Madrid";

    /// <summary>The distinctive note plaintext the response must never contain.</summary>
    private const string Note = "cólicos por la mañana";

    private static DateOnly Today => DateOnly.FromDateTime(
        TimeZoneInfo.ConvertTime(TimeProvider.System.GetUtcNow(), TimeZoneInfo.FindSystemTimeZoneById(Timezone)).Date);

    private static string Day(int offset = 0) => Today.AddDays(offset).ToString("yyyy-MM-dd");

    // --- the aggregation, on the database that ships ----------------------------------------------

    [Fact]
    public async Task The_calendar_counts_day_logs_events_and_symptoms_and_leaks_no_note_plaintext()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cal-agg-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            // Today: a day log with an encrypted note, two events (the unique key is (user, kind,
            // day), so two events on one day means two kinds) and two symptoms.
            (await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 7, mood = 2, notes = Note }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = Day(),
                flowIntensity = 3,
                notes = Note,
            })).StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.Spotting,
                occurredOn = Day(),
            })).StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.PostAsJsonAsync("/symptoms", new
            {
                entries = new object[]
                {
                    new { symptomCode = Symptom.Codes.Pain, intensity = 6, notes = Note },
                    new { symptomCode = Symptom.NonPainCodes.Bloating, intensity = 4 },
                },
            })).StatusCode.ShouldBe(HttpStatusCode.Created);

            // Two days back: a day log with no note at all, so `hasNotes` has a false case to prove.
            (await authed.PostAsJsonAsync($"/cycle/day/{Day(-2)}", new { pain = 0 }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            var response = await authed.GetAsync($"/cycle/calendar?from={Day(-5)}&to={Day()}");
            response.StatusCode.ShouldBe(HttpStatusCode.OK);

            // Read the RAW body first: the plaintext assertion has to see the bytes the client gets,
            // not a re-serialised object graph.
            var raw = await response.Content.ReadAsStringAsync();
            raw.ShouldNotContain("cólicos", Case.Insensitive);
            raw.ShouldNotContain("mañana", Case.Insensitive);

            var body = JsonDocument.Parse(raw).RootElement;
            body.GetProperty("from").GetString().ShouldBe(Day(-5));
            body.GetProperty("to").GetString().ShouldBe(Day());
            body.GetProperty("today").GetString().ShouldBe(Day(), "today is the user's local day (D-12)");
            body.GetProperty("timezone").GetString().ShouldBe(Timezone);

            // §G6: the phase envelope, once, on the response — the ONLY phase-shaped thing here.
            var phase = body.GetProperty("phase");
            phase.GetProperty("available").GetBoolean().ShouldBeFalse();
            phase.GetProperty("unavailableReason").GetString().ShouldBe("phase_engine_not_implemented");
            body.TryGetProperty("cycleDay", out _).ShouldBeFalse();
            body.TryGetProperty("confidence", out _).ShouldBeFalse();

            var days = body.GetProperty("days").EnumerateArray().ToList();
            days.Count.ShouldBe(2, "only days with something on them appear (sparse)");

            // §G6 again, and this is the assertion that matters most: NOT ONE day row may carry a
            // phase, a cycle day or a confidence. A placeholder key is exactly how a not-yet-computed
            // estimate gets rendered as a clinical fact.
            foreach (var day in days)
            {
                day.TryGetProperty("phase", out _).ShouldBeFalse();
                day.TryGetProperty("cycleDay", out _).ShouldBeFalse();
                day.TryGetProperty("confidence", out _).ShouldBeFalse();
                day.TryGetProperty("notes", out _).ShouldBeFalse("the calendar exposes a flag, never the note");
            }

            var older = days.Single(d => d.GetProperty("date").GetString() == Day(-2));
            older.GetProperty("pain").GetInt32().ShouldBe(0, "pain 0 is a datum, never an absence (D-08)");
            older.GetProperty("hasNotes").GetBoolean().ShouldBeFalse();
            older.GetProperty("eventCount").GetInt32().ShouldBe(0);
            older.GetProperty("symptomCount").GetInt32().ShouldBe(0);

            var today = days.Single(d => d.GetProperty("date").GetString() == Day());
            today.GetProperty("pain").GetInt32().ShouldBe(7);
            today.GetProperty("mood").GetInt32().ShouldBe(2);
            today.GetProperty("hasNotes").GetBoolean().ShouldBeTrue();
            today.GetProperty("eventCount").GetInt32().ShouldBe(2);
            today.GetProperty("symptomCount").GetInt32().ShouldBe(2);

            // The notes really are on the rows the counts came from — so the absence above is the
            // endpoint declining to decrypt, not an empty database.
            await using var db = TestFixtures.NewDb();
            (await db.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId && l.Day == Today))
                .NotesEnc.ShouldNotBeNull();
            (await db.CycleEvents.AsNoTracking()
                .SingleAsync(e => e.UserId == userId && e.Kind == CycleEvent.Kinds.PeriodStart))
                .NotesEnc.ShouldNotBeNull();
            (await db.Symptoms.AsNoTracking()
                .SingleAsync(s => s.UserId == userId && s.SymptomCode == Symptom.Codes.Pain))
                .NotesEnc.ShouldNotBeNull();
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the default window --------------------------------------------------------------------

    [Fact]
    public async Task An_absent_from_and_to_default_to_the_users_current_month()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cal-def-{Guid.NewGuid():N}@example.com");

            var response = await Authed(token).GetAsync("/cycle/calendar");
            response.StatusCode.ShouldBe(HttpStatusCode.OK);

            var body = await response.Content.ReadFromJsonAsync<JsonElement>();
            var monthStart = new DateOnly(Today.Year, Today.Month, 1);
            body.GetProperty("from").GetString().ShouldBe(monthStart.ToString("yyyy-MM-dd"));
            body.GetProperty("to").GetString()
                .ShouldBe(monthStart.AddMonths(1).AddDays(-1).ToString("yyyy-MM-dd"));
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- the §G11 window cap, at both boundaries -------------------------------------------------

    [Fact]
    public async Task A_366_day_window_is_accepted_and_a_367_day_one_is_the_shared_400()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cal-cap-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            // 366 days inclusive: from + 365.
            (await authed.GetAsync($"/cycle/calendar?from={Day(-365)}&to={Day()}"))
                .StatusCode.ShouldBe(HttpStatusCode.OK);

            var tooWide = await authed.GetAsync($"/cycle/calendar?from={Day(-366)}&to={Day()}");
            tooWide.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            tooWide.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await tooWide.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            problem.GetProperty("errors").GetProperty("to")[0].GetString()
                .ShouldBe("the range must not exceed 366 days");

            var inverted = await authed.GetAsync($"/cycle/calendar?from={Day()}&to={Day(-1)}");
            inverted.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            (await inverted.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("errors").GetProperty("to")[0].GetString()
                .ShouldBe("date must not be before the start of the range");

            // An unparseable bound fails at the binder and becomes T3's one 400 under `request`.
            var unparseable = await authed.GetAsync("/cycle/calendar?from=not-a-date");
            unparseable.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- tenant isolation ---------------------------------------------------------------------------

    [Fact]
    public async Task One_users_calendar_never_shows_another_users_rows()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"cal-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"cal-int-{Guid.NewGuid():N}@example.com");

            (await Authed(ownerToken).PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 9, notes = Note }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await Authed(ownerToken).PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = Day(),
            })).StatusCode.ShouldBe(HttpStatusCode.OK);

            // The intruder's own calendar over the same window is EMPTY — not a 403, and certainly
            // not the owner's rows. A range read has no id to 404 on, so "empty" is the isolation.
            var theirs = await Authed(intruderToken).GetAsync($"/cycle/calendar?from={Day(-3)}&to={Day()}");
            theirs.StatusCode.ShouldBe(HttpStatusCode.OK);
            var raw = await theirs.Content.ReadAsStringAsync();
            raw.ShouldNotContain("cólicos", Case.Insensitive);
            JsonDocument.Parse(raw).RootElement.GetProperty("days").GetArrayLength().ShouldBe(0);

            // And the owner still sees their own.
            var owner = await Authed(ownerToken).GetAsync($"/cycle/calendar?from={Day(-3)}&to={Day()}");
            var ownerDays = (await owner.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("days");
            ownerDays.GetArrayLength().ShouldBe(1);
            ownerDays[0].GetProperty("pain").GetInt32().ShouldBe(9);
            ownerDays[0].GetProperty("eventCount").GetInt32().ShouldBe(1);
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // --- the perimeter -------------------------------------------------------------------------------

    [Fact]
    public async Task The_calendar_route_requires_a_bearer_token()
    {
        (await factory.CreateClient().GetAsync("/cycle/calendar"))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_from_the_calendar()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"cal-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            (await authed.PostAsJsonAsync($"/cycle/day/{Day()}", new { pain = 5, notes = Note }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            (await authed.GetAsync("/cycle/calendar")).StatusCode.ShouldBe(HttpStatusCode.OK);

            // The token stays cryptographically valid until it expires. On a READ the 404 matters for
            // its own reason: a successful empty answer would still confirm the account existed, and
            // a successful non-empty one would hand back health data after erasure.
            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            var after = await authed.GetAsync("/cycle/calendar");
            after.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await after.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");
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
            displayName = "Calendar Tester",
            locale = "es-ES",
            timezone = Timezone,
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
