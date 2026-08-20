// ---------------------------------------------------------------------------
// CachedQuery — online-only stale-while-revalidate read helper (§4.1)
// ---------------------------------------------------------------------------
//
// Design:
//   • cachedRead<T>: attempts the network every time unless the entry is
//     fresh (isFresh == true → short-circuit and return Fresh from cache).
//     On network failure: return Stale(cached) if a cached value exists,
//     else return NetworkRequired(failure).
//   • cachedWrite<T>: performs the network write and returns its result.  On
//     success, invalidates the given keys AND/OR keys derived from the
//     result (P4b-T19: a batch write whose invalidation depends on the
//     server-derived response, e.g. `SymptomsRepository.createBatch`).  On an
//     AMBIGUOUS failure (S-6 — a NetworkFailure/ServerFailure that may have
//     landed after the server already committed), an opt-in key list is
//     invalidated too.  On any other failure, rethrows the typed Failure
//     WITHOUT persisting any pending-write entry (online-only contract:
//     writes never queue).
//   • In-flight de-duplication: concurrent cachedReads of the SAME key on the
//     same store share one request (see _inflightFor).

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
// In-flight de-duplication
// ---------------------------------------------------------------------------

/// The reads currently awaiting the network, per [CacheStore], keyed by cache
/// key.
///
/// Two providers can want the same key at the same instant — today
/// `ProfileController` and the router's onboarding gate both read `GET:/me` on
/// a cold start, and neither can see a cache entry the other has not written
/// yet. Without a guard that is N round-trips for one logical read.
///
/// This is the same single-flight idiom as `AuthInterceptor._doRefresh`
/// (`core/auth/auth_interceptor.dart`): the first caller stores its future, the
/// rest join it, and `whenComplete` clears the slot. `whenComplete` — not
/// `then` — is what keeps a FAILED read from stranding the key forever.
///
/// An [Expando] rather than a module-global map because the guard is per-store
/// state: `cachedRead` is a free function, so it has no instance field to hang
/// it on, and keying by cache key alone would let two stores (a test's temp box
/// and another test's) collide on `GET:/me`. Entries are dropped with the store
/// they belong to.
final Expando<Map<String, Future<Object?>>> _inflightReads =
    Expando<Map<String, Future<Object?>>>('cachedRead in-flight');

Map<String, Future<Object?>> _inflightFor(CacheStore store) =>
    _inflightReads[store] ??= <String, Future<Object?>>{};

// ---------------------------------------------------------------------------
// cachedRead
// ---------------------------------------------------------------------------

/// Stale-while-revalidate read helper.
///
/// Semantics:
/// 1. If [store.isFresh(key)] is true → return [Fresh] from cache immediately
///    (no network call).
/// 2. If an identical read is already in flight → join it; no second request
///    is issued and both callers get the same outcome (value OR error).
/// 3. Otherwise attempt the network [fetch].
/// 4. On success → write-through via [store.putJson] and return [Fresh].
/// 5. On a connectivity/transient-server failure ([NetworkFailure] /
///    [ServerFailure]) WITH a cached value → [Stale]; WITHOUT one →
///    [NetworkRequired].
/// 6. Any other failure (validation / auth / not-found / unknown) is REAL and
///    propagates to the caller — it is never masked as stale/offline.
///
/// Build [key] with `CacheKeys` (`core/cache/cache_keys.dart`) — never with an
/// ad-hoc string — so that a write can name the keys it invalidates.
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

  // ── Join an identical read already in flight ────────────────────────────
  final inflight = _inflightFor(store);
  final joined = inflight[key];
  if (joined != null) {
    return await joined as CacheResult<T>;
  }

  // Registration must happen before the first `await` below, so that a caller
  // running in the same microtask sees it. An async function body runs
  // synchronously up to its first await, so _read starts fetching and returns
  // its future without yielding first.
  final read = _read<T>(
    key: key,
    store: store,
    fetch: fetch,
    toJson: toJson,
    fromJson: fromJson,
    ttl: ttl,
  );

  // `whenComplete`, so a failure clears the slot too — and a BLOCK body, not an
  // arrow: `Map.remove` returns the removed value, and `whenComplete` waits on
  // any Future its callback returns, so an arrow would hand it this very future
  // and deadlock every read.
  final future = read.whenComplete(() {
    inflight.remove(key);
  });
  inflight[key] = future;

  return await future;
}

/// The un-guarded read: everything [cachedRead] does once it owns the request.
Future<CacheResult<T>> _read<T>({
  required String key,
  required CacheStore store,
  required Future<T> Function() fetch,
  required Map<String, dynamic> Function(T) toJson,
  required T Function(Map<String, dynamic>) fromJson,
  required Duration ttl,
}) async {
  // ── Attempt network ─────────────────────────────────────────────────────
  try {
    final value = await fetch();
    // Write-through is best-effort: a cache-write hiccup (e.g. the box was
    // closed by a concurrent logout-purge, disk full) must NOT mask a
    // successful network fetch — the live value is still returned as Fresh.
    try {
      await store.putJson(key, toJson(value), ttl: ttl);
    } catch (_) {
      // Swallow cache-write errors; the fetched value is authoritative.
    }
    return Fresh(value);
  } on DioException catch (e) {
    final failure = mapDioException(e);
    return _resolveFailure<T>(
      store: store,
      key: key,
      failure: failure,
      fromJson: fromJson,
    );
  } on Failure catch (failure) {
    return _resolveFailure<T>(
      store: store,
      key: key,
      failure: failure,
      fromJson: fromJson,
    );
  }
}

/// For connectivity/transient-server failures, falls back to cache: returns
/// [Stale] if a cached entry exists, else [NetworkRequired]. Any other failure
/// (validation/auth/not-found/unknown) is real and is rethrown to the caller
/// rather than being masked as an offline state.
CacheResult<T> _resolveFailure<T>({
  required CacheStore store,
  required String key,
  required Failure failure,
  required T Function(Map<String, dynamic>) fromJson,
}) {
  if (failure is! NetworkFailure && failure is! ServerFailure) {
    throw failure;
  }
  final cached = store.getJson(key);
  if (cached != null) {
    return Stale(fromJson(cached));
  }
  return NetworkRequired(failure);
}

// ---------------------------------------------------------------------------
// cachedWrite
// ---------------------------------------------------------------------------

/// Online-only write helper — GENERALISED at P4b-T19 to return the write's
/// own result and to let invalidation be derived from it.
///
/// Performs the network [write] and returns whatever it produces.
///
/// **Success.** Invalidates the union of the STATIC [invalidateKeys] (known
/// before the write runs — every pre-T19 caller's shape, e.g.
/// `CycleRepository.logEvent` invalidating the CLIENT-supplied `occurredOn`)
/// and whatever [invalidateKeysFor] computes FROM the result (T19's shape:
/// `POST /symptoms` answers with the server-derived `occurredOn`, so the keys
/// cannot be known until the write has already returned — see
/// `SymptomsRepository.createBatch`). Either or both may be supplied; neither
/// is required, so every existing caller compiles unchanged.
///
/// **Ambiguous failure (S-6).** A write can throw AFTER the server has
/// already committed it — a timeout or a dropped connection on the response
/// leg. [invalidateKeysOnAmbiguousFailure] runs in exactly that case, using
/// the SAME test [cachedRead]'s own `_resolveFailure` already uses to decide
/// "this might be transient, not real": a [NetworkFailure] or a
/// [ServerFailure]. Every other [Failure] (validation, auth, conflict,
/// rate-limit, not-found, TLS, unknown) means the server is KNOWN not to have
/// written anything — invalidating there would only cost an extra fetch for
/// no reason, so nothing runs. Defaults to `const []`, so a caller that does
/// not name this parameter keeps the pre-T19 behaviour exactly: no
/// invalidation on any failure at all.
///
/// On [DioException] or a directly-thrown [Failure] (e.g. [write] itself
/// throwing a typed failure for a malformed 2xx body, the existing
/// `getX`/`logEvent` idiom): maps/rethrows the typed [Failure]. NO
/// pending-write entry is ever persisted in the cache box (writes never
/// queue).
Future<T> cachedWrite<T>({
  required CacheStore store,
  required Future<T> Function() write,
  List<String> invalidateKeys = const [],
  List<String> Function(T value)? invalidateKeysFor,
  List<String> invalidateKeysOnAmbiguousFailure = const [],
}) async {
  final T value;
  try {
    value = await write();
  } on DioException catch (e) {
    final failure = mapDioException(e);
    await _invalidateOnAmbiguousFailure(
      store,
      failure,
      invalidateKeysOnAmbiguousFailure,
    );
    throw failure;
  } on Failure catch (failure) {
    await _invalidateOnAmbiguousFailure(
      store,
      failure,
      invalidateKeysOnAmbiguousFailure,
    );
    rethrow;
  }

  // Success: invalidate affected keys so they are re-fetched on next read.
  // A Set so a key present in both sources is invalidated once.
  final keys = <String>{...invalidateKeys, ...?invalidateKeysFor?.call(value)};
  for (final key in keys) {
    await store.invalidate(key);
  }
  return value;
}

/// The S-6 half of [cachedWrite]: invalidates [keys] only when [failure] is
/// the kind that leaves the server's outcome genuinely unknown to the client.
Future<void> _invalidateOnAmbiguousFailure(
  CacheStore store,
  Failure failure,
  List<String> keys,
) async {
  if (failure is! NetworkFailure && failure is! ServerFailure) return;
  for (final key in keys) {
    await store.invalidate(key);
  }
}
