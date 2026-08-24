import 'package:built_collection/built_collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/create_symptoms_request.dart';
import 'package:lumen/api/model/create_symptoms_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/symptom_entry_input.dart';
import 'package:lumen/api/model/symptom_list_response.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/cache/built_json_codec.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// SymptomEntryDraft
// ---------------------------------------------------------------------------

/// One symptom episode to save, before it becomes wire — the P4b-T19 "request
/// boundary" that makes a dropped field IMPOSSIBLE, not merely validated.
///
/// The generated [SymptomEntryInput] is a `built_value` class: every one of
/// its builder setters is OPTIONAL, so `SymptomEntryInput((b) => b.intensity =
/// 5)` compiles clean without ever mentioning `region`. Nothing stops that
/// from shipping, and nothing about it fails loudly — the server just answers
/// with its own default (`SymptomService.cs:413-415,480-481,496`): a null
/// `symptomCode` becomes `pain`, a null `region` becomes `unspecified`, a null
/// `side` is stored as SQL NULL, **none of the three as a 400**. A mapper bug
/// that drops one of these three fields is therefore invisible forever — the
/// row still saves, just as a slightly different, permanently indistinguishable
/// observation.
///
/// [symptomCode], [region] and [side] are `required` NAMED parameters here —
/// Dart's keyword, independent of the parameter's own nullable TYPE, the same
/// device `CycleRepository.logEvent` (P4b-T14) uses for `flowIntensity` and
/// `notes`. A call site that does not mention one of them is a COMPILE ERROR,
/// not a passing build with a quiet default. Passing an explicit `null` still
/// reaches the server's default — that is a legitimate, deliberate choice
/// (an unclassified RELATED chip genuinely has no region); the parameter only
/// forbids the ACCIDENTAL version, where a caller simply forgot the field
/// existed.
///
/// [intensity] is `int`, never `int?` — the ONE field the contract actually
/// marks required (a missing one is this endpoint's only field-level 400,
/// `SymptomService.cs:458-464`), so the Dart type system enforces it exactly:
/// there is no null to test for falsiness and no `?? 0` to write by mistake.
/// D-08's `intensity: 0` reaches the wire like any other value because it was
/// never a nullable field to begin with — there is no falsy/absent conflation
/// possible.
///
/// [painTypes] and [triggers] default to `const []` rather than being
/// `required`: an OMITTED array and an EXPLICIT empty array already mean the
/// identical thing on the wire (`SymptomService.cs:567`,
/// `supplied is null or { Count: 0 } => []`), so there is no silent-default
/// hazard on these two to guard against — nothing for a forgotten line to
/// silently change.
///
/// [occurredAt] is `required` but nullable: an explicit `null` asks the
/// server for its own single `now` for the whole batch — the "logging as it
/// happens" case the contract names as a first-class choice, not a defect
/// (`SymptomService.cs:428-430`).
///
/// **Correction (fix round 1, I-1): `occurredAt` IS a fourth silently-defaulted
/// field, not exempt from the class above.** `SymptomService.cs:430`,
/// `entry.OccurredAt ?? now`, no 400 — and a mapper bug that drops the
/// `..occurredAt = occurredAt` line in [_toWire] has a WORSE consequence than
/// the other three: every entry, even one built with an explicit historical
/// instant, would silently relocate onto today — an entire backdated batch,
/// permanently and indistinguishably re-dated. `null` reaching the wire is
/// still a legitimate, deliberate choice (that half was always true); what
/// this class got wrong was implying the field carried none of the mapper's
/// silent-default risk. It is `required` for the same "state your choice"
/// reason as the other three, and [_toWire]'s wire-level tests now pin it the
/// same way (`symptoms_repository_test.dart`, `createBatch` group).
class SymptomEntryDraft {
  const SymptomEntryDraft({
    required this.symptomCode,
    required this.intensity,
    required this.region,
    required this.side,
    this.painTypes = const <String>[],
    this.triggers = const <String>[],
    required this.occurredAt,
    this.notes,
  });

  /// One of the 21 ratified codes, or `null` to ask the server for its `pain`
  /// default.
  final String? symptomCode;

  /// 0–10 NRS-11 (D-08). `0` is a real datum, never an absence — there is no
  /// null on this field to conflate it with.
  final int intensity;

  /// One of the 9 ratified regions, or `null` to ask the server for its
  /// `unspecified` default.
  final String? region;

  /// `front`/`back` (anatomical, NOT laterality), or `null` for "not
  /// classified" — stored as SQL NULL.
  final String? side;

  /// Zero or more of the 6 ratified pain qualities.
  final List<String> painTypes;

  /// Zero or more of the 7 ratified triggers.
  final List<String> triggers;

  /// When the episode happened, or `null` to ask the server for the batch's
  /// single `now`.
  final DateTime? occurredAt;

  /// Optional free text, ≤ 2000 characters after trimming (server-enforced).
  final String? notes;

  /// The generated wire shape, every field set explicitly — the ONE
  /// reviewable place a `symptomCode`/`region`/`side` line could be dropped,
  /// rather than one of N call sites each free to forget it independently.
  SymptomEntryInput _toWire() {
    return SymptomEntryInput(
      (b) => b
        ..symptomCode = symptomCode
        ..intensity = intensity
        ..region = region
        ..side = side
        ..painTypes = ListBuilder<String>(painTypes)
        ..triggers = ListBuilder<String>(triggers)
        ..occurredAt = occurredAt
        ..notes = notes,
    );
  }
}

// ---------------------------------------------------------------------------
// SymptomsRepository
// ---------------------------------------------------------------------------

/// The `/symptoms` surface: T16's read (day-scoped list) plus T19's write
/// (the batch create).
///
/// **T16 shipped read-only.** R-11 (`lumen-build.md:865`) gives screen 12
/// (T20) sole ownership of the batch `POST /symptoms`; T16's own brief says
/// "you write nothing to the API". [getDay] is that slice, unchanged here.
///
/// **T19 adds exactly one write: [createBatch].** `PUT /symptoms/{id}` and
/// `DELETE /symptoms/{id}` were both CUT from P4b — a survey
/// (`.superpowers/sdd/lumen-build/survey-symptoms/05-critic.md`, DL-1)
/// established neither has a caller anywhere in the phase (T20 is
/// create-only, T21 writes nothing, T16b is cycle-only, and screen 12 draws
/// no delete affordance), and every data-loss path the survey found lives on
/// the `PUT` full-replace path. Shipping either now would be a live control
/// pointing at nothing — R-20 inverted. Symptom edit and delete are booked
/// for P6.
///
/// Filed under [CacheKeys.symptomsDay], which [CacheKeys.keysForDate]
/// already invalidates on every cycle write (`cache_keys.dart:106-110`) —
/// that plumbing was built at P4b-T4 and would otherwise sit unused until
/// T19 landed. The key's own `?day=` spelling is a client-side cache
/// identifier (R-05), not a URL — the real query is `?from&to`, below.
class SymptomsRepository {
  const SymptomsRepository({
    required LumenApiApi api,
    required CacheStore store,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api, // ignore: prefer_initializing_formals
       _store = store; // ignore: prefer_initializing_formals

  final LumenApiApi _api;
  final CacheStore _store;

  // ── getDay ─────────────────────────────────────────────────────────────

  /// Reads `GET /symptoms?from={date}&to={date}&limit=100` — one day's
  /// symptom rows, server-ordered newest first (`occurredAt DESC, id DESC`).
  ///
  /// Filed under [CacheKeys.symptomsDay] at [CacheKeys.ttl].
  ///
  /// **`from` and `to` are ALWAYS sent, explicitly, both equal to [date].**
  /// The validator requires both
  /// (`backend/src/Lumen.Api/Symptoms/SymptomService.cs:205-209`), but
  /// `backend/contract/openapi.json` marks neither required, so the
  /// generated `symptomsGet({Date? from, Date? to, ...})` COMPILES with
  /// neither supplied and answers a 400 at runtime. The contract document is
  /// wrong here; the validator is authoritative, so this method never omits
  /// either.
  ///
  /// **`limit: 100` is ALWAYS sent, explicitly.** The default is 50, the max
  /// is 100, and an out-of-range value is a 400 — NEVER a silent clamp
  /// (`SymptomService.cs:222-228`). R-18 allows up to 37 rows in a single
  /// save (`lumen-build.md:872`), so two saves on one day can already exceed
  /// the default of 50. Sending the max up front moves the cliff as far as
  /// the server allows; [SymptomListResponse.total] still carries the true
  /// row count, so a caller that hits even the 100-row cap can show that
  /// truncation happened rather than silently dropping rows past it. There
  /// is no paging UI in P4b — a visible limit, never a silent one.
  ///
  /// **A day with no symptoms is a 200 with `items: []`, `total: 0`** — not
  /// a 404 (a 404 on this endpoint means "no such user", checked before
  /// anything else). Passed straight through: [SymptomListResponse.items]
  /// is nullable on the generated model (every property is, §C.0.2), so a
  /// caller reads `.items ?? const []` the same way it reads every other
  /// nullable field.
  Future<CacheResult<SymptomListResponse>> getDay(DateTime date) {
    final day = date.toDate();
    return cachedRead<SymptomListResponse>(
      key: CacheKeys.symptomsDay(date),
      store: _store,
      fetch: () async {
        final response = await _api.symptomsGet(from: day, to: day, limit: 100);
        final body = response.data;
        if (body == null) {
          // Fix round 2, M-3: its own message, distinct from createBatch's
          // "no body" and "no items" cases below — three different
          // broken-contract shapes, three different strings.
          throw const ServerFailure(
            'The server returned an empty symptoms-day response.',
          );
        }
        return body;
      },
      toJson: (value) => toCacheJson(SymptomListResponse.serializer, value),
      fromJson: (map) => fromCacheJson(SymptomListResponse.serializer, map),
      ttl: CacheKeys.ttl,
    );
  }

  // ── createBatch ────────────────────────────────────────────────────────

  /// A save must contain at least one entry (`SymptomBatch.MinEntries`,
  /// `SymptomContracts.cs:94`) — an empty array is a client bug, not a no-op.
  static const minBatchEntries = 1;

  /// The inclusive ceiling: 50 entries are accepted, 51 are refused
  /// (`SymptomBatch.MaxEntries`, `SymptomContracts.cs:97`). R-18 — no
  /// chunking; a batch over this is refused client-side, never split.
  static const maxBatchEntries = 50;

  /// Calls `POST /symptoms` — the all-or-nothing batch create behind screen
  /// 12's "Save symptom" and screen 13's "Save body map" (T20/T21). Answers
  /// with every created row, in request order.
  ///
  /// **The size bound is enforced HERE, client-side, before any network
  /// call** — R-18 (`lumen-build.md:873`): a batch outside
  /// [minBatchEntries]..[maxBatchEntries] is refused with a [ValidationFailure]
  /// keyed `entries`, reusing the server's own wire strings
  /// (`SymptomValidationMessages.BatchEmpty`/`MaxEntries`,
  /// `SymptomContracts.cs:152,161`) so the client and the server never say two
  /// different things about the same rule. Never chunked into several
  /// requests: `SymptomService.cs:97-166` validates and saves the batch as
  /// ONE transaction, so splitting it here would silently reintroduce the
  /// half-written-episode hazard the endpoint exists to prevent.
  ///
  /// **How the T19 hazards are held (fix round 1 revises items 2 and 3).**
  ///
  /// 1. **`cachedWrite` is GENERALISED, not bypassed** (`cached_query.dart`):
  ///    it now returns the write's own result, and [invalidateKeysFor] lets
  ///    invalidation be computed FROM that result — this call could not use
  ///    the pre-T19 shape at all, because neither the created rows nor the
  ///    server-derived `occurredOn` exist until the 201 comes back.
  /// 2. **Every distinct `occurredOn` in the response is invalidated**, not
  ///    one date — a batch may span several days and the server derives each
  ///    row's day independently (`SymptomService.cs:526`). A `null` `items`
  ///    or a `null` `occurredOn` on a returned row — both of which the
  ///    contract's non-nullable `Items`/`DateOnly` guarantee can never
  ///    actually happen — are treated as a broken response and answer a loud
  ///    [ServerFailure], validated INSIDE the `write:` closure (see
  ///    [_requireValidItems]) rather than afterward: a throw placed after
  ///    `write()` had already returned successfully — where fix round 1 found
  ///    it — sits outside `cachedWrite`'s ambiguity handling entirely, so it
  ///    both skips invalidating every OTHER, perfectly valid item in the same
  ///    batch and never reaches [invalidateKeysOnAmbiguousFailure] — a known
  ///    successful write left with a 100%-stale cache, worse than the silent
  ///    skip this loud guard exists to replace (I-2/I-5).
  /// 3. **Ambiguous failure invalidates anyway (S-6), for 100% of expected
  ///    traffic, not only the entries that happen to carry an explicit
  ///    date.** If the write throws a [NetworkFailure] or [ServerFailure] —
  ///    the server may have already committed the rows before the response
  ///    was lost — [cachedWrite]'s `invalidateKeysOnAmbiguousFailure` runs
  ///    [_fallbackInvalidationKeys]: a ±1-day WINDOW around the entry's own
  ///    day if [SymptomEntryDraft.occurredAt] is explicit (fix round 2, item
  ///    2 — the client cannot compute the server's exact profile-timezone
  ///    day offline), else [fallbackDay]'s EXACT day, un-windowed — never
  ///    nothing. [fallbackDay] matters because screen 12's
  ///    mockup draws no date affordance at all, so on the traffic T20 will
  ///    actually send, EVERY entry's `occurredAt` is `null` (fix round 1,
  ///    C-1) — the first version of this method, which contributed no key
  ///    for a null `occurredAt`, invalidated nothing for that traffic shape,
  ///    which is 100% of it.
  /// 4. **A missing `symptomCode`/`region`/`side`/`occurredAt` cannot be
  ///    expressed** — see [SymptomEntryDraft].
  ///
  /// Any other failure (a real 400, 401, 409, 429, 5xx that is NOT preceded
  /// by an ambiguous network condition, …) invalidates nothing, matching
  /// every other write in this app: [ValidationFailure] keeps its per-entry
  /// [ValidationFailure.fields] keyed `entries[N].field`
  /// (`SymptomService.cs:127`, `$"entries[{i}]"`), which
  /// [ValidationFailure.path] builds.
  ///
  /// [fallbackDay] is the server-confirmed "today" (`sessionTodayProvider`),
  /// **required** for the identical "impossible to forget" reason
  /// [SymptomEntryDraft]'s own fields are — the same shape
  /// `CheckinRepository.quickCheckin`'s `fallbackDay` already uses in
  /// production for screen 9, which has the same "no date affordance, server
  /// picks `now`" shape (`checkin_repository.dart:95-101`). It is
  /// invalidation-only: it never reaches the request body, so it cannot
  /// change which instant the server stores (`SymptomService.cs:430`).
  Future<List<SymptomResponse>> createBatch({
    required List<SymptomEntryDraft> entries,
    required DateTime fallbackDay,
  }) async {
    if (entries.length < minBatchEntries || entries.length > maxBatchEntries) {
      throw ValidationFailure(
        message: _batchSizeMessage(entries.length),
        detail: _batchSizeMessage(entries.length),
        fields: {
          'entries': [_batchSizeMessage(entries.length)],
        },
      );
    }

    final request = CreateSymptomsRequest(
      (b) => b.entries.replace(entries.map((e) => e._toWire())),
    );

    return cachedWrite<List<SymptomResponse>>(
      store: _store,
      write: () async {
        final response = await _api.symptomsPost(
          createSymptomsRequest: request,
        );
        final body = response.data;
        if (body == null) {
          throw const ServerFailure(
            'The server returned an empty symptoms response.',
          );
        }
        // Validated HERE, inside write() — see _requireValidItems and hazard
        // 2 above for why this must not move back out to invalidateKeysFor.
        return _requireValidItems(body);
      },
      invalidateKeysFor: _keysForCreatedItems,
      invalidateKeysOnAmbiguousFailure: _fallbackInvalidationKeys(
        entries,
        fallbackDay,
      ),
    );
  }
}

/// [count] entries, refused client-side — the SAME two wire strings
/// `SymptomService.cs` answers with, so a request that WOULD have been
/// refused reads identically whether it was caught here or on the server
/// (`SymptomValidationMessages.BatchEmpty`/`MaxEntries`,
/// `SymptomContracts.cs:152,161`).
String _batchSizeMessage(int count) {
  if (count < SymptomsRepository.minBatchEntries) {
    return 'at least one entry is required';
  }
  return 'a request may contain at most '
      '${SymptomsRepository.maxBatchEntries} entries';
}

/// Unwraps and FULLY validates [CreateSymptomsResponse.items] — that the list
/// itself is present, AND that every item's `occurredOn` is present — so that
/// everything downstream can treat both as guaranteed. **Called from INSIDE
/// the `write:` closure, not from `invalidateKeysFor`** (fix round 1, I-2):
/// a throw here is caught by `cachedWrite`'s own `on Failure catch`
/// (`cached_query.dart`), which tests it for ambiguity exactly like any other
/// failure — and since a malformed 201 body means the rows were, in fact,
/// just committed, that IS ambiguous, so [SymptomsRepository.createBatch]'s
/// `invalidateKeysOnAmbiguousFailure` fires for it. Thrown from
/// `invalidateKeysFor` instead (this function's first shipped location) sits
/// OUTSIDE `cachedWrite`'s `try` entirely — success has already been decided
/// by the time that callback runs — so it neither reaches the ambiguous
/// handler NOR lets any OTHER, perfectly valid item in the same batch
/// invalidate: a write KNOWN to have committed left with a 100%-stale cache,
/// which is worse than the silent skip this loud guard exists to replace.
///
/// [CreateSymptomsResponse.items] and each item's [SymptomResponse.occurredOn]
/// are non-nullable on the contract (`IReadOnlyList<SymptomResponse> Items`;
/// `DateOnly OccurredOn`) even though the generated Dart model makes both
/// `T?` (§C.0.2). A `null` in either place is therefore a broken-contract
/// state, not an empty save or an unlucky row — DL-2's rule: a loud
/// [ServerFailure], never a silent `?? const []`/skip that would tell the
/// caller "you created nothing" (or leave one day's cache stale) about a
/// batch that has, in fact, just committed. The two cases get DISTINCT
/// messages (fix round 1, M-3) — they are different broken-contract shapes
/// and a caller inspecting `Failure.message` should be able to tell them
/// apart.
List<SymptomResponse> _requireValidItems(CreateSymptomsResponse created) {
  final items = created.items;
  if (items == null) {
    throw const ServerFailure(
      'The server returned a symptoms response with no items.',
    );
  }
  for (final item in items) {
    if (item.occurredOn == null) {
      throw const ServerFailure(
        "The server created a symptom with no occurredOn — the day's cache "
        'cannot be safely invalidated.',
      );
    }
  }
  return items.toList(growable: false);
}

/// Every [CacheKeys.keysForDate] for every DISTINCT `occurredOn` [items]
/// carries (DL-4 — a batch may span more than one day, and the server derives
/// each row's day independently, so one date is not enough).
///
/// [items] must already be [_requireValidItems]'s output: the `!` below is
/// safe ONLY because that function has already rejected every null
/// `occurredOn`, and this function does not re-check — re-validating here
/// would put the check back in two places to drift apart, and this function
/// (used as `invalidateKeysFor`) only ever runs after `write()` — which is
/// exactly where that validation now lives — has already succeeded.
List<String> _keysForCreatedItems(List<SymptomResponse> items) {
  final keys = <String>{};
  for (final item in items) {
    keys.addAll(CacheKeys.keysForDate(item.occurredOn!.toDateTime()));
  }
  return keys.toList(growable: false);
}

/// S-6's ambiguous-failure invalidation list (`lumen-build.md:1145`) for a
/// write whose outcome `cachedWrite` could not confirm.
///
/// For each entry: if [SymptomEntryDraft.occurredAt] is explicit, a ±1-day
/// WINDOW around it (see [_dayWindow] — fix round 2, item 2); if it was left
/// `null` (asking the server for its own `now`), [fallbackDay]'s keys
/// instead, un-windowed — **never nothing** (fix round 1, C-1). [fallbackDay]
/// is a required, server-confirmed "today" (`sessionTodayProvider`) — the
/// same shape `CheckinRepository.quickCheckin`'s `fallbackDay` already uses
/// in production for the IDENTICAL case (screen 9 draws no date affordance
/// either, `checkin_repository.dart:95-101`). It is NOT the device clock
/// D-12 forbids and NOT a guess: it is the one value in this whole call the
/// server has already confirmed.
///
/// **This closes the gap the first version of this function left.** Screen
/// 12's mockup draws no date affordance at all
/// (`Screens/screen_12_symptom_form.html`), so on the traffic T20 will
/// actually send, EVERY entry's `occurredAt` is `null` — a version of this
/// function that contributed no key for the null case invalidated NOTHING
/// for the survey's most-likely-bad-outcome path (2N indistinguishable rows
/// after a re-save) on the only traffic shape that exists.
///
/// **M-2, corrected at fix round 2 — `.toUtc()` was INERT, not a fix.** The
/// first version of this function called `.toUtc()` on an explicit
/// `occurredAt`, reasoning that it made the answer independent of whether
/// the caller built a local- or UTC-flavoured `DateTime`. That reasoning was
/// wrong: the client serialises with built_value's `Iso8601DateTimeSerializer`
/// (`client/lib/api/serializers.dart`), whose `serialize` THROWS
/// `ArgumentError` on a non-UTC `DateTime`, so any `occurredAt` that actually
/// reaches the wire is already UTC and `.toUtc()` was a no-op on every value
/// that got here and later succeeded. M-2's conclusion stands; **its
/// MECHANISM was wrong in both operative clauses, disproved at T17b by the
/// implementer and the reviewer independently, and is corrected here rather
/// than left to be re-derived.**
///
/// It said a local `occurredAt` would crash "INSIDE `write()` … neither
/// `DioException` nor `Failure`, so `cachedWrite` never even reaches this
/// list — long before this function's answer could matter". Both halves are
/// false. **(1) The order is inverted:** this function is an EAGER ARGUMENT
/// EXPRESSION at the `createBatch` call site — `invalidateKeysOnAmbiguousFailure`
/// takes a `List<String>`, not a callback — so it has already run before
/// `cachedWrite` is entered, and a later throw can only DISCARD its answer,
/// never prevent it being computed. **(2) The throw is caught:** the generated
/// `LumenApiApi.symptomsPost` catches that `ArgumentError` and rethrows a
/// `DioException(type: unknown)`, which `cachedWrite` very much does catch.
/// The wrong keys are dropped one link further on, and only by accident:
/// `mapDioException` maps `unknown` to `UnknownFailure`, and
/// `_invalidateOnAmbiguousFailure` returns early on anything that is not a
/// `NetworkFailure` or a `ServerFailure`. **That is a four-file coincidence,
/// one plausible edit away from going live** (`unknown` → `NetworkFailure`
/// would do it), **and it is absent from the tests** — every test here drives
/// a `MockLumenApiApi`, so no serializer ever runs and a local `occurredAt`
/// would produce the narrowed window with no crash at all.
///
/// It is not reachable today: all three `SymptomEntryDraft` construction
/// sites in `client/lib` pass `occurredAt: null`. [_dayWindow]'s own
/// normalisation, below, is what makes it unreachable by CONSTRUCTION rather
/// than by that coincidence. **The boundary is still unguarded** —
/// `SymptomEntryDraft.occurredAt` is an unvalidated public `DateTime?` — and
/// that residual is booked for the next phase.
///
/// **T17b — a `.toUtc()` IS back, inside [_dayWindow], and it is not the one
/// M-2 removed.** M-2's call sat here, on the value handed to
/// [CacheKeys.keysForDate], and was sold as closing the profile-timezone gap;
/// it did not, because the value was already UTC. T17b's sits one level down,
/// on the ANCHOR of the ±1-day arithmetic, and does a different job: it makes
/// the "given a UTC instant" premise of the exhaustiveness argument below a
/// property of the code instead of a claim about callers. Read together with
/// the [fallbackDay] paragraph that follows: that branch must still never be
/// `.toUtc()`-ed, and is not.
///
/// **The gap `.toUtc()` never closed, closed instead by a ±1-day window.**
/// [CacheKeys.keysForDate] reads the UTC civil date, while the SERVER derives
/// the stored day in the user's PROFILE timezone (`SymptomService.cs:526`,
/// `dayResolver.ToUserDay`). IANA offsets span −12:00…+14:00, so a
/// profile-timezone civil date differs from the UTC civil date by AT MOST
/// one day either way — [_dayWindow]'s `{D−1, D, D+1}` is therefore provably
/// exhaustive. An exact computation is not available offline: the client has
/// the profile timezone's NAME but no tz database (`package:timezone` is not
/// a dependency), so the window is the only exhaustive shape reachable here.
/// Applied ONLY to the explicit-`occurredAt` branch.
///
/// **The [fallbackDay] branch is deliberately NOT windowed, and must never
/// be.** `fallbackDay` is the server's OWN profile-timezone "today"
/// (`sessionTodayProvider`, reading `GET /cycle/calendar`'s `today`) —
/// already exact; widening it would trade a right answer for three
/// wrong-adjacent ones. **Production supplies it as `Date.toDateTime()` —
/// LOCAL midnight carrying the server's civil fields**
/// (`client/lib/api/model/date.dart:25-31`,
/// `quick_checkin_controller.dart:212`) — while every test in this file
/// passes `DateTime.utc(...)`; both read the identical `year`/`month`/`day`
/// today, so nothing distinguishes them here. **A future "consistency" edit
/// adding `.toUtc()` to THIS branch would be a no-op in every test and a
/// real off-by-one-day bug in production**, shifting local midnight onto the
/// PREVIOUS UTC day on every positive-offset device. Pinned by a dedicated
/// test passing a LOCAL `DateTime` for `fallbackDay` (fix round 2, item 3) —
/// that test must redden if `.toUtc()` is ever added here.
///
/// **Cost of the window.** [CacheStore.invalidate] deletes the entry outright
/// (`hive_boot.dart`), and the ambiguous-failure path IS the offline path —
/// so over-invalidating a neighbouring day converts a would-be `Stale`
/// render into `NetworkRequired` for a day the write never touched. Still far
/// cheaper than the S-6 hazard this function exists to close (2N duplicate
/// clinical rows), and `keysForDate` already deletes the month's calendar key
/// regardless of which of the three days triggered it — so the incremental
/// cost is one extra `cycleDay`/`symptomsDay` pair per neighbouring day,
/// roughly 3 → 9 keys per explicit-`occurredAt` entry, de-duplicated through
/// the `Set` below.
List<String> _fallbackInvalidationKeys(
  List<SymptomEntryDraft> entries,
  DateTime fallbackDay,
) {
  final keys = <String>{};
  for (final entry in entries) {
    final occurredAt = entry.occurredAt;
    if (occurredAt == null) {
      keys.addAll(CacheKeys.keysForDate(fallbackDay));
    } else {
      for (final day in _dayWindow(occurredAt)) {
        keys.addAll(CacheKeys.keysForDate(day));
      }
    }
  }
  return keys.toList(growable: false);
}

/// [instant]'s own UTC civil day plus its immediate neighbours (D−1, D, D+1) —
/// see [_fallbackInvalidationKeys]'s doc for why this specific window is
/// exhaustive for a profile-timezone civil date given a UTC instant.
///
/// **T17b — the UTC premise is now ENFORCED here rather than asserted about
/// callers, and the arithmetic is on calendar FIELDS.** The first version
/// yielded `instant.subtract(const Duration(days: 1))` and its `.add` twin,
/// which is exact arithmetic on an instant: 86 400 seconds, correct for a
/// calendar day only when the value carries no DST. It was safe *only* while
/// [instant] was UTC, and nothing in this file made that true — the dartdoc
/// said it. What actually kept it safe was a coincidence three files away
/// (built_value's `Iso8601DateTimeSerializer` throws `ArgumentError` on a
/// non-UTC `DateTime`, the generated client rewraps that as a
/// `DioException(unknown)`, `mapDioException` answers `UnknownFailure`, and
/// [cachedWrite] invalidates on nothing but `NetworkFailure`/`ServerFailure`)
/// — and that coincidence does **not** hold in the unit tests, where the API
/// is mocked and no serializer ever runs. `.toUtc()` costs nothing on the
/// values that actually arrive (it is the identity on a UTC one) and makes
/// the window's exhaustiveness argument true for any flavour of input; the
/// field arithmetic then makes "±1 day" mean one CALENDAR day by
/// construction, since `DateTime.utc` normalises day 0 into the previous
/// month and day 32 into the next.
///
/// The three values are UTC MIDNIGHTS rather than the original's
/// same-time-of-day instants. Nothing downstream can tell: the sole consumer
/// is [CacheKeys.keysForDate], which reads `year`/`month`/`day` and nothing
/// else.
///
/// This is deliberately NOT a waived `Duration(days: 1)`
/// (`test/support/duration_days_guard.dart`). A waiver would have rested on
/// the dartdoc above being true, which is the thing that was not enforceable.
Iterable<DateTime> _dayWindow(DateTime instant) sync* {
  final utc = instant.toUtc();
  yield DateTime.utc(utc.year, utc.month, utc.day - 1);
  yield DateTime.utc(utc.year, utc.month, utc.day);
  yield DateTime.utc(utc.year, utc.month, utc.day + 1);
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [SymptomsRepository] wired to the shared API client and cache
/// store — the same wiring [cycleRepositoryProvider] uses.
final symptomsRepositoryProvider = Provider<SymptomsRepository>((ref) {
  return SymptomsRepository(
    api: ref.watch(lumenApiProvider),
    store: ref.watch(cacheStoreProvider),
  );
});
