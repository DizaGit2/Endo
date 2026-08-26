// Accessibility tests for LumenRetryButton (P4b-T5b).
//
// This is the app's one secondary affordance, and it is the affordance that
// appears exactly when something has already gone wrong. Two properties have to
// hold: it announces as a button WITH a tap action assistive tech can invoke
// (`Semantics(excludeSemantics: true)` around a GestureDetector silently drops
// that action, which is the failure `expectLabeledButton` was written for), and
// its accessible name is exactly its label — nothing merged in.
//
// The labelled-button assertion moved here from `lumen_retry_button_test.dart`
// when the widget registry started requiring a semantics test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_retry_button.dart';

import '../support/harness.dart';

Future<void> _pumpButton(WidgetTester tester, {String label = 'Try again'}) =>
    pumpApp(
      tester,
      home: Scaffold(
        body: Center(
          child: LumenRetryButton(label: label, onPressed: () {}),
        ),
      ),
    );

void main() {
  testWidgetsWithSemantics('announces as a labelled, activatable button', (
    tester,
  ) async {
    await _pumpButton(tester);

    expectLabeledButton(
      tester,
      find.text('Try again'),
      'Try again',
      exactLabel: true,
    );
  });

  testWidgetsWithSemantics('the other shipped label announces as itself', (
    tester,
  ) async {
    // Screen 31's network-required body says 'Retry'. Pinned exactly, so a
    // spinner or badge merging into the name is a failure rather than a
    // containment that still passes.
    await _pumpButton(tester, label: 'Retry');

    expectLabeledButton(tester, find.text('Retry'), 'Retry', exactLabel: true);
  });

  testWidgetsWithSemantics('the tap action assistive tech invokes runs the '
      'callback', (tester) async {
    // `expectLabeledButton` proves the ACTION is advertised. This proves the
    // advertisement is honest: performing it from the semantics tree — which is
    // what a screen reader's double-tap does — reaches onPressed.
    var taps = 0;
    await pumpApp(
      tester,
      home: Scaffold(
        body: Center(
          child: LumenRetryButton(label: 'Try again', onPressed: () => taps++),
        ),
      ),
    );

    // `tester.semantics.tap` performs the SemanticsAction, not a pointer
    // gesture — a button whose visual hit target works but whose semantics
    // action was dropped stays green under `tester.tap` and red here.
    tester.semantics.tap(find.semantics.byLabel('Try again'));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpButton(tester);

    expectNoDingbats(tester, screen: 'LumenRetryButton');
  });
}
