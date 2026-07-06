// Semantics regression guard — WelcomeScreen (P3c-T13, house a11y pattern).
//
// WelcomeScreen's CTAs are stock Material buttons (FilledButton / TextButton),
// which already expose correct `button` + label semantics for free, sourced
// from their Text child — no production wrapping is needed here. These tests
// lock that baseline in as a regression guard, so a future refactor (e.g.
// swapping a CTA for an icon-only button) can't silently drop the accessible
// name without a test failing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';

Widget _wrap() => MaterialApp(
  theme: lumenTheme(Brightness.light),
  home: const WelcomeScreen(),
);

void main() {
  testWidgets('Begin CTA exposes button semantics with its visible label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final data = tester.getSemantics(find.text('Begin'));
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.label, 'Begin');
    expect(find.bySemanticsLabel('Begin'), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
    '"I already have an account" link exposes button semantics with its '
    'visible label',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final data = tester.getSemantics(
        find.text('I already have an account'),
      );
      expect(data.flagsCollection.isButton, isTrue);
      expect(
        find.bySemanticsLabel('I already have an account'),
        findsOneWidget,
      );
      handle.dispose();
    },
  );
}
