import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/cycle_day_response.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/log_cycle_day_request.dart';
import 'package:lumen/api/model/log_cycle_event_request.dart';
import 'package:lumen/core/cache/built_json_codec.dart';
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
/// Five operations, deliberately not six:
/// - [getCalendarMonth] — `GET /cycle/calendar?from&to`, month-bucketed.
/// - [getDay]           — `GET /cycle/day/{date}`.
/// - [logDay]           — `POST /cycle/day/{date}`, the day-log **MERGE**
///                        (P4b-T16b). Screen 11's day-log editor is its only
///                        caller.
/// - [logEvent]         — `POST /cycle/events`, the FULL UPSERT this class
///                        exists to make safe. **Ruling R-10: only T16
///                        (screen 11) calls it.**
/// - [deleteEvent]      — `DELETE /cycle/events/{id}` (D-13 soft-delete).
///
/// **[logDay] and [logEvent] are the two OPPOSITE write rules in this phase,
/// and this class is where the difference has to be visible.** On [logEvent] an
/// omitted field is **CLEARED**; on [logDay] an omitted field is **LEFT
/// UNCHANGED**. Both take `required`-but-nullable parameters, and they do so
/// for mirror-image reasons: [logEvent] because a caller must never forget to
/// re-send a field it means to keep, [logDay] because a caller must never
/// forget to state whether the user actually touched one. Read each method's
/// own doc before writing a call site; they are not interchangeable.
///
/// **`POST /cycle/phase-override` is deliberately NOT here.** Screen 14 (phase
/// correction) is T23's, not T17's — `lumen-build.md` is the authority
/// (`:1132`) — but this class still would not host the phase-override write
/// even once T23 lands: R-08 defers the actual write to P6 entirely, so T23
/// ships screen 14 as the documented unavailable state and writes nothing in
/// P4b. `ARCHITECTURE.md` §C.0.1 calls `POST /cycle/phase-override` *"the most
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
      toJson: (value) => toCacheJson(CycleCalendarResponse.serializer, value),
      fromJson: (map) => fromCacheJson(CycleCalendarResponse.serializer, map),
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
      toJson: (value) => toCacheJson(CycleDayResponse.serializer, value),
      fromJson: (map) => fromCacheJson(CycleDayResponse.serializer, map),
      ttl: CacheKeys.ttl,
    );
  }

  // ── logDay ─────────────────────────────────────────────────────────────────

  /// Calls `POST /cycle/day/{date}` — the day-log write behind screen 11's
  /// editor (P4b-T16b). Returns the 200 body, which is the **stored** row.
  ///
  /// **MERGE**, the exact opposite of [logEvent] (`ARCHITECTURE.md` §C.0.1).
  /// Verified at the source rather than inherited: `CycleDayService`'s
  /// `MergeScales` assigns `row.Pain`/`row.Mood` only `if (pain is { } value)`
  /// — never a falsiness test, so `pain: 0` OVERWRITES a stored 8 (D-08) —
  /// and `UpsertDayAsync` writes `row.NotesEnc` only when the trimmed note is
  /// non-empty, echoing the stored note back otherwise. So on this endpoint:
  ///
  /// | wire                | stored column          |
  /// |---------------------|------------------------|
  /// | key absent          | **left unchanged**     |
  /// | `notes: ""` / `" "` | **left unchanged**     |
  /// | `pain: 0`           | overwritten with 0     |
  ///
  /// **There is therefore NO way to clear a day-log field**, and this method
  /// deliberately offers none: `LogCycleDayRequest`'s generated serializer
  /// omits every null member, so an explicit `null` is indistinguishable from
  /// an absent key on the wire, and the server would read either as
  /// "leave alone". A caller that wants to remove a logged pain or mood
  /// cannot, in v1, by any route — see `LumenIntensityScale.allowClear`.
  ///
  /// **The three `touched*` flags are the only thing that decides what is
  /// SENT, and they are never re-derived from whether the value is null.**
  /// This is `CheckinRepository.quickCheckin`'s shape, on the same kind of
  /// endpoint, for the same two reasons — and on this method it closes a
  /// second hazard that one does not have, because screen 11's editor is
  /// PREFILLED where screen 9's form is not:
  ///
  ///  1. **A value the user never touched is never asserted.** The editor is
  ///     seeded from a day read that may have come out of a 5-minute-TTL
  ///     cache. Under MERGE, an untouched field is omitted, so a stale seed
  ///     cannot become a lost update — the freshness of the seed stops
  ///     mattering rather than having to be established. (`cachedRead` has no
  ///     `forceRefresh`, and `CacheResult.Fresh` also means "a cache hit
  ///     inside the TTL", so "re-read until fresh" was never available.)
  ///  2. **An empty, untouched notes box does not send `""`.** It sends
  ///     nothing at all.
  ///
  /// `if (touchedPain) b.pain = pain;` — **not** `if (pain != null)`. The two
  /// differ on exactly one input, "untouched but holding a value", which is
  /// what every prefilled field is until the user edits it; that is the case
  /// `cycle_repository_test.dart`'s matrix varies independently.
  ///
  /// A `touched` field whose value is `null` is still omitted — by the
  /// serializer, not by a guard — and that is correct: the endpoint cannot
  /// express a clear, so there is nothing else it could mean. What must never
  /// happen is `pain ?? 0`, which would turn "the user took their answer
  /// back" into a logged "none today" that D-08 makes permanently
  /// indistinguishable from a real one, on an endpoint with no delete.
  ///
  /// [date] is the ROUTE date and is the only place the day appears —
  /// `LogCycleDayRequest` has no `day` member at all. It is never re-derived
  /// from the response.
  ///
  /// Cache: the three [CacheKeys.keysForDate] keys for [date], on success AND
  /// on an ambiguous failure. `invalidateKeysOnAmbiguousFailure` is
  /// `cachedWrite`'s own parameter (added at P4b-T19) rather than a
  /// hand-rolled `on Failure catch`, and it fires only for
  /// [NetworkFailure]/[ServerFailure] — the two shapes where the server may
  /// have committed and the client cannot tell. A 400 invalidates nothing:
  /// `CycleDayService` collects every error before the first write, so a
  /// rejected request changed nothing and the cache is still correct.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure] keyed `pain`, `mood`, `notes`, `date`
  ///   (the future-day rule) or the cross-field `request` key
  ///   (`at least one of pain, mood or notes is required`). There is **no
  ///   backdate floor on this endpoint** — `CycleDayService` says so at the
  ///   site: *"capped by today and NOTHING ELSE"* — so a five-year-old day is
  ///   a legal write.
  /// - **404** → the caller has no live `users` row (never existed, or
  ///   crypto-shredded), not "no such day": an unlogged day is a 200 on the
  ///   GET and a legal target for this POST.
  Future<CycleDayLogResponse> logDay({
    required DateTime date,
    required int? pain,
    required int? mood,
    required String? notes,
    required bool touchedPain,
    required bool touchedMood,
    required bool touchedNotes,
  }) async {
    final request = LogCycleDayRequest((b) {
      // The guard is the FLAG, never the value. See this method's doc for the
      // one input the two shapes disagree on, and why it is the only one that
      // matters.
      if (touchedPain) b.pain = pain;
      if (touchedMood) b.mood = mood;
      if (touchedNotes) b.notes = notes;
    });

    final keys = CacheKeys.keysForDate(date);

    return cachedWrite<CycleDayLogResponse>(
      store: _store,
      write: () async {
        final response = await _api.cycleDayDatePost(
          date: date.toDate(),
          logCycleDayRequest: request,
        );
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty day-log response.',
          );
        }
        return data;
      },
      invalidateKeys: keys,
      // S-6: a write that committed server-side and then timed out would
      // otherwise leave all three keys fresh for the rest of the 5-minute
      // TTL, so the screen re-reads pre-write data AND shows an error.
      // Over-invalidation is free (the next read re-fetches); this is the
      // failure that ships silently.
      invalidateKeysOnAmbiguousFailure: keys,
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
