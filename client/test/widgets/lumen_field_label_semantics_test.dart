// Accessibility tests for LumenFieldLabel (P4b-T5c).
//
// This widget exists in two behaviours, and the promotion's whole risk is that
// one of them quietly becomes the other:
//
//   * `announce: true` (the default, and screen 3's every call site) — the
//     label is a node of its own, announced in SENTENCE case even though the
//     run on screen is uppercased. An all-caps run is spelled out letter by
//     letter by many screen readers, which is why what is drawn and what is
//     announced are deliberately different strings.
//   * `announce: false` (screen 4's date-of-birth, height and weight labels) —
//     drawn, and silent, because the CONTROL beneath already carries the same
//     name. A second, unassociated "Height" immediately before the field that
//     is called Height is noise in the reading order.
//
// The second test below holds both in ONE tree so neither can be a broken
// mount.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';

import '../support/harness.dart';

Future<void> _pumpLabel(
  WidgetTester tester, {
  String text = 'Average cycle length',
}) => pumpApp(tester, home: Scaffold(body: LumenFieldLabel(text)));

void main() {
  testWidgetsWithSemantics(
    'announces the sentence case it was given, not the run it draws',
    (tester) async {
      await _pumpLabel(tester);

      // Control for both assertions below: the shouted run IS on screen, so
      // what follows is about the semantics rather than about a label that
      // never built.
      expect(find.text('AVERAGE CYCLE LENGTH'), findsOneWidget);

      expect(find.bySemanticsLabel('Average cycle length'), findsOneWidget);
      expect(find.bySemanticsLabel('AVERAGE CYCLE LENGTH'), findsNothing);
    },
  );

  testWidgetsWithSemantics(
    'announce: false is drawn and silent, beside a default that is announced',
    (tester) async {
      // Both variants, one pump, one harness — so the silent label's absence
      // from the semantics tree cannot be an empty tree, and the announced
      // one's presence proves the tree is there to be read. Screen 4 renders
      // exactly this mix.
      await pumpApp(
        tester,
        home: const Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LumenFieldLabel('Endometriosis status'),
              LumenFieldLabel('Height', announce: false),
            ],
          ),
        ),
      );

      // Both are drawn.
      expect(find.text('ENDOMETRIOSIS STATUS'), findsOneWidget);
      expect(find.text('HEIGHT'), findsOneWidget);

      // Only the default one is announced.
      expect(find.bySemanticsLabel('Endometriosis status'), findsOneWidget);
      expect(find.bySemanticsLabel('Height'), findsNothing);
      expect(find.bySemanticsLabel('HEIGHT'), findsNothing);
    },
  );

  testWidgetsWithSemantics('is not announced as a button', (tester) async {
    // Field labels sit directly above tappable chips, option rows and a date
    // box, which is exactly where a stray `Semantics(button: true)` would send
    // a screen-reader user double-tapping a caption.
    await _pumpLabel(tester);

    expectNotAButton(tester, find.byType(LumenFieldLabel));
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpLabel(tester);

    expectNoDingbats(tester, screen: 'LumenFieldLabel');
  });
}
