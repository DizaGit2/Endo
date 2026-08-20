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
