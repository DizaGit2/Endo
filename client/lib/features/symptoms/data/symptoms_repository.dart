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
/// (`SymptomService.cs:428-430`). It is NOT one of the three silently-defaulted
/// fields above; it is `required` only so every call site states its choice
/// explicitly, the same discipline as the rest of this class.
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
          throw const ServerFailure(
            'The server returned an empty symptoms response.',
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
  /// **How the four T19 hazards are held.**
  ///
  /// 1. **`cachedWrite` is GENERALISED, not bypassed** (`cached_query.dart`):
  ///    it now returns the write's own result, and [invalidateKeysFor] lets
  ///    invalidation be computed FROM that result — this call could not use
  ///    the pre-T19 shape at all, because neither the created rows nor the
  ///    server-derived `occurredOn` exist until the 201 comes back.
  /// 2. **Every distinct `occurredOn` in the response is invalidated**, not
  ///    one date — a batch may span several days and the server derives each
  ///    row's day independently (`SymptomService.cs:526`). A `null`
  ///    `occurredOn` on a returned row — which the contract's `DateOnly`
  ///    guarantees can never actually happen — is treated as a broken
  ///    response and answers a loud [ServerFailure] rather than silently
  ///    skipping that row's invalidation (DL-2: never a fallback where the
  ///    contract promises a value).
  /// 3. **Ambiguous failure invalidates anyway (S-6).** If the write throws a
  ///    [NetworkFailure] or [ServerFailure] — the server may have already
  ///    committed the rows before the response was lost — every date named by
  ///    THIS REQUEST's own [SymptomEntryDraft.occurredAt] values is
  ///    invalidated too, via [cachedWrite]'s `invalidateKeysOnAmbiguousFailure`.
  ///    An entry whose `occurredAt` was left `null` (asking the server for
  ///    its own `now`) contributes no key here — the client has no
  ///    server-confirmed day to invalidate and D-12 forbids guessing one from
  ///    the device clock, so that narrow gap is accepted and documented
  ///    rather than papered over with a device-clock guess.
  /// 4. **A missing `symptomCode`/`region`/`side` cannot be expressed** — see
  ///    [SymptomEntryDraft].
  ///
  /// Any other failure (a real 400, 401, 409, 429, 5xx that is NOT preceded
  /// by an ambiguous network condition, …) invalidates nothing, matching
  /// every other write in this app: [ValidationFailure] keeps its per-entry
  /// [ValidationFailure.fields] keyed `entries[N].field`
  /// (`SymptomService.cs:127`, `$"entries[{i}]"`), which
  /// [ValidationFailure.path] builds.
  Future<List<SymptomResponse>> createBatch({
    required List<SymptomEntryDraft> entries,
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

    late final List<SymptomResponse> items;

    await cachedWrite<CreateSymptomsResponse>(
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
        return body;
      },
      invalidateKeysFor: (created) {
        items = _requireItems(created);
        return _keysForCreatedItems(items);
      },
      invalidateKeysOnAmbiguousFailure: _fallbackInvalidationKeys(entries),
    );

    return items;
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

/// Unwraps [CreateSymptomsResponse.items], which the contract guarantees is
/// always present (`IReadOnlyList<SymptomResponse> Items`, non-nullable) even
/// though the generated Dart model makes it `T?` (§C.0.2 — every generated
/// property is). A `null` here means the server sent a malformed 201, which
/// is a broken contract, not an empty save — DL-2's rule applies: a loud
/// [ServerFailure], never a silent `?? const []` that would tell the caller
/// "you created nothing" about a batch that may well have committed.
List<SymptomResponse> _requireItems(CreateSymptomsResponse created) {
  final items = created.items;
  if (items == null) {
    throw const ServerFailure(
      'The server returned an empty symptoms response.',
    );
  }
  return items.toList(growable: false);
}

/// Every [CacheKeys.keysForDate] for every DISTINCT `occurredOn` [items]
/// carries (DL-4 — a batch may span more than one day, and the server derives
/// each row's day independently, so one date is not enough).
///
/// A `null` `occurredOn` on a returned row is a broken-contract state
/// (`SymptomResponse.OccurredOn` is `DateOnly`, never null, on the wire) —
/// DL-2's rule applies here too: a loud [ServerFailure] rather than silently
/// skipping that row's invalidation, which would leave a day's cache stale
/// with no signal that anything went wrong.
List<String> _keysForCreatedItems(List<SymptomResponse> items) {
  final keys = <String>{};
  for (final item in items) {
    final occurredOn = item.occurredOn;
    if (occurredOn == null) {
      throw const ServerFailure(
        "The server created a symptom with no occurredOn — the day's cache "
        'cannot be safely invalidated.',
      );
    }
    keys.addAll(CacheKeys.keysForDate(occurredOn.toDateTime()));
  }
  return keys.toList(growable: false);
}

/// The best a client can name for S-6's ambiguous-failure invalidation
/// (`lumen-build.md:1145`) when the write itself never returned: every
/// [CacheKeys.keysForDate] for every DISTINCT, CLIENT-SUPPLIED
/// [SymptomEntryDraft.occurredAt] in [entries].
///
/// An entry whose `occurredAt` is `null` (asking the server for its own
/// `now`) contributes nothing — the client has no server-confirmed day for
/// it, and D-12 (`test/core/locale/formatting_guard_test.dart`) forbids
/// guessing one from the device clock. That is a real, narrow gap (a batch
/// made ENTIRELY of `occurredAt: null` entries that then fails ambiguously
/// invalidates nothing), accepted and documented here rather than closed
/// with a device-clock guess that could just as easily invalidate the WRONG
/// day.
List<String> _fallbackInvalidationKeys(List<SymptomEntryDraft> entries) {
  final keys = <String>{};
  for (final entry in entries) {
    final occurredAt = entry.occurredAt;
    if (occurredAt == null) continue;
    keys.addAll(CacheKeys.keysForDate(occurredAt));
  }
  return keys.toList(growable: false);
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
