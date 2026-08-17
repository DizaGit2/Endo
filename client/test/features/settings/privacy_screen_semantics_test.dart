// Semantics tests — PrivacyScreen (P3c-T13, house a11y pattern).
//
// PrivacyScreen is static (no API/state) but every row visually resembles a
// settings control. None of them has a wired onTap today (the toggles are
// explicitly documented as "visual-only" in _MiniToggle, and the nav rows have
// no destination screen yet) — so rows get MergeSemantics (read label +
// subtitle/value as one unit) rather than fabricated button semantics. See
// profile_screen_semantics_test.dart's doc comment for the same reasoning
// applied to the user-card row.

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
    'Delete all data row is informational (not exposed as a button — no '
    'destination screen exists yet)',
    (tester) async {
      await _pump(tester);

      expectNotAButton(tester, find.text('Delete all data'));
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
