// ---------------------------------------------------------------------------
// CheckinRepository — `POST /checkin/quick`, screen 9's write (P4b-T18)
// ---------------------------------------------------------------------------
//
// The first client write of the logging half. `POST /checkin/quick` is a
// MERGE onto `cycle_day_logs` — an omitted field is left alone, not cleared —
// and it has **no clear affordance at all**: nothing this repository sends
// can ever be removed by the user, on any screen, in any later phase. See
// `quick_checkin_controller.dart` for the anti-fabrication rules this file's
// caller must uphold; this file's own job is narrower — send exactly what the
// caller says was touched, and invalidate the right day afterward.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/quick_checkin_request.dart';
import 'package:lumen/api/model/quick_checkin_response.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

class CheckinRepository {
  const CheckinRepository({
    required LumenApiApi api,
    required CacheStore store,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api, // ignore: prefer_initializing_formals
       _store = store; // ignore: prefer_initializing_formals

  final LumenApiApi _api;
  final CacheStore _store;

  // ── quickCheckin ───────────────────────────────────────────────────────

  /// Calls `POST /checkin/quick`.
  ///
  /// **[touchedPain]/[touchedMood] decide what is SENT, never [pain]/[mood]
  /// themselves.** The generated [QuickCheckinRequest] serializer already
  /// omits a null member from the wire (`quick_checkin_request.dart:47,:54`),
  /// so leaving the builder field unset is the only correct representation
  /// of "not touched" — and the only way to reach that state from here is to
  /// not assign it at all. `pain: 0` is a real, sendable value (D-08); a
  /// caller that touched pain and left it at 0 (or cleared it back to `null`
  /// via [LumenIntensityScale]'s clear gesture) still passes `touchedPain:
  /// true` — this method does not re-derive "touched" from whether [pain] is
  /// null, because 0 and "cleared" are BOTH legitimate values of a touched
  /// field and neither may be mistaken for "never touched".
  ///
  /// **Invalidation uses the RESPONSE's own `day`, never [fallbackDay],
  /// whenever the response supplies one.** `sessionTodayProvider`'s value is
  /// pinned for the whole app session; the server writes its own
  /// `day.Today`. Across a local-midnight write the two can disagree, and
  /// invalidating the pinned day would make the write invisible: the
  /// dashboard re-derives its month buckets from the SAME pinned value, so a
  /// write landing on the server's "today" would sit under a cache key
  /// nothing re-reads. [fallbackDay] is used only if the response's own
  /// `day` is absent (defensive — the contract does not promise it is
  /// omittable) or if the write's outcome is ambiguous (see below).
  ///
  /// **`cachedWrite`'s own static `invalidateKeys` parameter is evaluated
  /// eagerly, before `write` runs** (`cached_query.dart:249`), so passing it
  /// still could not see the response's `day` at all — this method
  /// invalidates by hand afterward, the shape `cycle_repository.dart:276-280`
  /// (soft-delete 404) already uses for the same reason. **P4b-T19 later
  /// added a SECOND, deferred option, `invalidateKeysFor`**
  /// (`cached_query.dart:250`), computed FROM the write's own result — the
  /// shape this method's own `saved.day ?? fallbackDay` fallback below is
  /// hand-rolling. This repository predates that parameter and has not been
  /// migrated to it; the two invalidation paths below remain hand-rolled on
  /// purpose until that migration happens, not because the parameter could
  /// not serve them.
  ///
  /// **Any [Failure] reaching this method — from `cachedWrite`'s own
  /// `on DioException` mapping, OR from the empty-body guard below, which
  /// throws a bare [ServerFailure] INSIDE the `write` closure — invalidates
  /// [fallbackDay]'s keys before rethrowing.** Corrected at P4b-T19 fix round
  /// 1 (I-4): `cachedWrite` now ALSO catches a directly-thrown [Failure]
  /// (`cached_query.dart:264`), so the empty-body guard's [ServerFailure]
  /// no longer "escapes cachedWrite's catch entirely" — it IS caught there,
  /// tested for ambiguity, and (being a [ServerFailure]) would invalidate
  /// whatever THIS call site names via `invalidateKeysOnAmbiguousFailure`.
  /// This call does not pass that parameter, so nothing invalidates via
  /// `cachedWrite`'s own path either way — the `on Failure catch (_)` below,
  /// unconditional on EVERY [Failure] rather than only the ambiguous ones,
  /// is what actually performs the invalidation. Both the timeout and the
  /// malformed-200 cases are ambiguous enough to invalidate anyway: a
  /// timed-out write may have committed server-side, and a malformed-200
  /// response almost certainly did — and even a genuine rejection costs
  /// nothing extra to invalidate. Over-invalidation is safe by design
  /// (`cache_keys.dart`'s own file header: the next read just re-fetches);
  /// under-invalidation is the bug that ships silently and leaves a
  /// committed write stale for the rest of the 5-minute TTL.
  Future<QuickCheckinResponse> quickCheckin({
    required int? pain,
    required int? mood,
    required bool touchedPain,
    required bool touchedMood,
    required DateTime fallbackDay,
  }) async {
    final request = QuickCheckinRequest((b) {
      // Deliberately not `if (pain != null) b.pain = pain;` — that shape
      // conflates "not touched" with "touched and cleared/zero", exactly
      // the fabrication path D-08/S-4 exist to prevent. `touchedPain` is
      // the caller's own explicit record of the gesture, never re-derived
      // from the value here.
      if (touchedPain) b.pain = pain;
      if (touchedMood) b.mood = mood;
    });

    QuickCheckinResponse? body;
    try {
      await cachedWrite(
        store: _store,
        write: () async {
          final response = await _api.checkinQuickPost(
            quickCheckinRequest: request,
          );
          final data = response.data;
          if (data == null) {
            throw const ServerFailure(
              'The server returned an empty check-in response.',
            );
          }
          body = data;
        },
      );
    } on Failure catch (_) {
      for (final key in CacheKeys.keysForDate(fallbackDay)) {
        await _store.invalidate(key);
      }
      rethrow;
    }

    final saved = body!;
    final invalidateDay = saved.day?.toDateTime() ?? fallbackDay;
    for (final key in CacheKeys.keysForDate(invalidateDay)) {
      await _store.invalidate(key);
    }

    return saved;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [CheckinRepository] wired to the shared API client and cache
/// store.
final checkinRepositoryProvider = Provider<CheckinRepository>((ref) {
  return CheckinRepository(
    api: ref.watch(lumenApiProvider),
    store: ref.watch(cacheStoreProvider),
  );
});
