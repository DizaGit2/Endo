namespace Lumen.Application.Crypto;

/// <summary>
/// Wraps/unwraps a per-user DEK with the Vault Transit KEK. The plaintext KEK never leaves Vault;
/// only the wrapped DEK is persisted. "Wrapped" bytes are the opaque Vault ciphertext token.
/// </summary>
public interface IKeyWrapper
{
    Task<byte[]> WrapAsync(byte[] dek, CancellationToken ct = default);
    Task<byte[]> UnwrapAsync(byte[] wrappedDek, CancellationToken ct = default);
}
