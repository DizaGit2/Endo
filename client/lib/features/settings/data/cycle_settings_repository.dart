import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/core/cache/built_json_codec.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// CycleSettingsRepository
// ---------------------------------------------------------------------------

/// The `/settings/cycle` resource — screen 32's endpoint, and the second half
/// of screen 3's resume.
///
/// **Why an onboarding screen reads a settings endpoint.**
/// `GET /onboarding/state` answers `lastPeriodStart` and none of
/// `avgCycleLengthDays` / `avgPeriodLengthDays` / `regularity`
/// (`ARCHITECTURE.md` §C.0.1, the `POST /onboarding/cycle` row). Screen 3 shows
/// all four. If it read only the onboarding state it would draw the server's
/// *defaults* over two answers the user had already given — the precise state
/// the endpoint became a MERGE in order to prevent. So screen 3 composes two
/// reads, and this is the one the onboarding repository deliberately does not
/// wrap: an endpoint with two client owners diverges the moment the second one
/// is written.
///
/// **Only the read is here.** `PATCH /settings/cycle` belongs to screen 32
/// (T22a) — it carries the C-12 pause state machine and the
/// not-round-trippable response rule, neither of which screen 3 touches, and a
/// write nobody calls is a write nobody tests.
class CycleSettingsRepository {
  const CycleSettingsRepository({
    required LumenApiApi api,
    required CacheStore store,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api, // ignore: prefer_initializing_formals
       _store = store; // ignore: prefer_initializing_formals

  final LumenApiApi _api;
  final CacheStore _store;

  // ── getSettings ────────────────────────────────────────────────────────────

  /// Reads `GET /settings/cycle`.
  ///
  /// Stale-while-revalidate under [CacheKeys.cycleSettings] at the shared
  /// [CacheKeys.ttl] — the key comes from the policy so that a write which must
  /// invalidate this read (`POST /onboarding/cycle` does) cannot spell it
  /// differently.
  ///
  /// **A user with no settings row is a 200, not a 404**: the server answers
  /// the documented defaults (28 / null / `somewhat`) with `createdAt` and
  /// `updatedAt` null, and those two nulls are the only thing that
  /// distinguishes "untouched defaults" from "a saved row that equals them".
  /// This repository passes that through untouched and interprets nothing.
  Future<CacheResult<CycleSettingsResponse>> getSettings() {
    return cachedRead<CycleSettingsResponse>(
      key: CacheKeys.cycleSettings,
      store: _store,
      fetch: () async {
        final response = await _api.settingsCycleGet();
        final body = response.data;
        if (body == null) {
          // A 200 with no body is a server fault. Typed, so it never reaches a
          // screen as a raw TypeError from a force-unwrap.
          throw const ServerFailure(
            'The server returned empty cycle settings.',
          );
        }
        return body;
      },
      toJson: (value) => toCacheJson(CycleSettingsResponse.serializer, value),
      fromJson: (map) => fromCacheJson(CycleSettingsResponse.serializer, map),
      ttl: CacheKeys.ttl,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [CycleSettingsRepository] wired to the shared API client and cache
/// store.
final cycleSettingsRepositoryProvider = Provider<CycleSettingsRepository>((
  ref,
) {
  return CycleSettingsRepository(
    api: ref.watch(lumenApiProvider),
    store: ref.watch(cacheStoreProvider),
  );
});
