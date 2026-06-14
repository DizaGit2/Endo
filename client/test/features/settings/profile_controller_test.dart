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
  });
}

