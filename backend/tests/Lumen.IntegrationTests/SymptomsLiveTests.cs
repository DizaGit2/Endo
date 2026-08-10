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
/// LIVE-STACK integration tests for the whole §C.3 symptoms resource: <c>POST /symptoms</c> (T11),
/// <c>GET /symptoms</c>, <c>PUT /symptoms/{id}</c> and <c>DELETE /symptoms/{id}</c> (T12).
///
/// <para><b>Why this file exists at all.</b> T11 shipped the batch create with unit coverage only, so
/// nothing committed proved the symptom routes were WIRED: a <c>Program.cs</c> edit dropping
/// <c>MapSymptomEndpoints()</c> or a handler losing <c>.RequireAuthorization()</c> would have left the
/// whole suite green. These tests exercise the routes over real HTTP against real Postgres, real
/// Keycloak tokens and the real Vault-backed crypto, which is the only place four facts can be
/// established: the routes exist and are authenticated, the notes column really holds ciphertext, a
/// crypto-shredded user's still-valid bearer token really is inert, and the batch really does roll
/// back inside one database transaction.</para>
///
/// <para><b>Tenant isolation is 404, never 403</b> — a 403 would itself confirm the id exists. It is
/// asserted here on all three id-addressed and range-addressed reads and writes.</para>
/// </summary>
[Trait("Category", "LiveStack")]
public class SymptomsLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";
    private const string Note = "dolor pélvico punzante";

    private static DateOnly Today => DateOnly.FromDateTime(
        TimeZoneInfo.ConvertTime(TimeProvider.System.GetUtcNow(), TimeZoneInfo.FindSystemTimeZoneById("Europe/Madrid")).Date);

    private static string Day(int offsetDays = 0) => Today.AddDays(offsetDays).ToString("yyyy-MM-dd");

    private static string Range(int fromOffset = -30, int toOffset = 0) =>
        $"/symptoms?from={Day(fromOffset)}&to={Day(toOffset)}";

    // --- the perimeter: proof the routes are WIRED and authenticated ------------------------------

    [Fact]
    public async Task Every_symptom_route_requires_a_bearer_token()
    {
        // The guard T11 lacked. Each assertion fails with 404 (not 401) if its route is unregistered,
        // so this doubles as the wiring test for MapSymptomEndpoints().
        var client = factory.CreateClient();

        (await client.GetAsync(Range())).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        (await client.PostAsJsonAsync("/symptoms", new { entries = new[] { new { intensity = 5 } } }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        (await client.PutAsJsonAsync($"/symptoms/{Guid.NewGuid()}", new { intensity = 5, occurredAt = DateTimeOffset.UtcNow }))
            .StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        (await client.DeleteAsync($"/symptoms/{Guid.NewGuid()}")).StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    // --- create → read → replace → delete, end to end ----------------------------------------------

    [Fact]
    public async Task A_batch_of_three_is_created_read_back_newest_first_and_stored_as_ciphertext()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"sym-crud-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var created = await authed.PostAsJsonAsync("/symptoms", new
            {
                entries = new object[]
                {
                    new { symptomCode = Symptom.Codes.Pain, intensity = 8, region = Symptom.Regions.Pelvis, side = Symptom.Sides.Back, notes = Note, occurredAt = Instant(-2) },
                    new { symptomCode = Symptom.NonPainCodes.Bloating, intensity = 4, occurredAt = Instant(-1) },
                    new { symptomCode = Symptom.NonPainCodes.Fatigue, intensity = 6, occurredAt = Instant(0) },
                },
            });

            created.StatusCode.ShouldBe(HttpStatusCode.Created);
            var items = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("items");
            items.GetArrayLength().ShouldBe(3);
            var painId = items[0].GetProperty("id").GetGuid();

            // Ciphertext at rest.
            await using (var db = TestFixtures.NewDb())
            {
                var row = await db.Symptoms.AsNoTracking().SingleAsync(s => s.Id == painId);
                row.NotesEnc.ShouldNotBeNull();
                Encoding.UTF8.GetString(row.NotesEnc!).ShouldNotContain("dolor");
                row.NotesEnc!.Length.ShouldBeGreaterThanOrEqualTo(28); // 12-byte nonce + ciphertext + 16-byte tag
                row.Side.ShouldBe(Symptom.Sides.Back);
            }

            // Newest first (OccurredAt DESC), with the note decrypted on the way out.
            var read = await authed.GetAsync(Range());
            read.StatusCode.ShouldBe(HttpStatusCode.OK);
            var page = await read.Content.ReadFromJsonAsync<JsonElement>();
            page.GetProperty("total").GetInt32().ShouldBe(3);
            page.GetProperty("limit").GetInt32().ShouldBe(50);
            page.GetProperty("offset").GetInt32().ShouldBe(0);
            page.GetProperty("items").EnumerateArray().Select(i => i.GetProperty("symptomCode").GetString())
                .ShouldBe([Symptom.NonPainCodes.Fatigue, Symptom.NonPainCodes.Bloating, Symptom.Codes.Pain]);
            page.GetProperty("items")[2].GetProperty("notes").GetString().ShouldBe(Note);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task A_replace_rotates_the_note_ciphertext_clears_the_omitted_side_and_leaves_the_symptom_code_alone()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"sym-put-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var created = await authed.PostAsJsonAsync("/symptoms", new
            {
                entries = new[]
                {
                    new
                    {
                        symptomCode = Symptom.NonPainCodes.Bloating,
                        intensity = 4,
                        region = Symptom.Regions.LowerAbdomen,
                        side = Symptom.Sides.Front,
                        notes = Note,
                        occurredAt = Instant(-1),
                    },
                },
            });
            created.StatusCode.ShouldBe(HttpStatusCode.Created);
            var item = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("items")[0];
            var id = item.GetProperty("id").GetGuid();
            var occurredAt = item.GetProperty("occurredAt").GetString();

            string ciphertextBefore;
            await using (var db = TestFixtures.NewDb())
                ciphertextBefore = Convert.ToBase64String((await db.Symptoms.AsNoTracking().SingleAsync(s => s.Id == id)).NotesEnc!);

            // Screen 12 has no front/back control, so a replace posted from it omits `side` — and under
            // full replace that CLEARS it. The note carries the SAME plaintext, so only a fresh nonce
            // can make the stored blob differ.
            var replaced = await authed.PutAsJsonAsync($"/symptoms/{id}", new
            {
                intensity = 9,
                region = Symptom.Regions.Pelvis,
                notes = Note,
                occurredAt,
            });

            replaced.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await replaced.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("id").GetGuid().ShouldBe(id);
            body.GetProperty("intensity").GetInt32().ShouldBe(9);
            body.GetProperty("region").GetString().ShouldBe(Symptom.Regions.Pelvis);
            body.GetProperty("side").ValueKind.ShouldBe(JsonValueKind.Null, "an omitted side is CLEARED");
            body.GetProperty("symptomCode").GetString()
                .ShouldBe(Symptom.NonPainCodes.Bloating, "symptomCode is immutable by construction");

            await using (var db = TestFixtures.NewDb())
            {
                var row = await db.Symptoms.AsNoTracking().SingleAsync(s => s.Id == id);
                Convert.ToBase64String(row.NotesEnc!).ShouldNotBe(ciphertextBefore, "a replace re-encrypts with a fresh nonce");
                Encoding.UTF8.GetString(row.NotesEnc!).ShouldNotContain("dolor");
                row.Side.ShouldBeNull();
                row.SymptomCode.ShouldBe(Symptom.NonPainCodes.Bloating);
                (await db.Symptoms.IgnoreQueryFilters().CountAsync(s => s.UserId == userId))
                    .ShouldBe(1, "a replace writes no second row");
            }

            // And the re-hydration round trip: re-sending `side` keeps it.
            var rehydrated = await authed.PutAsJsonAsync($"/symptoms/{id}", new
            {
                intensity = 9,
                region = Symptom.Regions.Pelvis,
                side = Symptom.Sides.Back,
                occurredAt,
            });
            rehydrated.StatusCode.ShouldBe(HttpStatusCode.OK);
            (await rehydrated.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("side").GetString()
                .ShouldBe(Symptom.Sides.Back);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task A_deleted_row_is_tombstoned_gone_from_items_and_gone_from_total()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"sym-del-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var created = await authed.PostAsJsonAsync("/symptoms", new
            {
                entries = new[]
                {
                    new { symptomCode = Symptom.Codes.Pain, intensity = 7, occurredAt = Instant(-1) },
                    new { symptomCode = Symptom.NonPainCodes.Nausea, intensity = 2, occurredAt = Instant(0) },
                },
            });
            created.StatusCode.ShouldBe(HttpStatusCode.Created);
            var id = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("items")[0].GetProperty("id").GetGuid();

            (await authed.DeleteAsync($"/symptoms/{id}")).StatusCode.ShouldBe(HttpStatusCode.NoContent);
            (await authed.DeleteAsync($"/symptoms/{id}")).StatusCode.ShouldBe(HttpStatusCode.NotFound);

            var page = await (await authed.GetAsync(Range())).Content.ReadFromJsonAsync<JsonElement>();
            page.GetProperty("total").GetInt32().ShouldBe(1, "a total that counted tombstones would page into rows that never arrive");
            page.GetProperty("items").GetArrayLength().ShouldBe(1);
            page.GetProperty("items").EnumerateArray()
                .Select(i => i.GetProperty("id").GetGuid()).ShouldNotContain(id);

            // A replace on a tombstone is a 404 too — PUT must not resurrect a deleted row.
            (await authed.PutAsJsonAsync($"/symptoms/{id}", new { intensity = 1, occurredAt = Instant(0) }))
                .StatusCode.ShouldBe(HttpStatusCode.NotFound);

            await using var db = TestFixtures.NewDb();
            (await db.Symptoms.IgnoreQueryFilters().AsNoTracking().SingleAsync(s => s.Id == id))
                .DeletedAt.ShouldNotBeNull("DELETE is a soft delete (D-13), never a row removal");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- paging over rows that share one instant (the D-09 normal case) ------------------------------

    [Fact]
    public async Task Offset_paging_is_stable_when_a_single_save_writes_three_rows_at_one_instant()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"sym-page-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            // No `occurredAt` on any entry: all three take the request's single `now`, which is exactly
            // what screen 13's "Save body map" produces. Without the `Id` tiebreak in the ORDER BY,
            // Postgres may order the tied rows differently per query and page 2 could repeat a row from
            // page 1 while dropping another entirely.
            var created = await authed.PostAsJsonAsync("/symptoms", new
            {
                entries = new[]
                {
                    new { symptomCode = Symptom.Codes.Pain, intensity = 3 },
                    new { symptomCode = Symptom.Codes.Pain, intensity = 4 },
                    new { symptomCode = Symptom.Codes.Pain, intensity = 5 },
                },
            });
            created.StatusCode.ShouldBe(HttpStatusCode.Created);

            var first = await (await authed.GetAsync($"{Range()}&limit=2&offset=0")).Content.ReadFromJsonAsync<JsonElement>();
            var second = await (await authed.GetAsync($"{Range()}&limit=2&offset=2")).Content.ReadFromJsonAsync<JsonElement>();

            first.GetProperty("total").GetInt32().ShouldBe(3);
            second.GetProperty("total").GetInt32().ShouldBe(3);
            first.GetProperty("limit").GetInt32().ShouldBe(2);
            second.GetProperty("offset").GetInt32().ShouldBe(2);

            var seen = first.GetProperty("items").EnumerateArray()
                .Concat(second.GetProperty("items").EnumerateArray())
                .Select(i => i.GetProperty("id").GetGuid()).ToList();
            seen.Count.ShouldBe(3);
            seen.Distinct().Count().ShouldBe(3, "no row may appear on two pages and none may be skipped");

            // Out of range is a 400, never a silent clamp.
            var clamped = await authed.GetAsync($"{Range()}&limit=101");
            clamped.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            clamped.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await clamped.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            problem.GetProperty("errors").GetProperty("limit")[0].GetString()
                .ShouldBe("value must be between 1 and 100");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- all-or-nothing, enforced by a REAL transaction ----------------------------------------------

    [Fact]
    public async Task One_bad_entry_rolls_the_whole_batch_back_and_the_live_row_count_is_unchanged()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"sym-roll-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            // One good row first, so "unchanged" is a real number and not zero-versus-zero.
            (await authed.PostAsJsonAsync("/symptoms", new
            {
                entries = new[] { new { symptomCode = Symptom.Codes.Pain, intensity = 5, occurredAt = Instant(-1) } },
            })).StatusCode.ShouldBe(HttpStatusCode.Created);

            var rejected = await authed.PostAsJsonAsync("/symptoms", new
            {
                entries = new object[]
                {
                    new { symptomCode = Symptom.Codes.Pain, intensity = 6 },
                    new { symptomCode = Symptom.NonPainCodes.Bloating, intensity = 99 },
                    new { symptomCode = Symptom.NonPainCodes.Nausea, intensity = 3 },
                },
            });

            rejected.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            rejected.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await rejected.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("errors").GetProperty("entries[1].intensity")[0].GetString()
                .ShouldBe("value must be between 0 and 10");

            await using var db = TestFixtures.NewDb();
            (await db.Symptoms.IgnoreQueryFilters().CountAsync(s => s.UserId == userId))
                .ShouldBe(1, "a rejected batch writes no row at all — not even the two valid ones");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- tenant isolation, over real HTTP ------------------------------------------------------------

    [Fact]
    public async Task One_user_can_neither_read_replace_nor_delete_another_users_symptom()
    {
        Guid ownerId = default;
        Guid intruderId = default;
        try
        {
            (ownerId, var ownerToken) = await OnboardAndLoginAsync($"sym-own-{Guid.NewGuid():N}@example.com");
            (intruderId, var intruderToken) = await OnboardAndLoginAsync($"sym-int-{Guid.NewGuid():N}@example.com");

            var created = await Authed(ownerToken).PostAsJsonAsync("/symptoms", new
            {
                entries = new[] { new { symptomCode = Symptom.Codes.Pain, intensity = 8, side = Symptom.Sides.Back, notes = Note, occurredAt = Instant(-1) } },
            });
            created.StatusCode.ShouldBe(HttpStatusCode.Created);
            var id = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("items")[0].GetProperty("id").GetGuid();

            var intruder = Authed(intruderToken);

            // READ: the row is simply not in the intruder's window — no id, no total, no leak.
            var page = await (await intruder.GetAsync(Range())).Content.ReadFromJsonAsync<JsonElement>();
            page.GetProperty("total").GetInt32().ShouldBe(0);
            page.GetProperty("items").GetArrayLength().ShouldBe(0);

            // REPLACE and DELETE: 404, never 403 — a 403 would itself confirm the id exists.
            var put = await intruder.PutAsJsonAsync($"/symptoms/{id}", new { intensity = 0, occurredAt = Instant(0) });
            put.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await put.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            var delete = await intruder.DeleteAsync($"/symptoms/{id}");
            delete.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await delete.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            await using var db = TestFixtures.NewDb();
            var row = await db.Symptoms.IgnoreQueryFilters().AsNoTracking().SingleAsync(s => s.Id == id);
            row.UserId.ShouldBe(ownerId);
            row.Intensity.ShouldBe((short)8);
            row.Side.ShouldBe(Symptom.Sides.Back);
            row.DeletedAt.ShouldBeNull();
        }
        finally
        {
            if (ownerId != default) await CleanupAsync(ownerId);
            if (intruderId != default) await CleanupAsync(intruderId);
        }
    }

    // --- the erased-user fence, against real Postgres --------------------------------------------------

    [Fact]
    public async Task A_crypto_shredded_users_still_valid_token_gets_404_from_every_symptom_route()
    {
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync($"sym-shred-{Guid.NewGuid():N}@example.com");
            var authed = Authed(token);

            var created = await authed.PostAsJsonAsync("/symptoms", new
            {
                entries = new[] { new { symptomCode = Symptom.Codes.Pain, intensity = 5, notes = Note, occurredAt = Instant(0) } },
            });
            created.StatusCode.ShouldBe(HttpStatusCode.Created);
            var item = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("items")[0];
            var id = item.GetProperty("id").GetGuid();
            var occurredAt = item.GetProperty("occurredAt").GetString();

            // Erase. The bearer token stays cryptographically valid until it expires and nothing else
            // fences these paths, so the 404s below are the ONLY thing stopping this token from reading
            // or re-writing plaintext health rows for a user who no longer exists.
            await using (var jobDb = TestFixtures.NewDb())
                await new CryptoShredJob(jobDb, TimeProvider.System, NullLogger<CryptoShredJob>.Instance).ExecuteAsync(userId);

            var read = await authed.GetAsync(Range());
            read.StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await read.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("title").GetString()
                .ShouldBe("The requested resource was not found.");

            (await authed.PostAsJsonAsync("/symptoms", new { entries = new[] { new { intensity = 5 } } }))
                .StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await authed.PutAsJsonAsync($"/symptoms/{id}", new { intensity = 1, occurredAt }))
                .StatusCode.ShouldBe(HttpStatusCode.NotFound);
            (await authed.DeleteAsync($"/symptoms/{id}")).StatusCode.ShouldBe(HttpStatusCode.NotFound);

            // §F/OQ-1: the shred HARD-deletes the plaintext clinical rows, and the token wrote none back.
            await using var db = TestFixtures.NewDb();
            (await db.Symptoms.IgnoreQueryFilters().CountAsync(s => s.UserId == userId)).ShouldBe(0);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // ------------------------------------------------------------------ helpers

    /// <summary>An instant on the user-local day <paramref name="offsetDays"/> from today, at midday.</summary>
    private static string Instant(int offsetDays) =>
        new DateTimeOffset(Today.AddDays(offsetDays).ToDateTime(new TimeOnly(12, 0)), TimeSpan.Zero)
            .ToString("O");

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
            displayName = "Symptom Tester",
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
        await db.Symptoms.IgnoreQueryFilters().Where(s => s.UserId == userId).ExecuteDeleteAsync();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.AdminAuditLogs.Where(l => l.EntityId == userId.ToString()).ExecuteDeleteAsync();
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
