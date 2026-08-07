namespace Lumen.Domain.Entities;

/// <summary>
/// A discrete, user-observed cycle event: a period start, a period end, or spotting
/// (§D "Cycle &amp; symptoms"). Observed data is <b>never</b> clinically validated (§G7) — the only
/// database constraint is the numeric range of <see cref="FlowIntensity"/>. Soft-deleted via
/// <see cref="DeletedAt"/> (D-13); account deletion hard-deletes the row instead (crypto-shred
/// no longer makes this plaintext unreadable, so §F erases it physically).
///
/// <para><b>Unique-index regime (§G9): UNFILTERED</b> — <c>(UserId, Kind, OccurredOn)</c> is unique
/// across live <i>and</i> tombstoned rows. Upserts must therefore look the row up with
/// <c>IgnoreQueryFilters()</c> and clear <see cref="DeletedAt"/>; they never insert a second row.</para>
///
/// <para><b>Onboarding-seed merge rule</b> (consumed by T18's <c>POST /onboarding/cycle</c>, and the
/// reason the index is unfiltered). The seed row written at onboarding is found by
/// <c>(UserId, Kind = <see cref="Kinds.PeriodStart"/>, Source = <see cref="Sources.Onboarding"/>)</c>
/// under <c>IgnoreQueryFilters()</c>. Before moving it to a new day, look up
/// <c>(UserId, Kind, targetDay)</c> under <c>IgnoreQueryFilters()</c>:
/// <list type="bullet">
///   <item>no row → move the seed row (set <see cref="OccurredOn"/> = targetDay);</item>
///   <item>a row exists (live or tombstoned) → <b>adopt/revive it</b>: clear its
///   <see cref="DeletedAt"/> and keep its existing <see cref="Source"/> and <see cref="CreatedAt"/>,
///   then retire the stale onboarding row by soft-deleting it.</item>
/// </list>
/// Never two rows for the same key, never an index violation.</para>
/// </summary>
public class CycleEvent
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>One of <see cref="Kinds"/>. Membership is enforced in code, not by a DB CHECK.</summary>
    public string Kind { get; set; } = string.Empty;

    /// <summary>
    /// The user-local day the event happened (D-12). The only P4a write that may backdate:
    /// <c>&gt;= UserDayInfo.BackdateFloor</c> and <c>&lt;= UserDayInfo.Today</c> (§G8 / D-13).
    /// </summary>
    public DateOnly OccurredOn { get; set; }

    /// <summary>
    /// Optional flow level, 1–4 per <see cref="FlowIntensityScale"/>. Null means "not recorded".
    /// </summary>
    public short? FlowIntensity { get; set; }

    /// <summary>AES-256-GCM ciphertext of the free-text note (≤2000 chars plaintext, D-13).</summary>
    public byte[]? NotesEnc { get; set; }

    /// <summary>One of <see cref="Sources"/>. Records how the row got here, not what it means.</summary>
    public string Source { get; set; } = Sources.User;

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>Soft-delete marker (D-13). Tombstones still occupy the unique key — see the class remarks.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    /// <summary>
    /// Canonical <see cref="Kind"/> values — the three ratified cycle-event kinds
    /// (definitions.md 2026-07-08). Append-only: never rename, reorder or remove a member.
    /// </summary>
    public static class Kinds
    {
        public const string PeriodStart = "period_start";
        public const string PeriodEnd = "period_end";
        public const string Spotting = "spotting";

        public static readonly IReadOnlyList<string> All = [PeriodStart, PeriodEnd, Spotting];
    }

    /// <summary>
    /// Canonical <see cref="Source"/> values. <b>P4a-proposed vocabulary (§G11)</b> — not part of the
    /// 2026-07-08 ratification block; recorded as an invention so a later phase does not mistake it
    /// for a signed-off set. <c>auto_detected</c> is deliberately <b>not</b> reserved: the set is
    /// append-only, so pre-reserving an unsigned C-04 concept buys nothing.
    /// </summary>
    public static class Sources
    {
        /// <summary>Logged by the user from the cycle UI.</summary>
        public const string User = "user";

        /// <summary>Seeded from the onboarding cycle-setup step (B15). See the merge rule above.</summary>
        public const string Onboarding = "onboarding";

        public static readonly IReadOnlyList<string> All = [User, Onboarding];
    }

    /// <summary>
    /// The 1–4 flow-intensity scale {spotting, light, medium, heavy}.
    /// <b>C-04 PO-interim — clinician sign-off pending.</b> The scale's <i>shape</i> (four ordinal
    /// levels) is what the DB CHECK pins; any clinical meaning attached to a level — notably the
    /// "<c>flow_intensity &gt;= 2</c> is period-qualifying" rule — is an unsigned PO-interim value and
    /// has no home in <c>backend/src</c> during P4a (§G7). It belongs to P6's <c>ref_insight_rule</c>
    /// seed rows.
    /// </summary>
    public static class FlowIntensityScale
    {
        public const short Min = 1;
        public const short Max = 4;

        public const short Spotting = 1;
        public const short Light = 2;
        public const short Medium = 3;
        public const short Heavy = 4;

        /// <summary>Level codes in scale order: <c>Codes[value - Min]</c>.</summary>
        public static readonly IReadOnlyList<string> Codes = ["spotting", "light", "medium", "heavy"];
    }
}
