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
//   • the same read publishes the profile's locale (P4b-T6) — this is the
//     app's only once-per-session /me, so it is the only place the user's own
//     locale can reach the formatters before a screen renders a date.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/locale/locale_provider.dart';
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
  ///
  /// [gateTimeout] shortens the bounded wait so the timeout path is testable
  /// without an 8-second test.
  ProviderContainer makeContainer(AuthStatus status, {Duration? gateTimeout}) {
    final container = ProviderContainer(
      retry: lumenRetry,
      overrides: [
        authStatusProvider.overrideWith(() => _FakeAuthController(status)),
        meRepositoryProvider.overrideWithValue(repo),
        // Pinned so a locale assertion never depends on the host machine's
        // regional settings. Deliberately NOT es-ES: every locale assertion
        // below has to move it to be worth anything.
        deviceLocaleProvider.overrideWithValue('en-US'),
        if (gateTimeout != null)
          onboardingGateTimeoutProvider.overrideWithValue(gateTimeout),
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

    test(
      'a non-Failure throwable still resolves to incomplete (e.g. a provider '
      'that cannot be constructed)',
      () async {
        when(repo.getMe).thenThrow(StateError('boom'));

        final container = makeContainer(AuthStatus.authenticated);
        await pumpEventQueue();

        expect(
          container.read(onboardingStatusProvider),
          OnboardingStatus.incomplete,
        );
      },
    );

    test(
      'an AuthFailure leaves the gate unanswered — the session is being torn '
      'down, so /onboarding must not flash before AuthStatus flips',
      () async {
        when(repo.getMe).thenThrow(const AuthFailure());

        final container = makeContainer(AuthStatus.authenticated);
        await pumpEventQueue();

        expect(
          container.read(onboardingStatusProvider),
          OnboardingStatus.unknown,
        );
      },
    );

    test(
      'a /me read that outruns the bounded wait resolves to unavailable',
      () async {
        // Never completes: the bound is the only thing that can end this.
        when(repo.getMe).thenAnswer((_) => Completer<CacheResult<MeResponse>>().future);

        final container = makeContainer(
          AuthStatus.authenticated,
          gateTimeout: const Duration(milliseconds: 20),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(
          container.read(onboardingStatusProvider),
          OnboardingStatus.unavailable,
        );
      },
    );

    test('a read that beats the bound is unaffected by it', () async {
      when(repo.getMe).thenAnswer(
        (_) async => Fresh(_me(onboardingCompleted: true)),
      );

      final container = makeContainer(
        AuthStatus.authenticated,
        gateTimeout: const Duration(milliseconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.completed,
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

  // -------------------------------------------------------------------------
  // The gate's /me read is also the app's locale source (P4b-T6)
  // -------------------------------------------------------------------------
  //
  // Without this, a user whose profile says `es-ES` on an `en-US` device gets
  // Sunday-first weeks, a 12-hour clock and period decimals for the whole
  // session — until they happen to open Settings > Profile, which is the only
  // other place a profile is loaded, and then everything flips mid-session.

  group('publishes the profile locale', () {
    test('a Fresh profile moves the effective locale off the device', () async {
      when(repo.getMe).thenAnswer(
        (_) async => Fresh(_me(onboardingCompleted: true)),
      );

      final container = makeContainer(AuthStatus.authenticated);
      expect(container.read(localeProvider), 'en_US');

      await pumpEventQueue();

      expect(container.read(profileLocaleProvider), 'es');
      expect(container.read(localeProvider), 'es');
    });

    test('a Stale profile publishes it too', () async {
      when(repo.getMe).thenAnswer(
        (_) async => Stale(_me(onboardingCompleted: true)),
      );

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();

      expect(container.read(localeProvider), 'es');
    });

    test('NetworkRequired publishes nothing, and erases nothing', () async {
      // Same shape as the profile controller's: asserting the sink is null
      // after a NetworkRequired proves nothing, because null is where it
      // starts. Seeding it first is the positive control — it catches the
      // plausible wrong implementation `adopt(profile?.locale)`, which would
      // publish a null over a locale that was already there.
      when(repo.getMe).thenAnswer(
        (_) async => const NetworkRequired<MeResponse>(NetworkFailure()),
      );

      final container = makeContainer(AuthStatus.authenticated);
      container.read(profileLocaleProvider.notifier).adopt('fr-FR');
      // 'fr', not 'fr_FR': intl ships no `fr_FR` entry, so the resolver
      // shortens it — the same fact `hasLocaleData` documents for `de_DE`.
      expect(container.read(localeProvider), 'fr',
          reason: 'control: something really was published first');

      await pumpEventQueue();

      expect(container.read(profileLocaleProvider), 'fr-FR');
      expect(container.read(localeProvider), 'fr');
    });

    test('a session that only ever sees NetworkRequired keeps the device '
        'locale', () async {
      when(repo.getMe).thenAnswer(
        (_) async => const NetworkRequired<MeResponse>(NetworkFailure()),
      );

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();

      expect(container.read(profileLocaleProvider), isNull);
      expect(container.read(localeProvider), 'en_US');
    });

    test('a read that lands after sign-out publishes nothing', () async {
      // Same reasoning as the status itself: on a shared device that response
      // carries the PREVIOUS user's locale, and sign-out just cleared it.
      final gate = Completer<CacheResult<MeResponse>>();
      when(repo.getMe).thenAnswer((_) => gate.future);

      final container = makeContainer(AuthStatus.authenticated);
      await pumpEventQueue();

      (container.read(authStatusProvider.notifier) as _FakeAuthController)
          .setStatus(AuthStatus.unauthenticated);
      await pumpEventQueue();

      gate.complete(Fresh(_me(onboardingCompleted: true)));
      await pumpEventQueue();

      expect(container.read(profileLocaleProvider), isNull);
      expect(container.read(localeProvider), 'en_US');
    });
  });
}
