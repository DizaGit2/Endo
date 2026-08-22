// Semantics tests — PrivacyScreen (P3c-T13, house a11y pattern).
//
// A row on this screen that resembles a settings control without having
// anything wired behind it gets MergeSemantics — label + value read as one
// unit — rather than fabricated button semantics. See
// profile_screen_semantics_test.dart's doc comment for the same reasoning
// applied to the user-card row.
//
// **Two rows are no longer in that class, as of P4b-T22c**, and the distinction
// is the whole point of the rule rather than an exception to it: the
// danger-zone row now invokes `DELETE /me`, and the back chevron now pops a
// real route. Both therefore announce themselves as buttons — a control with an
// action behind it SHOULD. The erasure behaviour they lead to is pinned in
// `privacy_screen_erasure_test.dart`.
//
// **And three rows are no longer here at all**, which the first test below
// pins. T22c's fix round removed the APP LOCK section under R-16 rather than
// disabling or rewording it. A screen-reader user was the only one the old
// section did not lie to (the pills exposed no toggle state), so the assertion
// that matters is not about semantics flags — it is that the strings are gone
// from the tree entirely.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';

import '../../support/harness.dart';

Future<void> _pump(WidgetTester tester) =>
    pumpApp(tester, home: const PrivacyScreen());

/// Every string the APP LOCK section used to draw.
///
/// Kept as literals rather than as constants imported from the screen: a
/// constant deleted along with its widget would make this test compile-fail
/// instead of assert, and the point is to keep asserting after the code is
/// gone.
const List<String> _kRemovedAppLockStrings = <String>[
  'App lock',
  'Face ID',
  'Required to open',
  'Hide content in app switcher',
  'Show blank screen',
  'Disguised app icon',
  'Show as "Notes"',
];

void main() {
  testWidgets(
    'the APP LOCK section is GONE — the screen claims no protection v1 does '
    'not ship (R-16; removed at T22c, not disabled and not reworded)',
    (tester) async {
      await _pump(tester);

      for (final gone in _kRemovedAppLockStrings) {
        expect(
          find.textContaining(gone, findRichText: true),
          findsNothing,
          reason:
              '"$gone" is back on screen 36. It described a biometric app '
              'lock, an app-switcher blur or a disguised icon — none of which '
              'v1 has, and the first two rendered as ON. D-07 keeps the '
              'FEATURE in scope; R-16 keeps the COPY out until the feature '
              'is behind it. Ship them together or not at all.',
        );
      }

    },
  );

  testWidgetsWithSemantics(
    'screen 36 offers exactly TWO controls — back, and Delete all data',
    (tester) async {
      await _pump(tester);

      // The complement of the test above, and the half a string assertion
      // cannot make: the section could come back under new words. What may
      // not come back is a CONTROL on this screen with nothing behind it —
      // whether it announces itself (a real Switch) or not.
      expect(
        kAnyButtonSemantics,
        findsExactly(2),
        reason:
            'Screen 36 has two things a user can actuate: the back chevron '
            'and the danger-zone row. A third means something was wired — or '
            'worse, something claims to be wired.',
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
