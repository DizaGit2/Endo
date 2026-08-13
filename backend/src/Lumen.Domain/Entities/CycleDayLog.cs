namespace Lumen.Domain.Entities;

/// <summary>
/// One row per user per user-local day (D-11): the day's <b>headline</b> pain and mood, upserted by
/// the quick check-in and the day-detail screen. Classified pain episodes are separate
/// <see cref="Symptom"/> rows — this table exists so P6 gets one clean daily series per user.
/// Observed data is never clinically validated (§G7); the only DB constraints are the numeric
/// ranges of <see cref="Pain"/> and <see cref="Mood"/>.
///
/// <para><b>Unique-index regime (§G9): UNFILTERED</b> — <c>(UserId, Day)</c> is unique across live
/// <i>and</i> tombstoned rows. The upsert looks the row up with <c>IgnoreQueryFilters()</c> and
/// clears <see cref="DeletedAt"/>; it never inserts a second row for a day it has seen before.</para>
/// </summary>
public class CycleDayLog
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>The user-local day this log belongs to (D-12). Never client-supplied as an instant.</summary>
    public DateOnly Day { get; set; }

    /// <summary>
    /// Headline pain for the day on the 0–10 NRS-11 scale (<see cref="PainScale"/>).
    /// <b>0 is a real datum</b> ("none today", D-08) — only <c>null</c> means "not recorded".
    /// </summary>
    public short? Pain { get; set; }

    /// <summary>Mood on the 1–4 scale (<see cref="MoodScale"/>). Null means "not recorded".</summary>
    public short? Mood { get; set; }

    /// <summary>
    /// <b>Reserved (§D), not written in P4a.</b> D-10 defers the energy scale, so there is no CHECK,
    /// no DTO and no writer for this column yet. The column exists so the deferred scale lands
    /// without a migration.
    /// </summary>
    public short? Energy { get; set; }

    /// <summary>
    /// <b>Reserved (§D), not written in P4a.</b> D-10 defers the libido scale — see
    /// <see cref="Energy"/>. No CHECK, no DTO, no writer.
    /// </summary>
    public short? Libido { get; set; }

    /// <summary>AES-256-GCM ciphertext of the free-text note (≤2000 chars plaintext, D-13).</summary>
    public byte[]? NotesEnc { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>Soft-delete marker (D-13). Tombstones still occupy the unique key — see the class remarks.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    /// <summary>
    /// The 0–10 NRS-11 pain scale (D-08, ratified 2026-07-08). Zero is a valid logged value, so
    /// readers must distinguish <c>0</c> from <c>null</c> and never coalesce one into the other.
    /// </summary>
    public static class PainScale
    {
        public const short Min = 0;
        public const short Max = 10;
    }

    /// <summary>
    /// The 1–4 mood scale {low, tired, steady, bright} (definitions.md 2026-07-08).
    /// Append-only: never rename, reorder or remove a member.
    /// </summary>
    public static class MoodScale
    {
        public const short Min = 1;
        public const short Max = 4;

        public const short Low = 1;
        public const short Tired = 2;
        public const short Steady = 3;
        public const short Bright = 4;

        /// <summary>Level codes in scale order: <c>Codes[value - Min]</c>.</summary>
        public static readonly IReadOnlyList<string> Codes = ["low", "tired", "steady", "bright"];
    }
}
