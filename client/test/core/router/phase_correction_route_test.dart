// The production route for screen 14 (P4b-T23): `/cycle/phase`, reachable
// today by DEEP LINK ONLY.
//
// TDD (RED first). R3 ships this route with no entry affordance, deliberately:
// R-08 requires the route, the screen, the goldens and the semantics to land,
// but a control whose destination can only say "phases aren't available yet"
// is inert navigation, which R-10 hides rather than disables, and R-20 forbids
// shipping half an affordance — so the entry point lands in P6 together with
// the `POST /cycle/phase-override` write. `phase_correction_source_test.dart`
// holds the tripwire that keeps it that way.
//
// **That leaves the deep link as the ONLY way in, so R4's question — where
// does a cold link land, and where does Back go from there — is not a corner
// case here; it is the entire entry path.** T21b measured the answer for a
// CHILD route one screen over (probe C, quoted in `_leaveDayDetail`'s
// dartdoc): go_router materialises the parent's page beneath a child route
// even on a cold link, so `context.canPop()` answers true and Back reaches the
// calendar. This file pins that for `/cycle/phase` rather than inheriting the
// measurement, because the whole reachability story rests on it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/presentation/cycle_calendar_screen.dart';
import 'package:lumen/features/cycle/presentation/phase_correction_screen.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../../support/harness.dart';

class _SettledCalendar extends CycleCalendarController {
  @override
  Future<CycleCalendarView> build() async => CycleCalendarView(
    visibleMonth: DateTime(2026, 4),
    today: Date(2026, 4, 22),
    phase: CyclePhaseAvailabilityResponse(
      (b) => b
        ..available = false
        ..unavailableReason = 'phase_engine_not_implemented',
    ),
    dayByDate: const <Date, CycleCalendarDay>{},
  );
}

/// Pumps the REAL production route table at [initialLocation], wired to the
/// REAL production redirect.
Future<void> _pumpProductionRouter(
  WidgetTester tester, {
  required String initialLocation,
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
      ...lumenOverrides(cacheStore: emptyCacheStore()),
      cycleCalendarControllerProvider.overrideWith(_SettledCalendar.new),
    ],
  );
}

String _location(WidgetTester tester, Type screen) =>
    GoRouterState.of(tester.element(find.byType(screen))).uri.path;

void main() {
  group('the path constant', () {
    test(
      'screen 14 lives INSIDE the Cycle branch — its path is built from '
      'Routes.cycle, so the branch root and the child cannot drift apart',
      () {
        expect(Routes.cyclePhase, startsWith('${Routes.cycle}/'));
        expect(
          Routes.cyclePhase,
          '${Routes.cycle}/${Routes.cyclePhaseSegment}',
        );
      },
    );
  });

  group('R-02 — the child route, verified against production', () {
    testWidgets(
      'a direct deep link to /cycle/phase is recognised as a KNOWN location '
      'and renders screen 14 — no redirect to Home, and no second edit '
      'anywhere but the route table',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.cyclePhase);

        expect(find.byType(PhaseCorrectionScreen), findsOneWidget);
        expect(find.byType(DashboardScreen), findsNothing);
        expect(_location(tester, PhaseCorrectionScreen), Routes.cyclePhase);
      },
    );

    testWidgets(
      'the Cycle tab stays selected and the bottom nav survives — screen 14 '
      'is a CHILD of the Cycle branch, not a top-level route and not the '
      'unmatched-location fallback',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.cyclePhase);

        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.selectedIndex, 1);
        expect(find.byType(LumenBottomNav), findsOneWidget);
      },
    );
  });

  group('R4 — where a COLD deep link goes back to', () {
    testWidgets(
      'Back pops to the cycle calendar, not out of the app — go_router '
      'materialises the branch root beneath a child route even on a cold '
      'link, so there IS something to pop',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.cyclePhase);
        expect(find.byType(PhaseCorrectionScreen), findsOneWidget);

        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();

        expect(find.byType(PhaseCorrectionScreen), findsNothing);
        expect(find.byType(CycleCalendarScreen), findsOneWidget);
        expect(_location(tester, CycleCalendarScreen), Routes.cycle);
      },
    );

    testWidgets(
      'the pop is a real pop, not a `go` — the Cycle branch is one entry '
      'deep at the calendar afterwards, so the tab has not been rebuilt out '
      'from under the user',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.cyclePhase);

        final context = tester.element(find.byType(PhaseCorrectionScreen));
        expect(
          GoRouter.of(context).canPop(),
          isTrue,
          reason:
              'If this ever answers false, `_leavePhaseCorrection`\'s '
              'canPop guard becomes the live branch and the assertion above '
              'stops proving a pop. Both halves are deliberate: the guard '
              'ships because a route table change must not be able to turn a '
              'cold link into a crash.',
        );
      },
    );
  });

  group('R3 — the route ships with no entry affordance', () {
    testWidgets(
      'the cycle calendar offers nothing that reaches screen 14 — its only '
      'destinations are the two month chevrons and the 30 current-month day '
      'cells',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.cycle);
        expect(find.byType(CycleCalendarScreen), findsOneWidget);

        // Every mockup word that would advertise the correction surface.
        expect(find.textContaining('Correct phase'), findsNothing);
        expect(find.textContaining('Adjust'), findsNothing);
        expect(find.byType(PhaseCorrectionScreen), findsNothing);
      },
    );
  });
}
