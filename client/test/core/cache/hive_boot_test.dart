// Tests for CacheStore (hive_boot.dart) — TDD RED phase.
//
// Uses a real temp dir for Hive (dart:io is available in flutter test).
// FlutterSecureStorage is mocked with mocktail (key-bootstrap tests) or a
// simple in-memory fake (encryption-at-rest test, which needs the key to
// persist between two initHive calls in the same test).
// A fixed clock is injected for deterministic freshness assertions.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// ---------------------------------------------------------------------------
// In-memory fake secure storage (used where key must survive across calls)
// ---------------------------------------------------------------------------

/// Simple fake that stores key/value pairs in memory — behaves like a real
/// FlutterSecureStorage without any platform-channel involvement.
///
/// We use [noSuchMethod] to satisfy the interface and only override
/// [read] and [write] with explicit in-memory behaviour.
class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final _map = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _map[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }
}

// ---------------------------------------------------------------------------
// Fixed-clock helpers
// ---------------------------------------------------------------------------

/// A simple clock abstraction for injecting a fixed "now".
typedef Clock = DateTime Function();

// ---------------------------------------------------------------------------
// Helper to set up a fresh CacheStore with a temp dir
// ---------------------------------------------------------------------------

Future<TestEnv> buildEnv({
  required Directory dir,
  required MockFlutterSecureStorage storage,
  required Clock clock,
}) async {
  // initHive returns the opened encrypted box
  final store = await initHive(
    path: dir.path,
    storage: storage,
    clock: clock,
  );
  return TestEnv(store: store, dir: dir);
}

class TestEnv {
  const TestEnv({required this.store, required this.dir});
  final CacheStore store;
  final Directory dir;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockFlutterSecureStorage mockStorage;
  late Directory tempDir;
  final baseTime = DateTime.utc(2026, 6, 14, 12, 0, 0);

  setUp(() async {
    mockStorage = MockFlutterSecureStorage();
    tempDir = Directory.systemTemp.createTempSync('hive_test_');

    // Default: no stored key → generate fresh
    when(
      () => mockStorage.read(key: any(named: 'key')),
    ).thenAnswer((_) async => null);

    when(
      () => mockStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    // Close all Hive boxes and clean up temp dir
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // -------------------------------------------------------------------------
  // initHive / key bootstrap
  // -------------------------------------------------------------------------

  group('initHive — key bootstrap', () {
    test('generates and persists key when absent from secure storage', () async {
      await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      // key must have been written to secure storage
      verify(
        () => mockStorage.write(
          key: 'hive_cache_key',
          value: any(named: 'value'),
        ),
      ).called(1);
    });

    test('reads existing key without writing again', () async {
      // Arrange: a pre-existing 32-byte AES key in storage
      final key = List<int>.generate(32, (i) => i + 1);
      final encoded = base64.encode(key);

      when(
        () => mockStorage.read(key: 'hive_cache_key'),
      ).thenAnswer((_) async => encoded);

      await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      verifyNever(
        () => mockStorage.write(
          key: 'hive_cache_key',
          value: any(named: 'value'),
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // CacheStore — put/get round-trip
  // -------------------------------------------------------------------------

  group('CacheStore.putJson / getJson', () {
    test('round-trips a JSON map', () async {
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      await env.store.putJson(
        'GET:/users:',
        {'id': '123', 'name': 'Alice'},
        ttl: const Duration(minutes: 5),
      );

      final result = env.store.getJson('GET:/users:');
      expect(result, isNotNull);
      expect(result!['id'], '123');
      expect(result['name'], 'Alice');
    });

    test('getJson returns null for unknown key', () async {
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      expect(env.store.getJson('no:such:key'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // CacheStore — isFresh
  // -------------------------------------------------------------------------

  group('CacheStore.isFresh', () {
    test('returns true when entry is within TTL', () async {
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      await env.store.putJson(
        'GET:/me:',
        {'user': 'bob'},
        ttl: const Duration(minutes: 10),
      );

      // Clock still at baseTime — should be fresh
      expect(env.store.isFresh('GET:/me:'), isTrue);
    });

    test('returns false after TTL has elapsed', () async {
      // Clock starts at baseTime
      var now = baseTime;
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => now,
      );

      await env.store.putJson(
        'GET:/me:',
        {'user': 'bob'},
        ttl: const Duration(minutes: 5),
      );

      // Advance clock by 6 minutes (past the 5-minute TTL)
      now = baseTime.add(const Duration(minutes: 6));

      expect(env.store.isFresh('GET:/me:'), isFalse);
    });

    test('returns false for unknown key', () async {
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      expect(env.store.isFresh('non:existent:key'), isFalse);
    });

    test('returns false when putJson called without ttl', () async {
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      // No TTL → never fresh
      await env.store.putJson('GET:/x:', {'k': 'v'});

      expect(env.store.isFresh('GET:/x:'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // CacheStore — invalidate
  // -------------------------------------------------------------------------

  group('CacheStore.invalidate', () {
    test('removes the key so getJson returns null afterward', () async {
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      await env.store.putJson(
        'GET:/items:',
        {'count': 3},
        ttl: const Duration(minutes: 5),
      );
      expect(env.store.getJson('GET:/items:'), isNotNull);

      await env.store.invalidate('GET:/items:');

      expect(env.store.getJson('GET:/items:'), isNull);
    });

    test('invalidating a non-existent key does not throw', () async {
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      // Should not throw
      await expectLater(
        env.store.invalidate('non:existent:key'),
        completes,
      );
    });
  });

  // -------------------------------------------------------------------------
  // CacheStore — purge
  // -------------------------------------------------------------------------

  group('CacheStore.purge', () {
    test('clears all entries from the box', () async {
      final env = await buildEnv(
        dir: tempDir,
        storage: mockStorage,
        clock: () => baseTime,
      );

      await env.store.putJson('key1', {'a': 1}, ttl: const Duration(hours: 1));
      await env.store.putJson('key2', {'b': 2}, ttl: const Duration(hours: 1));
      await env.store.putJson('key3', {'c': 3}, ttl: const Duration(hours: 1));

      await env.store.purge();

      expect(env.store.getJson('key1'), isNull);
      expect(env.store.getJson('key2'), isNull);
      expect(env.store.getJson('key3'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Encryption-at-rest exit criterion
  // -------------------------------------------------------------------------

  group('CacheStore — encryption at rest', () {
    test(
      'raw box file bytes do NOT contain the plaintext value; '
      'reopen with correct key reads the value back',
      () async {
        // A recognizable plaintext sentinel
        const sentinel = 'PLAINTEXT_SENTINEL_LUMEN_2026';

        // Use a fake that persists the AES key in memory so it survives
        // across the two initHive() calls within the same test.
        final fakeStorage = _FakeSecureStorage();
        final encryptedDir = Directory.systemTemp.createTempSync('hive_enc_test_');

        try {
          // ── First open: write sentinel value ──────────────────────────────
          final store1 = await initHive(
            path: encryptedDir.path,
            storage: fakeStorage,
            clock: () => baseTime,
          );

          await store1.putJson(
            'GET:/sentinel:',
            {'secret': sentinel},
            ttl: const Duration(hours: 1),
          );

          // Close so all data is flushed to disk files
          await Hive.close();

          // ── Check raw bytes ───────────────────────────────────────────────
          final files = encryptedDir.listSync(recursive: true).whereType<File>();
          final boxFiles = files.where(
            (f) =>
                f.path.endsWith('.hive') ||
                f.path.contains('box_cache'),
          );

          expect(
            boxFiles,
            isNotEmpty,
            reason: 'No Hive box file found — did initHive open the box?',
          );

          var sentinelFoundInRaw = false;
          for (final file in boxFiles) {
            final bytes = file.readAsBytesSync();
            final raw = utf8.decode(bytes, allowMalformed: true);
            if (raw.contains(sentinel)) {
              sentinelFoundInRaw = true;
              break;
            }
          }
          expect(
            sentinelFoundInRaw,
            isFalse,
            reason: 'Plaintext sentinel found in raw box file — box is NOT encrypted!',
          );

          // ── Reopen with the same key (fakeStorage retains it) ─────────────
          final store2 = await initHive(
            path: encryptedDir.path,
            storage: fakeStorage,
            clock: () => baseTime,
          );

          final result = store2.getJson('GET:/sentinel:');
          expect(result, isNotNull, reason: 'Value should be readable after reopening with correct key');
          expect(result!['secret'], sentinel);
        } finally {
          await Hive.close();
          try {
            encryptedDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      },
    );
  });
}
