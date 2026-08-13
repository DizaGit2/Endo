using System.Globalization;

namespace Lumen.Domain.Entities;

/// <summary>
/// One measured body metric for one user on one user-local day (§D "Body &amp; activity"). P4a
/// creates this table for a single reason: the D-02 onboarding baseline step seeds the user's
/// weight, and rider 4 requires weight to have <b>one source of truth</b> — this row, never a
/// column on <see cref="UserProfileEnc"/>. <b>P5 owns the module</b> (screens 22–25) and extends it;
/// P4a ships no read/write endpoint of its own beyond the onboarding seed.
///
/// <para><b>Unique-index regime (§G9): FILTERED</b> — <c>(UserId, Metric, MeasuredOn)</c> is unique
/// only <c>WHERE "DeletedAt" IS NULL</c>. This is the <b>one deliberate exception</b> to the
/// otherwise-unfiltered regime, and the rationale is D-02: the onboarding baseline step must stay
/// re-submittable after the user deletes their weight entry. Under an unfiltered index the
/// tombstone would keep occupying the key and the re-submit would fail with a constraint violation
/// on a row the user believes they deleted. The trade-off accepted here is that a metric can
/// accumulate several tombstones for one day; that is invisible to every read (the query filter
/// hides them) and T8 hard-deletes them all on account erasure.</para>
///
/// <para><b>Value encoding.</b> <see cref="ValueEnc"/> is AES-256-GCM ciphertext of a
/// <i>string</i>, so the plaintext form is the column's real contract. There is exactly one
/// canonical encoder — <see cref="EncodeValue"/>/<see cref="DecodeValue"/>, both invariant-culture —
/// because a culture-sensitive round-trip silently reads 60.4&#160;kg as 604&#160;kg under
/// <c>de-DE</c>. Never format or parse this value any other way.</para>
///
/// <para><b>No units column.</b> D-06 is metric-only for v1 and the unit is part of the metric code
/// itself (<c>weight_kg</c>). <see cref="User.UnitSystem"/> is a reserved <i>display</i>
/// preference and never changes what is stored.</para>
/// </summary>
public class BodyMetric
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>One of <see cref="Metrics"/>. Membership is enforced in code, not by a DB CHECK.</summary>
    public string Metric { get; set; } = string.Empty;

    /// <summary>
    /// AES-256-GCM ciphertext of the canonical value string (see <see cref="EncodeValue"/>).
    /// Required: a metric row with no value is not a measurement.
    /// </summary>
    public byte[] ValueEnc { get; set; } = [];

    /// <summary>One of <see cref="Sources"/>. Records how the row got here, not what it means.</summary>
    public string Source { get; set; } = Sources.Default;

    /// <summary>The instant the measurement was taken (or attributed to).</summary>
    public DateTimeOffset MeasuredAt { get; set; }

    /// <summary>
    /// The user-local day of <see cref="MeasuredAt"/> (D-12), computed at write time through
    /// <c>IUserDayContext</c> and never client-supplied. It is the day component of the unique key,
    /// so it must be a stored column rather than a per-row timezone conversion. Capped by the
    /// user's local today with <b>no backdate floor</b> — the floor is <c>cycle_events</c>-only (§G8).
    /// </summary>
    public DateOnly MeasuredOn { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>
    /// Soft-delete marker (D-13). Unlike every other soft-deletable P4a table, a tombstone here
    /// <b>frees</b> the unique key — see the class remarks on the §G9 filtered exception.
    /// </summary>
    public DateTimeOffset? DeletedAt { get; set; }

    /// <summary>
    /// Canonical <see cref="Metric"/> codes. <b>Deliberately a one-member set:</b> P4a needs only
    /// the onboarding weight seed, and the full body-metric vocabulary is an <b>open decision
    /// (D-15)</b> owned by P5. Freezing <c>body_fat_pct</c>/<c>waist_cm</c> here would pre-empt it.
    /// Append-only, and the column carries no CHECK, so P5 adds members without a migration.
    /// </summary>
    public static class Metrics
    {
        /// <summary>Body weight in kilograms (D-06: metric-only v1). Seeded by onboarding screen 4.</summary>
        public const string WeightKg = "weight_kg";

        public static readonly IReadOnlyList<string> All = [WeightKg];
    }

    /// <summary>
    /// Canonical <see cref="Source"/> values (§D:188). Only <see cref="Manual"/> has a writer in
    /// P4a; the two sync sources ship now so P5's HealthKit / Google Fit work writes an
    /// already-committed code instead of inventing one. Append-only.
    /// </summary>
    public static class Sources
    {
        /// <summary>Entered by the user (including the onboarding baseline seed).</summary>
        public const string Manual = "manual";

        /// <summary>Imported from Apple HealthKit. No writer until P5.</summary>
        public const string AppleHealth = "apple_health";

        /// <summary>Imported from Google Fit. No writer until P5.</summary>
        public const string GoogleFit = "google_fit";

        /// <summary>The DB default: everything P4a writes is user-entered.</summary>
        public const string Default = Manual;

        public static readonly IReadOnlyList<string> All = [Manual, AppleHealth, GoogleFit];
    }

    /// <summary>
    /// The <b>one</b> canonical plaintext encoding of a metric value, invariant-culture. Encrypt the
    /// result into <see cref="ValueEnc"/>; never <c>ToString()</c> a metric value any other way.
    /// </summary>
    public static string EncodeValue(decimal value) => value.ToString(CultureInfo.InvariantCulture);

    /// <summary>
    /// The inverse of <see cref="EncodeValue"/>. <see cref="NumberStyles.Float"/> excludes
    /// <see cref="NumberStyles.AllowThousands"/>, so a locale-formatted string such as "60,4"
    /// raises <see cref="FormatException"/> instead of being misread as 604.
    /// </summary>
    public static decimal DecodeValue(string canonical) =>
        decimal.Parse(canonical, NumberStyles.Float, CultureInfo.InvariantCulture);
}
