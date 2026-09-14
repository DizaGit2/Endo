import 'package:lumen/features/onboarding/application/hormones_controller.dart';
import 'package:lumen/features/onboarding/presentation/hormones_screen.dart';

import '../../support/harness.dart';

/// A controller pinned to one settled form.
///
/// Rule 5 of `golden_app.dart`: never golden a loading state. This screen has
/// no loading state to golden — it makes no read of its own — but the real
/// controller seeds itself from `onboardingFlowControllerProvider`, and pinning
/// the form is cheaper and more legible than overriding the whole flow to get
/// the state below.
class _SettledForm extends HormonesController {
  _SettledForm(this.form);

  final HormonesForm form;

  @override
  HormonesForm build() => form;
}

void main() {
  // The mockup's own state, and the D-14 seed: all seven ON
  // (`Screens/screen_06_hormones.html`, where every `.r` carries `.on`).
  final form = HormonesForm(
    hormones: <HormoneChoice>[
      for (final HormoneOption option in HormoneOption.values)
        HormoneChoice(code: option.wireName, charted: option.defaultCharted),
    ],
  );

  goldenTestLightAndDark(
    subject: 'HormonesScreen',
    fileName: 'hormones_screen',
    build: (brightness) => goldenApp(
      // The frame the shell puts around a step body — the shell's own insets
      // and its own step slot, not a copy of them, so this pair cannot go on
      // photographing a layout the app has stopped drawing. It leaves out the
      // eyebrow, the dots and the back affordance, which T8 already goldens.
      home: onboardingStepHost(const HormonesScreen()),
      brightness: brightness,
      overrides: [
        hormonesControllerProvider.overrideWith(() => _SettledForm(form)),
      ],
    ),
  );
}
