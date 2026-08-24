// CycleSetupController — screen 3's state (P4b-T9).
//
// Screen 3 collects the one mandatory answer of onboarding (D-02), and it is
// also the screen a user comes back to in order to fix a mistyped date. Both
// facts point at the same property, and most of this file is about it: the
// screen must never send an answer it is not showing. `POST /onboarding/cycle`
// MERGES, so a field the client fills in "helpfully" overwrites a real answer
// with a default, and `GET /onboarding/state` cannot give that answer back.
//
// The resume is therefore TWO reads. `GET /onboarding/state` (already made by
// the shell) carries `lastPeriodStart`; `GET /settings/cycle` carries
// `avgCycleLengthDays` and `regularity`. A third read, `GET /cycle/calendar`,
// answers the one thing D-12 forbids the client to work out for itself —
// today — and everything that depends on it degrades rather than guesses.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockCycleSettingsRepository extends Mock
    implements CycleSettingsRepository {}

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// The shell's flow, settled on step 3 with [lastPeriodStart] already read.
///
/// The step body only ever renders inside the shell's `data` arm, so the flow
/// is settled by construction — which is why this controller reads the anchor
/// straight off it instead of issuing a second `GET /onboarding/state`.
class _SettledFlow extends OnboardingFlowController {
  _SettledFlow({this.lastPeriodStart});

  final Date? lastPeriodStart;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: OnboardingStep.cycle,
      state: onboardingStateFixture(lastPeriodStart: lastPeriodStart),
    ),
  );
}

/// One assembled screen-3 world.
class _World {
  _World({
    Date? resumeAnchor,
    CycleSettingsResponse? settings,
    Failure? settingsFailure,
    Date? today,
    Failure? todayFailure,
    Completer<CacheResult<CycleSettingsResponse>>? settingsGate,
    Completer<Date>? todayGate,
  }) : settingsRepo = _MockCycleSettingsRepository(),
       todayRepo = _MockServerTodayRepository(),
       onboardingRepo = _MockOnboardingRepository() {
    if (settingsGate != null) {
      when(settingsRepo.getSettings).thenAnswer((_) => settingsGate.future);
    } else if (settingsFailure != null) {
      when(settingsRepo.getSettings).thenAnswer(
        (_) async => NetworkRequired<CycleSettingsResponse>(settingsFailure),
      );
    } else {
      when(settingsRepo.getSettings).thenAnswer(
        (_) async =>
            Fresh<CycleSettingsResponse>(settings ?? cycleSettingsFixture()),
      );
    }

    if (todayGate != null) {
      when(todayRepo.today).thenAnswer((_) => todayGate.future);
    } else if (todayFailure != null) {
      when(todayRepo.today).thenAnswer((_) async => throw todayFailure);
    } else {
      when(todayRepo.today).thenAnswer((_) async => today ?? Date(2026, 4, 20));
    }

    container = ProviderContainer(
      retry: lumenRetry,
      overrides: <Override>[
        onboardingFlowControllerProvider.overrideWith(
          () => _SettledFlow(lastPeriodStart: resumeAnchor),
        ),
        cycleSettingsRepositoryProvider.overrideWithValue(settingsRepo),
        serverTodayRepositoryProvider.overrideWithValue(todayRepo),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepo),
      ],
    );
    addTearDown(container.dispose);

    // Both providers are autoDispose. A bare `read` disposes them as it
    // returns, so the deferred load would find `ref.mounted == false` and
    // resolve nothing; a subscription is what a screen's `ref.watch` does.
    container.listen(cycleSetupControllerProvider, (_, _) {});
    container.listen(onboardingFlowControllerProvider, (_, _) {});
  }

  final _MockCycleSettingsRepository settingsRepo;
  final _MockServerTodayRepository todayRepo;
  final _MockOnboardingRepository onboardingRepo;
  late final ProviderContainer container;

  CycleSetupController get notifier =>
      container.read(cycleSetupControllerProvider.notifier);

  AsyncValue<CycleSetupForm> get state =>
      container.read(cycleSetupControllerProvider);

  CycleSetupForm get form => state.value!;

  OnboardingStep get step =>
      container.read(onboardingFlowControllerProvider).value!.step;

  /// Lets the deferred load run to completion.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  void answerSave([OnboardingCycleResponse? body]) {
    when(
      () => onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    ).thenAnswer((_) async => body ?? onboardingCycleFixture());
  }

  void rejectSave(Object error) {
    when(
      () => onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    ).thenAnswer((_) async => throw error);
  }

  void pendSave(Completer<OnboardingCycleResponse> release) {
    when(
      () => onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    ).thenAnswer((_) => release.future);
  }

  VerificationResult verifySaves() => verify(
    () => onboardingRepo.saveCycle(
      lastPeriodStart: captureAny(named: 'lastPeriodStart'),
      avgCycleLengthDays: captureAny(named: 'avgCycleLengthDays'),
      regularity: captureAny(named: 'regularity'),
      previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
    ),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(Date(2026, 1, 1)));

  // -------------------------------------------------------------------------
  // The vocabulary
  // -------------------------------------------------------------------------

  group('CycleRegularity', () {
    test('it carries the three ratified codes and their labels', () {
      expect(CycleRegularity.values.map((r) => r.wireName).toList(), <String>[
        'regular',
        'somewhat',
        'irregular',
      ]);
      expect(CycleRegularity.values.map((r) => r.label).toList(), <String>[
        'Regular',
        'Somewhat',
        'Irregular',
      ]);
    });

    test('it matches a wire code exactly, and nothing else', () {
      // The server compares with StringComparer.Ordinal and answers 400 for
      // anything else, so a client that normalised case would send a value it
      // believed was valid.
      expect(
        CycleRegularity.fromWireName('somewhat'),
        CycleRegularity.somewhat,
      );
      for (final near in <String?>[
        'Somewhat',
        'SOMEWHAT',
        ' somewhat',
        'somewhat ',
        'sometimes',
        '',
        null,
      ]) {
        expect(CycleRegularity.fromWireName(near), isNull, reason: '$near');
      }
    });
  });

  // -------------------------------------------------------------------------
  // The quick picks
  // -------------------------------------------------------------------------

  test(
    'the quick picks are the five the mockup draws, over a free integer',
    () {
      expect(kAvgCycleLengthQuickPicks, <int>[26, 27, 28, 29, 30]);
    },
  );

  // -------------------------------------------------------------------------
  // Resume — what each of the two reads supplies
  // -------------------------------------------------------------------------

  test('it opens on the month of the anchor the user already gave', () async {
    final resumed = _World(
      resumeAnchor: Date(2026, 3, 9),
      today: Date(2026, 4, 20),
    );
    await resumed.settle();

    expect(resumed.form.visibleMonth, DateTime(2026, 3));
    expect(resumed.form.answers.lastPeriodStart, Date(2026, 3, 9));

    // The control, and the discrimination: a controller that always opened on
    // today would answer April for BOTH of these. The month is a property of
    // which read had something to say.
    final fresh = _World(today: Date(2026, 4, 20));
    await fresh.settle();

    expect(fresh.form.visibleMonth, DateTime(2026, 4));
    expect(fresh.form.answers.lastPeriodStart, isNull);
  });

  test('it prefills the two self-reports from GET /settings/cycle', () async {
    final world = _World(
      settings: cycleSettingsFixture(
        avgCycleLengthDays: 29,
        regularity: 'irregular',
      ),
    );
    await world.settle();

    // 29 / irregular is deliberately NOT the documented default: a controller
    // that showed 28 / somewhat regardless of the response would pass an
    // assertion written against the defaults.
    expect(world.form.answers.avgCycleLengthDays, 29);
    expect(world.form.answers.regularity, CycleRegularity.irregular);

    // The other half of the same property: the "no row yet" answer is the
    // server's defaults, arriving the same way — the client applies none of
    // its own.
    final blank = _World(settings: cycleSettingsFixture());
    await blank.settle();
    expect(blank.form.answers.avgCycleLengthDays, 28);
    expect(blank.form.answers.regularity, CycleRegularity.somewhat);
  });

  test('a settings read that failed leaves both answers UNKNOWN', () async {
    final offline = _World(settingsFailure: const NetworkFailure());
    await offline.settle();

    expect(offline.form.answers.avgCycleLengthDays, isNull);
    expect(offline.form.answers.regularity, isNull);
    expect(offline.form.failure, isA<NetworkFailure>());

    // Positive control: null is also what a controller that never read the
    // settings at all would hold. The same controller, given a working read,
    // must show the answer — and must show no failure.
    final online = _World(
      settings: cycleSettingsFixture(avgCycleLengthDays: 29),
    );
    await online.settle();
    expect(online.form.answers.avgCycleLengthDays, 29);
    expect(online.form.failure, isNull);
  });

  test('a stale settings read is used exactly like a fresh one', () async {
    final world = _World();
    when(world.settingsRepo.getSettings).thenAnswer(
      (_) async => Stale<CycleSettingsResponse>(
        cycleSettingsFixture(avgCycleLengthDays: 31, regularity: 'regular'),
      ),
    );
    await world.settle();

    expect(world.form.answers.avgCycleLengthDays, 31);
    expect(world.form.answers.regularity, CycleRegularity.regular);
    expect(world.form.failure, isNull);
  });

  test(
    'with neither an anchor nor a today there is no calendar to draw',
    () async {
      final stranded = _World(todayFailure: const NetworkFailure());
      await stranded.settle();

      // No month can be opened without inventing one, and the only thing left to
      // invent it from is the device clock, which D-12 forbids. So the screen
      // gets a whole-surface failure and a retry instead of a calendar.
      expect(stranded.state, isA<AsyncError<CycleSetupForm>>());
      expect(
        (stranded.state as AsyncError<CycleSetupForm>).error,
        isA<NetworkFailure>(),
      );

      // Control: the SAME today failure is survivable once the resume read has
      // an anchor of its own to open on.
      final resumed = _World(
        resumeAnchor: Date(2026, 3, 9),
        todayFailure: const NetworkFailure(),
      );
      await resumed.settle();
      expect(resumed.state, isA<AsyncData<CycleSetupForm>>());
      expect(resumed.form.visibleMonth, DateTime(2026, 3));
      expect(resumed.form.today, isNull);
    },
  );

  test(
    'the two resume reads are issued TOGETHER, not one after the other',
    () async {
      final settingsGate = Completer<CacheResult<CycleSettingsResponse>>();
      final todayGate = Completer<Date>();
      final world = _World(settingsGate: settingsGate, todayGate: todayGate);

      await world.settle();

      // Neither read has answered — that is the control, and it is what makes
      // the two lines below mean "concurrently" rather than "eventually". A
      // serial load cannot have asked the second question yet.
      expect(world.state, isA<AsyncLoading<CycleSetupForm>>());
      verify(world.settingsRepo.getSettings).called(1);
      verify(world.todayRepo.today).called(1);

      settingsGate.complete(
        Fresh<CycleSettingsResponse>(
          cycleSettingsFixture(avgCycleLengthDays: 29),
        ),
      );
      todayGate.complete(Date(2026, 4, 20));
      await world.settle();

      // …and both answers still land where they belong.
      expect(world.form.answers.avgCycleLengthDays, 29);
      expect(world.form.today, Date(2026, 4, 20));
    },
  );

  test('shares its "today" round trip with another dated screen on the same '
      'session, via sessionTodayProvider — fix round 1 / M-1: the regression '
      'this controller would silently reintroduce by going back to calling '
      'ServerTodayRepository directly', () async {
    final world = _World(today: Date(2026, 4, 20));
    await world.settle();
    expect(
      world.form.today,
      Date(2026, 4, 20),
      reason: 'premise: the controller\'s own resume read succeeded',
    );

    // A DIFFERENT dated screen (T15's dashboard, T16's day detail, …) on
    // the SAME container reads sessionTodayProvider directly. If this
    // controller still called ServerTodayRepository.today() directly
    // (bypassing the shared provider), sessionTodayProvider would never
    // have been built yet — this read would be ITS first, and
    // `todayRepo.today` would show TWO calls total. Routed through the
    // shared provider as intended, the controller's own read already
    // pinned the value, so this is a cache hit: the total stays at one.
    final sharedRead = await world.container.read(sessionTodayProvider.future);

    expect(sharedRead, Date(2026, 4, 20));
    verify(world.todayRepo.today).called(1);
  });

  // -------------------------------------------------------------------------
  // Choosing a day — the one server rule the client can mirror
  // -------------------------------------------------------------------------

  test('today can be chosen and tomorrow cannot', () async {
    final world = _World(today: Date(2026, 4, 20));
    await world.settle();

    // The ACCEPTING boundary, asserted as deliberately as the rejecting one:
    // the server rejects `lastPeriodStart > today`, so today itself is a
    // legitimate answer and a client that refused it would lose a real one.
    world.notifier.chooseDay(Date(2026, 4, 20));
    expect(world.form.answers.lastPeriodStart, Date(2026, 4, 20));

    world.notifier.chooseDay(Date(2026, 4, 21));
    expect(
      world.form.answers.lastPeriodStart,
      Date(2026, 4, 20),
      reason: 'a future day must not become the anchor',
    );
  });

  test('with no server today, no day is refused', () async {
    final unknown = _World(
      resumeAnchor: Date(2026, 3, 9),
      todayFailure: const NetworkFailure(),
    );
    await unknown.settle();

    // The bound is the server's answer or it is absent — never a guess. The
    // server still rejects the write, and its message reaches the field.
    unknown.notifier.chooseDay(Date(2026, 4, 21));
    expect(unknown.form.answers.lastPeriodStart, Date(2026, 4, 21));

    // Control: the same day IS refused when today is known, so the line above
    // is about the missing bound rather than about a controller with no bound
    // at all.
    final known = _World(today: Date(2026, 4, 20));
    await known.settle();
    known.notifier.chooseDay(Date(2026, 4, 21));
    expect(known.form.answers.lastPeriodStart, isNull);
  });

  test('month navigation stops at the month holding today', () async {
    final world = _World(today: Date(2026, 4, 20));
    await world.settle();

    // Backwards always works…
    world.notifier.showPreviousMonth();
    expect(world.form.visibleMonth, DateTime(2026, 3));
    world.notifier.showNextMonth();
    expect(world.form.visibleMonth, DateTime(2026, 4));

    // …forwards stops, because every day past today is unselectable and a
    // month of them is a dead end.
    world.notifier.showNextMonth();
    expect(world.form.visibleMonth, DateTime(2026, 4));
    expect(world.form.canShowNextMonth, isFalse);

    // Control: the cap is today's, not a refusal to ever move forward.
    world.notifier.showPreviousMonth();
    expect(world.form.canShowNextMonth, isTrue);
  });

  // -------------------------------------------------------------------------
  // Submitting — the merge
  // -------------------------------------------------------------------------

  test('it sends the anchor and only the answers it is showing', () async {
    final world = _World(settingsFailure: const NetworkFailure());
    await world.settle();
    world.answerSave();

    world.notifier.chooseDay(Date(2026, 4, 6));
    await world.notifier.submit();

    var captured = world.verifySaves().captured;
    expect(captured, <Object?>[Date(2026, 4, 6), null, null]);

    // The control this whole test exists for: those two nulls are also what a
    // screen that never sends anything produces. Choose the two answers and
    // they must travel — a full-replace regression (sending 28 / `somewhat`
    // because "the screen shows a default") reddens the first assertion, and a
    // screen that sends nothing at all reddens this one.
    world.notifier.chooseCycleLength(29);
    world.notifier.chooseRegularity(CycleRegularity.irregular);
    await world.notifier.submit();

    captured = world.verifySaves().captured;
    expect(captured, <Object?>[Date(2026, 4, 6), 29, 'irregular']);
  });

  test('a value it only READ is never written back', () async {
    final world = _World(
      settings: cycleSettingsFixture(
        avgCycleLengthDays: 29,
        regularity: 'irregular',
      ),
    );
    await world.settle();
    world.answerSave(
      onboardingCycleFixture(
        lastPeriodStart: Date(2026, 4, 6),
        avgCycleLengthDays: 29,
        regularity: 'irregular',
      ),
    );

    // Premise: both answers ARE on screen, so omitting them below is a
    // decision about the write rather than about an empty form.
    expect(world.form.answers.avgCycleLengthDays, 29);
    expect(world.form.answers.regularity, CycleRegularity.irregular);

    world.notifier.chooseDay(Date(2026, 4, 6));
    await world.notifier.submit();

    // `GET /settings/cycle` is stale-while-revalidate: the 29 on screen may be
    // a cache entry served after a failed refresh while screen 32 on another
    // device set something else. Re-sending it turns a READ into a WRITE and
    // silently reverts the other device's answer.
    expect(world.verifySaves().captured, <Object?>[
      Date(2026, 4, 6),
      null,
      null,
    ]);

    // Positive control: null here must mean "unchanged", not "never sent".
    // Change ONE of them and exactly that one travels.
    world.notifier.chooseCycleLength(30);
    world.answerSave(
      onboardingCycleFixture(
        lastPeriodStart: Date(2026, 4, 6),
        avgCycleLengthDays: 30,
        regularity: 'irregular',
      ),
    );
    await world.notifier.submit();

    expect(world.verifySaves().captured, <Object?>[Date(2026, 4, 6), 30, null]);
  });

  test('a warning this build cannot render does not hold the step', () async {
    final unknown = _World();
    await unknown.settle();
    unknown.answerSave(
      onboardingCycleFixture(warnings: const <String>['some_future_code']),
    );

    unknown.notifier.chooseDay(Date(2026, 4, 6));
    await unknown.notifier.submit();

    // The vocabulary is append-only, so a third code will arrive at a build
    // that has never seen it. Holding the step for it shows the user an
    // unchanged page and a Continue that appears to do nothing.
    expect(unknown.step, OnboardingStep.baseline);
    // …and the state still records what the server actually said.
    expect(unknown.form.warnings, <String>['some_future_code']);

    // Control: a code that DOES render still holds the step, even alongside one
    // that does not — the gate is "is there anything to show", not "were there
    // any warnings".
    final mixed = _World();
    await mixed.settle();
    mixed.answerSave(
      onboardingCycleFixture(
        warnings: const <String>[
          'some_future_code',
          'avg_cycle_length_out_of_sanity_band',
        ],
      ),
    );

    mixed.notifier.chooseDay(Date(2026, 4, 6));
    await mixed.notifier.submit();

    expect(mixed.step, OnboardingStep.cycle);
  });

  test('it tells the repository which day the anchor is moving off', () async {
    final world = _World(resumeAnchor: Date(2026, 3, 9));
    await world.settle();
    world.answerSave(onboardingCycleFixture(lastPeriodStart: Date(2026, 4, 6)));

    world.notifier.chooseDay(Date(2026, 4, 6));
    await world.notifier.submit();

    final previous = verify(
      () => world.onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: captureAny(named: 'previousLastPeriodStart'),
      ),
    ).captured.single;

    // The day the server currently holds the anchor on — not the day being
    // sent. It is what lets the write drop the cached March calendar the
    // anchor is leaving.
    expect(previous, Date(2026, 3, 9));
  });

  test('it adopts the values the server echoed back', () async {
    final world = _World(settingsFailure: const NetworkFailure());
    await world.settle();
    world.answerSave(
      onboardingCycleFixture(
        lastPeriodStart: Date(2026, 4, 6),
        avgCycleLengthDays: 28,
        regularity: 'somewhat',
      ),
    );

    world.notifier.chooseDay(Date(2026, 4, 6));
    // Premise: the screen showed neither answer before the save, so the two
    // below can only have come from the response.
    expect(world.form.answers.avgCycleLengthDays, isNull);
    expect(world.form.answers.regularity, isNull);

    await world.notifier.submit();

    expect(world.form.answers.avgCycleLengthDays, 28);
    expect(world.form.answers.regularity, CycleRegularity.somewhat);
  });

  // -------------------------------------------------------------------------
  // Submitting — what happens next
  // -------------------------------------------------------------------------

  test('a clean save walks on to the next step', () async {
    final world = _World();
    await world.settle();
    world.answerSave();

    expect(world.step, OnboardingStep.cycle);
    world.notifier.chooseDay(Date(2026, 4, 6));
    await world.notifier.submit();

    expect(world.step, OnboardingStep.baseline);
  });

  test(
    'a save that came back warned stays put and carries the warning',
    () async {
      final world = _World();
      await world.settle();
      world.answerSave(
        onboardingCycleFixture(
          warnings: const <String>['avg_period_length_out_of_sanity_band'],
        ),
      );

      expect(world.step, OnboardingStep.cycle);
      world.notifier.chooseDay(Date(2026, 4, 6));
      await world.notifier.submit();

      // The save SUCCEEDED — the band never blocks a write — and the hint is
      // worth nothing on a screen the user has already left.
      expect(world.form.warnings, <String>[
        'avg_period_length_out_of_sanity_band',
      ]);
      expect(world.step, OnboardingStep.cycle);
      expect(world.form.failure, isNull);
    },
  );

  test('pressing Continue again after a warned save walks on WITHOUT '
      're-posting', () async {
    final world = _World();
    await world.settle();
    world.answerSave(
      onboardingCycleFixture(
        warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
      ),
    );

    world.notifier.chooseDay(Date(2026, 4, 6));
    await world.notifier.submit();
    world.verifySaves().called(1);
    expect(world.step, OnboardingStep.cycle);

    await world.notifier.submit();

    // Re-posting would return the same warning and trap the user on the step
    // forever — the hint would have become the entry blocker rider 7 forbids.
    verifyNever(
      () => world.onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    );
    expect(world.step, OnboardingStep.baseline);
  });

  test(
    'changing an answer after a save makes the next Continue post again',
    () async {
      final world = _World();
      await world.settle();
      world.answerSave(
        onboardingCycleFixture(
          warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
        ),
      );

      world.notifier.chooseDay(Date(2026, 4, 6));
      await world.notifier.submit();
      world.verifySaves().called(1);

      // The control for the test above: the "do not re-post" short circuit is
      // about the answers being UNCHANGED, not about a second submit being
      // ignored.
      world.notifier.chooseCycleLength(29);
      await world.notifier.submit();
      world.verifySaves().called(1);
    },
  );

  test(
    'a rejection keeps the user on the step, with the server\'s message',
    () async {
      final world = _World();
      await world.settle();
      world.rejectSave(
        const ValidationFailure(
          message: 'The request contained invalid data.',
          fields: <String, List<String>>{
            'lastPeriodStart': <String>[
              'date is before the earliest allowed date',
            ],
          },
        ),
      );

      world.notifier.chooseDay(Date(2020, 1, 1));
      expect(world.form.failure, isNull);

      await world.notifier.submit();

      expect(world.form.failure, isA<ValidationFailure>());
      expect(
        (world.form.failure! as ValidationFailure).messageFor(
          'lastPeriodStart',
        ),
        'date is before the earliest allowed date',
      );
      expect(world.step, OnboardingStep.cycle);
      expect(world.form.submitting, isFalse);

      // Control for "stayed on the step": staying put is also what a controller
      // that can never advance does. The same controller, given a save that
      // works, moves.
      world.answerSave();
      await world.notifier.submit();
      expect(world.step, OnboardingStep.baseline);
    },
  );

  test(
    'an untyped error is reported, never swallowed into a dead spinner',
    () async {
      final world = _World();
      await world.settle();
      world.rejectSave(StateError('the Hive box closed under a logout purge'));

      world.notifier.chooseDay(Date(2026, 4, 6));
      await world.notifier.submit();

      expect(world.form.failure, isA<UnknownFailure>());
      expect(world.form.submitting, isFalse);
      expect(world.step, OnboardingStep.cycle);
    },
  );

  test('a submit already in flight is not issued twice', () async {
    final world = _World();
    await world.settle();
    final release = Completer<OnboardingCycleResponse>();
    world.pendSave(release);

    world.notifier.chooseDay(Date(2026, 4, 6));
    final first = world.notifier.submit();
    await world.notifier.submit();

    world.verifySaves().called(1);
    expect(world.form.submitting, isTrue);

    release.complete(onboardingCycleFixture());
    await first;

    // Control: a stub nobody calls also records no second call. Once the first
    // save has settled the guard is open, so a further attempt DOES reach the
    // repository — here by changing an answer, since an unchanged one is
    // deliberately not re-posted.
    world.answerSave();
    world.notifier.chooseCycleLength(27);
    await world.notifier.submit();
    world.verifySaves().called(1);
  });

  test('submitting before the reads land issues nothing', () async {
    final world = _World();
    world.answerSave();

    // Not settled: the controller has no form yet, so there is nothing to
    // send and no anchor to send it with.
    await world.notifier.submit();
    verifyNever(
      () => world.onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    );

    // Control: the same call after the settle reaches the repository.
    await world.settle();
    world.notifier.chooseDay(Date(2026, 4, 6));
    await world.notifier.submit();
    world.verifySaves().called(1);
  });

  test('submitting with no day chosen issues nothing', () async {
    final world = _World();
    await world.settle();
    world.answerSave();

    expect(world.form.answers.lastPeriodStart, isNull);
    expect(world.step, OnboardingStep.cycle);

    await world.notifier.submit();

    verifyNever(
      () => world.onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    );
    // …and it does not walk on either. Sending nothing is only half the rule:
    // the anchor is the one MANDATORY answer (D-02), so a screen that let the
    // user past it without one would hand them a finish button that 409s.
    expect(world.step, OnboardingStep.cycle);

    // Control for both: with a day, the same call goes AND the step moves.
    world.notifier.chooseDay(Date(2026, 4, 6));
    await world.notifier.submit();
    world.verifySaves().called(1);
    expect(world.step, OnboardingStep.baseline);
  });

  test('a retry clears the previous failure BEFORE it lands', () async {
    final world = _World();
    await world.settle();
    world.rejectSave(const NetworkFailure());

    world.notifier.chooseDay(Date(2026, 4, 6));
    await world.notifier.submit();
    expect(world.form.failure, isA<NetworkFailure>());

    final release = Completer<OnboardingCycleResponse>();
    world.pendSave(release);
    // Nothing is touched between the two attempts — deliberately. Changing an
    // answer clears the failure on its own way in (`_write`), which would make
    // the assertion below true before `submit` ran a line.
    final second = world.notifier.submit();

    // Mid-flight, not after: without this the old banner sits beside the new
    // spinner, telling the user the attempt they are watching has already
    // failed.
    expect(world.form.submitting, isTrue);
    expect(world.form.failure, isNull);

    release.complete(onboardingCycleFixture());
    await second;
  });

  test(
    'changing an answer drops the note about the answer it replaced',
    () async {
      final world = _World();
      await world.settle();
      world.answerSave(
        onboardingCycleFixture(
          warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
        ),
      );

      world.notifier.chooseDay(Date(2026, 4, 6));
      await world.notifier.submit();
      // Premise: there IS a note, so its absence below is about the change.
      expect(world.form.warnings, isNotEmpty);

      world.notifier.chooseCycleLength(29);

      // The hint described a value that is no longer on screen. This is the only
      // place warnings are cleared — see the comment in `submit`.
      expect(world.form.warnings, isEmpty);
    },
  );
}
