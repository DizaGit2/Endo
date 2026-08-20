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
//      character count — this is the THIRD false or imprecise
//      self-description this file has carried, and the second correction to
//      THIS SAME rule** (P4b-T13/M9 first wrote "equal character count";
//      P4b-T16/fix-round-1 measured that claim itself and found it wrong).
//      `BlockedTextPaintingContext.paintChild` (`alchemist` 0.14.0,
//      `blocked_text_image.dart:34-44`) draws its rectangle at
//      `child.size` — the REAL `RenderParagraph` size that ordinary
//      proportional-font text layout already computed, before any glyph is
//      replaced. Obscuring swaps *what gets painted*, never *how the
//      paragraph was measured*, so the block's width tracks the true
//      rendered width of the run, and no fixed-advance/monospace test font
//      is configured anywhere in this repo to make character count a proxy
//      for it. **Measured directly** (P4b-T16/fix-round-1): two 7-glyph
//      strings of deliberately different composition ("lllllll" vs
//      "WWWWWWW") produce dramatically different block widths at equal
//      character count, while two ordinary same-length English words
//      (e.g. "Bloating"/"Headache") land close but not always exactly
//      equal — which is why an EQUAL-length production copy edit
//      (`day_detail_screen.dart`'s label map, `'Bloating'` ->
//      `'Headache'` and `'Fatigue'` -> `'Nauseaa'`) still reddened both
//      goldens by 847 px: two ordinary words of the same length usually
//      have close but not identical total glyph advance, and "close" is
//      not "insensitive". A length-changing copy edit (rule 6's original
//      example, "Phase shift" -> "Phase shifts") is the reliable, easy
//      case of the same underlying rule — more glyphs is a coarser and
//      more certain way to move the width than any same-length swap can be
//      relied on NOT to. **Treat every copy edit as needing
//      `--update-goldens` and a look at the diff** — length alone was
//      never a safe test either way, and neither is character count.
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
