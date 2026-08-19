import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
