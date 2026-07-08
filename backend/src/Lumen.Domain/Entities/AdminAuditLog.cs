namespace Lumen.Domain.Entities;

/// <summary>
/// Immutable audit record for privileged or automated actions (e.g. crypto-shred).
/// <see cref="ActorId"/> is null when the action is system-initiated. No FK to <see cref="User"/>
/// so audit history survives erasure (§F / GDPR Art. 17 recital 65).
/// </summary>
public class AdminAuditLog
{
    public Guid Id { get; set; }
    public Guid? ActorId { get; set; }
    public string Action { get; set; } = string.Empty;
    public string EntityType { get; set; } = string.Empty;
    public string? EntityId { get; set; }
    public string? BeforeJson { get; set; }
    public string? AfterJson { get; set; }
    public DateTimeOffset At { get; set; }

    /// <summary>
    /// Canonical <see cref="Action"/> values. Always lowercase snake_case — the table has no
    /// enum/check constraint, so these constants are the single source of truth that keeps
    /// writers and readers casing-consistent (P3c-T4).
    /// </summary>
    public static class Actions
    {
        public const string CryptoShred = "crypto_shred";
        public const string SystemJob = "system_job";
    }

    /// <summary>
    /// Canonical <see cref="EntityType"/> values. Always lowercase snake_case (P3c-T4).
    /// </summary>
    public static class EntityTypes
    {
        public const string User = "user";
        public const string UserKey = "user_key";
    }
}
