namespace Lumen.Domain.Entities;

/// <summary>
/// One classified symptom episode (D-09). A single save from the full form or the body map produces
/// many of these rows — pain plus each RELATED chip becomes its own row from the 20-member non-pain
/// catalogue. Classification is <b>always optional</b>: only <see cref="Intensity"/> and the date are
/// required; <see cref="Region"/> defaults to <see cref="Regions.Unspecified"/> and
/// <see cref="Side"/>/<see cref="PainTypes"/>/<see cref="Triggers"/> may be empty.
/// Observed data is never clinically validated (§G7) — the only DB constraint is the numeric range
/// of <see cref="Intensity"/>.
/// </summary>
public class Symptom
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// <summary>One of <see cref="Codes"/>. Membership is enforced in code, not by a DB CHECK.</summary>
    public string SymptomCode { get; set; } = string.Empty;

    /// <summary>
    /// Severity on the 0–10 NRS-11 scale (<see cref="IntensityScale"/>). <b>0 is a real datum</b>
    /// (D-08); unlike <see cref="CycleDayLog.Pain"/> this column is required, because a symptom row
    /// only exists because the user logged one.
    /// </summary>
    public short Intensity { get; set; }

    /// <summary>One of <see cref="Regions"/>; defaults to <see cref="Regions.Unspecified"/>.</summary>
    public string Region { get; set; } = Regions.Unspecified;

    /// <summary>
    /// One of <see cref="Sides"/> — anatomical <c>front</c>/<c>back</c>, <b>not</b> laterality.
    /// Null when the user did not classify it.
    /// </summary>
    public string? Side { get; set; }

    /// <summary>
    /// Zero or more of <see cref="PainTypeCodes"/>. A plain <c>List&lt;string&gt;</c> primitive
    /// collection (T1 probe 2): no value converter, no <c>ValueComparer</c> and <b>no</b> explicit
    /// column type — Npgsql emits <c>text[]</c> and SQLite round-trips it, but pinning either
    /// literal would leak a provider-specific type into the other provider's DDL.
    /// </summary>
    public List<string> PainTypes { get; set; } = [];

    /// <summary>Zero or more of <see cref="TriggerCodes"/>. Same storage shape as <see cref="PainTypes"/>.</summary>
    public List<string> Triggers { get; set; } = [];

    /// <summary>The instant the episode occurred, as supplied by the client.</summary>
    public DateTimeOffset OccurredAt { get; set; }

    /// <summary>
    /// The user-local day of <see cref="OccurredAt"/>, computed at write time via
    /// <c>IUserDayContext</c> (D-12). <b>Never client-supplied.</b> It exists so calendar and range
    /// reads are a day-keyed index scan rather than a per-row timezone conversion.
    /// Capped by the user's local today — <b>no backdate floor</b> (§G8: the floor is
    /// <c>cycle_events</c>-only).
    /// </summary>
    public DateOnly OccurredOn { get; set; }

    /// <summary>AES-256-GCM ciphertext of the free-text note (≤2000 chars plaintext, D-13).</summary>
    public byte[]? NotesEnc { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>Soft-delete marker (D-13): excluded from every read, matview, report and export.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    /// <summary>
    /// The 0–10 NRS-11 intensity scale (D-08, ratified 2026-07-08), shared with
    /// <see cref="CycleDayLog.PainScale"/>.
    /// </summary>
    public static class IntensityScale
    {
        public const short Min = 0;
        public const short Max = 10;
    }

    /// <summary>
    /// The 20-member non-pain symptom catalogue (definitions.md 2026-07-08).
    /// Append-only: never rename, reorder or remove a member — stored rows carry these strings forever.
    /// </summary>
    public static class NonPainCodes
    {
        public const string Bloating = "bloating";
        public const string Nausea = "nausea";
        public const string Fatigue = "fatigue";
        public const string Diarrhea = "diarrhea";
        public const string Constipation = "constipation";
        public const string Headache = "headache";
        public const string Dizziness = "dizziness";
        public const string Inflammation = "inflammation";
        public const string WaterRetention = "water_retention";
        public const string JointPain = "joint_pain";
        public const string FrequentUrination = "frequent_urination";
        public const string FrequentBowelMovements = "frequent_bowel_movements";
        public const string Indigestion = "indigestion";
        public const string DepressedMood = "depressed_mood";
        public const string PainfulIntercourse = "painful_intercourse";
        public const string HeavyMenstrualFlow = "heavy_menstrual_flow";
        public const string BrainFog = "brain_fog";
        public const string PoorConcentration = "poor_concentration";
        public const string FoodSensitivity = "food_sensitivity";
        public const string Acne = "acne";

        public static readonly IReadOnlyList<string> All =
        [
            Bloating, Nausea, Fatigue, Diarrhea, Constipation,
            Headache, Dizziness, Inflammation, WaterRetention, JointPain,
            FrequentUrination, FrequentBowelMovements, Indigestion, DepressedMood,
            PainfulIntercourse, HeavyMenstrualFlow, BrainFog, PoorConcentration,
            FoodSensitivity, Acne,
        ];
    }

    /// <summary>
    /// Canonical <see cref="SymptomCode"/> values: <see cref="Pain"/> plus the 20 members of
    /// <see cref="NonPainCodes"/> — 21 in all.
    /// </summary>
    public static class Codes
    {
        public const string Pain = "pain";

        public static readonly IReadOnlyList<string> All = [Pain, .. NonPainCodes.All];
    }

    /// <summary>
    /// Canonical <see cref="Region"/> values — 8 anatomical regions plus
    /// <see cref="Unspecified"/> (definitions.md 2026-07-08). Append-only.
    /// </summary>
    public static class Regions
    {
        public const string LowerAbdomen = "lower_abdomen";
        public const string Pelvis = "pelvis";
        public const string LowerBack = "lower_back";
        public const string Legs = "legs";
        public const string BowelRectal = "bowel_rectal";
        public const string Bladder = "bladder";
        public const string Vaginal = "vaginal";
        public const string ChestShoulder = "chest_shoulder";
        public const string Unspecified = "unspecified";

        /// <summary>The value stored when the user does not localise the symptom.</summary>
        public const string Default = Unspecified;

        public static readonly IReadOnlyList<string> All =
        [
            LowerAbdomen, Pelvis, LowerBack, Legs, BowelRectal,
            Bladder, Vaginal, ChestShoulder, Unspecified,
        ];
    }

    /// <summary>
    /// Canonical <see cref="Side"/> values: anatomical <c>front</c>/<c>back</c> — <b>not</b>
    /// left/right (ARCHITECTURE.md:37,:51,:184; decision-sheet:61). The body map has a front view and
    /// a back view; laterality was never part of the model.
    /// </summary>
    public static class Sides
    {
        public const string Front = "front";
        public const string Back = "back";

        public static readonly IReadOnlyList<string> All = [Front, Back];
    }

    /// <summary>
    /// Canonical members of <see cref="PainTypes"/> — the 6 ratified pain qualities
    /// (definitions.md 2026-07-08; <c>aching</c> is deliberately absent). Append-only.
    /// </summary>
    public static class PainTypeCodes
    {
        public const string Cramping = "cramping";
        public const string Sharp = "sharp";
        public const string Burning = "burning";
        public const string Dull = "dull";
        public const string Stabbing = "stabbing";
        public const string Throbbing = "throbbing";

        public static readonly IReadOnlyList<string> All = [Cramping, Sharp, Burning, Dull, Stabbing, Throbbing];
    }

    /// <summary>
    /// Canonical members of <see cref="Triggers"/> — the 7 ratified triggers
    /// (definitions.md 2026-07-08). Append-only.
    /// </summary>
    public static class TriggerCodes
    {
        public const string Stress = "stress";
        public const string Intercourse = "intercourse";
        public const string Food = "food";
        public const string Exercise = "exercise";
        public const string PhysicalStrain = "physical_strain";
        public const string PoorSleep = "poor_sleep";
        public const string Weather = "weather";

        public static readonly IReadOnlyList<string> All =
            [Stress, Intercourse, Food, Exercise, PhysicalStrain, PoorSleep, Weather];
    }
}
