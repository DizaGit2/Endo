// Tests for ProfileController (TDD — RED first).
//
// Verifies:
//   (a) build() loads /me → state becomes AsyncData wrapping Fresh/Stale/NetworkRequired.
//   (b) saveDisplayName() calls updateMe then refreshes (triggers a new load).
//   (c) NetworkRequired failure surfaces as AsyncError.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/provider_overrides.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockMeRepository extends Mock implements MeRepository {}

/// Records every provider failure Riverpod reports.
///
/// Needed because the thing under test is an exception that is otherwise
/// INVISIBLE: a `ref.read` on a disposed provider throws
/// `UnmountedRefException`, and with nobody listening to the disposed
/// controller the throw is swallowed. Asserting only on the sink cannot tell
/// "the guard returned early" from "the read threw and was discarded".
final class _FailureSpy extends ProviderObserver {
  final failures = <Object>[];

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    failures.add(error);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MeResponse _sampleMe({String displayName = 'María'}) {
  return MeResponse(
    (b) => b
      ..id = 'user-123'
      ..displayName = displayName
      ..locale = 'es'
      ..timezone = 'Europe/Madrid'
      ..onboardingCompleted = true,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockMeRepository mockRepo;

  setUp(() {
    mockRepo = MockMeRepository();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      retry: lumenRetry,
      overrides: [
        meRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // (a) build — loads /me successfully → AsyncData(Fresh)
  // -------------------------------------------------------------------------

  group('ProfileController build — success', () {
    test('state is AsyncData(Fresh(MeResponse)) after successful load',
        () async {
      final me = _sampleMe();
      when(() => mockRepo.getMe())
          .thenAnswer((_) async => Fresh(me));

      final container = makeContainer();
      addTearDown(container.dispose);

      // Wait for the notifier to finish building
      final result =
          await container.read(profileControllerProvider.future);

      expect(result, isA<Fresh<MeResponse>>());
      final fresh = result as Fresh<MeResponse>;
      expect(fresh.value.displayName, 'María');
    });
  });

  // -------------------------------------------------------------------------
  // (b) build — returns Stale when offline with cache
  // -------------------------------------------------------------------------

  group('ProfileController build — stale', () {
    test('state is AsyncData(Stale(MeResponse)) when network fails with cache',
        () async {
      final me = _sampleMe(displayName: 'CachedUser');
      when(() => mockRepo.getMe())
          .thenAnswer((_) async => Stale(me));

      final container = makeContainer();
      addTearDown(container.dispose);

      final result =
          await container.read(profileControllerProvider.future);

      expect(result, isA<Stale<MeResponse>>());
      final stale = result as Stale<MeResponse>;
      expect(stale.value.displayName, 'CachedUser');
    });
  });

  // -------------------------------------------------------------------------
  // (c) build — NetworkRequired surfaces as AsyncError
  // -------------------------------------------------------------------------

  group('ProfileController build — NetworkRequired', () {
    test('state is AsyncData(NetworkRequired) when no network and no cache',
        () async {
      when(() => mockRepo.getMe()).thenAnswer((_) async =>
          const NetworkRequired<MeResponse>(
            NetworkFailure('No network and no cache.'),
          ));

      final container = makeContainer();
      addTearDown(container.dispose);

      final result =
          await container.read(profileControllerProvider.future);

      expect(result, isA<NetworkRequired<MeResponse>>());
    });
  });

  // -------------------------------------------------------------------------
  // (d) saveDisplayName — calls updateMe and refreshes
  // -------------------------------------------------------------------------

  group('ProfileController saveDisplayName', () {
    test('calls updateMe then triggers a refresh (getMe called twice)',
        () async {
      final me = _sampleMe();
      when(() => mockRepo.getMe()).thenAnswer((_) async => Fresh(me));
      when(() => mockRepo.updateMe(displayName: any(named: 'displayName')))
          .thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      // Wait for initial load
      await container.read(profileControllerProvider.future);

      // Invoke saveDisplayName
      await container
          .read(profileControllerProvider.notifier)
          .saveDisplayName('Nueva');

      // updateMe was called once
      verify(
        () => mockRepo.updateMe(displayName: 'Nueva'),
      ).called(1);
      // getMe was called at least twice (initial + after refresh)
      verify(() => mockRepo.getMe()).called(greaterThanOrEqualTo(2));
    });

    test(
        'keeps the loaded profile (with the new name) when the post-save '
        're-fetch returns NetworkRequired — does NOT blank the screen',
        () async {
      final me = _sampleMe(displayName: 'María');
      var call = 0;
      when(() => mockRepo.getMe()).thenAnswer((_) async {
        call++;
        return call == 1
            ? Fresh(me)
            : const NetworkRequired<MeResponse>(NetworkFailure());
      });
      when(() => mockRepo.updateMe(displayName: any(named: 'displayName')))
          .thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(profileControllerProvider.future);

      await container
          .read(profileControllerProvider.notifier)
          .saveDisplayName('Nueva');

      // PATCH succeeded; the transient re-fetch failure must NOT replace the
      // profile with the "connect to load" empty state.
      final state = container.read(profileControllerProvider);
      expect(state, isA<AsyncData<CacheResult<MeResponse>>>());
      final result = state.requireValue;
      expect(result, isA<Fresh<MeResponse>>());
      expect((result as Fresh<MeResponse>).value.displayName, 'Nueva');
    });

    test(
        'keeps the loaded profile (with the new name) when the post-save '
        're-fetch throws — does NOT surface AsyncError', () async {
      final me = _sampleMe(displayName: 'María');
      var call = 0;
      when(() => mockRepo.getMe()).thenAnswer((_) async {
        call++;
        if (call == 1) return Fresh(me);
        throw Exception('refetch failed');
      });
      when(() => mockRepo.updateMe(displayName: any(named: 'displayName')))
          .thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(profileControllerProvider.future);

      await container
          .read(profileControllerProvider.notifier)
          .saveDisplayName('Nueva');

      final state = container.read(profileControllerProvider);
      expect(state, isA<AsyncData<CacheResult<MeResponse>>>());
      expect(
        (state.requireValue as Fresh<MeResponse>).value.displayName,
        'Nueva',
      );
    });
  });

  // -------------------------------------------------------------------------
  // (e) cross-account isolation — no stale profile across sessions
  // -------------------------------------------------------------------------

  group('ProfileController cross-account isolation', () {
    test(
        'does NOT retain the previous session profile after the screen '
        'unsubscribes (re-login fetches the new user)', () async {
      final userA = _sampleMe(displayName: 'Maya');
      final userB = _sampleMe(displayName: 'Verify');
      var call = 0;
      when(() => mockRepo.getMe()).thenAnswer((_) async {
        call++;
        return Fresh(call == 1 ? userA : userB);
      });

      final container = makeContainer();
      addTearDown(container.dispose);

      // Session 1: the ProfileScreen mounts (subscribes), loads user A, then
      // the user logs out and the screen unmounts (subscription closes).
      final sub1 = container.listen(
        profileControllerProvider,
        (_, _) {},
      );
      final first = await container.read(profileControllerProvider.future);
      expect((first as Fresh<MeResponse>).value.displayName, 'Maya');
      sub1.close();
      await Future<void>.delayed(Duration.zero); // allow tear-down

      // Session 2: a different user logs in → the screen remounts. It MUST
      // fetch its own profile, not reuse the previous session's data.
      container.listen(profileControllerProvider, (_, _) {});
      final second = await container.read(profileControllerProvider.future);
      expect(
        (second as Fresh<MeResponse>).value.displayName,
        'Verify',
        reason: 'A new authenticated session must not see the prior user\'s '
            'profile (cross-account PII leak).',
      );
    });
  });

  // -------------------------------------------------------------------------
  // (f) the profile publishes its locale (P4b-T6)
  // -------------------------------------------------------------------------
  //
  // `localeProvider` resolves profile -> device -> es-ES. The profile half of
  // that chain only works if something actually pushes `MeResponse.locale` into
  // it, and this controller is the one place a profile is ever loaded.

  group('ProfileController publishes the profile locale', () {
    ProviderContainer localeContainer() {
      final container = ProviderContainer(
        retry: lumenRetry,
        overrides: [
          meRepositoryProvider.overrideWithValue(mockRepo),
          // Pinned so the assertions do not depend on the host machine.
          deviceLocaleProvider.overrideWithValue('en-US'),
          // `profileLocaleProvider` watches auth so sign-out forgets the
          // locale; an un-pinned AuthController transitions to
          // `unauthenticated` mid-test and clears what was just adopted.
          ...lumenOverrides(),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a loaded profile switches the effective locale away from the device',
        () async {
      when(() => mockRepo.getMe()).thenAnswer((_) async => Fresh(_sampleMe()));

      final container = localeContainer();
      expect(container.read(localeProvider), 'en_US',
          reason: 'before the profile loads, the device locale stands');

      await container.read(profileControllerProvider.future);

      expect(container.read(profileLocaleProvider), 'es');
      expect(container.read(localeProvider), 'es');
    });

    test('a STALE profile publishes its locale too', () async {
      // Offline is not a reason to render a Spanish user an American calendar.
      when(() => mockRepo.getMe()).thenAnswer((_) async => Stale(_sampleMe()));

      final container = localeContainer();
      await container.read(profileControllerProvider.future);

      expect(container.read(localeProvider), 'es');
    });

    test('NetworkRequired neither publishes nor erases', () async {
      // The first half of this test is a POSITIVE CONTROL. Asserting only that
      // the sink is null after a NetworkRequired proves nothing: null is the
      // container's starting value, so it would pass with `_adoptLocale`
      // deleted outright. Publishing something first makes the assertion
      // load-bearing in both directions — the read must not publish, and must
      // not wipe what is already there ("leaves the previous answer standing").
      var call = 0;
      when(() => mockRepo.getMe()).thenAnswer((_) async {
        call++;
        return call == 1
            ? Fresh(_sampleMe())
            : const NetworkRequired<MeResponse>(NetworkFailure());
      });

      final container = localeContainer();
      final sub = container.listen(profileControllerProvider, (_, _) {});
      addTearDown(sub.close);

      await container.read(profileControllerProvider.future);
      expect(container.read(localeProvider), 'es',
          reason: 'control: the locale really was published first');

      container.invalidate(profileControllerProvider);
      await container.read(profileControllerProvider.future);

      expect(container.read(profileLocaleProvider), 'es');
      expect(container.read(localeProvider), 'es');
    });

    test('a session that only ever sees NetworkRequired keeps the device '
        'locale', () async {
      when(() => mockRepo.getMe())
          .thenAnswer((_) async => const NetworkRequired<MeResponse>(
                NetworkFailure(),
              ));

      final container = localeContainer();
      await container.read(profileControllerProvider.future);

      expect(container.read(profileLocaleProvider), isNull);
      expect(container.read(localeProvider), 'en_US');
    });

    test('the post-save re-fetch republishes the locale', () async {
      // saveDisplayName re-reads /me, and that response can legitimately carry
      // a different locale (the user changed it on another device). Without an
      // adopt on this path the screen would show the new name and the old
      // locale until the next cold start.
      final before = _sampleMe();
      final after = _sampleMe().rebuild((b) => b..locale = 'en-GB');
      var call = 0;
      when(() => mockRepo.getMe()).thenAnswer((_) async {
        call++;
        return Fresh(call == 1 ? before : after);
      });
      when(() => mockRepo.updateMe(displayName: any(named: 'displayName')))
          .thenAnswer((_) async {});

      final container = localeContainer();
      await container.read(profileControllerProvider.future);
      expect(container.read(localeProvider), 'es');

      await container
          .read(profileControllerProvider.notifier)
          .saveDisplayName('Nueva');

      expect(container.read(localeProvider), 'en_GB');
    });

    test('a read landing after the screen unmounted publishes nothing, quietly',
        () async {
      // The session guard on this side of the app. Unlike the onboarding gate
      // (which carries a generation counter) this provider is autoDispose and
      // dies with the screen — so `ref.mounted` is the whole check.
      //
      // BOTH assertions are needed and the second is the one with teeth:
      // autoDispose alone already keeps the sink null, because the late
      // `ref.read` throws `UnmountedRefException` and the throw is discarded.
      // Asserting only `isNull` would pass with or without the guard.
      final gate = Completer<CacheResult<MeResponse>>();
      when(() => mockRepo.getMe()).thenAnswer((_) => gate.future);

      final spy = _FailureSpy();
      final container = ProviderContainer(
        retry: lumenRetry,
        observers: [spy],
        overrides: [
          meRepositoryProvider.overrideWithValue(mockRepo),
          deviceLocaleProvider.overrideWithValue('en-US'),
          ...lumenOverrides(),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(profileControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      sub.close(); // the screen unmounts -> autoDispose disposes the controller
      await Future<void>.delayed(Duration.zero);

      gate.complete(Fresh(_sampleMe()));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(profileLocaleProvider), isNull);
      expect(
        spy.failures,
        isEmpty,
        reason: 'the late adopt must return early, not raise '
            'UnmountedRefException and have it swallowed; '
            'got ${spy.failures.map((e) => e.runtimeType).toList()}',
      );
    });

    test('a null locale on the profile falls back rather than throwing',
        () async {
      // Every generated property is nullable; `locale` is no exception.
      final noLocale = _sampleMe().rebuild((b) => b..locale = null);
      when(() => mockRepo.getMe()).thenAnswer((_) async => Fresh(noLocale));

      final container = localeContainer();
      await container.read(profileControllerProvider.future);

      expect(container.read(localeProvider), 'en_US');
    });
  });
}
