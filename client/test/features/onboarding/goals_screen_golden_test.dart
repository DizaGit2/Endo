import 'package:lumen/features/onboarding/application/goals_controller.dart';
import 'package:lumen/features/onboarding/presentation/goals_screen.dart';

import '../../support/harness.dart';

/// A controller pinned to one settled form.
///
/// Rule 5 of `golden_app.dart`: never golden a loading state. This screen has
/// no loading state to golden — it makes no read of its own — but the real
/// controller seeds itself from `onboardingFlowControllerProvider`, and pinning
/// the form is cheaper and more legible than overriding the whole flow to get
/// the state below.
class _SettledForm extends GoalsController {
  _SettledForm(this.form);

  final GoalsForm form;

  @override
  GoalsForm build() => form;
}

void main() {
  // The mockup's own state, and the D-14 seed: the first two goals ON, the
  // other three off (`Screens/screen_05_goals.html`'s two `.g.on` rows).
  final form = GoalsForm(
    goals: <GoalChoice>[
      for (final GoalOption option in GoalOption.values)
        GoalChoice(code: option.wireName, selected: option.defaultSelected),
    ],
  );

  goldenTestLightAndDark(
    subject: 'GoalsScreen',
    fileName: 'goals_screen',
    build: (brightness) => goldenApp(
      // The frame the shell puts around a step body — the shell's own insets
      // and its own step slot, not a copy of them, so this pair cannot go on
      // photographing a layout the app has stopped drawing. It leaves out the
      // eyebrow, the dots and the back affordance, which T8 already goldens.
      home: onboardingStepHost(const GoalsScreen()),
      brightness: brightness,
      overrides: [
        goalsControllerProvider.overrideWith(() => _SettledForm(form)),
      ],
    ),
  );
}
