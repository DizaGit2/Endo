import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/features/shell/presentation/tab_placeholder_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

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
/// | authenticated   | completed  | "/", "/account", "/splash", "/onboarding" | "/profile" |
/// | authenticated   | completed  | unmatched location      | "/profile"    |
/// | authenticated   | completed  | any other known route   | null          |
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
        // location falls back to the authed default.
        case OnboardingStatus.completed:
          if (!isKnownLocation ||
              location == Routes.welcome ||
              location == Routes.account ||
              location == Routes.splash ||
              location == Routes.onboarding) {
            return Routes.profile;
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
/// - **Outside the shell** — splash, welcome, account, onboarding. These are
///   pre-app surfaces: the mockups for screens 1–7 have no bottom nav, and a
///   user part-way through onboarding must not be handed a nav bar that lets
///   them wander off. [Routes.profile] is also still out here (see below).
/// - **Inside the shell** — the five bottom-nav tabs, as branches of a
///   [StatefulShellRoute.indexedStack] in CLAUDE.md's order. `indexedStack`
///   (rather than a plain [ShellRoute] over an [IndexedStack] of tab roots)
///   gives every branch its own [Navigator], so a tab remembers how deep the
///   user had gone into it when they come back. That matters as soon as the
///   Cycle tab has `/cycle/day/:date` under it (P4b-T16/T17): without it,
///   glancing at Home would silently throw the open day away.
///
/// Routes belonging to a tab must be registered as CHILDREN of that tab's root
/// route, not as new top-level entries — a top-level route renders over the
/// whole app with no nav bar and no branch history.
///
/// **Why [Routes.profile] is not the More branch yet.** Screen 31 is a settings
/// screen and CLAUDE.md files settings under More, so that is where it will end
/// up. But it is also today's authenticated landing route and the only way to
/// reach sign-out and account deletion, and P4b-T2's brief keeps the three
/// unbuilt tabs on the placeholder. Moving it in now would mean either two
/// entry points to one screen or an authenticated user landing on a
/// placeholder — so it stays a top-level route until a task owns the More tab.
///
/// A function rather than a constant, deliberately: [StatefulShellRoute] and
/// [StatefulShellBranch] each allocate a [GlobalKey], so two simultaneously
/// live routers (a widget test's, say) must not share one instance.
List<RouteBase> lumenRoutes() => <RouteBase>[
  GoRoute(path: Routes.splash, builder: (_, _) => const _SplashScreen()),
  GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
  GoRoute(path: Routes.account, builder: (_, _) => const AccountScreen()),
  GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
  GoRoute(
    path: Routes.onboarding,
    builder: (_, _) => const _OnboardingPlaceholderScreen(),
  ),
  StatefulShellRoute.indexedStack(
    builder: (_, _, navigationShell) =>
        _TabShell(navigationShell: navigationShell),
    branches: <StatefulShellBranch>[
      // 0 — Home. P4b-T15 replaces the builder with screen 8 (dashboard).
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.home,
            builder: (_, _) =>
                const TabPlaceholderScreen(heading: 'Home isn\'t here yet'),
          ),
        ],
      ),
      // 1 — Cycle. P4b-T16/T17 replace the builder with screens 10 and 11.
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.cycle,
            builder: (_, _) =>
                const TabPlaceholderScreen(heading: 'Cycle isn\'t here yet'),
          ),
        ],
      ),
      // 2–4 — not in P4b at all. The tab exists because the nav is a design
      // constant; the destination says so plainly (ruling R-10).
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.hormones,
            builder: (_, _) =>
                const TabPlaceholderScreen(heading: 'Hormones aren\'t here yet'),
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
      StatefulShellBranch(
        routes: <RouteBase>[
          GoRoute(
            path: Routes.more,
            builder: (_, _) =>
                const TabPlaceholderScreen(heading: 'More isn\'t here yet'),
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
// Onboarding — placeholder until P4b-T8 builds the real flow
// ---------------------------------------------------------------------------

/// Stand-in for the onboarding flow (screens 3–7).
///
/// [Routes.onboarding] has to be a real registered route for the gate above to
/// have anywhere to send an authenticated-but-not-onboarded user, and a
/// redirect target that does not exist is worse than no gate at all. P4b-T8
/// replaces this builder with the real onboarding shell; it is private here for
/// the same reason [_SplashScreen] is — it is router chrome, not a feature
/// screen, and nothing else may reference it.
class _OnboardingPlaceholderScreen extends StatelessWidget {
  const _OnboardingPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LumenSectionLabel(
                'Onboarding',
                fontSize: 11,
                letterSpacing: 1.5,
              ),
              const SizedBox(height: 12),
              Text(
                'Set up Lumen',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A few questions about your cycle come next, so Lumen can '
                'make sense of what you log.',
                style: TextStyle(fontSize: 14, height: 1.5, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
