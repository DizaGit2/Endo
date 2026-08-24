import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/cycle/presentation/cycle_calendar_screen.dart';
import 'package:lumen/features/cycle/presentation/day_detail_screen.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';
import 'package:lumen/features/settings/presentation/cycle_settings_screen.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/features/shell/presentation/tab_placeholder_screen.dart';
import 'package:lumen/features/symptoms/presentation/body_map_screen.dart';
import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

// ---------------------------------------------------------------------------
// Redirect logic (pure function — unit-testable without a router instance)
// ---------------------------------------------------------------------------

/// Returns the path to redirect to, or null if no redirect is needed.
///
/// [location] must be the path only (no query/fragment) — callers pass
/// `state.uri.path`.
///
/// [isKnownLocation] is "does this location match a route in the table?".
/// It is NOT computed here and it is NOT a membership test against a list of
/// literals: [lumenRouteRedirect] takes it from GoRouter's own matcher, which
/// is the only thing that can answer it for a parameterised route such as
/// `/cycle/day/:date`. Registering a `GoRoute` is therefore the whole job of
/// adding a route — there is no second place to edit.
///
/// A location that matches NO route (a stray deep link, a typo) would otherwise
/// reach GoRouter's built-in "page not found" error screen, so it never returns
/// null: every status funnels it to that status's own destination. Only the
/// `authenticated + completed` branch has to test [isKnownLocation] explicitly —
/// it is the only branch whose "anything else" answer is "stay put".
///
/// Truth table:
/// | status          | onboarding | location                | result        |
/// |-----------------|------------|-------------------------|---------------|
/// | unknown         | any        | "/splash"               | null          |
/// | unknown         | any        | anything else           | "/splash"     |
/// | unauthenticated | any        | "/" or "/account"       | null          |
/// | unauthenticated | any        | anything else           | "/"           |
/// | authenticated   | unknown or unavailable | "/splash"   | null          |
/// | authenticated   | unknown or unavailable | anything else | "/splash"   |
/// | authenticated   | incomplete | "/onboarding"           | null          |
/// | authenticated   | incomplete | anything else           | "/onboarding" |
/// | authenticated   | completed  | "/", "/account", "/splash", "/onboarding" | "/home" |
/// | authenticated   | completed  | unmatched location      | "/home"       |
/// | authenticated   | completed  | any other known route   | null          |
///
/// **R-19: the authed default is [Routes.home], not `/profile`.** Screen 31
/// (profile) has no top-level route anymore — it mounts as the More branch's
/// root ([Routes.more], see [lumenRoutes]) — so this row and that mount are
/// the two halves of one ruling, shipped in the same commit: flipping this
/// default while profile stayed a separate top-level route would have
/// stranded a signed-in user with no route to sign-out (no nav destination
/// reaches `/profile` once it is not the default), and mounting profile
/// under More while this default still pointed at the old `/profile` route
/// would have given the one screen two live URLs with divergent back
/// behaviour. Neither half alone is R-19.
///
/// The `authenticated + unknown/unavailable` rows are the "profile not loaded
/// yet" case: this function must not fetch `/me` (it runs synchronously and
/// often), so it holds the user on the loading path the splash already provides
/// rather than guessing a side of the gate. [OnboardingStatusController]
/// resolves the value and the router's `refreshListenable` re-runs this
/// function when it does; [OnboardingStatus.unavailable] is the same routing
/// decision with a different splash surface (retry instead of spinner), so the
/// hold is always bounded.
String? lumenRedirect({
  required AuthStatus status,
  required OnboardingStatus onboarding,
  required String location,
  required bool isKnownLocation,
}) {
  switch (status) {
    // ── Still initialising ───────────────────────────────────────────────────
    // Hold on the splash so a cold start with a stored session never flashes
    // the welcome screen before redirecting on.
    case AuthStatus.unknown:
      return location == Routes.splash ? null : Routes.splash;

    // ── Signed out ───────────────────────────────────────────────────────────
    // Allow the welcome screen and the account (login/register) screen;
    // everything else (incl. the splash and /onboarding) goes to welcome.
    case AuthStatus.unauthenticated:
      if (location == Routes.welcome || location == Routes.account) {
        return null;
      }
      return Routes.welcome;

    // ── Signed in — the onboarding gate ──────────────────────────────────────
    case AuthStatus.authenticated:
      switch (onboarding) {
        // The gate's answer has not arrived (still loading, or the read
        // outran its bounded wait): hold on the splash, which renders a
        // spinner or a retry accordingly. Never guess a side of the gate.
        case OnboardingStatus.unknown:
        case OnboardingStatus.unavailable:
          return location == Routes.splash ? null : Routes.splash;

        // Gate closed: everything funnels into the onboarding flow, including
        // unmatched locations. Already there → no redirect (no loop).
        case OnboardingStatus.incomplete:
          if (location == Routes.onboarding) return null;
          return Routes.onboarding;

        // Gate open: honour the requested route. Onboarded users have no
        // business on welcome / account / splash / onboarding, and an unmatched
        // location falls back to the authed default — the Home branch since
        // R-19, not `/profile` (removed as a top-level route; see this
        // function's own dartdoc for why the two halves of R-19 ship together).
        case OnboardingStatus.completed:
          if (!isKnownLocation ||
              location == Routes.welcome ||
              location == Routes.account ||
              location == Routes.splash ||
              location == Routes.onboarding) {
            return Routes.home;
          }
          return null;
      }
  }
}

/// Adapts a [GoRouterState] to [lumenRedirect]. This is the production
/// `redirect` callback body, shared with its tests so they exercise the real
/// wiring rather than a copy of it.
///
/// `state.error` is GoRouter's own answer to "did this location match a route?"
/// — `RouteConfiguration.buildTopLevelGoRouterState` copies it straight from
/// `RouteMatchList.error`, which is set exactly when the matcher found no route
/// for the URL (go_router 17.3.0, `src/configuration.dart`). Using it means the
/// route table is the single source of truth: nested routes, shell branches and
/// parameterised paths all answer correctly because the matcher walks the whole
/// tree, and no hand-maintained path list can drift from it.
String? lumenRouteRedirect(
  GoRouterState state, {
  required AuthStatus status,
  required OnboardingStatus onboarding,
}) {
  return lumenRedirect(
    status: status,
    onboarding: onboarding,
    // Path only — query/fragment must not break the location comparison.
    location: state.uri.path,
    isKnownLocation: state.error == null,
  );
}

// ---------------------------------------------------------------------------
// ChangeNotifier bridge — GoRouter refreshListenable
// ---------------------------------------------------------------------------

/// Bridges the Riverpod state the redirect reads to a [ChangeNotifier] so
/// GoRouter's [GoRouter.refreshListenable] re-runs [lumenRedirect] whenever it
/// changes.
///
/// Both sources matter: [authStatusProvider] for sign-in/sign-out, and
/// [onboardingStatusProvider] because the `/me` read that opens or closes the
/// gate resolves a few frames after the router is built — without it an
/// authenticated user would sit on the splash forever.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen<AuthStatus>(authStatusProvider, (_, _) => notifyListeners());
    ref.listen<OnboardingStatus>(
      onboardingStatusProvider,
      (_, _) => notifyListeners(),
    );
  }
}

// ---------------------------------------------------------------------------
// goRouterProvider
// ---------------------------------------------------------------------------

/// The one route table.
///
/// Adding a screen is: add a constant to [Routes], add a [GoRoute] here, import
/// the screen. Nothing else — the redirect derives what it knows from this
/// table (see [lumenRouteRedirect]).
///
/// Two shapes live here, and the split is the whole point:
///
/// - **Outside the shell** — splash, welcome, account, onboarding, and (since
///   P4b-T20b) screen 12 at [Routes.symptomsNew]. The first four are pre-app
///   surfaces: the mockups for screens 1–7 have no bottom nav, and a user
///   part-way through onboarding must not be handed a nav bar that lets them
///   wander off. Screen 12 is out here for a different reason — it is a task
///   flow pushed from inside a branch and popped back into it — but the same
///   test applies: its mockup draws no bottom nav either. Screen 31 (profile)
///   is NOT out here — see below.
/// - **Inside the shell** — the five bottom-nav tabs, as branches of a
///   [StatefulShellRoute.indexedStack] in CLAUDE.md's order. `indexedStack`
///   (rather than a plain [ShellRoute] over an [IndexedStack] of tab roots)
///   gives every branch its own [Navigator], so a tab remembers how deep the
///   user had gone into it when they come back. That matters as soon as the
///   Cycle tab has `/cycle/day/:date` under it (P4b-T16): without it,
///   glancing at Home would silently throw the open day away.
///
/// Routes belonging to a tab must be registered as CHILDREN of that tab's root
/// route, not as new top-level entries — a top-level route renders over the
/// whole app with no nav bar and no branch history.
///
/// **Screen 31 (profile) mounts as the More branch's ROOT (P4b-T17, R-19)** —
/// the settled home CLAUDE.md always intended for it (a settings screen files
/// under More), and now its only URL: there is no top-level `/profile` route
/// anymore. This shipped in the SAME commit as [Routes.home] becoming the
/// authed default (`lumenRedirect`, above) — the two are one ruling, not two:
/// flipping the default alone (profile still top-level, still unreached from
/// any nav destination) would have stranded a signed-in user with no route to
/// sign-out; mounting profile here alone (default still pointing at the old
/// `/profile`) would have given one screen two live URLs with divergent back
/// behaviour. **Screen 36 (privacy & security) is that root's first CHILD
/// since P4b-T22c** ([Routes.privacy]) — the same shape `/cycle/day/:date`
/// uses under [Routes.cycle] — and **screen 32 (cycle settings) is its sibling
/// since P4b-T22a** ([Routes.cycleSettings]), which is what R-19 means by
/// *"T22a then pushes screen 32 inside that branch"*.
///
/// A function rather than a constant, deliberately: [StatefulShellRoute] and
/// [StatefulShellBranch] each allocate a [GlobalKey], so two simultaneously
/// live routers (a widget test's, say) must not share one instance.
List<RouteBase> lumenRoutes() => <RouteBase>[
  GoRoute(path: Routes.splash, builder: (_, _) => const _SplashScreen()),
  GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
  GoRoute(path: Routes.account, builder: (_, _) => const AccountScreen()),
  GoRoute(
    path: Routes.onboarding,
    builder: (_, _) => const OnboardingShellScreen(),
  ),
  // Screen 12 (P4b-T20b). Out here WITH the pre-app surfaces rather than
  // under a tab, and for a related reason: it is a task flow entered and left
  // (the mockup draws no bottom nav), so it renders over the whole app and is
  // PUSHED from whichever branch the user was in. `context.pop()` then returns
  // them to that branch — the deciding property, since mounting it under one
  // tab would either strand a user who arrived from another or give the screen
  // two URLs with divergent back behaviour.
  GoRoute(
    path: Routes.symptomsNew,
    builder: (_, _) => const SymptomFormScreen(),
  ),
  // Screen 13 (P4b-T21b). A SIBLING of screen 12, not a child of it: screen 12
  // is a plain GoRoute rather than a shell, so a child route would still push
  // onto the same root Navigator while implying a nesting that does not exist.
  // Pushed from screen 12's body-map affordance (R-20), and popped back into
  // it — screen 12 stays mounted underneath, which is what keeps its
  // autoDispose form (and every unsent selection on it) alive.
  GoRoute(
    path: Routes.symptomsBodyMap,
    builder: (_, _) => const BodyMapScreen(),
  ),
  StatefulShellRoute.indexedStack(
    builder: (_, _, navigationShell) =>
        _TabShell(navigationShell: navigationShell),
    branches: <StatefulShellBranch>[
      // 0 — Home. Screen 8 (the dashboard), and the authenticated default
      // since R-19 (P4b-T17) — see lumenRedirect's own dartdoc.
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.home,
            builder: (_, _) => const DashboardScreen(),
          ),
        ],
      ),
      // 1 — Cycle. Screen 10 (calendar) ships here — P4b-T15. P4b-T16 adds
      // screen 11 (day detail) as a CHILD route under this one
      // (`/cycle/day/:date`), together with the day-cell tap that reaches
      // it — the app's FIRST parameterised route. A child, not a sibling in
      // this branch's own `routes:` list, so it stacks on top of the
      // calendar in the branch's own Navigator (system back / `context.pop()`
      // returns to the calendar) rather than replacing it.
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.cycle,
            builder: (_, _) => const CycleCalendarScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: Routes.cycleDaySegment,
                builder: (_, state) {
                  // No `redirect:` here on purpose: a redirect would make a
                  // malformed date vanish silently into `/cycle` with no
                  // explanation, and this app has exactly ONE whole-surface
                  // failure pattern (`_GateUnavailableBody` above collapses
                  // onto the same `LumenErrorRetry`, per P4b-T5) — inventing
                  // a second would violate that. The round-trip check that
                  // catches `/cycle/day/2026-02-31` (which MATCHES this
                  // route just as well as a real date —
                  // `Routes.parseCycleDayDate`'s own dartdoc) runs here,
                  // before any read — and, once T16b lands, before any
                  // write — is ever issued for the rolled date.
                  final date = Routes.parseCycleDayDate(
                    state.pathParameters['date'],
                  );
                  if (date == null) return const _InvalidDayDateScreen();
                  return DayDetailScreen(date: date);
                },
              ),
            ],
          ),
        ],
      ),
      // 2–4 — not in P4b at all. The tab exists because the nav is a design
      // constant; the destination says so plainly (ruling R-10).
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.hormones,
            builder: (_, _) => const TabPlaceholderScreen(
              heading: 'Hormones aren\'t here yet',
            ),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.body,
            builder: (_, _) => const TabPlaceholderScreen(
              heading: 'Body tracking isn\'t here yet',
            ),
          ),
        ],
      ),
      // 4 — More. Screen 31 (profile) mounts as this branch's root since
      // P4b-T17 (R-19) — see lumenRoutes' own dartdoc above for why this and
      // the redirect flip are one ruling. Treatment and reports (the rest of
      // what "More" names) are not built in P4b and stay off this branch —
      // R-10 covers only the TAB existing with an honest destination, not a
      // full accordion of placeholder children.
      //
      // Screen 36 (privacy & security) is a CHILD of that root since P4b-T22c,
      // and screen 32 (cycle settings) is its SIBLING since P4b-T22a — each
      // together with the row on screen 31 that reaches it (R-20). Children, so
      // they stack inside the branch's own Navigator and pop back to profile
      // with the tab and the nav bar intact — the same arrangement
      // `/cycle/day/:date` has under Routes.cycle.
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.more,
            builder: (_, _) => const ProfileScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: Routes.cycleSettingsSegment,
                builder: (_, _) => const CycleSettingsScreen(),
              ),
              GoRoute(
                path: Routes.privacySegment,
                builder: (_, _) => const PrivacyScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];

/// Provides the [GoRouter] singleton wired to [authStatusProvider] and
/// [onboardingStatusProvider].
final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    redirect: (_, state) => lumenRouteRedirect(
      state,
      status: ref.read(authStatusProvider),
      onboarding: ref.read(onboardingStatusProvider),
    ),
    routes: lumenRoutes(),
  );
});

// ---------------------------------------------------------------------------
// The tab shell — chrome around the five branch Navigators
// ---------------------------------------------------------------------------

/// What a bottom-nav tap does: switch [shell] to the branch at [index].
///
/// The whole behavioural contract of the tab bar lives in this one line, and it
/// is a line with three plausible-looking spellings that behave very
/// differently once a tab is more than one route deep:
///
/// - `goBranch(index)` — re-tapping the tab you are on does nothing, so a user
///   deep inside a tab has no way back to its top;
/// - `goBranch(index, initialLocation: true)` — every tab switch resets the
///   branch, throwing away the open day/detail the user was on. That is exactly
///   the loss [StatefulShellRoute.indexedStack] was chosen to prevent;
/// - `initialLocation: index == shell.currentIndex` — the correct one, and the
///   standard go_router idiom: tapping the current tab returns to its top,
///   tapping a different tab resumes it where it was left.
///
/// It is a named top-level function rather than a closure inside [_TabShell] so
/// that the mirror route table in `route_table_test.dart` — the only table with
/// a branch deep enough to tell the three spellings apart — calls **this**
/// function rather than a hand-retyped copy of it. Sharing the callback is what
/// makes those branch-stack tests production tests; the route table itself
/// stays a deliberate hand-maintained mirror (that duplication is load-bearing
/// and must not be removed).
void switchToBranch(StatefulNavigationShell shell, int index) {
  shell.goBranch(index, initialLocation: index == shell.currentIndex);
}

/// Wraps the active branch's [Navigator] in the app's persistent chrome.
///
/// [navigationShell] is both the content (it renders the branch [IndexedStack])
/// and the controller (`currentIndex` / `goBranch`), which is why the nav bar
/// needs no state of its own — the router IS the selected-tab state, so a deep
/// link straight to `/cycle` shows the Cycle tab selected without anything
/// having to synchronise.
///
/// It reuses [LumenBottomNav] as-is rather than declaring a second nav widget —
/// that stub existed with no production caller since P3c, and this is its
/// caller. Tap handling is [switchToBranch].
class _TabShell extends StatelessWidget {
  const _TabShell({required this.navigationShell});

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

// ---------------------------------------------------------------------------
// Splash — shown while auth state resolves on cold start
// ---------------------------------------------------------------------------

/// Neutral loading screen shown while [AuthStatus] is [AuthStatus.unknown], or
/// while an authenticated session's [OnboardingStatus] is still loading.
///
/// Prevents a flash of the welcome screen when a stored session resolves to
/// [AuthStatus.authenticated] a frame later.
///
/// It is also the failure surface for the onboarding gate's `/me` read. That
/// read used to live on the profile screen, which has a designed retry state;
/// moving it here would otherwise have left an authenticated user on a flaky
/// network watching an indeterminate spinner until Dio gave up (up to ~20 s),
/// with nothing to tap. When the read exceeds its bounded wait the spinner is
/// replaced by the same error + retry affordance screen 31 uses.
class _SplashScreen extends ConsumerWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    if (ref.watch(onboardingStatusProvider) == OnboardingStatus.unavailable) {
      return const Scaffold(body: SafeArea(child: _GateUnavailableBody()));
    }

    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: scheme.primary,
          semanticsLabel: 'Loading',
        ),
      ),
    );
  }
}

/// Error + retry shown on the splash when the gate's `/me` read outran its
/// bounded wait.
///
/// Copy and shape are screen 31's, because P4b-T5 collapsed both onto the same
/// [LumenErrorRetry] — the app has one whole-surface failure pattern, not two.
/// The only thing this call site owns is what "try again" means here: rebuild
/// the controller, which is a fresh generation, back to `unknown` (spinner),
/// and a new `/me` read.
class _GateUnavailableBody extends ConsumerWidget {
  const _GateUnavailableBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LumenErrorRetry(
      message: 'Something went wrong. Please try again.',
      onRetry: () => ref.invalidate(onboardingStatusProvider),
    );
  }
}

// ---------------------------------------------------------------------------
// Invalid `:date` — screen 11's own failure surface for a malformed deep link
// ---------------------------------------------------------------------------

/// Rendered when `/cycle/day/:date` MATCHES but the value fails
/// [Routes.parseCycleDayDate]'s round-trip check — e.g. a stale or
/// hand-typed deep link to `/cycle/day/2026-02-31`, which go_router's
/// pattern matcher accepts just as readily as a real date (see
/// [Routes.parseCycleDayDate]'s dartdoc for why the pattern alone cannot
/// catch it).
///
/// Same [LumenErrorRetry] every other whole-surface failure in this app
/// uses — screen 11 is the one screen a malformed date belongs to, and there
/// is nothing to "retry" that would fix a bad date, so the affordance
/// returns to the calendar instead of re-running the same parse.
class _InvalidDayDateScreen extends StatelessWidget {
  const _InvalidDayDateScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LumenErrorRetry(
          message: "That date isn't valid.",
          onRetry: () => context.go(Routes.cycle),
        ),
      ),
    );
  }
}
