import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
