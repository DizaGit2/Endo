import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/features/settings/data/me_repository.dart';

// ---------------------------------------------------------------------------
// OnboardingStatus
// ---------------------------------------------------------------------------

/// Whether the signed-in user still has to go through the onboarding flow.
///
/// Three states, not a `bool`: the router's redirect runs synchronously and
/// must be able to tell "not onboarded" apart from "not known yet". Collapsing
/// the two would either strand a first-run user in the app or bounce a
/// long-standing user through onboarding on every cold start.
enum OnboardingStatus {
  /// No session, or the profile that answers the question has not loaded yet.
  unknown,

  /// The read outran its bounded wait ([onboardingGateTimeoutProvider]).
  ///
  /// Routing-wise this is identical to [unknown] — still no answer, so the user
  /// is still held on the splash. What changes is the *surface*: the splash
  /// swaps its indeterminate spinner for an error state with a retry, so the
  /// wait is bounded and actionable instead of endless.
  unavailable,

  /// The user has not finished onboarding — the gate is closed.
  incomplete,

  /// The user has finished onboarding — the gate is open.
  completed,
}

// ---------------------------------------------------------------------------
// Bounded wait
// ---------------------------------------------------------------------------

/// How long the gate waits for `/me` before showing the retry surface.
///
/// Deliberately shorter than Dio's own timeouts (connect 15 s / receive 20 s,
/// `dio_provider.dart`): on a flaky-but-not-dead network the transport can take
/// the best part of half a minute to give up, and the user is staring at a
/// spinner for all of it. Eight seconds is long enough that a healthy cold start
/// never sees it and short enough to stay human-scale. Overridable so tests do
/// not have to spend it.
final onboardingGateTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 8),
);

/// Maps a loaded profile onto an [OnboardingStatus].
///
/// `MeResponse.onboardingCompleted` is `bool?`: per `ARCHITECTURE.md` §C.0.2
/// *every* generated Dart property is nullable, so `null` is a shape the
/// contract permits rather than a bug. It is treated as NOT onboarded — the
/// safe direction, because it routes the user into a flow they can leave
/// instead of past a gate they needed. Never force-unwrap it.
OnboardingStatus onboardingStatusFrom(MeResponse? me) {
  return me?.onboardingCompleted == true
      ? OnboardingStatus.completed
      : OnboardingStatus.incomplete;
}

// ---------------------------------------------------------------------------
// OnboardingStatusController
// ---------------------------------------------------------------------------

/// Session-scoped holder for the onboarding gate's answer.
///
/// GoRouter's `redirect` callback is synchronous and runs on every navigation
/// and every `refreshListenable` notification, so it must never fetch `/me`
/// itself. This controller does the read once per authenticated session and
/// publishes the result as a plain synchronous value the redirect can read.
///
/// Lifecycle:
/// - it watches [authStatusProvider], so signing out rebuilds it back to
///   [OnboardingStatus.unknown] and no answer survives into the next session
///   (the profile behind it is per-user PII);
/// - becoming [AuthStatus.authenticated] kicks off a single `/me` read;
/// - that read also publishes the profile's locale into `profileLocaleProvider`
///   (P4b-T6), which is what makes the app locale-aware from the first frame
///   rather than from whenever the user first opens Settings;
/// - an in-flight read that lands after the session changed is discarded
///   (see [_generation]), so a logout can never be undone by a late response.
///
/// Failure handling, which is the whole subtlety here:
/// - a profile that cannot be read resolves to [OnboardingStatus.incomplete]
///   rather than staying `unknown` — `unknown` holds the user on the splash
///   with no way forward, whereas the onboarding flow is a screen they can act
///   on;
/// - except an [AuthFailure], which means the session is already being torn
///   down; resolving that one would flash `/onboarding` on the way to the
///   welcome screen, so it is left unanswered;
/// - and except the bounded wait ([onboardingGateTimeoutProvider]) being
///   exceeded, which resolves to [OnboardingStatus.unavailable] so the splash
///   can offer a retry rather than spinning until Dio gives up.
class OnboardingStatusController extends Notifier<OnboardingStatus> {
  /// Incremented on every rebuild so a stale `/me` response can be recognised.
  int _generation = 0;

  @override
  OnboardingStatus build() {
    final generation = ++_generation;

    if (ref.watch(authStatusProvider) == AuthStatus.authenticated) {
      // Deferred to a microtask so `state` is never assigned from inside
      // build(): a repository that throws synchronously would otherwise have
      // its resolution overwritten by build()'s own return value below.
      unawaited(Future<void>.microtask(() => _load(generation)));
    }
    return OnboardingStatus.unknown;
  }

  Future<void> _load(int generation) async {
    OnboardingStatus resolved;
    // Held rather than mapped immediately: this same read is the app's only
    // once-per-session `/me`, so it is also the only place the user's own
    // locale can reach `profileLocaleProvider` before a screen renders a date.
    // ProfileScreen (screen 31) is the only other producer, and a user who
    // never opens Settings would otherwise spend the whole session on the
    // device locale — Sunday-first and 12-hour for an `es-ES` user on a US
    // phone (D-03/D-05).
    MeResponse? profile;
    try {
      final result = await ref
          .read(meRepositoryProvider)
          .getMe()
          .timeout(ref.read(onboardingGateTimeoutProvider));
      profile = switch (result) {
        Fresh(:final value) => value,
        Stale(:final value) => value,
        // Offline with no cache, so the answer is unknowable right now.
        NetworkRequired() => null,
      };
      // Unchanged behaviour: `onboardingStatusFrom(null)` is `incomplete`,
      // which is what the NetworkRequired arm resolved to before.
      resolved = onboardingStatusFrom(profile);
    } on AuthFailure {
      // The session itself is invalid (an expired refresh token surfaces here
      // as a 401 that cachedRead deliberately rethrows rather than masking).
      // dioProvider.onAuthLost is already tearing the session down, so leave
      // the gate unanswered: resolving to `incomplete` would flash
      // /onboarding in the window before AuthStatus flips to unauthenticated.
      return;
    } on TimeoutException {
      // The bounded wait, not a transport failure — the read may still be in
      // flight. Hand the user a retry instead of an endless spinner.
      resolved = OnboardingStatus.unavailable;
    } on Failure {
      // Any other typed Failure: no answer, so fall to the leavable side of
      // the gate rather than stranding the user on the splash.
      resolved = OnboardingStatus.incomplete;
    } catch (_) {
      // Not a Failure at all (e.g. a provider that cannot be constructed in a
      // test scope). Same conclusion, and it must never escape as an unhandled
      // async error.
      resolved = OnboardingStatus.incomplete;
    }

    // The session moved on while the read was in flight (sign-out, or another
    // auth transition): the answer belongs to a session that no longer exists.
    if (!ref.mounted || generation != _generation) return;

    // Deliberately AFTER the staleness guard, for the same reason `state` is:
    // adopting here from a previous session's response would re-populate the
    // locale sink that signing out just cleared, and on a shared device that is
    // the previous user's locale.
    if (profile != null) {
      ref.read(profileLocaleProvider.notifier).adopt(profile.locale);
    }
    state = resolved;
  }

  /// Opens the gate without another `/me` round-trip.
  ///
  /// Called by the onboarding flow once `POST /onboarding/complete` succeeds
  /// (P4b-T8) so the user is not bounced back into the flow they just finished
  /// while the cached profile is still stale.
  void markCompleted() => state = OnboardingStatus.completed;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Exposes [OnboardingStatus] for the router's onboarding gate.
///
/// Deliberately NOT `autoDispose`: the router holds it for the whole session
/// and disposing it between navigations would re-read `/me` on every route
/// change. Sign-out clears it via the [authStatusProvider] dependency.
final onboardingStatusProvider =
    NotifierProvider<OnboardingStatusController, OnboardingStatus>(
      OnboardingStatusController.new,
    );
