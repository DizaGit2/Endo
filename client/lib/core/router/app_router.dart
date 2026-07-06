import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';

// ---------------------------------------------------------------------------
// Redirect logic (pure function — unit-testable without a router instance)
// ---------------------------------------------------------------------------

/// The paths actually registered as [GoRoute]s in [goRouterProvider].
///
/// [Routes.onboarding] is deliberately NOT included: the route has no screen
/// yet (P4 will register it — see the TODO below), so until then it must be
/// treated the same as any other unregistered path.
const _knownPaths = {
  Routes.splash,
  Routes.welcome,
  Routes.account,
  Routes.profile,
};

/// Returns the path to redirect to, or null if no redirect is needed.
///
/// [location] must be the path only (no query/fragment) — callers pass
/// `state.uri.path`.
///
/// [location] is first checked against [_knownPaths]. An UNKNOWN path (e.g. a
/// stray deep link, or [Routes.onboarding] pre-P4) would otherwise reach
/// GoRouter's built-in "page not found" error screen, so it is redirected by
/// [status] alone, before the known-path truth table below ever runs.
///
/// Truth table (KNOWN paths only — unknown paths are handled above):
/// | status          | location                   | result       |
/// |-----------------|-----------------------------|--------------|
/// | unknown         | UNKNOWN path (any)          | "/splash"    |
/// | unknown         | "/splash"                   | null         |
/// | unknown         | known, other                | "/splash"    |
/// | unauthenticated | UNKNOWN path (any)          | "/"          |
/// | unauthenticated | "/" or "/account"            | null         |
/// | unauthenticated | known, other (incl. /splash) | "/"          |
/// | authenticated   | UNKNOWN path (any)          | "/profile"   |
/// | authenticated   | "/profile"                   | null         |
/// | authenticated   | known, other ("/", "/account", "/splash") | "/profile" |
///
/// TODO(P4): Route authenticated-but-not-onboarded users to [Routes.onboarding]
/// instead of [Routes.profile]. This requires reading an "onboarded" flag from
/// the user profile (loaded after login) and is deferred to P4 — until then,
/// [Routes.onboarding] falls through the UNKNOWN-path branch above.
String? lumenRedirect(AuthStatus status, String location) {
  // ── Unknown-route fallback ────────────────────────────────────────────────
  if (!_knownPaths.contains(location)) {
    switch (status) {
      case AuthStatus.unknown:
        return Routes.splash;
      case AuthStatus.unauthenticated:
        return Routes.welcome;
      case AuthStatus.authenticated:
        return Routes.profile;
    }
  }

  // ── Known-path auth gate (unchanged) ──────────────────────────────────────
  switch (status) {
    case AuthStatus.unknown:
      // Still initialising — hold on the splash so a cold start with a stored
      // session never flashes the welcome screen before redirecting to profile.
      return location == Routes.splash ? null : Routes.splash;

    case AuthStatus.unauthenticated:
      // Allow the welcome screen and the account (login/register) screen;
      // everything else (incl. the splash) goes to welcome.
      if (location == Routes.welcome || location == Routes.account) {
        return null;
      }
      return Routes.welcome;

    case AuthStatus.authenticated:
      // Authed users have no business on welcome / account / splash.
      if (location == Routes.welcome ||
          location == Routes.account ||
          location == Routes.splash) {
        return Routes.profile;
      }
      return null;
  }
}

// ---------------------------------------------------------------------------
// ChangeNotifier bridge — GoRouter refreshListenable
// ---------------------------------------------------------------------------

/// Bridges a Riverpod [ProviderListenable] to [ChangeNotifier] so GoRouter's
/// [refreshListenable] can re-run redirect logic whenever [authStatusProvider]
/// emits a new value.
class _AuthStatusNotifier extends ChangeNotifier {
  _AuthStatusNotifier(Ref ref) {
    ref.listen<AuthStatus>(authStatusProvider, (_, _) => notifyListeners());
  }
}

// ---------------------------------------------------------------------------
// goRouterProvider
// ---------------------------------------------------------------------------

/// Provides the [GoRouter] singleton wired to [authStatusProvider].
///
/// The [refreshListenable] is a [_AuthStatusNotifier] that fires
/// [ChangeNotifier.notifyListeners] whenever auth state changes, causing
/// GoRouter to re-evaluate the [redirect] callback.
final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthStatusNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authStatus = ref.read(authStatusProvider);
      // Path only — query/fragment must not break the location comparison.
      return lumenRedirect(authStatus, state.uri.path);
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const _SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.account, builder: (_, _) => const AccountScreen()),
      GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
    ],
  );
});

// ---------------------------------------------------------------------------
// Splash — shown while auth state resolves on cold start
// ---------------------------------------------------------------------------

/// Neutral loading screen shown while [AuthStatus] is [AuthStatus.unknown].
///
/// Prevents a flash of the welcome screen when a stored session resolves to
/// [AuthStatus.authenticated] a frame later.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
