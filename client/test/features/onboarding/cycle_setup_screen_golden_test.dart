import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/features/onboarding/presentation/cycle_setup_screen.dart';

import '../../support/harness.dart';

/// A controller pinned to one settled form — no reads, so nothing animates.
///
/// Rule 5 of `golden_app.dart`: never golden a loading state. The real
/// controller's `build()` starts two reads, and `pumpBeforeTest` would settle
/// forever against the spinner they put on screen.
class _SettledForm extends CycleSetupController {
  _SettledForm(this.form);

  final CycleSetupForm form;

  @override
  AsyncValue<CycleSetupForm> build() => AsyncValue<CycleSetupForm>.data(form);
}

void main() {
  // The mockup's own state: April 2026 with the 6th chosen, 28 days, Somewhat.
  // `today` is the 20th, so the last ten cells are drawn as unchoosable — the
  // one piece of this screen's state that comes from neither the user nor a
  // stored answer.
  final form = CycleSetupForm(
    answers: CycleAnswers(
      lastPeriodStart: Date(2026, 4, 6),
      avgCycleLengthDays: 28,
      regularity: CycleRegularity.somewhat,
    ),
    saved: const CycleAnswers(),
    visibleMonth: DateTime(2026, 4),
    today: Date(2026, 4, 20),
  );

  goldenTestLightAndDark(
    subject: 'CycleSetupScreen',
    fileName: 'cycle_setup_screen',
    build: (brightness) => goldenApp(
      // The frame the shell puts around a step body — the shell's own insets
      // and its own step slot, not a copy of them, so this pair cannot go on
      // photographing a layout the app has stopped drawing. It leaves out the
      // eyebrow, the dots and the back affordance, which T8 already goldens.
      home: onboardingStepHost(const CycleSetupScreen()),
      brightness: brightness,
      overrides: [
        // Pinned: without it the month header and the week's first column
        // would follow whichever machine ran the suite.
        deviceLocaleProvider.overrideWithValue('es-ES'),
        cycleSetupControllerProvider.overrideWith(() => _SettledForm(form)),
      ],
    ),
  );
}
