// ---------------------------------------------------------------------------
// golden_app.dart — the phone frame + the light/dark pair (P4b-T3)
// ---------------------------------------------------------------------------
//
// A golden test has no `WidgetTester` when `builder:` runs, so it cannot use
// `pump_app.dart`. What it does share is the frame and the boilerplate: every
// golden file in this repo declared its own `_kWidth`/`_kHeight` and then wrote
// the same two near-identical `goldenTest(...)` calls.
//
// The frame is 390 x 844 LOGICAL pixels (the iPhone-14 portrait frame — the
// design system's 300 px mockups are not the Flutter surface size). The
// committed PNGs are 390 x 874 because Alchemist draws a 30 px caption band
// above the scenario; do not "correct" the constants to 874.
//
// Rules baked in here, all of which the shipped goldens obey and every new one
// must (see `.superpowers/sdd/lumen-build/survey/client-test-infra.md` §2.3):
//   1. `SizedBox(width, height)` — GoldenTestGroup lays out with an intrinsic
//      column table, so an unbounded child throws "given an infinite size".
//   2. `MediaQuery(size:)` — Scaffold's safe-area maths needs one inside
//      Alchemist's bare wrapper.
//   3. `debugShowCheckedModeBanner: false`.
//   4. `theme: lumenTheme(brightness)` — the only way LumenColors reaches the
//      tree.
//   5. Never golden a loading state: `pumpBeforeTest` defaults to
//      `onlyPumpAndSettle`, so an indeterminate spinner or a never-resolving
//      controller hangs the test.
//   6. `obscureText: true` is on globally (flutter_test_config.dart), so these
//      images prove layout, geometry and NON-TEXT colour (backgrounds,
//      borders, decorations). Assert strings in the semantics/widget test
//      instead — a golden can never tell you WHICH glyphs were drawn.
//      **The insensitivity criterion is EQUAL RENDERED WIDTH, not equal
//      character count and not equal glyph identity — this is the FOURTH
//      false or imprecise self-description this file has carried, and the
//      second correction to THIS SAME rule** (P4b-T13/M9 first wrote
//      "equal character count"; P4b-T16/fix-round-1 measured that the
//      criterion was wrong but got the MECHANISM sentence wrong too;
//      P4b-T16/fix-round-2 corrects the mechanism). Sharpest control
//      (fix-round-2): `"Bloating"` -> `"Blotaing"` — the same 8 glyphs,
//      reordered, identical rendered width — passes at 0 px. `"lllllll"`
//      -> `"WWWWWWW"` (same length, very different width) does not. It is
//      width, specifically, that the images are insensitive to holding
//      equal — never character count, never which glyphs are present.
//
//      **The mechanism has TWO environments that give opposite answers,
//      and that split is the part worth remembering.**
//      `BlockedTextPaintingContext.paintChild` (`alchemist` 0.14.0,
//      `blocked_text_image.dart:34-44`) draws its rectangle at
//      `child.size` — the REAL `RenderParagraph` size ordinary text layout
//      already computed, before any glyph is replaced — so the block's
//      width always tracks the true rendered width of the run. What
//      changes between environments is which FONT that layout used:
//        - In an ORDINARY `flutter_test` widget test (no golden), the
//          binding's default font genuinely IS fixed-advance. Measured
//          directly, in this repo, outside any golden: `"lllllll"` and
//          `"WWWWWWW"` both come out **78.75 px** wide. Character count
//          really is a safe proxy for width here.
//        - Inside an `alchemist` golden, it is not: `goldenTest`'s setup
//          (`_setUpGoldenTests` -> `loadFonts()`,
//          `alchemist-0.14.0/lib/src/golden_test.dart:26-30`, `:38-67`)
//          reads this app's OWN `FontManifest.json` and registers every
//          real bundled family — including proportional Roboto — before
//          the first `goldenTest` body runs. Measured directly, inside a
//          golden: the SAME two strings come out **20.44 px** and
//          **70.06 px**. `obscureText` swaps what gets PAINTED; it never
//          touches what MEASURED the paragraph, and inside a golden that
//          measurement uses a real proportional font.
//      **This split is exactly why the original "fixed-advance test font"
//      claim looked right for so long: it is true of an ordinary widget
//      test and false of a golden**, and this file is about goldens. A
//      mechanism claim measured in the wrong environment reads as
//      confirmed and is not.
//
//      Consequence for real copy: two same-length English words are NOT
//      reliably close in rendered width. `"Bloating"`/`"Headache"`
//      (`day_detail_screen.dart`'s label map, the actual production edit
//      that surfaced this) measure **42.28 px** and **51.48 px** inside a
//      golden — 22% apart, not "close" — which is why that equal-length
//      swap reddened both goldens by 847 px. **Treat every copy edit,
//      length-changing or not, as needing `--update-goldens` and a look at
//      the diff** — neither character count nor "it's just a synonym of
//      similar length" is a safe test either way.
//   7. **TEXT OPACITY IS INVISIBLE TO A BLOCKED-TEXT GOLDEN — this is the
//      second false self-description this file has carried** (P4b-T13 found
//      the copy-insensitivity one above; P4b-T15/fix-round-1 found this one).
//      `alchemist`'s `BlockedTextPaintingContext.paintChild` (0.14.0) draws a
//      `RenderParagraph`'s block using `child.text.style?.color` DIRECTLY,
//      bypassing the render tree's paint-time opacity compositing an
//      `Opacity` ancestor would normally apply. Measured on a real shipped
//      artifact: every day number in `cycle_calendar_screen_light.png`
//      — including the ones P4b-T15 draws inside `Opacity(opacity: 0.3, …)`
//      for an adjacent-month day — samples as the exact same full-strength
//      `#3B2A20`, dimmed or not. So "these images prove … colour" in rule 6
//      is true of a widget's OWN paint colour and false of opacity applied
//      to TEXT above it in the tree: a golden cannot distinguish a dimmed
//      text node from a full-strength one. Assert `Opacity.opacity` directly
//      in a widget test instead (`cycle_calendar_screen_semantics_test.dart`,
//      "an adjacent-month cell is drawn at 0.3 opacity…").
//   8. **AN `Icon` IS BLOCKED THE SAME WAY A `Text` IS, AND FOR THE SAME
//      REASON — P4b-T18 fix round 2.** `Icon`'s `build` wraps its glyph in a
//      `RichText` (`widgets/icon.dart:328`), which is a `RenderParagraph` —
//      the exact type `BlockedTextPaintingContext.paintChild` matches on
//      (`alchemist` 0.14.0, `blocked_text_image.dart:34-41`):
//      `if (child is RenderParagraph) { … canvas.drawRect(offset &
//      child.size, paint); }`. **The glyph itself is never painted at
//      all** — not blocked-and-measured, simply never drawn — so these
//      images are insensitive to which `IconData` was chosen. What DOES
//      still reach the canvas is the same two things rule 6 already names
//      for text: the rect's SIZE (`child.size`, driven by `Icon.size`) and
//      its COLOUR (`child.text.style?.color`, i.e. `Icon.color` — an icon
//      swap paired with a colour change still shows). Measured directly:
//      swapping an icon's `IconData` to an unrelated one leaves all four
//      goldens green; changing only its `size` reddens all four.
//
//      **Do not attribute the size-insensitivity-across-codepoints to "the
//      icon font is monospaced so every glyph has the same advance width"**
//      — that is plausible-sounding and WRONG for the same reason rule 6's
//      original claim was: it is environment-sensitive reasoning about what
//      a real font measures, and this file has now been corrected on it
//      three times (rule 6, rule 7, this one). The actual, environment-
//      INDEPENDENT reason two different icons at the same `size` paint
//      identically is `drawRect` itself — `child.size` is set by `Icon`'s
//      own layout (bound to the `size` parameter), not measured from
//      whatever glyph the chosen font happens to contain, and the branch
//      above never inspects the glyph at all.
//   9. **`hint: ''` ON A `LumenInputField` MOVES PAINTED TEXT BY A
//      HOST-DEPENDENT FRACTION OF A PIXEL — P4b-T25a, corrected in
//      fix-round-1.** The first push of this branch turned `ci-client` red on
//      four screens (`day_log_editor`, `period_editor`, `baseline`,
//      `onboarding_shell`, both themes) while the other 70 goldens passed. It
//      was not a visual regression and not a blanket platform difference: it
//      was one production typo-of-intent, `hint: ''` where the field wanted no
//      placeholder at all, and it is fixed at the source.
//
//      **The discriminator, measured directly.** Same widget, same style, same
//      golden environment (`loadFonts()`, 390x844, DPR 1), reading the
//      `RenderEditable`'s global `dy` and the hint paragraph's box:
//
//        | `hint`   | input `dy`           | hint paragraph   |
//        |----------|----------------------|------------------|
//        | `''`     | 14.531421661376953   | exists, 264 x 21 |
//        | `'Maya'` | 13.5                 | exists, 264 x 21 |
//        | `null`   | 13.5                 | absent           |
//
//      An EMPTY hint, and only an empty hint, is fragile, for TWO independent
//      reasons that between them account for all eight failures:
//        (a) `InputDecorator` positions input and hint by baseline
//            (`offset.dy = baseline - box.getDistanceToBaseline(alphabetic)`),
//            which with an `OutlineInputBorder` resolves to `dy =
//            max(hintBaseline, inputBaseline) - ownBaseline + (containerHeight
//            - inputHeight) / 2`. An empty paragraph reports a LARGER
//            alphabetic baseline than a shaped one in the identical style, so
//            `max(...)` picks the hint and leaves `hintBaseline -
//            inputBaseline = 1.031421661376953` in the input's paint offset.
//            With a real hint the two are equal and the term is 0; with `null`
//            there is no hint operand at all. **That float is the only
//            non-integer term in any blocked rect's position in this app**,
//            and it is the one POSITION the two host font backends were
//            measured to disagree about — (b) is a second disagreement, about
//            a block's height, and its mechanism is open
//            (Windows placed `baseline_screen`'s editables at y =
//            146.53142, Linux at 146.7608; `day_log_editor`'s at 645.03142 vs
//            645.7608).
//        (b) An empty hint is NOT invisible to a blocked-text golden —
//            MEASURED. The table above shows `''` laying out the same
//            264 x 21 box as `'Maya'` — `InputDecorator` stretches the hint
//            to the field — and Alchemist paints that box as a solid
//            full-width block with hard edges on exact half-pixels
//            (`onboarding_shell`'s two sat at y = 215.5 and 299.5, painted 21
//            rows on Windows and 22 on Linux). Deleting the hint deleted the
//            blocks: 8850 px of `--mut` at 0.6 became plain `--in`, and
//            nothing else in either image changed.
//
//            **WHY the two hosts painted a different number of rows there is
//            OPEN — and this line is a retraction.** Fix-round-1 wrote that a
//            non-antialiased edge on an exact half-pixel is a rounding tie the
//            two rasterizers broke differently, and called that "measured".
//            It was not measured, and three things it cannot survive:
//              * `''` and `'Maya'` lay out the SAME box at the SAME dy (the
//                table above), so "hard-edged block on a half-pixel" is
//                equally true of every real hint in this app. It cannot be
//                what separated `onboarding_shell` from the other 70.
//              * `account_screen_light.png` carries three hint blocks at rows
//                229..249, 314..334 and 399..419 — 21 rows each, the same
//                `[x.5, x.5]` hard-edged class — and that golden PASSED on
//                Linux.
//              * It contradicts `flutter_test_config.dart`, which says
//                placement is host-independent while it comes out of integer
//                or exact-half arithmetic. Both cannot be true.
//            What IS known: the two blocks existed, the two hosts drew them
//            with different heights, and they are gone. What is NOT known is
//            the mechanism, and it cannot be measured from a Windows host —
//            one Linux render of the pre-fix widget would settle it. Candidate
//            explanations are recorded in
//            `.superpowers/sdd/lumen-build/task-25a-review.md` (fix-round-1
//            re-review, C2); none is measured, and nothing here rests on one.
//            The fix does not rest on one either: it removes the blocks.
//
//      **The fix (fix-round-1): `hint` is `String?` and every no-placeholder
//      call site passes `null`.** The constructor asserts against `''` so the
//      trap cannot be re-entered. Measured after the change, on this Windows
//      machine: `baseline_screen`'s editable rects land on exactly
//      [145.5, 166.5], height exactly 21.0, both edge rows an exact 50/50
//      blend (125, 123, 119); `day_log_editor`'s and `period_editor`'s land on
//      exactly [644.0, 686.0] and [632.0, 674.0], height exactly 42.0, with no
//      edge blend at all; and `onboarding_shell`'s two diverging rects **no
//      longer exist**, because the paragraph that drew them is not built.
//      Nothing else in any of the eight images moved.
//
//      **The control that shows the new geometry survives the host crossing.**
//      `lumen_input_field_light.png` — a golden CI has compared successfully
//      on Linux — carries a blocked-text rect at exactly [185.5, 206.5],
//      height exactly 21.0, with both edge rows the same exact 50/50 blend
//      (125, 123, 119). That is the new `baseline_screen` geometry byte for
//      byte, already proven to cross Windows -> Linux unchanged. What is
//      KNOWN not to survive the crossing is a fractional position
//      (146.53142); the fix produces none. Whether a hard edge on a half-pixel
//      crosses is OPEN, per (b): `account_screen`'s three such blocks crossed,
//      `onboarding_shell`'s two did not, and no measurement from this host
//      separates them. The fix leaves this app with no blocked-text rect that
//      is not on an exact integer or an exact half-pixel, and the half-pixel
//      cases that remain are `RenderEditable` rects of the SAME class as
//      `lumen_input_field`'s, which crossed.
//
//      MEASURED AND STILL TRUE, about the images generally:
//      * Alchemist blocks text through two paints and only one is
//        antialiased. A `RenderParagraph` child goes through
//        `BlockedTextPaintingContext.paintChild`, which sets
//        `isAntiAlias = false` and the text's own colour — hard rows, with no
//        coverage blend to record where inside the pixel the edge fell. Text
//        painted by a render object that is NOT a `RenderParagraph` — here
//        that is
//        exclusively `RenderEditable`, i.e. a `TextField` WITH TEXT IN IT —
//        goes through `BlockedTextCanvasAdapter.drawParagraph`, which draws
//        with a bare `Paint()`: **opaque black, antialiasing ON**. Its edge
//        rows are coverage blends that encode the fractional y to ~1/255, so
//        any sub-pixel difference shows. Such rects are the only source of
//        pure `#000000` in a golden: **exactly 10 of 78 committed goldens
//        contain pure black.**
//      * Everything else is integral because the engine ROUNDS paragraph
//        heights: measured, 22 px x 1.4 -> 31.0, 11 px x 1.45 -> 16.0,
//        12 px x 1.43 -> 17.0. Integer geometry is bit-identical on any host,
//        which is why 70 goldens never noticed.
//
//      **Predictive rule.** `InputDecorator` is the fragile surface, because
//      it is the only widget in this app that turns a font-metric float into a
//      paint offset — and the only thing that made it produce one was an empty
//      hint, which no longer compiles past the assert. The next golden at risk
//      is still the next one that photographs a `LumenInputField`, and the
//      cheap check on any suspect image is whether it contains pure black; but
//      the known cause is closed at the source rather than absorbed by a
//      tolerance or by pinning the images to one operating system.
//
//      **What this file used to say here, and what was wrong with it.** T25a
//      shipped a rule 9 claiming `lumen_input_field`'s goldens pass because
//      *"its scenarios pass no `hint`, so `hintBaseline` is 0"*. `hint` was a
//      REQUIRED NON-NULLABLE `String` at the time and every one of those
//      scenarios passes a real string — the control case was false about the
//      code it cited, and it was the only thing separating the fragile fields
//      from the safe ones in that model. On the same false premise T25a
//      declared the half-pixel-tie explanation of `onboarding_shell`
//      *"REFUTED, not merely unverified"*, comparing `onboarding_shell`'s
//      hints with `account_screen`'s and calling them identical: one set was
//      `''` and the other real text, which is the entire variable. So the tie
//      is not refuted — but fix-round-1 then flipped it to "the measured
//      explanation" of (b), which was false in the other direction and is
//      retracted in (b) above. The honest state is OPEN, and it was OPEN
//      before either round said otherwise. **That is the SIXTH false
//      self-description this file has carried (rule 6 twice, 7, 8, T25a's
//      control case, and fix-round-1's own replacement for it) — the fifth
//      foreclosed the fix, and the sixth was written by the very round whose
//      subject was unearned certainty.** The lesson is narrower than "do not
//      guess": T25a DID separate measured from open and still shipped this,
//      because the false sentence sat in the MEASURED half; fix-round-1 then
//      moved a guess INTO that half while correcting the last one. Cite the
//      file and line for a claim about code, or do not make it — and when the
//      claim is about a host you cannot run, write OPEN and stop.

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:lumen/core/theme/lumen_theme.dart';

/// The golden surface, in logical pixels. The PNG on disk is 30 px taller.
const double kGoldenWidth = 390.0;

/// The golden surface, in logical pixels. The PNG on disk is 30 px taller.
const double kGoldenHeight = 844.0;

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

/// Wraps [home] in the size-bounded, themed phone frame every golden uses.
Widget goldenApp({
  required Widget home,
  required Brightness brightness,
  List<Override> overrides = const <Override>[],
}) {
  return _goldenFrame(
    overrides: overrides,
    app: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lumenTheme(brightness),
      home: home,
    ),
  );
}

/// The [goldenApp] frame for a screen that only exists as a route — the shell
/// chrome, for instance, which is a shell route's builder and has no
/// standalone widget to hand to `home:`.
Widget goldenRouterApp({
  required RouterConfig<Object> routerConfig,
  required Brightness brightness,
  List<Override> overrides = const <Override>[],
}) {
  return _goldenFrame(
    overrides: overrides,
    app: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: lumenTheme(brightness),
      routerConfig: routerConfig,
    ),
  );
}

Widget _goldenFrame({required Widget app, required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: SizedBox(
      width: kGoldenWidth,
      height: kGoldenHeight,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(kGoldenWidth, kGoldenHeight)),
        child: app,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// The light/dark pair
// ---------------------------------------------------------------------------

/// Declares the two goldens every screen ships: `<fileName>_light` and
/// `<fileName>_dark`.
///
/// [subject] names the thing under test (`'ProfileScreen'`); the test
/// descriptions become `'<subject> light theme'` / `'<subject> dark theme'`.
/// [fileName] is the golden's stem — the screen's file basename without
/// `.dart`, e.g. `'profile_screen'`, which is what the screen registry
/// (`test/shared/screen_registry_test.dart`) looks for on disk at
/// `goldens/ci/<fileName>_light.png` and `goldens/ci/<fileName>_dark.png`.
///
/// Call this at the top level of a `*_golden_test.dart` file, never inside a
/// `test(...)` body.
void goldenTestLightAndDark({
  required String subject,
  required String fileName,
  required Widget Function(Brightness brightness) build,
}) {
  goldenTest(
    '$subject light theme',
    fileName: '${fileName}_light',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(name: 'Light', child: build(Brightness.light)),
      ],
    ),
  );

  goldenTest(
    '$subject dark theme',
    fileName: '${fileName}_dark',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(name: 'Dark', child: build(Brightness.dark)),
      ],
    ),
  );
}
