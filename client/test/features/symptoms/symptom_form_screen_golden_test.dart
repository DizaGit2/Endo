// Goldens for screen 12 — the symptom form (P4b-T20b).
//
// ## What this pair captures, and what it therefore does NOT pin
//
// Screen 12 is by far the tallest surface in the phase: 41 chips, a notes
// box, and up to 21 full-width intensity scales. At the 390x844 golden
// surface the image can only ever hold the FIRST viewport plus the pinned
// footer — a golden cannot scroll, because `goldenTest`'s `builder:` runs
// with no `WidgetTester` to drive one.
//
// So the deliberate choice is ONE pair, of the OPENING state, and it pins:
//
//  * the pinned-footer layout itself — the block reason above a CTA that is
//    outside the scroll view, which is the whole point of S7 and the one
//    thing no widget test measures;
//  * the empty pain scale, which is this screen's mechanical
//    anti-fabrication control: CI goldens block out TEXT but record non-text
//    paint, so a `?? 0` default anywhere on the pain path would show up here
//    as an accent-filled first stop even though the numeral itself is
//    blocked;
//  * the top of the form — section tag, title, the pain row, and the first
//    chip rows wrapping at their real widths in both themes.
//
// It deliberately does NOT pin: anything below the first viewport (TRIGGERS,
// the 20 RELATED chips, the disclosed intensity list, the notes box), the
// submitting state, or the error states. Those are covered where they can
// actually be measured — `symptom_form_screen_semantics_test.dart` asserts
// them structurally, at every scroll depth.
//
// A second "populated" pair (screen 9's shape) was considered and NOT added:
// the only extra paint it would capture is a selected chip and a selected
// stop, and both already ship their own committed golden pairs as widgets
// (`test/widgets/goldens/ci/lumen_selectable_chip_*.png`,
// `lumen_intensity_scale_*.png`). Re-photographing them inside this screen
// would pin the same pixels a second time while the states that are actually
// unique to this screen stay below the fold either way.

import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';

import '../../support/harness.dart';

void main() {
  goldenTestLightAndDark(
    subject: 'SymptomFormScreen',
    fileName: 'symptom_form_screen',
    build: (brightness) =>
        goldenApp(home: const SymptomFormScreen(), brightness: brightness),
  );
}
