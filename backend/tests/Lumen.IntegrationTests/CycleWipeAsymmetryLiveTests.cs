using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Lumen.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK proof of the <c>POST /cycle/events</c> FULL-UPSERT <b>wipe</b> (P4b-T16d) — and of the
/// fact that the byte-identical request body is a <b>no-op</b> on <c>POST /cycle/day/{date}</c>.
///
/// <para><b>The two sites.</b> <see cref="Lumen.Api.Cycle.CycleService.LogEventAsync"/> assigns
/// <c>row.FlowIntensity</c> and <c>row.NotesEnc</c> with <b>no <c>if</c> around either</b>, so an
/// upsert that does not name a field destroys whatever was stored in it.
/// <see cref="Lumen.Api.Cycle.CycleDayService.UpsertDayAsync"/> assigns <c>row.NotesEnc</c> INSIDE
/// <c>if (notesEnc is not null)</c>, and in the other branch decrypts the stored note back out for
/// the echo — so the same input changes nothing there. Both rules are deliberate and are stated on
/// their DTOs in <c>CycleContracts.cs</c>; the value of pinning them <b>together, in one file</b> is
/// that the mistake this guards against is not "the rule is wrong", it is <b>somebody reasoning from
/// one endpoint to the other</b> — which has already happened once inside this phase.</para>
///
/// <para><b>Why every assertion below reads POSTGRES and not the 200 body.</b> The two endpoints echo
/// from different places. <c>/cycle/day</c> echoes the STORED row, so its body can report a field the
/// request never sent. <c>/cycle/events</c> builds its body out of the REQUEST — <c>notes</c> from
/// the trimmed request string, <c>flowIntensity</c> from the row it was assigned onto a line earlier
/// — so that body reads "null" whether or not the column was actually cleared. <b>An assertion on the
/// event response would pass with the wipe and without it</b>: it is the defect, not the proof.</para>
///
/// <para><b>And the note is CIPHERTEXT.</b> <c>cycle_events.notes_enc</c> is a per-user
/// envelope-encrypted <c>bytea</c>. "Erased" is asserted here as <c>NotesEnc is null</c> — the blob
/// itself is gone from the column, not merely missing from some projection — and "survived" is
/// asserted as the SAME base64, which is stronger than non-null: a re-encryption would also leave a
/// non-null blob behind.</para>
///
/// <para><b>Four shapes for the note, because a client sends more than one.</b> The request string is
/// trimmed before it is measured, so <b>absent</b>, <b>explicit null</b>, <b>empty string</b> and
/// <b>whitespace</b> all arrive at the assignment as <see langword="null"/>, and all four wipe. A test
/// that covered only "absent" would miss the shape a text field actually produces when a user selects
/// its contents and deletes them.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class CycleWipeAsymmetryLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";
    private const string Note = "dolor pélvico al despertar";

    // The blank-note fragments, named so the theory rows read as wire shapes rather than as escapes.
    private const string NotesNull = "\"notes\": null,";
    private const string NotesEmpty = "\"notes\": \"\",";
    private const string NotesWhitespace = "\"notes\": \"   \",";

    private static DateOnly Today => DateOnly.FromDateTime(
        TimeZoneInfo.ConvertTime(TimeProvider.System.GetUtcNow(), TimeZoneInfo.FindSystemTimeZoneById("Europe/Madrid")).Date);

    private static string Day(int offset = 0) => Today.AddDays(offset).ToString("yyyy-MM-dd");

    // --- R1 + R2: the same blank note, on both endpoints, in all four shapes ----------------------

    [Theory]
    [InlineData("an absent", "")]
    [InlineData("an explicitly null", NotesNull)]
    [InlineData("an empty-string", NotesEmpty)]
    [InlineData("a whitespace-only", NotesWhitespace)]
    public async Task The_same_blank_note_destroys_the_events_ciphertext_and_leaves_the_day_logs_untouched(
        string shape, string noteFields)
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"wipe-note-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var day = Day(-1);

            // Seed BOTH rows on the same day with the same plaintext, so the only thing that differs in
            // the second half of this test is which endpoint the identical body was posted to.
            (await authed.PostAsJsonAsync($"/cycle/day/{day}", new { pain = 5, notes = Note }))
                .StatusCode.ShouldBe(HttpStatusCode.OK);
            var created = await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = day,
                flowIntensity = 3,
                notes = Note,
            });
            created.StatusCode.ShouldBe(HttpStatusCode.OK);
            var eventId = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

            string dayCiphertextBefore;
            await using (var db = TestFixtures.NewDb())
            {
                var eventBefore = await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId);
                eventBefore.NotesEnc.ShouldNotBeNull();
                eventBefore.NotesEnc!.Length.ShouldBeGreaterThanOrEqualTo(28); // 12-byte nonce + ciphertext + 16-byte tag
                Encoding.UTF8.GetString(eventBefore.NotesEnc!).ShouldNotContain("dolor");

                var logBefore = await db.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId);
                logBefore.NotesEnc.ShouldNotBeNull();
                dayCiphertextBefore = Convert.ToBase64String(logBefore.NotesEnc!);
            }

            // The identical note fragment, posted to each endpoint. `flowIntensity` and `pain` are
            // re-sent so that the ONLY field under test is the note: without `pain` the day-log post is
            // a 400 (at least one of pain, mood or notes), and without `flowIntensity` the event post
            // would clear a second column and blur which assignment this test is measuring.
            var eventResponse = await PostJsonAsync(
                authed, "/cycle/events", EventJson(day, noteFields + " \"flowIntensity\": 3,"));
            eventResponse.StatusCode.ShouldBe(HttpStatusCode.OK);

            var dayResponse = await PostJsonAsync(authed, $"/cycle/day/{day}", DayJson(noteFields));
            dayResponse.StatusCode.ShouldBe(HttpStatusCode.OK);

            // THE PROOF — the stored rows. Nothing above this line establishes anything about them.
            await using (var db = TestFixtures.NewDb())
            {
                var eventAfter = await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId);
                eventAfter.NotesEnc.ShouldBeNull(
                    $"{shape} note on POST /cycle/events must destroy the stored ciphertext, not be ignored");
                eventAfter.FlowIntensity.ShouldBe((short)3, "the re-sent flow level is untouched");
                (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId))
                    .ShouldBe(1, "the wipe happens on the SAME row — this is an upsert, not a new insert");

                var logAfter = await db.CycleDayLogs.AsNoTracking().SingleAsync(l => l.UserId == userId);
                logAfter.NotesEnc.ShouldNotBeNull(
                    $"{shape} note on POST /cycle/day/{{date}} is absent text, never an instruction to erase");
                Convert.ToBase64String(logAfter.NotesEnc!).ShouldBe(
                    dayCiphertextBefore,
                    "byte for byte: the merge branch does not even re-encrypt, so the blob is the original one");
            }

            // The bodies, LAST and deliberately: they are the trap this file exists to disarm. The event
            // body reports a null note because it echoes the request, and would report exactly this null
            // if the assignment were guarded and the column still held its ciphertext.
            (await eventResponse.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("notes").ValueKind.ShouldBe(JsonValueKind.Null);
            (await dayResponse.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("notes").GetString().ShouldBe(Note, "the day-log body echoes the STORED note back");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- R1: the flow level, in the only two shapes an `int?` can take ---------------------------

    [Theory]
    [InlineData("an absent", "")]
    [InlineData("an explicitly null", "\"flowIntensity\": null,")]
    public async Task An_event_upsert_that_does_not_name_the_flow_level_clears_the_stored_column(
        string shape, string flowFields)
    {
        // Only two shapes, not the note's four: `flowIntensity` is an `int?`, so `""` and `"   "` are
        // not values it can carry — they fail JSON binding before the service is reached. That case is
        // covered separately below, because a body the server cannot read must also clear nothing.
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"wipe-flow-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var day = Day(-2);

            var created = await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = day,
                flowIntensity = 4,
                notes = Note,
            });
            created.StatusCode.ShouldBe(HttpStatusCode.OK);
            var eventId = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

            await using (var db = TestFixtures.NewDb())
                (await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId)).FlowIntensity.ShouldBe((short)4);

            // The note is re-sent so the note column is not the thing that moves here.
            var response = await PostJsonAsync(
                authed, "/cycle/events", EventJson(day, flowFields + $" \"notes\": \"{Note}\","));
            response.StatusCode.ShouldBe(HttpStatusCode.OK);

            await using (var db = TestFixtures.NewDb())
            {
                var after = await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId);
                after.FlowIntensity.ShouldBeNull(
                    $"{shape} flowIntensity on POST /cycle/events must clear the stored level — that is the "
                    + "only way a user takes a flow level back off an event");
                after.NotesEnc.ShouldNotBeNull("the re-sent note is untouched");
                (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId)).ShouldBe(1);
            }
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- R1: the shape a real client actually sends — neither field named at all ------------------

    [Fact]
    public async Task A_bare_event_repost_clears_the_flow_and_the_note_together_on_the_surviving_row()
    {
        // The two theories above each hold one field steady in order to isolate the other. This is the
        // body a client that "just re-confirms the day" sends, and it clears BOTH columns at once.
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"wipe-bare-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var day = Day(-3);

            var created = await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = day,
                flowIntensity = 4,
                notes = Note,
            });
            created.StatusCode.ShouldBe(HttpStatusCode.OK);
            var eventId = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

            DateTimeOffset createdAt;
            await using (var db = TestFixtures.NewDb())
            {
                var before = await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId);
                before.FlowIntensity.ShouldBe((short)4);
                before.NotesEnc.ShouldNotBeNull();
                createdAt = before.CreatedAt;
            }

            var response = await PostJsonAsync(authed, "/cycle/events", EventJson(day, string.Empty));
            response.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid().ShouldBe(eventId);

            await using (var db = TestFixtures.NewDb())
            {
                var after = await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId);
                after.FlowIntensity.ShouldBeNull("the omitted flow level is cleared");
                after.NotesEnc.ShouldBeNull("the omitted note's ciphertext is destroyed");
                after.DeletedAt.ShouldBeNull("the row survives the wipe — only its two optional columns are emptied");
                after.CreatedAt.ShouldBe(createdAt, "CreatedAt belongs to the observation, not to this edit");
                (await db.CycleEvents.IgnoreQueryFilters().CountAsync(e => e.UserId == userId)).ShouldBe(1);
            }
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- a body the server cannot read must clear nothing at all ----------------------------------

    [Fact]
    public async Task A_flow_level_the_server_cannot_parse_is_rejected_and_wipes_neither_column()
    {
        // `"flowIntensity": ""` is the `int?` counterpart of the note's empty-string shape. It never
        // reaches LogEventAsync — the body fails to bind first — and the point of asserting it is that
        // a rejected request must leave the row exactly as it was, wipe rule or no wipe rule.
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"wipe-bind-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);
            var day = Day(-4);

            var created = await authed.PostAsJsonAsync("/cycle/events", new
            {
                kind = CycleEvent.Kinds.PeriodStart,
                occurredOn = day,
                flowIntensity = 2,
                notes = Note,
            });
            created.StatusCode.ShouldBe(HttpStatusCode.OK);
            var eventId = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

            string ciphertextBefore;
            await using (var db = TestFixtures.NewDb())
                ciphertextBefore = Convert.ToBase64String(
                    (await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId)).NotesEnc!);

            var response = await PostJsonAsync(authed, "/cycle/events", EventJson(day, "\"flowIntensity\": \"\","));
            response.StatusCode.ShouldBe(HttpStatusCode.BadRequest);

            await using (var db = TestFixtures.NewDb())
            {
                var after = await db.CycleEvents.AsNoTracking().SingleAsync(e => e.Id == eventId);
                after.FlowIntensity.ShouldBe((short)2, "an unreadable body writes nothing, so it clears nothing");
                Convert.ToBase64String(after.NotesEnc!).ShouldBe(ciphertextBefore);
            }
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // ------------------------------------------------------------------ helpers

    /// <summary>
    /// The event body as RAW JSON, on purpose: <b>absent</b> and <b>explicit null</b> are different
    /// bytes on the wire and indistinguishable in any C# object model, so an anonymous object cannot
    /// express the distinction this whole file is about. <paramref name="fields"/> is spliced in ahead
    /// of the two required keys, so an empty fragment still leaves valid JSON behind.
    /// </summary>
    private static string EventJson(string occurredOn, string fields) =>
        $$"""{ {{fields}} "kind": "{{CycleEvent.Kinds.PeriodStart}}", "occurredOn": "{{occurredOn}}" }""";

    /// <summary>The day-log body, taking the SAME <paramref name="fields"/> fragment as <see cref="EventJson"/>.</summary>
    private static string DayJson(string fields) => $$"""{ {{fields}} "pain": 5 }""";

    private static Task<HttpResponseMessage> PostJsonAsync(HttpClient client, string url, string json) =>
        client.PostAsync(url, new StringContent(json, Encoding.UTF8, "application/json"));

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
            displayName = "Wipe Tester",
            locale = "es-ES",
            timezone = "Europe/Madrid",
            policyVersion = "v1-test",
        });
        start.StatusCode.ShouldBe(HttpStatusCode.OK);
        var userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();
        return (userId, await TestFixtures.GetUserTokenAsync(email, Password));
    }

    /// <summary>
    /// Reclaims ONLY the rows this test planted, keyed on the user it onboarded. The Keycloak account
    /// is deliberately left alone — reclaiming realm accounts belongs to <c>TestResidueSweep</c>'s
    /// opt-in, age-floored, dev-stack-verified pass, and to nothing else.
    /// </summary>
    private static async Task CleanupAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        await db.CycleDayLogs.IgnoreQueryFilters().Where(l => l.UserId == userId).ExecuteDeleteAsync();
        await db.CycleEvents.IgnoreQueryFilters().Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await db.CyclePhaseOverrides.IgnoreQueryFilters().Where(o => o.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
