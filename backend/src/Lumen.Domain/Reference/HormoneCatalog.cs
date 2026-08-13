namespace Lumen.Domain.Reference;

/// <summary>
/// The B16 shared constants file: the canonical seven hormone codes with their display labels and
/// chart colours, plus the four notification category codes and their canonical labels.
///
/// <para><b>Codes are data; labels are not.</b> The lowercase snake_case codes are what reaches the
/// wire, the database and the LLM JSON schema. The display strings are i18n <i>source</i> strings
/// and are <b>never stored</b> — storing a label would fork the vocabulary the first time copy
/// changes. Two codes deliberately differ from their label: <c>estradiol</c> renders as "Estrogen"
/// and <c>glp1</c> as "GLP-1" (B16 — the clinically-correct analyte code keeps LLM validation and
/// chart joins stable while the screens keep the familiar word).</para>
///
/// <para><b>Constants, not a <c>ref_hormone</c> table, in P4a.</b> B16 describes a reference table
/// of <c>{code, display_label, category, color, display_unit}</c>. Two of those five columns cannot
/// be filled today: <c>display_unit</c> depends on the C-07 unit whitelist and <c>category</c> on
/// the C-13/C-08 grouping — both <b>clinician-UNSIGNED</b>. Seeding them now would bake unsigned
/// clinical values into reference data, which §G5 makes the single source of truth for the engine.
/// The table is therefore deferred to P7b (OQ-9) and only the three safe columns ship, as code.</para>
///
/// <para><b>Not a clinical file.</b> No reference ranges, no units, no phase-specific bounds
/// (§G6/§G7). Colours are the CLAUDE.md design-system swatches, which are hard-coded and not
/// theme-switched.</para>
/// </summary>
public static class HormoneCatalog
{
    /// <summary>
    /// Canonical hormone codes — the seven charted in v1, in the screen-6/screen-33 display order
    /// (definitions.md 2026-07-08, codes from <c>ARCHITECTURE.md</c> §E). Append-only.
    /// </summary>
    public static class Codes
    {
        /// <summary>Code is <c>estradiol</c>; every screen says "Estrogen" (B16).</summary>
        public const string Estradiol = "estradiol";
        public const string Progesterone = "progesterone";
        public const string Lh = "lh";
        public const string Fsh = "fsh";
        public const string Testosterone = "testosterone";
        public const string Cortisol = "cortisol";

        /// <summary>Code is <c>glp1</c>; every screen says "GLP-1" (B16).</summary>
        public const string Glp1 = "glp1";

        public static readonly IReadOnlyList<string> All =
            [Estradiol, Progesterone, Lh, Fsh, Testosterone, Cortisol, Glp1];
    }

    /// <summary>
    /// Display label per hormone code — the exact on-screen strings (i18n source). Acronyms stay
    /// uppercase ("LH", "FSH"); the two code↔label mismatches are "Estrogen" and "GLP-1".
    /// </summary>
    public static readonly IReadOnlyDictionary<string, string> Labels =
        new Dictionary<string, string>
        {
            [Codes.Estradiol] = "Estrogen",
            [Codes.Progesterone] = "Progesterone",
            [Codes.Lh] = "LH",
            [Codes.Fsh] = "FSH",
            [Codes.Testosterone] = "Testosterone",
            [Codes.Cortisol] = "Cortisol",
            [Codes.Glp1] = "GLP-1",
        };

    /// <summary>
    /// Chart swatch per hormone code — the CLAUDE.md hormone palette. These are hard-coded and
    /// <b>not</b> theme-switched: a hormone keeps its identity colour in both themes.
    /// </summary>
    public static readonly IReadOnlyDictionary<string, string> Colors =
        new Dictionary<string, string>
        {
            [Codes.Estradiol] = "#C25A36",
            [Codes.Progesterone] = "#7B8F6B",
            [Codes.Lh] = "#D4537E",
            [Codes.Fsh] = "#378ADD",
            [Codes.Testosterone] = "#BA7517",
            [Codes.Cortisol] = "#7F77DD",
            [Codes.Glp1] = "#1D9E75",
        };

    /// <summary>
    /// The four notification categories and their canonical labels. They live here rather than on
    /// <see cref="Entities.UserNotificationPref"/> so that every display string in the app has one
    /// home (§G10: "canonical display labels live in one shared constants file").
    /// </summary>
    public static class NotificationCategories
    {
        public const string DailyCheckin = "daily_checkin";
        public const string PhaseShift = "phase_shift";
        public const string PeriodPrediction = "period_prediction";
        public const string MedicationReminders = "medication_reminders";

        /// <summary>Category codes in the screen-7 order the ON/ON/OFF/OFF seed is stated in.</summary>
        public static readonly IReadOnlyList<string> All =
            [DailyCheckin, PhaseShift, PeriodPrediction, MedicationReminders];

        /// <summary>
        /// Canonical labels. <c>phase_shift</c> is <b>"Phase shift"</b>, singular — screen 7's
        /// plural "Phase shifts" is the drift, and screen 34's singular is canonical.
        /// </summary>
        public static readonly IReadOnlyDictionary<string, string> Labels =
            new Dictionary<string, string>
            {
                [DailyCheckin] = "Daily check-in",
                [PhaseShift] = "Phase shift",
                [PeriodPrediction] = "Period prediction",
                [MedicationReminders] = "Medication reminders",
            };
    }
}
