import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';

// ---------------------------------------------------------------------------
// AccountController
// ---------------------------------------------------------------------------

/// Drives the Account screen (register / sign-in).
///
/// States:
/// - [AsyncData<void>]  — idle (initial) or last operation succeeded.
/// - [AsyncLoading<void>] — operation in progress.
/// - [AsyncError<void>] — last operation failed; [AsyncError.error] holds a
///   [Failure] subtype that the UI renders as an inline error message.
///
/// Navigation: on success the router redirect (authenticated → /profile) handles
/// navigation — the controller does NOT push routes.
class AccountController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Initial state is idle (AsyncData(null)).
  }

  // -------------------------------------------------------------------------
  // register
  // -------------------------------------------------------------------------

  /// Creates a new account, then triggers the OIDC login flow.
  ///
  /// 1. Calls [OnboardingRepository.startOnboarding] with the supplied fields.
  /// 2. On success, calls [AuthController.login] so a Keycloak session is
  ///    established and the router guard redirects to /profile.
  /// 3. If the account already exists ([ConflictFailure] / HTTP 409 — e.g. a
  ///    prior attempt created it but the interactive login was cancelled),
  ///    registration is treated as already-done and the flow proceeds to login
  ///    rather than dead-ending on a generic error.
  /// 4. On any other failure, surfaces the [Failure] as [AsyncError] (no
  ///    navigation).
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        await ref
            .read(onboardingRepositoryProvider)
            .startOnboarding(
              email: email,
              password: password,
              displayName: displayName,
            );
      } on ConflictFailure {
        // The account already exists — recover by signing in with these
        // credentials instead of trapping the user on a 409.
      }
      // Registration succeeded (or the account already existed) — start the
      // interactive OIDC session.
      await ref.read(authStatusProvider.notifier).login();
    });
  }

  // -------------------------------------------------------------------------
  // signIn
  // -------------------------------------------------------------------------

  /// Triggers the OIDC login flow for an existing user.
  ///
  /// The router guard redirects to /profile after [AuthController.login]
  /// resolves and state becomes [AuthStatus.authenticated].
  Future<void> signIn() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authStatusProvider.notifier).login(),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [AccountController] as an [AsyncNotifier].
final accountControllerProvider =
    AsyncNotifierProvider<AccountController, void>(AccountController.new);
