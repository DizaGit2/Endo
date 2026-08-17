// Accessibility tests for LumenSectionLabel (P4b-T5b).
//
// The widget uppercases its text with CSS-equivalent letter-spacing, and both
// of those are accessibility-relevant: what a screen reader announces is the
// UPPERCASED string, not the sentence-case one the caller wrote. That is worth
// pinning rather than assuming, because it is the argument for uppercasing in
// CSS (`text-transform`, which leaves the accessible text alone) rather than in
// Dart (`toUpperCase()`, which does not).
//
// It is also the widget most likely to be mistaken for a heading. It is not one
// today — see the last test, which records that rather than asserting it is
// fine.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

import '../support/harness.dart';

Future<void> _pumpLabel(WidgetTester tester, {String text = 'App lock'}) =>
    pumpApp(
      tester,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LumenSectionLabel(text),
              const SizedBox(height: 6),
              const Text('Require a passcode to open Lumen'),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgetsWithSemantics('announces the uppercased text it renders', (
    tester,
  ) async {
    await _pumpLabel(tester);

    // The rendered string IS the announced string — there is no separate
    // semanticsLabel keeping the sentence-case original.
    expect(find.bySemanticsLabel('APP LOCK'), findsOneWidget);
    expect(find.bySemanticsLabel('App lock'), findsNothing);
  });

  testWidgetsWithSemantics('is not announced as a button', (tester) async {
    // Section labels sit directly above tappable rows, which is exactly where
    // a stray `Semantics(button: true)` would send a screen-reader user
    // double-tapping a caption.
    await _pumpLabel(tester);

    expectNotAButton(tester, find.byType(LumenSectionLabel));
  });

  testWidgetsWithSemantics('carries no header flag — recorded, not endorsed', (
    tester,
  ) async {
    // A section label is what a heading-navigation gesture SHOULD land on, and
    // this one is not flagged as a header, so that gesture skips it. Changing
    // that is a behaviour change to a promoted widget and belongs to whoever
    // owns the settings screens' structure, not to the registry task — but it
    // is pinned here so the change is deliberate and this test goes red on the
    // day someone makes it.
    await _pumpLabel(tester);

    expect(
      tester
          .getSemantics(find.byType(LumenSectionLabel))
          .flagsCollection
          .isHeader,
      isFalse,
      reason:
          'If you have just made LumenSectionLabel a header, that is an '
          'improvement — delete this test and say so.',
    );
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpLabel(tester);

    expectNoDingbats(tester, screen: 'LumenSectionLabel');
  });
}
