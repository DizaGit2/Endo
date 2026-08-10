using Lumen.Api.Cycle;
using Lumen.Domain.Entities;
using Lumen.Domain.Reference;
using Shouldly;
using Xunit;

namespace Lumen.UnitTests.Persistence;

/// <summary>
/// Pins the frozen vocabularies of the 2026-07-08 ratification block (definitions.md:24-33) —
/// counts **and** exact members, in order. The sets are append-only: a member may be added at the
/// end, never renamed, reordered or removed, because stored rows carry these strings forever.
///
/// Deliberately literal: the expected members are typed out rather than derived from the constants,
/// so a typo in a constant fails here instead of silently redefining the vocabulary. §G10 also
/// forbids consulting the per-module tables further down definitions.md — they are stale.
/// </summary>
public class VocabularyTests
{
    [Fact]
    public void Cycle_event_kinds_are_the_three_ratified_members() =>
        CycleEvent.Kinds.All.ShouldBe(["period_start", "period_end", "spotting"]);

    [Fact]
    public void Cycle_event_sources_are_the_two_P4a_proposed_members() =>
        // §G11: a P4a invention, recorded so a later phase does not mistake it for ratified.
        CycleEvent.Sources.All.ShouldBe(["user", "onboarding"]);

    [Fact]
    public void Flow_intensity_is_a_four_level_one_based_scale()
    {
        CycleEvent.FlowIntensityScale.Min.ShouldBe((short)1);
        CycleEvent.FlowIntensityScale.Max.ShouldBe((short)4);
        CycleEvent.FlowIntensityScale.Codes.ShouldBe(["spotting", "light", "medium", "heavy"]);
        CycleEvent.FlowIntensityScale.Spotting.ShouldBe((short)1);
        CycleEvent.FlowIntensityScale.Light.ShouldBe((short)2);
        CycleEvent.FlowIntensityScale.Medium.ShouldBe((short)3);
        CycleEvent.FlowIntensityScale.Heavy.ShouldBe((short)4);
    }

    [Fact]
    public void Mood_is_a_four_level_one_based_scale()
    {
        CycleDayLog.MoodScale.Min.ShouldBe((short)1);
        CycleDayLog.MoodScale.Max.ShouldBe((short)4);
        CycleDayLog.MoodScale.Codes.ShouldBe(["low", "tired", "steady", "bright"]);
        CycleDayLog.MoodScale.Low.ShouldBe((short)1);
        CycleDayLog.MoodScale.Tired.ShouldBe((short)2);
        CycleDayLog.MoodScale.Steady.ShouldBe((short)3);
        CycleDayLog.MoodScale.Bright.ShouldBe((short)4);
    }

    [Fact]
    public void Pain_is_the_zero_based_NRS_11_scale()
    {
        // D-08: 0 is a valid datum ("none today"), not the absence of one.
        CycleDayLog.PainScale.Min.ShouldBe((short)0);
        CycleDayLog.PainScale.Max.ShouldBe((short)10);
    }

    [Fact]
    public void Symptom_intensity_is_the_same_zero_based_NRS_11_scale()
    {
        Symptom.IntensityScale.Min.ShouldBe((short)0);
        Symptom.IntensityScale.Max.ShouldBe((short)10);
    }

    [Fact]
    public void The_non_pain_catalog_has_the_twenty_ratified_members() =>
        Symptom.NonPainCodes.All.ShouldBe([
            "bloating", "nausea", "fatigue", "diarrhea", "constipation",
            "headache", "dizziness", "inflammation", "water_retention", "joint_pain",
            "frequent_urination", "frequent_bowel_movements", "indigestion", "depressed_mood",
            "painful_intercourse", "heavy_menstrual_flow", "brain_fog", "poor_concentration",
            "food_sensitivity", "acne",
        ]);

    [Fact]
    public void Symptom_codes_are_pain_plus_the_twenty_non_pain_members()
    {
        Symptom.Codes.All.Count.ShouldBe(21);
        Symptom.Codes.All[0].ShouldBe("pain");
        Symptom.Codes.All.Skip(1).ShouldBe(Symptom.NonPainCodes.All);
        Symptom.Codes.All.ShouldBeUnique();
    }

    [Fact]
    public void Symptom_regions_are_the_nine_ratified_members_with_unspecified_as_the_default()
    {
        Symptom.Regions.All.ShouldBe([
            "lower_abdomen", "pelvis", "lower_back", "legs", "bowel_rectal",
            "bladder", "vaginal", "chest_shoulder", "unspecified",
        ]);
        Symptom.Regions.Default.ShouldBe("unspecified");
    }

    [Fact]
    public void Sides_are_front_and_back_never_left_and_right() =>
        // ARCHITECTURE.md:37,:51,:184 / decision-sheet:61 — anatomical front/back, NOT laterality.
        Symptom.Sides.All.ShouldBe(["front", "back"]);

    [Fact]
    public void Pain_types_are_the_six_ratified_members_without_aching() =>
        Symptom.PainTypeCodes.All.ShouldBe(["cramping", "sharp", "burning", "dull", "stabbing", "throbbing"]);

    [Fact]
    public void Triggers_are_the_seven_ratified_members() =>
        Symptom.TriggerCodes.All.ShouldBe([
            "stress", "intercourse", "food", "exercise", "physical_strain", "poor_sleep", "weather",
        ]);

    [Fact]
    public void Cycle_phases_are_the_four_ratified_codes() =>
        // Codes only: P4a encodes no ordering and no dates (the C-01 band sequence is P6's).
        CyclePhaseOverride.Phases.All.ShouldBe(["menstrual", "follicular", "ovulatory", "luteal"]);

    [Fact]
    public void Phase_boundaries_are_start_and_end() =>
        CyclePhaseOverride.Boundaries.All.ShouldBe(["start", "end"]);

    [Fact]
    public void Phase_override_sources_are_the_single_P4a_proposed_member() =>
        // §G11: a P4a invention. Append-only, so P6's computed corrections can add their own later.
        CyclePhaseOverride.Sources.All.ShouldBe(["user_correction"]);

    // --- T6 sets: cycle settings, pause reasons, goals, hormones, notification categories ---

    [Fact]
    public void Regularity_has_the_three_ratified_members_with_somewhat_as_the_default()
    {
        UserCycleSettings.RegularityValues.All.ShouldBe(["regular", "somewhat", "irregular"]);
        UserCycleSettings.RegularityValues.Default.ShouldBe("somewhat");
    }

    [Fact]
    public void Pause_reasons_are_the_FIVE_C12_members_not_the_superseded_three()
    {
        // ARCHITECTURE.md:59 (authoritative) + clinical-asks C-12, PO-extended 2026-07-14.
        // The r15 rider's 3-member list {pregnancy, hormonal_suppression, other} is SUPERSEDED.
        UserCycleSettings.PauseReasons.All.ShouldBe([
            "pregnancy", "hormonal_suppression", "surgical", "menopause", "other",
        ]);
        UserCycleSettings.PauseReasons.All.Count.ShouldBe(5);
        UserCycleSettings.PauseReasons.All.ShouldContain("surgical");
        UserCycleSettings.PauseReasons.All.ShouldContain("menopause");
    }

    [Fact]
    public void Goals_are_the_five_ratified_codes_with_the_first_two_selected_by_default()
    {
        UserGoal.Codes.All.ShouldBe([
            "manage_symptoms", "understand_hormones", "plan_fertility",
            "prepare_appointments", "just_curious",
        ]);
        UserGoal.DefaultSelected.ShouldBe(["manage_symptoms", "understand_hormones"]);
    }

    [Fact]
    public void Hormones_are_the_seven_canonical_codes_and_all_seven_are_charted_by_default()
    {
        HormoneCatalog.Codes.All.ShouldBe([
            "estradiol", "progesterone", "lh", "fsh", "testosterone", "cortisol", "glp1",
        ]);
        // D-14: charted default = all 7 ON (screen 33's 4-ON state is a populated sample).
        UserHormonePref.DefaultCharted.ShouldBe([
            "estradiol", "progesterone", "lh", "fsh", "testosterone", "cortisol", "glp1",
        ]);
    }

    [Fact]
    public void Notification_categories_are_the_four_ratified_codes_seeded_ON_ON_OFF_OFF()
    {
        HormoneCatalog.NotificationCategories.All.ShouldBe([
            "daily_checkin", "phase_shift", "period_prediction", "medication_reminders",
        ]);
        // Screen 7 (onboarding) is the authoritative initial seed, not screen 34's all-ON sample.
        UserNotificationPref.DefaultEnabled.ShouldBe(["daily_checkin", "phase_shift"]);
        UserNotificationPref.DefaultEnabled.ShouldNotContain("period_prediction");
        UserNotificationPref.DefaultEnabled.ShouldNotContain("medication_reminders");
    }

    [Fact]
    public void The_B16_label_map_covers_every_hormone_and_keeps_the_two_code_label_mismatches()
    {
        HormoneCatalog.Labels["estradiol"].ShouldBe("Estrogen");
        HormoneCatalog.Labels["glp1"].ShouldBe("GLP-1");
        HormoneCatalog.Labels["progesterone"].ShouldBe("Progesterone");
        HormoneCatalog.Labels["lh"].ShouldBe("LH");
        HormoneCatalog.Labels["fsh"].ShouldBe("FSH");
        HormoneCatalog.Labels["testosterone"].ShouldBe("Testosterone");
        HormoneCatalog.Labels["cortisol"].ShouldBe("Cortisol");
        HormoneCatalog.Labels.Count.ShouldBe(7);
    }

    [Fact]
    public void The_notification_label_map_uses_the_singular_Phase_shift()
    {
        HormoneCatalog.NotificationCategories.Labels["phase_shift"].ShouldBe("Phase shift");
        HormoneCatalog.NotificationCategories.Labels["phase_shift"].ShouldNotBe("Phase shifts");
        HormoneCatalog.NotificationCategories.Labels["daily_checkin"].ShouldBe("Daily check-in");
        HormoneCatalog.NotificationCategories.Labels["period_prediction"].ShouldBe("Period prediction");
        HormoneCatalog.NotificationCategories.Labels["medication_reminders"].ShouldBe("Medication reminders");
        HormoneCatalog.NotificationCategories.Labels.Count.ShouldBe(4);
    }

    [Fact]
    public void Every_hormone_carries_its_CLAUDE_md_swatch_colour()
    {
        HormoneCatalog.Colors["estradiol"].ShouldBe("#C25A36");
        HormoneCatalog.Colors["progesterone"].ShouldBe("#7B8F6B");
        HormoneCatalog.Colors["lh"].ShouldBe("#D4537E");
        HormoneCatalog.Colors["fsh"].ShouldBe("#378ADD");
        HormoneCatalog.Colors["testosterone"].ShouldBe("#BA7517");
        HormoneCatalog.Colors["cortisol"].ShouldBe("#7F77DD");
        HormoneCatalog.Colors["glp1"].ShouldBe("#1D9E75");
        HormoneCatalog.Colors.Count.ShouldBe(7);
    }

    // --- T7 sets: body metrics & sources, endo status, unit system, the snapshot marker -------

    [Fact]
    public void Body_metrics_freeze_only_weight_kg_because_D15_is_still_open() =>
        // The full metric set is P5's (D-15 undecided): pre-freezing body_fat_pct/waist_cm here
        // would pre-empt a decision P4a has no standing to make. Append-only, so P5 just adds.
        BodyMetric.Metrics.All.ShouldBe(["weight_kg"]);

    [Fact]
    public void Body_metric_sources_are_the_three_ratified_members_with_manual_as_the_default()
    {
        // §D:188 — the two sync sources ship as committed values now so P5's HealthKit/Google Fit
        // work writes an already-frozen code rather than inventing one.
        BodyMetric.Sources.All.ShouldBe(["manual", "apple_health", "google_fit"]);
        BodyMetric.Sources.Default.ShouldBe("manual");
    }

    [Fact]
    public void Endo_status_has_the_three_ratified_members() =>
        UserProfileEnc.EndoStatuses.All.ShouldBe(["diagnosed", "suspected", "not_applicable"]);

    [Fact]
    public void Unit_system_has_the_single_reserved_metric_member()
    {
        // D-06: metric-only v1. The column is reserved for a future imperial *display* toggle and
        // has no write path in P4a.
        User.UnitSystems.All.ShouldBe(["metric"]);
        User.UnitSystems.Default.ShouldBe("metric");
    }

    [Fact]
    public void The_insight_snapshot_marker_says_placeholder_and_nothing_else() =>
        // §G6 mandates the value verbatim; it is not a §G11 invention. P6 appends its own writer
        // codes when the engine ships.
        UserInsightSnapshot.ComputedByValues.All.ShouldBe(["placeholder"]);

    [Fact]
    public void The_snapshot_reuses_the_four_phase_codes_rather_than_declaring_its_own() =>
        // One vocabulary, one home: a second copy of the phase codes is how two tables drift apart.
        UserInsightSnapshot.PhaseCodes.ShouldBeSameAs(CyclePhaseOverride.Phases.All);

    [Fact]
    public void Data_completeness_is_a_zero_to_hundred_percentage()
    {
        // C-09 renamed §D's `confidence`. P4a pins the SHAPE only — nothing computes a score (§G6).
        UserInsightSnapshot.DataCompletenessScale.Min.ShouldBe((short)0);
        UserInsightSnapshot.DataCompletenessScale.Max.ShouldBe((short)100);
    }

    [Fact]
    public void Every_vocabulary_member_is_lowercase_snake_case()
    {
        IEnumerable<string> all =
        [
            .. CycleEvent.Kinds.All, .. CycleEvent.Sources.All, .. CycleEvent.FlowIntensityScale.Codes,
            .. CycleDayLog.MoodScale.Codes,
            .. Symptom.Codes.All, .. Symptom.Regions.All, .. Symptom.Sides.All,
            .. Symptom.PainTypeCodes.All, .. Symptom.TriggerCodes.All,
            .. CyclePhaseOverride.Phases.All, .. CyclePhaseOverride.Boundaries.All,
            .. CyclePhaseOverride.Sources.All,
            .. UserCycleSettings.RegularityValues.All, .. UserCycleSettings.PauseReasons.All,
            .. UserGoal.Codes.All, .. HormoneCatalog.Codes.All,
            .. HormoneCatalog.NotificationCategories.All,
            .. BodyMetric.Metrics.All, .. BodyMetric.Sources.All,
            .. UserProfileEnc.EndoStatuses.All, .. User.UnitSystems.All,
            .. UserInsightSnapshot.ComputedByValues.All,
        ];

        foreach (var member in all)
        {
            member.ShouldNotBeNullOrWhiteSpace();
            member.ShouldBe(member.ToLowerInvariant(), $"'{member}' must be lowercase");
            member.ShouldNotContain(" ");
            member.ShouldNotContain("-");
        }
    }

    [Fact]
    public void Every_vocabulary_member_fits_its_column_length()
    {
        foreach (var kind in CycleEvent.Kinds.All) kind.Length.ShouldBeLessThanOrEqualTo(16);
        foreach (var source in CycleEvent.Sources.All) source.Length.ShouldBeLessThanOrEqualTo(16);
        foreach (var code in Symptom.Codes.All) code.Length.ShouldBeLessThanOrEqualTo(32);
        foreach (var region in Symptom.Regions.All) region.Length.ShouldBeLessThanOrEqualTo(32);
        foreach (var side in Symptom.Sides.All) side.Length.ShouldBeLessThanOrEqualTo(8);
        foreach (var phase in CyclePhaseOverride.Phases.All) phase.Length.ShouldBeLessThanOrEqualTo(16);
        foreach (var b in CyclePhaseOverride.Boundaries.All) b.Length.ShouldBeLessThanOrEqualTo(8);
        foreach (var s in CyclePhaseOverride.Sources.All) s.Length.ShouldBeLessThanOrEqualTo(24);
        foreach (var r in UserCycleSettings.RegularityValues.All) r.Length.ShouldBeLessThanOrEqualTo(16);
        foreach (var r in UserCycleSettings.PauseReasons.All) r.Length.ShouldBeLessThanOrEqualTo(32);
        foreach (var g in UserGoal.Codes.All) g.Length.ShouldBeLessThanOrEqualTo(32);
        foreach (var h in HormoneCatalog.Codes.All) h.Length.ShouldBeLessThanOrEqualTo(32);
        foreach (var c in HormoneCatalog.NotificationCategories.All) c.Length.ShouldBeLessThanOrEqualTo(32);
        foreach (var m in BodyMetric.Metrics.All) m.Length.ShouldBeLessThanOrEqualTo(24);
        foreach (var s in BodyMetric.Sources.All) s.Length.ShouldBeLessThanOrEqualTo(16);
        foreach (var u in User.UnitSystems.All) u.Length.ShouldBeLessThanOrEqualTo(8);
        foreach (var c in UserInsightSnapshot.ComputedByValues.All) c.Length.ShouldBeLessThanOrEqualTo(24);
        // UserProfileEnc.EndoStatuses has no column length to fit: the code is stored as AES-GCM
        // ciphertext in endo_status_enc (bytea), not as a varchar.
    }

    [Fact]
    public void Every_hormone_and_category_code_has_exactly_one_label_and_no_orphans()
    {
        // The B16 "one shared constants file" rule only holds if the maps stay in lockstep with
        // the code lists — an orphaned entry is how a renamed code silently loses its label.
        HormoneCatalog.Labels.Keys.OrderBy(k => k).ShouldBe(HormoneCatalog.Codes.All.OrderBy(k => k));
        HormoneCatalog.Colors.Keys.OrderBy(k => k).ShouldBe(HormoneCatalog.Codes.All.OrderBy(k => k));
        HormoneCatalog.NotificationCategories.Labels.Keys.OrderBy(k => k)
            .ShouldBe(HormoneCatalog.NotificationCategories.All.OrderBy(k => k));
    }

    [Fact]
    public void Every_default_seed_list_is_a_subset_of_its_own_vocabulary()
    {
        UserGoal.DefaultSelected.ShouldBeSubsetOf(UserGoal.Codes.All);
        UserHormonePref.DefaultCharted.ShouldBeSubsetOf(HormoneCatalog.Codes.All);
        UserNotificationPref.DefaultEnabled.ShouldBeSubsetOf(HormoneCatalog.NotificationCategories.All);
    }

    [Fact]
    public void Phase_unavailability_reasons_are_the_four_reserved_codes()
    {
        // §G6/§G11: P4a ships zero clinical inference, so the calendar can only ever answer
        // `phase_engine_not_implemented`. The other three are declared now and reserved for P6 so
        // that phase cannot invent a second spelling of a reason P4a already had a word for. These
        // are BACKEND constants — none is exported to Dart; the generated client sees only the
        // nullable `unavailableReason` string, which is what lets P6 emit a new code without a
        // client regeneration.
        CyclePhaseAvailability.PhaseEngineNotImplemented.ShouldBe("phase_engine_not_implemented");
        CyclePhaseAvailability.TrackingPaused.ShouldBe("tracking_paused");
        CyclePhaseAvailability.InsufficientData.ShouldBe("insufficient_data");
        CyclePhaseAvailability.NoPeriodLogged.ShouldBe("no_period_logged");
        CyclePhaseAvailability.All.ShouldBe([
            "phase_engine_not_implemented", "tracking_paused", "insufficient_data", "no_period_logged",
        ]);
    }
}
