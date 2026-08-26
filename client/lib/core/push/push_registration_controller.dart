import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/push/push_token_source.dart';
import 'package:lumen/features/settings/data/device_repository.dart';

// ---------------------------------------------------------------------------
// PushRegistrationOutcome
// ---------------------------------------------------------------------------

/// What the last registration attempt did.
///
/// Nothing renders this in P4b — there is no surface for it and none is
/// invented (R-10's rule for the preferences applies here too). It exists so
/// the hook's behaviour is *observable*: without it "nothing was sent" is
/// indistinguishable from "the hook never ran", and that distinction is the
/// only thing a null token source leaves a test to assert.
enum PushRegistrationOutcome {
  /// No attempt has been made in this session — the state before the hook runs,
  /// and the state of an unauthenticated app.
  idle,

  /// The hook ran and the device has no token to send. **The normal P4b
  /// outcome**, and a documented normal outcome of the contract too
  /// (`deviceRegistered: false`), not a failure.
  noToken,

  /// `POST /me/devices` accepted the token.
  registered,

  /// The attempt failed — the token source threw, or the write did. There is no
  /// retry and no user-facing surface: the next app start is the retry, which
  /// is the cadence.
  failed,
}

// ---------------------------------------------------------------------------
// PushRegistrationController
// ---------------------------------------------------------------------------

/// Registers this device's push token — **on every app start** (§C.0.3, §C.9).
///
/// ## Why "every app start" and not "first launch + token refresh"
///
/// `POST /me/devices` upserts on `(UserId, PushToken)`, and **registering a
/// token detaches it from every other account**. That detach's accepted cost —
/// anyone holding a victim's token can unregister their device — is bounded
/// *only* because the victim's app takes the token back on its next start. Under
/// a "first launch + token refresh" cadence there is nothing to take it back
/// with: a silenced user stays silenced until FCM or APNs happens to rotate
/// their token, which may be months. The cadence is a safety property, not a
/// housekeeping preference, and `push_registration_test.dart` states it as the
/// thing it forbids — a second authenticated session re-registers the *same*
/// token.
///
/// So this class holds **no memory of what it last sent**, deliberately. Adding
/// one is the mutation the cadence test exists to kill, and it would survive an
/// ordinary rebuild: in Riverpod 3.3.2 a `Notifier` whose watched dependency
/// changes has `build()` re-invoked on the *same instance* (measured at T13).
///
/// ## Shape
///
/// A plain `Notifier<PushRegistrationOutcome>` with a **synchronous `build()`**,
/// per the phase's controller-shape rule: the work is handed to a microtask that
/// `build()` does not await, exactly as `OnboardingFlowController` and
/// `OnboardingStatusController` do. An `AsyncNotifier` would assign its build
/// result unconditionally when it landed and silently drop the outcome written
/// first.
///
/// ## When it runs
///
/// It watches [authStatusProvider] and attempts a registration whenever the
/// status *is* authenticated. `POST /me/devices` is an authenticated endpoint
/// and a device row belongs to an account, so there is nothing to send before
/// then. That makes the trigger "every app start of a signed-in user, plus every
/// later sign-in" — a **superset** of §C.9's cadence and never a subset.
///
/// The provider is **not** `autoDispose`: it is built once inside the root
/// `ProviderScope`, which exists exactly once per app start, and `LumenApp`
/// subscribes to it. That subscription is what makes "app start" a real trigger
/// rather than a comment.
///
/// ## Order of operations
///
/// The token is read **before** the repository is touched. On a build with no
/// messaging service that means [deviceRepositoryProvider] — and therefore the
/// whole Dio stack behind it — is never constructed for a device that has no
/// token, which is every P4b device.
class PushRegistrationController extends Notifier<PushRegistrationOutcome> {
  /// Incremented on every build so an attempt that lands after a rebuild is
  /// discarded rather than overwriting a newer generation's outcome.
  ///
  /// **This is not a memo of what was sent**, and it must never become one: it
  /// never suppresses a request, only the recording of a stale one's result.
  int _generation = 0;

  @override
  PushRegistrationOutcome build() {
    final AuthStatus auth = ref.watch(authStatusProvider);
    if (auth != AuthStatus.authenticated) return PushRegistrationOutcome.idle;

    final int generation = ++_generation;
    // Deferred to a microtask so `state` is never assigned from inside build().
    unawaited(Future<void>.microtask(() => _register(generation)));
    return PushRegistrationOutcome.idle;
  }

  Future<void> _register(int generation) async {
    late final PushRegistrationOutcome outcome;
    try {
      // FIRST — see the class docs. With no token there is nothing to send and
      // no repository to build.
      //
      // Through `sendable`, so a BLANK half never reaches the wire: both
      // members are required on `POST /me/devices` and measured after trimming,
      // so a blank token is a 400 rather than a registration. FCM can answer an
      // empty string during a `deleteToken()` race, and "no token" is the
      // honest reading of that.
      final PushToken? token = PushToken.sendable(
        await ref.read(pushTokenSourceProvider).read(),
      );

      if (token == null) {
        outcome = PushRegistrationOutcome.noToken;
      } else {
        await ref
            .read(deviceRepositoryProvider)
            .registerDevice(platform: token.platform, pushToken: token.token);
        outcome = PushRegistrationOutcome.registered;
      }
    } catch (_) {
      // Nothing here is user-facing, and app start must not become a crash
      // because the network was down, the token was rejected or a future
      // messaging SDK threw. The token is PII (§F), so the failure is recorded
      // as a state and never as a message that could quote it.
      outcome = PushRegistrationOutcome.failed;
    }

    if (!ref.mounted || generation != _generation) return;
    state = outcome;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// The app-start push registration.
///
/// Deliberately **not** `autoDispose`: one instance per app start is the whole
/// cadence. `LumenApp` subscribes to it with `ref.listen`, which builds it
/// without rebuilding the app on every outcome change.
final pushRegistrationProvider =
    NotifierProvider<PushRegistrationController, PushRegistrationOutcome>(
      PushRegistrationController.new,
    );
