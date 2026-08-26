import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/update_me_request.dart';
import 'package:lumen/core/cache/built_json_codec.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// MeRepository
// ---------------------------------------------------------------------------

/// Repository for the /me endpoint.
///
/// - [getMe]    : stale-while-revalidate via [cachedRead]; encrypts the
///                profile in the Hive cache box.
/// - [updateMe] : online-only write via [cachedWrite]; invalidates 'GET:/me'
///                so the next [getMe] re-fetches fresh data.
/// - [deleteMe] : online-only write via [cachedWrite]; on acceptance it
///                PURGES the cache box rather than naming keys — see its own
///                dartdoc for why an erasure cannot be expressed as a key list.
class MeRepository {
  const MeRepository({
    required LumenApiApi api,
    required CacheStore store,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api, // ignore: prefer_initializing_formals
       _store = store; // ignore: prefer_initializing_formals

  final LumenApiApi _api;
  final CacheStore _store;

  /// The profile key comes from the shared policy (`CacheKeys`) rather than
  /// a literal here, so a write elsewhere that must invalidate the profile
  /// cannot spell the key differently from this read.
  static const _key = CacheKeys.profile;

  // ── getMe ──────────────────────────────────────────────────────────────────

  /// Fetches the current user's profile.
  ///
  /// Returns [Fresh] on a successful network call (result is also cached).
  /// Returns [Stale] if the network fails but a cached value exists.
  /// Returns [NetworkRequired] if no network AND no cache.
  Future<CacheResult<MeResponse>> getMe() {
    return cachedRead<MeResponse>(
      key: _key,
      store: _store,
      fetch: () async {
        final response = await _api.meGet();
        final body = response.data;
        if (body == null) {
          // A 200 with an empty/null body is a server fault — map it to a typed
          // failure instead of force-unwrapping into a raw TypeError that would
          // escape the SWR layer.
          throw const ServerFailure('The server returned an empty profile.');
        }
        return body;
      },
      toJson: (value) => toCacheJson(MeResponse.serializer, value),
      fromJson: (map) => fromCacheJson(MeResponse.serializer, map),
      ttl: CacheKeys.ttl,
    );
  }

  // ── updateMe ───────────────────────────────────────────────────────────────

  /// Updates the current user's profile.
  ///
  /// Calls [PATCH /me] online-only. On success, invalidates the cached 'GET:/me'
  /// entry so the next call to [getMe] will re-fetch.
  /// Throws a typed [Failure] on network error (no write is cached).
  Future<void> updateMe({String? displayName}) {
    return cachedWrite(
      store: _store,
      write: () async {
        final request = UpdateMeRequest((b) => b..displayName = displayName);
        await _api.mePatch(updateMeRequest: request);
      },
      invalidateKeys: [_key],
    );
  }

  // ── deleteMe ───────────────────────────────────────────────────────────────

  /// Asks the server to erase this account and the data in it.
  ///
  /// Calls `DELETE /me` online-only. **The response is `202 Accepted`, and
  /// that is all this method can report: the server enqueues the erasure and
  /// answers before it has run.** Returning normally therefore means *the
  /// request was accepted*, never *the data is gone* — a caller that renders
  /// this outcome must not say otherwise (see `privacy_screen.dart`'s
  /// `kPrivacyErasureRequestedMessage`).
  ///
  /// **On acceptance the whole cache box is PURGED, not a key list, and that
  /// is a deliberate departure from every other write in this app.** The house
  /// shape is `cachedWrite(invalidateKeys: …)`, which works because a write
  /// can NAME what it touches — `CacheKeys.profile` for [updateMe],
  /// `CacheKeys.keysForDate` for a dated write. An erasure touches
  /// *everything*, and under ruling R-05 every other key is derived from a
  /// DATE, so the affected set is unbounded and cannot be enumerated:
  /// [CacheStore] exposes exact-key `invalidate` and no iteration. The only
  /// expression of "all of it" this store has is [CacheStore.purge], so that
  /// is what an accepted erasure uses. It does not depend on the caller
  /// signing out afterwards — `AuthController.logout` purges too, but that is
  /// the SESSION's teardown, and the decrypted health data of an account whose
  /// erasure has been accepted must not sit on this disk waiting for it.
  ///
  /// **A refused request clears nothing at all — including the ambiguous
  /// ones.** A [NetworkFailure] or [ServerFailure] can hide a request that
  /// reached the server and lost its response (S-6), which is why dated writes
  /// pass `invalidateKeysOnAmbiguousFailure`. This one deliberately does not:
  /// there the cost of guessing wrong is one extra fetch, here it is emptying
  /// a live user's local data over a request that most likely failed outright.
  /// The ambiguous case is self-healing without it — the identity is disabled
  /// by the same call, so the next authenticated read answers 401, and
  /// `dioProvider`'s `onAuthLost` runs `logout()`, which purges.
  ///
  /// Throws the typed [Failure] `mapDioException` produces for every refusal;
  /// no pending write is ever persisted (online-only: writes never queue).
  Future<void> deleteMe() async {
    await cachedWrite<void>(
      store: _store,
      write: () async {
        await _api.meDelete();
      },
    );
    await _store.purge();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [MeRepository] wired to the shared API client and cache store.
final meRepositoryProvider = Provider<MeRepository>((ref) {
  return MeRepository(
    api: ref.watch(lumenApiProvider),
    store: ref.watch(cacheStoreProvider),
  );
});
