// Accessibility tests for LumenStepDots (P4b-T5b).
//
// The row is pure decoration: seven coloured boxes, no text, no gestures. Two
// things follow, and both are assertions rather than observations.
//
//   1. It must announce NOTHING — no node, no label, and above all no button.
//      Seven unlabelled nodes in the reading order between the heading and the
//      first field is a swipe-through cost paid on every onboarding screen.
//   2. Because it announces nothing, the progress it shows visually
//      ("step 2 of 7") reaches a screen-reader user only if the SCREEN says so.
//      Screens 1 and 2 do not say it today, and that gap is recorded where the
//      person who fixes onboarding will actually be reading:
//      `test/features/onboarding/welcome_screen_semantics_test.dart`.
//
// `expectNoDingbats` is deliberately not used here — it fails a tree with no
// `Text` in it, which for a screen means the harness never mounted anything and
// for this widget is simply the truth. That asymmetry is why the widget rule's
// semantics gate asks for any `a11y_guard.dart` matcher rather than that one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_step_dots.dart';

import '../support/harness.dart';

Future<void> _pumpDots(WidgetTester tester, {int activeIndex = 1}) => pumpApp(
  tester,
  home: Scaffold(
    body: Center(child: LumenStepDots(count: 7, activeIndex: activeIndex)),
  ),
);

void main() {
  testWidgetsWithSemantics('the dots offer no affordance', (tester) async {
    // A dot rendered as a tappable-looking node is a promise the row cannot
    // keep: nothing is wired to it and the flow is linear.
    await _pumpDots(tester);

    expectNoButtons(
      tester,
      reason: 'The step indicator is decoration; nothing in it is tappable.',
    );
  });

  testWidgetsWithSemantics('the dots contribute no semantics node at all', (
    tester,
  ) async {
    await _pumpDots(tester);

    final labels = tester.semantics
        .find(find.byType(LumenStepDots))
        .getSemanticsData()
        .label;
    expect(
      labels,
      isEmpty,
      reason:
          'Seven decorative boxes must not put anything into the reading '
          'order. If the row has just gained a real announcement (e.g. '
          '"Step 2 of 7"), that is an improvement — replace this test with one '
          'asserting the announcement.',
    );
  });
}
