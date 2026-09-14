// ---------------------------------------------------------------------------
// symptom_vocabulary_test.dart — the promoted clinical label maps (P4b-T19b)
// ---------------------------------------------------------------------------
//
// Direct pin, independent of any screen render. Before this task the only
// coverage of these labels ran through `day_detail_screen_semantics_test.dart`
// mounting screen 11 — real coverage, but coverage that could not tell a
// wrong map from a wrong render. Once two screens (T19c/T20's screen 12,
// T21's screen 13) depend on `lib/shared/symptom_vocabulary.dart`, the
// vocabulary itself needs a pin that does not require mounting anything.
//
// Each map is asserted as a whole — member count AND the complete key set
// and label values — not a sample, because a map this size invites an
// "append the missing one" edit that a sampled assertion would not catch.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';

void main() {
  group('kSymptomCodeLabels', () {
    test('has exactly the 20 ratified non-pain codes, byte-for-byte', () {
      expect(kSymptomCodeLabels, hasLength(20));
      expect(kSymptomCodeLabels, <String, String>{
        'bloating': 'Bloating',
        'nausea': 'Nausea',
        'fatigue': 'Fatigue',
        'diarrhea': 'Diarrhea',
        'constipation': 'Constipation',
        'headache': 'Headache',
        'dizziness': 'Dizziness',
        'inflammation': 'General inflammation',
        'water_retention': 'Fluid retention',
        'joint_pain': 'Cramping / joint pain',
        'frequent_urination': 'Frequent urination',
        'frequent_bowel_movements': 'Frequent bowel movements',
        'indigestion': 'Indigestion',
        'depressed_mood': 'Depressed mood',
        'painful_intercourse': 'Painful intercourse',
        'heavy_menstrual_flow': 'Excessive menstrual flow',
        'brain_fog': 'Mental fog',
        'poor_concentration': 'Trouble concentrating',
        'food_sensitivity': 'Food sensitivity',
        'acne': 'Acne',
      });
    });

    test(
      '`pain` is deliberately absent — it has no ratified display label',
      () {
        // `pain` is not a display code: the fallback for it in
        // `symptomCodeLabel` is the sentence-cased "Pain", never a map hit.
        // An "append the missing one" edit is exactly what this pin catches.
        expect(kSymptomCodeLabels.containsKey('pain'), isFalse);
      },
    );
  });

  group('kRegionLabels', () {
    test('has exactly the 8 ratified anatomical regions, byte-for-byte', () {
      expect(kRegionLabels, hasLength(8));
      expect(kRegionLabels, <String, String>{
        'lower_abdomen': 'Lower abdomen',
        'pelvis': 'Pelvis',
        'lower_back': 'Lower back',
        'legs': 'Legs',
        'bowel_rectal': 'Bowel / rectal',
        'bladder': 'Bladder',
        'vaginal': 'Vaginal',
        'chest_shoulder': 'Chest / shoulder',
      });
    });

    test('`unspecified` is deliberately absent — it is the "no location" '
        'default and must never render as a chip', () {
      expect(kRegionLabels.containsKey('unspecified'), isFalse);
    });
  });

  group('kPainTypeLabels', () {
    test('has exactly the 6 ratified pain types, byte-for-byte', () {
      expect(kPainTypeLabels, hasLength(6));
      expect(kPainTypeLabels, <String, String>{
        'cramping': 'Cramping',
        'sharp': 'Sharp',
        'burning': 'Burning',
        'dull': 'Dull',
        'stabbing': 'Stabbing',
        'throbbing': 'Throbbing',
      });
    });
  });

  group('kTriggerLabels', () {
    test('has exactly the 7 ratified triggers, byte-for-byte', () {
      expect(kTriggerLabels, hasLength(7));
      expect(kTriggerLabels, <String, String>{
        'stress': 'Stress',
        'intercourse': 'Intercourse',
        'food': 'Food',
        'exercise': 'Exercise',
        'physical_strain': 'Physical strain / sedentarism',
        'poor_sleep': 'Poor sleep',
        'weather': 'Weather',
      });
    });
  });

  group('symptomCodeLabel', () {
    test('returns the ratified label for a mapped code', () {
      expect(symptomCodeLabel('bloating'), 'Bloating');
    });

    test('returns "Symptom" for a null code, never a sentence-cased '
        'fallback', () {
      expect(symptomCodeLabel(null), 'Symptom');
    });

    test('falls through to a sentence-cased rendering of the raw code for an '
        'unmapped code — `pain` is the documented example: "Pain", never '
        'the fabricated "Pelvic pain"', () {
      expect(symptomCodeLabel('pain'), 'Pain');
    });

    test('sentence-cases an arbitrary unmapped multi-word code too', () {
      // Not one of the 20 ratified codes and not `pain` either — proves the
      // fallback is a real transformation, not a hardcoded special case for
      // the one documented example above.
      expect(symptomCodeLabel('some_unmapped_code'), 'Some unmapped code');
    });
  });
}
