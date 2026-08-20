// Tests for LumenBottomSheet — the phase's modal standard (P4b-T5, brief §2).
//
// TDD (RED first): this widget did not exist, and screens 9, 11, 12 and 13 are
// all modals-with-input. Its metrics are screen 9's mockup, which
// `screen-mockups.md` §9 calls "the canonical spec for P4b's sheets":
//
//     .dim  { position:absolute; inset:0; background:var(--ovl); }
//     .sheet{ background:var(--f); border-radius:24px 24px 0 0;
//             padding:18px 22px 26px; }
//     .hd   { width:32px; height:3px; background:var(--bd); border-radius:2px;
//             margin:0 auto 14px; }
//
// Screen 20's sheet is 36x4 with 22/22/24 padding; §15-D9 asked for one of the
// two to be standardised. Screen 9's is the one the brief names, and screen 20
// is not a P4b screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';

import '../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Mounts a screen with a button that opens the sheet, and returns a future
/// that completes with whatever the sheet was popped with.
Future<Future<String?>> _openSheet(
  WidgetTester tester, {
  Widget content = const Text('How\'s today?'),
  bool isDismissible = true,
  bool? enableDrag,
  Brightness brightness = Brightness.light,
}) async {
  late Future<String?> result;

  await pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () {
              result = showLumenBottomSheet<String>(
                context: context,
                isDismissible: isDismissible,
                enableDrag: enableDrag,
                builder: (_) => content,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

/// The sheet's own painted box (surface + top-only corners).
Container _sheetBox(WidgetTester tester) => tester.widget<Container>(
  find
      .descendant(
        of: find.byType(LumenBottomSheet),
        matching: find.byType(Container),
      )
      .first,
);

/// The grab handle: the small [Container] that is not the sheet box.
Container _handle(WidgetTester tester) => tester.widget<Container>(
  find.descendant(
    of: find.byType(LumenBottomSheet),
    matching: find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxWidth == 32,
    ),
  ),
);

void main() {
  // -------------------------------------------------------------------------
  // Opening and closing
  // -------------------------------------------------------------------------

  group('opening and closing', () {
    testWidgets('opens over the caller and shows the content', (tester) async {
      await _openSheet(tester);

      expect(find.byType(LumenBottomSheet), findsOneWidget);
      expect(find.text('How\'s today?'), findsOneWidget);
    });

    testWidgets('is not on screen until it is opened', (tester) async {
      await pumpApp(
        tester,
        home: const Scaffold(body: Center(child: Text('dashboard'))),
      );

      expect(find.byType(LumenBottomSheet), findsNothing);
    });

    testWidgets('tapping the scrim dismisses it with a null result', (
      tester,
    ) async {
      final result = await _openSheet(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(LumenBottomSheet), findsNothing);
      expect(await result, isNull);
    });

    testWidgets('isDismissible: false keeps it open on a scrim tap', (
      tester,
    ) async {
      await _openSheet(tester, isDismissible: false);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(LumenBottomSheet), findsOneWidget);
    });

    // Fix round 2, item 2: `enableDrag` defaults to MIRRORING
    // `isDismissible` when the caller does not pass it — pinned here
    // because nothing did. A caller who decided `isDismissible: false`
    // (a decision sheet the user must answer) and never mentioned drag at
    // all must not have that decision escapable by a swipe either.
    testWidgets(
      'isDismissible: false with NO enableDrag override also blocks a '
      'downward drag — the default mirrors isDismissible, not `true`',
      (tester) async {
        await _openSheet(tester, isDismissible: false);

        await tester.drag(find.byType(LumenBottomSheet), const Offset(0, 400));
        await tester.pumpAndSettle();

        expect(
          find.byType(LumenBottomSheet),
          findsOneWidget,
          reason:
              'enableDrag ?? isDismissible must resolve to false here — '
              'an `enableDrag ?? true` mutation would let a swipe escape '
              'an isDismissible: false decision sheet',
        );
      },
    );

    testWidgets('returns the value its content pops with', (tester) async {
      final result = await _openSheet(
        tester,
        content: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.pop(context, 'saved'),
            child: const Text('Save check-in'),
          ),
        ),
      );

      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      expect(await result, 'saved');
    });
  });

  // -------------------------------------------------------------------------
  // useRootNavigator (P4b-T18) — the sheet must cover the bottom nav
  // -------------------------------------------------------------------------
  //
  // `screen-mockups.md:354`, verbatim: "Bottom nav: belongs to Home (the
  // sheet covers the nav)." A sheet opened on a BRANCH Navigator (the SDK
  // default) mounts INSIDE that branch's own Overlay — a descendant of the
  // branch Navigator widget — leaving a sibling bottom nav outside the
  // branch untouched and tappable. Opened on the app's ROOT Navigator
  // instead, the sheet is not a descendant of the branch Navigator at all.

  group('useRootNavigator', () {
    testWidgets('mounts on the ROOT navigator, not a nested branch one', (
      tester,
    ) async {
      final branchNavigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          theme: lumenTheme(Brightness.light),
          home: Scaffold(
            body: Navigator(
              key: branchNavigatorKey,
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                builder: (context) => Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => showLumenBottomSheet<void>(
                        context: context,
                        builder: (_) => const Text('How\'s today?'),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(LumenBottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(branchNavigatorKey),
          matching: find.byType(LumenBottomSheet),
        ),
        findsNothing,
        reason:
            'the sheet mounted inside the BRANCH Navigator\'s own Overlay — '
            'a bottom nav living outside that branch would stay lit and '
            'tappable underneath the scrim, contradicting '
            'screen-mockups.md:354 ("the sheet covers the nav").',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Metrics — screen 9's mockup, exactly
  // -------------------------------------------------------------------------

  group('metrics', () {
    testWidgets('pads 18 top / 22 sides / 26 bottom', (tester) async {
      await _openSheet(tester);

      expect(
        _sheetBox(tester).padding,
        const EdgeInsets.fromLTRB(22, 18, 22, 26),
      );
    });

    testWidgets('is a surface with 24 px TOP corners only', (tester) async {
      await _openSheet(tester);
      final decoration = _sheetBox(tester).decoration! as BoxDecoration;

      expect(decoration.color, lumenLight.surface);
      expect(
        decoration.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
    });

    testWidgets('the grab handle is 32x3 on the border token, radius 2', (
      tester,
    ) async {
      await _openSheet(tester);
      final handle = _handle(tester);
      final decoration = handle.decoration! as BoxDecoration;

      expect(handle.constraints!.maxWidth, 32);
      expect(handle.constraints!.maxHeight, 3);
      expect(decoration.color, lumenLight.border);
      expect(decoration.borderRadius, BorderRadius.circular(2));
    });

    testWidgets('the handle sits 14 above the content', (tester) async {
      await _openSheet(tester);

      final gap = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(LumenBottomSheet),
              matching: find.byType(SizedBox),
            ),
          )
          .where((box) => box.height == 14);
      expect(gap, hasLength(1));
    });

    testWidgets('hugs the bottom rather than filling the screen', (
      tester,
    ) async {
      await _openSheet(tester);

      final sheet = tester.getRect(find.byType(LumenBottomSheet));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(sheet.bottom, screen.bottom);
      expect(sheet.height, lessThan(screen.height / 2));
    });
  });

  // -------------------------------------------------------------------------
  // The scrim — screen 9's `--ovl`, the one token that is screen-local
  // -------------------------------------------------------------------------

  group('scrim', () {
    test('is rgba(59,42,32,.45) light and rgba(0,0,0,.6) dark', () {
      expect(scrimFor(Brightness.light), const Color(0x733B2A20));
      expect(scrimFor(Brightness.dark), const Color(0x99000000));
    });

    testWidgets('the modal barrier is painted with it', (tester) async {
      await _openSheet(tester);

      final barriers = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .map((b) => b.color)
          .whereType<Color>();
      expect(barriers, contains(scrimFor(Brightness.light)));
    });

    testWidgets('and with the dark value in dark mode', (tester) async {
      await _openSheet(tester, brightness: Brightness.dark);

      final barriers = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .map((b) => b.color)
          .whereType<Color>();
      expect(barriers, contains(scrimFor(Brightness.dark)));
    });
  });

  // -------------------------------------------------------------------------
  // Dark theme
  // -------------------------------------------------------------------------

  testWidgets('takes its colours from the dark palette in dark mode', (
    tester,
  ) async {
    await _openSheet(tester, brightness: Brightness.dark);

    expect(
      (_sheetBox(tester).decoration! as BoxDecoration).color,
      lumenDark.surface,
    );
    expect(
      (_handle(tester).decoration! as BoxDecoration).color,
      lumenDark.border,
    );
  });

  // -------------------------------------------------------------------------
  // Tall content
  // -------------------------------------------------------------------------
  //
  // Screens 9, 11, 12 and 13 all put a form in this sheet. T20's is label +
  // eleven-stop scale + note field + CTA, which exceeds a 667 pt device once a
  // ~300 pt keyboard is up. A sheet that laid that out in an unscrollable
  // Column would throw `RenderFlex overflowed` — and nothing else in this file
  // would catch it, because every other test's content is one line of text on
  // an 844 pt surface.

  group('content taller than the viewport', () {
    /// 20 x 60 = 1200 logical px of content: taller than any test surface.
    Widget tallContent() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 20; i++)
          SizedBox(height: 60, child: Text('row $i')),
      ],
    );

    testWidgets('scrolls instead of overflowing the sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lumenTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: LumenBottomSheet(child: tallContent()),
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'A RenderFlex overflow here is the bug this test exists for.',
      );

      final sheet = tester.getRect(find.byType(LumenBottomSheet));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;

      // `SingleChildScrollView` builds its whole child, so `findsNothing` on
      // the last row would be wrong AND would pass on an unscrollable Column.
      // What actually distinguishes the two is that there is somewhere to
      // scroll TO, and that the last row starts out beyond the sheet.
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason:
            'content is 1200 px tall in a 600 px viewport — a sheet with no '
            'scroll view reports 0 here (and overflows instead).',
      );
      expect(
        tester.getRect(find.text('row 19')).top,
        greaterThan(sheet.bottom),
        reason: 'the last row starts below the sheet, out of sight',
      );

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.text('row 19')).bottom,
        lessThanOrEqualTo(sheet.bottom),
        reason: 'the bottom of a long form must be reachable by scrolling',
      );
    });

    testWidgets('still hugs SHORT content rather than filling the viewport', (
      tester,
    ) async {
      // The other half of the same decision: `Expanded` would also stop the
      // overflow, and would stretch screen 9's four-line sheet to full height.
      await _openSheet(tester);

      final sheet = tester.getRect(find.byType(LumenBottomSheet));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(sheet.height, lessThan(screen.height / 2));
    });

    testWidgets('a tall form does not overflow with the keyboard up either', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lumenTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 667),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: LumenBottomSheet(child: tallContent()),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Keyboard
  // -------------------------------------------------------------------------

  testWidgets('lifts its content clear of the on-screen keyboard', (
    tester,
  ) async {
    // "Every modal-with-input in P4b uses this sheet" — so a sheet that let
    // the keyboard cover its own text field would be wrong thirteen times.
    // Deliberately NOT inside a Scaffold: `Scaffold` strips the bottom
    // viewInsets from its body's MediaQuery (that is what
    // `resizeToAvoidBottomInset` does). A modal bottom sheet is a separate
    // route ABOVE the Scaffold, so it sees the real insets — and a test that
    // wrapped one in a Scaffold would measure zero and prove nothing.
    await tester.pumpWidget(
      MaterialApp(
        theme: lumenTheme(Brightness.light),
        home: const MediaQuery(
          data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
          child: LumenBottomSheet(child: Text('body')),
        ),
      ),
    );

    expect(
      _sheetBox(tester).padding,
      const EdgeInsets.fromLTRB(22, 18, 22, 326),
      reason: '26 of designed bottom padding plus the 300 the keyboard takes.',
    );
  });
}
