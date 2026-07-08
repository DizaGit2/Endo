// ---------------------------------------------------------------------------
// Hive encrypted cache bootstrap + CacheStore
// ---------------------------------------------------------------------------
//
// Design (§4.1 — online-only):
//   • Encrypted box "box_cache" using a 32-byte AES key from
//     FlutterSecureStorage.
//   • CacheStore wraps the box: put/get with TTL metadata, isFresh via
//     injected clock, invalidate, purge (called on logout).
//   • Keys are caller-chosen strings (convention: "METHOD:path:querystring").
//   • The box is opened once at app startup via initHive(); the returned
//     CacheStore is exposed via cacheStoreProvider.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kBoxName = 'box_cache';
const _kStorageKey = 'hive_cache_key';

// ---------------------------------------------------------------------------
// Clock typedef (injectable for testing)
// ---------------------------------------------------------------------------

/// A simple clock abstraction.  In production: `() => DateTime.now()`.
/// In tests: inject a fixed or mutable clock for deterministic assertions.
typedef Clock = DateTime Function();

// ---------------------------------------------------------------------------
// initHive
// ---------------------------------------------------------------------------

/// Initialises Hive, bootstraps the AES key, and opens the encrypted cache
/// box.  Returns a [CacheStore] wrapping that box.
///
/// Parameters:
/// - [path]: directory for Hive storage.  Pass a temp dir in tests;
///   in the real app call `Hive.initFlutter()` directly before
///   calling this (or pass `null` to use the Flutter default path).
/// - [storage]: the [FlutterSecureStorage] instance (inject a mock in tests).
/// - [clock]: clock function (inject a fixed clock in tests).
Future<CacheStore> initHive({
  String? path,
  FlutterSecureStorage? storage,
  Clock? clock,
}) async {
  // Initialise Hive at the given path (tests) or default Flutter path (app).
  if (path != null) {
    Hive.init(path);
  }
  // If path == null, caller must have already called Hive.initFlutter().

  final secureStorage = storage ??
      const FlutterSecureStorage(
        aOptions: AndroidOptions(),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  final effectiveClock = clock ?? DateTime.now;

  // ── AES key bootstrap ──────────────────────────────────────────────────
  final List<int> aesKey;

  final stored = await secureStorage.read(key: _kStorageKey);
  if (stored != null) {
    aesKey = base64.decode(stored);
  } else {
    final generated = Hive.generateSecureKey();
    await secureStorage.write(
      key: _kStorageKey,
      value: base64.encode(generated),
    );
    aesKey = generated;
  }

  // ── Open encrypted box ─────────────────────────────────────────────────
  final box = await Hive.openBox<Map<dynamic, dynamic>>(
    _kBoxName,
    encryptionCipher: HiveAesCipher(aesKey),
  );

  return CacheStore(box: box, clock: effectiveClock);
}

// ---------------------------------------------------------------------------
// CacheStore
// ---------------------------------------------------------------------------

/// Wraps an encrypted Hive box and provides put/get with TTL, freshness
/// checking, per-key invalidation, and full purge (used on logout).
///
/// Stored entry shape:
/// ```json
/// { "data": { ... }, "fetchedAt": "2026-06-14T12:00:00.000Z", "ttlMs": 300000 }
/// ```
///
/// When [ttl] is null the entry is written without a TTL; [isFresh] returns
/// `false` for such entries (they can still be served as Stale).
class CacheStore {
  CacheStore({
    required Box<Map<dynamic, dynamic>> box,
    required Clock clock,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  })  : _box = box, // ignore: prefer_initializing_formals
        _clock = clock; // ignore: prefer_initializing_formals

  final Box<Map<dynamic, dynamic>> _box;
  final Clock _clock;

  // ── Write ────────────────────────────────────────────────────────────────

  /// Stores [value] under [key].  If [ttl] is provided the entry is
  /// considered fresh until `fetchedAt + ttl`.
  Future<void> putJson(
    String key,
    Map<String, dynamic> value, {
    Duration? ttl,
  }) async {
    final entry = <String, dynamic>{
      'data': value,
      'fetchedAt': _clock().toUtc().toIso8601String(),
      if (ttl != null) 'ttlMs': ttl.inMilliseconds,
    };
    await _box.put(key, entry);
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  /// Returns the stored data map for [key], or `null` if absent.
  Map<String, dynamic>? getJson(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    final data = raw['data'];
    if (data is Map<String, dynamic>) return data;
    // Hive can return Map<dynamic,dynamic> — cast it.
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  // ── Freshness ────────────────────────────────────────────────────────────

  /// Returns `true` iff the entry for [key] exists, has a TTL, and
  /// `fetchedAt + ttl > now`.
  bool isFresh(String key) {
    final raw = _box.get(key);
    if (raw == null) return false;

    final ttlMs = raw['ttlMs'];
    if (ttlMs == null) return false;

    final fetchedAtStr = raw['fetchedAt'];
    if (fetchedAtStr == null) return false;

    final fetchedAt = DateTime.tryParse(fetchedAtStr.toString());
    if (fetchedAt == null) return false;

    final expiry = fetchedAt.add(Duration(milliseconds: (ttlMs as num).toInt()));
    return _clock().isBefore(expiry);
  }

  // ── Invalidate ───────────────────────────────────────────────────────────

  /// Removes the entry for [key] (no-op if absent).
  Future<void> invalidate(String key) => _box.delete(key);

  // ── Purge ────────────────────────────────────────────────────────────────

  /// Clears all entries from the box.  Called on logout.
  Future<void> purge() => _box.clear();
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Provides the [CacheStore] singleton.
///
/// This provider has no real default: the [CacheStore] can only be produced
/// asynchronously (via [initHive]), so app startup MUST override it at the
/// root [ProviderScope] once [initHive] resolves — see `main.dart`:
/// ```dart
/// final store = await initHive();
/// runApp(ProviderScope(
///   overrides: [cacheStoreProvider.overrideWithValue(store)],
///   child: const LumenApp(),
/// ));
/// ```
/// Tests override it the same way, per-container/per-ProviderScope, which
/// keeps each test's cache fully isolated (no shared module-global state).
/// Reading it un-overridden is a programmer error and fails loudly.
final cacheStoreProvider = Provider<CacheStore>(
  (_) => throw UnimplementedError(
    'cacheStoreProvider must be overridden at the root ProviderScope',
  ),
);
