// Tests for ProfileController (TDD — RED first).
//
// Verifies:
//   (a) build() loads /me → state becomes AsyncData wrapping Fresh/Stale/NetworkRequired.
//   (b) saveDisplayName() calls updateMe then refreshes (triggers a new load).
//   (c) NetworkRequired failure surfaces as AsyncError.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockMeRepository extends Mock implements MeRepository {}

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
}

