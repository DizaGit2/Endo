namespace Lumen.Domain.Entities;

/// <summary>
/// A versioned record of the consent a user gave at sign-up (D-02 / GDPR Art. 9).
/// Stored non-encrypted (no special-category content) but immutable per version;
/// a new policy version produces a new row. Legal finalizes the policy text (legal-asks L-02).
/// </summary>
public class ConsentRecord
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string PolicyVersion { get; set; } = string.Empty;
    public string Locale { get; set; } = string.Empty;
    public DateTimeOffset ConsentedAt { get; set; }
}
