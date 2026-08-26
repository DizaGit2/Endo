// ---------------------------------------------------------------------------
// flow_harness.dart — the world a `test/flows/` multi-screen test runs in
// (P4b-T24, R-06 (i))
// ---------------------------------------------------------------------------
//
// R-06 amended this phase's `integration_test green` exit criterion: there is
// no `integration_test` dev dependency, CI is `ubuntu-latest` with no emulator
// and no compose stack, and Keycloak's login runs in a Chrome Custom Tab that
// is not automatable. What replaces it is this — multi-screen widget tests over
// a faked `LumenApiApi`, runnable in CI — plus one recorded manual on-device
// walk (`docs/superpowers/specs/2026-05-31-build-strategy/
// p4b-manual-walkthrough.md`, executed by a human at T25).
//
// ## The technique, and why it is this one
//
// P4b-T26's reviewer drove seven real screens by mounting [LumenRootScope] —
// *the exact widget `main()` builds* — with the real provider graph, real
// controllers, real repositories and the real cache layer, **faking only at the
// `LumenApiApi` boundary**. That is reproduced here rather than reinvented.
//
// A flow that stubs a controller is not a flow test; it is a widget test with
// extra steps. Every route test in this repo pins `DashboardController`,
// `ProfileController` or `OnboardingFlowController` because its subject is the
// route table — this file exists so the SEAMS BETWEEN those controllers get
// exercised end to end instead.
//
// ## Exactly three things are faked, and each is a platform edge
//
//  1. **`lumenApiProvider`** — the HTTP boundary. Everything above it (the
//     repositories, `cachedRead`/`cachedWrite`, `CacheKeys`, every controller,
//     the router and its gate) is production code.
//  2. **`cacheStoreProvider`** — [FlowCacheStore], a real stale-while-
//     revalidate store over a `Map` with an injected clock, instead of an
//     encrypted Hive box on disk. The cache *policy* is untouched: reads
//     short-circuit on `isFresh`, writes invalidate, and this harness records
//     every invalidation so a flow can assert WHICH day a write invalidated.
//     `emptyCacheStore()` (the always-miss mock every screen test uses) would
//     have made cache invalidation unobservable, because a store that never
//     serves anything cannot show that something was thrown away.
//  3. **`authStatusProvider`** — the same `FakeAuthController` `lumenOverrides`
//     pins for every widget test in this repo, for the reason stated there: the
//     real controller reaches for `FlutterSecureStorage` and a live OIDC client
//     on its first build. **This is the R-06 (ii) boundary**: the login leg is
//     the one part of these flows a CI-runnable suite genuinely cannot cover,
//     which is exactly why the manual walkthrough exists and starts there.
//
// ## What reached the wire (R2)
//
// Every serious defect this phase found was wire-level and screen-invisible: a
// duplicate symptom batch a "no exception" assertion sat green over (T21b), a
// never-paused user echoing six stale values back (T22a), a pause reason
// travelling without its flag (T22b), an empty-hint wipe (T16b). So [FlowWorld]
// records every request in order — [FlowWorld.wire] — and keeps the request
// OBJECT for every write, so a flow asserts the serialized body rather than
// "it did not throw".
//
// ## This harness is a MODEL of the server, and that is its largest limit
//
// [applyCycleSettingsPatch], [applyDayLogPatch] and the goals FULL REPLACE
// apply the server's own documented write rules BY HAND. A mock that echoed
// its request could not tell a client that re-sent stale values from one that
// sent nothing, which is precisely the T22a shape — but the cost is that **if
// the shipped service ever disagrees with what this file believes, the flow is
// green and the app is broken.** Nothing in CI can catch that; step 8 of the
// manual walk is where it gets checked.
//
// The stubs also model only ONE of the server's `Validate` 400s — the day
// log's all-absent rejection, because that 400 is the entire consequence of
// the T16b defect shape. Every other body production would reject is accepted
// here, so a *"this would be a 400"* reason string is asserted only indirectly,
// through the exact-map body assertions.
//
// ## Frames (R3)
//
// Nothing here settles. `pumpAndSettle` advances the fake clock through async
// work and observes the state after it resolves — T26 measured a whole phase's
// worth of screens spinning for 38 s behind exactly that. [pumpFlowFrames]
// drives a fixed, small number of zero-duration frames, and every call site
// says how many and why.

import 'dart:convert';

import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/create_symptoms_request.dart';
import 'package:lumen/api/model/create_symptoms_response.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/cycle_day_response.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/api/model/quick_checkin_request.dart';
import 'package:lumen/api/model/quick_checkin_response.dart';
import 'package:lumen/api/model/goals_response.dart';
import 'package:lumen/api/model/log_cycle_day_request.dart';
import 'package:lumen/api/model/register_device_request.dart';
import 'package:lumen/api/model/register_device_response.dart';
import 'package:lumen/api/model/save_baseline_request.dart';
import 'package:lumen/api/model/save_goals_request.dart';
import 'package:lumen/api/model/save_hormone_prefs_request.dart';
import 'package:lumen/api/model/save_notification_prefs_request.dart';
import 'package:lumen/api/model/save_onboarding_cycle_request.dart';
import 'package:lumen/api/model/symptom_entry_input.dart';
import 'package:lumen/api/model/symptom_list_response.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/api/model/update_cycle_settings_request.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/app.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:mocktail/mocktail.dart';

import '../support/harness.dart';

// ---------------------------------------------------------------------------
// The cache
// ---------------------------------------------------------------------------

/// The real stale-while-revalidate cache policy over an in-memory map.
///
/// A `Fake`, not a `Mock`: every member of [CacheStore] is implemented with the
/// behaviour `hive_boot.dart` documents, and anything added to that class later
/// throws here rather than silently answering null. The only thing standing in
/// is the STORAGE — a `Map` instead of an encrypted Hive box — because a box
/// needs `Hive.initFlutter`, a temp directory and a secure-storage key, none of
/// which is part of any seam a flow is about.
///
/// The clock is fixed. Freshness is therefore decided entirely by what the flow
/// itself wrote and invalidated, never by how long the test took to run.
class FlowCacheStore extends Fake implements CacheStore {
  FlowCacheStore({DateTime? now}) : _now = now ?? DateTime.utc(2026, 4, 20, 8);

  final DateTime _now;
  final Map<String, _Entry> _entries = <String, _Entry>{};

  /// Every key [invalidate] was asked to drop, in order — including keys that
  /// held nothing, because "the write named this key" is the assertion, not
  /// "something happened to be there".
  final List<String> invalidations = <String>[];

  /// Every key [putJson] wrote, in order.
  final List<String> writes = <String>[];

  @override
  Future<void> putJson(
    String key,
    Map<String, dynamic> value, {
    Duration? ttl,
  }) async {
    writes.add(key);
    _entries[key] = _Entry(value, _now, ttl);
  }

  @override
  Map<String, dynamic>? getJson(String key) => _entries[key]?.data;

  @override
  bool isFresh(String key) {
    final entry = _entries[key];
    if (entry == null || entry.ttl == null) return false;
    return _now.isBefore(entry.fetchedAt.add(entry.ttl!));
  }

  @override
  Future<void> invalidate(String key) async {
    invalidations.add(key);
    _entries.remove(key);
  }

  @override
  Future<void> purge() async => _entries.clear();

  /// Whether [key] currently holds anything at all.
  bool holds(String key) => _entries.containsKey(key);
}

class _Entry {
  _Entry(this.data, this.fetchedAt, this.ttl);
  final Map<String, dynamic> data;
  final DateTime fetchedAt;
  final Duration? ttl;
}

// ---------------------------------------------------------------------------
// The wire log
// ---------------------------------------------------------------------------

/// The one endpoint whose absence is itself an assertion.
///
/// `POST /me/devices` is wired at app start on every launch (R-09), and in P4b
/// `PushTokenSource` answers null, so nothing may reach the wire. It is stubbed
/// rather than left unstubbed because `PushRegistrationController._register`
/// catches everything — an unstubbed call would be swallowed into
/// `PushRegistrationOutcome.failed` and no flow would ever see it.
const String kDeviceRegisterOp = 'POST /me/devices';

/// `GET /cycle/calendar` with NO window — `ServerTodayRepository.today()`, the
/// one shared "what day is it" round trip (D-12).
const String kTodayOp = 'GET /cycle/calendar';

/// The dummies `any(named: …)` needs for the non-nullable request arguments.
///
/// Idempotent, so calling it per world is safe; called from [FlowWorld]'s
/// constructor rather than from each file's `setUpAll` so a new flow file
/// cannot forget one and fail with mocktail's generic message instead of its
/// own assertion.
void registerFlowFallbacks() {
  registerFallbackValue(Date(2026, 1, 1));
  registerFallbackValue(SaveOnboardingCycleRequest((b) => b));
  registerFallbackValue(SaveBaselineRequest((b) => b));
  registerFallbackValue(SaveGoalsRequest((b) => b));
  registerFallbackValue(SaveHormonePrefsRequest((b) => b));
  registerFallbackValue(SaveNotificationPrefsRequest((b) => b));
  registerFallbackValue(QuickCheckinRequest((b) => b));
  registerFallbackValue(LogCycleDayRequest((b) => b));
  registerFallbackValue(CreateSymptomsRequest((b) => b));
  registerFallbackValue(UpdateCycleSettingsRequest((b) => b));
  registerFallbackValue(RegisterDeviceRequest((b) => b));
}

// ---------------------------------------------------------------------------
// The world
// ---------------------------------------------------------------------------

/// A faked server, a real cache and the real app on top of both.
///
/// Every response is a mutable field rather than a constructor argument, so a
/// flow can change what the server holds BETWEEN steps — which is what a
/// multi-screen test is for. Answers are read at CALL time, never captured when
/// the stub is installed.
class FlowWorld {
  FlowWorld({DateTime? now, this.auth = AuthStatus.authenticated})
    : cache = FlowCacheStore(now: now) {
    registerFlowFallbacks();
    _install();
  }

  final MockLumenApiApi api = MockLumenApiApi();
  final FlowCacheStore cache;
  final AuthStatus auth;

  /// Every request that reached the faked HTTP boundary, in order.
  ///
  /// Method + path, with the window on the two windowed reads, because "which
  /// month" and "which day" are exactly the facts a hand-off can get wrong.
  final List<String> wire = <String>[];

  /// The request objects of every write, in order, per endpoint.
  final List<SaveOnboardingCycleRequest> onboardingCyclePosts =
      <SaveOnboardingCycleRequest>[];
  final List<SaveGoalsRequest> onboardingGoalsPosts = <SaveGoalsRequest>[];
  final List<SaveHormonePrefsRequest> onboardingHormonesPosts =
      <SaveHormonePrefsRequest>[];
  final List<SaveNotificationPrefsRequest> onboardingNotificationsPosts =
      <SaveNotificationPrefsRequest>[];
  final List<SaveBaselineRequest> onboardingBaselinePosts =
      <SaveBaselineRequest>[];
  final List<QuickCheckinRequest> checkinPosts = <QuickCheckinRequest>[];
  final List<CreateSymptomsRequest> symptomPosts = <CreateSymptomsRequest>[];
  final List<LogCycleDayRequest> dayLogPosts = <LogCycleDayRequest>[];
  final List<UpdateCycleSettingsRequest> settingsPatches =
      <UpdateCycleSettingsRequest>[];

  // ── What the server holds (mutable between steps) ────────────────────────

  /// `GET /me`.
  MeResponse me = meResponseFixture();

  /// `GET /onboarding/state`.
  OnboardingStateResponse onboardingState = onboardingStateFixture();

  /// `GET /settings/cycle`.
  CycleSettingsResponse cycleSettings = cycleSettingsFixture();

  /// The day `GET /cycle/calendar` (windowless) reports as the user's today.
  Date today = Date(2026, 4, 20);

  /// `GET /cycle/calendar?from&to` — one response per month key (`yyyy-MM`),
  /// defaulting to an empty month.
  final Map<String, CycleCalendarResponse> months =
      <String, CycleCalendarResponse>{};

  /// `GET /cycle/day/{date}` — one response per `yyyy-MM-dd`, defaulting to an
  /// empty day.
  final Map<String, CycleDayResponse> days = <String, CycleDayResponse>{};

  /// `GET /symptoms?from&to` — one response per `yyyy-MM-dd`, defaulting to an
  /// empty list.
  final Map<String, SymptomListResponse> symptomDays =
      <String, SymptomListResponse>{};

  // ── The answers writes give, injectable per test ─────────────────────────

  /// What `POST /cycle/day/{date}` does. Defaults to [applyDayLogPatch] over
  /// the stored day, INCLUDING the endpoint's own all-absent 400.
  Future<CycleDayLogResponse> Function(Date date, LogCycleDayRequest request)?
  onDayLogPost;

  /// What `POST /checkin/quick` does. Defaults to storing and echoing.
  Future<QuickCheckinResponse> Function(QuickCheckinRequest request)?
  onCheckinPost;

  /// What `POST /symptoms` does. Defaults to a 201 echoing one row per entry.
  Future<CreateSymptomsResponse> Function(CreateSymptomsRequest request)?
  onSymptomsPost;

  /// What `PATCH /settings/cycle` does. Defaults to applying the patch to
  /// [cycleSettings] and echoing the stored row.
  Future<CycleSettingsResponse> Function(UpdateCycleSettingsRequest request)?
  onSettingsPatch;

  /// What `POST /onboarding/cycle` does. Defaults to echoing the anchor.
  Future<OnboardingCycleResponse> Function(SaveOnboardingCycleRequest request)?
  onOnboardingCyclePost;

  /// What `GET /settings/cycle` does. Defaults to answering [cycleSettings];
  /// a flow that wants the read to FAIL throws [flowOffline] from here.
  Future<CycleSettingsResponse> Function()? onCycleSettingsGet;

  /// What `GET /onboarding/state` does. Defaults to answering
  /// [onboardingState]; a flow that wants the read to FAIL throws
  /// [flowOffline] from here.
  Future<OnboardingStateResponse> Function()? onOnboardingState;

  /// What `POST /onboarding/goals` does. Defaults to echoing the FULL REPLACE
  /// the request asked for, which is what the server stores.
  Future<GoalsResponse> Function(SaveGoalsRequest request)? onOnboardingGoals;

  /// What `POST /onboarding/complete` does. Defaults to a first completion.
  Future<OnboardingCompleteResponse> Function()? onOnboardingComplete;

  // ── Mounting ─────────────────────────────────────────────────────────────

  /// The container the app is mounted against, captured from inside
  /// [LumenRootScope] — the production scope, so a flow reads exactly the
  /// provider graph the shipped app builds.
  late final ProviderContainer container;

  /// Mounts the REAL app — [LumenRootScope] wrapping [LumenApp], the pair
  /// `main()` builds — at the splash, and lets the production redirect decide
  /// where the session lands.
  ///
  /// No settle, ever (R3): the splash draws an indeterminate
  /// `CircularProgressIndicator`, so settle would either never arrive or would
  /// silently advance the fake clock through work a flow is meant to observe.
  /// [frames] zero-duration frames are pumped instead — enough for the gate
  /// read, the redirect and the landing screen's own reads to resolve.
  Future<void> mount(WidgetTester tester, {int frames = 8}) async {
    await tester.binding.setSurfaceSize(kTestSurfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late ProviderContainer captured;
    await tester.pumpWidget(
      LumenRootScope(
        overrides: <Override>[
          ...lumenOverrides(auth: auth, api: api, cacheStore: cache),
        ],
        child: Builder(
          builder: (BuildContext context) {
            captured = ProviderScope.containerOf(context, listen: false);
            return const LumenApp();
          },
        ),
      ),
    );
    container = captured;
    await pumpFlowFrames(tester, frames);
    // The cold start is itself a NAVIGATION — `/splash` to wherever the gate
    // sends the session — so the clock has to advance past that page
    // transition before the landing screen is where it will be. Measured, and
    // the failure mode is nasty enough to be worth recording: with
    // zero-duration frames only, the shell is left mid-transition offset ~97 px
    // to the RIGHT, so `tester.getRect` reports the bottom nav at
    // `97.5..487.5` inside a 390-wide app and the last two destinations ("Body"
    // and "More") sit outside the surface entirely — `tester.tap` on them hits
    // nothing at all and only prints a warning. The first cut of this harness
    // did exactly that, and the flow that caught it looked like a broken
    // assertion, not a missed tap.
    await pumpRouteTransition(tester);
  }

  // ── Reading the wire back ────────────────────────────────────────────────

  /// How many times [op] reached the wire.
  int countOf(String op) => wire.where((String e) => e == op).length;

  /// The wire log with every occurrence of [ops] removed.
  ///
  /// For asserting the SHAPE of a flow's traffic without re-stating the reads a
  /// landing screen makes on its own — those have their own tests.
  List<String> wireWithout(Set<String> ops) =>
      wire.where((String e) => !ops.contains(e)).toList();

  /// Forgets everything recorded so far. Used between the phases of a long
  /// flow, so the assertion after a tap is about THAT tap.
  void clearWire() {
    wire.clear();
    cache.invalidations.clear();
    cache.writes.clear();
  }

  // ── Stubs ────────────────────────────────────────────────────────────────

  void _install() {
    // GET /me
    when(() => api.meGet()).thenAnswer((_) async {
      wire.add('GET /me');
      return _ok(me);
    });

    // GET /cycle/calendar — windowless (today) and windowed (a month) are the
    // SAME generated method; they are told apart by the arguments, exactly as
    // the server tells them apart.
    when(
      () => api.cycleCalendarGet(
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((Invocation call) async {
      final Date? from = call.namedArguments[#from] as Date?;
      final Date? to = call.namedArguments[#to] as Date?;
      if (from == null && to == null) {
        wire.add(kTodayOp);
        return _ok(cycleCalendarFixture(today: today));
      }
      final String key = _monthKey(from!);
      wire.add('GET /cycle/calendar?from=${_ymd(from)}&to=${_ymd(to!)}');
      return _ok(
        months[key] ??
            cycleCalendarFixture(
              today: today,
              from: from,
              to: to,
              days: const <CycleCalendarDay>[],
            ),
      );
    });

    // GET /cycle/day/{date}
    when(() => api.cycleDayDateGet(date: any(named: 'date'))).thenAnswer((
      Invocation call,
    ) async {
      final Date date = call.namedArguments[#date] as Date;
      wire.add('GET /cycle/day/${_ymd(date)}');
      return _ok(days[_ymd(date)] ?? cycleDayFixture(date: date));
    });

    // GET /symptoms?from&to
    when(
      () => api.symptomsGet(
        from: any(named: 'from'),
        to: any(named: 'to'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((Invocation call) async {
      final Date? from = call.namedArguments[#from] as Date?;
      final String key = from == null ? 'all' : _ymd(from);
      wire.add('GET /symptoms?from=$key');
      return _ok(
        symptomDays[key] ??
            symptomListResponseFixture(items: const <SymptomResponse>[]),
      );
    });

    // GET /onboarding/state
    when(() => api.onboardingStateGet()).thenAnswer((_) async {
      wire.add('GET /onboarding/state');
      final handler = onOnboardingState;
      return _ok(handler == null ? onboardingState : await handler());
    });

    // GET /settings/cycle
    when(() => api.settingsCycleGet()).thenAnswer((_) async {
      wire.add('GET /settings/cycle');
      final handler = onCycleSettingsGet;
      return _ok(handler == null ? cycleSettings : await handler());
    });

    // POST /onboarding/cycle
    when(
      () => api.onboardingCyclePost(
        saveOnboardingCycleRequest: any(named: 'saveOnboardingCycleRequest'),
      ),
    ).thenAnswer((Invocation call) async {
      final SaveOnboardingCycleRequest request =
          call.namedArguments[#saveOnboardingCycleRequest]
              as SaveOnboardingCycleRequest;
      wire.add('POST /onboarding/cycle');
      onboardingCyclePosts.add(request);
      final handler = onOnboardingCyclePost;
      if (handler != null) return _ok(await handler(request));
      return _ok(
        onboardingCycleFixture(lastPeriodStart: request.lastPeriodStart),
      );
    });

    // POST /onboarding/complete
    when(() => api.onboardingCompletePost()).thenAnswer((_) async {
      wire.add('POST /onboarding/complete');
      final handler = onOnboardingComplete;
      return _ok(
        handler == null ? onboardingCompleteFixture() : await handler(),
      );
    });

    // POST /onboarding/baseline
    when(
      () => api.onboardingBaselinePost(
        saveBaselineRequest: any(named: 'saveBaselineRequest'),
      ),
    ).thenAnswer((Invocation call) async {
      wire.add('POST /onboarding/baseline');
      onboardingBaselinePosts.add(
        call.namedArguments[#saveBaselineRequest] as SaveBaselineRequest,
      );
      return _ok(baselineFixture());
    });

    // POST /onboarding/goals — a FULL REPLACE: the array IS the complete
    // desired state, so the harness stores it rather than echoing the request
    // back unchanged. A stale prefill is then visible as what the SERVER ends
    // up holding, not merely as what the client sent.
    when(
      () => api.onboardingGoalsPost(
        saveGoalsRequest: any(named: 'saveGoalsRequest'),
      ),
    ).thenAnswer((Invocation call) async {
      final SaveGoalsRequest request =
          call.namedArguments[#saveGoalsRequest] as SaveGoalsRequest;
      wire.add('POST /onboarding/goals');
      onboardingGoalsPosts.add(request);
      final handler = onOnboardingGoals;
      if (handler != null) return _ok(await handler(request));
      final Set<String> chosen = request.goals?.toSet() ?? <String>{};
      return _ok(
        goalsResponseFixture(<String, bool>{
          for (final String code in kSeededGoals.keys)
            code: chosen.contains(code),
        }),
      );
    });

    // POST /onboarding/hormones
    when(
      () => api.onboardingHormonesPost(
        saveHormonePrefsRequest: any(named: 'saveHormonePrefsRequest'),
      ),
    ).thenAnswer((Invocation call) async {
      final SaveHormonePrefsRequest request =
          call.namedArguments[#saveHormonePrefsRequest]
              as SaveHormonePrefsRequest;
      wire.add('POST /onboarding/hormones');
      onboardingHormonesPosts.add(request);
      final Set<String> chosen = request.chartedHormones?.toSet() ?? <String>{};
      return _ok(
        hormonePrefsResponseFixture(<String, bool>{
          for (final String code in kSeededHormones.keys)
            code: chosen.contains(code),
        }),
      );
    });

    // POST /onboarding/notifications
    when(
      () => api.onboardingNotificationsPost(
        saveNotificationPrefsRequest: any(
          named: 'saveNotificationPrefsRequest',
        ),
      ),
    ).thenAnswer((Invocation call) async {
      final SaveNotificationPrefsRequest request =
          call.namedArguments[#saveNotificationPrefsRequest]
              as SaveNotificationPrefsRequest;
      wire.add('POST /onboarding/notifications');
      onboardingNotificationsPosts.add(request);
      final Set<String> chosen =
          request.enabledCategories?.toSet() ?? <String>{};
      return _ok(
        notificationPrefsResponseFixture(<String, bool>{
          for (final String code in kSeededNotifications.keys)
            code: chosen.contains(code),
        }),
      );
    });

    // POST /cycle/day/{date} — screen 11's day-log editor (T16b).
    //
    // The server's rules are APPLIED, not echoed, and this stub applies one
    // more of them than the others do: `CycleDayService.LogDayAsync`'s
    // all-absent 400. That 400 is the whole consequence of the T16b defect
    // shape — a `notes` guard re-derived from the VALUE lets an emptied note
    // box submit `notes: ""`, which the server trims to nothing, matches
    // against `request.Pain is null && request.Mood is null && notes is not
    // { Length: > 0 }`, and rejects. A stub that answered 200 to that body
    // would let the flow assert the wipe the defect does NOT cause and miss
    // the round trip it does.
    when(
      () => api.cycleDayDatePost(
        date: any(named: 'date'),
        logCycleDayRequest: any(named: 'logCycleDayRequest'),
      ),
    ).thenAnswer((Invocation call) async {
      final Date date = call.namedArguments[#date] as Date;
      final LogCycleDayRequest request =
          call.namedArguments[#logCycleDayRequest] as LogCycleDayRequest;
      wire.add('POST /cycle/day/${_ymd(date)}');
      dayLogPosts.add(request);
      final handler = onDayLogPost;
      if (handler != null) return _ok(await handler(date, request));

      final String? notes = request.notes?.trim();
      if (request.pain == null &&
          request.mood == null &&
          (notes == null || notes.isEmpty)) {
        throw const ValidationFailure(
          message: 'One or more validation errors occurred.',
          detail: 'One or more validation errors occurred.',
          fields: <String, List<String>>{
            'request': <String>[kServerDayLogEmpty],
          },
        );
      }

      final String key = _ymd(date);
      final CycleDayResponse day = days[key] ?? cycleDayFixture(date: date);
      final CycleDayLogResponse saved = applyDayLogPatch(
        day.log,
        date,
        request,
      );
      days[key] = day.rebuild((b) => b..log.replace(saved));
      return _ok(saved);
    });

    // POST /checkin/quick
    when(
      () => api.checkinQuickPost(
        quickCheckinRequest: any(named: 'quickCheckinRequest'),
      ),
    ).thenAnswer((Invocation call) async {
      final QuickCheckinRequest request =
          call.namedArguments[#quickCheckinRequest] as QuickCheckinRequest;
      wire.add('POST /checkin/quick');
      checkinPosts.add(request);
      final handler = onCheckinPost;
      if (handler != null) return _ok(await handler(request));
      return _ok(
        quickCheckinResponseFixture(
          day: today,
          pain: request.pain,
          mood: request.mood,
        ),
      );
    });

    // POST /symptoms
    when(
      () => api.symptomsPost(
        createSymptomsRequest: any(named: 'createSymptomsRequest'),
      ),
    ).thenAnswer((Invocation call) async {
      final CreateSymptomsRequest request =
          call.namedArguments[#createSymptomsRequest] as CreateSymptomsRequest;
      wire.add('POST /symptoms');
      symptomPosts.add(request);
      final handler = onSymptomsPost;
      if (handler != null) return _ok(await handler(request));
      final List<SymptomEntryInput> entries =
          request.entries?.toList() ?? <SymptomEntryInput>[];
      return _ok(
        createSymptomsResponseFixture(
          items: <SymptomResponse>[
            for (int i = 0; i < entries.length; i++)
              symptomResponseFixture(
                id: 'symptom-$i',
                // The server's own default for an entry that named no code
                // (`SymptomService.cs`: the pain row).
                symptomCode: entries[i].symptomCode ?? 'pain',
                intensity: entries[i].intensity,
                region: entries[i].region,
                occurredOn: today,
              ),
          ],
        ),
      );
    });

    // PATCH /settings/cycle
    when(
      () => api.settingsCyclePatch(
        updateCycleSettingsRequest: any(named: 'updateCycleSettingsRequest'),
      ),
    ).thenAnswer((Invocation call) async {
      final UpdateCycleSettingsRequest request =
          call.namedArguments[#updateCycleSettingsRequest]
              as UpdateCycleSettingsRequest;
      wire.add('PATCH /settings/cycle');
      settingsPatches.add(request);
      final handler = onSettingsPatch;
      if (handler != null) return _ok(await handler(request));
      cycleSettings = applyCycleSettingsPatch(cycleSettings, request);
      return _ok(cycleSettings);
    });

    // POST /me/devices — see [kDeviceRegisterOp].
    when(
      () => api.meDevicesPost(
        registerDeviceRequest: any(named: 'registerDeviceRequest'),
      ),
    ).thenAnswer((_) async {
      wire.add(kDeviceRegisterOp);
      return _ok(RegisterDeviceResponse((b) => b..deviceId = 'device-1'));
    });
  }
}

// ---------------------------------------------------------------------------
// The server's own write rules, applied rather than echoed
// ---------------------------------------------------------------------------

/// `PATCH /settings/cycle`'s MERGE semantics, applied to [current].
///
/// A mock that echoed its request could not tell a client that re-sent stale
/// values from one that sent nothing — which is precisely the T22a defect (a
/// never-paused user's echo re-asserting six stale values). So the harness
/// stores, exactly as `CycleSettingsService.UpdateAsync` does: an omitted
/// member leaves the stored value alone.
///
/// The pause triple follows the shipped server rule (T22b): `trackingPaused:
/// false` clears the date and PRESERVES the reason — *"there is deliberately no
/// CHECK tying it to `TrackingPaused`"* — which is the state that makes a
/// resumed user's echo a 400 in production and is therefore the state a flow
/// must be able to reach.
CycleSettingsResponse applyCycleSettingsPatch(
  CycleSettingsResponse current,
  UpdateCycleSettingsRequest patch,
) {
  return CycleSettingsResponse(
    (b) => b
      ..avgCycleLengthDays =
          patch.avgCycleLengthDays ?? current.avgCycleLengthDays
      ..avgPeriodLengthDays =
          patch.avgPeriodLengthDays ?? current.avgPeriodLengthDays
      ..regularity = patch.regularity ?? current.regularity
      ..phasePredictionEnabled =
          patch.phasePredictionEnabled ?? current.phasePredictionEnabled
      ..autoDetectPeriodStartEnabled =
          patch.autoDetectPeriodStartEnabled ??
          current.autoDetectPeriodStartEnabled
      ..showFertilityWindowEnabled =
          patch.showFertilityWindowEnabled ?? current.showFertilityWindowEnabled
      ..trackingPaused = patch.trackingPaused ?? current.trackingPaused
      ..pauseReason = patch.pauseReason ?? current.pauseReason
      ..pausedSince = patch.trackingPaused == false
          ? null
          : (patch.pausedSince ?? current.pausedSince)
      ..phasesUnavailable =
          (patch.trackingPaused ?? current.trackingPaused ?? false) ||
          (patch.phasePredictionEnabled ??
                  current.phasePredictionEnabled ??
                  true) ==
              false
      ..createdAt = current.createdAt ?? DateTime.utc(2026, 1, 1)
      ..updatedAt = DateTime.utc(2026, 4, 20, 8),
  );
}

/// `CycleDayService`'s cross-field 400, verbatim
/// (`CycleContracts.cs`, `CycleValidationMessages.DayLogEmpty`).
///
/// Spelled out here rather than imported because it is the SERVER's sentence;
/// the client has its own, deliberately different one
/// (`kDayLogEmptyChangeMessage`, whose dartdoc records why the two are not
/// mirrored). A flow that saw this string in a banner would be seeing a round
/// trip the client should have prevented.
const String kServerDayLogEmpty =
    'at least one of pain, mood or notes is required';

/// `POST /cycle/day/{date}`'s MERGE semantics, applied to [current].
///
/// `CycleDayService.LogDayAsync`, rule for rule:
///
///  * **pain and mood merge on `is { } value`**, so a supplied `0` OVERWRITES
///    and an omitted key leaves the column alone. `patch.pain ?? current?.pain`
///    is that, exactly — `0 ?? x` is `0` in Dart — and it is why the harness
///    must not use a truthiness test either (D-08).
///  * **A blank or whitespace-only note is ABSENT TEXT, not an erase.** The
///    service trims first and only writes `NotesEnc` when the result is
///    non-empty; otherwise it echoes the STORED note back, *"reporting null
///    would render the day as note-less on the very screen that wrote the
///    note, which is the read half of the same wipe"*. So an emptied box
///    cannot destroy a note on this endpoint — what it can do is make the
///    whole request all-absent, which is the 400 the stub above raises.
///
/// **This is a MODEL of the server, and the flow suite's largest limit.** If
/// the shipped service ever diverges from these three lines, every flow that
/// asserts through them stays green while the app is wrong — which is why
/// step 8 of the manual walk exists.
CycleDayLogResponse applyDayLogPatch(
  CycleDayLogResponse? current,
  Date day,
  LogCycleDayRequest patch,
) {
  final String? notes = patch.notes?.trim();
  return CycleDayLogResponse(
    (b) => b
      ..day = day
      ..pain = patch.pain ?? current?.pain
      ..mood = patch.mood ?? current?.mood
      ..notes = (notes != null && notes.isNotEmpty) ? notes : current?.notes
      ..createdAt = current?.createdAt ?? DateTime.utc(2026, 4, 20, 8)
      ..updatedAt = DateTime.utc(2026, 4, 20, 8),
  );
}

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

/// Pumps [count] zero-duration frames.
///
/// **Never `pumpAndSettle` (R3).** Settling runs the fake clock forward until
/// nothing is scheduled, which means it walks through retry backoffs, timeouts
/// and animations and then asserts about the state on the far side; T26 proved
/// that a settling widget test is structurally blind to a class of defect this
/// phase actually shipped. A fixed, small frame count observes the app the way
/// a user does — a few frames after a tap — and reddens if a hand-off starts
/// taking materially longer.
///
/// One frame flushes one turn of microtasks, and the deepest chain in this app
/// is the dashboard's (`sessionTodayProvider` → two month reads → the combining
/// step), so the defaults below are the measured depth plus headroom, not a
/// number chosen to make something pass.
Future<void> pumpFlowFrames(WidgetTester tester, [int count = 4]) async {
  for (int i = 0; i < count; i++) {
    await tester.pump();
  }
}

/// Pumps a route transition to completion by hand.
///
/// **[kFlowTransition] is measured, and it is a CEILING rather than the
/// number.** A pushed route is findable from its first frame, so only a POP
/// needs the full duration — and getting that number wrong does not fail
/// loudly: it leaves the popped screen findable and turns "screen 12 left
/// after the save" into a false NEGATIVE, which is the one direction a test
/// must never be wrong in. Measured by pumping 50 ms at a time after a
/// successful save on screen 12, the route was gone at **450 ms** in one
/// arrangement and at **550 ms** in another (go_router's `MaterialPage` under
/// Android's zoom transition, not the 300 ms a bare `MaterialPageRoute`
/// advertises; where the pop lands relative to a frame boundary moves it).
/// 800 ms is that range plus headroom, and it is still far short of anything
/// this app schedules on a timer — the nearest is the onboarding gate's 8 s
/// bounded wait.
///
/// **This is not a settle.** `pumpAndSettle` advances the clock until nothing
/// is scheduled, which is how a test walks unknowingly through ten retry
/// backoffs; this advances a stated, bounded amount and would still redden if
/// a hand-off started taking a second.
const Duration kFlowTransition = Duration(milliseconds: 800);

Future<void> pumpRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(kFlowTransition);
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

/// [request], serialized exactly as it would go on the wire.
///
/// This is the level R2 is about. `built_value` DROPS a null member from its
/// own serialized form, so a key that is PRESENT in this map was genuinely
/// sent, and a key that is ABSENT was genuinely omitted — which is the whole
/// difference between "leave the stored value alone" and "overwrite it" on
/// every MERGE endpoint in this contract. Comparing request OBJECTS instead
/// would collapse the two.
Map<String, dynamic> wireBody<T>(Serializer<T> serializer, T request) {
  final Object? encoded = standardSerializers.serializeWith(
    serializer,
    request,
  );
  return json.decode(json.encode(encoded)) as Map<String, dynamic>;
}

/// The `DioException` a dead connection produces — the exact shape
/// `apiNetworkFailure` throws, so a flow's offline case travels the identical
/// mapping (`mapDioException` -> `NetworkFailure` -> `cachedRead`'s `Stale` /
/// `NetworkRequired`) rather than a second one invented here.
DioException flowOffline({String path = '/'}) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.connectionError,
);

/// A 200 carrying [body], at the one path the generated client would have used.
Response<T> _ok<T>(T body) => Response<T>(
  requestOptions: RequestOptions(path: '/'),
  statusCode: 200,
  data: body,
);

String _ymd(Date date) =>
    '${_pad(date.year, 4)}-${_pad(date.month, 2)}-${_pad(date.day, 2)}';

String _monthKey(Date date) => '${_pad(date.year, 4)}-${_pad(date.month, 2)}';

String _pad(int value, int width) => value.toString().padLeft(width, '0');

/// The key [FlowWorld.months] files a month's response under — `yyyy-MM`.
///
/// Deliberately NOT [CacheKeys.cycleCalendarMonth]: that is the CACHE key, and
/// a flow that seeded the server's answers under the cache key would look right
/// and silently seed nothing (the first cut of this file did exactly that, and
/// the flow it broke went green on the pre-write render).
String flowMonth(DateTime date) =>
    '${_pad(date.year, 4)}-${_pad(date.month, 2)}';

/// The cache key the month containing [date] is filed under — built through
/// [CacheKeys] rather than spelled out, so a flow asserting an invalidation is
/// asserting against the policy the repository actually used.
String flowMonthCacheKey(DateTime date) => CacheKeys.cycleCalendarMonth(date);
