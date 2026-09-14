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

  testWidgetsWithSemantics('the step position is announced, not only drawn', (
    tester,
  ) async {
    // P4b-T8 closes the deficiency P4b-T5b pinned here. The old test asserted
    // that this flow conveyed its position visually ONLY, and carried an
    // instruction to delete it once that stopped being true; this is its
    // replacement.
    //
    // `LumenStepDots` still announces nothing, and that is still correct —
    // seven coloured boxes belong nowhere in the reading order (see
    // `test/widgets/lumen_step_dots_semantics_test.dart`). So the position has
    // to come from the eyebrow, and the eyebrow is drawn UPPERCASED, which is
    // what made it useless: `LUMEN · 1 OF 7` is an all-caps run many screen
    // readers spell out, punctuated by a middle dot read as noise.
    //
    // Hence both halves below. The first is the positive control for the
    // second: the shouted string really is on screen, so its absence from the
    // semantics tree is a fact about what is announced rather than about a
    // screen that failed to render.
    await _pump(tester);

    expect(find.byType(LumenStepDots), findsOneWidget);
    expect(
      find.text('LUMEN · 1 OF 7'),
      findsOneWidget,
      reason: 'premise: the mockup eyebrow is drawn, unchanged and uppercased',
    );

    // "Lumen" is in no other Text on this screen, so the announcement carries
    // the word rather than dropping it along with the shouting.
    expect(find.bySemanticsLabel('Lumen, step 1 of 7'), findsOneWidget);
    expect(find.bySemanticsLabel('LUMEN · 1 OF 7'), findsNothing);
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pump(tester);

    expectNoDingbats(tester, screen: 'WelcomeScreen');
  });
}
