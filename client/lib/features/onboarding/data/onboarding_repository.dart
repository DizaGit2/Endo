import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/baseline_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/goals_response.dart';
import 'package:lumen/api/model/hormone_prefs_response.dart';
import 'package:lumen/api/model/notification_prefs_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/api/model/onboarding_start_request.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/api/model/save_baseline_request.dart';
import 'package:lumen/api/model/save_goals_request.dart';
import 'package:lumen/api/model/save_hormone_prefs_request.dart';
import 'package:lumen/api/model/save_notification_prefs_request.dart';
import 'package:lumen/api/model/save_onboarding_cycle_request.dart';
import 'package:lumen/core/cache/built_json_codec.dart';
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
/// - [saveBaseline]    — `POST /onboarding/baseline`, screen 4's write (MERGE).
/// - [saveGoals]       — `POST /onboarding/goals`, screen 5's write. The first
///                       **FULL REPLACE** of the flow: a code left out is
///                       stored as deselected.
/// - [saveHormones]    — `POST /onboarding/hormones`, screen 6's write. FULL
///                       REPLACE too, but with **no minimum** — see below.
/// - [saveNotifications] — `POST /onboarding/notifications`, screen 7's write.
///                       FULL REPLACE, and the only step that also carries the
///                       optional push pair.
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
      toJson: (state) => toCacheJson(OnboardingStateResponse.serializer, state),
      fromJson: (map) => fromCacheJson(OnboardingStateResponse.serializer, map),
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

  // ── saveGoals ──────────────────────────────────────────────────────────────

  /// Calls `POST /onboarding/goals` — screen 5's write.
  ///
  /// **FULL REPLACE of the complete row set** (`ARCHITECTURE.md` §C.0.1), and
  /// the first such surface in the flow. [codes] is the whole desired state of
  /// `user_goals`, not a list of additions: the server writes a row for **every**
  /// code in `UserGoal.Codes.All` and sets `Selected` from membership of this
  /// array (`OnboardingStepsService.cs:381-407`, `StagePreferenceRows`). So a
  /// code left out is **stored as deselected** — deselection is recorded as an
  /// answer rather than vanishing, which is the whole point of the shape
  /// (`UserGoal.cs:5-9`). A caller that sends only what changed silently
  /// discards every goal the user selected on an earlier visit.
  ///
  /// **An empty array throws instead of posting.** D-14 is multi-select **min
  /// 1, no max**, and an empty array is a 400 whose message is `select at least
  /// one goal` (`OnboardingStepResult.cs:371`, raised at
  /// `OnboardingStepsService.cs:369-375`) — deliberately **not** the generic
  /// `value is required`, because the field *was* supplied. The guard here is
  /// the same shape as [saveBaseline]'s and has the same standing: the guard
  /// USERS are protected by is the screen's inert Continue, and this is the
  /// backstop that keeps the body unconstructable if that is ever removed.
  ///
  /// **What this deliberately does NOT do**, because the server accepts both
  /// and a client that rejects what the server stores is a defect:
  ///
  ///  * it does not de-duplicate. Duplicates collapse silently server-side
  ///    (`OnboardingStepsService.cs:1127-1149`, a `HashSet` keyed
  ///    `StringComparer.Ordinal`);
  ///  * it does not normalise case, and no caller may. Matching is **Ordinal**,
  ///    so `Manage_Symptoms` is an unknown code and a 400 keyed `goals[i]` —
  ///    folding case here would send a value this client believed was valid.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure] keyed `goals` for the whole array, or
  ///   `goals[i]` for one member (`ValidationFailure.path('goals', i)`).
  /// - **409** → [ConflictFailure] with `code: onboarding_already_completed`.
  Future<GoalsResponse> saveGoals({required List<String> codes}) async {
    if (codes.isEmpty) {
      throw ArgumentError.value(
        codes,
        'codes',
        'POST /onboarding/goals rejects an empty array (400 "select at least '
            'one goal"). D-14 is min 1, no max — an empty selection is not a '
            'request this client may issue.',
      );
    }

    final request = SaveGoalsRequest(
      (b) => b..goals = ListBuilder<String>(codes),
    );

    late final GoalsResponse body;

    await cachedWrite(
      store: _store,
      write: () async {
        final response = await _api.onboardingGoalsPost(
          saveGoalsRequest: request,
        );
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty goals response.',
          );
        }
        body = data;
      },
      // `GET /onboarding/state` carries both `goalsProvided` and the goals
      // projection itself, so this write moves it. Nothing else: `user_goals`
      // appears in no other cached read — `MeResponse` has no goals member, and
      // nothing here stamps `onboarding_completed_at`, so invalidating the
      // profile would re-read it every time a user changed a chip.
      invalidateKeys: const <String>[CacheKeys.onboardingState],
    );

    return body;
  }

  // ── saveHormones ───────────────────────────────────────────────────────────

  /// Calls `POST /onboarding/hormones` — screen 6's write.
  ///
  /// **FULL REPLACE of the complete row set** (`ARCHITECTURE.md` §C.0.1), the
  /// same shape as [saveGoals]: [codes] is the whole desired state of
  /// `user_hormone_prefs`, not a list of additions. The server writes a row for
  /// **every** code in `HormoneCatalog.Codes.All` and sets `Charted` from
  /// membership of this array (`OnboardingStepsService.cs:448-464`,
  /// `StagePreferenceRows`), so a code left out is **stored as deselected**. A
  /// caller that sends only what changed silently discards every hormone the
  /// user had charted on an earlier visit.
  ///
  /// **[codes] carries WIRE CODES, never display labels.** The two that differ
  /// are the whole reason this is worth saying: `estradiol` is drawn as
  /// "Estrogen" and `glp1` as "GLP-1" (B16, `HormoneCatalog.cs:32,40`). A label
  /// on this array is an unknown code and a 400 keyed `chartedHormones[i]`.
  ///
  /// **An empty array is a valid answer and is POSTED, not refused.** This is
  /// where screen 6 parts company with screen 5: `POST /onboarding/goals` is
  /// min 1 and [saveGoals] throws rather than spend a round trip to be told,
  /// but this endpoint has **no minimum at all** — "chart nothing" is a real
  /// answer and a different state from having skipped the step. The server
  /// keys `value is required` on a **null** `chartedHormones` and on nothing
  /// else (`OnboardingStepsService.cs:435-436`), where `SaveGoalsAsync` adds a
  /// second arm for `Count == 0` (`:369-375`). So the guard that belongs on
  /// screen 5 must not be copied here, and the array has to reach the wire as
  /// `[]`: `built_value` omits a **null** member, and an omitted
  /// `chartedHormones` is exactly the null the server rejects. Passing the list
  /// to `ListBuilder` unconditionally is what keeps the member non-null.
  ///
  /// **Charted is not extracted.** The flag decides only whether a series is
  /// *drawn*; P7b extracts all seven hormones from every lab regardless of what
  /// this call stores (D-14, `OnboardingContracts.cs:210-214`).
  ///
  /// **What this deliberately does NOT do**, because the server accepts both
  /// and a client that rejects what the server stores is a defect: it does not
  /// de-duplicate (duplicates collapse silently server-side,
  /// `OnboardingStepsService.cs:1127-1149`, a `HashSet` keyed
  /// `StringComparer.Ordinal`) and it does not normalise case (matching is
  /// **Ordinal**, so `Estradiol` is an unknown code and a 400).
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure] keyed `chartedHormones` for the whole
  ///   array, or `chartedHormones[i]` for one member
  ///   (`ValidationFailure.path('chartedHormones', i)`).
  /// - **409** → [ConflictFailure] with `code: onboarding_already_completed`.
  Future<HormonePrefsResponse> saveHormones({
    required List<String> codes,
  }) async {
    final request = SaveHormonePrefsRequest(
      (b) => b..chartedHormones = ListBuilder<String>(codes),
    );

    late final HormonePrefsResponse body;

    await cachedWrite(
      store: _store,
      write: () async {
        final response = await _api.onboardingHormonesPost(
          saveHormonePrefsRequest: request,
        );
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty hormone response.',
          );
        }
        body = data;
      },
      // `GET /onboarding/state` carries both `hormonesProvided` and the hormone
      // projection itself, so this write moves it. Nothing else:
      // `user_hormone_prefs` appears in no other cached read — `MeResponse` has
      // no hormone member, `GET /settings/hormones` is a P6 endpoint that does
      // not exist yet, and nothing here stamps `onboarding_completed_at`.
      invalidateKeys: const <String>[CacheKeys.onboardingState],
    );

    return body;
  }

  // ── saveNotifications ──────────────────────────────────────────────────────

  /// Calls `POST /onboarding/notifications` — screen 7's write.
  ///
  /// **FULL REPLACE of the complete row set** (`ARCHITECTURE.md` §C.0.1), the
  /// same shape as [saveGoals] and [saveHormones]: [codes] is the whole desired
  /// state of `user_notification_prefs`, not a list of additions. The server
  /// writes a row for **every** code in
  /// `HormoneCatalog.NotificationCategories.All` and sets `Enabled` from
  /// membership of this array (`OnboardingStepsService.cs:556-573`, through
  /// `StagePreferenceRows` at `:1172-1192`), so a code left out is **stored as
  /// deselected**.
  ///
  /// **[codes] carries WIRE CODES.** `phase_shift` is singular — screen 7's
  /// plural "Phase shifts" is display drift and `HormoneCatalog
  /// .NotificationCategories` is the authority (`HormoneCatalog.cs:85-108`). A
  /// label on this array is an unknown code and a 400 keyed
  /// `enabledCategories[i]`.
  ///
  /// **An empty array is a valid answer and is POSTED, not refused.** Muting
  /// everything is a real answer: the server keys `value is required` on a
  /// **null** `enabledCategories` and on nothing else
  /// (`OnboardingStepsService.cs:515-517`), exactly as
  /// `POST /onboarding/hormones` does. Passing the list to `ListBuilder`
  /// unconditionally is what keeps the member non-null, because `built_value`
  /// omits a null member and an omitted `enabledCategories` IS that null.
  ///
  /// **Calling this with an empty array is NOT how a user skips the step**, and
  /// the difference is the whole of D-02. "Skip" means *not calling this method
  /// at all*: an empty post stores four rows with every flag `false`, and
  /// `POST /onboarding/complete` then leaves them alone, because its backfill is
  /// guarded by `if (!await db.UserNotificationPrefs.AnyAsync(...))`
  /// (`OnboardingStepsService.cs:1091`). So a "skip" that posted an empty set
  /// would silence a user who never said anything — the exact opposite of the
  /// ON / ON / OFF / OFF seed completion would otherwise have materialised
  /// (`:1093-1104`, `UserNotificationPref.DefaultEnabled`).
  ///
  /// **[pushToken] and [platform] are all-or-nothing.** Both are optional and an
  /// absent pair is a **normal outcome** (`deviceRegistered: false`), not a
  /// failure (`OnboardingContracts.cs:290-293`). What the server refuses is
  /// *half* a pair — a token with no platform is a device P9a could never
  /// dispatch to, and a platform with no token is not a registration at all —
  /// which is a 400 under the reserved `request` key
  /// (`OnboardingStepsService.cs:524-530`). That is knowable on the device, so
  /// an [ArgumentError] names it here rather than spending a round trip; the
  /// same backstop shape [saveGoals] and [saveBaseline] have.
  ///
  /// **Blank counts as absent on both**, the rule the server applies before it
  /// measures anything (`OnboardingStepsService.cs:521-522`): a client sending
  /// `""` for a token it does not have gets "no device", not a half-supplied
  /// pair. Normalising here rather than only server-side is what stops the guard
  /// above from rejecting a request the server would have accepted.
  ///
  /// **What this deliberately does NOT do.** It does not de-duplicate and does
  /// not fold case (matching is Ordinal, `OnboardingStepsService.cs:1127-1149`),
  /// and it does not mirror the token's 1–512 character bound
  /// (`UserDevice.PushTokenMaxLength`): that is the storage column's width, no
  /// user types a push token, and a client that refused a longer one would be
  /// refusing what a future provider hands it.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure] keyed `enabledCategories`,
  ///   `enabledCategories[i]`, `platform`, `pushToken`, or the cross-field
  ///   `request`.
  /// - **409** → [ConflictFailure] with `code: onboarding_already_completed`.
  Future<NotificationPrefsResponse> saveNotifications({
    required List<String> codes,
    String? pushToken,
    String? platform,
  }) async {
    final String? token = _blankIsAbsent(pushToken);
    final String? devicePlatform = _blankIsAbsent(platform);

    if ((token == null) != (devicePlatform == null)) {
      throw ArgumentError(
        'POST /onboarding/notifications rejects half a device pair (400 '
        '"pushToken and platform must be provided together"). Send both or '
        'neither — an absent pair is a normal outcome, reported as '
        'deviceRegistered: false.',
      );
    }

    final request = SaveNotificationPrefsRequest(
      (b) => b
        ..enabledCategories = ListBuilder<String>(codes)
        // Left unset when null: `built_value` omits a null member, and an
        // absent pair is what the server reads as "no device to register".
        ..pushToken = token
        ..platform = devicePlatform,
    );

    late final NotificationPrefsResponse body;

    await cachedWrite(
      store: _store,
      write: () async {
        final response = await _api.onboardingNotificationsPost(
          saveNotificationPrefsRequest: request,
        );
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty notification response.',
          );
        }
        body = data;
      },
      // `GET /onboarding/state` carries both `notificationsProvided` and the
      // notification projection itself, so this write moves it. NOT the
      // profile: `MeResponse` has no notification member and nothing here
      // stamps `onboarding_completed_at` — [complete] does that, and it
      // invalidates the profile itself.
      invalidateKeys: const <String>[CacheKeys.onboardingState],
    );

    return body;
  }

  /// [value] with the server's own "blank is absent" rule applied.
  ///
  /// `OnboardingStepsService.cs:521-522` trims and then treats an empty string
  /// as absent, on the token and the platform alike.
  static String? _blankIsAbsent(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
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
