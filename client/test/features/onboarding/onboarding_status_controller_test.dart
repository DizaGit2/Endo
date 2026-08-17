// Tests for OnboardingStatusController (P4b-T1, TDD — RED first).
//
// The router's onboarding gate runs inside GoRouter's synchronous `redirect`
// callback, which fires often and cannot await. This controller is the
// already-available state the redirect reads: it loads `/me` ONCE per
// authenticated session and exposes the answer as a synchronous three-state
// value (unknown / incomplete / completed).
//
// Covered here:
//   • no session, no read — /me is never touched while unauthenticated.
//   • the nullable `onboardingCompleted` mapping (ARCHITECTURE §C.0.2).
//   • Stale (offline-with-cache) is as good as Fresh for this decision.
//   • an unreadable profile resolves to `incomplete`, the leavable direction.
//   • sign-out resets the status, and an in-flight read that lands after
//     sign-out cannot resurrect it.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _MockMeRepository extends Mock implements MeRepository {}

/// [AuthController] with no TokenStore / OidcClient, whose status the test
/// drives directly (sign-out is a status transition, not a real logout).
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthStatus _initial;

  @override
  AuthStatus build() {
    initialized = Future<void>.value();
    return _initial;
  }

  void setStatus(AuthStatus status) => state = status;
}

MeResponse _me({bool? onboardingCompleted}) {
  return MeResponse(
    (b) => b
      ..id = 'user-1'
      ..displayName = 'María'
      ..locale = 'es'
      ..timezone = 'Europe/Madrid'
      ..onboardingCompleted = onboardingCompleted,
  );
}

void main() {
  late _MockMeRepository repo;

  setUp(() {
    repo = _MockMeRepository();
  });

  /// Builds a container with [status] as the session state, keeps the
  /// onboarding provider alive, and returns it.
  ProviderContainer makeContainer(AuthStatus status) {
    final container = ProviderContainer(
      overrides: [
        authStatusProvider.overrideWith(() => _FakeAuthController(status)),
        meRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    // Keep the provider alive so an auth transition rebuilds it eagerly.
    container.listen(onboardingStatusProvider, (_, _) {}, fireImmediately: true);
    return container;
  }

  // -------------------------------------------------------------------------
  // No session — nothing is read
  // -------------------------------------------------------------------------

  group('without an authenticated session', () {
    test('auth unknown leaves the status unknown and never reads /me', () async {
      final container = makeContainer(AuthStatus.unknown);
      await pumpEventQueue();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.unknown,
      );
      verifyNever(repo.getMe);
    });

    test('unauthenticated leaves the status unknown and never reads /me',
        () async {
      final container = makeContainer(AuthStatus.unauthenticated);
      await pumpEventQueue();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.unknown,
      );
      verifyNever(repo.getMe);
    });
  });

  // -------------------------------------------------------------------------
  // Authenticated — the /me read resolves the gate
  // -------------------------------------------------------------------------

  group('authenticated', () {
    test('starts at unknown before the /me read resolves', () {
      when(repo.getMe).thenAnswer(
        (_) async => Fresh(_me(onboardingCompleted: true)),
      );

      final container = makeContainer(AuthStatus.authenticated);

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.unknown,
      );
    });

    test('onboardingCompleted == true resolves to completed', () async {
      when(repo.getMe).thenAnswer(
        (_) async => Fresh(_me(onboardingCompleted: true)),
      );

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.completed,
      );
    });

    test('onboardingCompleted == false resolves to incomplete', () async {
      when(repo.getMe).thenAnswer(
        (_) async => Fresh(_me(onboardingCompleted: false)),
      );

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.incomplete,
      );
    });

    test('a null onboardingCompleted resolves to incomplete', () async {
      when(repo.getMe).thenAnswer((_) async => Fresh(_me()));

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.incomplete,
      );
    });

    test('a Stale (cached, offline) profile is good enough to open the gate',
        () async {
      when(repo.getMe).thenAnswer(
        (_) async => Stale(_me(onboardingCompleted: true)),
      );

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.completed,
      );
    });

    test(
      'NetworkRequired (no network, no cache) resolves to incomplete — never '
      'left at unknown, which would strand the user on the splash',
      () async {
        when(repo.getMe).thenAnswer(
          (_) async => const NetworkRequired<MeResponse>(NetworkFailure()),
        );

        final container = makeContainer(AuthStatus.authenticated);
        await pumpEventQueue();

        expect(
          container.read(onboardingStatusProvider),
          OnboardingStatus.incomplete,
        );
      },
    );

    test('a throwing /me read resolves to incomplete', () async {
      when(repo.getMe).thenThrow(const ServerFailure());

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.incomplete,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Transitions
  // -------------------------------------------------------------------------

  group('transitions', () {
    test('markCompleted() opens the gate without another /me read', () async {
      when(repo.getMe).thenAnswer(
        (_) async => Fresh(_me(onboardingCompleted: false)),
      );

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();
      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.incomplete,
      );

      container.read(onboardingStatusProvider.notifier).markCompleted();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.completed,
      );
      verify(repo.getMe).called(1);
    });

    test('signing out resets the status to unknown', () async {
      when(repo.getMe).thenAnswer(
        (_) async => Fresh(_me(onboardingCompleted: true)),
      );

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();
      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.completed,
      );

      (container.read(authStatusProvider.notifier) as _FakeAuthController)
          .setStatus(AuthStatus.unauthenticated);
      await pumpEventQueue();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.unknown,
      );
    });

    test(
      'a /me read that lands after sign-out does not resurrect the status',
      () async {
        final gate = Completer<CacheResult<MeResponse>>();
        when(repo.getMe).thenAnswer((_) => gate.future);

        final container = makeContainer(AuthStatus.authenticated);
        await pumpEventQueue();

        (container.read(authStatusProvider.notifier) as _FakeAuthController)
            .setStatus(AuthStatus.unauthenticated);
        await pumpEventQueue();

        gate.complete(Fresh(_me(onboardingCompleted: true)));
        await pumpEventQueue();

        expect(
          container.read(onboardingStatusProvider),
          OnboardingStatus.unknown,
        );
      },
    );
  });
}
