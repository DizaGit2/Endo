namespace Lumen.Application.Crypto;

/// <summary>
/// Provisions a fresh per-user DEK on first use: generate 256-bit key → wrap via Vault → persist
/// the <c>user_keys</c> row. Idempotent (a second call for an existing user is a no-op).
/// </summary>
public interface IDekProvisioner
{
    Task ProvisionAsync(Guid userId, CancellationToken ct = default);
}
