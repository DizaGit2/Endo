import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/time/device_timezone.dart';
import 'package:lumen/features/onboarding/application/account_validation.dart';
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
  /// 0. Runs [AccountValidation.validate] FIRST. A form the server would
  ///    certainly reject never leaves the device: state becomes [AsyncError]
  ///    holding a [ValidationFailure] keyed exactly the way a server 400 is,
  ///    and no request is issued (P4b-T7). The rules are a strict *subset* of
  ///    the server's — see `account_validation.dart` for what is deliberately
  ///    left to the server.
  /// 1. Reads the device's IANA zone ([deviceTimezoneProvider]) and BCP-47
  ///    locale ([deviceLocaleProvider]) — **D-12's "captured at
  ///    `/onboarding/start`", implemented at the PR #4 review hand-back (D1,
  ///    B-50).** Without them the server defaults the account to
  ///    `Europe/Madrid` / `es-ES`, and every day-keyed row of a user in Mexico
  ///    City files under a day they have not reached. Both are fallbacks the
  ///    server can supply, so a device that will not say (`null`) never blocks
  ///    registration.
  /// 2. Calls [OnboardingRepository.startOnboarding] with all of it — once
  ///    more without the two device fields if the server rejects one of them
  ///    (see [_start]).
  /// 3. On success, calls [AuthController.login] so a Keycloak session is
  ///    established and the router guard redirects to /profile.
  /// 4. If the account already exists ([ConflictFailure] / HTTP 409 — e.g. a
  ///    prior attempt created it but the interactive login was cancelled),
  ///    registration is treated as already-done and the flow proceeds to login
  ///    rather than dead-ending on a generic error.
  /// 5. On any other failure, surfaces the [Failure] as [AsyncError] (no
  ///    navigation).
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final invalid = AccountValidation.validate(
      email: email,
      password: password,
      displayName: displayName,
    );
    if (invalid != null) {
      // Not routed through AsyncValue.guard: there is nothing to guard, and
      // passing through AsyncLoading first would flash the spinner and disable
      // the three fields for a frame on a submit that never left the device.
      state = AsyncError<void>(invalid, StackTrace.current);
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final timezone = await _deviceTimezone();
      final locale = ref.read(deviceLocaleProvider);
      try {
        await _start(
          email: email,
          password: password,
          displayName: displayName,
          locale: locale,
          timezone: timezone,
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

  /// The device zone, or `null` — never an error. [readDeviceTimezone] already
  /// swallows platform failures; this guards the provider itself, so that
  /// nothing about the zone can turn a registration into an [AsyncError].
  Future<String?> _deviceTimezone() async {
    try {
      return await ref.read(deviceTimezoneProvider.future);
    } catch (_) {
      return null;
    }
  }

  /// `POST /onboarding/start`, retried ONCE without the device fields if the
  /// server rejects one of them.
  ///
  /// The server resolves [timezone] with `TimeZoneInfo` and bounds [locale] to
  /// 35 characters; an id the device reports but the server's tz database
  /// does not know would come back as a 400 keyed `timezone` — a field screen
  /// 2 does not draw, so the user could never fix it and registration would
  /// dead-end. The column defaults are exactly what the server applied to
  /// every account before D1 was fixed, so falling back to them costs the
  /// user nothing they had. A 400 on any OTHER field is the form's own and is
  /// rethrown untouched.
  Future<void> _start({
    required String email,
    required String password,
    required String displayName,
    required String? locale,
    required String? timezone,
  }) async {
    final repo = ref.read(onboardingRepositoryProvider);
    try {
      await repo.startOnboarding(
        email: email,
        password: password,
        displayName: displayName,
        locale: locale,
        timezone: timezone,
      );
    } on ValidationFailure catch (failure) {
      final sentDeviceFields = timezone != null || locale != null;
      final deviceFieldRejected =
          failure.messagesFor('timezone').isNotEmpty ||
          failure.messagesFor('locale').isNotEmpty;
      if (!sentDeviceFields || !deviceFieldRejected) rethrow;

      await repo.startOnboarding(
        email: email,
        password: password,
        displayName: displayName,
        locale: null,
        timezone: null,
      );
    }
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
