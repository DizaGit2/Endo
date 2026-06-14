namespace Lumen.Application.Crypto;

/// <summary>
/// Job-scoped envelope-crypto facade bound to an explicit user id. Mirrors <see cref="IUserCryptoContext"/>
/// but is used by background jobs that must decrypt a user's data while the user is offline. The user id
/// is supplied at construction time (via <see cref="IJobCryptoContextFactory"/>), not obtained from an
/// HTTP request context. The DEK is unwrapped at most once and held only for this context's lifetime,
/// then zeroed on disposal — the same custody invariants as the request-scoped context.
/// </summary>
public interface IJobCryptoContext : IAsyncDisposable
{
    Task<byte[]> EncryptAsync(byte[] plaintext, CancellationToken ct = default);
    Task<byte[]> DecryptAsync(byte[] blob, CancellationToken ct = default);
    Task<byte[]> EncryptStringAsync(string plaintext, CancellationToken ct = default);
    Task<string> DecryptStringAsync(byte[] blob, CancellationToken ct = default);
}
