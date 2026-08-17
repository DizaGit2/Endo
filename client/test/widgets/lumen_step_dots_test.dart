// Tests for LumenStepDots — the promoted `_StepDot` (P4b-T5).
//
// TDD (RED first): `_StepDot` existed TWICE, verbatim, in `welcome_screen.dart`
// and `account_screen.dart`, and each call site also hand-rolled the same
// centred Row with the same 6 px gaps. Screens 3-7 need that row five more
// times, so what is promoted is the ROW (`LumenStepDots`) with the dot as its
// private implementation detail — promoting only the dot would have left five
// copies of the row behind, which is the duplication this task exists to kill.
//
// The geometry assertions are the fidelity guard: screens 1 and 2 have
// committed goldens that must pass unmodified.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';
import 'package:lumen/shared/widgets/lumen_step_dots.dart';

import '../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pumpDots(
  WidgetTester tester, {
  int count = 7,
  required int activeIndex,
  Brightness brightness = Brightness.light,
}) {
  return pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: Center(
        child: LumenStepDots(count: count, activeIndex: activeIndex),
      ),
    ),
  );
}

List<AnimatedContainer> _dots(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(LumenStepDots),
        matching: find.byType(AnimatedContainer),
      ),
    )
    .toList();

Color _dotColor(AnimatedContainer dot) =>
    (dot.decoration! as BoxDecoration).color!;

/// [AnimatedContainer] folds `width`/`height` into tight [BoxConstraints], so
/// the geometry has to be read back off those rather than off the fields.
double _dotWidth(AnimatedContainer dot) => dot.constraints!.maxWidth;

double _dotHeight(AnimatedContainer dot) => dot.constraints!.maxHeight;

void main() {
  // -------------------------------------------------------------------------
  // Geometry — verbatim from the two private copies
  // -------------------------------------------------------------------------

  testWidgets('renders exactly `count` dots', (tester) async {
    await _pumpDots(tester, count: 7, activeIndex: 0);

    expect(_dots(tester), hasLength(7));
  });

  testWidgets('the active dot is an 18x6 accent pill', (tester) async {
    await _pumpDots(tester, activeIndex: 3);
    final dots = _dots(tester);

    expect(_dotWidth(dots[3]), 18);
    expect(_dotHeight(dots[3]), 6);
    expect(_dotColor(dots[3]), lumenLight.accent);
    expect(
      (dots[3].decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(3),
    );
  });

  testWidgets('every other dot is a 6x6 border-coloured circle', (tester) async {
    await _pumpDots(tester, activeIndex: 3);
    final dots = _dots(tester);

    for (var i = 0; i < dots.length; i++) {
      if (i == 3) continue;
      expect(_dotWidth(dots[i]), 6, reason: 'dot $i should be inactive');
      expect(_dotHeight(dots[i]), 6);
      expect(_dotColor(dots[i]), lumenLight.border);
      expect(
        (dots[i].decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(50),
      );
    }
  });

  testWidgets('activeIndex selects WHICH dot is the pill', (tester) async {
    // The assertion that fails if the row hard-codes `i == 0` (or ignores
    // activeIndex): every index in turn, and only that one, is wide.
    for (var active = 0; active < 7; active++) {
      await _pumpDots(tester, activeIndex: active);
      final widths = _dots(tester).map(_dotWidth).toList();

      expect(
        widths,
        List<double>.generate(7, (i) => i == active ? 18 : 6),
        reason: 'activeIndex: $active',
      );
    }
  });

  testWidgets('dots are separated by 6 px and centred', (tester) async {
    await _pumpDots(tester, count: 3, activeIndex: 0);

    final gaps = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(LumenStepDots),
            matching: find.byType(SizedBox),
          ),
        )
        .where((box) => box.width == 6)
        .toList();
    expect(gaps, hasLength(2), reason: 'n dots => n-1 gaps');

    final row = tester.widget<Row>(
      find.descendant(
        of: find.byType(LumenStepDots),
        matching: find.byType(Row),
      ),
    );
    expect(row.mainAxisAlignment, MainAxisAlignment.center);
  });

  testWidgets('animates the transition over 200 ms, as the copies did', (
    tester,
  ) async {
    await _pumpDots(tester, activeIndex: 0);

    expect(
      _dots(tester).first.duration,
      const Duration(milliseconds: 200),
    );
  });

  testWidgets('takes its colours from the dark palette in dark mode', (
    tester,
  ) async {
    await _pumpDots(tester, activeIndex: 1, brightness: Brightness.dark);
    final dots = _dots(tester);

    expect(_dotColor(dots[1]), lumenDark.accent);
    expect(_dotColor(dots[0]), lumenDark.border);
  });

  // -------------------------------------------------------------------------
  // Both former copies really are collapsed onto this widget
  // -------------------------------------------------------------------------
  //
  // Without these two, the promotion could ship alongside the private copies
  // and every assertion above would still pass.

  testWidgets('screen 1 renders the shared row, on step 1 of 7', (tester) async {
    await pumpApp(tester, home: const WelcomeScreen());

    expect(find.byType(LumenStepDots), findsOneWidget);
    final dots = tester.widget<LumenStepDots>(find.byType(LumenStepDots));
    expect(dots.count, 7);
    expect(dots.activeIndex, 0);
  });

  testWidgets('screen 2 renders the shared row, on step 2 of 7', (tester) async {
    await pumpApp(
      tester,
      home: const AccountScreen(),
      overrides: lumenOverrides(),
    );

    expect(find.byType(LumenStepDots), findsOneWidget);
    final dots = tester.widget<LumenStepDots>(find.byType(LumenStepDots));
    expect(dots.count, 7);
    expect(dots.activeIndex, 1);
  });
}
