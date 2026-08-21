// The production route for screen 11 (P4b-T16): `/cycle/day/:date`, reached
// two ways — a tap on a screen-10 day cell, and a direct deep link.
//
// TDD (RED first). Two things this file exists to prove that no other file
// proves against the REAL production route table:
//
//  * R-02 verification (the brief's own ask: "R-02 / `_knownPaths` has never
//    been verified against a parameterised route. You are the first."):
//    `lumenRouteRedirect` derives `isKnownLocation` from GoRouter's own
//    matcher (`state.error == null`), not from a hand-maintained literal
//    set — `test/core/router/route_table_test.dart` proves that mechanism
//    against a PROBE table. This file proves the PRODUCTION table's real
//    `/cycle/day/:date` child route is recognised the same way, with no
//    second edit anywhere.
//  * the day-cell tap and the route landing together, in the SAME real app
//    (R-10: "route and tap in one commit") — including that back pops to
//    the calendar, and that a malformed `:date` renders screen 11's own
//    error surface rather than vanishing into a silent redirect.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/cycle/presentation/cycle_calendar_screen.dart';
import 'package:lumen/features/cycle/presentation/day_detail_screen.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _MockCycleRepository extends Mock implements CycleRepository {}

class _MockSymptomsRepository extends Mock implements SymptomsRepository {}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _SettledOnboarding extends OnboardingFlowController {
  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(step: OnboardingStep.cycle, state: onboardingStateFixture()),
  );
}

/// April 2026, today the 20th, with a mark on the 16th — the same cell every
/// test in this file taps.
final _calendarView = CycleCalendarView(
  visibleMonth: DateTime(2026, 4),
  today: Date(2026, 4, 20),
  phase: null,
  dayByDate: <Date, CycleCalendarDay>{
    Date(2026, 4, 16): cycleCalendarDayFixture(
      date: Date(2026, 4, 16),
      eventCount: 1,
    ),
  },
);

class _SettledCalendar extends CycleCalendarController {
  @override
  Future<CycleCalendarView> build() async => _calendarView;
}

class _SettledDayDetail extends DayDetailController {
  _SettledDayDetail(this.view) : super(view.date);

  final DayDetailView view;

  @override
  Future<DayDetailView> build() async => view;
}

/// Pumps the REAL production route table at [initialLocation], wired to the
/// REAL production redirect, with screen 10 and screen 11 (for April 16,
/// 2026) pinned settled so `pumpAndSettle` returns.
Future<void> _pumpProductionRouter(
  WidgetTester tester, {
  required String initialLocation,
  List<Override> extraOverrides = const [],
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: lumenRoutes(),
    redirect: (_, state) => lumenRouteRedirect(
      state,
      status: AuthStatus.authenticated,
      onboarding: OnboardingStatus.completed,
    ),
  );
  addTearDown(router.dispose);

  await pumpRouterApp(
    tester,
    routerConfig: router,
    overrides: [
      ...lumenOverrides(),
      onboardingFlowControllerProvider.overrideWith(_SettledOnboarding.new),
      cycleCalendarControllerProvider.overrideWith(_SettledCalendar.new),
      dayDetailControllerProvider(DateTime(2026, 4, 16)).overrideWith(
        () => _SettledDayDetail(
          DayDetailView(
            events: const [],
            date: DateTime(2026, 4, 16),
            log: cycleDayLogFixture(pain: 4, mood: 2),
            symptoms: const [],
            symptomsTotal: 0,
          ),
        ),
      ),
      ...extraOverrides,
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  group('R-02 — the parameterised route, verified against production', () {
    testWidgets(
      'a direct deep link to /cycle/day/2026-04-16 is recognised as a '
      'KNOWN location — no redirect to /profile, no second edit anywhere',
      (tester) async {
        await _pumpProductionRouter(
          tester,
          initialLocation: '/cycle/day/2026-04-16',
        );

        expect(find.byType(DayDetailScreen), findsOneWidget);
        expect(find.byType(CycleCalendarScreen), findsNothing);
      },
    );

    testWidgets(
      'the Cycle tab stays selected while showing the day route — this IS '
      'a bottom-nav branch, not a location that fell through to the '
      'unmatched-location fallback',
      (tester) async {
        await _pumpProductionRouter(
          tester,
          initialLocation: '/cycle/day/2026-04-16',
        );

        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.selectedIndex, 1);
      },
    );
  });

  group('the day-cell tap and the route, together', () {
    testWidgets(
      'tapping a current-month day cell navigates to screen 11 for THAT '
      'date',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.cycle);
        expect(find.byType(CycleCalendarScreen), findsOneWidget);

        await tester.tap(find.byKey(ValueKey<DateTime>(DateTime(2026, 4, 16))));
        await tester.pumpAndSettle();

        expect(find.byType(DayDetailScreen), findsOneWidget);
        expect(find.text('April 16'), findsOneWidget);
      },
    );

    testWidgets(
      'the back chevron pops to the calendar, which is still on the SAME '
      'visible month — a pushed route inside the branch, not a fresh '
      'rebuild',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.cycle);
        await tester.tap(find.byKey(ValueKey<DateTime>(DateTime(2026, 4, 16))));
        await tester.pumpAndSettle();
        expect(find.byType(DayDetailScreen), findsOneWidget);

        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();

        expect(find.byType(CycleCalendarScreen), findsOneWidget);
        expect(find.byType(DayDetailScreen), findsNothing);
      },
    );
  });

  group('a malformed :date', () {
    testWidgets(
      '/cycle/day/2026-02-31 renders screen 11\'s own error surface — NOT '
      'a silent redirect to the calendar, and NOT the rolled date '
      '(March 3rd)',
      (tester) async {
        // fix round 1, M-3: the brief's actual requirement is "assert no
        // read is issued for the rolled date" — stated directly here with
        // a mocked repository, rather than only inferred from
        // `find.byType(DayDetailScreen), findsNothing`.
        //
        // fix round 2, M-3: `symptomsRepositoryProvider` must ALSO be
        // overridden, or this assertion is vacuous. `DayDetailController.
        // build()` reads `symptomsRepositoryProvider` before it ever calls
        // `cycleRepo.getDay` — left un-overridden, that provider throws
        // while building (it reaches the real, un-overridden
        // `cacheStoreProvider`, which throws by design when un-overridden)
        // BEFORE `cycleRepo.getDay` can be reached at all, on every path —
        // guard intact or broken alike. `verifyNever` would then pass for
        // the wrong reason (nothing ever calls the mock, full stop) rather
        // than for the reason this test claims (the guard rejected the
        // rolled date). With both repositories mocked and answering
        // successfully, the guard is the only thing standing between a
        // broken round-trip check and a real `getDay(2026-03-03)` call —
        // which is what makes this assertion capable of failing at all.
        final cycleRepo = _MockCycleRepository();
        when(
          () => cycleRepo.getDay(any()),
        ).thenAnswer((_) async => Fresh(cycleDayFixture()));
        final symptomsRepo = _MockSymptomsRepository();
        when(
          () => symptomsRepo.getDay(any()),
        ).thenAnswer((_) async => Fresh(symptomListResponseFixture()));

        await _pumpProductionRouter(
          tester,
          initialLocation: '/cycle/day/2026-02-31',
          extraOverrides: [
            cycleRepositoryProvider.overrideWithValue(cycleRepo),
            symptomsRepositoryProvider.overrideWithValue(symptomsRepo),
          ],
        );

        expect(find.byType(LumenErrorRetry), findsOneWidget);
        expect(find.byType(DayDetailScreen), findsNothing);
        expect(find.text("That date isn't valid."), findsOneWidget);
        verifyNever(() => cycleRepo.getDay(DateTime(2026, 3, 3)));
      },
    );

    testWidgets('the malformed-date screen\'s retry affordance returns to the '
        'calendar', (tester) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: '/cycle/day/2026-02-31',
      );

      await tester.tap(find.text(LumenErrorRetry.retryLabel));
      await tester.pumpAndSettle();

      expect(find.byType(CycleCalendarScreen), findsOneWidget);
    });
  });
}
