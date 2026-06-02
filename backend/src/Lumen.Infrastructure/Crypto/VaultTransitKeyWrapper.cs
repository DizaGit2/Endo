using System.Text;
using Lumen.Application.Crypto;
using VaultSharp;
using VaultSharp.V1.AuthMethods.Token;
using VaultSharp.V1.SecretsEngines.Transit;

namespace Lumen.Infrastructure.Crypto;

/// <summary>
/// <see cref="IKeyWrapper"/> backed by Vault's Transit engine. The DEK is sent base64 to
/// <c>transit/encrypt/{key}</c>; the returned <c>vault:v1:…</c> token is what we persist.
/// Unwrap reverses it via <c>transit/decrypt/{key}</c>. Vault holds the KEK; we never see it.
/// </summary>
public sealed class VaultTransitKeyWrapper : IKeyWrapper
{
    private readonly IVaultClient _client;
    private readonly VaultOptions _options;

    public VaultTransitKeyWrapper(VaultOptions options)
    {
        _options = options;
        var settings = new VaultClientSettings(options.Address, new TokenAuthMethodInfo(options.Token));
        _client = new VaultClient(settings);
    }

    public async Task<byte[]> WrapAsync(byte[] dek, CancellationToken ct = default)
    {
        var request = new EncryptRequestOptions { Base64EncodedPlainText = Convert.ToBase64String(dek) };
        var result = await _client.V1.Secrets.Transit.EncryptAsync(_options.KeyName, request, _options.TransitMount);
        return Encoding.ASCII.GetBytes(result.Data.CipherText); // "vault:v1:…"
    }

    public async Task<byte[]> UnwrapAsync(byte[] wrappedDek, CancellationToken ct = default)
    {
        var cipherText = Encoding.ASCII.GetString(wrappedDek);
        var request = new DecryptRequestOptions { CipherText = cipherText };
        var result = await _client.V1.Secrets.Transit.DecryptAsync(_options.KeyName, request, _options.TransitMount);
        return Convert.FromBase64String(result.Data.Base64EncodedPlainText);
    }
}
