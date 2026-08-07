using Lumen.Domain.Entities;
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
    }
}
