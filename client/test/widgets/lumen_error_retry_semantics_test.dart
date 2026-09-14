// Accessibility tests for LumenErrorRetry (P4b-T5b).
//
// This is what a screen renders when it has nothing else to show, so it is the
// only thing on the surface: if it does not announce, the screen is silent. Two
// halves, and they fail independently — the message must be a live region, and
// the affordance beside it must be a real, named, activatable button.
//
// The live-region assertion moved here from `lumen_error_retry_test.dart` when
// the widget registry started requiring a semantics test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';

import '../support/harness.dart';

const _message = 'Something went wrong. Please try again.';

Future<void> _pumpSurface(WidgetTester tester, {VoidCallback? onRetry}) =>
    pumpApp(
      tester,
      home: Scaffold(
        body: LumenErrorRetry(message: _message, onRetry: onRetry ?? () {}),
      ),
    );

void main() {
  testWidgetsWithSemantics('the message announces itself as a live region', (
    tester,
  ) async {
    await _pumpSurface(tester);

    expectLiveRegion(tester, _message);
  });

  testWidgetsWithSemantics('the retry is a named, activatable button', (
    tester,
  ) async {
    await _pumpSurface(tester);

    expectLabeledButton(
      tester,
      find.text(LumenErrorRetry.retryLabel),
      LumenErrorRetry.retryLabel,
      exactLabel: true,
    );
  });

  testWidgetsWithSemantics('the announcement is the message, not the button', (
    tester,
  ) async {
    // The failure text and the affordance are separate nodes. If the message
    // merged into the button, a screen reader would announce two sentences as
    // one control name and the live region would be attached to a button.
    await _pumpSurface(tester);

    final button = tester.getSemantics(find.text(LumenErrorRetry.retryLabel));
    expect(button.label, isNot(contains('Something went wrong')));
    expect(
      button.flagsCollection.isLiveRegion,
      isFalse,
      reason:
          'The live region is the message. A button that is also a live region '
          'announces itself every time the surface rebuilds.',
    );
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpSurface(tester);

    expectNoDingbats(tester, screen: 'LumenErrorRetry');
  });
}
