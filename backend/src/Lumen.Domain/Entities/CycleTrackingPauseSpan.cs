namespace Lumen.Domain.Entities;

/// <summary>
/// One closed or open cycle-tracking pause: "this user paused for <see cref="Reason"/> from
/// <see cref="StartedOn"/> until <see cref="EndedOn"/> (null = still paused)".
///
/// <para><b>Why the table exists.</b> <c>ARCHITECTURE.md</c> §A:59 requires that "paused spans [are]
/// excluded from estimators", and C-12 repeats it. The three fields on
/// <see cref="UserCycleSettings"/> (<c>TrackingPaused</c>, <c>PauseReason</c>, <c>PausedSince</c>)
/// describe only the <i>current</i> pause: resume clears <c>PausedSince</c> and the span is gone
/// forever. Without this history every pause/resume between P4a and P6 would silently poison the
/// estimator — exactly the harm the §A row exists to prevent.</para>
///
/// <para><b>P4a stores; it does not interpret</b> (§G6). No exclusion logic, no overlap merging and
/// no "resume = fresh cycle start" rule ships here — those are P6's, and they read these rows.</para>
///
/// <para><b>Unique-index regime.</b> A <b>partial UNIQUE on <c>UserId WHERE "EndedOn" IS NULL</c></b>
/// enforces at most one <i>open</i> pause per user, so a double-tap on "pause" cannot fork the
/// history into two concurrent spans. Closed spans are unconstrained — a user may pause and resume
/// any number of times. This filter is on a domain lifecycle column, <b>not</b> on a soft-delete
/// marker: this table has no <c>DeletedAt</c> at all, so it is outside the §G9 tombstone regime
/// (whose one filtered case remains <c>body_metrics</c>).</para>
/// </summary>
public class CycleTrackingPauseSpan
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>
    /// One of <see cref="UserCycleSettings.PauseReasons"/> — the <b>five</b>-member C-12 set.
    /// Copied onto the span at pause time so the history survives a later change to the settings row.
    /// </summary>
    public string Reason { get; set; } = string.Empty;

    /// <summary>The user-local day the pause began (D-12).</summary>
    public DateOnly StartedOn { get; set; }

    /// <summary>
    /// The user-local day the pause ended, or <c>null</c> while the pause is open. Nullability is
    /// load-bearing: it is the predicate of the partial unique index described in the class remarks.
    /// </summary>
    public DateOnly? EndedOn { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}
