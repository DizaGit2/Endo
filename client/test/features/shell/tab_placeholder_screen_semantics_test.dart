// Semantics test — the shared tab placeholder (P4b-T2, house a11y pattern).
//
// TDD (RED first). Ruling R-10: the five-tab bottom nav is a design constant,
// so the tabs render even where the feature does not exist yet — but the
// destination must say so plainly, with no date and no promise, and it must
// NOT offer an affordance that goes nowhere. Both halves are asserted here:
// the copy is announced verbatim, and the screen exposes no button at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/shell/presentation/tab_placeholder_screen.dart';

import '../../support/harness.dart';

Future<void> _pump(WidgetTester tester, String heading) =>
    pumpApp(tester, home: TabPlaceholderScreen(heading: heading));

void main() {
  testWidgetsWithSemantics('the heading is exposed as a header', (
    tester,
  ) async {
    await _pump(tester, 'Hormones aren\'t here yet');

    final data = tester.getSemantics(find.text('Hormones aren\'t here yet'));
    expect(
      data.flagsCollection.isHeader,
      isTrue,
      reason:
          'the heading is the whole point of this screen — a screen-reader '
          'user must be able to jump straight to it.',
    );
  });

  testWidgetsWithSemantics('the body copy is announced verbatim', (
    tester,
  ) async {
    await _pump(tester, 'Body tracking isn\'t here yet');

    expect(find.text('Body tracking isn\'t here yet'), findsOneWidget);
    expect(
      find.bySemanticsLabel('This part of Lumen arrives in a later release.'),
      findsOneWidget,
    );
  });

  testWidgets('the copy makes no promise and names no date', (tester) async {
    await _pump(tester, 'More isn\'t here yet');

    expect(find.textContaining('soon'), findsNothing);
    expect(find.textContaining('2026'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgetsWithSemantics(
    'the placeholder offers no affordance that goes nowhere',
    (tester) async {
      await _pump(tester, 'More isn\'t here yet');

      expectNoButtons(
        tester,
        reason:
            'R-10: a navigational affordance pointing at nothing is dishonest. '
            'The placeholder states the absence; it must not invite a tap.',
      );
    },
  );

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pump(tester, 'More isn\'t here yet');

    expectNoDingbats(tester, screen: 'TabPlaceholderScreen');
  });
}
