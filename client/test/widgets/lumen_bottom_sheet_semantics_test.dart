// Accessibility tests for LumenBottomSheet (P4b-T5, brief §2).
//
// A modal sheet's a11y contract is mostly about what it does NOT do: it must
// not announce its own decoration, and it must not trap a screen-reader user
// behind content they cannot dismiss. Both are asserted here, because both are
// silently broken by a plausible implementation (a grab handle built as a
// tappable drag target announces "button, 32 by 3"; `isDismissible: false`
// without an in-sheet close affordance is a trap).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';

import '../support/harness.dart';

Future<void> _openSheet(
  WidgetTester tester, {
  Widget content = const Text('How\'s today?'),
}) async {
  await pumpApp(
    tester,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showLumenBottomSheet<void>(
              context: context,
              builder: (_) => content,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgetsWithSemantics('the sheet\'s content is announced', (tester) async {
    await _openSheet(tester);

    expect(find.bySemanticsLabel('How\'s today?'), findsOneWidget);
  });

  testWidgetsWithSemantics('the grab handle announces nothing', (tester) async {
    await _openSheet(tester);

    // The handle is a drag affordance for a gesture assistive tech does not
    // make; the barrier below is how a screen-reader user dismisses the sheet.
    // A node for it would be a 32x3 rectangle in the reading order with
    // nothing to say.
    final labels = tester.semantics
        .find(find.byType(LumenBottomSheet))
        .getSemanticsData()
        .label;
    expect(labels, isNot(contains('handle')));
    expect(
      find.descendant(
        of: find.byType(LumenBottomSheet),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgetsWithSemantics('the sheet content keeps its own controls', (
    tester,
  ) async {
    await _openSheet(
      tester,
      content: Builder(
        builder: (context) => FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Save check-in'),
        ),
      ),
    );

    expectLabeledButton(
      tester,
      find.text('Save check-in'),
      'Save check-in',
      exactLabel: true,
    );
  });

  testWidgetsWithSemantics('the scrim is a dismiss affordance, and is labelled', (
    tester,
  ) async {
    await _openSheet(tester);

    // A dismissible sheet must be escapable without a drag: the modal barrier
    // carries the platform's "Dismiss"/"Scrim" semantics label and a tap
    // action, which is what an assistive technology activates.
    final barrier = tester.widget<ModalBarrier>(
      find
          .byWidgetPredicate((w) => w is ModalBarrier && w.dismissible)
          .first,
    );
    expect(barrier.semanticsLabel, isNotNull);
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _openSheet(tester);

    expectNoDingbats(tester, screen: 'LumenBottomSheet');
  });
}
