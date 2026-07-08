using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Lumen.Application.Crypto;

namespace Lumen.Infrastructure.Crypto;

/// <summary>
/// <see cref="IEmailHasher"/> backed by Vault's Transit HMAC endpoint (<c>transit/hmac/{key}/sha2-256</c>).
/// The email is sent base64-encoded; the returned <c>vault:v1:…</c> token is persisted verbatim as
/// <c>users.EmailHash</c>. Vault holds the HMAC key; we never see it. Key version is pinned to 1 —
/// rotation is a later, deliberate act.
/// </summary>
public sealed class VaultTransitEmailHasher(HttpClient http, VaultOptions options) : IEmailHasher
{
    public async Task<string> HashEmailAsync(string email, CancellationToken ct = default)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post, $"{options.Address}/v1/transit/hmac/{options.EmailHmacKeyName}/sha2-256");
        request.Headers.Add("X-Vault-Token", options.Token);
        request.Content = JsonContent.Create(new
        {
            input = Convert.ToBase64String(Encoding.UTF8.GetBytes(email)),
            key_version = 1,
        });

        using var response = await http.SendAsync(request, ct);
        response.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        return doc.RootElement.GetProperty("data").GetProperty("hmac").GetString()
            ?? throw new InvalidOperationException("Vault HMAC response had no data.hmac.");
    }
}
