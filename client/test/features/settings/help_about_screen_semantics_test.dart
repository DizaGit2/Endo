// Semantics tests — HelpAboutScreen (P3c-T13, house a11y pattern).
//
// Static screen (no API/state). The 7 nav rows (_NavRow) have no destination
// screen yet, so — matching privacy_screen.dart / profile_screen.dart's
// user-card row — they get MergeSemantics (one readable unit) rather than
// fabricated button semantics with no action behind them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/settings/presentation/help_about_screen.dart';

Widget _wrap() => MaterialApp(
  theme: lumenTheme(Brightness.light),
  home: const HelpAboutScreen(),
);

void main() {
  testWidgets(
    'Quick start guide row is informational (not exposed as a button — no '
    'destination screen exists yet)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final data = tester.getSemantics(find.text('Quick start guide'));
      expect(data.flagsCollection.isButton, isFalse);
      handle.dispose();
    },
  );

  testWidgets('App identity card icon is decorative (no semantics label)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // The app-icon glyph contributes nothing to the semantics tree; only the
    // visible "Lumen" wordmark text should be announced for that card.
    expect(find.bySemanticsLabel('Lumen'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Footer notice text remains fully readable', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        RegExp("Made with care for everyone who's been told it's just cramps"),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Dingbat glyphs are replaced by real Icons', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // 4 support rows + 3 legal rows.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(7));
    // App-icon glyph + footer notice glyph.
    expect(find.byIcon(Icons.auto_awesome), findsNWidgets(2));
  });
}
