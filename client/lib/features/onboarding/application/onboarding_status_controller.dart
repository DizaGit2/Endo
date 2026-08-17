import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
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

  /// The user has not finished onboarding — the gate is closed.
  incomplete,

  /// The user has finished onboarding — the gate is open.
  completed,
}

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
/// - an in-flight read that lands after the session changed is discarded
///   (see [_generation]), so a logout can never be undone by a late response.
///
/// A profile that cannot be read at all resolves to
/// [OnboardingStatus.incomplete] rather than staying `unknown`: `unknown` holds
/// the user on the splash with no way forward, whereas the onboarding flow is
/// a screen they can act on.
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
    try {
      final result = await ref.read(meRepositoryProvider).getMe();
      resolved = switch (result) {
        Fresh(:final value) => onboardingStatusFrom(value),
        Stale(:final value) => onboardingStatusFrom(value),
        // Offline with no cache, so the answer is unknowable right now.
        NetworkRequired() => OnboardingStatus.incomplete,
      };
    } catch (_) {
      // Any typed Failure (or a provider that cannot even be constructed in a
      // test scope) means the same thing here: no answer. Fall to the leavable
      // side of the gate rather than stranding the user on the splash.
      resolved = OnboardingStatus.incomplete;
    }

    // The session moved on while the read was in flight (sign-out, or another
    // auth transition): the answer belongs to a session that no longer exists.
    if (!ref.mounted || generation != _generation) return;
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
