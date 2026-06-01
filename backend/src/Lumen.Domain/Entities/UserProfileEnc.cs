namespace Lumen.Domain.Entities;

/// <summary>
/// Envelope-encrypted profile fields. Each <c>*Enc</c> column is AES-256-GCM
/// ciphertext (nonce ‖ ciphertext ‖ tag) produced with the user's DEK — never plaintext.
/// </summary>
public class UserProfileEnc
{
    public Guid UserId { get; set; }
    public byte[]? DisplayNameEnc { get; set; }
    public byte[]? DobEnc { get; set; }
    public byte[]? BioEnc { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}
