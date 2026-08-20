import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/symptom_list_response.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// SymptomsRepository
// ---------------------------------------------------------------------------

/// The `/symptoms` READ surface P4b-T16 needs, and the class P4b-T19 extends.
///
/// **Read-only, deliberately — this is not the whole symptoms repository.**
/// R-11 (`lumen-build.md:865`) gives screen 12 (T20) sole ownership of the
/// batch `POST /symptoms`; T19 (`lumen-build.md:1129`) owns that write, the
/// FULL-REPLACE `PUT /symptoms/{id}` and the soft `DELETE`. T16 is ordered
/// BEFORE T19 in the ledger (`:1118` vs `:1129`) and needs the day-scoped
/// list NOW to render screen 11's Symptoms section — so this class ships
/// exactly the slice T19's own ledger line already names ("day-scoped
/// list"), under the SAME class name T19 will extend, rather than T16
/// inventing a second symptoms repository for T19 to reconcile later.
///
/// **T16 must not, and does not, add [getDay]'s write counterparts here.**
/// No `post`, no `put`, no `delete` — screen 11 renders symptoms; it does not
/// edit them (T16 brief: "You write nothing to the API").
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
      toJson: _toJson,
      fromJson: _fromJson,
      ttl: CacheKeys.ttl,
    );
  }

  // ── built_value ↔ JSON-map helpers ─────────────────────────────────────

  /// Serialized for the Hive cache. Round-tripped through `json.encode` so no
  /// Dart-only type reaches the box — same shape as `CycleRepository`'s pair.
  static Map<String, dynamic> _toJson(SymptomListResponse value) {
    final encoded = standardSerializers.serializeWith(
      SymptomListResponse.serializer,
      value,
    );
    return json.decode(json.encode(encoded)) as Map<String, dynamic>;
  }

  static SymptomListResponse _fromJson(Map<String, dynamic> map) {
    return standardSerializers.deserializeWith(
      SymptomListResponse.serializer,
      map,
    )!;
  }
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
