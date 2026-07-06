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
