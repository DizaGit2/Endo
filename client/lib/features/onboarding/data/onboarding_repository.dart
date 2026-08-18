import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/baseline_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/api/model/onboarding_start_request.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/api/model/save_baseline_request.dart';
import 'package:lumen/api/model/save_onboarding_cycle_request.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/error_mapper.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_wire.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// OnboardingRepository
// ---------------------------------------------------------------------------

/// The onboarding feature's one door to the API.
///
/// Three operations today, and they belong together because they are three
/// points on one flow rather than three features:
///
/// - [startOnboarding] — `POST /onboarding/start`, screen 2 (P3b).
/// - [getState]        — `GET /onboarding/state`, the resume read every one of
///                       screens 3-7 lands behind.
/// - [saveCycle]       — `POST /onboarding/cycle`, screen 3's write and the one
///                       mandatory answer of the flow (D-02).
/// - [complete]        — `POST /onboarding/complete`, the end of the flow.
///
/// **What [getState] deliberately does NOT do.** It returns the response whole
/// and narrows nothing. `OnboardingStateResponse` carries `lastPeriodStart`,
/// the three preference lists and the five step booleans, and screens 3-7 each
/// prefill from a different subset — a narrowed model here would force the next
/// five tasks either to re-read the endpoint or to widen this one, and the
/// widening would happen five times.
///
/// **The one asymmetry to know about** (§C.0.1, `POST /onboarding/cycle`):
/// `GET /onboarding/state` answers `lastPeriodStart` but **not**
/// `avgCycleLengthDays`, `avgPeriodLengthDays` or `regularity`. Screen 3 needs
/// all four. The other three live on `GET /settings/cycle`, which is a settings
/// read with its own key already reserved in the policy
/// (`CacheKeys.cycleSettings`) — so screen 3 composes two reads, and this
/// repository does not pretend to be the second one. Wrapping a settings
/// endpoint here would give `GET /settings/cycle` two owners the moment screen
/// 32 is built.
class OnboardingRepository {
  const OnboardingRepository({
    required LumenApiApi api,
    required CacheStore store,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api, // ignore: prefer_initializing_formals
       _store = store; // ignore: prefer_initializing_formals

  final LumenApiApi _api;
  final CacheStore _store;

  // ── startOnboarding ────────────────────────────────────────────────────────

  /// Registers a new user account by calling `POST /onboarding/start`.
  ///
  /// Fields sent to the server:
  /// - [email]       — required
  /// - [password]    — required
  /// - [displayName] — required (the "Name" field in the mockup)
  /// - [locale] / [timezone] / [policyVersion] — optional; the server applies
  ///   `es-ES` / `Europe/Madrid` / `v1-draft` when they are absent.
  ///
  /// Throws a [Failure] subtype on any error (network, validation, server).
  Future<void> startOnboarding({
    required String email,
    required String password,
    required String displayName,
    String? locale,
    String? timezone,
    String? policyVersion,
  }) async {
    final request = OnboardingStartRequest(
      (b) => b
        ..email = email
        ..password = password
        ..displayName = displayName
        ..locale = locale
        ..timezone = timezone
        ..policyVersion = policyVersion,
    );

    try {
      await _api.onboardingStartPost(onboardingStartRequest: request);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // ── getState ───────────────────────────────────────────────────────────────

  /// Reads `GET /onboarding/state` — where the user left off.
  ///
  /// Stale-while-revalidate, filed under [CacheKeys.onboardingState] at the
  /// shared [CacheKeys.ttl]: the key comes from the policy rather than a
  /// literal here so that a step write (T9-T13) can invalidate the read without
  /// the two spellings drifting.
  ///
  /// Returns [Fresh] on a successful call, [Stale] when the network failed but
  /// a cached answer exists, and [NetworkRequired] when there is neither. A
  /// stale resume is still usable — the read is idempotent and the flow it
  /// describes is the user's own — so callers may treat [Stale] exactly as they
  /// treat [Fresh].
  Future<CacheResult<OnboardingStateResponse>> getState() {
    return cachedRead<OnboardingStateResponse>(
      key: CacheKeys.onboardingState,
      store: _store,
      fetch: () async {
        final response = await _api.onboardingStateGet();
        final body = response.data;
        if (body == null) {
          // A 200 with no body is a server fault. Mapping it to a typed failure
          // keeps it out of the shell as a raw TypeError from a force-unwrap.
          throw const ServerFailure(
            'The server returned an empty onboarding state.',
          );
        }
        return body;
      },
      toJson: _stateToJson,
      fromJson: _stateFromJson,
      ttl: CacheKeys.ttl,
    );
  }

  // ── saveCycle ──────────────────────────────────────────────────────────────

  /// Calls `POST /onboarding/cycle` — screen 3's write.
  ///
  /// **MERGE, not replace** (`ARCHITECTURE.md` §C.0.1). [lastPeriodStart] is
  /// required on every post; each of the two self-reports is written only when
  /// it is supplied, and an omitted one leaves the stored value **unchanged**.
  /// That is not a nicety: screen 3 is where a user returns to correct a
  /// mistyped date, sending the anchor and nothing else, and
  /// `GET /onboarding/state` cannot give them back the other three answers if a
  /// re-post cleared them. The documented defaults (28 / null / `somewhat`)
  /// therefore belong to the server, on CREATE only — this repository has no
  /// default of its own to apply.
  ///
  /// **There is no `avgPeriodLengthDays` parameter.** Screen 3 never collects
  /// it and no P4a surface can clear it back to null, so a parameter here would
  /// be a dead one that invites a caller to believe it was persisted.
  ///
  /// [previousLastPeriodStart] is the anchor the screen was showing before this
  /// save, when it had one. It buys nothing on the wire — it decides which
  /// cached days are dropped. The server MOVES the onboarding-seeded
  /// `cycle_events.period_start` row rather than adding a second one, so a
  /// corrected date leaves the previous day without the anchor it used to
  /// carry, and a cached calendar for that month would keep drawing it.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure] keyed by wire field name. The backdate
  ///   floor reaches the user ONLY this way: it is `users.created_at` minus two
  ///   years and no endpoint returns `created_at`, so no client can pre-check
  ///   it. (The future-date rule is different — screen 3 does keep its calendar
  ///   inside the server's own `today` — but the server stays the authority,
  ///   and a client that could not learn today draws no bound at all.)
  /// - **409** → [ConflictFailure] with `code: onboarding_already_completed`.
  ///   A different code from the completion's `onboarding_incomplete`, meaning
  ///   the opposite thing.
  /// - The **sanity band is not an error at all**: an out-of-band length is
  ///   stored and answered with a 200 carrying a `warnings` code.
  Future<OnboardingCycleResponse> saveCycle({
    required Date lastPeriodStart,
    int? avgCycleLengthDays,
    String? regularity,
    Date? previousLastPeriodStart,
  }) async {
    final request = SaveOnboardingCycleRequest(
      (b) => b
        ..lastPeriodStart = lastPeriodStart
        // Left unset when null. `built_value` omits a null member from the
        // wire, and an absent member is what the server reads as "leave the
        // stored value alone".
        ..avgCycleLengthDays = avgCycleLengthDays
        ..regularity = regularity,
    );

    late final OnboardingCycleResponse body;

    await cachedWrite(
      store: _store,
      write: () async {
        final response = await _api.onboardingCyclePost(
          saveOnboardingCycleRequest: request,
        );
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty cycle response.',
          );
        }
        body = data;
      },
      invalidateKeys: _cycleWriteKeys(lastPeriodStart, previousLastPeriodStart),
    );

    return body;
  }

  /// Every cached entry this one write can have made wrong.
  ///
  /// `GET /onboarding/state` because `cycleProvided` and `lastPeriodStart` both
  /// move; `GET /settings/cycle` because the same unit of work writes
  /// `user_cycle_settings`; and the date-derived keys from [CacheKeys] for both
  /// the day the anchor lands on and the day it left, because the second table
  /// this endpoint writes is `cycle_events`.
  ///
  /// Not `GET:/me` — nothing here stamps `onboarding_completed_at`, and
  /// invalidating the profile would re-read it every time a user fixed a date.
  static List<String> _cycleWriteKeys(Date anchor, Date? previous) {
    return <String>[
      CacheKeys.onboardingState,
      CacheKeys.cycleSettings,
      ...CacheKeys.keysForDate(anchor.toDateTime()),
      if (previous != null && previous != anchor)
        ...CacheKeys.keysForDate(previous.toDateTime()),
    ];
  }

  // ── saveBaseline ───────────────────────────────────────────────────────────

  /// Calls `POST /onboarding/baseline` — screen 4's write.
  ///
  /// **MERGE** (`ARCHITECTURE.md` §C.0.1): only a supplied field is written and
  /// an omitted one is left **unchanged**, never reset to a default. Every
  /// parameter is therefore optional, and a null means "this screen has nothing
  /// to say about that field" rather than "clear it" — there is no way to clear
  /// one back to null on this endpoint at all.
  ///
  /// **An empty call throws instead of posting**, and that is the rule this
  /// endpoint has and no other on the P4a surface does: a body carrying none of
  /// the six fields is a **400** (`provide at least one baseline field`,
  /// `OnboardingStepResult.cs:332`). D-02 makes the step skippable and "skip"
  /// means *not calling the endpoint*, so an empty body can only be a client
  /// bug — an [ArgumentError] names it here, where the stack still points at
  /// the caller, instead of spending a round trip to be told the same thing.
  /// It is the same kind of guard as the server's own
  /// `RasrmStages.Encode` [ArgumentOutOfRangeException]: unreachable from a
  /// correct caller.
  ///
  /// **How loud it actually is depends on who calls.** A direct caller — a
  /// test, a future repository consumer — gets the throw with the stack
  /// pointing at itself. Through screen 4 it is quieter than that:
  /// `BaselineController.submit` wraps the call in `catch (_)`, so an
  /// [ArgumentError] would arrive as an `UnknownFailure` banner with the
  /// message every unclassifiable error in the app shows, and nothing would
  /// name this rule on screen. That is the right trade — a caught programming
  /// error beats a crash in a user's hands — but it is why the controller has
  /// its own `unsent.isEmpty` early return: the guard that USERS are protected
  /// by is that one, and this is the backstop that keeps the body
  /// unconstructable if it is ever removed.
  ///
  /// **[weightKg] is rounded to one decimal here**, immediately before the
  /// request is built, because the backend REJECTS more precision rather than
  /// rounding it (`OnboardingStepsService.cs:192-197`) and a *computed*
  /// kilogram — a slider step, an lbs→kg conversion — does not land on a tenth
  /// (`0.1 + 0.2` serialises as `0.30000000000000004`). [LumenWire.weightKg] is
  /// the one place that rounding is spelled. Screen 4 does not let a user TYPE
  /// more than one decimal, so this can only ever tidy representation error —
  /// it must never be the thing that silently drops a digit somebody entered.
  ///
  /// **There is no `rasrmStage` and no `diagnosedOn` parameter.** Screen 4's
  /// mockup draws no control for either (`Screens/screen_04_baseline.html`) and
  /// no copy for one exists in `definitions.md`, so a parameter here would be a
  /// dead one that invites a caller to believe it was persisted — the same
  /// reason [saveCycle] has no `avgPeriodLengthDays`. When a surface for them
  /// exists, `diagnosedOn` goes on the wire as a `yyyy-MM` **string** built by
  /// [LumenWire.diagnosedOn]; it is not a `Date` and the generated serializer
  /// would throw on it (§C.0.2).
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure] keyed by wire field name (`dob`,
  ///   `heightCm`, `weightKg`, `endoStatus`), plus the cross-field `request`
  ///   key. The bounds behind them are the server's own **structural storage**
  ///   domain and are not restated on this side of the wire; in particular
  ///   there is **no age gate and no lower bound on `dob`** anywhere — C-12
  ///   makes the population a design target, not a data-entry gate.
  /// - **409** → [ConflictFailure] with `code: onboarding_already_completed`.
  Future<BaselineResponse> saveBaseline({
    Date? dob,
    int? heightCm,
    double? weightKg,
    String? endoStatus,
  }) async {
    if (dob == null &&
        heightCm == null &&
        weightKg == null &&
        endoStatus == null) {
      throw ArgumentError(
        'POST /onboarding/baseline rejects a body carrying none of its fields '
        '(400 "provide at least one baseline field"). Skipping this step means '
        'not calling this method at all.',
      );
    }

    final request = SaveBaselineRequest(
      (b) => b
        // Left unset when null: `built_value` omits a null member from the
        // wire, and an absent member is what the server reads as "leave the
        // stored value alone".
        ..dob = dob
        ..heightCm = heightCm
        ..weightKg = weightKg == null ? null : LumenWire.weightKg(weightKg)
        ..endoStatus = endoStatus,
    );

    late final BaselineResponse body;

    await cachedWrite(
      store: _store,
      write: () async {
        final response = await _api.onboardingBaselinePost(
          saveBaselineRequest: request,
        );
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty baseline response.',
          );
        }
        body = data;
      },
      // `GET /me` splices this exact projection into `MeResponse` (§C.0.2's six
      // new keys), so a cached profile is wrong the moment this returns; and
      // `GET /onboarding/state.baselineProvided` moves. Nothing dated: the
      // weight seeds `body_metrics`, which no key in the policy stands for and
      // no P4b read serves.
      invalidateKeys: const <String>[
        CacheKeys.profile,
        CacheKeys.onboardingState,
      ],
    );

    return body;
  }

  // ── complete ───────────────────────────────────────────────────────────────

  /// Calls `POST /onboarding/complete` — no body, per the contract.
  ///
  /// **Invalidates the profile as well as the onboarding state.** Completion
  /// stamps `onboarding_completed_at`, which is what `GET /me.onboardingCompleted`
  /// reports and what the router's gate reads; leaving `GET:/me` cached would
  /// keep the gate shut for up to the whole TTL after the user finished.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **409** → [ConflictFailure] carrying `code: onboarding_incomplete` and
  ///   `missingSteps: ["cycle"]`. Those two are problem-details *extensions*
  ///   that `error_mapper.dart` lifts off the body; a caller reads them from the
  ///   failure and never from `DioException.response.data`.
  /// - a repeat call is **not** an error: the server answers 200 with the
  ///   original `completedAt` and `alreadyCompleted: true`.
  Future<OnboardingCompleteResponse> complete() async {
    late final OnboardingCompleteResponse body;

    await cachedWrite(
      store: _store,
      write: () async {
        final response = await _api.onboardingCompletePost();
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty completion response.',
          );
        }
        body = data;
      },
      invalidateKeys: const <String>[
        CacheKeys.onboardingState,
        CacheKeys.profile,
      ],
    );

    return body;
  }

  // ── built_value ↔ JSON-map helpers ─────────────────────────────────────────

  /// Serializes for the Hive cache. Round-tripped through `json.encode` so no
  /// Dart-only type (the custom-serialized `Date` included) reaches the box.
  static Map<String, dynamic> _stateToJson(OnboardingStateResponse state) {
    final encoded = standardSerializers.serializeWith(
      OnboardingStateResponse.serializer,
      state,
    );
    return json.decode(json.encode(encoded)) as Map<String, dynamic>;
  }

  static OnboardingStateResponse _stateFromJson(Map<String, dynamic> map) {
    return standardSerializers.deserializeWith(
      OnboardingStateResponse.serializer,
      map,
    )!;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [OnboardingRepository] wired to the shared API client and cache
/// store.
final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    api: ref.watch(lumenApiProvider),
    store: ref.watch(cacheStoreProvider),
  );
});
