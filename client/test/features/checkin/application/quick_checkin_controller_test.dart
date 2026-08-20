// QuickCheckinController — screen 9's form state (P4b-T18).
//
// TDD (RED first). See `quick_checkin_controller.dart`'s own header for the
// eight anti-fabrication rules this controller exists to enforce; each group
// below is named after the rule it pins. `CheckinRepository` is mocked
// directly here — the wire-payload proof (rule 1, "assert on the payload")
// lives in `checkin_repository_test.dart`, which is the layer that actually
// serializes anything. This file's job is the STATE MACHINE: what gets
// marked touched, when the CTA may fire, what happens to the form on
// success/failure, and which dependent screens get told to refresh.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/quick_checkin_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/checkin/application/quick_checkin_controller.dart';
import 'package:lumen/features/checkin/data/checkin_repository.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/harness.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockCheckinRepository extends Mock implements CheckinRepository {}

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockCycleRepository extends Mock implements CycleRepository {}

class _MockMeRepository extends Mock implements MeRepository {}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _MockCheckinRepository checkinRepo;
  late _MockServerTodayRepository todayRepo;
  late _MockCycleRepository cycleRepo;
  late _MockMeRepository meRepo;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  setUp(() {
    checkinRepo = _MockCheckinRepository();
    todayRepo = _MockServerTodayRepository();
    cycleRepo = _MockCycleRepository();
    meRepo = _MockMeRepository();
    when(todayRepo.today).thenAnswer((_) async => Date(2026, 4, 20));
  });

  ProviderContainer buildContainer() {
    final c = ProviderContainer(
      overrides: <Override>[
        checkinRepositoryProvider.overrideWithValue(checkinRepo),
        serverTodayRepositoryProvider.overrideWithValue(todayRepo),
        cycleRepositoryProvider.overrideWithValue(cycleRepo),
        meRepositoryProvider.overrideWithValue(meRepo),
      ],
    );
    addTearDown(c.dispose);
    // autoDispose — a bare read disposes as it returns once any `await`
    // lets the scheduled teardown run, matching how a screen's `ref.watch`
    // keeps it alive (`dashboard_controller_test.dart`'s own precedent).
    c.listen(quickCheckinControllerProvider, (_, _) {});
    return c;
  }

  QuickCheckinController notifier(ProviderContainer c) =>
      c.read(quickCheckinControllerProvider.notifier);

  QuickCheckinForm state(ProviderContainer c) =>
      c.read(quickCheckinControllerProvider);

  // -------------------------------------------------------------------------
  // Rule 4 — no prefill
  // -------------------------------------------------------------------------

  test('build() reads nothing — the form opens with both fields untouched '
      'and null, never seeded from any cache or read', () {
    container = buildContainer();
    final form = state(container);

    expect(form.pain, isNull);
    expect(form.mood, isNull);
    expect(form.touchedPain, isFalse);
    expect(form.touchedMood, isFalse);
    expect(form.canSubmit, isFalse);
    verifyZeroInteractions(checkinRepo);
    verifyNever(todayRepo.today);
  });

  // -------------------------------------------------------------------------
  // Rules 1, 3, 6 — explicit touched-ness, CTA gating, clearing
  // -------------------------------------------------------------------------

  group('touched-ness and the CTA gate', () {
    test('setPain marks pain touched and enables the CTA', () {
      container = buildContainer();
      notifier(container).setPain(3);

      final form = state(container);
      expect(form.pain, 3);
      expect(form.touchedPain, isTrue);
      expect(form.canSubmit, isTrue);
    });

    test('setPain(0) — a real datum, D-08 — still marks pain touched', () {
      container = buildContainer();
      notifier(container).setPain(0);

      final form = state(container);
      expect(form.pain, 0);
      expect(
        form.touchedPain,
        isTrue,
        reason:
            'touched-ness must be tracked explicitly, never derived from '
            'whether the value is falsy',
      );
      expect(form.canSubmit, isTrue);
    });

    test('setMood marks mood touched and enables the CTA', () {
      container = buildContainer();
      notifier(container).setMood(2);

      final form = state(container);
      expect(form.mood, 2);
      expect(form.touchedMood, isTrue);
      expect(form.canSubmit, isTrue);
    });

    test('the CTA is disabled until something is touched, and '
        'touching-then-clearing disables it again', () {
      container = buildContainer();
      expect(state(container).canSubmit, isFalse);

      notifier(container).setPain(5);
      expect(state(container).canSubmit, isTrue);

      // LumenIntensityScale's clear gesture reports `null` for a field the
      // user DID interact with — the controller must treat that as
      // "untouched again", not as "touched, value null".
      notifier(container).setPain(null);
      final cleared = state(container);
      expect(cleared.pain, isNull);
      expect(cleared.touchedPain, isFalse);
      expect(
        cleared.canSubmit,
        isFalse,
        reason:
            'nothing else was touched — clearing the only touched '
            'field must disable the CTA again',
      );
    });

    test('clearing ONE field leaves the CTA enabled if the OTHER is still '
        'touched', () {
      container = buildContainer();
      notifier(container).setPain(5);
      notifier(container).setMood(2);

      notifier(container).setPain(null);

      final form = state(container);
      expect(form.touchedPain, isFalse);
      expect(form.touchedMood, isTrue);
      expect(form.canSubmit, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Rule 5 — CTA-only save
  // -------------------------------------------------------------------------

  test('setPain/setMood never call the repository themselves — no '
      'save-on-change', () {
    container = buildContainer();
    notifier(container).setPain(4);
    notifier(container).setMood(3);

    verifyZeroInteractions(checkinRepo);
  });

  // -------------------------------------------------------------------------
  // submit() — guards
  // -------------------------------------------------------------------------

  group('submit() guards', () {
    test('a no-op when nothing is touched', () async {
      container = buildContainer();
      final ok = await notifier(container).submit();

      expect(ok, isFalse);
      verifyZeroInteractions(checkinRepo);
    });

    test('a no-op while already submitting', () async {
      container = buildContainer();
      final release = Completer<QuickCheckinResponse>();
      when(
        () => checkinRepo.quickCheckin(
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer((_) => release.future);

      notifier(container).setPain(4);
      final first = notifier(container).submit();
      await settle();
      expect(state(container).submitting, isTrue);

      final second = await notifier(container).submit();
      expect(second, isFalse);

      release.complete(QuickCheckinResponse((b) => b..pain = 4));
      await first;
      verify(
        () => checkinRepo.quickCheckin(
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).called(1);
    });
  });

  // -------------------------------------------------------------------------
  // submit() — sends exactly the touched state
  // -------------------------------------------------------------------------

  test('submit() sends pain/mood/touchedPain/touchedMood exactly as the '
      'form holds them, plus the SESSION day as fallbackDay', () async {
    container = buildContainer();
    when(
      () => checkinRepo.quickCheckin(
        pain: any(named: 'pain'),
        mood: any(named: 'mood'),
        touchedPain: any(named: 'touchedPain'),
        touchedMood: any(named: 'touchedMood'),
        fallbackDay: any(named: 'fallbackDay'),
      ),
    ).thenAnswer((_) async => QuickCheckinResponse((b) => b..pain = 4));

    notifier(container).setPain(4);
    await notifier(container).submit();

    verify(
      () => checkinRepo.quickCheckin(
        pain: 4,
        mood: null,
        touchedPain: true,
        touchedMood: false,
        fallbackDay: DateTime(2026, 4, 20),
      ),
    ).called(1);
  });

  // -------------------------------------------------------------------------
  // Rule 7 — never adopt the response
  // -------------------------------------------------------------------------

  test('a pain-only submit whose response echoes a `mood` the user never '
      'touched does NOT adopt it into form state', () async {
    container = buildContainer();
    when(
      () => checkinRepo.quickCheckin(
        pain: any(named: 'pain'),
        mood: any(named: 'mood'),
        touchedPain: any(named: 'touchedPain'),
        touchedMood: any(named: 'touchedMood'),
        fallbackDay: any(named: 'fallbackDay'),
      ),
      // The stored-row echo: mood == 2 even though this request never sent
      // one — CycleDayService.cs:187's real behaviour, per the brief.
    ).thenAnswer(
      (_) async => QuickCheckinResponse(
        (b) => b
          ..pain = 4
          ..mood = 2,
      ),
    );

    notifier(container).setPain(4);
    final ok = await notifier(container).submit();

    expect(ok, isTrue);
    final form = state(container);
    expect(
      form.mood,
      isNull,
      reason:
          'adopting the echoed mood would make a value the user never '
          'entered indistinguishable from real input on the NEXT save',
    );
    expect(form.touchedMood, isFalse);
  });

  // -------------------------------------------------------------------------
  // Failure handling
  // -------------------------------------------------------------------------

  group('a rejected submit', () {
    test('surfaces the typed Failure and preserves the touched form for a '
        'retry', () async {
      container = buildContainer();
      when(
        () => checkinRepo.quickCheckin(
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer(
        (_) async => throw const ValidationFailure(
          fields: {
            'request': ['at least one of pain or mood is required'],
          },
        ),
      );

      notifier(container).setPain(4);
      final ok = await notifier(container).submit();

      expect(ok, isFalse);
      final form = state(container);
      expect(form.submitting, isFalse);
      expect(form.failure, isA<ValidationFailure>());
      expect(
        form.pain,
        4,
        reason:
            'the touched answer must survive a failed attempt so a '
            'retry re-sends the SAME payload, not an emptied form',
      );
      expect(form.touchedPain, isTrue);
    });

    test('a non-Failure exception becomes UnknownFailure, never an '
        'unhandled rejection (the goals_controller.dart precedent — a '
        'concurrent cache-purge during invalidation)', () async {
      container = buildContainer();
      when(
        () => checkinRepo.quickCheckin(
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer((_) async => throw StateError('box closed'));

      notifier(container).setPain(4);
      final ok = await notifier(container).submit();

      expect(ok, isFalse);
      expect(state(container).failure, isA<UnknownFailure>());
    });

    test(
      'does not touch the dashboard or calendar controllers on failure',
      () async {
        container = buildContainer();
        when(
          () => checkinRepo.quickCheckin(
            pain: any(named: 'pain'),
            mood: any(named: 'mood'),
            touchedPain: any(named: 'touchedPain'),
            touchedMood: any(named: 'touchedMood'),
            fallbackDay: any(named: 'fallbackDay'),
          ),
        ).thenAnswer((_) async => throw const NetworkFailure());

        notifier(container).setPain(4);
        await notifier(container).submit();

        verifyZeroInteractions(meRepo);
        verifyZeroInteractions(cycleRepo);
      },
    );

    test('the retry re-issues exactly one request with the same touched '
        'payload', () async {
      container = buildContainer();
      var calls = 0;
      when(
        () => checkinRepo.quickCheckin(
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw const NetworkFailure();
        return QuickCheckinResponse((b) => b..pain = 4);
      });

      notifier(container).setPain(4);
      final first = await notifier(container).submit();
      expect(first, isFalse);

      final second = await notifier(container).submit();
      expect(second, isTrue);
      expect(calls, 2);
    });
  });

  // -------------------------------------------------------------------------
  // Refreshing dependents on success
  // -------------------------------------------------------------------------

  group('refreshing dependent screens on success', () {
    test('the dashboard is ALWAYS invalidated and re-fetches', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      when(
        () => cycleRepo.getCalendarMonth(any()),
      ).thenAnswer((_) async => Fresh(cycleCalendarFixture()));
      container = buildContainer();

      container.listen(dashboardControllerProvider, (_, _) {});
      await settle();
      // Consumes the initial build's own call — mocktail's verify()
      // consumes matched interactions, the same idiom
      // cycle_repository_test.dart's own "invalidates nothing" test relies
      // on.
      verify(meRepo.getMe).called(1);

      when(
        () => checkinRepo.quickCheckin(
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer((_) async => QuickCheckinResponse((b) => b..pain = 4));

      notifier(container).setPain(4);
      await notifier(container).submit();
      await settle();

      verify(
        meRepo.getMe,
      ).called(1); // the dashboard rebuilt after invalidation
    });

    test(
      'the calendar controller is NOT created when nobody has read it — a '
      'bare read would fire sessionToday plus three calendar GETs for a '
      'screen nobody opened (checked via Ref.exists, never ref.read)',
      () async {
        when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
        container = buildContainer();
        when(
          () => checkinRepo.quickCheckin(
            pain: any(named: 'pain'),
            mood: any(named: 'mood'),
            touchedPain: any(named: 'touchedPain'),
            touchedMood: any(named: 'touchedMood'),
            fallbackDay: any(named: 'fallbackDay'),
          ),
        ).thenAnswer((_) async => QuickCheckinResponse((b) => b..pain = 4));

        notifier(container).setPain(4);
        await notifier(container).submit();
        await settle();

        verifyZeroInteractions(cycleRepo);
      },
    );

    test('the calendar controller is refreshed when it already exists AND '
        'already has a value', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      when(
        () => cycleRepo.getCalendarMonth(any()),
      ).thenAnswer((_) async => Fresh(cycleCalendarFixture()));
      container = buildContainer();

      // Simulate "the Cycle tab was already opened this session".
      container.listen(cycleCalendarControllerProvider, (_, _) {});
      await settle();
      expect(
        container.read(cycleCalendarControllerProvider).hasValue,
        isTrue,
        reason: 'premise: the calendar controller has already settled',
      );
      verify(() => cycleRepo.getCalendarMonth(any())).called(3);

      when(
        () => checkinRepo.quickCheckin(
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer((_) async => QuickCheckinResponse((b) => b..pain = 4));

      notifier(container).setPain(4);
      await notifier(container).submit();
      await settle();

      verify(() => cycleRepo.getCalendarMonth(any())).called(3);
    });

    test('the calendar controller is SKIPPED — not refreshed — while it exists '
        'but has not settled to a value yet, avoiding the documented '
        'snap-back', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      final pending = Completer<CacheResult<CycleCalendarResponse>>();
      when(
        () => cycleRepo.getCalendarMonth(any()),
      ).thenAnswer((_) => pending.future);
      container = buildContainer();

      container.listen(cycleCalendarControllerProvider, (_, _) {});
      await settle();
      expect(
        container.read(cycleCalendarControllerProvider).hasValue,
        isFalse,
        reason:
            'premise: still loading — three requests in flight, none '
            'resolved',
      );
      verify(() => cycleRepo.getCalendarMonth(any())).called(3);

      when(
        () => checkinRepo.quickCheckin(
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer((_) async => QuickCheckinResponse((b) => b..pain = 4));

      notifier(container).setPain(4);
      await notifier(container).submit();
      await settle();

      verifyNever(() => cycleRepo.getCalendarMonth(any()));
    });
  });
}
