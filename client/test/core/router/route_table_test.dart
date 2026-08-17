// Tests for the route table as the single source of truth (P4b-T1, extended by
// P4b-T2).
//
// TDD (RED first). Before P4b-T1 the redirect consulted a hand-maintained
// `const _knownPaths = { … }` of literal strings: a GoRoute added to the table
// without a matching second edit was silently redirected away, and a
// parameterised route (`/cycle/day/:date`) could not be expressed at all.
//
// These tests drive a REAL GoRouter through the production redirect adapter
// (`lumenRouteRedirect`), so they fail if the literal list ever comes back:
//   • `/t1-newly-registered-route` is registered in this file's route table and
//     NOWHERE else — no constant, no set membership, no production edit. If the
//     "known" decision stops deriving from the route table, this route is
//     swallowed by the unknown-location fallback and the test goes red.
//   • `/t2-shell-branch-route` is the same trick one level harder: its only
//     registration is inside a StatefulShellBranch.
//   • `/cycle/day/:date` is matched by the concrete location
//     `/cycle/day/2026-04-07`, which no `Set<String>` of literals can express.
//   • that parameterised route is registered as a CHILD of a shell branch's
//     root route, so the derivation is proven to walk into the branch
//     Navigators rather than only the top level. T1 could only reason about
//     this from go_router's source; T2 introduced a real StatefulShellRoute, so
//     it can be tested.
//
// `_probeRoutes` is a DELIBERATELY hand-maintained mirror of the production
// table. It is not derived from `lumenRoutes()` and must not become derived:
// the point of the two probe routes above is that they exist ONLY here, which
// is what makes "registration is enough" falsifiable instead of tautological.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/app.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Probe screen — renders its own name so a test can assert which route won
// ---------------------------------------------------------------------------

class _Probe extends StatelessWidget {
  const _Probe(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

/// Mirrors the production shell chrome (`_TabShell` in `app_router.dart`) so a
/// probe test can switch branches the way a user does — by tapping the nav.
///
/// The tap handler is NOT mirrored: it calls the production [switchToBranch]
/// directly. Every production branch is one route deep today, so `goBranch(i)`,
/// `initialLocation: true` and the correct expression are indistinguishable
/// there — a retyped copy here would leave the real call site untested until
/// T15/T16 made a regression user-visible. Only the ROUTE TABLE below is a
/// deliberate hand-maintained mirror.
class _ProbeShell extends StatelessWidget {
  const _ProbeShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return LumenScaffold(
      body: navigationShell,
      bottomNavigationBar: LumenBottomNav(
        currentIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) =>
            switchToBranch(navigationShell, index),
      ),
    );
  }
}

/// A route table that mirrors the production one (five shell branches in
/// CLAUDE.md order) plus three routes that exist ONLY here. Nothing else in the
/// repository mentions them.
///
/// A function, not a constant: `StatefulShellRoute`/`StatefulShellBranch` each
/// allocate a `GlobalKey`, so two live routers must not share one instance.
List<RouteBase> _probeRoutes() => <RouteBase>[
  GoRoute(path: Routes.splash, builder: (_, _) => const _Probe('splash')),
  GoRoute(path: Routes.welcome, builder: (_, _) => const _Probe('welcome')),
  GoRoute(path: Routes.account, builder: (_, _) => const _Probe('account')),
  GoRoute(path: Routes.profile, builder: (_, _) => const _Probe('profile')),
  GoRoute(
    path: Routes.onboarding,
    builder: (_, _) => const _Probe('onboarding'),
  ),
  // Registered here and nowhere else — no constant, no membership list.
  GoRoute(
    path: '/t1-newly-registered-route',
    builder: (_, _) => const _Probe('newly registered'),
  ),
  StatefulShellRoute.indexedStack(
    builder: (_, _, navigationShell) =>
        _ProbeShell(navigationShell: navigationShell),
    branches: <StatefulShellBranch>[
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(path: Routes.home, builder: (_, _) => const _Probe('home')),
        ],
      ),
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.cycle,
            builder: (_, _) => const _Probe('cycle'),
            routes: <RouteBase>[
              // Parameterised AND nested under a shell branch's root — the
              // shape T15–T17 will use for screens 10/11.
              GoRoute(
                path: 'day/:date',
                builder: (_, state) =>
                    _Probe('day ${state.pathParameters['date']}'),
              ),
            ],
          ),
          // Registered ONLY as a route of a shell branch — nowhere else.
          GoRoute(
            path: '/t2-shell-branch-route',
            builder: (_, _) => const _Probe('shell branch route'),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.hormones,
            builder: (_, _) => const _Probe('hormones'),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(path: Routes.body, builder: (_, _) => const _Probe('body')),
        ],
      ),
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(path: Routes.more, builder: (_, _) => const _Probe('more')),
        ],
      ),
    ],
  ),
];

/// Pumps a real [GoRouter] over [routes], wired to the SAME redirect adapter
/// the production router uses, and settles on [initialLocation].
Future<void> _pumpProbeRouter(
  WidgetTester tester, {
  required String initialLocation,
  AuthStatus status = AuthStatus.authenticated,
  OnboardingStatus onboarding = OnboardingStatus.completed,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: _probeRoutes(),
    redirect: (_, state) =>
        lumenRouteRedirect(state, status: status, onboarding: onboarding),
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

int _selectedIndex(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

// ---------------------------------------------------------------------------
// Production-router harness
// ---------------------------------------------------------------------------

class _MockMeRepository extends Mock implements MeRepository {}

class _FixedAuthController extends AuthController {
  _FixedAuthController(this._status);
  final AuthStatus _status;

  @override
  AuthStatus build() {
    initialized = Future<void>.value();
    return _status;
  }
}

class _FakeProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async => Fresh(_me(true));

  @override
  Future<void> saveDisplayName(String name) async {}
}

MeResponse _me(bool? onboardingCompleted) {
  return MeResponse(
    (b) => b
      ..id = 'user-1'
      ..displayName = 'María'
      ..locale = 'es'
      ..timezone = 'Europe/Madrid'
      ..onboardingCompleted = onboardingCompleted,
  );
}

/// Pumps the real [LumenApp] (and therefore the real `goRouterProvider` route
/// table) with an authenticated session whose `/me` reports
/// [onboardingCompleted].
Future<void> _pumpRealApp(
  WidgetTester tester, {
  required bool? onboardingCompleted,
}) async {
  final repo = _MockMeRepository();
  when(repo.getMe).thenAnswer((_) async => Fresh(_me(onboardingCompleted)));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStatusProvider.overrideWith(
          () => _FixedAuthController(AuthStatus.authenticated),
        ),
        meRepositoryProvider.overrideWithValue(repo),
        profileControllerProvider.overrideWith(_FakeProfileController.new),
      ],
      child: const LumenApp(),
    ),
  );

  // Not pumpAndSettle(): the splash spinner animates forever, so "settle"
  // never arrives while the profile load is still in flight. A handful of
  // frames is enough for the /me read to resolve, the refreshListenable to
  // fire and GoRouter to re-run the redirect.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  // -------------------------------------------------------------------------
  // The falsifiable regression test: registration in the table is enough.
  // -------------------------------------------------------------------------

  group('known paths derive from the route table', () {
    testWidgets(
      'a route registered ONLY in the route table is recognised — no second '
      'edit anywhere',
      (tester) async {
        await _pumpProbeRouter(
          tester,
          initialLocation: '/t1-newly-registered-route',
        );

        expect(find.text('newly registered'), findsOneWidget);
        expect(find.text('profile'), findsNothing);
      },
    );

    testWidgets('a location matching no route still falls back by auth status', (
      tester,
    ) async {
      await _pumpProbeRouter(tester, initialLocation: '/definitely-not-a-route');

      expect(find.text('profile'), findsOneWidget);
    });

    testWidgets(
      'the gate still wins over a registered route (adapter passes status '
      'through)',
      (tester) async {
        await _pumpProbeRouter(
          tester,
          initialLocation: '/t1-newly-registered-route',
          onboarding: OnboardingStatus.incomplete,
        );

        expect(find.text('onboarding'), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Requirement 6: the derivation reaches INSIDE a StatefulShellRoute branch.
  // T1 could only reason about this; the shell exists now, so it is tested.
  // -------------------------------------------------------------------------

  group('routes inside a StatefulShellRoute branch', () {
    testWidgets(
      'a route registered ONLY inside a shell branch is recognised',
      (tester) async {
        await _pumpProbeRouter(
          tester,
          initialLocation: '/t2-shell-branch-route',
        );

        expect(find.text('shell branch route'), findsOneWidget);
        expect(find.text('profile'), findsNothing);
      },
    );

    testWidgets('a shell branch\'s root route is recognised', (tester) async {
      await _pumpProbeRouter(tester, initialLocation: Routes.cycle);

      expect(find.text('cycle'), findsOneWidget);
      expect(find.byType(LumenBottomNav), findsOneWidget);
    });

    testWidgets(
      'a location that matches nothing UNDER a branch root still falls back',
      (tester) async {
        await _pumpProbeRouter(tester, initialLocation: '/cycle/not-a-route');

        // The shell must not swallow unmatched deep links into its branch.
        expect(find.text('profile'), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Parameterised routes — impossible with a Set<String> of literals. These
  // now live one level down inside a shell branch as well.
  // -------------------------------------------------------------------------

  group('parameterised routes nested under a shell branch root', () {
    testWidgets('"/cycle/day/2026-04-07" matches the "/cycle/day/:date" route', (
      tester,
    ) async {
      await _pumpProbeRouter(tester, initialLocation: '/cycle/day/2026-04-07');

      expect(find.text('day 2026-04-07'), findsOneWidget);
      expect(find.text('profile'), findsNothing);
    });

    testWidgets('a different concrete date matches the same route', (
      tester,
    ) async {
      await _pumpProbeRouter(tester, initialLocation: '/cycle/day/2025-12-31');

      expect(find.text('day 2025-12-31'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 1: each branch keeps its OWN navigation stack. This is the
  // whole reason for StatefulShellRoute.indexedStack over a plain IndexedStack
  // of branch roots — so the assertion is about the PUSHED route, not the root.
  //
  // These two run against the PRODUCTION tap handler (`switchToBranch`), not a
  // copy of it: the mirror table exists to give that handler a branch that is
  // two routes deep, which no production branch is yet. Simplifying
  // `switchToBranch` to `shell.goBranch(index)` turns the second one red.
  // -------------------------------------------------------------------------

  group('branch navigation stacks', () {
    testWidgets(
      'switching away from a branch and back leaves you on the pushed route',
      (tester) async {
        await _pumpProbeRouter(tester, initialLocation: '/cycle/day/2026-04-07');
        expect(find.text('day 2026-04-07'), findsOneWidget);
        expect(_selectedIndex(tester), 1);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        expect(_selectedIndex(tester), 0);
        expect(find.text('home'), findsOneWidget);
        expect(find.text('day 2026-04-07'), findsNothing);

        await tester.tap(find.text('Cycle'));
        await tester.pumpAndSettle();

        expect(_selectedIndex(tester), 1);
        // Still on the SECOND route of the branch, not its root: a shell that
        // only remembered which branch was selected would show 'cycle' here.
        expect(find.text('day 2026-04-07'), findsOneWidget);
        expect(find.text('cycle'), findsNothing);
      },
    );

    testWidgets('tapping the already-selected tab returns to the branch root', (
      tester,
    ) async {
      await _pumpProbeRouter(tester, initialLocation: '/cycle/day/2026-04-07');
      expect(find.text('day 2026-04-07'), findsOneWidget);

      await tester.tap(find.text('Cycle'));
      await tester.pumpAndSettle();

      expect(find.text('cycle'), findsOneWidget);
      expect(find.text('day 2026-04-07'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // The production route table: /onboarding is a real registered route and the
  // gate lands on it.
  // -------------------------------------------------------------------------

  group('production router — the onboarding gate', () {
    testWidgets(
      'an authenticated user with onboardingCompleted == false lands on the '
      'onboarding route',
      (tester) async {
        await _pumpRealApp(tester, onboardingCompleted: false);

        expect(find.text('Set up Lumen'), findsOneWidget);
      },
    );

    testWidgets(
      'an authenticated user with a null onboardingCompleted lands on the '
      'onboarding route',
      (tester) async {
        await _pumpRealApp(tester, onboardingCompleted: null);

        expect(find.text('Set up Lumen'), findsOneWidget);
      },
    );

    testWidgets(
      'an authenticated, onboarded user ARRIVES at the profile screen',
      (tester) async {
        await _pumpRealApp(tester, onboardingCompleted: true);

        // The positive half is the load-bearing one: `findsNothing` alone is
        // also satisfied by a user stranded on the splash, so on its own it
        // could not fail for the reason this test exists (e.g. deleting the
        // onboardingStatusProvider listen in _RouterRefreshNotifier would
        // leave it green). Assert the destination, not just the non-destination.
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(find.text('Set up Lumen'), findsNothing);
      },
    );
  });
}
