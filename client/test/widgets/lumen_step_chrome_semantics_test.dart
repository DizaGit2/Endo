// Accessibility tests for LumenStepChrome (P4b-T8).
//
// This widget exists BECAUSE of these assertions. P4b-T5b recorded the
// deficiency it closes: `LumenStepDots` is decoration and announces nothing
// (correctly — it is seven coloured boxes), so a screen-reader user learned
// neither where they were in onboarding nor how much remained. The eyebrow is
// the only other place that information is on screen, and it was drawn through
// `LumenSectionLabel`, which UPPERCASES its text — so even where the string was
// in the tree, what reached assistive tech was "STEP 3 OF 7 · CYCLE": an
// all-caps run many screen readers spell out letter by letter, punctuated by a
// middle dot read as noise.
//
// So the chrome renders the uppercased string and ANNOUNCES a sentence-case
// one. The pair of assertions below is the whole contract, and neither half
// stands alone: "the sentence-case label is announced" is satisfied by a widget
// that also announces the shouted one, and "the shouted one is not announced"
// is satisfied by a widget that renders nothing at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_step_chrome.dart';

import '../support/harness.dart';

Future<void> _pumpChrome(
  WidgetTester tester, {
  String? title = 'Cycle',
  int step = 3,
  String? lead,
}) => pumpApp(
  tester,
  home: Scaffold(
    body: LumenStepChrome(step: step, totalSteps: 7, title: title, lead: lead),
  ),
);

void main() {
  testWidgetsWithSemantics(
    'the step position is announced in sentence case, not as the shouted '
    'eyebrow',
    (tester) async {
      await _pumpChrome(tester);

      // Positive control FIRST: the uppercased string really is in the tree, so
      // the `findsNothing` below is a fact about the SEMANTICS rather than
      // about a widget that failed to render.
      expect(
        find.text('STEP 3 OF 7 · CYCLE'),
        findsOneWidget,
        reason: 'premise: the eyebrow is drawn uppercased',
      );

      expect(find.bySemanticsLabel('Step 3 of 7, Cycle'), findsOneWidget);
      expect(
        find.bySemanticsLabel('STEP 3 OF 7 · CYCLE'),
        findsNothing,
        reason:
            'An all-caps eyebrow with a middle dot in it is what a screen '
            'reader would otherwise read out. The visible text must be '
            'excluded from semantics, not merely accompanied by a better '
            'label.',
      );
    },
  );

  testWidgetsWithSemantics('the eyebrow is a header, so heading navigation '
      'lands on it', (tester) async {
    await _pumpChrome(tester);

    final data = tester.semantics
        .find(find.byType(LumenStepChrome))
        .getSemanticsData();

    expect(
      data.flagsCollection.isHeader,
      isTrue,
      reason:
          'The eyebrow is the first thing on every onboarding screen and it is '
          'what a heading gesture should reach. Without the flag the only way '
          'to find out which step you are on is to swipe from the top.',
    );
    expect(
      data.flagsCollection.isButton,
      isFalse,
      reason:
          'Nothing in the chrome is tappable; announcing a button would be a '
          'promise it cannot keep.',
    );
  });

  testWidgetsWithSemantics(
    'a screen with no title still announces its position',
    (tester) async {
      // Screen 2's eyebrow is "Step 2 of 7" — no title after the dot. The
      // announcement must not grow a trailing comma or the word "null".
      await _pumpChrome(tester, step: 2, title: null);

      expect(find.bySemanticsLabel('Step 2 of 7'), findsOneWidget);
    },
  );

  testWidgetsWithSemantics('a lead word is announced too, not just drawn', (
    tester,
  ) async {
    // Screen 1 prints "Lumen · 1 of 7", and "Lumen" appears in no other Text on
    // that screen — so an eyebrow that excluded its own visible string without
    // carrying the word into the label would delete the product's name from
    // everything a screen reader ever hears there.
    await _pumpChrome(tester, step: 1, title: null, lead: 'Lumen');

    expect(
      find.text('LUMEN · 1 OF 7'),
      findsOneWidget,
      reason: 'premise: the mockup copy is unchanged',
    );
    expect(find.bySemanticsLabel('Lumen, step 1 of 7'), findsOneWidget);
    expect(find.bySemanticsLabel('LUMEN · 1 OF 7'), findsNothing);
    expect(
      find.bySemanticsLabel('Step 1 of 7'),
      findsNothing,
      reason:
          'The bare position is what this screen announced before the lead was '
          'carried through. Asserting the lead-carrying label alone would also '
          'pass with BOTH in the tree, which is the doubled announcement worth '
          'avoiding.',
    );
  });

  testWidgets('the eyebrow renders no dingbat glyphs', (tester) async {
    await _pumpChrome(tester);

    expectNoDingbats(tester, screen: 'LumenStepChrome');
  });
}
