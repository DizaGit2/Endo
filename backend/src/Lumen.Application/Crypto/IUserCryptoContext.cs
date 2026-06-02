namespace Lumen.Application.Crypto;

/// <summary>
/// Request-scoped envelope-crypto facade for the current user. Unwraps the user's DEK at most
/// once per scope (lazily), keeps it only for the scope's lifetime, and zeroes it on disposal.
/// All encrypted-column reads/writes go through this so call sites never touch raw key material.
/// </summary>
public interface IUserCryptoContext : IAsyncDisposable
{
    Task<byte[]> EncryptAsync(byte[] plaintext, CancellationToken ct = default);
    Task<byte[]> DecryptAsync(byte[] blob, CancellationToken ct = default);
    Task<byte[]> EncryptStringAsync(string plaintext, CancellationToken ct = default);
    Task<string> DecryptStringAsync(byte[] blob, CancellationToken ct = default);
}
