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
import 'package:lumen/shared/widgets/lumen_step_dots.dart';

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

  testWidgetsWithSemantics(
    'the step position is conveyed visually only — recorded, not endorsed',
    (tester) async {
      // P4b-T5b. `LumenStepDots` is decoration and announces nothing, which is
      // correct for seven coloured boxes (see
      // `test/widgets/lumen_step_dots_semantics_test.dart`). The consequence is
      // that "step 1 of 7" reaches a screen-reader user only if this SCREEN
      // says it, and it does not — so the position is invisible to assistive
      // tech across the whole onboarding flow.
      //
      // Filed here rather than with the widget because this is the screen that
      // has to say it, and the natural fix is a Semantics label on the header
      // rather than any change to the shared row.
      await _pump(tester);

      expect(find.byType(LumenStepDots), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('[Ss]tep')),
        findsNothing,
        reason:
            'If this flow now announces its step position, delete this test '
            'and say so — it exists to record that it did not.',
      );
    },
  );

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pump(tester);

    expectNoDingbats(tester, screen: 'WelcomeScreen');
  });
}
