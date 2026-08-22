// Semantics tests — PrivacyScreen (P3c-T13, house a11y pattern).
//
// Most rows on this screen visually resemble a settings control while having
// nothing wired behind them (the toggles are documented as "visual-only" in
// `_MiniToggle`) — those get MergeSemantics, reading label + subtitle/value as
// one unit, rather than fabricated button semantics. See
// profile_screen_semantics_test.dart's doc comment for the same reasoning
// applied to the user-card row.
//
// **Two of them are no longer in that class, as of P4b-T22c**, and the
// distinction is the whole point of the rule rather than an exception to it:
// the danger-zone row now invokes `DELETE /me`, and the back chevron now pops
// a real route. Both therefore announce themselves as buttons — a control with
// an action behind it SHOULD. The erasure behaviour they lead to is pinned in
// `privacy_screen_erasure_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';

import '../../support/harness.dart';

Future<void> _pump(WidgetTester tester) =>
    pumpApp(tester, home: const PrivacyScreen());

void main() {
  testWidgetsWithSemantics(
    'Face ID row merges label + subtitle into one unit',
    (tester) async {
      await _pump(tester);

      expectNotAButton(
        tester,
        find.text('Face ID'),
        merged: const ['Face ID', 'Required to open'],
      );
    },
  );

  testWidgetsWithSemantics(
    'Encryption status row merges label + value into one unit',
    (tester) async {
      await _pump(tester);

      final data = tester.getSemantics(find.text('Encryption status'));
      expect(data.label, contains('Encryption status'));
      expect(data.label, contains('AES-256'));
    },
  );

  testWidgetsWithSemantics(
    'Delete all data row IS a button now — it has an action behind it '
    '(P4b-T22c wired DELETE /me), so announcing one is honest',
    (tester) async {
      await _pump(tester);

      expectLabeledButton(
        tester,
        find.text(kPrivacyDeleteRowLabel),
        kPrivacyDeleteRowLabel,
      );
    },
  );

  testWidgetsWithSemantics(
    'the back chevron announces itself with the platform\'s own name for the '
    'control — screen 36 is a pushed route since P4b-T22c, so there is '
    'something to go back TO',
    (tester) async {
      await _pump(tester);

      final back = MaterialLocalizations.of(
        tester.element(find.byType(PrivacyScreen)),
      ).backButtonTooltip;
      expectLabeledButton(tester, find.bySemanticsLabel(back), back);
    },
  );

  testWidgetsWithSemantics(
    'Warrant-canary notice text remains fully readable',
    (tester) async {
      await _pump(tester);

      expect(
        find.bySemanticsLabel(
          RegExp('Lumen has never received a data request'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Dingbat glyphs are replaced by real Icons', (tester) async {
    await _pump(tester);

    expectNoDingbats(tester, screen: 'PrivacyScreen');
    expect(find.byIcon(Icons.chevron_right), findsOneWidget); // Delete all data
    expect(find.byIcon(Icons.check), findsOneWidget); // AES-256 ✓
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget); // ✦ warrant canary
  });
}
