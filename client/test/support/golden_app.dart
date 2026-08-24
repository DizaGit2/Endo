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
//      the diff** (on Linux — see rule 9; off Linux the goldens are
//      skipped and the command writes nothing) — neither character count
//      nor "it's just a synonym of similar length" is a safe test either
//      way.
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
//   9. **A GOLDEN IMAGE IS A LINUX ARTIFACT AND IS ONLY COMPARED ON LINUX —
//      P4b-T25a.** The first push of this branch turned `ci-client` red on
//      four screens (`day_log_editor`, `period_editor`, `baseline`,
//      `onboarding_shell`, both themes) while ~70 other goldens passed. It is
//      not a visual regression and not a blanket platform difference. What
//      follows separates what was MEASURED from what remains open, because
//      this file has shipped a plausible-sounding mechanism four times
//      already (rules 6, 7, 8) and a fifth would be worse than an admission.
//
//      MEASURED, on the CI artifacts and reproduced on the dev machine:
//      * Every differing pixel is the TOP or BOTTOM row of a blocked text
//        rectangle. Every interior row and every x-extent is byte-identical,
//        so the font, its glyph advances, and every box height are the same
//        on both hosts. The disagreement is SUB-PIXEL and VERTICAL.
//      * Alchemist blocks text through two paints and only one is
//        antialiased. A `RenderParagraph` child goes through
//        `BlockedTextPaintingContext.paintChild`, which sets
//        `isAntiAlias = false` and the text's own colour — hard rows. Text
//        painted by a render object that is NOT a `RenderParagraph` — here
//        that is exclusively `RenderEditable`, i.e. a `TextField` WITH TEXT
//        IN IT — goes through `BlockedTextCanvasAdapter.drawParagraph`, which
//        draws with a bare `Paint()`: **opaque black, antialiasing ON**. Its
//        two edge rows are coverage blends that encode the fractional y to
//        ~1/255, so ANY sub-pixel difference shows. Such rects are the only
//        source of pure `#000000` in a golden: **exactly 10 of 78 committed
//        goldens contain pure black.**
//      * Reading those blends back gives the geometry directly. Windows:
//        `baseline_screen`'s two editables sit at y = 146.53142 and 230.53142
//        (matching the layout measured in-process to five decimals),
//        `day_log_editor`'s at 645.03142. Linux: both land on .7608. So the
//        editable rects moved DOWN by 0.23 px and 0.73 px respectively.
//      * The fractional part comes from ONE place. `InputDecorator` positions
//        input and hint by BASELINE (`offset.dy = baseline -
//        box.getDistanceToBaseline(alphabetic)`), and with an
//        `OutlineInputBorder` that resolves to `dy = max(hintBaseline,
//        inputBaseline) - ownBaseline + (containerHeight - inputHeight) / 2`.
//        For the HINT the first term is 0, leaving 13.5 or 13.0 — integer
//        arithmetic. For the INPUT it leaves `hintBaseline - inputBaseline`,
//        measured here as **16.625713348388672 - 15.594292 = 1.031421** — the
//        only non-integer term in any blocked rect's position in this app.
//        (Everything else is integral because the engine ROUNDS paragraph
//        heights: measured, 22 px x 1.4 -> 31.0, 11 px x 1.45 -> 16.0,
//        12 px x 1.43 -> 17.0.)
//      * `lumen_input_field`'s own goldens hold pure-black rects and PASS:
//        its scenarios pass no `hint`, so `hintBaseline` is 0, the float term
//        cancels, and the rects land on 185.5 and 425.0.
//
//      OPEN, and stated as open: `onboarding_shell`'s two differing rects are
//      HINTS, not editables — hard-edged, `--mut` at 0.6 alpha, 21 px tall,
//      measured at exactly y = 215.5 and 299.5, i.e. the pure integer branch
//      above. In the Linux image each is one row TALLER AT THE TOP with the
//      bottom row unchanged, which is a bigger ascent, not a translation
//      (a translation would move both edges). **The obvious explanation —
//      that a hard edge exactly on a half-pixel is a rounding tie the two
//      rasterizers break differently — is REFUTED here, not merely
//      unverified: `account_screen`'s three hint rects sit at exactly 228.5,
//      313.5 and 398.5, the same .5, and that golden passes on Linux.**
//      A wholesale font-metric swap is ruled out too: Alchemist's own caption
//      (`GoldenTestTheme.nameTextStyle`, `fontSize: 18` with NO `height:`, so
//      its box is pure font metrics) renders 22 rows in BOTH images, so the
//      two hosts agree on Roboto's natural line height. Whatever moves the
//      `onboarding_shell` hints is not determinable from a Windows machine,
//      and nothing here should be read as knowing it.
//
//      **Predictive rule — use the granularity the evidence supports.** All
//      eight failures are inside a `LumenInputField`, and nothing outside one
//      failed. `InputDecorator` is the fragile surface, because it is the
//      only widget in this app that turns a font-metric float into a paint
//      offset. A field WITH TEXT is reliably fragile (3 screens of 3); a
//      field showing only its hint is sometimes fragile (`onboarding_shell`
//      yes, `account_screen` no) for a reason we cannot yet name. **So: the
//      next golden to break will be the next one that photographs a
//      `LumenInputField`** — and the cheap check on any suspect image is
//      whether it contains pure black.
//
//      **Consequence, and it is a process rule.** The committed
//      `goldens/ci/*.png` are now **Linux renders** (T25a took the CI
//      runner's own images as the masters for the eight), and
//      `goldenTestLightAndDark` therefore COMPARES THEM ONLY ON LINUX; on any
//      other host it registers the pair as a skipped test. Do NOT run
//      `flutter test --update-goldens` on Windows or macOS expecting it to
//      help: it now writes nothing, which is deliberate — a Windows
//      regeneration is what put the branch in this state. To update a golden,
//      run the `regenerate-goldens` workflow (`ci-client.yml`,
//      `workflow_dispatch`) and commit the artifact, or run the suite in a
//      Linux container. To SEE a failure on Windows, set
//      `LUMEN_GOLDEN_COMPARE=1`: the four screens above then fail by exactly
//      614/614/400/400/110/110 px, which is the platform delta and not a
//      regression.
//      **This supersedes `flutter_test_config.dart`'s original claim that
//      blocked text makes the output "identical regardless of the host OS or
//      font renderer". That claim was false, and it is why the divergence
//      went unnoticed until the branch was first pushed.**

import 'dart:io' show Platform;

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Whether the committed `goldens/ci/*.png` may be compared on this host.
///
/// The masters are **Linux renders** (see rule 9). Comparing them anywhere
/// else measures the host's font backend, not the app: it is how P4b-T25a's
/// four screens went red on their first push. So the comparison runs on
/// Linux — the CI runner, and the only host that can also regenerate them —
/// and nowhere else.
///
/// `LUMEN_GOLDEN_COMPARE` forces the comparison on regardless. It exists to
/// let a non-Linux machine SEE a failure (the four T25a screens will fail by
/// exactly 614/614/400/400/110/110 px), never to update a golden: a
/// `--update-goldens` run under that flag would write host-specific images
/// over the Linux masters and put the branch straight back where it was.
final bool kGoldensAreComparedHere =
    Platform.isLinux ||
    Platform.environment.containsKey('LUMEN_GOLDEN_COMPARE');

/// Why a golden pair did not run, printed by the test runner on non-Linux
/// hosts so the skip is self-explaining rather than mysterious.
const String kGoldensSkipReason =
    'CI goldens are Linux artifacts (see golden_app.dart rule 9). Regenerate '
    'via the regenerate-goldens workflow; set LUMEN_GOLDEN_COMPARE=1 to '
    'compare here anyway.';

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
  if (!kGoldensAreComparedHere) {
    // Registered, not silently dropped: `goldenTest`'s own `skip:` returns
    // before declaring anything, which would leave a golden file with zero
    // tests and make `flutter test <that file>` an error. A real skipped test
    // keeps the pair visible in the run and names why it did not execute.
    test('\$subject light theme', () {}, skip: kGoldensSkipReason);
    test('\$subject dark theme', () {}, skip: kGoldensSkipReason);
    return;
  }

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
