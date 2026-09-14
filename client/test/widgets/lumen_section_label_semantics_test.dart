// Accessibility tests for LumenSectionLabel (P4b-T5b; B-12 fixed at the PR #4
// review hand-back).
//
// The widget uppercases its text with CSS-equivalent letter-spacing, and that
// is a presentation choice — what a screen reader announces must stay the
// sentence-case string the caller wrote. An all-caps run is spelled out letter
// by letter by many screen readers ("D, A, T, A"), which is the argument for
// uppercasing in CSS (`text-transform`, which leaves the accessible text alone)
// rather than in Dart (`toUpperCase()`, which does not). `LumenFieldLabel`
// already draws and announces different strings for exactly this reason; this
// widget now does the same.
//
// It is also the widget a heading-navigation gesture should land on: a section
// label is what a section IS called, so it carries the header flag. Until B-12
// the last test here recorded the flag's absence "rather than endorsing it";
// it now asserts its presence.

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
  testWidgetsWithSemantics('announces the sentence-case text, not the '
      'uppercased rendering', (tester) async {
    await _pumpLabel(tester);

    expect(find.bySemanticsLabel('App lock'), findsOneWidget);
    expect(
      find.bySemanticsLabel('APP LOCK'),
      findsNothing,
      reason:
          'the uppercased string is for the eyes only — announced, it is '
          'spelled out letter by letter (B-12)',
    );
  });

  testWidgets('still DRAWS the uppercased text — the fix is to the announced '
      'string, not the painted one', (tester) async {
    await _pumpLabel(tester);

    expect(find.text('APP LOCK'), findsOneWidget);
    expect(find.text('App lock'), findsNothing);
  });

  testWidgetsWithSemantics('is not announced as a button', (tester) async {
    // Section labels sit directly above tappable rows, which is exactly where
    // a stray `Semantics(button: true)` would send a screen-reader user
    // double-tapping a caption.
    await _pumpLabel(tester);

    expectNotAButton(tester, find.byType(LumenSectionLabel));
  });

  testWidgetsWithSemantics('carries the header flag, so heading navigation '
      'lands on it', (tester) async {
    await _pumpLabel(tester);

    expect(
      tester
          .getSemantics(find.byType(LumenSectionLabel))
          .flagsCollection
          .isHeader,
      isTrue,
      reason:
          'a section label is what a section is called; a heading-navigation '
          'gesture that skips it has nothing else to land on',
    );
  });

  testWidgetsWithSemantics('exposes exactly ONE node — the drawn Text does not '
      'leak a second, uppercased announcement under the header',
      (tester) async {
    await _pumpLabel(tester);

    final node = tester.getSemantics(find.byType(LumenSectionLabel));
    expect(node.label, 'App lock');
    expect(
      find.descendant(
        of: find.byType(LumenSectionLabel),
        matching: find.bySemanticsLabel('APP LOCK'),
      ),
      findsNothing,
    );
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpLabel(tester);

    expectNoDingbats(tester, screen: 'LumenSectionLabel');
  });
}
