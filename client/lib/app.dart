import 'package:flutter/material.dart';
import 'core/theme/lumen_theme.dart';

/// Root application widget for Lumen.
///
/// Wires [MaterialApp] with the light and dark [ThemeData] built from design
/// tokens, respecting the system theme mode.
///
/// Note: the [home] placeholder (a centered "Lumen" text on the theme
/// background) is replaced in T7 / P3b with the real onboarding welcome
/// screen (screen_01).
class LumenApp extends StatelessWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: lumenTheme(Brightness.light),
      darkTheme: lumenTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const _PlaceholderHome(),
    );
  }
}

/// Temporary placeholder home screen — replaced in T7/P3b.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Lumen',
          style: Theme.of(context).textTheme.displaySmall,
        ),
      ),
    );
  }
}
