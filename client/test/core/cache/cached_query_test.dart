// Tests for cachedRead / cachedWrite (cached_query.dart) — TDD RED phase.
//
// CacheStore is used via a real temp-dir backed Hive instance (same as
// hive_boot_test). DioException / Failure are used directly.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

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
