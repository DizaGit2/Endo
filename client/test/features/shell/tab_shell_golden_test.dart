import 'package:go_router/go_router.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';

import '../../support/harness.dart';

/// Screen 8, pinned to a settled Fresh view. Parked on the Home branch since
/// P4b-T17 (R-19) means this golden's `initialLocation` renders the real
/// dashboard, not [TabPlaceholderScreen] — a network-backed controller with
/// no override would otherwise reach the real (unoverridden)
/// `cacheStoreProvider`, which throws by design.
class _SettledDashboard extends DashboardController {
  @override
  Future<CacheResult<DashboardView>> build() async => Fresh(
    DashboardView(
      today: DateTime(2026, 4, 20),
      displayName: 'Maya',
      todayPain: null,
      todayMood: null,
      yesterdayPain: null,
      phaseAvailable: null,
      phaseUnavailableReason: null,
    ),
  );
}

/// Renders the REAL shell — the production route table's
/// `StatefulShellRoute.indexedStack` and its `LumenBottomNav` chrome — parked
/// on the Home branch.
///
/// This is the one golden that cannot use `goldenApp(home: …)`: the shell
/// chrome only exists as the builder of a shell route, so the only way to
/// photograph the real thing (rather than a hand-built copy that could drift)
/// is to mount [lumenRoutes] in a router. The redirect is omitted deliberately
/// — auth gating is `app_router_test.dart`'s subject, and pinning providers
/// here would make the image depend on a controller's timing. The dashboard
/// controller override above is the one exception, added when P4b-T17 (R-19)
/// replaced the Home branch's placeholder with a real, network-backed screen:
/// without it this golden would depend on a real read's timing (rule 5 —
/// never golden a loading state), not merely on auth gating.
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
      overrides: [
        dashboardControllerProvider.overrideWith(_SettledDashboard.new),
        greetingTimeOfDayProvider.overrideWithValue('Good morning'),
      ],
    ),
  );
}
