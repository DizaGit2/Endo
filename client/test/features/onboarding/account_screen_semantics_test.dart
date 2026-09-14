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
import 'package:lumen/features/onboarding/application/account_validation.dart';
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

/// A per-field rejection (P4b-T7) — the shape both a locally-invalid form and
/// a server 400 leave behind, since screen 2 renders one failure type for both.
///
/// The failure comes from the REAL validator rather than a hand-written
/// literal. A fixture that spells its own copy would make the dingbat guard
/// below inspect the fixture instead of the shipped string — proved by
/// mutation: a banned glyph planted in `AccountValidation.emailInvalid` left
/// the hand-written version of this test green.
class _FieldErrorAccountController extends AccountController {
  @override
  Future<void> build() async {
    throw AccountValidation.validate(
      email: 'maya',
      password: 'a-good-passphrase',
      displayName: 'Maya',
    )!;
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

/// Mounts screen 2 on a controller whose `build()` THROWS — **without
/// settling** — and drives the frames by hand.
///
/// `settle: false` is the load-bearing part (P4b-T26 fix round 1).
/// `accountControllerProvider` names no `retry:` of its own, so these three
/// tests are governed by whatever policy the container carries. `pumpApp`
/// defaults to `settle: true`, and `pumpAndSettle` **advances the fake clock**:
/// under riverpod 3.3.2's `defaultRetry` it walks straight through all ten
/// backoffs (~38 s of fake time) and observes the state AFTER the retries are
/// exhausted. A widget test that settles is therefore structurally blind to a
/// provider being retried into a spinner — which is exactly why these three
/// were green before `lumenRetry` existed, and why they were missed in the
/// first sweep for tests that were green for a reason production did not have.
///
/// Pumping frames instead observes what the user gets: with the policy on, the
/// designed error body is on screen; with it off, a spinner is.
Future<void> _pumpFailedBuild(
  WidgetTester tester,
  AccountController Function() controller,
) async {
  await _pump(tester, controller, settle: false);
  await tester.pump();
  await tester.pump();
  // ...then one short frame WITH time on it, for a reason that is about
  // Material and not about riverpod: `InputDecorator` fades `errorText` in
  // over ~167 ms, and a `RenderOpacity` at alpha 0 drops its children from
  // the semantics tree entirely (`visitChildrenForSemantics`). The field
  // error is in the widget tree on the frame above — `find.text` sees it —
  // but `find.bySemanticsLabel` does not until the fade has run. 400 ms is
  // two orders of magnitude short of the ~38 s of backoff the defect needs,
  // so this buys the animation without buying the retries: under
  // `defaultRetry` the tree here is still AsyncLoading(retrying: true), i.e.
  // a spinner.
  await tester.pump(const Duration(milliseconds: 400));
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
    await _pumpFailedBuild(tester, _ErrorAccountController.new);

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

  testWidgetsWithSemantics(
    'a rejected field puts its message in the semantics tree, and the form '
    'still announces that something failed',
    (tester) async {
      // P4b-T7. A red outline is invisible to a screen reader, so a field
      // error that exists only as paint is an error only sighted users get.
      // The message has to be a node of its own; and because a node the user
      // has not swiped onto is silent, the banner keeps its live region so the
      // failure is ANNOUNCED at the moment it happens.
      await _pumpFailedBuild(tester, _FieldErrorAccountController.new);

      expect(
        find.bySemanticsLabel('Enter a valid email address.'),
        findsOneWidget,
        reason: 'the field error must be reachable by assistive tech',
      );
      expectLiveRegion(tester, 'Check the highlighted fields.');
    },
  );

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pump(tester, _IdleAccountController.new);

    expectNoDingbats(tester, screen: 'AccountScreen');
  });

  testWidgets('renders no dingbat glyphs while showing a field error', (
    tester,
  ) async {
    // The rejected state draws copy the idle golden and the idle dingbat check
    // never see.
    await _pumpFailedBuild(tester, _FieldErrorAccountController.new);

    // PIN THE PREMISE. `expectNoDingbats` only requires that SOME `Text`
    // exists, so on its own this test would stay green if screen 2 stopped
    // passing `errorText` altogether — it would go on reporting "no dingbats
    // while showing a field error" with no field error on screen. This line is
    // what makes the name true.
    expect(find.text(AccountValidation.emailInvalid), findsOneWidget);

    expectNoDingbats(tester, screen: 'AccountScreen');
  });
}
