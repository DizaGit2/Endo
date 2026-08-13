using Lumen.Domain.Reference;

namespace Lumen.Domain.Entities;

/// <summary>
/// One row per user per notification category (onboarding screen 7, settings screen 34): whether
/// that category may notify.
///
/// <para><b>P4a stores the preference and dispatches nothing</b> — notification delivery is out of
/// scope for this phase (§G14). The rows exist so the D-19 per-user schedule has something to read.</para>
///
/// <para><b>No <c>DeletedAt</c>.</b> A tombstone would keep occupying <c>(UserId, CategoryCode)</c>
/// and block re-enabling the category; the boolean is the retraction. Account deletion hard-deletes
/// these rows (§F, T8).</para>
/// </summary>
public class UserNotificationPref
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>
    /// One of <see cref="HormoneCatalog.NotificationCategories"/>. Membership is enforced in code,
    /// not by a DB CHECK.
    /// </summary>
    public string CategoryCode { get; set; } = string.Empty;

    /// <summary>Whether this category may notify. False is a real answer, not a delete.</summary>
    public bool Enabled { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>
    /// The categories seeded ON at onboarding — <c>daily_checkin</c> and <c>phase_shift</c> only.
    /// The seed is <b>ON / ON / OFF / OFF</b> in category order: onboarding screen 7 is the
    /// authoritative initial state, and screen 34's all-ON rendering is a populated sample.
    /// <c>period_prediction</c> and <c>medication_reminders</c> are seeded as rows with
    /// <see cref="Enabled"/> = <c>false</c>.
    /// </summary>
    public static readonly IReadOnlyList<string> DefaultEnabled =
    [
        HormoneCatalog.NotificationCategories.DailyCheckin,
        HormoneCatalog.NotificationCategories.PhaseShift,
    ];
}
