using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Lumen.Application.Auth;

namespace Lumen.Infrastructure.Auth;

/// <summary>
/// <see cref="IKeycloakAdmin"/> over the Keycloak admin REST API. Authenticates with the API's
/// confidential client via <c>client_credentials</c> (its service account holds the scoped
/// <c>realm-management</c> roles granted in the realm import).
/// </summary>
public sealed class KeycloakAdminClient(HttpClient http, KeycloakOptions options) : IKeycloakAdmin
{
    public async Task<Guid> CreateUserAsync(string email, string password, CancellationToken ct = default)
    {
        var token = await GetAdminTokenAsync(ct);

        using var request = new HttpRequestMessage(HttpMethod.Post, $"{options.BaseUrl}/admin/realms/{options.Realm}/users");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new
        {
            username = email,
            email,
            enabled = true,
            emailVerified = true,
            // Non-PII placeholders. The real display name lives ENCRYPTED in Lumen, never in Keycloak.
            // Keycloak's declarative user profile requires first/last name to be present for login.
            firstName = "Lumen",
            lastName = "User",
            credentials = new[] { new { type = "password", value = password, temporary = false } },
        });

        using var response = await http.SendAsync(request, ct);
        if (response.StatusCode == HttpStatusCode.Conflict)
            throw new DuplicateUserException("An account with that email already exists.");
        if (!response.IsSuccessStatusCode)
            throw new IdentityProviderException($"Keycloak user creation failed ({(int)response.StatusCode}).");

        // Keycloak returns 201 Created with Location: .../users/{id}
        var location = response.Headers.Location?.ToString()
            ?? throw new IdentityProviderException("Keycloak did not return a user location header.");
        var id = location[(location.LastIndexOf('/') + 1)..];
        if (!Guid.TryParse(id, out var userId))
            throw new IdentityProviderException("Keycloak returned an unparseable user id.");
        return userId;
    }

    public async Task DeleteUserAsync(Guid userId, CancellationToken ct = default)
    {
        var token = await GetAdminTokenAsync(ct);

        using var request = new HttpRequestMessage(HttpMethod.Delete, $"{options.BaseUrl}/admin/realms/{options.Realm}/users/{userId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        using var response = await http.SendAsync(request, ct);
        if (response.StatusCode is not (HttpStatusCode.NoContent or HttpStatusCode.NotFound))
            response.EnsureSuccessStatusCode();
    }

    private async Task<string> GetAdminTokenAsync(CancellationToken ct)
    {
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "client_credentials",
            ["client_id"] = options.AdminClientId,
            ["client_secret"] = options.AdminClientSecret,
        });

        using var response = await http.PostAsync(
            $"{options.BaseUrl}/realms/{options.Realm}/protocol/openid-connect/token", form, ct);
        response.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        return doc.RootElement.GetProperty("access_token").GetString()
            ?? throw new InvalidOperationException("Keycloak token response had no access_token.");
    }
}
