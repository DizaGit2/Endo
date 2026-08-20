// Golden tests for DashboardScreen — light + dark at 390x844 (P4b-T17).
//
// A settled Fresh view with both cards populated (including a genuine
// pain drop, so the "vs yesterday" caption is visible in the image) — never
// golden a loading state (`golden_app.dart` rule 5).

import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';

import '../../support/harness.dart';

class _SettledDashboard extends DashboardController {
  _SettledDashboard(this.view);
  final DashboardView view;

  @override
  Future<CacheResult<DashboardView>> build() async => Fresh(view);
}

void main() {
  // Thursday, April 9, 2026 — the mockup's own date
  // (`Screens/screen_08_dashboard.html:38`) — with a pain drop (3 -> 2) and a
  // mood value, so one golden pair shows every element this screen draws.
  final view = DashboardView(
    today: DateTime(2026, 4, 9),
    displayName: 'Maya',
    todayPain: 2,
    todayMood: 4,
    yesterdayPain: 3,
    // The real P4a envelope (every account answers this today), not null —
    // fix round 1, M5. Renders identically either way (the same neutral
    // copy), but the fixture should say what production actually sends.
    phaseUnavailableReason: kPhaseEngineNotImplemented,
  );

  goldenTestLightAndDark(
    subject: 'DashboardScreen',
    fileName: 'dashboard_screen',
    build: (brightness) => goldenApp(
      home: const DashboardScreen(),
      brightness: brightness,
      overrides: [
        dashboardControllerProvider.overrideWith(() => _SettledDashboard(view)),
        greetingTimeOfDayProvider.overrideWithValue('Good morning'),
      ],
    ),
  );
}
