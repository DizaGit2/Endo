using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Lumen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Shouldly;
using Xunit;

namespace Lumen.IntegrationTests;

/// <summary>
/// LIVE-STACK integration tests for <c>PATCH /me</c> — the profile-update path used to change the
/// user's display name (envelope-encrypted at rest). These pin the endpoint's ACTUAL current
/// behavior (read from <c>Program.cs</c>, not assumed): success returns 204 No Content, a missing
/// bearer returns 401, and a missing <c>user_profile_enc</c> row is silently created on PATCH
/// (the handler does not require the row to pre-exist). No test here changes that behavior.
/// </summary>
[Trait("Category", "LiveStack")]
public class MePatchLiveTests(LumenApiFactory factory) : IClassFixture<LumenApiFactory>
{
    private const string Password = "Sup3rSecretPassw0rd!";

    [Fact]
    public async Task Patch_me_updates_display_name_and_rotates_ciphertext_at_rest()
    {
        var email = $"patch-{Guid.NewGuid():N}@example.com";
        const string newDisplayName = "Nueva María";
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, "Original Name");

            await using var dbBefore = TestFixtures.NewDb();
            var before = await dbBefore.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            before.DisplayNameEnc.ShouldNotBeNull("onboarding seeded a display name, so a profile row with ciphertext must already exist");
            var ciphertextBefore = Convert.ToBase64String(before.DisplayNameEnc!);

            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

            // Act: PATCH /me with a new display name.
            var patch = await authed.PatchAsJsonAsync("/me", new { displayName = newDisplayName });
            patch.StatusCode.ShouldBe(HttpStatusCode.NoContent); // the endpoint's actual success status

            // Assert: GET /me reflects the new (decrypted) name.
            var me = await authed.GetAsync("/me");
            me.StatusCode.ShouldBe(HttpStatusCode.OK);
            var body = await me.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("displayName").GetString().ShouldBe(newDisplayName);

            // Assert: the raw ciphertext column changed and never carries the plaintext.
            await using var dbAfter = TestFixtures.NewDb();
            var after = await dbAfter.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId);
            after.DisplayNameEnc.ShouldNotBeNull();
            Convert.ToBase64String(after.DisplayNameEnc!).ShouldNotBe(ciphertextBefore, "the stored ciphertext must be rotated by the PATCH, not reused");
            Encoding.UTF8.GetString(after.DisplayNameEnc!).ShouldNotContain(newDisplayName); // ciphertext at rest, never plaintext
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Patch_me_without_bearer_returns_401()
    {
        var client = factory.CreateClient();

        var response = await client.PatchAsJsonAsync("/me", new { displayName = "whoever" });

        response.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Patch_me_creates_the_profile_row_when_it_is_missing()
    {
        var email = $"patch-create-{Guid.NewGuid():N}@example.com";
        const string displayName = "Created On Patch";
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, "Original Name");

            // Delete the profile row directly (SQL via EF's ExecuteDelete) so PATCH must create it from scratch.
            await using (var db = TestFixtures.NewDb())
                await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
            await using (var dbCheck = TestFixtures.NewDb())
                (await dbCheck.UserProfiles.AsNoTracking().AnyAsync(p => p.UserId == userId)).ShouldBeFalse("the row must actually be gone before the act");

            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

            // Act: PATCH /me with the profile row missing.
            var patch = await authed.PatchAsJsonAsync("/me", new { displayName });
            patch.StatusCode.ShouldBe(HttpStatusCode.NoContent); // same success status as the update path

            // Assert: a user_profile_enc row now exists, with the display name encrypted.
            await using var dbAfter = TestFixtures.NewDb();
            var created = await dbAfter.UserProfiles.AsNoTracking().SingleOrDefaultAsync(p => p.UserId == userId);
            created.ShouldNotBeNull("PATCH /me must create the profile row when it is missing");
            created!.DisplayNameEnc.ShouldNotBeNull();
            Encoding.UTF8.GetString(created.DisplayNameEnc!).ShouldNotContain(displayName); // ciphertext at rest, never plaintext

            var me = await authed.GetAsync("/me");
            var body = await me.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("displayName").GetString().ShouldBe(displayName);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Patch_me_with_an_empty_body_is_204_and_creates_the_profile_row()
    {
        // ARCHITECTURE.md §C.0.1 claimed an empty body here was a 400. It is not, and the difference is
        // load-bearing for P4b: `POST /onboarding/baseline` 400s on an all-null body
        // (OnboardingValidationMessages.BaselineEmpty), `PATCH /me` falls through every branch and
        // answers 204 — and on the way it CREATES a `user_profile_enc` row that did not exist. A client
        // written to the merged rule would either send a field it does not mean or treat a success as a
        // failure. Nothing pinned the real behaviour, so nothing would have caught the doc being wrong.
        var email = $"patch-empty-{Guid.NewGuid():N}@example.com";
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, "Nombre Intacto");

            // Remove the profile row so the creation half is observable, exactly as the row-creation
            // test above does — this is the state a user reaches before any baseline step has run.
            await using (var db = TestFixtures.NewDb())
                await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();

            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

            var patch = await authed.PatchAsJsonAsync("/me", new { });

            patch.StatusCode.ShouldBe(
                HttpStatusCode.NoContent,
                "PATCH /me has no all-fields-absent check; the empty-body 400 belongs to "
                + "POST /onboarding/baseline alone");

            await using var db2 = TestFixtures.NewDb();
            var created = await db2.UserProfiles.AsNoTracking().SingleOrDefaultAsync(p => p.UserId == userId);
            created.ShouldNotBeNull("an empty PATCH still materialises the profile row");
            created!.DisplayNameEnc.ShouldBeNull("nothing was supplied, so nothing was written to it");

            // Absent is never a reset: the rest of the resource is exactly as onboarding left it.
            var user = await db2.Users.AsNoTracking().SingleAsync(u => u.Id == userId);
            user.Timezone.ShouldBe("Europe/Madrid");
            user.Locale.ShouldBe("es-ES");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // --- T4: users.timezone / users.locale become mutable ---------------------------------

    [Fact]
    public async Task Patch_me_updates_timezone_and_locale()
    {
        var email = $"patch-tz-{Guid.NewGuid():N}@example.com";
        const string newTimezone = "America/Argentina/Buenos_Aires";
        const string newLocale = "en-GB";
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, "Zona Original");

            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

            var patch = await authed.PatchAsJsonAsync("/me", new { timezone = newTimezone, locale = newLocale });
            patch.StatusCode.ShouldBe(HttpStatusCode.NoContent);

            // The D-12 hole this closes: every day-keyed write resolves "today" from users.timezone,
            // so a user who moves must be able to correct it or their data is filed against the wrong day.
            await using var db = TestFixtures.NewDb();
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId);
            user.Timezone.ShouldBe(newTimezone);
            user.Locale.ShouldBe(newLocale);

            var me = await authed.GetAsync("/me");
            var body = await me.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("timezone").GetString().ShouldBe(newTimezone);
            body.GetProperty("locale").GetString().ShouldBe(newLocale);
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Patch_me_with_an_unknown_timezone_returns_the_shared_400_and_writes_nothing()
    {
        var email = $"patch-badtz-{Guid.NewGuid():N}@example.com";
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, "Zona Original");

            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

            // A garbage zone id is not merely wrong data: UserDayResolver logs a WARN every time it
            // fails to resolve, on every day-keyed request, forever — user-controlled log amplification.
            var patch = await authed.PatchAsJsonAsync("/me", new { displayName = "Never Saved", timezone = "Mars/Olympus" });

            patch.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            patch.Content.Headers.ContentType!.MediaType.ShouldBe("application/problem+json");
            var problem = await patch.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("detail").GetString().ShouldBe("The request contained invalid data.");
            problem.GetProperty("errors").GetProperty("timezone")[0].GetString()
                .ShouldBe("value is not a recognized IANA time zone");

            // Validate-then-act: the rejected request must not have written the display name either.
            await using var db = TestFixtures.NewDb();
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId);
            user.Timezone.ShouldBe("Europe/Madrid");
            var me = await authed.GetAsync("/me");
            var body = await me.Content.ReadFromJsonAsync<JsonElement>();
            body.GetProperty("displayName").GetString().ShouldBe("Zona Original");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Theory]
    // 36 characters: one over the users.locale column limit.
    [InlineData("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "text exceeds the maximum length of 35 characters")]
    [InlineData("not a locale!", "value is not a recognized BCP-47 locale")]
    public async Task Patch_me_with_an_unusable_locale_returns_the_shared_400(string locale, string expectedMessage)
    {
        var email = $"patch-badloc-{Guid.NewGuid():N}@example.com";
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, "Zona Original");

            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

            var patch = await authed.PatchAsJsonAsync("/me", new { locale });

            patch.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
            var problem = await patch.Content.ReadFromJsonAsync<JsonElement>();
            problem.GetProperty("errors").GetProperty("locale")[0].GetString().ShouldBe(expectedMessage);

            await using var db = TestFixtures.NewDb();
            (await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId)).Locale.ShouldBe("es-ES");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    [Fact]
    public async Task Patch_me_leaves_timezone_and_locale_alone_when_they_are_absent()
    {
        var email = $"patch-keep-{Guid.NewGuid():N}@example.com";
        Guid userId = default;
        try
        {
            (userId, var token) = await OnboardAndLoginAsync(email, "Zona Original");

            var authed = factory.CreateClient();
            authed.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

            // Absent is not "reset to default" — a display-name-only PATCH must not touch the zone.
            var patch = await authed.PatchAsJsonAsync("/me", new { displayName = "Solo Nombre" });
            patch.StatusCode.ShouldBe(HttpStatusCode.NoContent);

            await using var db = TestFixtures.NewDb();
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId);
            user.Timezone.ShouldBe("Europe/Madrid");
            user.Locale.ShouldBe("es-ES");
        }
        finally
        {
            if (userId != default) await CleanupAsync(userId);
        }
    }

    // ------------------------------------------------------------------ helpers

    private async Task<(Guid userId, string token)> OnboardAndLoginAsync(string email, string displayName)
    {
        var client = factory.CreateClient();
        var start = await client.PostAsJsonAsync("/onboarding/start", new
        {
            email,
            password = Password,
            displayName,
            locale = "es-ES",
            timezone = "Europe/Madrid",
            policyVersion = "v1-test",
        });
        start.StatusCode.ShouldBe(HttpStatusCode.OK);
        var userId = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("userId").GetGuid();

        var token = await TestFixtures.GetUserTokenAsync(email, Password);
        return (userId, token);
    }

    private static async Task CleanupAsync(Guid userId)
    {
        await using var db = TestFixtures.NewDb();
        await db.UserProfiles.Where(p => p.UserId == userId).ExecuteDeleteAsync();
        await db.ConsentRecords.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.UserKeys.Where(k => k.UserId == userId).ExecuteDeleteAsync();
        await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
    }
}
