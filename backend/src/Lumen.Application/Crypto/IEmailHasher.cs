namespace Lumen.Application.Crypto;

/// <summary>
/// Computes a keyed HMAC of an email via Vault Transit. Deterministic per key version — the same
/// email under the same key always yields the same output, which is what lets the unique
/// <c>users.EmailHash</c> column support duplicate-signup lookups without ever storing (or letting
/// an attacker with a stolen DB compute offline) an unsalted digest of the address.
/// </summary>
public interface IEmailHasher
{
    Task<string> HashEmailAsync(string email, CancellationToken ct = default);
}
