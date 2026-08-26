// ---------------------------------------------------------------------------
// symptom_vocabulary.dart — the shared clinical label maps (P4b-T19b)
// ---------------------------------------------------------------------------
//
// Promoted from `day_detail_screen.dart`'s private `_kSymptomCodeLabels`,
// `_kRegionLabels`, `_kPainTypeLabels`, `_kTriggerLabels` and
// `_symptomCodeLabel` — screen 11's own copy, and until now the only one.
// The house promotion threshold — the same one named in
// `mood_labels.dart:9-10` and `lumen_selectable_row.dart:4-11` — is two
// private copies plus a third caller, and it is explicitly ANTICIPATORY: it
// counts callers about to exist, not only ones that exist today. Region
// labels alone are about to have three (screen 11 shipped; screen 12's
// T19c/T20 LOCATION chips; screen 13's T21 region chip list).

// ---------------------------------------------------------------------------
// Ratified vocabulary labels this screen renders
// ---------------------------------------------------------------------------
//
// Sourced from `survey/decisions-and-vocabularies.md` §2.2-2.6, which is
// itself sourced from `definitions.md`'s frozen 2026-07-08 ratification
// block plus the backend's own frozen enum declarations. These sets are
// APPEND-ONLY on the wire; a code absent from a map below has no ratified
// label and is a vocabulary gap to REPORT, not to invent a rendering for.

/// Display label for each of the 20 non-pain `symptomCode` values.
/// `pain` is deliberately absent — see [symptomCodeLabel]'s dartdoc.
const Map<String, String> kSymptomCodeLabels = <String, String>{
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
  // The RATIFIED label — definitions.md's frozen ratification block. C-14 /
  // R-16 (`lumen-build.md:870`) recommend "Low mood" instead, but that
  // recommendation still needs a one-line PO confirmation (it post-dates
  // the frozen block), and "Low mood" collides with the mood scale's OWN
  // ordinal-1 label "Low" (`kMoodLabels[0]` in `mood_labels.dart`) — screen
  // 11 is the one surface that would render both at once. Rendered as-is;
  // the collision is reported, not resolved, in this task's report.
  'depressed_mood': 'Depressed mood',
  'painful_intercourse': 'Painful intercourse',
  'heavy_menstrual_flow': 'Excessive menstrual flow',
  'brain_fog': 'Mental fog',
  'poor_concentration': 'Trouble concentrating',
  'food_sensitivity': 'Food sensitivity',
  'acne': 'Acne',
};

/// Display label for each of the 8 anatomical `region` values.
/// `unspecified` is deliberately absent — it is the "no location" default
/// and must never render as a chip.
const Map<String, String> kRegionLabels = <String, String>{
  'lower_abdomen': 'Lower abdomen',
  'pelvis': 'Pelvis',
  'lower_back': 'Lower back',
  'legs': 'Legs',
  'bowel_rectal': 'Bowel / rectal',
  'bladder': 'Bladder',
  'vaginal': 'Vaginal',
  'chest_shoulder': 'Chest / shoulder',
};

/// Display label for each of the 6 `painTypes` values.
const Map<String, String> kPainTypeLabels = <String, String>{
  'cramping': 'Cramping',
  'sharp': 'Sharp',
  'burning': 'Burning',
  'dull': 'Dull',
  'stabbing': 'Stabbing',
  'throbbing': 'Throbbing',
};

/// Display label for each of the 7 `triggers` values.
const Map<String, String> kTriggerLabels = <String, String>{
  'stress': 'Stress',
  'intercourse': 'Intercourse',
  'food': 'Food',
  'exercise': 'Exercise',
  'physical_strain': 'Physical strain / sedentarism',
  'poor_sleep': 'Poor sleep',
  'weather': 'Weather',
};

/// The symptom row's own label: the code's ratified display label, or a
/// sentence-cased fallback of the raw code.
///
/// **Never a composite of code + region.** The mockup's own "Pelvic pain" is
/// neither a code label nor any ratified code+region rendering — `pain` has
/// no display label anywhere (`definitions.md:31`; screen 12's heading is
/// "Pain details" instead). Region/painTypes/triggers render separately, as
/// chips (see `_chipsFor` in `day_detail_screen.dart`) — never fused into
/// this string. A wrong row label is a clinical claim against a frozen,
/// append-only set, so the fallback here is a plain sentence-cased
/// rendering of the code itself, not a fabricated phrase: `pain` falls
/// through to "Pain", not "Pelvic pain".
String symptomCodeLabel(String? code) {
  if (code == null) return 'Symptom';
  return kSymptomCodeLabels[code] ?? _sentenceCase(code);
}

String _sentenceCase(String code) {
  final words = code.replaceAll('_', ' ');
  if (words.isEmpty) return words;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
