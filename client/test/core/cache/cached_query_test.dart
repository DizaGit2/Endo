// Tests for cachedRead / cachedWrite (cached_query.dart) — TDD RED phase.
//
// CacheStore is used via a real temp-dir backed Hive instance (same as
// hive_boot_test). DioException / Failure are used directly.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockCacheStore extends Mock implements CacheStore {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [DioException] of type [DioExceptionType.connectionError] to
/// simulate a network failure without needing a real HTTP server.
DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/test'),
      type: DioExceptionType.connectionError,
    );

typedef Clock = DateTime Function();

Future<CacheStore> _buildStore(Directory dir, Clock clock) async {
  final storage = MockFlutterSecureStorage();
  when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => null);
  when(
    () => storage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((_) async {});

  return initHive(path: dir.path, storage: storage, clock: clock);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;
  final baseTime = DateTime.utc(2026, 6, 14, 12, 0, 0);

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(const Duration(minutes: 5));
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cached_query_test_');
  });

  tearDown(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // -------------------------------------------------------------------------
  // cachedRead — (a) network success → Fresh + written through
  // -------------------------------------------------------------------------

  group('cachedRead — network success', () {
    test('returns Fresh(value) and writes through to cache', () async {
      final store = await _buildStore(tempDir, () => baseTime);
      const key = 'GET:/me:';
      final networkValue = {'id': '1', 'name': 'Alice'};

      final result = await cachedRead<Map<String, dynamic>>(
        key: key,
        store: store,
        fetch: () async => networkValue,
        toJson: (v) => v,
        fromJson: (m) => m,
        ttl: const Duration(minutes: 5),
      );

      expect(result, isA<Fresh<Map<String, dynamic>>>());
      final fresh = result as Fresh<Map<String, dynamic>>;
      expect(fresh.value['id'], '1');
      expect(fresh.value['name'], 'Alice');

      // Write-through: value must now be in cache
      final cached = store.getJson(key);
      expect(cached, isNotNull);
      expect(cached!['id'], '1');
    });
  });

  // -------------------------------------------------------------------------
  // cachedRead — (b) network fails + cache present → Stale(cached)
  // -------------------------------------------------------------------------

  group('cachedRead — network fail with cached value', () {
    test('returns Stale(cachedValue) when network throws and cache exists',
        () async {
      var now = baseTime;
      final store = await _buildStore(tempDir, () => now);
      const key = 'GET:/me:';

      // Pre-populate cache with a stale entry
      await store.putJson(key, {'id': '99', 'name': 'Cached'});

      // Advance clock so the entry is stale (no TTL → never fresh)
      now = baseTime.add(const Duration(hours: 1));

      final result = await cachedRead<Map<String, dynamic>>(
        key: key,
        store: store,
        fetch: () async => throw _networkError(),
        toJson: (v) => v,
        fromJson: (m) => m,
        ttl: const Duration(minutes: 5),
      );

      expect(result, isA<Stale<Map<String, dynamic>>>());
      final stale = result as Stale<Map<String, dynamic>>;
      expect(stale.value['id'], '99');
      expect(stale.value['name'], 'Cached');
    });
  });

  // -------------------------------------------------------------------------
  // cachedRead — (c) network fails + no cache → NetworkRequired(failure)
  // -------------------------------------------------------------------------

  group('cachedRead — network fail without cache', () {
    test('returns NetworkRequired(failure) when network throws and no cache',
        () async {
      final store = await _buildStore(tempDir, () => baseTime);

      final result = await cachedRead<Map<String, dynamic>>(
        key: 'GET:/me:',
        store: store,
        fetch: () async => throw _networkError(),
        toJson: (v) => v,
        fromJson: (m) => m,
        ttl: const Duration(minutes: 5),
      );

      expect(result, isA<NetworkRequired<Map<String, dynamic>>>());
      final nr = result as NetworkRequired<Map<String, dynamic>>;
      expect(nr.failure, isA<NetworkFailure>());
    });
  });

  // -------------------------------------------------------------------------
  // cachedRead — (d) fresh cache short-circuit
  // -------------------------------------------------------------------------

  group('cachedRead — fresh cache short-circuit', () {
    test('returns Fresh from cache without calling fetch when entry is fresh',
        () async {
      final store = await _buildStore(tempDir, () => baseTime);
      const key = 'GET:/me:';
      var fetchCalled = false;

      // Pre-populate cache with a fresh entry
      await store.putJson(key, {'id': '77', 'name': 'Fresh'}, ttl: const Duration(minutes: 10));

      final result = await cachedRead<Map<String, dynamic>>(
        key: key,
        store: store,
        fetch: () async {
          fetchCalled = true;
          return {'id': '77', 'name': 'Fresh'};
        },
        toJson: (v) => v,
        fromJson: (m) => m,
        ttl: const Duration(minutes: 10),
      );

      expect(result, isA<Fresh<Map<String, dynamic>>>());
      // When fresh, fetch should NOT have been called (stale-while-revalidate
      // short-circuit behavior)
      expect(fetchCalled, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // cachedRead — (e) cache-write failure must not mask a successful fetch
  // -------------------------------------------------------------------------

  group('cachedRead — cache-write failure', () {
    test('returns Fresh(value) when fetch succeeds but putJson throws',
        () async {
      final store = MockCacheStore();
      when(() => store.isFresh(any())).thenReturn(false);
      when(() => store.getJson(any())).thenReturn(null);
      // The encrypted Hive box can throw a raw error (e.g. box closed after a
      // logout-purge, disk full) — NOT a DioException or Failure.
      when(() => store.putJson(any(), any(), ttl: any(named: 'ttl')))
          .thenThrow(StateError('Box has already been closed.'));

      final result = await cachedRead<Map<String, dynamic>>(
        key: 'GET:/me:',
        store: store,
        fetch: () async => {'id': '1', 'name': 'Alice'},
        toJson: (v) => v,
        fromJson: (m) => m,
        ttl: const Duration(minutes: 5),
      );

      // The network fetch SUCCEEDED, so the live value must be returned as Fresh
      // even though the best-effort cache write failed.
      expect(result, isA<Fresh<Map<String, dynamic>>>());
      expect((result as Fresh<Map<String, dynamic>>).value['id'], '1');
    });
  });

  // -------------------------------------------------------------------------
  // cachedRead — in-flight de-duplication (r13 deferral)
  // -------------------------------------------------------------------------
  //
  // Two providers reading the same key concurrently (today: ProfileController
  // and the router's onboarding gate, both on 'GET:/me') must share ONE network
  // request. The regression a naive Completer cache gets wrong is the failure
  // path: if the guard is only cleared on success, a single failed read strands
  // the key forever.

  group('cachedRead — in-flight de-duplication', () {
    test('two concurrent reads of the same key issue ONE fetch, both get the value',
        () async {
      final store = await _buildStore(tempDir, () => baseTime);
      const key = 'GET:/me';
      var fetchCount = 0;
      final gate = Completer<Map<String, dynamic>>();

      Future<CacheResult<Map<String, dynamic>>> read() =>
          cachedRead<Map<String, dynamic>>(
            key: key,
            store: store,
            fetch: () {
              fetchCount++;
              return gate.future;
            },
            toJson: (v) => v,
            fromJson: (m) => m,
          );

      // Both calls are made before either can settle.
      final first = read();
      final second = read();
      gate.complete({'id': '1', 'name': 'Alice'});
      final results = await Future.wait([first, second]);

      expect(fetchCount, 1, reason: 'the second caller must join the in-flight request');
      for (final result in results) {
        expect(result, isA<Fresh<Map<String, dynamic>>>());
        expect((result as Fresh<Map<String, dynamic>>).value['id'], '1');
      }
    });

    test('concurrent reads of DIFFERENT keys are not merged', () async {
      final store = await _buildStore(tempDir, () => baseTime);
      var fetchCount = 0;
      final gateA = Completer<Map<String, dynamic>>();
      final gateB = Completer<Map<String, dynamic>>();

      Future<CacheResult<Map<String, dynamic>>> read(
        String key,
        Completer<Map<String, dynamic>> gate,
      ) =>
          cachedRead<Map<String, dynamic>>(
            key: key,
            store: store,
            fetch: () {
              fetchCount++;
              return gate.future;
            },
            toJson: (v) => v,
            fromJson: (m) => m,
          );

      final day = read('GET:/cycle/day/2026-06-14', gateA);
      final symptoms = read('GET:/symptoms?day=2026-06-14', gateB);
      gateA.complete({'id': 'day'});
      gateB.complete({'id': 'symptoms'});

      final dayResult = await day as Fresh<Map<String, dynamic>>;
      final symptomsResult = await symptoms as Fresh<Map<String, dynamic>>;

      expect(fetchCount, 2, reason: 'distinct keys are distinct requests');
      expect(dayResult.value['id'], 'day');
      expect(
        symptomsResult.value['id'],
        'symptoms',
        reason: 'a key-blind guard would hand this caller the day\'s value',
      );
    });

    test(
        'a failed in-flight read clears the guard: the NEXT read issues a new fetch',
        () async {
      final store = await _buildStore(tempDir, () => baseTime);
      const key = 'GET:/cycle/calendar?month=2026-06';
      var fetchCount = 0;

      Future<CacheResult<Map<String, dynamic>>> read(
        Future<Map<String, dynamic>> Function() answer,
      ) =>
          cachedRead<Map<String, dynamic>>(
            key: key,
            store: store,
            fetch: () {
              fetchCount++;
              return answer();
            },
            toJson: (v) => v,
            fromJson: (m) => m,
          );

      // Two concurrent readers share one FAILING request (no cache → the read
      // resolves to NetworkRequired rather than throwing).
      final failGate = Completer<Map<String, dynamic>>();
      final a = read(() => failGate.future);
      final b = read(() => failGate.future);
      failGate.completeError(_networkError());
      final failed = await Future.wait([a, b]);

      expect(fetchCount, 1);
      expect(failed[0], isA<NetworkRequired<Map<String, dynamic>>>());
      expect(failed[1], isA<NetworkRequired<Map<String, dynamic>>>());

      // The key must NOT be stranded: a later read tries the network again.
      final recovered = await read(() async => {'id': 'recovered'});

      expect(fetchCount, 2, reason: 'a settled failure must not poison the key');
      expect(recovered, isA<Fresh<Map<String, dynamic>>>());
      expect((recovered as Fresh<Map<String, dynamic>>).value['id'], 'recovered');
    });

    test(
        'an in-flight read that THROWS clears the guard and rejects every joiner',
        () async {
      final store = await _buildStore(tempDir, () => baseTime);
      const key = 'GET:/settings/cycle';
      var fetchCount = 0;

      Future<CacheResult<Map<String, dynamic>>> read(
        Future<Map<String, dynamic>> Function() answer,
      ) =>
          cachedRead<Map<String, dynamic>>(
            key: key,
            store: store,
            fetch: () {
              fetchCount++;
              return answer();
            },
            toJson: (v) => v,
            fromJson: (m) => m,
          );

      // A ValidationFailure is real: cachedRead rethrows it instead of masking
      // it as offline, so the shared future completes with an ERROR.
      final failGate = Completer<Map<String, dynamic>>();
      final a = read(() => failGate.future);
      final b = read(() => failGate.future);
      failGate.completeError(const ValidationFailure(message: 'bad input'));

      await expectLater(a, throwsA(isA<ValidationFailure>()));
      await expectLater(
        b,
        throwsA(isA<ValidationFailure>()),
        reason: 'the joiner must see the error, not hang or get a value',
      );
      expect(fetchCount, 1);

      // …and the guard is gone, so the key still works afterwards.
      final recovered = await read(() async => {'id': 'recovered'});
      expect(fetchCount, 2);
      expect((recovered as Fresh<Map<String, dynamic>>).value['id'], 'recovered');
    });

    test('the guard is per-store: two stores never join each other\'s request',
        () async {
      // Every other test in this group builds ONE store, so a module-global
      // `Map<String, Future>` keyed by cache key alone would pass them all.
      // The failure it hides: two ProviderScopes with different CacheStores
      // both read GET:/me, the second joins the first's future and gets the
      // value — but its OWN store is never written through, so it misses on
      // every subsequent read, forever.
      final storeA = MockCacheStore();
      final storeB = MockCacheStore();
      for (final store in [storeA, storeB]) {
        when(() => store.isFresh(any())).thenReturn(false);
        when(() => store.getJson(any())).thenReturn(null);
        when(() => store.putJson(any(), any(), ttl: any(named: 'ttl')))
            .thenAnswer((_) async {});
      }

      var fetchCount = 0;
      final gate = Completer<Map<String, dynamic>>();

      Future<CacheResult<Map<String, dynamic>>> read(CacheStore store) =>
          cachedRead<Map<String, dynamic>>(
            key: CacheKeys.profile,
            store: store,
            fetch: () {
              fetchCount++;
              return gate.future;
            },
            toJson: (v) => v,
            fromJson: (m) => m,
          );

      final a = read(storeA);
      final b = read(storeB);
      gate.complete({'id': '1'});
      await Future.wait([a, b]);

      expect(fetchCount, 2, reason: 'different stores are different caches');
      // The decisive assertion: EACH store was populated. A key-only guard
      // leaves storeB empty even though its caller got a value.
      verify(() => storeA.putJson(
            CacheKeys.profile,
            any(),
            ttl: any(named: 'ttl'),
          )).called(1);
      verify(() => storeB.putJson(
            CacheKeys.profile,
            any(),
            ttl: any(named: 'ttl'),
          )).called(1);
    });

    test('a completed read does not de-duplicate a later, separate read',
        () async {
      // Sanity: de-dup is per burst, not a second cache layer. Without this,
      // "one fetch" could be satisfied by never fetching again at all.
      var now = baseTime;
      final store = await _buildStore(tempDir, () => now);
      const key = 'GET:/me';
      var fetchCount = 0;

      Future<CacheResult<Map<String, dynamic>>> read() =>
          cachedRead<Map<String, dynamic>>(
            key: key,
            store: store,
            fetch: () async {
              fetchCount++;
              return {'id': '$fetchCount'};
            },
            toJson: (v) => v,
            fromJson: (m) => m,
            ttl: const Duration(minutes: 5),
          );

      await read();
      // Past the TTL, so the cache short-circuit does not hide the second call.
      now = baseTime.add(const Duration(minutes: 6));
      await read();

      expect(fetchCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  // cachedWrite — writes never queue
  // -------------------------------------------------------------------------

  group('cachedWrite — writes never queue', () {
    test(
      'on network failure: throws the Failure and leaves NO pending entry in box',
      () async {
        final store = await _buildStore(tempDir, () => baseTime);
        const invalidateKey = 'GET:/me:';

        // Pre-populate so we can confirm it's not modified
        await store.putJson(invalidateKey, {'id': 'original'}, ttl: const Duration(hours: 1));

        // cachedWrite with a failing network call
        Object? caught;
        try {
          await cachedWrite(
            store: store,
            invalidateKeys: [invalidateKey],
            write: () async => throw _networkError(),
          );
        } catch (e) {
          caught = e;
        }

        // Must have thrown a typed Failure
        expect(caught, isA<Failure>());
        expect(caught, isA<NetworkFailure>());

        // The original cache entry must be INTACT (no pending write entry persisted)
        final cached = store.getJson(invalidateKey);
        expect(
          cached,
          isNotNull,
          reason: 'The original cached value should remain untouched after a failed write',
        );
        expect(cached!['id'], 'original');
      },
    );

    test('on network success: invalidates all specified keys', () async {
      final store = await _buildStore(tempDir, () => baseTime);
      const key1 = 'GET:/me:';
      const key2 = 'GET:/settings:';

      await store.putJson(key1, {'a': 1}, ttl: const Duration(hours: 1));
      await store.putJson(key2, {'b': 2}, ttl: const Duration(hours: 1));

      await cachedWrite(
        store: store,
        invalidateKeys: [key1, key2],
        write: () async {},
      );

      // Both keys must be invalidated
      expect(store.getJson(key1), isNull);
      expect(store.getJson(key2), isNull);
    });
  });
}
