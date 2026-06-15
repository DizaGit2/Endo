// Tests for MeRepository (TDD — RED first).
//
// Uses a real temp-dir CacheStore (same pattern as cached_query_test.dart) and
// a mocktail mock of LumenApiApi to verify:
//   (a) getMe returns Fresh on network success + writes through to cache.
//   (b) getMe returns Stale when network fails and a cached entry exists.
//   (c) getMe returns NetworkRequired when network fails and no cache exists.
//   (d) updateMe calls mePatch and invalidates 'GET:/me'.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/update_me_request.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';
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
  late Directory tempDir;
  late MockLumenApiApi mockApi;
  late CacheStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('me_repository_test_');
    mockApi = MockLumenApiApi();
    store = await _buildStore(tempDir);

    // Register fallback for UpdateMeRequest (needed by mocktail for matchers)
    registerFallbackValue(UpdateMeRequest((b) => b..displayName = 'fallback'));
  });

  tearDown(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // -------------------------------------------------------------------------
  // (a) getMe — network success → Fresh + write-through
  // -------------------------------------------------------------------------

  group('getMe — network success', () {
    test('returns Fresh(MeResponse) and writes through to cache', () async {
      final me = _sampleMe();
      when(() => mockApi.meGet())
          .thenAnswer((_) async => Response(
                requestOptions: RequestOptions(path: '/me'),
                data: me,
                statusCode: 200,
              ));

      final repo = MeRepository(api: mockApi, store: store);
      final result = await repo.getMe();

      expect(result, isA<Fresh<MeResponse>>());
      final fresh = result as Fresh<MeResponse>;
      expect(fresh.value.id, 'user-123');
      expect(fresh.value.displayName, 'María');

      // Write-through: verify the cache has the entry
      final cached = store.getJson('GET:/me');
      expect(cached, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // (b) getMe — network fail + cache present → Stale
  // -------------------------------------------------------------------------

  group('getMe — network fail with cached value', () {
    test('returns Stale(MeResponse) when network throws and cache exists',
        () async {
      // Pre-populate cache via a successful call first
      final me = _sampleMe(displayName: 'CachedUser');
      when(() => mockApi.meGet())
          .thenAnswer((_) async => Response(
                requestOptions: RequestOptions(path: '/me'),
                data: me,
                statusCode: 200,
              ));
      final repo = MeRepository(api: mockApi, store: store);
      await repo.getMe(); // populates cache

      // Now make the network fail
      when(() => mockApi.meGet()).thenThrow(_networkError());

      // Force cache to be stale by invalidating TTL (re-write without TTL)
      await store.invalidate('GET:/me');
      // Re-write with no TTL so it's stale (not fresh)
      await store.putJson('GET:/me', {
        'id': 'user-123',
        'displayName': 'CachedUser',
        'locale': 'es',
        'timezone': 'Europe/Madrid',
        'onboardingCompleted': true,
      });

      final result = await repo.getMe();

      expect(result, isA<Stale<MeResponse>>());
      final stale = result as Stale<MeResponse>;
      expect(stale.value.displayName, 'CachedUser');
    });
  });

  // -------------------------------------------------------------------------
  // (c) getMe — network fail + no cache → NetworkRequired
  // -------------------------------------------------------------------------

  group('getMe — network fail without cache', () {
    test('returns NetworkRequired when network throws and no cache', () async {
      when(() => mockApi.meGet()).thenThrow(_networkError());

      final repo = MeRepository(api: mockApi, store: store);
      final result = await repo.getMe();

      expect(result, isA<NetworkRequired<MeResponse>>());
    });
  });

  // -------------------------------------------------------------------------
  // (c2) getMe — 200 with empty/null body → typed failure, not a raw TypeError
  // -------------------------------------------------------------------------

  group('getMe — empty 200 body', () {
    test('maps a null response body to a typed ServerFailure (NetworkRequired)',
        () async {
      when(() => mockApi.meGet()).thenAnswer((_) async => Response<MeResponse>(
            requestOptions: RequestOptions(path: '/me'),
            data: null,
            statusCode: 200,
          ));

      final repo = MeRepository(api: mockApi, store: store);

      // Must NOT throw a raw TypeError (null-check on null) that escapes the
      // SWR layer — an empty body is mapped to a typed failure; with no cache
      // it surfaces as NetworkRequired.
      final result = await repo.getMe();
      expect(result, isA<NetworkRequired<MeResponse>>());
      expect(
        (result as NetworkRequired<MeResponse>).failure,
        isA<ServerFailure>(),
      );
    });
  });

  // -------------------------------------------------------------------------
  // (d) updateMe — calls mePatch + invalidates 'GET:/me'
  // -------------------------------------------------------------------------

  group('updateMe — calls mePatch and invalidates cache', () {
    test('calls mePatch with the correct displayName and invalidates GET:/me',
        () async {
      // Pre-populate cache
      await store.putJson(
        'GET:/me',
        {'id': 'user-123', 'displayName': 'Old'},
        ttl: const Duration(hours: 1),
      );

      when(() => mockApi.mePatch(updateMeRequest: any(named: 'updateMeRequest')))
          .thenAnswer((_) async => Response(
                requestOptions: RequestOptions(path: '/me'),
                statusCode: 204,
              ));

      final repo = MeRepository(api: mockApi, store: store);
      await repo.updateMe(displayName: 'María');

      // Verify mePatch was called
      verify(
        () => mockApi.mePatch(updateMeRequest: any(named: 'updateMeRequest')),
      ).called(1);

      // Verify cache was invalidated
      expect(store.getJson('GET:/me'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Provider wiring — meRepositoryProvider resolves without error given overrides
  // -------------------------------------------------------------------------

  group('meRepositoryProvider', () {
    test('resolves to a MeRepository instance', () {
      final container = ProviderContainer(
        overrides: [
          lumenApiProvider.overrideWithValue(mockApi),
          cacheStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(meRepositoryProvider);
      expect(repo, isA<MeRepository>());
    });
  });
}
