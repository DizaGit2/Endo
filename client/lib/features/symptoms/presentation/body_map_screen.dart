// Screen 13 — the body map (P4b-T21b, the screen half of T21).
//
// The whole headless half already shipped at T21a and is NOT re-implemented
// here: `BodyMapSelection` (`application/body_map_selection.dart`) owns
// placement, per-point intensity, the block reason and the draft mapping, and
// `body_map_geometry.dart` owns the region table and the hit test. **Read both
// before changing anything in this file** — if a rule looks missing here it is
// because it lives there, and a second copy of it would be a defect rather
// than thoroughness.
//
// What this file owns, and nothing else does:
//  * the silhouette, transcribed from `Screens/screen_13_body_map.html`'s one
//    `viewBox="0 0 120 220"` svg (see [_BodyMapPainter]);
//  * the ALL-EIGHT region chip list, which is the COMPLETE input path (R3) —
//    four of the eight have no hit zone and are reachable only here;
//  * one stacked intensity block per placed region, in frozen vocabulary
//    order (R2), which is screen 12's shipped `_IntensityBlock` pattern
//    (`symptom_form_screen.dart:368-392`) applied to a different selection;
//  * the LIVE write into `SymptomForm.bodyMapPoints` on every change (R7);
//  * the `Done` affordance, blocked with a stated reason while any placed
//    region is unrated (R8).
//
// Cut from the mockup, and why:
//  * **the Front/Back pill pair** — plan R-21, PO-ruled 2026-08-21 and
//    escalated to the clinician as C-16. No source anywhere assigns a region
//    to a view; `side` is documented as ANATOMICAL in three shipped sources;
//    the app never renders it back; v1 has neither edit nor delete; and a
//    P6/P7 heatmap will act on it. There is no `side` field, no `side`
//    parameter and no `'front'`/`'back'` string in this file or in T21a's.
//  * **"INTENSITY AT SELECTED POINT"** — R2. R-15's "a tap toggles a region
//    off" and R-12's "intensity at the selected point" cannot both hold under
//    one gesture, and because T19c froze `LumenSelectableChip` as a plain
//    two-state toggle, a chip-list user could otherwise place a point and
//    never rate it. Every placed region gets its own block instead.
//  * **the +/− zoom, its 100% label and the `✦ Pinch or use +/− to zoom` hint
//    card** — R5/T21-J. The mockup's own zoom recentres on user space
//    (60,105) with NO pan, so at 300% the head and the feet are unreachable:
//    porting it ships a defect, and R-16 removes copy describing machinery
//    this phase does not ship rather than rewording it. Both `✦` (U+2726) and
//    `−` (U+2212) are also outside `kAllowedNonAsciiGlyphs`
//    (`a11y_guard.dart:159-176`), so that card could not ship as written
//    regardless. There is no `InteractiveViewer`, no `Matrix4` and no scale
//    factor anywhere below.
//  * **the marker size/alpha ramp** (r7@.85 / r5@.7 / r4@.6) — R4. D-08 makes
//    `0` a real logged intensity, so any monotone size-or-alpha encoding of
//    0-10 draws a logged `0` at zero radius or zero alpha and the user's own
//    data disappears from the only picture of it. The mockup's faintest step
//    also measures ~2.2:1 against `--in` in light theme, which would make low
//    intensities the LEAST visible.
//  * **"Save body map"** — R6. It is extraction-verbatim rather than ratified,
//    and its markup is byte-identical to screen 12's real save button, so its
//    visual weight promises a write R-11 forbids. Nothing is pending here (R7
//    writes live), so nothing needs a primary-weight commit button.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/symptoms/application/body_map_geometry.dart';
import 'package:lumen/features/symptoms/application/body_map_selection.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/application/symptom_form_controller.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

/// The affordance that leaves the screen (R6).
///
/// **Authored, not ratified** — the mockup says "Save body map", which R6
/// cuts because it promises a write. Flagged for PO confirmation at phase exit
/// alongside the six strings already on T25's list.
const String kBodyMapDoneLabel = 'Done';

/// The screen's title — the mockup's own `20px/500` line.
const String kBodyMapTitle = 'Tap where it hurts';

/// The mockup's own `.tag` — 11 px, sage, uppercase, 1.5 px tracking.
const String kBodyMapSectionLabel = 'Body map';

/// The chip row's label, in sentence case (`LumenFieldLabel` uppercases it for
/// the eye and announces this string unchanged).
///
/// **Authored, not ratified.** The mockup draws no chip list at all — the list
/// exists because R-15 requires a non-tap input path and R3 makes it the
/// COMPLETE one. `Location` (screen 12's own row label) was rejected: that row
/// is a single-select attribute of the pain row, and reusing its name for a
/// multi-select set of body-map points would make two different things
/// announce identically inside one episode. Flagged for PO confirmation.
const String kBodyMapRegionsLabel = 'Regions';

/// What the silhouette's ONE summary semantics node is called (R10).
///
/// **Authored, not ratified**, and deliberately the same words as
/// [kBodyMapSectionLabel]: naming the picture after the screen is the smallest
/// claim available, and inventing a second phrase for it would be a fourth
/// authored string bought for nothing.
const String kBodyMapFigureLabel = 'Body map';

/// The mockup's own counter sentence — "3 points placed" — over [count]
/// distinct placed regions (R9).
///
/// **The singular is authored.** The mockup only ever draws the plural, and
/// this screen opens at `0` and passes through `1` on the way to every other
/// value, so shipping the mockup's form unchanged would render `1 points
/// placed`. Flagged for PO confirmation with the strings above.
String bodyMapPointsPlaced(int count) =>
    count == 1 ? '1 point placed' : '$count points placed';

// ---------------------------------------------------------------------------
// Handles
// ---------------------------------------------------------------------------

/// The key on the silhouette's [CustomPaint].
///
/// Nothing in hand-drawn vector art can be addressed by text, so this is how a
/// test reaches the figure's own render object — which is what
/// `flutter_test`'s `paints` matcher records canvas calls from. Without it,
/// `find.byType(CustomPaint)` would match Material's own internal painters
/// too.
const Key kBodyMapFigureKey = ValueKey<String>('body-map-figure');

/// The key on the intensity block disclosed for [region].
///
/// Every block draws stops labelled `0`..`10`, so nothing in the rendered text
/// can tell two of them apart — `symptom_form_screen.dart`'s
/// `symptomIntensityKey` precedent, for the identical reason.
Key bodyMapIntensityKey(String region) =>
    ValueKey<String>('body-map-intensity-$region');

/// The marker's radius, in [kBodyMapUserSpace] units — which are logical
/// pixels here, because the figure is painted at exactly 1:1 (see
/// [_BodyMapPainter]).
///
/// ONE radius for every marker (R4), the middle of the mockup's own three
/// (r7/r5/r4). It is a `const` rather than a function of anything: a radius
/// that varied with intensity would draw a logged `0` at zero size, and D-08
/// makes `0` a real datum that v1 can neither edit nor delete.
const double kBodyMapMarkerRadius = 5;

// ---------------------------------------------------------------------------
// BodyMapScreen
// ---------------------------------------------------------------------------

/// Screen 13 — the body map.
///
/// Mounted as a TOP-LEVEL route OUTSIDE the tab shell
/// (`Routes.symptomsBodyMap`, `/symptoms/body-map`), the same shape screen 12
/// has, and PUSHED from screen 12's own body-map affordance (R-20).
///
/// ## It writes nothing, and there is nothing to cancel (R7)
///
/// Every change — a placement, a removal, an intensity — is written straight
/// into `SymptomForm.bodyMapPoints` through
/// [SymptomFormController.setBodyMapPoints], and [kBodyMapDoneLabel] only
/// leaves. **Deliberately NOT `context.push<T>` + `context.pop(points)`:**
/// `go_router` reserves a `null` result for dismissal, so under a
/// result-sentinel a user who cleared every point and then left by the SYSTEM
/// BACK GESTURE would keep every point they had just removed. R-15's toggle is
/// itself the undo, so a screen whose every action is individually reversible
/// has nothing to cancel — and the house does not confirm discards anyway
/// (its `PopScope`, `symptom_form_screen.dart:168-169`, blocks only a write
/// in flight).
///
/// **The honest consequence, stated (R8):** because the writes are live, an
/// UNRATED placement is the one thing leaving by the system back gesture can
/// lose. That is correct rather than merely tolerable — an unrated placement
/// carries no intensity, `toDrafts()` refuses to invent one (`?? 0` would
/// promote it to a logged zero nobody can take back), and every RATED point is
/// already in the form. [kBodyMapDoneLabel] blocks on exactly that state, with
/// the reason drawn beside it, so the only way to reach the loss is to
/// deliberately leave past a stated block.
///
/// ## The deep-link case, ruled (R11)
///
/// `/symptoms/body-map` is a legal cold URL: it builds a fresh, empty
/// autoDispose form with **nothing underneath to pop back to**. That is
/// accepted rather than redirected away at the door, because a redirect on
/// entry cannot tell a cold link from screen 12's push, and one that could
/// would throw away points the user had already placed. Leaving handles it
/// instead — see [_BodyMapScreenState._leave]: when there is nothing to pop,
/// the user is sent to `/symptoms/new`, which is where the points they just
/// placed can actually be saved.
///
/// ## State lives here, and is rehydrated on entry
///
/// The screen owns its own [BodyMapSelection] rather than pushing the
/// placed-but-unrated state into `SymptomForm`: `SymptomEntryDraft.intensity`
/// is a non-nullable `int` with no representation for "unrated" at all, and
/// `SymptomForm.blockReason`'s guard 2 inspects only `relatedIntensities`, so
/// screen 12 could never report an unrated body-map point. On entry the
/// selection is rebuilt from whatever is already in the form, so re-opening
/// the screen shows what is already placed.
class BodyMapScreen extends ConsumerStatefulWidget {
  const BodyMapScreen({super.key});

  @override
  ConsumerState<BodyMapScreen> createState() => _BodyMapScreenState();
}

class _BodyMapScreenState extends ConsumerState<BodyMapScreen> {
  late BodyMapSelection _selection;

  @override
  void initState() {
    super.initState();
    // **The subscription is opened BEFORE the read, and it is load-bearing.**
    // `symptomFormControllerProvider` is `autoDispose`, and `ref.read` creates
    // no listener at all — so a screen that only ever `read` it would hold it
    // open for the duration of each call and no longer. With screen 12 pushed
    // underneath that is invisible (screen 12 watches the form, so it never
    // disposes); on a COLD DEEP LINK there is no screen 12, and every point
    // the user placed would be written into a provider that disposed itself
    // before the next tap could read it back. The two cases look identical
    // from inside this file, which is exactly why the subscription is
    // explicit rather than inherited from whoever happens to be below.
    //
    // `listenManual` rather than `ref.watch`: this screen owns its own
    // [BodyMapSelection] and must NOT rebuild from the form — it is the only
    // writer while it is mounted, so watching would feed its own writes back
    // to it. The subscription is closed automatically when this State is
    // disposed.
    final ProviderSubscription<SymptomForm> form = ref.listenManual(
      symptomFormControllerProvider,
      (_, _) {},
    );
    _selection = _rehydrate(form.read().bodyMapPoints);
  }

  /// Rebuilds the selection from the drafts already in the form (R7).
  ///
  /// Every draft `toDrafts()` emits is RATED, so a round trip through the form
  /// returns a fully-rated selection — which is the same statement as "an
  /// unrated placement does not survive leaving", made from the other side.
  ///
  /// A draft whose `region` is null or outside `kRegionLabels` is skipped
  /// rather than placed: `bodyMapPoints` is a public field on a public value
  /// class, and a code this screen cannot draw a chip for would otherwise be
  /// a point the user can see in the counter and never remove.
  static BodyMapSelection _rehydrate(List<SymptomEntryDraft> points) {
    final intensities = <String, int?>{};
    for (final SymptomEntryDraft point in points) {
      final String? region = point.region;
      if (region == null || !kRegionLabels.containsKey(region)) continue;
      intensities[region] = point.intensity;
    }
    return BodyMapSelection(
      intensities: Map<String, int?>.unmodifiable(intensities),
    );
  }

  /// Adopts [next] and writes it straight through to the form (R7).
  ///
  /// The ONE place either half happens, so a change can never reach the screen
  /// without reaching the form — the defect a "write on Done" shape would make
  /// reachable, and the reason `setBodyMapPoints` is called here rather than
  /// in [_leave].
  void _apply(BodyMapSelection next) {
    setState(() => _selection = next);
    ref
        .read(symptomFormControllerProvider.notifier)
        .setBodyMapPoints(next.toDrafts());
  }

  /// A tap on the silhouette at [localPosition], in the figure's own
  /// coordinates.
  ///
  /// The figure is painted at EXACTLY [kBodyMapUserSpace] — 120x220 logical
  /// pixels, 1:1 with the mockup's own `viewBox` — so the rect handed to
  /// [regionAt] is the box itself and there is no scale factor, matrix or zoom
  /// level anywhere in this path (T21-J). A tap that hits no zone (the head,
  /// an arm, the background) places nothing: [regionAt] returns null and this
  /// method returns, rather than guessing at a nearest region.
  void _handleFigureTap(Offset localPosition) {
    final String? region = regionAt(
      localPosition,
      Offset.zero & kBodyMapUserSpace,
    );
    if (region == null) return;
    _apply(_selection.toggle(region));
  }

  /// Leaves the screen with no value (R7), or hands the user to screen 12 when
  /// there is nothing to pop (R11).
  ///
  /// `context.pop()` on the root of the stack asserts "there is nothing to
  /// pop", so the cold-link case needs an answer rather than a crash.
  /// `/symptoms/new` is that answer: the points just placed are already in the
  /// autoDispose form, screen 12 is the only surface that can save them, and
  /// `go` reaches it in the same frame — so the form keeps a listener
  /// throughout and is never torn down between the two screens.
  ///
  /// **`go` REPLACES**, so on that path screen 12 arrives as the ROOT of the
  /// stack — which is why screen 12's own chevron is the same `canPop`-guarded
  /// shape (`_leaveSymptomForm`, `symptom_form_screen.dart`). A hand-off into
  /// a screen whose back affordance then throws would not be an answer to the
  /// cold link, only a longer route to the same crash. The two screens now
  /// share ONE exit idiom; screen 11's is booked for P4b-T16b.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.symptomsNew);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The mockup's `‹`, as a real back affordance — this is a pushed
            // route, so there is something to pop back to. In the LAYOUT
            // rather than positioned over the scroll view, screen 12's
            // precedent: content that came to rest under a floating chevron
            // would silently stop accepting taps, and this screen's content
            // is tappable end to end.
            //
            // `semanticLabel` on the Icon, never `tooltip:`, which Material
            // surfaces as a SEPARATE semantics field rather than the button's
            // own name. The word is `MaterialLocalizations`' — the platform's
            // own, translated name for this control.
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(
                    Icons.chevron_left,
                    semanticLabel: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                  ),
                  color: c.muted,
                  onPressed: _leave,
                ),
              ),
            ),
            // The body SCROLLS and the footer does not — screen 12's S7, for
            // screen 12's reason, and here it is also what keeps the promise
            // T21a's `kBodyMapMinPaintedHeight` extracts: the silhouette has
            // only 16 logical px of slack over the floor that keeps `pelvis`
            // above the 24 px tap-target minimum, so a layout short of
            // vertical room must scroll rather than shrink the figure. It
            // cannot shrink: the figure is a fixed 120x220 box.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                child: _BodyMapBody(
                  selection: _selection,
                  onTapFigure: _handleFigureTap,
                  onToggleRegion: (region) =>
                      _apply(_selection.toggle(region)),
                  onSetIntensity: (region, value) =>
                      _apply(_selection.setIntensity(region, value)),
                ),
              ),
            ),
            _BodyMapFooter(selection: _selection, onDone: _leave),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The scrolling body
// ---------------------------------------------------------------------------

/// Everything above the pinned footer, top to bottom.
class _BodyMapBody extends StatelessWidget {
  const _BodyMapBody({
    required this.selection,
    required this.onTapFigure,
    required this.onToggleRegion,
    required this.onSetIntensity,
  });

  final BodyMapSelection selection;
  final ValueChanged<Offset> onTapFigure;
  final ValueChanged<String> onToggleRegion;
  final void Function(String region, int? value) onSetIntensity;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final List<String> placed = selection.placedRegions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const LumenSectionLabel(
          kBodyMapSectionLabel,
          fontSize: 11,
          letterSpacing: 1.5,
        ),
        const SizedBox(height: 4),
        Semantics(
          header: true,
          child: Text(
            kBodyMapTitle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
        ),
        const SizedBox(height: 4),

        // R9 + R10 — ONE summary node over the counter AND the figure, because
        // the counter is exactly the figure's summary: `label` names the
        // picture, `value` is the count.
        //
        // **Not a `liveRegion`.** All seven existing `liveRegion` sites in
        // `client/lib` are appear-once messages; this counter is permanently
        // mounted and changes on every tap, so flagging it would re-announce
        // on every placement — a new use of the flag and a chattiness
        // regression.
        //
        // **`ExcludeSemantics` over the subtree is R10, not an oversight.**
        // Individual zones get NO semantics nodes: a screen reader cannot aim
        // a tap at a pixel region, and the all-8 chip list below is the
        // complete input path (R3) — which is precisely what R-15's "non-tap
        // path" requires. Announcing eight invisible sub-targets that only a
        // sighted user can hit would be worse than announcing none.
        Semantics(
          container: true,
          label: kBodyMapFigureLabel,
          value: bodyMapPointsPlaced(selection.pointCount),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  bodyMapPointsPlaced(selection.pointCount),
                  style: TextStyle(fontSize: 11, color: c.muted),
                ),
                const SizedBox(height: 10),
                _FigureCard(placedRegions: placed, onTap: onTapFigure),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // R3 — ALL EIGHT ratified regions, in frozen declaration order, as the
        // COMPLETE input path. Four of them (`lower_back`, `bowel_rectal`,
        // `bladder`, `vaginal`) have no hit zone and no marker, deliberately:
        // a pixel zone for them on an anterior figure would be an invented
        // anatomical projection. They are placed here and nowhere else, and
        // the chip — not the picture — is the authoritative display of what is
        // placed.
        const LumenFieldLabel(kBodyMapRegionsLabel),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final MapEntry<String, String> entry in kRegionLabels.entries)
              LumenSelectableChip(
                label: entry.value,
                selected: selection.isPlaced(entry.key),
                onTap: () => onToggleRegion(entry.key),
              ),
          ],
        ),

        // R2 — one intensity block per PLACED region, stacked below the whole
        // chip row and iterated over `placedRegions`, which derives its order
        // from `kRegionLabels` rather than from tap order. Frozen order is
        // what stops the list reordering under the user on every tap; it is
        // also the order `toDrafts()` emits in, derived from the same getter,
        // so what the user sees and what the wire receives cannot drift.
        for (final String region in placed) ...<Widget>[
          const SizedBox(height: 14),
          _IntensityBlock(
            key: bodyMapIntensityKey(region),
            label: kRegionLabels[region]!,
            // T20-J's convention — `<Region> intensity`. This screen can
            // render eight scales at once and every one of them draws stops
            // labelled `0`..`10`, so without it they all announce the same
            // thing.
            semanticsLabel: '${kRegionLabels[region]!} intensity',
            value: selection.intensities[region],
            onChanged: (value) => onSetIntensity(region, value),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The figure
// ---------------------------------------------------------------------------

/// The mockup's `--in`-filled, `--bd`-outlined, radius-14 card with the
/// silhouette centred in it.
class _FigureCard extends StatelessWidget {
  const _FigureCard({required this.placedRegions, required this.onTap});

  final List<String> placedRegions;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        // `onTapDown` rather than `onTap`: the position is the input here, and
        // `onTap` carries none. `HitTestBehavior.opaque` so a tap on the
        // figure's empty background (the head, an arm, the gap beside the
        // torso) still reaches this handler and is answered with "no region"
        // rather than falling through to whatever is underneath.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails details) => onTap(details.localPosition),
          child: CustomPaint(
            key: kBodyMapFigureKey,
            // EXACTLY the mockup's user space. The svg is
            // `viewBox="0 0 120 220" width="150" height="220"`, whose default
            // `xMidYMid meet` fits at scale 1 with horizontal letterboxing and
            // none vertically — so 120x220 logical px reproduces it, and the
            // 15 px of empty letterbox each side is exactly the Center's own
            // slack. Painting at user size is what makes `regionAt`'s rect the
            // box itself and removes every scale factor from the tap path.
            size: kBodyMapUserSpace,
            painter: _BodyMapPainter(
              figureColor: c.muted,
              markerColor: c.accent,
              markedRegions: placedRegions,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws `Screens/screen_13_body_map.html`'s one svg, verbatim, plus one flat
/// marker per placed region that HAS a hit zone.
///
/// The mockup's svg, transcribed element for element:
/// ```
/// <ellipse cx="60" cy="22" rx="14" ry="16" .../>
/// <path d="M46 38 Q60 34 74 38 L82 76 Q86 110 80 140 L74 200 L66 202
///          L62 150 L58 150 L54 202 L46 200 L40 140 Q34 110 38 76 Z" .../>
/// <path d="M40 60 L24 110 L28 140  M80 60 L96 110 L92 140" .../>
/// ```
/// all three `fill="none" stroke="var(--mut)" stroke-width="1.2"`. The three
/// accent circles it also draws — `(60,100) r7 @.85`, `(54,115) r5 @.7`,
/// `(66,92) r4 @.6` — are a design fixture showing three placed points, not
/// chrome: they are replaced by [markedRegions], at ONE radius and full
/// opacity (R4).
///
/// **A PRIVATE class in the screen file**, the `_MoonPainter` house idiom
/// (`welcome_screen.dart:165-206`): constructor-injected colours, a
/// `shouldRepaint` that is a field equality, and a dartdoc naming the exact
/// mockup svg it transcribes. `CustomPainter` is on neither
/// `kWidgetSuperclasses` nor `kNonWidgetSuperclasses`, but the widget-coverage
/// rule scans `lib/shared/**` only (`screen_registry.dart:815-817,:844-874`),
/// so a painter under `features/**/presentation/` is invisible to both rules —
/// this class is covered by the screen's own artifacts instead.
///
/// **No semantics of any kind, and no zone is addressable.** See the
/// `ExcludeSemantics` in `_BodyMapBody`: the chip list is the accessible path
/// (R3/R10), and eight invisible sub-targets a screen-reader user cannot aim
/// at would be noise rather than access.
///
/// [markedRegions] is `placedRegions` — the SINGLE order derivation — and a
/// region with no entry in [kBodyMapRegionZones] draws NOTHING (R3). No
/// position is invented for it, no legend pin and no "elsewhere" bucket: the
/// chip list already shows it as placed, and the picture shows what it can
/// honestly show.
class _BodyMapPainter extends CustomPainter {
  const _BodyMapPainter({
    required this.figureColor,
    required this.markerColor,
    required this.markedRegions,
  });

  /// The silhouette's stroke — the mockup's `var(--mut)`.
  final Color figureColor;

  /// The markers' fill — the mockup's `var(--ac)`, at full opacity.
  final Color markerColor;

  /// Placed regions in `kRegionLabels` order. Only those with a hit zone draw.
  final List<String> markedRegions;

  @override
  void paint(Canvas canvas, Size size) {
    // The box is [kBodyMapUserSpace], so the mockup's own numbers are used
    // raw. Nothing here scales, translates or transforms the canvas.
    final Paint stroke = Paint()
      ..color = figureColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(60, 22),
        width: 28, // rx 14
        height: 32, // ry 16
      ),
      stroke,
    );

    final Path torso = Path()
      ..moveTo(46, 38)
      ..quadraticBezierTo(60, 34, 74, 38)
      ..lineTo(82, 76)
      ..quadraticBezierTo(86, 110, 80, 140)
      ..lineTo(74, 200)
      ..lineTo(66, 202)
      ..lineTo(62, 150)
      ..lineTo(58, 150)
      ..lineTo(54, 202)
      ..lineTo(46, 200)
      ..lineTo(40, 140)
      ..quadraticBezierTo(34, 110, 38, 76)
      ..close();
    canvas.drawPath(torso, stroke);

    // One `Path` with two subpaths, exactly as the mockup's single `d`
    // attribute has: the second `M` starts a new subpath rather than closing
    // the first.
    final Path arms = Path()
      ..moveTo(40, 60)
      ..lineTo(24, 110)
      ..lineTo(28, 140)
      ..moveTo(80, 60)
      ..lineTo(96, 110)
      ..lineTo(92, 140);
    canvas.drawPath(arms, stroke);

    final Paint marker = Paint()
      ..color = markerColor
      ..style = PaintingStyle.fill;
    for (final String region in markedRegions) {
      final Rect? zone = kBodyMapRegionZones[region];
      // R3 — a region with no zone gets no marker. `continue`, never a
      // fallback position.
      if (zone == null) continue;
      // The zone's centre, and one radius for every marker regardless of
      // intensity (R4).
      //
      // **A known cosmetic, and a deliberate consequence of that rule:**
      // `legs`'s zone spans BOTH legs, so its centre (60,177) falls in the
      // gap the silhouette draws between them and the marker overlaps each
      // inner edge rather than sitting on a leg. Every available correction
      // invents something — nudging it onto one leg invents laterality, which
      // R1 cut so completely that `side` is not a field this screen has, and
      // a second `legs` zone would invent an anatomy the ratified vocabulary
      // does not carry. "Paint at the zone's centre" is the rule; this is
      // what it looks like for the one zone that spans a gap. Recorded for
      // the design pass rather than patched here.
      canvas.drawCircle(zone.center, kBodyMapMarkerRadius, marker);
    }
  }

  @override
  bool shouldRepaint(_BodyMapPainter old) =>
      old.figureColor != figureColor ||
      old.markerColor != markerColor ||
      !listEquals(old.markedRegions, markedRegions);
}

// ---------------------------------------------------------------------------
// One intensity block
// ---------------------------------------------------------------------------

/// A label, a [LumenIntensityScale] and nothing else.
///
/// Screen 12's `_IntensityBlock` minus its `errorMessage` slot: this screen
/// posts nothing (R-11), so there is no rejection that could land on a point.
/// T21-P rules an `entries[N].region` rejection unreachable — every value this
/// screen can emit comes from a frozen client-side vocabulary — and screen 12
/// still owns the banner for anything that does come back.
class _IntensityBlock extends StatelessWidget {
  const _IntensityBlock({
    required this.label,
    required this.semanticsLabel,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Drawn above the scale, in sentence case.
  final String label;

  /// What the scale announces — `<Region> intensity`.
  final String semanticsLabel;

  /// The point's logged intensity, or `null` for "placed, not rated yet".
  /// **`0` is a real datum** and is passed straight through; nothing here
  /// tests it for truthiness.
  final int? value;

  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // announce: false — the scale below carries [semanticsLabel] as its
        // OWN name, so announcing this caption too would put a second,
        // unassociated copy of it in the reading order.
        LumenFieldLabel(label, announce: false),
        const SizedBox(height: 6),
        LumenIntensityScale(
          value: value,
          semanticsLabel: semanticsLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The pinned footer
// ---------------------------------------------------------------------------

/// The block reason and the `Done` affordance — outside the scroll view,
/// always on screen.
///
/// The goals/screen-12 shape (R8): a blocked affordance **plus** the reason
/// drawn beside it, never a bare disabled control — `goals_screen.dart:184-186`
/// states the rule, "the reason is never left to be guessed". The reason comes
/// STRAIGHT from `BodyMapSelection.blockReason`; nothing composes a sentence
/// here.
///
/// Deliberately NOT a live region, screen 12's precedent: the reason sits
/// directly above the control it disables, and a live region would re-announce
/// on every one of eight chip taps.
class _BodyMapFooter extends StatelessWidget {
  const _BodyMapFooter({required this.selection, required this.onDone});

  final BodyMapSelection selection;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final String? blockReason = selection.blockReason;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (blockReason != null) ...<Widget>[
            LumenFieldMessage(blockReason),
            const SizedBox(height: 8),
          ],
          // R6 — a TextButton, not the mockup's filled primary. Nothing is
          // pending (R7 writes live), so a primary-weight commit button would
          // promise a save this screen does not perform.
          TextButton(
            // Gated on `canApply`, which is `blockReason == null` — never on a
            // condition recomputed here.
            onPressed: selection.canApply ? onDone : null,
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              disabledForegroundColor: c.muted.withValues(alpha: 0.4),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(kBodyMapDoneLabel),
          ),
        ],
      ),
    );
  }
}
