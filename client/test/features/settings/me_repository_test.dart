// Tests for MeRepository (TDD — RED first).
//
// Uses a real temp-dir CacheStore (same pattern as cached_query_test.dart) and
// a mocktail mock of LumenApiApi to verify:
//   (a) getMe returns Fresh on network success + writes through to cache.
//   (b) getMe returns Stale when network fails and a cached entry exists —
//       the Stale value deep-equals the original response field-by-field, a
//       real _toJson -> Hive -> _fromJson round trip (P3c-T12).
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

/// Builds a real (temp-dir, encrypted) [CacheStore]. [clock] defaults to a
/// fixed instant; pass a mutable one (e.g. `() => clockNow`) so a test can
/// advance time past a TTL without a second, independent Hive box.
Future<CacheStore> _buildStore(Directory dir, {Clock? clock}) async {
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
    clock: clock ?? () => DateTime.utc(2026, 6, 14, 12, 0, 0),
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
  // Mutable clock backing `store`. Only the round-trip fidelity test below
  // advances it; every other test leaves it untouched, so behaviour there is
  // identical to the old fixed-clock lambda.
  late DateTime clockNow;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('me_repository_test_');
    mockApi = MockLumenApiApi();
    clockNow = DateTime.utc(2026, 6, 14, 12, 0, 0);
    store = await _buildStore(tempDir, clock: () => clockNow);

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

      // Write-through: the cache holds the wire-format fields. This is a
      // narrower check than the round-trip fidelity test below (group (b)) —
      // it only proves *something* recognizable was written, not that
      // reading it back is lossless.
      final cached = store.getJson('GET:/me');
      expect(cached, isNotNull);
      expect(cached!['id'], 'user-123');
      expect(cached['displayName'], 'María');
    });
  });

  // -------------------------------------------------------------------------
  // (b) getMe — network fail + cache present → Stale, round-trip fidelity
  // -------------------------------------------------------------------------

  group('getMe — network fail with cached value', () {
    test(
      'Stale result deep-equals the original response, field-by-field, '
      'after a real _toJson -> Hive -> _fromJson round trip',
      () async {
        // Full response: 5/5 fields, including a NON-default
        // onboardingCompleted=true — a lost field or a silent default-to-false
        // bug would surface as a mismatch below instead of being masked.
        final me = _sampleMe(displayName: 'CachedUser');
        when(() => mockApi.meGet())
            .thenAnswer((_) async => Response(
                  requestOptions: RequestOptions(path: '/me'),
                  data: me,
                  statusCode: 200,
                ));

        final repo = MeRepository(api: mockApi, store: store);

        // First call succeeds: writes through to cache via the REAL _toJson
        // serializer (never a hand-built map).
        final first = await repo.getMe();
        expect(first, isA<Fresh<MeResponse>>());

        // Advance the shared clock past the 5-minute TTL used by
        // MeRepository.getMe so the next call treats the entry as stale and
        // is forced through the (now-failing) network path instead of
        // short-circuiting to the fresh-cache branch.
        clockNow = clockNow.add(const Duration(minutes: 6));

        when(() => mockApi.meGet()).thenThrow(_networkError());

        final result = await repo.getMe();

        expect(result, isA<Stale<MeResponse>>());
        final stale = (result as Stale<MeResponse>).value;

        // Deep-equals, field-by-field: proves _toJson -> Hive -> _fromJson
        // loses nothing.
        expect(stale.id, me.id);
        expect(stale.displayName, me.displayName);
        expect(stale.locale, me.locale);
        expect(stale.timezone, me.timezone);
        expect(stale.onboardingCompleted, me.onboardingCompleted);
        expect(
          stale.onboardingCompleted,
          isTrue,
          reason:
              'guards against a silent default-to-false bug masking a lost field',
        );
        // Belt-and-braces: built_value's generated field-by-field equality.
        expect(stale, me);
      },
    );
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
