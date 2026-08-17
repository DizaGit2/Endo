import 'package:go_router/go_router.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';

import '../../support/harness.dart';

/// Renders the REAL shell — the production route table's
/// `StatefulShellRoute.indexedStack` and its `LumenBottomNav` chrome — parked
/// on the Home branch.
///
/// This is the one golden that cannot use `goldenApp(home: …)`: the shell
/// chrome only exists as the builder of a shell route, so the only way to
/// photograph the real thing (rather than a hand-built copy that could drift)
/// is to mount [lumenRoutes] in a router. The redirect is omitted deliberately
/// — auth gating is `app_router_test.dart`'s subject, and pinning providers
/// here would make the image depend on a controller's timing.
void main() {
  goldenTestLightAndDark(
    subject: 'Tab shell',
    fileName: 'tab_shell',
    build: (brightness) => goldenRouterApp(
      routerConfig: GoRouter(
        initialLocation: Routes.home,
        routes: lumenRoutes(),
      ),
      brightness: brightness,
    ),
  );
}
