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
    public async Task<Guid> CreateUserAsync(string email, string password, string? displayName, CancellationToken ct = default)
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
            firstName = displayName,
            credentials = new[] { new { type = "password", value = password, temporary = false } },
        });

        using var response = await http.SendAsync(request, ct);
        if (response.StatusCode == HttpStatusCode.Conflict)
            throw new InvalidOperationException("A user with that email already exists.");
        response.EnsureSuccessStatusCode();

        // Keycloak returns 201 Created with Location: .../users/{id}
        var location = response.Headers.Location?.ToString()
            ?? throw new InvalidOperationException("Keycloak did not return a user location header.");
        var id = location[(location.LastIndexOf('/') + 1)..];
        return Guid.Parse(id);
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
