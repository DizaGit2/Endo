namespace Lumen.Domain.Entities;

/// <summary>
/// The per-user envelope key. <see cref="WrappedDek"/> is the user's 256-bit DEK
/// encrypted ("wrapped") by the Vault Transit KEK; the plaintext DEK is never stored.
/// Deleting this row is the crypto-shred erasure mechanism (§F).
/// </summary>
public class UserKey
{
    public Guid UserId { get; set; }
    public byte[] WrappedDek { get; set; } = [];
    public int KeyVersion { get; set; } = 1;
    public string VaultKeyName { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; }
}
