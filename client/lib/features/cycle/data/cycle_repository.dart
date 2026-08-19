import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_day_response.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/log_cycle_event_request.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// CycleRepository
// ---------------------------------------------------------------------------

/// The `/cycle/*` surface T15–T17 and T23 build screens 10, 11, 8 and 14 on.
///
/// Four operations, deliberately not five or six:
/// - [getCalendarMonth] — `GET /cycle/calendar?from&to`, month-bucketed.
/// - [getDay]           — `GET /cycle/day/{date}`.
/// - [logEvent]         — `POST /cycle/events`, the FULL UPSERT this class
///                        exists to make safe. **Ruling R-10: only T16
///                        (screen 11) calls it.**
/// - [deleteEvent]      — `DELETE /cycle/events/{id}` (D-13 soft-delete).
///
/// **`POST /cycle/day/{date}` (the day-log MERGE write) and
/// `POST /cycle/phase-override` are deliberately NOT here.** T14's brief
/// enumerates exactly the four operations above; the day-log write belongs to
/// whichever of T15/T16 needs it first. Screen 14 (phase correction) is
/// T23's, not T17's — `lumen-build.md` is the authority (`:1132`) — but this
/// class still would not host the phase-override write even once T23 lands:
/// R-08 defers the actual write to P6 entirely, so T23 ships screen 14 as the
/// documented unavailable state and writes nothing in P4b.
/// `ARCHITECTURE.md` §C.0.1 calls `POST /cycle/phase-override` *"the most
/// dangerous field on the P4a surface"*, on a par with [logEvent], and giving
/// it a home before the screen that owns it exists (in a phase where it does
/// not even write) would be guessing at a shape nobody has designed against.
///
/// **No clinical inference lives here.** `flowIntensity` is passed through as
/// the raw `1..4` scale the wire defines (§2.11) — this class renders no
/// meaning onto it, computes no phase, and infers no period boundary from it.
/// C-04's *"flow ≥ 2 is period-qualifying"* rule, C-01's phase boundaries and
/// C-05's regularity bands are P6's; none of the three appears anywhere below.
class CycleRepository {
  const CycleRepository({
    required LumenApiApi api,
    required CacheStore store,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api, // ignore: prefer_initializing_formals
       _store = store; // ignore: prefer_initializing_formals

  final LumenApiApi _api;
  final CacheStore _store;

  // ── getCalendarMonth ───────────────────────────────────────────────────────

  /// Reads `GET /cycle/calendar` for the month containing [date].
  ///
  /// **Month-bucketed, per T4's key policy** (`CacheKeys.cycleCalendarMonth`):
  /// callers ask for a month, never an arbitrary window. [date]'s year/month
  /// choose both the cache key and the request window — [CacheKeys.monthWindow]
  /// derives the exact inclusive `from`/`to` the request sends, so the two can
  /// never drift apart (the window a body is cached under is the window it was
  /// actually fetched for). Filed under [CacheKeys.cycleCalendarMonth] at
  /// [CacheKeys.ttl], stale-while-revalidate like every other P4b read.
  ///
  /// **A future `to` is allowed here, and only here** (`survey/backend-
  /// endpoints.md:236`, *"A future `to` is legal here (and on `GET
  /// /symptoms`), nowhere else"*): the server caps the window at ≤366 days
  /// but does not reject a month that has not finished yet — a calendar view
  /// spans forward. [CacheKeys.monthWindow]'s `to` is the last calendar day
  /// of the month regardless of where `today` falls inside it.
  ///
  /// **`days` is sparse and ascending** — a day with nothing logged on it is
  /// simply absent from the list, not a zero-valued row
  /// (`survey/decisions-and-vocabularies.md:450`, the screen-10 row: *"...
  /// sparse days..."*; also `survey/backend-endpoints.md:517`: *"(sparse;
  /// `pain`, `mood`, `hasNotes`, `eventCount`, `symptomCount`)"*). This method
  /// does not normalise that; callers read [CycleCalendarResponse.days]
  /// exactly as the server sent it.
  ///
  /// **The phase envelope is always `unavailable`** in P4a
  /// (`ARCHITECTURE.md` §C.0.3): `phase: { available: false, unavailableReason:
  /// "phase_engine_not_implemented" }`, and no day row carries a `phase`,
  /// `cycleDay` or `confidence` key. Render the unavailable state; nothing here
  /// computes one.
  Future<CacheResult<CycleCalendarResponse>> getCalendarMonth(DateTime date) {
    final window = CacheKeys.monthWindow(date);
    return cachedRead<CycleCalendarResponse>(
      key: CacheKeys.cycleCalendarMonth(date),
      store: _store,
      fetch: () async {
        final response = await _api.cycleCalendarGet(
          from: window.from.toDate(),
          to: window.to.toDate(),
        );
        final body = response.data;
        if (body == null) {
          throw const ServerFailure(
            'The server returned an empty calendar response.',
          );
        }
        return body;
      },
      toJson: _calendarToJson,
      fromJson: _calendarFromJson,
      ttl: CacheKeys.ttl,
    );
  }

  // ── getDay ─────────────────────────────────────────────────────────────────

  /// Reads `GET /cycle/day/{date}` — one day's log, events and phase overrides.
  ///
  /// Filed under [CacheKeys.cycleDay] at [CacheKeys.ttl].
  ///
  /// **An empty day is a 200 with `log: null`, never a 404**
  /// (`survey/decisions-and-vocabularies.md:451`, the screen-11 row: *"empty
  /// day = 200 with `log:null`, not 404"*; also `survey/backend-
  /// endpoints.md:245`: *"a future/long-past/unlogged day is a 200 with
  /// `log: null` and empty lists"*). Nothing special is done with
  /// that here — [CycleDayResponse.log] is already nullable on the generated
  /// model (§C.0.2: every property is `T?`), so a day nobody has logged
  /// anything on round-trips exactly like any other nullable field. Only a
  /// **missing body** (a 200 with no payload at all — a server fault, not an
  /// empty day) is turned into a typed [ServerFailure]; `log: null` inside a
  /// present body is passed straight through.
  ///
  /// **Does NOT return that day's symptoms** — `CycleDayResponse` carries
  /// `date`, `log`, `events`, `phaseOverrides` only. A caller that also wants
  /// the symptom list needs a second call, `GET /symptoms?from=D&to=D`, which
  /// is outside this class (Symptoms is its own module, §C.3).
  Future<CacheResult<CycleDayResponse>> getDay(DateTime date) {
    return cachedRead<CycleDayResponse>(
      key: CacheKeys.cycleDay(date),
      store: _store,
      fetch: () async {
        final response = await _api.cycleDayDateGet(date: date.toDate());
        final body = response.data;
        if (body == null) {
          throw const ServerFailure(
            'The server returned an empty day response.',
          );
        }
        return body;
      },
      toJson: _dayToJson,
      fromJson: _dayFromJson,
      ttl: CacheKeys.ttl,
    );
  }

  // ── logEvent ───────────────────────────────────────────────────────────────

  /// Calls `POST /cycle/events` — the most dangerous write on the P4a surface.
  ///
  /// **FULL UPSERT** (`ARCHITECTURE.md` §C.0.1): an omitted `notes` or
  /// `flowIntensity` is **CLEARED**, not left alone. A screen that posts a
  /// `period_start` without re-sending the row's existing note silently wipes
  /// it — there is no "leave this field as it is" gesture on this endpoint,
  /// unlike the MERGE writes elsewhere in this phase.
  ///
  /// **How a partial call is made structurally impossible, not merely
  /// discouraged (the brief's question, answered here).** All four wire
  /// fields are `required` named parameters:
  ///
  /// - [kind] and [occurredOn] are `required` AND non-nullable — the server
  ///   treats a missing one as a hard 400 on every call, so there is no
  ///   legitimate reason to omit either and no clearing semantics to protect.
  /// - [flowIntensity] and [notes] are `required` but **nullable** — the
  ///   FULL-UPSERT hazard lives here. Marking them `required` (Dart's
  ///   keyword, independent of the parameter's own type) means the compiler
  ///   rejects a call that does not mention them, full stop: omitting
  ///   `flowIntensity:` or `notes:` from a call site is a compile error, not a
  ///   passing build with a quiet default. A caller is therefore forced to
  ///   type an explicit answer for both, every time — either the value being
  ///   kept (which means it had to go read the existing row first, e.g. via
  ///   [getDay]) or an explicit `null` to *deliberately* clear it. There is no
  ///   third, silent option: an **optional** named parameter (the shape every
  ///   other writer in this phase uses for a field that may be skipped) is
  ///   exactly the shape that would let a caller forget one and wipe it by
  ///   accident, which is why this method does not use it.
  ///
  /// [flowIntensity] passed through as the raw `1..4` scale (§2.11) with no
  /// client-side range check — the value is a rendering concern for whichever
  /// screen collects it, and the server is the bounds authority (400,
  /// `value must be between 1 and 4`) exactly as for every other numeric field
  /// on this surface.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure], keyed `kind`, `occurredOn`,
  ///   `flowIntensity`, `notes`. The backdate floor (`occurredOn` earlier than
  ///   the user's account-creation day minus two years) reaches the user only
  ///   this way — no endpoint returns the account-creation date, so nothing
  ///   here can pre-check it (`survey/backend-endpoints.md:407`).
  Future<CycleEventResponse> logEvent({
    required String kind,
    required Date occurredOn,
    required int? flowIntensity,
    required String? notes,
  }) async {
    final request = LogCycleEventRequest(
      (b) => b
        ..kind = kind
        ..occurredOn = occurredOn
        ..flowIntensity = flowIntensity
        ..notes = notes,
    );

    late final CycleEventResponse body;

    await cachedWrite(
      store: _store,
      write: () async {
        final response = await _api.cycleEventsPost(
          logCycleEventRequest: request,
        );
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty cycle-event response.',
          );
        }
        body = data;
      },
      // T4's named derivation, not re-implemented: a write to occurredOn
      // invalidates that day's own key AND its month bucket, because
      // eventCount / hasNotes on the calendar row move too.
      invalidateKeys: CacheKeys.keysForDate(occurredOn.toDateTime()),
    );

    return body;
  }

  // ── deleteEvent ────────────────────────────────────────────────────────────

  /// Calls `DELETE /cycle/events/{id}` — soft-deletes one `cycle_events` row.
  ///
  /// [occurredOn] is required because the 204 response carries no body: the
  /// only way this method can name the keys the deletion invalidates
  /// ([CacheKeys.keysForDate], the same derivation [logEvent] uses) is if the
  /// caller — which just showed the user this exact row, e.g. via [getDay] —
  /// supplies the date it was on.
  ///
  /// **A second delete of an already-deleted row is a 404, and this client
  /// treats it as SUCCESS** (D-13 soft-delete,
  /// `survey/backend-endpoints.md:270-274`): the row is gone either way, and a
  /// caller retrying a delete it is not sure landed (a dropped response, a
  /// double-tap) should not be shown an error for a row that is, in fact,
  /// gone. `cachedWrite` only invalidates after a write that does **not**
  /// throw, so the 404 path invalidates explicitly here — the first delete
  /// (this device's own, or a race with another) may not have reached this
  /// device's cache, and the 404 itself confirms the row no longer exists
  /// regardless of which call actually removed it.
  ///
  /// Any other failure (network, 401, 5xx…) propagates as the typed [Failure]
  /// `mapDioException` produces, and invalidates nothing.
  Future<void> deleteEvent({
    required String id,
    required Date occurredOn,
  }) async {
    try {
      await cachedWrite(
        store: _store,
        write: () async {
          await _api.cycleEventsIdDelete(id: id);
        },
        invalidateKeys: CacheKeys.keysForDate(occurredOn.toDateTime()),
      );
    } on NotFoundFailure {
      for (final key in CacheKeys.keysForDate(occurredOn.toDateTime())) {
        await _store.invalidate(key);
      }
    }
  }

  // ── built_value ↔ JSON-map helpers ─────────────────────────────────────────

  /// Serialized for the Hive cache. Round-tripped through `json.encode` so no
  /// Dart-only type (the custom-serialized `Date` fields included) reaches the
  /// box.
  static Map<String, dynamic> _calendarToJson(CycleCalendarResponse value) {
    final encoded = standardSerializers.serializeWith(
      CycleCalendarResponse.serializer,
      value,
    );
    return json.decode(json.encode(encoded)) as Map<String, dynamic>;
  }

  static CycleCalendarResponse _calendarFromJson(Map<String, dynamic> map) {
    return standardSerializers.deserializeWith(
      CycleCalendarResponse.serializer,
      map,
    )!;
  }

  static Map<String, dynamic> _dayToJson(CycleDayResponse value) {
    final encoded = standardSerializers.serializeWith(
      CycleDayResponse.serializer,
      value,
    );
    return json.decode(json.encode(encoded)) as Map<String, dynamic>;
  }

  static CycleDayResponse _dayFromJson(Map<String, dynamic> map) {
    return standardSerializers.deserializeWith(
      CycleDayResponse.serializer,
      map,
    )!;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [CycleRepository] wired to the shared API client and cache store.
final cycleRepositoryProvider = Provider<CycleRepository>((ref) {
  return CycleRepository(
    api: ref.watch(lumenApiProvider),
    store: ref.watch(cacheStoreProvider),
  );
});
