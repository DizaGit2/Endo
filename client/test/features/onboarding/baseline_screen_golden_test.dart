import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/features/onboarding/application/baseline_controller.dart';
import 'package:lumen/features/onboarding/presentation/baseline_screen.dart';

import '../../support/harness.dart';

/// A controller pinned to one settled form — no reads, so nothing animates.
///
/// Rule 5 of `golden_app.dart`: never golden a loading state. The real
/// controller's `build()` starts two reads, and `pumpBeforeTest` would settle
/// forever against the spinner they put on screen.
class _SettledForm extends BaselineController {
  _SettledForm(this.form);

  final BaselineForm form;

  @override
  AsyncValue<BaselineForm> build() => AsyncValue<BaselineForm>.data(form);
}

void main() {
  // The mockup's own state: a filled-in profile with "Diagnosed" chosen. The
  // date of birth stands where the mockup draws "29 yrs" — the screen collects
  // the date and age is derived from it.
  final form = BaselineForm(
    answers: BaselineAnswers(
      dob: Date(1996, 4, 6),
      heightCm: 165,
      weightKg: 62,
      endoStatus: EndoStatus.diagnosed,
    ),
    saved: const BaselineAnswers(),
    today: Date(2026, 4, 20),
  );

  goldenTestLightAndDark(
    subject: 'BaselineScreen',
    fileName: 'baseline_screen',
    build: (brightness) => goldenApp(
      // The frame the shell puts around a step body — the shell's own insets
      // and its own step slot, not a copy of them, so this pair cannot go on
      // photographing a layout the app has stopped drawing. It leaves out the
      // eyebrow, the dots and the back affordance, which T8 already goldens.
      home: onboardingStepHost(const BaselineScreen()),
      brightness: brightness,
      overrides: [
        // Pinned: without it the decimal separator in the weight field would
        // follow whichever machine ran the suite.
        deviceLocaleProvider.overrideWithValue('es-ES'),
        baselineControllerProvider.overrideWith(() => _SettledForm(form)),
      ],
    ),
  );
}
