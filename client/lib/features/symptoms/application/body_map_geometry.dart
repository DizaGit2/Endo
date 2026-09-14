import 'dart:ui';

// ---------------------------------------------------------------------------
// Body-map region geometry — screen 13's hit table (P4b-T21a)
// ---------------------------------------------------------------------------
//
// `Screens/screen_13_body_map.html` ships ONE `viewBox="0 0 120 220"` svg: a
// head ellipse, one closed torso+legs path, an open two-subpath arm stroke and
// three accent circles. It has no `<g>`, no `id` and no `data-region` — nothing
// in it maps a coordinate to a region. This file is that mapping, authored.
//
// DECLARED IN THE MOCKUP'S OWN UNITS, not in normalised 0..1, so every number
// below can be read straight against the path data it came from:
//
//   head     : cx=60 cy=22 rx=14 ry=16                    -> y 6..38
//   torso    : M46 38 Q60 34 74 38 L82 76 Q86 110 80 140
//              L74 200 L66 202 L62 150 L58 150 L54 202
//              L46 200 L40 140 Q34 110 38 76 Z
//              -> shoulders at y=38; widest at y~102.6 (x 36.4..83.6) — the
//                 torso quadratic `L82 76 Q86 110 80 140` reaches its
//                 extremum at t=0.4, i.e. (83.6, 102.56), mirrored at
//                 (36.4, 102.56); leg split at y=150, feet at y~202
//   arms     : M40 60 L24 110 L28 140  /  M80 60 L96 110 L92 140
//   accents  : (60,100) r7, (54,115) r5, (66,92) r4  -> all mid-torso
//
// **No zoom, anywhere** (plan T21-J). The mockup's own zoom recentres on user
// space (60,105) with NO pan, so at 300% the head and the feet are off-canvas
// and unreachable — porting it ships a defect. [regionAt] therefore takes the
// painted rect and nothing else: no scale factor, no matrix, no zoom level.
//
// **Independent of the painter.** T21b's `CustomPainter` is private to its
// screen file; this table is not, and nothing here may be shaped by what is
// convenient to paint.

/// The mockup's own user space: `viewBox="0 0 120 220"`.
///
/// Every [Rect] in [kBodyMapRegionZones] is expressed in these units, and
/// [regionAt] is the only place they are converted to logical pixels.
const Size kBodyMapUserSpace = Size(120, 220);

/// WCAG 2.2 SC 2.5.8 (Target Size Minimum, AA), in logical pixels — the floor
/// this project ruled it can claim conformance against
/// (`docs/superpowers/plans/lumen-build.md:1026`, the tap-target ruling made
/// at T9). Material's 48 is a design guideline, not a conformance
/// requirement, and nothing in the harness gates tap size.
const double kBodyMapMinTapTarget = 24;

/// The shortest the figure may be painted, in logical pixels, before a zone
/// falls under [kBodyMapMinTapTarget].
///
/// Derived, not chosen: the shallowest zone is `pelvis` at 26 user units of
/// [kBodyMapUserSpace]'s 220, so it clears 24 logical px only while the
/// painted height is at least `24 * 220 / 26` = 203.1. **T21b must not paint
/// the figure shorter than this**, and `body_map_geometry_test.dart` pins both
/// the floor and its tightness so a later zone edit cannot quietly slip under
/// it.
///
/// **The natural size clears this by 16 px, and no more.** This project maps
/// 1 mockup CSS px to 1 Flutter logical px with no frame scaling — screen 12
/// carries the mockup's `padding:44px 22px 20px` over verbatim
/// (`symptom_form_screen.dart:200,592`), `LumenSelectableChip` its
/// `6px 10px` / `14` / `11px` (its own `build`), and the tap-target ruling
/// itself reasons in the mockups' absolute sizes
/// ("Screen 3's day cells are 26 logical px"). The one counterexample in the
/// repo, `lumen_scaffold.dart:86-89`, scales the nav bar's 9 px label by
/// 390/300 to 11 — but it sits under that dartdoc's explicit "Departures from
/// the CSS" heading, so it reads as a declared exception for one widget, not a
/// competing convention. Either reading leaves the number below intact,
/// because 204 is a FLOOR: any scale above 1:1 only enlarges the zones.
/// The mockup's svg is
/// `viewBox="0 0 120 220" width="150" height="220"`, and the default
/// `xMidYMid meet` fits 120x220 into 150x220 at scale 1, so the figure's
/// natural size here is 120x220 LOGICAL px. At that size the four zones are
/// 48x42, 48x44, 48x26 and 40x54, and the tightest — `pelvis` at 26 px — is
/// **1.08x** the floor, not a comfortable multiple of it. **T21b therefore
/// has 16 logical px of slack and nothing more**: a layout that runs out of
/// vertical room (the header, the point counter, N stacked intensity blocks
/// and the CTA) must SCROLL rather than shrink the silhouette.
const double kBodyMapMinPaintedHeight = 204;

/// Each tappable region's hit shape, in [kBodyMapUserSpace] units.
///
/// **Four zones, four deliberate absences (R10).** With `side` cut by R-21, a
/// tap writes a `region` byte-identical to the one T21b's chip writes, so the
/// pixel placement is a UI affordance that asserts nothing clinical — but only
/// while it places what lay anatomy places unambiguously on an anterior
/// figure. Every one of the eight ratified regions in `kRegionLabels` is
/// accounted for here, present or absent, with its reason:
///
///  * `lower_abdomen` — **present**. The torso below the waist and above the
///    pelvis band; the mockup's own three accent circles (y 92..115) all sit
///    inside it. Unambiguous on an anterior figure.
///  * `pelvis` — **present**. The band between `lower_abdomen` and the leg
///    split at y=150. Unambiguous.
///  * `lower_back` — **ABSENT**. Posterior, and no back view ships (R-21 cut
///    Front/Back). A zone for it on an anterior figure would be exactly the
///    anatomical claim R-21 refused to make in pixels. Reachable by chip.
///  * `legs` — **present**. Both legs below the split, drawn on the figure.
///  * `bowel_rectal` — **ABSENT**. An internal pelvic structure with no
///    honest surface projection; any zone would be an invented projection and
///    would overlap `pelvis`. Reachable by chip.
///  * `bladder` — **ABSENT**. Same reason as `bowel_rectal`.
///  * `vaginal` — **ABSENT**. Same reason as `bowel_rectal`.
///  * `chest_shoulder` — **present**. The upper torso and the shoulder span,
///    drawn on the figure, anterior.
///
/// "No hit zone" is always the safe answer: an absent region is still fully
/// reachable through T21b's all-8 chip list, which is the complete input path.
/// **Do not add a fifth zone** without a ruling — report it instead.
///
/// The zones are RECTANGLES, deliberately: hit-testing needs no Bezier
/// transcription, and a rectangle is a shape a reviewer can check against the
/// path data above by reading. They are slightly generous against the outline
/// (the torso zones span the figure's full width, x 36..84, so the widest part
/// of the silhouette at y~102.6 is inside them; the `legs` zone spans the gap
/// between the two legs) — a generous affordance on an input that asserts
/// nothing beyond the region code is the right trade, and the alternative is
/// dead pixels on the drawn figure.
///
/// **Declaration order here is anatomical (top to bottom), for review against
/// the SVG — it is NOT an output order.** `BodyMapSelection.toDrafts` derives
/// its order from `kRegionLabels.keys` and never reads this map, so there is
/// no second copy of the frozen order to drift.
const Map<String, Rect> kBodyMapRegionZones = <String, Rect>{
  // Shoulder line (y=38) down to just above the mockup's uppermost accent
  // circle; x spans the shoulder width, which is wider than the torso is at
  // y=38 (46..74) because the arms leave the body at (40,60)/(80,60).
  'chest_shoulder': Rect.fromLTRB(36, 38, 84, 80),
  // The mid-torso band that carries all three accent circles.
  'lower_abdomen': Rect.fromLTRB(36, 80, 84, 124),
  // Down to the leg split at y=150.
  'pelvis': Rect.fromLTRB(36, 124, 84, 150),
  // From the split to just past the feet at y~202.
  'legs': Rect.fromLTRB(40, 150, 80, 204),
};

/// The region a tap at [localPosition] falls in, or `null` for a tap that hits
/// no zone — the head, an arm, the background, or anywhere outside
/// [paintedFigure].
///
/// [localPosition] is in the local coordinates of whatever painted the figure;
/// [paintedFigure] is the rect that [kBodyMapUserSpace] was painted ONTO — the
/// fitted figure box, not the surrounding card. T21b maps a tap through a
/// plain fit and passes that rect; there is no scale factor, matrix or zoom
/// level in this signature, and none is wanted (T21-J).
///
/// Zones do not overlap (R11, pinned by a pairwise test), so the iteration
/// order below cannot decide anything — a tie would be a defect, not a
/// priority question. [Rect.contains] is half-open, so a tap exactly on the
/// shared edge of two adjacent zones resolves to the lower/right one and to
/// nothing else.
String? regionAt(Offset localPosition, Rect paintedFigure) {
  if (paintedFigure.width <= 0 || paintedFigure.height <= 0) return null;
  final userPosition = Offset(
    (localPosition.dx - paintedFigure.left) *
        kBodyMapUserSpace.width /
        paintedFigure.width,
    (localPosition.dy - paintedFigure.top) *
        kBodyMapUserSpace.height /
        paintedFigure.height,
  );
  for (final entry in kBodyMapRegionZones.entries) {
    if (entry.value.contains(userPosition)) return entry.key;
  }
  return null;
}
