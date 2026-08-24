import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/update_cycle_settings_request.dart';
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
/// **The write arrived with screen 32 (P4b-T22a).** [updateSettings] covers
/// the six self-report and prediction fields; the three C-12 pause members
/// (`trackingPaused`, `pauseReason`, `pausedSince`) are **deliberately not
/// parameters of it** and belong to screen 32's pause card (T22b). Screen 3
/// still calls only [getSettings].
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

  // ── updateSettings ─────────────────────────────────────────────────────────

  /// Calls `PATCH /settings/cycle` — screen 32's save (P4b-T22a). Returns the
  /// 200 body, which is the **whole stored resource**.
  ///
  /// **MERGE**, verified at the source rather than inherited:
  /// `CycleSettingsService.UpdateAsync` assigns each column only
  /// `if (request.X is { } value)` — never a truthiness test, so a supplied
  /// `false` on any of the three prediction flags OVERWRITES a stored `true`,
  /// exactly as a supplied `0` does on the day log. An absent key leaves the
  /// column alone, and **there is no way to clear one**: a `null` member is
  /// dropped by the generated serializer
  /// (`update_cycle_settings_request.dart`'s `_serializeProperties`, one
  /// `if (object.x != null)` per member), so an explicit null and an absent
  /// key are the same bytes and the server reads both as "leave alone".
  /// `UpdateCycleSettingsRequest`'s own C# doc states the cost in those
  /// terms: *"P4a ships no way to CLEAR `avgPeriodLengthDays` back to null…
  /// Screen 32 offers no clear affordance, so nothing is lost today."* This
  /// method offers none either.
  ///
  /// **The six `touched*` flags are the only thing that decides what is SENT,
  /// and they are never re-derived from whether the value is null.**
  /// `CheckinRepository.quickCheckin` and `CycleRepository.logDay` are the
  /// shape. Two hazards make it mandatory here rather than merely safe:
  ///
  ///  1. **A value the user never touched is never asserted.** The form is
  ///     seeded from a `GET /settings/cycle` that may have come out of a
  ///     5-minute-TTL cache, and `user_cycle_settings` is a **multi-writer
  ///     row** — `POST /onboarding/cycle` writes the same three self-reports
  ///     through `CycleSettingsService.ApplyOnboardingCycleAsync`, and T22b's
  ///     pause card will write the same row again. Under MERGE an untouched
  ///     field is omitted, so a stale seed cannot become a lost update.
  ///  2. **The response is not round-trippable, and this signature makes the
  ///     round trip impossible rather than merely discouraged.** The 200
  ///     carries `pauseReason`, which **survives a resume on purpose** so the
  ///     pause card can pre-select it; `CycleSettingsService.Validate` then
  ///     rejects that same value on the way back in with a 400 keyed
  ///     `pauseReason` (*"value is only allowed while cycle tracking is
  ///     paused"*) whenever the effective state is not paused. There is no
  ///     `pauseReason` parameter on this method, so no caller can echo it.
  ///
  /// `if (touchedRegularity) b.regularity = regularity;` — **not**
  /// `if (regularity != null)`. The two differ on exactly one input,
  /// "untouched but holding a value", which is what every seeded field is
  /// until the user edits it; that is the case
  /// `cycle_settings_repository_test.dart`'s matrix varies independently.
  ///
  /// **An all-absent body is a 400**, keyed `request`:
  /// *"at least one settings field is required"*
  /// (`CycleSettingsValidationMessages.NoFieldsSupplied`). Under merge an
  /// empty body is a pure no-op that would still materialise a defaults row
  /// and stamp `updatedAt`. This method does not pre-check it —
  /// `CycleSettingsForm.blockReason` does, at the CTA, so the user meets the
  /// condition as a disabled control with a reason rather than a round trip
  /// that can only fail.
  ///
  /// **No bound is applied here, and none may be.** The server's only 400 on
  /// the two lengths is structural (a positive integer that fits `smallint`);
  /// a value outside its sanity band is **stored** and answered with a 200
  /// carrying a non-blocking `warnings` code. R-17: the C-03 clinical bounds
  /// are clinician-UNSIGNED and appear nowhere in `client/lib`.
  ///
  /// Cache: [CacheKeys.cycleSettings], on success AND on an ambiguous failure
  /// ([NetworkFailure]/[ServerFailure] — the two shapes where the server may
  /// have committed and the client cannot tell). A 400 invalidates nothing:
  /// `CycleSettingsService` collects every field error before the first write.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure] keyed `avgCycleLengthDays`,
  ///   `avgPeriodLengthDays`, `regularity`, or the cross-field `request` key.
  /// - **404** → the caller has no live `users` row (never existed, or
  ///   crypto-shredded). A user with no *settings* row is a 200 on the GET and
  ///   a legal target for this PATCH.
  Future<CycleSettingsResponse> updateSettings({
    required int? avgCycleLengthDays,
    required int? avgPeriodLengthDays,
    required String? regularity,
    required bool? phasePredictionEnabled,
    required bool? autoDetectPeriodStartEnabled,
    required bool? showFertilityWindowEnabled,
    required bool touchedAvgCycleLengthDays,
    required bool touchedAvgPeriodLengthDays,
    required bool touchedRegularity,
    required bool touchedPhasePredictionEnabled,
    required bool touchedAutoDetectPeriodStartEnabled,
    required bool touchedShowFertilityWindowEnabled,
  }) async {
    final request = UpdateCycleSettingsRequest((b) {
      // The guard is the FLAG, never the value. See this method's doc for the
      // one input the two shapes disagree on, and why it is the only one that
      // matters.
      if (touchedAvgCycleLengthDays) b.avgCycleLengthDays = avgCycleLengthDays;
      if (touchedAvgPeriodLengthDays) {
        b.avgPeriodLengthDays = avgPeriodLengthDays;
      }
      if (touchedRegularity) b.regularity = regularity;
      if (touchedPhasePredictionEnabled) {
        b.phasePredictionEnabled = phasePredictionEnabled;
      }
      if (touchedAutoDetectPeriodStartEnabled) {
        b.autoDetectPeriodStartEnabled = autoDetectPeriodStartEnabled;
      }
      if (touchedShowFertilityWindowEnabled) {
        b.showFertilityWindowEnabled = showFertilityWindowEnabled;
      }
    });

    const keys = <String>[CacheKeys.cycleSettings];

    return cachedWrite<CycleSettingsResponse>(
      store: _store,
      write: () async {
        final response = await _api.settingsCyclePatch(
          updateCycleSettingsRequest: request,
        );
        final data = response.data;
        if (data == null) {
          // A 200 with no body is a server fault. Typed, so it never reaches a
          // screen as a raw TypeError from a force-unwrap.
          throw const ServerFailure(
            'The server returned empty cycle settings.',
          );
        }
        return data;
      },
      invalidateKeys: keys,
      // S-6: a write that committed server-side and then timed out would
      // otherwise leave the read fresh for the rest of the 5-minute TTL, so
      // the next screen re-reads pre-write data AND shows an error.
      invalidateKeysOnAmbiguousFailure: keys,
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
