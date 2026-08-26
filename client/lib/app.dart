import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'core/error/retry_policy.dart';
import 'core/push/push_registration_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/lumen_theme.dart';

/// Root application widget for Lumen.
///
/// Wires [MaterialApp.router] with the [goRouterProvider] (GoRouter with
/// auth-guard redirect logic) and the light/dark [ThemeData] built from
/// design tokens, respecting the system theme mode.
///
/// Navigation is managed by GoRouter (P3b-T5). The initial route is [Routes.welcome]
/// (the onboarding welcome screen) and the router redirects based on [AuthStatus].
class LumenApp extends ConsumerWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The app-start push registration (§C.0.3, ruling R-09). `listen` and not
    // `watch`: this subscription exists to BUILD the provider — the root
    // `ProviderScope` is created once per process, so one build of it is one
    // app start — and the app has nothing to redraw when the outcome moves.
    // `watch` would rebuild the whole `MaterialApp.router` on every
    // registration.
    //
    // Nothing is sent in P4b: `PushTokenSource` answers null until P9a wires
    // FCM/APNs. The CADENCE is what ships, and it is load-bearing — see
    // `push_registration_controller.dart`.
    ref.listen(pushRegistrationProvider, (_, _) {});

    return MaterialApp.router(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: lumenTheme(Brightness.light),
      darkTheme: lumenTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(goRouterProvider),
    );
  }
}

// ---------------------------------------------------------------------------
// LumenRootScope
// ---------------------------------------------------------------------------

/// The one `ProviderScope` the app ever creates, and therefore the one place
/// container-wide policy can be set (P4b-T26).
///
/// It exists as a named production widget rather than an inline `ProviderScope`
/// in `main()` for one reason: `main()` cannot be mounted in a widget test (it
/// initialises Hive and calls `runApp`), so an inline scope's `retry:` argument
/// could only ever be checked by reading the source. This can be pumped, and
/// `provider_retry_policy_test.dart` pumps it.
///
/// [overrides] is a parameter rather than a constant because the root scope's
/// other job is `cacheStoreProvider` dependency injection: the encrypted Hive
/// box is opened by `main()` before the first frame and injected here (P3c),
/// and `cacheStoreProvider` throws if it is not overridden at the root — see
/// `core/cache/hive_boot.dart`.
class LumenRootScope extends StatelessWidget {
  const LumenRootScope({
    required this.overrides,
    required this.child,
    super.key,
  });

  /// Root-scope dependency injection — today, `cacheStoreProvider`.
  final List<Override> overrides;

  /// The app below the scope; in production, [LumenApp].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      // The app-wide answer to riverpod's automatic retry. Without it a
      // failed read is rebuilt ten times over ~38 s while every screen shows
      // a spinner instead of its error body — see [lumenRetry] for the full
      // mechanism and for why nothing at all is retryable.
      retry: lumenRetry,
      overrides: overrides,
      child: child,
    );
  }
}
