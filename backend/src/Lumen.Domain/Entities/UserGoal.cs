namespace Lumen.Domain.Entities;

/// <summary>
/// One row per user per goal code (onboarding screen 5, D-14): whether the user picked that goal.
///
/// <para><b>A row per code, with a boolean — not "rows only for selected goals".</b> Deselecting
/// flips <see cref="Selected"/> to <c>false</c>; the row stays. That keeps the unique key stable and
/// records that the user was asked and said no, which is a different fact from never having seen
/// the question.</para>
///
/// <para><b>No <c>DeletedAt</c>.</b> A tombstone would keep occupying <c>(UserId, GoalCode)</c> and
/// block re-selecting the same goal — see <see cref="Selected"/>. Account deletion hard-deletes
/// these rows (§F, T8).</para>
///
/// <para><b>P4a stores; it does not act.</b> <c>plan_fertility</c> in particular drives nothing this
/// phase — the C-02 fertile-window overlay is clinician-UNSIGNED and belongs to P6.</para>
/// </summary>
public class UserGoal
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>One of <see cref="Codes"/>. Membership is enforced in code, not by a DB CHECK.</summary>
    public string GoalCode { get; set; } = string.Empty;

    /// <summary>Whether the user currently has this goal selected. False is a real answer, not a delete.</summary>
    public bool Selected { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>
    /// The goal codes seeded ON when onboarding writes the initial set (D-14: "first two default
    /// ON"; screen 6's "Defaults shown" is the authoritative initial state). The remaining three
    /// are seeded as rows with <see cref="Selected"/> = <c>false</c>.
    /// </summary>
    public static readonly IReadOnlyList<string> DefaultSelected =
        [Codes.ManageSymptoms, Codes.UnderstandHormones];

    /// <summary>
    /// Canonical <see cref="GoalCode"/> values — the five ratified codes
    /// (definitions.md 2026-07-08). Declaration order is the screen-5 display order. Append-only.
    /// </summary>
    public static class Codes
    {
        public const string ManageSymptoms = "manage_symptoms";
        public const string UnderstandHormones = "understand_hormones";
        public const string PlanFertility = "plan_fertility";
        public const string PrepareAppointments = "prepare_appointments";
        public const string JustCurious = "just_curious";

        public static readonly IReadOnlyList<string> All =
            [ManageSymptoms, UnderstandHormones, PlanFertility, PrepareAppointments, JustCurious];
    }
}
