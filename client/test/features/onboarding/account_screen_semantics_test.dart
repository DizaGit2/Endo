// Semantics tests — AccountScreen (P3c-T13, house a11y pattern).
//
// TDD (RED first): before this task, the loading-state CircularProgressIndicator
// had no semanticsLabel (an unlabeled spinner takes over the Continue button's
// accessible name, and screen readers announce nothing useful), and the error
// banner was not a live region (a screen reader never hears about a failed
// registration attempt). Both are fixed in account_screen.dart.
//
// The idle-state "Continue" / "I already have an account" controls are stock
// Material buttons — covered here as a regression guard (see the equivalent
// welcome_screen_semantics_test.dart doc comment).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/account_controller.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Controller archetypes (the four states of a data-driven screen)
// ---------------------------------------------------------------------------

/// Idle controller (AsyncData(null)) — the default "Continue" label state.
class _IdleAccountController extends AccountController {
  @override
  Future<void> build() async {}
}

/// Never resolves — keeps the provider in AsyncLoading for the whole test,
/// simulating "register()/signIn() in flight".
class _PendingAccountController extends AccountController {
  @override
  Future<void> build() => Completer<void>().future;
}

/// build() throws a Failure — the provider's initial state becomes
/// AsyncError, matching what a failed register()/signIn() leaves behind.
class _ErrorAccountController extends AccountController {
  @override
  Future<void> build() async {
    throw const ServerFailure();
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester,
  AccountController Function() controller, {
  bool settle = true,
}) {
  return pumpApp(
    tester,
    home: const AccountScreen(),
    settle: settle,
    overrides: [
      ...lumenOverrides(auth: AuthStatus.unauthenticated),
      accountControllerProvider.overrideWith(controller),
    ],
  );
}

void main() {
  testWidgetsWithSemantics(
    'Continue CTA exposes button semantics with its visible label',
    (tester) async {
      await _pump(tester, _IdleAccountController.new);

      // exactLabel: this screen's very next test proves the reachable
      // regression — the loading spinner's 'Signing in' label merges into
      // this button's accessible name. "Continue Signing in" satisfies a
      // containment check and is exactly what must never ship in the idle
      // state, so the idle name is pinned by equality.
      expectLabeledButton(
        tester,
        find.text('Continue'),
        'Continue',
        exactLabel: true,
      );
    },
  );

  testWidgetsWithSemantics(
    'Loading state: the spinner has a semanticsLabel, which becomes the '
    "Continue button's accessible name",
    (tester) async {
      // settle: false — the spinner animates forever, so settle never arrives.
      await _pump(tester, _PendingAccountController.new, settle: false);

      expectLabeledSpinner(tester, 'Signing in');
      final data = tester.getSemantics(find.bySemanticsLabel('Signing in'));
      expect(data.flagsCollection.isButton, isTrue);
    },
  );

  testWidgetsWithSemantics('Error banner announces via a live region', (
    tester,
  ) async {
    await _pump(tester, _ErrorAccountController.new);

    expectLiveRegion(
      tester,
      'A server error occurred. Please try again later.',
    );
  });

  testWidgetsWithSemantics(
    'each field announces the label drawn above it, not its placeholder',
    (tester) async {
      // P4b-T5b. `LumenInputField` renders hint text only, so before it took a
      // required `label` a screen reader landing on these three fields heard
      // "Maya", "you@example.com" and the bullet run — the `_FieldLabel` above
      // each one is a separate Text node associated with nothing.
      //
      // The three assertions are per-field on purpose: the widget-level test
      // proves the mechanism works, and only this proves each screen field was
      // given the RIGHT string. `label: ''` compiles.
      await _pump(tester, _IdleAccountController.new);

      final fields = find.byType(LumenInputField);
      expect(fields, findsNWidgets(3));

      for (final (index, label) in <String>[
        'Name',
        'Email',
        'Password',
      ].indexed) {
        expectLabeledField(tester, fields.at(index), label);
      }
    },
  );

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pump(tester, _IdleAccountController.new);

    expectNoDingbats(tester, screen: 'AccountScreen');
  });
}
