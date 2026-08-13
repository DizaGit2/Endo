namespace Lumen.Domain.Entities;

/// <summary>
/// A user correction to one phase boundary of one cycle (screen 14, "phase correction").
/// The row says "for the cycle that started on <see cref="CycleStartOn"/>, the
/// <see cref="Boundary"/> of <see cref="Phase"/> is <see cref="OccurredOn"/>" — nothing more.
///
/// <para><b>P4a stores; it does not interpret.</b> P4a ships zero clinical inference (§G6): the
/// four <see cref="Phases"/> are <b>codes only</b>, carrying no ordering, no durations and no dates.
/// The C-01 band sequence is a clinician-UNSIGNED PO-interim value and belongs to P6.</para>
///
/// <para><b>P6 consumption contract</b> (stated here so the column meanings are fixed before any
/// engine reads them, and so P6 needs no migration): P6 computes its C-01 phase bands for a cycle,
/// then <b>replaces any computed boundary that has a live override row</b> for the same
/// <c>(CycleStartOn, Phase, Boundary)</c>. A cycle carrying at least one live override is
/// <b>flagged for the C-05/C-09 confidence path</b>, because its bands are partly user-asserted
/// rather than derived. No column changes meaning at P6.</para>
///
/// <para><b>Unique-index regime (§G9): UNFILTERED</b> — <c>(UserId, CycleStartOn, Phase, Boundary)</c>
/// is unique across live and tombstoned rows, so re-correcting a boundary revives and updates the
/// existing row rather than inserting a second one.</para>
/// </summary>
public class CyclePhaseOverride
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>
    /// The user-local start day of the cycle being corrected — the key that ties the override to a
    /// cycle without depending on any computed cycle id.
    /// </summary>
    public DateOnly CycleStartOn { get; set; }

    /// <summary>One of <see cref="Phases"/>. Membership is enforced in code, not by a DB CHECK.</summary>
    public string Phase { get; set; } = string.Empty;

    /// <summary>One of <see cref="Boundaries"/> — which end of <see cref="Phase"/> this row moves.</summary>
    public string Boundary { get; set; } = string.Empty;

    /// <summary>The user-local day the corrected boundary falls on.</summary>
    public DateOnly OccurredOn { get; set; }

    /// <summary>One of <see cref="Sources"/>. Records who asserted the boundary.</summary>
    public string Source { get; set; } = Sources.UserCorrection;

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>Soft-delete marker (D-13): a retracted correction stops overriding the computed band.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    /// <summary>
    /// Canonical <see cref="Phase"/> values — the four ratified cycle-phase codes
    /// (definitions.md 2026-07-08). <b>Codes only:</b> the declaration order here is the order they
    /// were ratified in and must not be read as a clinical sequence. Append-only.
    /// </summary>
    public static class Phases
    {
        public const string Menstrual = "menstrual";
        public const string Follicular = "follicular";
        public const string Ovulatory = "ovulatory";
        public const string Luteal = "luteal";

        public static readonly IReadOnlyList<string> All = [Menstrual, Follicular, Ovulatory, Luteal];
    }

    /// <summary>
    /// Canonical <see cref="Boundary"/> values — the two phase boundaries
    /// (definitions.md 2026-07-08).
    /// </summary>
    public static class Boundaries
    {
        public const string Start = "start";
        public const string End = "end";

        public static readonly IReadOnlyList<string> All = [Start, End];
    }

    /// <summary>
    /// Canonical <see cref="Source"/> values. <b>P4a-proposed vocabulary (§G11)</b> — not part of the
    /// 2026-07-08 ratification block. One member today because P4a has exactly one writer; the set is
    /// append-only, so P6 can add its own without a migration.
    /// </summary>
    public static class Sources
    {
        /// <summary>Asserted by the user on the phase-correction screen.</summary>
        public const string UserCorrection = "user_correction";

        public static readonly IReadOnlyList<string> All = [UserCorrection];
    }
}
