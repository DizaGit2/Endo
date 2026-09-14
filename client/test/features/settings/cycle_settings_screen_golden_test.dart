// Golden tests for CycleSettingsScreen (screen 32) — light + dark at 390x844.
//
// The controller is pinned to a settled form so the image is deterministic and
// settles (rule 5 of `golden_app.dart`: never golden a loading state).
//
// **The photographed state is the OPENING one**: a saved row, nothing touched,
// so the CTA is disabled with its block reason beside it — which is what the
// user actually sees on arrival, and what makes both R4 halves visible in one
// frame. The two cut items (`First day of week` and the retrain footer) are
// absent here too; their absence is asserted by name in
// `cycle_settings_screen_semantics_test.dart` rather than left to a reader
// noticing a missing box in a PNG.

import 'package:lumen/features/settings/application/cycle_settings_controller.dart';
import 'package:lumen/features/settings/presentation/cycle_settings_screen.dart';

import '../../support/harness.dart';

/// A controller settled on one saved row — no repository, so nothing loads.
///
/// [trackingPaused] / [pauseReason] are supplied **independently** (P4b-T22b),
/// because the two states worth photographing differ in the flag and not in
/// the reason: the default pair is a user who has never paused, and
/// `_PausedCycleSettings` below is the same row with the flag on.
class _SettledCycleSettings extends CycleSettingsController {
  _SettledCycleSettings({this.trackingPaused = false, this.pauseReason});

  final bool trackingPaused;
  final String? pauseReason;

  @override
  Future<CycleSettingsForm> build() async => CycleSettingsForm.seededFrom(
    cycleSettingsFixture(
      avgCycleLengthDays: 29,
      // Set, rather than the null a freshly-onboarded account carries: the
      // number path is the one worth photographing, and `Not set` is pinned
      // by name in the semantics test.
      avgPeriodLengthDays: 5,
      regularity: 'irregular',
      phasePredictionEnabled: true,
      autoDetectPeriodStartEnabled: true,
      showFertilityWindowEnabled: false,
      trackingPaused: trackingPaused,
      pauseReason: pauseReason,
      phasesUnavailable: trackingPaused,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'CycleSettingsScreen',
    fileName: 'cycle_settings_screen',
    build: (brightness) => goldenApp(
      home: const CycleSettingsScreen(),
      brightness: brightness,
      overrides: [
        ...lumenOverrides(),
        cycleSettingsControllerProvider.overrideWith(_SettledCycleSettings.new),
      ],
    ),
  );

  // The PAUSED state (P4b-T22b) — a second pair, because the pause card draws
  // a genuinely different thing in it: the five reason chips are replaced by a
  // read-only reason row, and the CTA relabels. None of that is visible to a
  // semantics assertion beyond its strings, and `_PauseCard`'s decoration is
  // exactly the class of thing T22a's m28 established the goldens are the pin
  // for.
  goldenTestLightAndDark(
    subject: 'CycleSettingsScreen paused',
    fileName: 'cycle_settings_screen_paused',
    build: (brightness) => goldenApp(
      home: const CycleSettingsScreen(),
      brightness: brightness,
      overrides: [
        ...lumenOverrides(),
        cycleSettingsControllerProvider.overrideWith(
          () => _SettledCycleSettings(
            trackingPaused: true,
            pauseReason: 'surgical',
          ),
        ),
      ],
    ),
  );
}
