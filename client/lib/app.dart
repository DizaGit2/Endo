import 'package:flutter/material.dart';
import 'core/theme/lumen_theme.dart';
import 'features/onboarding/presentation/welcome_screen.dart';

/// Root application widget for Lumen.
///
/// Wires [MaterialApp] with the light and dark [ThemeData] built from design
/// tokens, respecting the system theme mode.
///
/// Home is [WelcomeScreen] — the first screen of the onboarding flow (T7/P3a).
/// Navigation between screens is wired in P3b.
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
      home: const WelcomeScreen(),
    );
  }
}
