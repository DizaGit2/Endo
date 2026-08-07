namespace Lumen.Domain.Entities;

/// <summary>
/// One row per user: the cycle self-report and the cycle-tracking preferences that
/// <c>GET</c>/<c>PATCH /settings/cycle</c> and the onboarding cycle step (B15) write.
///
/// <para><b>Why a 1:1 table and not columns on <c>users</c>:</b> <c>users</c> is the identity/spine
/// row read on every request; these are domain preferences with their own write path. It is also
/// not <see cref="UserProfileEnc"/>, which is all-ciphertext — every column here is a SQL
/// predicate, sort or aggregate input for the P6 estimator and must stay plaintext.</para>
///
/// <para><b>No <c>DeletedAt</c>.</b> D-13's soft-delete governs individual <i>entries</i>. This is a
/// per-user singleton: there is nothing to retract, and a tombstone would strand the primary key.
/// Account deletion hard-deletes the row (§F, T8).</para>
///
/// <para><b>Two-tier bounds (§G7).</b> <see cref="AvgCycleLengthDays"/> and
/// <see cref="AvgPeriodLengthDays"/> are <i>typed self-reports</i>, so the only schema constraint is
/// structural — a positive integer that fits <c>smallint</c>. The sanity band (avg cycle 10–120 d,
/// period 1–30 d) is a <b>non-blocking warning</b> returned by the endpoint, never a CHECK; the
/// clinical bounds (cycle 21–45 d, period 1–10 d) are clinician-UNSIGNED PO-interim values that
/// gate the P6 estimator only and have <b>no home in this schema</b>. Bounds never block entry.</para>
///
/// <para><b>Deliberately absent columns:</b> <c>first_day_of_week</c> (D-05 derives it from
/// <c>users.locale</c> via ICU) and <c>regularity_variability_days</c> (a C-05 computed output that
/// belongs to P6, not a stored self-report).</para>
/// </summary>
public class UserCycleSettings
{
    /// <summary>Primary key and FK — 1:1 with <c>users</c>, like <c>user_keys</c>/<c>user_profile_enc</c>.</summary>
    public Guid UserId { get; set; }

    /// <summary>
    /// The user's self-reported average cycle length in days. Defaults to <b>28</b>
    /// (definitions.md:71 — the onboarding chip marked "default selected"). Structural CHECK
    /// <c>&gt; 0</c> only; see the class remarks on §G7.
    /// </summary>
    public short AvgCycleLengthDays { get; set; } = DefaultAvgCycleLengthDays;

    /// <summary>
    /// The user's self-reported average period length in days. <b>Nullable with no default</b> —
    /// onboarding screen 3 never collects it, so any seeded value would be a self-report the user
    /// never made. Structural CHECK <c>IS NULL OR &gt; 0</c>.
    /// </summary>
    public short? AvgPeriodLengthDays { get; set; }

    /// <summary>One of <see cref="RegularityValues"/>. Membership is enforced in code, not by a DB CHECK.</summary>
    public string Regularity { get; set; } = RegularityValues.Default;

    /// <summary>Whether the user wants phase predictions rendered. P4a stores it; P6 honours it.</summary>
    public bool PhasePredictionEnabled { get; set; } = true;

    /// <summary>
    /// Whether the C-04 <c>period_start</c> auto-detection may run. <b>P4a ships no auto-detect</b>
    /// (§G6) — the column exists so the preference is already captured when P6 turns it on.
    /// </summary>
    public bool AutoDetectPeriodStartEnabled { get; set; } = true;

    /// <summary>
    /// Whether the C-02 fertile-window overlay is shown. Defaults <b>off</b>: the overlay carries a
    /// mandatory non-contraceptive disclaimer and is clinician-UNSIGNED. P4a renders nothing.
    /// </summary>
    public bool ShowFertilityWindowEnabled { get; set; }

    /// <summary>
    /// Whether cycle tracking is currently paused (C-12 / <c>ARCHITECTURE.md</c> §A:59). While
    /// paused, P6 makes no predictions and excludes the span from every estimator; entry is
    /// <b>never</b> blocked.
    /// </summary>
    public bool TrackingPaused { get; set; }

    /// <summary>
    /// One of <see cref="PauseReasons"/> — the reason for the <i>most recent</i> pause.
    /// <b>Deliberately not tied to <see cref="TrackingPaused"/> by a CHECK</b>: resume clears
    /// <see cref="TrackingPaused"/> and <see cref="PausedSince"/> but preserves the reason, so the
    /// next pause can pre-select it.
    /// </summary>
    public string? PauseReason { get; set; }

    /// <summary>The user-local day the current pause started; null when not paused.</summary>
    public DateOnly? PausedSince { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>The DB default for <see cref="AvgCycleLengthDays"/> (definitions.md:71).</summary>
    public const short DefaultAvgCycleLengthDays = 28;

    /// <summary>
    /// Canonical <see cref="Regularity"/> values — the three ratified codes
    /// (definitions.md 2026-07-08), default <c>somewhat</c>. Append-only.
    /// </summary>
    public static class RegularityValues
    {
        public const string Regular = "regular";
        public const string Somewhat = "somewhat";
        public const string Irregular = "irregular";

        /// <summary>The seeded value when the user does not answer the regularity question.</summary>
        public const string Default = Somewhat;

        public static readonly IReadOnlyList<string> All = [Regular, Somewhat, Irregular];
    }

    /// <summary>
    /// Canonical <see cref="PauseReason"/> values — the <b>five</b>-member C-12 set, PO-extended
    /// 2026-07-14 and recorded in <c>ARCHITECTURE.md</c> §A:59, which is authoritative.
    /// <b>The three-member list in the r15 rider is superseded</b> — <c>surgical</c> and
    /// <c>menopause</c> are members. Append-only.
    ///
    /// <para>These are <b>PO-interim, clinician-UNSIGNED</b> values (clinical-asks C-12). P4a stores
    /// the code and nothing more: the pause semantics (no predictions, spans excluded from
    /// estimators, and the rule that <c>pregnancy</c> disables hormone-range interpretation
    /// entirely) are finalised at P6.</para>
    /// </summary>
    public static class PauseReasons
    {
        public const string Pregnancy = "pregnancy";
        public const string HormonalSuppression = "hormonal_suppression";
        public const string Surgical = "surgical";
        public const string Menopause = "menopause";
        public const string Other = "other";

        public static readonly IReadOnlyList<string> All =
            [Pregnancy, HormonalSuppression, Surgical, Menopause, Other];
    }
}
