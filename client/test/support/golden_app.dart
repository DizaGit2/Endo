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
