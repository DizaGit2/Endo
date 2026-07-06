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
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';

Widget _wrap() => MaterialApp(
  theme: lumenTheme(Brightness.light),
  home: const PrivacyScreen(),
);

void main() {
  testWidgets('Face ID row merges label + subtitle into one unit', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final data = tester.getSemantics(find.text('Face ID'));
    expect(data.label, contains('Face ID'));
    expect(data.label, contains('Required to open'));
    expect(data.flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  testWidgets('Encryption status row merges label + value into one unit', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final data = tester.getSemantics(find.text('Encryption status'));
    expect(data.label, contains('Encryption status'));
    expect(data.label, contains('AES-256'));
    handle.dispose();
  });

  testWidgets(
    'Delete all data row is informational (not exposed as a button — no '
    'destination screen exists yet)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final data = tester.getSemantics(find.text('Delete all data'));
      expect(data.flagsCollection.isButton, isFalse);
      handle.dispose();
    },
  );

  testWidgets('Warrant-canary notice text remains fully readable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp('Lumen has never received a data request')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Dingbat glyphs are replaced by real Icons', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_right), findsOneWidget); // Delete all data
    expect(find.byIcon(Icons.check), findsOneWidget); // AES-256 ✓
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget); // ✦ warrant canary
  });
}
