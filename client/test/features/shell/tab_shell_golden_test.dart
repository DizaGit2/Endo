import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/theme/lumen_theme.dart';

// Phone-frame dimensions matching the design spec.
const _kWidth = 390.0;
const _kHeight = 844.0;

/// Renders the REAL shell — the production route table's
/// `StatefulShellRoute.indexedStack` and its `LumenBottomNav` chrome — parked
/// on the Home branch.
///
/// This is the one golden that cannot use the usual `MaterialApp(home: Screen)`
/// shape: the shell chrome only exists as the builder of a shell route, so the
/// only way to photograph the real thing (rather than a hand-built copy that
/// could drift) is to mount [lumenRoutes] in a router. The redirect is omitted
/// deliberately — auth gating is `app_router_test.dart`'s subject, and pinning
/// providers here would make the image depend on a controller's timing.
Widget _buildApp(Brightness brightness) {
  return SizedBox(
    width: _kWidth,
    height: _kHeight,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(_kWidth, _kHeight)),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: lumenTheme(brightness),
        routerConfig: GoRouter(
          initialLocation: Routes.home,
          routes: lumenRoutes(),
        ),
      ),
    ),
  );
}

void main() {
  goldenTest(
    'Tab shell light theme',
    fileName: 'tab_shell_light',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(name: 'Light', child: _buildApp(Brightness.light)),
      ],
    ),
  );

  goldenTest(
    'Tab shell dark theme',
    fileName: 'tab_shell_dark',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(name: 'Dark', child: _buildApp(Brightness.dark)),
      ],
    ),
  );
}
