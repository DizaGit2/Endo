// ---------------------------------------------------------------------------
// CachedQuery — online-only stale-while-revalidate read helper (§4.1)
// ---------------------------------------------------------------------------
//
// Design:
//   • cachedRead<T>: attempts the network every time unless the entry is
//     fresh (isFresh == true → short-circuit and return Fresh from cache).
//     On network failure: return Stale(cached) if a cached value exists,
//     else return NetworkRequired(failure).
//   • cachedWrite: performs the network write and, on success, invalidates
//     the given keys.  On failure, rethrows the typed Failure WITHOUT
//     persisting any pending-write entry (online-only contract: writes never
//     queue).

import 'package:dio/dio.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/error_mapper.dart';
import 'package:lumen/core/error/failure.dart';

// ---------------------------------------------------------------------------
// CacheResult sealed class
// ---------------------------------------------------------------------------

/// The result of a [cachedRead] call.
sealed class CacheResult<T> {
  const CacheResult();
}

/// The value is authoritative (just fetched from the network, or served from
/// a fresh cache entry without hitting the network).
final class Fresh<T> extends CacheResult<T> {
  const Fresh(this.value);
  final T value;
}

/// The network was unreachable but a previously cached value is available.
final class Stale<T> extends CacheResult<T> {
  const Stale(this.value);
  final T value;
}

/// Neither a network response nor a cached value is available.
final class NetworkRequired<T> extends CacheResult<T> {
  const NetworkRequired(this.failure);
  final Failure failure;
}

// ---------------------------------------------------------------------------
// cachedRead
// ---------------------------------------------------------------------------

/// Stale-while-revalidate read helper.
///
/// Semantics:
/// 1. If [store.isFresh(key)] is true → return [Fresh] from cache immediately
///    (no network call).
/// 2. Otherwise attempt the network [fetch].
/// 3. On success → write-through via [store.putJson] and return [Fresh].
/// 4. On [DioException] / [NetworkFailure] WITH a cached value → [Stale].
/// 5. On [DioException] / [NetworkFailure] WITHOUT a cached value →
///    [NetworkRequired].
Future<CacheResult<T>> cachedRead<T>({
  required String key,
  required CacheStore store,
  required Future<T> Function() fetch,
  required Map<String, dynamic> Function(T) toJson,
  required T Function(Map<String, dynamic>) fromJson,
  Duration ttl = const Duration(minutes: 5),
}) async {
  // ── Short-circuit: fresh cache ──────────────────────────────────────────
  if (store.isFresh(key)) {
    final cached = store.getJson(key);
    if (cached != null) {
      return Fresh(fromJson(cached));
    }
  }

  // ── Attempt network ─────────────────────────────────────────────────────
  try {
    final value = await fetch();
    // Write-through
    await store.putJson(key, toJson(value), ttl: ttl);
    return Fresh(value);
  } on DioException catch (e) {
    final failure = mapDioException(e);
    return _resolveFailure<T>(store: store, key: key, failure: failure, fromJson: fromJson);
  } on Failure catch (failure) {
    return _resolveFailure<T>(store: store, key: key, failure: failure, fromJson: fromJson);
  }
}

/// Checks cache and returns [Stale] or [NetworkRequired] depending on whether
/// a cached entry exists.
CacheResult<T> _resolveFailure<T>({
  required CacheStore store,
  required String key,
  required Failure failure,
  required T Function(Map<String, dynamic>) fromJson,
}) {
  final cached = store.getJson(key);
  if (cached != null) {
    return Stale(fromJson(cached));
  }
  return NetworkRequired(failure);
}

// ---------------------------------------------------------------------------
// cachedWrite
// ---------------------------------------------------------------------------

/// Online-only write helper.
///
/// Performs the network [write].
/// On success: invalidates all [invalidateKeys] in [store] (so the next read
/// fetches fresh data).
/// On [DioException]: maps to a typed [Failure] and rethrows it.  NO pending-
/// write entry is ever persisted in the cache box (writes never queue).
Future<void> cachedWrite({
  required CacheStore store,
  required Future<void> Function() write,
  List<String> invalidateKeys = const [],
}) async {
  try {
    await write();
  } on DioException catch (e) {
    // Map to typed Failure and rethrow — no caching of failed write state.
    throw mapDioException(e);
  }
  // Success: invalidate affected keys so they are re-fetched on next read.
  for (final key in invalidateKeys) {
    await store.invalidate(key);
  }
}
