// Goldens for screen 13 — the body map (P4b-T21b).
//
// ## What this pair captures, and what it therefore does NOT pin
//
// ONE pair, of the OPENING state, with an EMPTY figure (R14). It pins:
//
//  * **the silhouette itself** — the head ellipse, the closed torso+legs path
//    with its three quadratics, and the two-subpath arm stroke, transcribed
//    from `Screens/screen_13_body_map.html`. This is the only artifact in the
//    repo that photographs hand-drawn vector art, and it is the reason the
//    marker assertions live in the widget test instead (see below);
//  * the figure card's own geometry — `--in` fill, `--bd` border, radius 14,
//    8 px padding, with the 120x220 figure centred in it;
//  * the pinned footer: `Done` as a plain-weight `TextButton` rather than the
//    mockup's filled primary, outside the scroll view;
//  * all eight region chips wrapping at their real widths in both themes.
//
// It deliberately does NOT pin: any marker, any intensity block, or the
// blocked state — all three need a placement, and the empty figure is what
// makes this image a stable reference rather than a photograph of one
// particular clinical state (R4's own argument: Alchemist forwards vector
// draws verbatim, so a populated golden would freeze somebody's pain map into
// a committed PNG at zero tolerance).
//
// ## Read the diff. Every time.
//
// `golden_app.dart`'s rules 6-8 — the ones that explain why goldens are
// usually copy-insensitive — **all concern `RenderParagraph`**. Blocked-text
// rectangles, icon glyphs never painted, opacity invisible on text: none of
// that applies to a `drawPath`. The silhouette is forwarded to the canvas
// exactly as drawn, which makes this the one image in the repo where a real
// geometry regression and a legitimate update look identical in the test
// output. `--update-goldens` without reading the diff is how a wrong
// transcription ships.
//
// `diffThreshold` stays 0.0 — the harness default. A global tolerance would
// apply to all 44+ committed goldens to buy slack for this one.
//
// The marker rules (R4: one radius, one colour, `opacity: 1.0`, at the zone's
// centre) are asserted in `body_map_screen_semantics_test.dart` through
// `flutter_test`'s `paints` matcher, where they can be stated as numbers and
// where a radius that varied with intensity fails loudly instead of shifting
// a few hundred pixels in an image nobody diffs.

import 'package:lumen/features/symptoms/presentation/body_map_screen.dart';

import '../../support/harness.dart';

void main() {
  goldenTestLightAndDark(
    subject: 'BodyMapScreen',
    fileName: 'body_map_screen',
    build: (brightness) =>
        goldenApp(home: const BodyMapScreen(), brightness: brightness),
  );
}
