namespace Lumen.Domain.Entities;

/// <summary>
/// The per-user cache the P6 inference engine will write (§D "Reports &amp; insights").
///
/// <para><b>In P4a this is a PLACEHOLDER and nothing else.</b> §G6 says the phase ships
/// <i>zero</i> clinical inference: no phase math, no ovulation, no fertile window, no
/// data-completeness computation, no missing-data cards, no <c>ref_insight_rule</c>, no matview and
/// no <c>RecomputeInsightSnapshotJob</c>. Consequently P4a <b>inserts zero rows</b> here, exposes
/// <b>no read endpoint</b>, and <see cref="ComputedBy"/> defaults to
/// <see cref="ComputedByValues.Placeholder"/> so any row that ever does appear announces that
/// nothing computed it. The "no read endpoint" half is build-enforced by
/// <c>ArchitectureTests.UserInsightSnapshot_is_unreachable_from_the_API_surface</c>: no
/// <c>Lumen.Api</c> type may depend on this entity. The table exists now only because §G4 allows
/// three migrations in this phase and P6 must not need a fourth.</para>
///
/// <para><b>No <c>DeletedAt</c>.</b> Every column here is <i>derived</i> output, not a user entry:
/// D-13's soft-delete governs entries, and a tombstone on a per-user derived singleton would
/// strand the primary key. Account deletion hard-deletes the row (§F, T8).</para>
///
/// <para><b>§D corrections carried here (§G13):</b> §D:219 called the score <c>confidence</c> —
/// C-09 renamed the concept to <b>data-completeness</b>, so the column is
/// <see cref="DataCompleteness"/>. §D:219 also typed <c>missing_data_cards_enc</c> as
/// <c>jsonb</c>; §D:173's rule that "'Enc' columns are <c>bytea</c>, encrypted with the per-user
/// DEK" wins, because AES-GCM ciphertext cannot live in a <c>jsonb</c> column.</para>
/// </summary>
public class UserInsightSnapshot
{
    /// <summary>Primary key and FK — 1:1 with <c>users</c>, like <c>user_keys</c>/<c>user_profile_enc</c>.</summary>
    public Guid UserId { get; set; }

    /// <summary>
    /// One of <see cref="PhaseCodes"/> when P6 eventually computes it; <c>null</c> for the whole of
    /// P4a. <b>Codes only</b> — this column encodes no ordering, no duration and no date, because
    /// the C-01 band sequence is a clinician-UNSIGNED PO-interim value that belongs to P6.
    /// Membership is enforced in code, not by a DB CHECK.
    /// </summary>
    public string? CurrentPhase { get; set; }

    /// <summary>The user-local day <see cref="CurrentPhase"/> began. No writer in P4a.</summary>
    public DateOnly? PhaseStart { get; set; }

    /// <summary>
    /// The C-09 data-completeness score, 0–100 (see <see cref="DataCompletenessScale"/>). The CHECK
    /// pins the percentage <i>shape</i> only; the weighting (labs / cycles / check-ins / body) is a
    /// clinician-UNSIGNED PO-interim value owned by P6. <b>Nothing computes this in P4a.</b>
    /// </summary>
    public short? DataCompleteness { get; set; }

    /// <summary>
    /// AES-256-GCM ciphertext of the serialised C-10 missing-data cards — <c>bytea</c>, not
    /// <c>jsonb</c> (see the class remarks). No writer in P4a; §G6 ships no cards.
    /// </summary>
    public byte[]? MissingDataCardsEnc { get; set; }

    /// <summary>
    /// What produced this row. Defaults to <see cref="ComputedByValues.Placeholder"/> so a row
    /// can never be mistaken for engine output; P6 writes its own marker when the engine lands.
    /// </summary>
    public string ComputedBy { get; set; } = ComputedByValues.Placeholder;

    /// <summary>When the engine last refreshed this row. Null for the whole of P4a.</summary>
    public DateTimeOffset? RefreshedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>
    /// Canonical <see cref="ComputedBy"/> values. <c>placeholder</c> is mandated verbatim by §G6 —
    /// it is <b>not</b> a §G11 invention to be re-litigated later. Append-only: P6 adds its engine
    /// marker beside this one.
    /// </summary>
    public static class ComputedByValues
    {
        /// <summary>No engine ran. The only value P4a can produce, and the DB default.</summary>
        public const string Placeholder = "placeholder";

        public static readonly IReadOnlyList<string> All = [Placeholder];
    }

    /// <summary>
    /// The allowed <see cref="CurrentPhase"/> codes — the same four §G10 members as
    /// <see cref="CyclePhaseOverride.Phases"/>, referenced rather than copied so the two tables
    /// cannot drift apart.
    /// </summary>
    public static IReadOnlyList<string> PhaseCodes => CyclePhaseOverride.Phases.All;

    /// <summary>
    /// The shape of <see cref="DataCompleteness"/>: a 0–100 percentage. Structural only — no
    /// clinical threshold lives here (§G6/§G7).
    /// </summary>
    public static class DataCompletenessScale
    {
        public const short Min = 0;
        public const short Max = 100;
    }
}
