// R-19 — the navigation fix, P4b-T17.
//
// R-19 is two halves that only work together:
//   1. the authenticated default flips from "/profile" to the Home branch
//      (`lumenRedirect`, `app_router.dart`);
//   2. screen 31 (profile) mounts as the More branch's ROOT, and the old
//      top-level "/profile" route is gone.
//
// `app_router_test.dart` already covers half 1 at the PURE-FUNCTION level
// (`lumenRedirect` itself) and `route_table_test.dart`/`shell_test.dart`
// cover the production route table's general shape. This file is the one
// place that proves BOTH halves TOGETHER, against the real production
// router, with assertions chosen so that shipping only one half would still
// fail at least one of them — see the comment above each group for exactly
// which half it discriminates and why a partial implementation reddens it.
//
//   - "the default lands on Home" discriminates half 1: reverting ONLY the
//     redirect flip (keeping half 2's route-table changes — profile mounted
//     under More, no top-level /profile) would send the fallback destination
//     to a location that no longer EXISTS in the table, which does not
//     render DashboardScreen.
//   - "profile is reachable from the More tab, sign-out included"
//     discriminates half 2's MOUNT: reverting ONLY the mount (More tab still
//     the placeholder) fails this regardless of where the redirect points.
//   - "/profile has exactly one URL" discriminates half 2's REMOVAL
//     specifically — the subtlest partial shape, where profile is mounted
//     under More AND the OLD top-level "/profile" route is left in place
//     too. Both of the two assertions above would still PASS in that shape;
//     only this one catches "one screen, two live URLs with divergent back
//     behaviour" — precisely the failure mode the brief names.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Settled fakes — this file's subject is NAVIGATION, not any one screen's
// own reads, so every screen along the way is pinned to a settled state.
// ---------------------------------------------------------------------------

class _SettledOnboarding extends OnboardingFlowController {
  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(step: OnboardingStep.cycle, state: onboardingStateFixture()),
  );
}

class _SettledCycleSetup extends CycleSetupController {
  @override
  AsyncValue<CycleSetupForm> build() => AsyncValue<CycleSetupForm>.data(
    CycleSetupForm(
      answers: const CycleAnswers(),
      saved: const CycleAnswers(),
      visibleMonth: DateTime(2026, 4),
    ),
  );
}

class _SettledCalendar extends CycleCalendarController {
  @override
  Future<CycleCalendarView> build() async => CycleCalendarView(
    visibleMonth: DateTime(2026, 4),
    today: Date(2026, 4, 20),
    phase: null,
    dayByDate: const <Date, CycleCalendarDay>{},
  );
}

class _SettledDashboard extends DashboardController {
  @override
  Future<CacheResult<DashboardView>> build() async => Fresh(
    DashboardView(
      today: DateTime(2026, 4, 20),
      displayName: 'Maya',
      todayPain: null,
      todayMood: null,
      yesterdayPain: null,
      phaseUnavailableReason: null,
    ),
  );
}

class _SettledProfile extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async =>
      Fresh(meResponseFixture(id: 'user-1'));

  @override
  Future<void> saveDisplayName(String name) async {}
}

int _selectedIndex(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

/// Pumps the REAL production route table, wired to the REAL production
/// redirect, with a signed-in onboarded session and every screen's own reads
/// pinned settled.
Future<void> _pumpApp(
  WidgetTester tester, {
  String initialLocation = Routes.home,
}) async {
  final cacheStore = emptyCacheStore();
  final tokenStore = emptyTokenStore();

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
      ...lumenOverrides(cacheStore: cacheStore, tokenStore: tokenStore),
      onboardingFlowControllerProvider.overrideWith(_SettledOnboarding.new),
      cycleSetupControllerProvider.overrideWith(_SettledCycleSetup.new),
      cycleCalendarControllerProvider.overrideWith(_SettledCalendar.new),
      dashboardControllerProvider.overrideWith(_SettledDashboard.new),
      greetingTimeOfDayProvider.overrideWithValue('Good morning'),
      profileControllerProvider.overrideWith(_SettledProfile.new),
    ],
  );
}

class _MockMeRepository extends Mock implements MeRepository {}

MeResponse _me() => meResponseFixture(id: 'user-1', onboardingCompleted: true);

/// Pumps the REAL [LumenApp] — the real `goRouterProvider`, with its
/// `_RouterRefreshNotifier` wired to `authStatusProvider` — for the one test
/// that needs a genuine auth TRANSITION to drive real navigation (signing
/// out). [_pumpApp]'s hand-built `GoRouter` above takes `status` as a fixed
/// constant, which is the right shape for every other test in this file (see
/// `route_table_test.dart`/`shell_test.dart`'s identical pattern) but cannot
/// react to `logout()` changing that status mid-test.
///
/// settle: false — the splash spinner animates forever while the gate's `/me`
/// read is in flight, so a handful of manual frames stand in for it.
Future<void> _pumpRealApp(WidgetTester tester) async {
  final repo = _MockMeRepository();
  when(repo.getMe).thenAnswer((_) async => Fresh(_me()));
  final cacheStore = emptyCacheStore();
  final tokenStore = emptyTokenStore();

  await pumpLumenApp(
    tester,
    settle: false,
    overrides: [
      ...lumenOverrides(cacheStore: cacheStore, tokenStore: tokenStore),
      meRepositoryProvider.overrideWithValue(repo),
      onboardingFlowControllerProvider.overrideWith(_SettledOnboarding.new),
      cycleSetupControllerProvider.overrideWith(_SettledCycleSetup.new),
      cycleCalendarControllerProvider.overrideWith(_SettledCalendar.new),
      dashboardControllerProvider.overrideWith(_SettledDashboard.new),
      greetingTimeOfDayProvider.overrideWithValue('Good morning'),
      profileControllerProvider.overrideWith(_SettledProfile.new),
    ],
  );

  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  // -------------------------------------------------------------------------
  // Half 1 — the default lands on Home, not on a profile screen of any kind
  // -------------------------------------------------------------------------

  group('the authenticated default is Home (half 1 of R-19)', () {
    testWidgets(
      'a signed-in, onboarded user starting at an unmatched location lands '
      'on the dashboard, with the Home tab selected',
      (tester) async {
        await _pumpApp(tester, initialLocation: '/nope');

        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(find.byType(ProfileScreen), findsNothing);
        expect(_selectedIndex(tester), 0);
      },
    );

    testWidgets(
      'starting at the welcome screen (the pre-auth entry point) also lands '
      'on the dashboard once authenticated + onboarded is established',
      (tester) async {
        await _pumpApp(tester, initialLocation: Routes.welcome);

        expect(find.byType(DashboardScreen), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Half 2 (mount) — profile is reachable from the More tab, sign-out
  // included. This is the compliance surface the brief names directly: a
  // signed-in user must have SOME route to sign-out.
  // -------------------------------------------------------------------------

  group('profile — and sign-out — are reachable from the More tab (half 2 '
      'of R-19, the mount)', () {
    testWidgets(
      'tapping the More tab shows screen 31, with the Home tab no longer '
      'selected',
      (tester) async {
        await _pumpApp(tester);
        expect(find.byType(ProfileScreen), findsNothing);

        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();

        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(_selectedIndex(tester), 4);
        // Still inside the shell — the bottom nav survived the navigation,
        // proving this is a BRANCH of the shell, not a route that replaced
        // it (which is what a top-level `/profile` route would have done).
        expect(find.byType(LumenBottomNav), findsOneWidget);
      },
    );

    testWidgetsWithSemantics(
      'Sign out is reachable from the More tab and actually signs the user '
      'out — the concrete compliance affordance R-19 exists to protect',
      (tester) async {
        // The REAL app, not the fixed-status router [_pumpApp] uses
        // elsewhere in this file: this test needs `authStatusProvider`'s
        // OWN transition (via `logout()`) to drive real navigation, which
        // only the real `goRouterProvider`'s `_RouterRefreshNotifier`
        // reacts to.
        await _pumpRealApp(tester);

        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();

        expectLabeledButton(
          tester,
          find.bySemanticsLabel('Sign out'),
          'Sign out',
        );

        tester.semantics.tap(find.semantics.byLabel('Sign out'));
        await tester.pumpAndSettle();

        // The real production redirect responds to the auth transition —
        // signing out lands back on the welcome screen, not a dead end.
        expect(find.byType(ProfileScreen), findsNothing);
        expect(find.byType(LumenBottomNav), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // /profile has exactly one URL — the removal half of the mount, and the
  // one assertion that a "mounted under More but never actually removed"
  // partial implementation would not satisfy.
  // -------------------------------------------------------------------------

  group('"/profile" has exactly one URL (the removal half of R-19)', () {
    testWidgets(
      'a direct deep link to the literal path "/profile" does NOT render '
      'screen 31 there — it is not a registered route anymore, so it falls '
      'through to the unmatched-location fallback (Home)',
      (tester) async {
        await _pumpApp(tester, initialLocation: '/profile');

        expect(find.byType(ProfileScreen), findsNothing);
        expect(find.byType(DashboardScreen), findsOneWidget);
      },
    );

    testWidgets(
      'the ONLY way to screen 31 is "/more" — reaching it via the More tab '
      'and reading the router state back confirms the location, not just '
      'the widget',
      (tester) async {
        await _pumpApp(tester);

        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(ProfileScreen));
        final location = GoRouterState.of(context).uri.path;
        expect(location, Routes.more);
        expect(location, isNot('/profile'));
      },
    );
  });
}
