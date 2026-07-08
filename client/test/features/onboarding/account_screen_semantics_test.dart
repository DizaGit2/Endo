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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/onboarding/application/account_controller.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.unauthenticated;
}

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

Widget _wrap(AccountController Function() controller) => ProviderScope(
  overrides: [
    authStatusProvider.overrideWith(() => _FakeAuthController()),
    accountControllerProvider.overrideWith(controller),
  ],
  child: MaterialApp(
    theme: lumenTheme(Brightness.light),
    home: const AccountScreen(),
  ),
);

void main() {
  testWidgets('Continue CTA exposes button semantics with its visible label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(_IdleAccountController.new));
    await tester.pumpAndSettle();

    final data = tester.getSemantics(find.text('Continue'));
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.label, 'Continue');
    handle.dispose();
  });

  testWidgets(
    'Loading state: the spinner has a semanticsLabel, which becomes the '
    "Continue button's accessible name",
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(_PendingAccountController.new));
      await tester.pump();

      expect(find.bySemanticsLabel('Signing in'), findsOneWidget);
      final data = tester.getSemantics(find.bySemanticsLabel('Signing in'));
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    },
  );

  testWidgets('Error banner announces via a live region', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(_ErrorAccountController.new));
    await tester.pumpAndSettle();

    const message = 'A server error occurred. Please try again later.';
    expect(find.text(message), findsOneWidget);
    final data = tester.getSemantics(find.text(message));
    expect(data.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
