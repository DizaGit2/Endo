// Repository-level "writes never queue" contract test for MeRepository.
//
// Verifies that a failing updateMe() call:
//   (a) throws a typed Failure, AND
//   (b) leaves NO pending-write entry in the real temp-dir CacheStore.
//
// This complements the cachedWrite unit test in test/core/cache/cached_query_test.dart
// by exercising the full MeRepository → cachedWrite → CacheStore path, tying the
// online-only contract to the actual repository code path.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/update_me_request.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockLumenApiApi extends Mock implements LumenApiApi {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/me'),
      type: DioExceptionType.connectionError,
    );

Future<CacheStore> _buildStore(Directory dir) async {
  final storage = MockFlutterSecureStorage();
  when(() => storage.read(key: any(named: 'key')))
      .thenAnswer((_) async => null);
  when(
    () => storage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((_) async {});
  return initHive(
    path: dir.path,
    storage: storage,
    clock: () => DateTime.utc(2026, 6, 14, 12, 0, 0),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;
  late MockLumenApiApi mockApi;
  late CacheStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('me_repository_write_test_');
    mockApi = MockLumenApiApi();
    store = await _buildStore(tempDir);

    registerFallbackValue(UpdateMeRequest((b) => b..displayName = 'fallback'));
  });

  tearDown(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // -------------------------------------------------------------------------
  // writes-never-queue — repository-level contract
  // -------------------------------------------------------------------------

  group('MeRepository.updateMe() — writes never queue', () {
    test(
      'on network failure: throws typed Failure and leaves no pending entry in CacheStore',
      () async {
        // 'GET:/me' is the key that updateMe() invalidates on success.
        // It must remain absent (no pending-write entry) after a failed call.
        const cacheKey = 'GET:/me';

        // Confirm the key is absent before the call.
        expect(store.getJson(cacheKey), isNull,
            reason: 'Precondition: cache must be empty before updateMe');

        // Make mePatch throw a connectivity error.
        when(() => mockApi.mePatch(
              updateMeRequest: any(named: 'updateMeRequest'),
            )).thenThrow(_networkError());

        final repo = MeRepository(api: mockApi, store: store);

        Object? caught;
        try {
          await repo.updateMe(displayName: 'Nuevo nombre');
        } catch (e) {
          caught = e;
        }

        // Must have thrown a typed Failure (not a raw DioException).
        expect(caught, isA<Failure>(),
            reason: 'updateMe must rethrow a typed Failure on network error');
        expect(caught, isA<NetworkFailure>());

        // The cache box must still have no entry for GET:/me — no pending write
        // was ever stored.
        expect(store.getJson(cacheKey), isNull,
            reason: 'No pending-write entry should exist in the cache after a failed write');
      },
    );

    test(
      'on network failure with existing cache: original cached entry is untouched, no pending write added',
      () async {
        const cacheKey = 'GET:/me';

        // Pre-populate cache (simulates a prior successful getMe call).
        await store.putJson(cacheKey, {
          'id': 'user-123',
          'displayName': 'Original',
          'locale': 'es',
          'timezone': 'Europe/Madrid',
          'onboardingCompleted': true,
        });

        // Make mePatch throw.
        when(() => mockApi.mePatch(
              updateMeRequest: any(named: 'updateMeRequest'),
            )).thenThrow(_networkError());

        final repo = MeRepository(api: mockApi, store: store);

        Object? caught;
        try {
          await repo.updateMe(displayName: 'Should not persist');
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<NetworkFailure>());

        // Original cached entry must be INTACT (not overwritten, not removed).
        final cached = store.getJson(cacheKey);
        expect(cached, isNotNull,
            reason: 'Original cache entry must survive a failed write');
        expect(cached!['displayName'], 'Original',
            reason: 'Cache must contain the original value, not the failed write payload');
      },
    );
  });
}
