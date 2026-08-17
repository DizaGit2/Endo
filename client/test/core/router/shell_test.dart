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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _FixedAuthController extends AuthController {
  _FixedAuthController(this._status);
  final AuthStatus _status;

  @override
  AuthStatus build() {
    initialized = Future<void>.value();
    return _status;
  }
}

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

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStatusProvider.overrideWith(() => _FixedAuthController(status)),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: lumenTheme(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _selectedIndex(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

/// (bottom-nav label, the heading the tab's destination renders).
///
/// The headings are written out as literals on purpose: reading them back from
/// the production widget would make the copy assertions tautological.
const _tabs = <(String, String)>[
  ('Home', 'Home isn\'t here yet'),
  ('Cycle', 'Cycle isn\'t here yet'),
  ('Hormones', 'Hormones aren\'t here yet'),
  ('Body', 'Body tracking isn\'t here yet'),
  ('More', 'More isn\'t here yet'),
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
      for (final (label, _) in _tabs) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets(
      'tapping each tab shows that tab\'s content and the selected index '
      'follows',
      (tester) async {
        await _pumpShell(tester);

        for (var index = 0; index < _tabs.length; index++) {
          final (label, heading) = _tabs[index];

          await tester.tap(find.text(label));
          await tester.pumpAndSettle();

          expect(
            _selectedIndex(tester),
            index,
            reason: 'tapping "$label" should select index $index',
          );
          expect(
            find.text(heading),
            findsOneWidget,
            reason: 'tapping "$label" should show "$heading"',
          );
          // Only the active branch is on stage: go_router wraps the inactive
          // branch Navigators in Offstage, which the default finder skips.
          for (final (otherLabel, otherHeading) in _tabs) {
            if (otherLabel == label) continue;
            expect(find.text(otherHeading), findsNothing);
          }
        }
      },
    );

    testWidgets('going back to a visited tab does not rebuild it from scratch', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: Routes.cycle);
      expect(find.text('Cycle isn\'t here yet'), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // Off stage, but still IN the tree: that retention is what makes a
      // branch's navigation stack survivable across a tab switch. A shell that
      // threw the branch away and rebuilt it would fail the skipOffstage:false
      // half of this pair.
      expect(find.text('Cycle isn\'t here yet'), findsNothing);
      expect(
        find.text('Cycle isn\'t here yet', skipOffstage: false),
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
    for (final (label, heading) in _tabs.sublist(2)) {
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

      expect(find.text('Set up Lumen'), findsOneWidget);
      expect(find.byType(LumenBottomNav), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
