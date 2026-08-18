// LumenStepChrome — the onboarding eyebrow (P4b-T8).
//
// Copy tests. What a screen reader hears from it is in
// `lumen_step_chrome_semantics_test.dart`; the two are separate because the
// whole point of this widget is that those two strings are DIFFERENT.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_step_chrome.dart';

import '../support/harness.dart';

Future<void> _pumpChrome(WidgetTester tester, LumenStepChrome chrome) =>
    pumpApp(tester, home: Scaffold(body: chrome));

void main() {
  test('the canonical eyebrow is the mockups\' own string', () {
    // Screens 3-7 print "Step N of 7 · <title>"; screen 2 prints "Step 2 of 7"
    // with no title. Both forms are built here rather than at five call sites.
    expect(
      const LumenStepChrome(step: 3, totalSteps: 7, title: 'Cycle').eyebrowText,
      'Step 3 of 7 · Cycle',
    );
    expect(
      const LumenStepChrome(step: 2, totalSteps: 7).eyebrowText,
      'Step 2 of 7',
    );
  });

  test('a lead word gives screen 1 the form its mockup prints', () {
    // Screen 1's mockup says "Lumen · 1 of 7", not "Step 1 of 7". Both strings
    // are asserted from ONE input, which is the whole reason `lead` is a word
    // rather than a visible-string override: the drawn form and the announced
    // form cannot drift apart, and "Lumen" survives into both.
    const chrome = LumenStepChrome(step: 1, totalSteps: 7, lead: 'Lumen');

    expect(chrome.eyebrowText, 'Lumen · 1 of 7');
    expect(chrome.announcement, 'Lumen, step 1 of 7');
  });

  test('a lead word and a title cannot both be set', () {
    // No mockup prints both, and the eyebrow has room for one separator.
    expect(
      () => LumenStepChrome(
        step: 1,
        totalSteps: 7,
        lead: 'Lumen',
        title: 'Cycle',
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('it renders the eyebrow uppercased, as the mockup draws it', (
    tester,
  ) async {
    await _pumpChrome(
      tester,
      const LumenStepChrome(step: 3, totalSteps: 7, title: 'Cycle'),
    );

    // The design system's `.tag` rule is `text-transform: uppercase`, so the
    // SOURCE string stays sentence case and the transform is presentation —
    // which is exactly why the announcement can be the sentence-case one.
    expect(find.text('STEP 3 OF 7 · CYCLE'), findsOneWidget);
    expect(find.text('Step 3 of 7 · Cycle'), findsNothing);
  });

  testWidgets('every step of the flow renders its own eyebrow', (tester) async {
    // Five different inputs, five different outputs: a widget that ignored
    // `step` or `title` would fail four of these five.
    for (final (step, title, expected) in const <(int, String, String)>[
      (3, 'Cycle', 'STEP 3 OF 7 · CYCLE'),
      (4, 'About you', 'STEP 4 OF 7 · ABOUT YOU'),
      (5, 'Goals', 'STEP 5 OF 7 · GOALS'),
      (6, 'Hormones', 'STEP 6 OF 7 · HORMONES'),
      (7, 'Reminders', 'STEP 7 OF 7 · REMINDERS'),
    ]) {
      await _pumpChrome(
        tester,
        LumenStepChrome(step: step, totalSteps: 7, title: title),
      );

      expect(find.text(expected), findsOneWidget);
    }
  });

  test('a position outside the flow is a programming error', () {
    // The eyebrow is a promise about how much remains. "Step 8 of 7" is not a
    // rendering bug to notice in review — it is a bad argument, and the assert
    // names it at the call site.
    expect(
      () => LumenStepChrome(step: 8, totalSteps: 7),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => LumenStepChrome(step: 0, totalSteps: 7),
      throwsA(isA<AssertionError>()),
    );
  });
}
