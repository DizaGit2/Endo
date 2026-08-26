// DashboardController — screen 8's state (P4b-T17, READ SURFACE ONLY).
//
// TDD (RED first). The controller's job is combining THREE independent reads
// — `GET /me`, and `GET /cycle/calendar` for the current AND previous month
// (unconditionally, per the brief: "yesterday is in the previous month
// whenever today is the 1st — do not special-case that") — into one honest
// `AsyncValue<CacheResult<DashboardView>>`. The shape mirrors
// `ProfileController` (screen 31's own precedent), not
// `DayDetailController`/`CycleCalendarController`'s collapse-everything-to-
// AsyncError shape: a `NetworkRequired`/`Stale` result from any of the three
// reads is a real, renderable state (screen 31's "connect to load" / "showing
// cached data" surfaces), not a thrown failure — only a genuine [Failure]
// (validation/auth/unexpected) is allowed to propagate as `AsyncError`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockCycleRepository extends Mock implements CycleRepository {}

class _MockMeRepository extends Mock implements MeRepository {}

void main() {
  late _MockServerTodayRepository todayRepo;
  late _MockCycleRepository cycleRepo;
  late _MockMeRepository meRepo;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  setUp(() {
    todayRepo = _MockServerTodayRepository();
    cycleRepo = _MockCycleRepository();
    meRepo = _MockMeRepository();
  });

  /// [today] drives both which months get requested and what a fixture's
  /// `today` field would report — kept as one value so a test cannot
  /// accidentally assert against two different "today"s.
  ProviderContainer buildContainer({Date? today}) {
    when(todayRepo.today).thenAnswer((_) async => today ?? Date(2026, 4, 20));
    final c = ProviderContainer(
      retry: lumenRetry,
      overrides: <Override>[
        serverTodayRepositoryProvider.overrideWithValue(todayRepo),
        cycleRepositoryProvider.overrideWithValue(cycleRepo),
        meRepositoryProvider.overrideWithValue(meRepo),
      ],
    );
    addTearDown(c.dispose);
    // autoDispose — a bare read disposes as it returns, so a subscription is
    // required, matching how a screen's ref.watch behaves.
    c.listen(dashboardControllerProvider, (_, _) {});
    return c;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  void answerMonth(DateTime month, CycleCalendarResponse response) {
    when(
      () => cycleRepo.getCalendarMonth(month),
    ).thenAnswer((_) async => Fresh(response));
  }

  group('both months are actually requested', () {
    test(
      'current AND previous month are both requested, unconditionally',
      () async {
        when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
        answerMonth(DateTime(2026, 4), cycleCalendarFixture());
        answerMonth(DateTime(2026, 3), cycleCalendarFixture());

        container = buildContainer(today: Date(2026, 4, 20));
        await settle();

        verify(() => cycleRepo.getCalendarMonth(DateTime(2026, 4))).called(1);
        verify(() => cycleRepo.getCalendarMonth(DateTime(2026, 3))).called(1);
      },
    );

    test('when today is the 1st, the "previous" window is still requested — '
        'yesterday lives there and is not special-cased', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      answerMonth(DateTime(2026, 5), cycleCalendarFixture());
      answerMonth(
        DateTime(2026, 4),
        cycleCalendarFixture(
          days: [cycleCalendarDayFixture(date: Date(2026, 4, 30), pain: 5)],
        ),
      );

      container = buildContainer(today: Date(2026, 5, 1));
      await settle();

      verify(() => cycleRepo.getCalendarMonth(DateTime(2026, 5))).called(1);
      verify(() => cycleRepo.getCalendarMonth(DateTime(2026, 4))).called(1);

      final view =
          (container.read(dashboardControllerProvider).value!
                  as Fresh<DashboardView>)
              .value;
      expect(view.yesterdayPain, 5);
    });
  });

  group('combining into one view', () {
    test('displayName, today\'s pain and today\'s mood come from the '
        'current month\'s row', () async {
      when(
        meRepo.getMe,
      ).thenAnswer((_) async => Fresh(meResponseFixture(displayName: 'Maya')));
      answerMonth(
        DateTime(2026, 4),
        cycleCalendarFixture(
          days: [
            cycleCalendarDayFixture(date: Date(2026, 4, 20), pain: 3, mood: 2),
          ],
        ),
      );
      answerMonth(DateTime(2026, 3), cycleCalendarFixture());

      container = buildContainer();
      await settle();

      final view =
          (container.read(dashboardControllerProvider).value!
                  as Fresh<DashboardView>)
              .value;
      expect(view.displayName, 'Maya');
      expect(view.todayPain, 3);
      expect(view.todayMood, 2);
      expect(view.today, DateTime(2026, 4, 20));
    });

    test('a null displayName is carried through, not defaulted', () async {
      when(
        meRepo.getMe,
      ).thenAnswer((_) async => Fresh(meResponseFixture(displayName: null)));
      answerMonth(DateTime(2026, 4), cycleCalendarFixture());
      answerMonth(DateTime(2026, 3), cycleCalendarFixture());

      container = buildContainer();
      await settle();

      final view =
          (container.read(dashboardControllerProvider).value!
                  as Fresh<DashboardView>)
              .value;
      expect(view.displayName, isNull);
    });

    test('pain: 0 (a real logged value, D-08) is carried through as 0, never '
        'as null', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      answerMonth(
        DateTime(2026, 4),
        cycleCalendarFixture(
          days: [cycleCalendarDayFixture(date: Date(2026, 4, 20), pain: 0)],
        ),
      );
      answerMonth(DateTime(2026, 3), cycleCalendarFixture());

      container = buildContainer();
      await settle();

      final view =
          (container.read(dashboardControllerProvider).value!
                  as Fresh<DashboardView>)
              .value;
      expect(view.todayPain, 0);
    });

    test(
      'a day absent from either month\'s sparse list is null, not zero',
      () async {
        when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
        answerMonth(DateTime(2026, 4), cycleCalendarFixture());
        answerMonth(DateTime(2026, 3), cycleCalendarFixture());

        container = buildContainer();
        await settle();

        final view =
            (container.read(dashboardControllerProvider).value!
                    as Fresh<DashboardView>)
                .value;
        expect(view.todayPain, isNull);
        expect(view.todayMood, isNull);
        expect(view.yesterdayPain, isNull);
      },
    );

    test(
      'yesterday\'s pain, from the SAME month, is picked up correctly',
      () async {
        when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
        answerMonth(
          DateTime(2026, 4),
          cycleCalendarFixture(
            days: [
              cycleCalendarDayFixture(date: Date(2026, 4, 19), pain: 3),
              cycleCalendarDayFixture(date: Date(2026, 4, 20), pain: 0),
            ],
          ),
        );
        answerMonth(DateTime(2026, 3), cycleCalendarFixture());

        container = buildContainer();
        await settle();

        final view =
            (container.read(dashboardControllerProvider).value!
                    as Fresh<DashboardView>)
                .value;
        expect(view.todayPain, 0);
        expect(view.yesterdayPain, 3);
      },
    );

    test('yesterday is computed by CALENDAR arithmetic, not by subtracting a '
        '24h Duration — fix round 1, I2: the exact es-ES/Europe/Madrid '
        'DST-crossing date named in review (2026-03-30), pinning that the '
        'view reads March 29\'s row, never March 28\'s', () async {
      // The old buggy form (`todayDate.subtract(const Duration(days:
      // 1))`) is DST-unsafe on a LOCAL DateTime: on 2026-03-30 in
      // Europe/Madrid, local midnight is CEST (UTC+2); minus exactly 24h
      // lands at 2026-03-28 23:00 CET — i.e. `.toDate()` == 2026-03-28,
      // the day BEFORE yesterday, not yesterday. Note both candidate
      // dates (the 28th and the 29th) sit inside the SAME calendar month
      // as today (the 30th) — this bug is not a month-boundary case at
      // all, which is exactly why it was easy to miss: the "today is the
      // 1st" test above already covers month/year rollover, and this is
      // a genuinely different failure shape, entirely WITHIN one month.
      // This fixture puts a DIFFERENT, distinguishable pain value on
      // each of the two candidate dates, so the assertion below is
      // genuinely sensitive to which one the controller reads: 7 on the
      // 28th (what the bug would read) and 3 on the 29th (the real
      // answer).
      //
      // This test CANNOT fail against the old buggy form ON THIS MACHINE
      // — confirmed empirically, not assumed; see the fix-round report
      // for the reproduction attempt and why it is a genuine limit of
      // this sandbox's OS timezone (Mexico Central, no DST since 2022;
      // `TZ=Europe/Madrid` was also tried and has no effect on Dart's
      // local `DateTime` on this platform). What this test DOES pin: the
      // fixed form's correct output at the exact named boundary date,
      // protecting it from a future regression back to `.subtract`.
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      answerMonth(
        DateTime(2026, 3),
        cycleCalendarFixture(
          days: [
            // What the OLD bug would have read ("day before yesterday").
            cycleCalendarDayFixture(date: Date(2026, 3, 28), pain: 7),
            // The real yesterday.
            cycleCalendarDayFixture(date: Date(2026, 3, 29), pain: 3),
            cycleCalendarDayFixture(date: Date(2026, 3, 30), pain: 1),
          ],
        ),
      );
      answerMonth(DateTime(2026, 2), cycleCalendarFixture());

      container = buildContainer(today: Date(2026, 3, 30));
      await settle();

      final view =
          (container.read(dashboardControllerProvider).value!
                  as Fresh<DashboardView>)
              .value;
      expect(view.todayPain, 1);
      expect(
        view.yesterdayPain,
        3,
        reason:
            'must read March 29 (real yesterday), never March 28 (what '
            'subtract(Duration(days: 1)) would read under a DST offset '
            'change this machine cannot reproduce)',
      );
    });

    test('phaseUnavailableReason comes from the CURRENT month\'s own envelope '
        '— fix round 1, M5', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      answerMonth(
        DateTime(2026, 4),
        cycleCalendarFixture(
          phase: CyclePhaseAvailabilityResponse(
            (b) => b
              ..available = false
              ..unavailableReason = kPhaseEngineNotImplemented,
          ),
        ),
      );
      // The PREVIOUS month's envelope is deliberately DIFFERENT, so this
      // test is genuinely sensitive to which response the controller
      // trusts — reading the wrong one would silently pass this
      // assertion if both fixtures answered the same reason.
      answerMonth(
        DateTime(2026, 3),
        cycleCalendarFixture(
          phase: CyclePhaseAvailabilityResponse(
            (b) => b
              ..available = false
              ..unavailableReason = 'some_other_reason_previous_month',
          ),
        ),
      );

      container = buildContainer();
      await settle();

      final view =
          (container.read(dashboardControllerProvider).value!
                  as Fresh<DashboardView>)
              .value;
      expect(view.phaseUnavailableReason, kPhaseEngineNotImplemented);
    });

    test('phaseUnavailableReason is null when the current month\'s envelope '
        'carries no reason (or no phase envelope at all)', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      answerMonth(DateTime(2026, 4), cycleCalendarFixture());
      answerMonth(DateTime(2026, 3), cycleCalendarFixture());

      container = buildContainer();
      await settle();

      final view =
          (container.read(dashboardControllerProvider).value!
                  as Fresh<DashboardView>)
              .value;
      expect(view.phaseUnavailableReason, isNull);
    });

    test(
      'phaseAvailable comes from that SAME envelope — T23 fix round 1, I-1',
      () async {
        when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
        // `available: true` is a value no P4a account can answer (§C.0.3), and
        // that is the point: the screen's gate can only be exercised if this
        // field carries the wire value rather than a constant, and nothing the
        // real backend sends today would tell the two apart.
        answerMonth(
          DateTime(2026, 4),
          cycleCalendarFixture(
            phase: CyclePhaseAvailabilityResponse(
              (b) => b
                ..available = true
                ..unavailableReason = null,
            ),
          ),
        );
        // Again the PREVIOUS month disagrees, so reading the wrong response
        // fails rather than coincidentally passing.
        answerMonth(
          DateTime(2026, 3),
          cycleCalendarFixture(
            phase: CyclePhaseAvailabilityResponse(
              (b) => b
                ..available = false
                ..unavailableReason = kPhaseEngineNotImplemented,
            ),
          ),
        );

        container = buildContainer();
        await settle();

        final view =
            (container.read(dashboardControllerProvider).value!
                    as Fresh<DashboardView>)
                .value;
        expect(view.phaseAvailable, isTrue);
        expect(view.phaseUnavailableReason, isNull);
      },
    );

    test('phaseAvailable is null when there is no phase envelope at all — an '
        'absent envelope answers neither half, and the view says so', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      answerMonth(DateTime(2026, 4), cycleCalendarFixture());
      answerMonth(DateTime(2026, 3), cycleCalendarFixture());

      container = buildContainer();
      await settle();

      final view =
          (container.read(dashboardControllerProvider).value!
                  as Fresh<DashboardView>)
              .value;
      expect(view.phaseAvailable, isNull);
    });
  });

  group(
    'a NetworkRequired read collapses the WHOLE screen, no partial data',
    () {
      test('NetworkRequired from the ME read', () async {
        when(meRepo.getMe).thenAnswer(
          (_) async => const NetworkRequired<MeResponse>(NetworkFailure()),
        );
        answerMonth(DateTime(2026, 4), cycleCalendarFixture());
        answerMonth(DateTime(2026, 3), cycleCalendarFixture());

        container = buildContainer();
        await settle();

        expect(
          container.read(dashboardControllerProvider).value,
          isA<NetworkRequired<DashboardView>>(),
        );
      });

      test('NetworkRequired from the CURRENT month read', () async {
        when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
        when(() => cycleRepo.getCalendarMonth(DateTime(2026, 4))).thenAnswer(
          (_) async =>
              const NetworkRequired<CycleCalendarResponse>(NetworkFailure()),
        );
        answerMonth(DateTime(2026, 3), cycleCalendarFixture());

        container = buildContainer();
        await settle();

        expect(
          container.read(dashboardControllerProvider).value,
          isA<NetworkRequired<DashboardView>>(),
        );
      });

      test('NetworkRequired from the PREVIOUS month read', () async {
        when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
        answerMonth(DateTime(2026, 4), cycleCalendarFixture());
        when(() => cycleRepo.getCalendarMonth(DateTime(2026, 3))).thenAnswer(
          (_) async =>
              const NetworkRequired<CycleCalendarResponse>(NetworkFailure()),
        );

        container = buildContainer();
        await settle();

        expect(
          container.read(dashboardControllerProvider).value,
          isA<NetworkRequired<DashboardView>>(),
        );
      });
    },
  );

  group('staleness — any Stale read makes the whole view Stale', () {
    test('a Stale ME read makes the combined view Stale, even though both '
        'calendar reads are Fresh', () async {
      when(meRepo.getMe).thenAnswer((_) async => Stale(meResponseFixture()));
      answerMonth(DateTime(2026, 4), cycleCalendarFixture());
      answerMonth(DateTime(2026, 3), cycleCalendarFixture());

      container = buildContainer();
      await settle();

      expect(
        container.read(dashboardControllerProvider).value,
        isA<Stale<DashboardView>>(),
      );
    });

    test('all three Fresh stays Fresh', () async {
      when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
      answerMonth(DateTime(2026, 4), cycleCalendarFixture());
      answerMonth(DateTime(2026, 3), cycleCalendarFixture());

      container = buildContainer();
      await settle();

      expect(
        container.read(dashboardControllerProvider).value,
        isA<Fresh<DashboardView>>(),
      );
    });
  });

  group('a genuine Failure surfaces AsyncError, not a partial dashboard', () {
    test(
      'a non-network/server Failure from the calendar read propagates',
      () async {
        when(meRepo.getMe).thenAnswer((_) async => Fresh(meResponseFixture()));
        when(
          () => cycleRepo.getCalendarMonth(DateTime(2026, 4)),
        ).thenAnswer((_) async => throw const AuthFailure());
        answerMonth(DateTime(2026, 3), cycleCalendarFixture());

        container = buildContainer();
        await settle();

        expect(
          container.read(dashboardControllerProvider),
          isA<AsyncError<CacheResult<DashboardView>>>(),
        );
      },
    );
  });
}
