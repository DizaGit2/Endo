// Tests for the five-tab bottom-nav shell (P4b-T2).
//
// TDD (RED first). Before this task the route table was flat: `LumenBottomNav`
// existed but had no production caller, and screens 8/10/11 (T15–T17) would
// have had to invent navigation for themselves.
//
// These tests drive a REAL GoRouter over the REAL production route table
// (`lumenRoutes()`) through the REAL production redirect (`lumenRouteRedirect`),
// so they exercise the shipped shell rather than a copy of it. Only the
// Riverpod-backed status inputs are pinned, because the shell's behaviour is
// independent of how auth resolved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/presentation/cycle_calendar_screen.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Pumps the production route table at [initialLocation], wired to the
/// production redirect adapter with a pinned [status] / [onboarding].
Future<void> _pumpShell(
  WidgetTester tester, {
  String initialLocation = Routes.home,
  AuthStatus status = AuthStatus.authenticated,
  OnboardingStatus onboarding = OnboardingStatus.completed,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: lumenRoutes(),
    redirect: (_, state) =>
        lumenRouteRedirect(state, status: status, onboarding: onboarding),
  );
  addTearDown(router.dispose);

  await pumpRouterApp(
    tester,
    routerConfig: router,
    overrides: [
      ...lumenOverrides(auth: status),
      // `/onboarding` renders the real shell since P4b-T8, and the shell reads
      // `GET /onboarding/state` on mount. Pinned settled so this file stays
      // about the SHELL CHROME rather than about a network read.
      onboardingFlowControllerProvider.overrideWith(_SettledOnboarding.new),
      // …and since P4b-T9 the `cycle` step renders screen 3, which reads
      // `GET /settings/cycle` and `GET /cycle/calendar` on mount. Pinned for
      // the same reason: an unresolved read leaves an indeterminate spinner on
      // screen and `pumpAndSettle` never returns.
      cycleSetupControllerProvider.overrideWith(_SettledCycleSetup.new),
      // …and since P4b-T15 the Cycle TAB itself (branch root, not a step)
      // renders screen 10, which reads `GET /cycle/calendar` three times on
      // mount. Pinned settled for the same reason as the two controllers
      // above.
      cycleCalendarControllerProvider.overrideWith(_SettledCalendar.new),
    ],
  );
}

/// The onboarding shell, pinned to a settled first step.
class _SettledOnboarding extends OnboardingFlowController {
  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(step: OnboardingStep.cycle, state: onboardingStateFixture()),
  );
}

/// Screen 3, pinned to a settled form.
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

/// Screen 10, pinned to a settled (empty) month. `CycleCalendarController`'s
/// OWN `build()` is declared `Future<CycleCalendarView> Function()` (a real
/// await, not the bare `FutureOr<T>` its `AsyncNotifier` base allows) — an
/// override has to match the signature actually declared on its immediate
/// superclass, so this stays `async` even though it never really awaits
/// anything.
class _SettledCalendar extends CycleCalendarController {
  @override
  Future<CycleCalendarView> build() async => CycleCalendarView(
    visibleMonth: DateTime(2026, 4),
    today: Date(2026, 4, 20),
    phase: null,
    dayByDate: const <Date, CycleCalendarDay>{},
  );
}

int _selectedIndex(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

/// The five bottom-nav labels, in CLAUDE.md order — written out as literals
/// on purpose: reading them back from the production widget would make the
/// "all five destinations" assertion tautological.
const _allLabels = <String>['Home', 'Cycle', 'Hormones', 'Body', 'More'];

/// (bottom-nav label, the heading the tab's destination renders) for the
/// tabs that are STILL a bare [TabPlaceholderScreen]. Cycle is deliberately
/// absent since P4b-T15: it renders [CycleCalendarScreen] now, which has no
/// heading string to compare against — see [_tabContent].
const _placeholderTabs = <(String, String)>[
  ('Home', 'Home isn\'t here yet'),
  ('Hormones', 'Hormones aren\'t here yet'),
  ('Body', 'Body tracking isn\'t here yet'),
  ('More', 'More isn\'t here yet'),
];

/// (bottom-nav label, a [Finder] that matches ONLY when that tab's real
/// content is on screen), for every one of the five tabs.
///
/// Four still render [TabPlaceholderScreen] and are found by their heading
/// text, same as [_placeholderTabs]. Cycle (P4b-T15) is found by its own
/// screen TYPE instead — [CycleCalendarScreen] no longer has a placeholder
/// heading to compare against, and finding it by TYPE is also what proves the
/// route table's builder was actually replaced, not merely relabelled.
List<(String label, Finder content)> _tabContent() => <(String, Finder)>[
  ('Home', find.text('Home isn\'t here yet')),
  ('Cycle', find.byType(CycleCalendarScreen)),
  ('Hormones', find.text('Hormones aren\'t here yet')),
  ('Body', find.text('Body tracking isn\'t here yet')),
  ('More', find.text('More isn\'t here yet')),
];

void main() {
  // -------------------------------------------------------------------------
  // The shell itself
  // -------------------------------------------------------------------------

  group('the tab shell', () {
    testWidgets('/home lands in the shell with the bottom nav on Home', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(find.byType(LumenBottomNav), findsOneWidget);
      expect(_selectedIndex(tester), 0);
      expect(find.text('Home isn\'t here yet'), findsOneWidget);
    });

    testWidgets('all five destinations are present, in CLAUDE.md order', (
      tester,
    ) async {
      await _pumpShell(tester);

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 5);
      for (final label in _allLabels) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets(
      'tapping each tab shows that tab\'s content and the selected index '
      'follows',
      (tester) async {
        await _pumpShell(tester);
        final tabs = _tabContent();

        for (var index = 0; index < tabs.length; index++) {
          final (label, content) = tabs[index];

          await tester.tap(find.text(label));
          await tester.pumpAndSettle();

          expect(
            _selectedIndex(tester),
            index,
            reason: 'tapping "$label" should select index $index',
          );
          expect(
            content,
            findsOneWidget,
            reason: 'tapping "$label" should show its content',
          );
          // Only the active branch is on stage: go_router wraps the inactive
          // branch Navigators in Offstage, which the default finder skips.
          for (final (otherLabel, otherContent) in tabs) {
            if (otherLabel == label) continue;
            expect(otherContent, findsNothing);
          }
        }
      },
    );

    testWidgets('going back to a visited tab does not rebuild it from scratch', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: Routes.cycle);
      expect(find.byType(CycleCalendarScreen), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // Off stage, but still IN the tree: that retention is what makes a
      // branch's navigation stack survivable across a tab switch. A shell that
      // threw the branch away and rebuilt it would fail the skipOffstage:false
      // half of this pair.
      expect(find.byType(CycleCalendarScreen), findsNothing);
      expect(
        find.byType(CycleCalendarScreen, skipOffstage: false),
        findsOneWidget,
      );

      // And it really is a stateful shell: StatefulNavigationShell only exists
      // for a StatefulShellRoute. A plain ShellRoute over an IndexedStack of
      // tab roots would satisfy the retention assertions above but has no
      // branches, no per-branch Navigator and therefore no per-branch history
      // — which is what route_table_test.dart's pushed-route test pins down.
      final shell = tester.widget<StatefulNavigationShell>(
        find.byType(StatefulNavigationShell),
      );
      expect(shell.route.branches.length, 5);
    });
  });

  // -------------------------------------------------------------------------
  // The placeholder copy (R-10): honest, no date, no promise.
  // -------------------------------------------------------------------------

  group('unimplemented tabs state plainly that the feature is not here', () {
    // Home excluded (T17 still owes it its real screen); Cycle excluded
    // entirely from _placeholderTabs since P4b-T15 gave it a real one.
    for (final (label, heading) in _placeholderTabs.sublist(1)) {
      testWidgets('the $label tab renders the exact placeholder copy', (
        tester,
      ) async {
        await _pumpShell(tester);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        expect(find.text(heading), findsOneWidget);
        expect(
          find.text('This part of Lumen arrives in a later release.'),
          findsOneWidget,
        );
        // No date, no countdown, no "coming soon".
        expect(find.textContaining('soon'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Requirement 5: onboarding and auth are OUTSIDE the shell.
  // -------------------------------------------------------------------------

  group('routes outside the shell have no bottom nav', () {
    testWidgets('the welcome screen has no bottom nav', (tester) async {
      await _pumpShell(
        tester,
        initialLocation: Routes.welcome,
        status: AuthStatus.unauthenticated,
        onboarding: OnboardingStatus.unknown,
      );

      expect(find.byType(LumenBottomNav), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the account screen has no bottom nav', (tester) async {
      await _pumpShell(
        tester,
        initialLocation: Routes.account,
        status: AuthStatus.unauthenticated,
        onboarding: OnboardingStatus.unknown,
      );

      expect(find.byType(LumenBottomNav), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the onboarding flow has no bottom nav', (tester) async {
      await _pumpShell(
        tester,
        initialLocation: Routes.onboarding,
        onboarding: OnboardingStatus.incomplete,
      );

      expect(find.byType(OnboardingShellScreen), findsOneWidget);
      expect(find.byType(LumenBottomNav), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
