// Semantics regression guard — WelcomeScreen (P3c-T13, house a11y pattern).
//
// WelcomeScreen's CTAs are stock Material buttons (FilledButton / TextButton),
// which already expose correct `button` + label semantics for free, sourced
// from their Text child — no production wrapping is needed here. These tests
// lock that baseline in as a regression guard, so a future refactor (e.g.
// swapping a CTA for an icon-only button) can't silently drop the accessible
// name without a test failing.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';

import '../../support/harness.dart';

Future<void> _pump(WidgetTester tester) =>
    pumpApp(tester, home: const WelcomeScreen());

void main() {
  testWidgetsWithSemantics(
    'Begin CTA exposes button semantics with its visible label',
    (tester) async {
      await _pump(tester);

      // exactLabel: the announced name must be "Begin" and nothing else —
      // a containment check would still pass if something merged extra text
      // into the CTA's accessible name.
      expectLabeledButton(
        tester,
        find.text('Begin'),
        'Begin',
        exactLabel: true,
      );
      expect(find.bySemanticsLabel('Begin'), findsOneWidget);
    },
  );

  testWidgetsWithSemantics(
    '"I already have an account" link exposes button semantics with its '
    'visible label',
    (tester) async {
      await _pump(tester);

      expectLabeledButton(
        tester,
        find.text('I already have an account'),
        'I already have an account',
      );
      expect(
        find.bySemanticsLabel('I already have an account'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pump(tester);

    expectNoDingbats(tester, screen: 'WelcomeScreen');
  });
}
