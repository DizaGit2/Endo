import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';

// ---------------------------------------------------------------------------
// Redirect logic (pure function — unit-testable without a router instance)
// ---------------------------------------------------------------------------

/// Returns the path to redirect to, or null if no redirect is needed.
///
/// Truth table:
/// | status          | location            | result       |
/// |-----------------|---------------------|--------------|
/// | unknown         | any                 | null         |
/// | unauthenticated | "/" or "/account"   | null         |
/// | unauthenticated | other               | "/"          |
/// | authenticated   | "/" or "/account"   | "/profile"   |
/// | authenticated   | other               | null         |
///
/// TODO(P4): Route authenticated-but-not-onboarded users to [Routes.onboarding]
/// instead of [Routes.profile]. This requires reading an "onboarded" flag from
/// the user profile (loaded after login) and is deferred to P4.
String? lumenRedirect(AuthStatus status, String location) {
  switch (status) {
    case AuthStatus.unknown:
      // Still initialising — don't redirect; a brief splash on whatever
      // route was requested is acceptable.
      return null;

    case AuthStatus.unauthenticated:
      // Allow the welcome screen and the account (login/register) screen.
      if (location == Routes.welcome || location == Routes.account) {
        return null;
      }
      return Routes.welcome;

    case AuthStatus.authenticated:
      // Authed users have no business on the welcome / account screens.
      if (location == Routes.welcome || location == Routes.account) {
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

  return GoRouter(
    initialLocation: Routes.welcome,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authStatus = ref.read(authStatusProvider);
      return lumenRedirect(authStatus, state.uri.toString());
    },
    routes: [
      GoRoute(
        path: Routes.welcome,
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.account,
        // TODO(T7): replace _AccountPlaceholder with the real AccountScreen.
        builder: (_, _) => const _AccountPlaceholder(),
      ),
      GoRoute(
        path: Routes.profile,
        // TODO(T8): replace _ProfilePlaceholder with the real ProfileScreen.
        builder: (_, _) => const _ProfilePlaceholder(),
      ),
    ],
  );
});

// ---------------------------------------------------------------------------
// Placeholder screens — replaced in T7 / T8
// ---------------------------------------------------------------------------

/// Temporary placeholder for the Account screen (register / sign-in).
///
/// Replaced by the real AccountScreen in T7.
class _AccountPlaceholder extends StatelessWidget {
  const _AccountPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Account')),
    );
  }
}

/// Temporary placeholder for the Profile / home screen.
///
/// Replaced by the real ProfileScreen in T8.
class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Profile')),
    );
  }
}
