// Accessibility tests for LumenFieldMessage (P4b-T5c).
//
// A rejection a screen reader cannot reach is a form that cannot be corrected,
// so the one thing this widget must never become is silent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';

import '../support/harness.dart';

const _message = 'date is before the earliest allowed date';

Future<void> _pumpMessage(WidgetTester tester) => pumpApp(
  tester,
  home: const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(16),
      child: LumenFieldMessage(_message),
    ),
  ),
);

void main() {
  testWidgetsWithSemantics('announces the message it draws', (tester) async {
    await _pumpMessage(tester);

    // Control: the message IS drawn. The assertion that follows is the one
    // that discriminates — an `ExcludeSemantics` wrapper would keep this first
    // expectation green and kill the second.
    expect(find.text(_message), findsOneWidget);

    expect(find.bySemanticsLabel(_message), findsOneWidget);
  });

  testWidgetsWithSemantics('is not announced as a button', (tester) async {
    // It sits under a field the user is about to correct; announcing it as a
    // button would offer an activation there is nothing behind.
    await _pumpMessage(tester);

    expectNotAButton(tester, find.byType(LumenFieldMessage));
  });

  testWidgetsWithSemantics('is not a live region — recorded, not endorsed', (
    tester,
  ) async {
    // Screens 3 and 4 render this beside a LumenErrorBanner, which IS a live
    // region, so a rejection is already announced once when it arrives; this
    // node is what the user then swipes onto, field by field.
    await _pumpMessage(tester);

    expect(
      tester
          .getSemantics(find.byType(LumenFieldMessage))
          .flagsCollection
          .isLiveRegion,
      isFalse,
      reason:
          'If you have just made LumenFieldMessage a live region, check what a '
          'multi-field rejection then announces — screens 3 and 4 can render '
          'three of these at once, under a banner that already announces. '
          'Then delete this test and say so.',
    );
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpMessage(tester);

    expectNoDingbats(tester, screen: 'LumenFieldMessage');
  });
}
