import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/features/onboarding/application/baseline_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';

import '../../support/harness.dart';

/// A controller pinned to one settled step — no load, so nothing animates.
///
/// Rule 5 of `golden_app.dart`: never golden a loading state. The real
/// controller's `build()` starts a read, and `pumpBeforeTest` would settle
/// forever against the spinner it puts on screen.
class _SettledFlow extends OnboardingFlowController {
  _SettledFlow(this.step);

  final OnboardingStep step;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: step,
      state: onboardingStateFixture(cycleProvided: true),
    ),
  );
}

/// Screen 4, pinned to a settled form.
///
/// Rule 5 again, one level down: since P4b-T10 the step-4 body reads `GET /me`
/// and `GET /cycle/calendar` on mount, so the shell's own golden would
/// photograph that body's spinner rather than the chrome this pair is about.
class _SettledBaseline extends BaselineController {
  @override
  AsyncValue<BaselineForm> build() => AsyncValue<BaselineForm>.data(
    BaselineForm(
      answers: const BaselineAnswers(),
      saved: const BaselineAnswers(),
      today: Date(2026, 4, 20),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'OnboardingShellScreen',
    fileName: 'onboarding_shell_screen',
    // Step 4, deliberately: it is the only position that exercises the whole
    // chrome at once — a back affordance (step 3 has none), an eyebrow with a
    // title, and a dot row whose active pill is neither at the start nor at
    // the end.
    build: (brightness) => goldenApp(
      home: const OnboardingShellScreen(),
      brightness: brightness,
      overrides: [
        authStatusProvider.overrideWith(
          () => FakeAuthController(AuthStatus.unauthenticated),
        ),
        onboardingFlowControllerProvider.overrideWith(
          () => _SettledFlow(OnboardingStep.baseline),
        ),
        baselineControllerProvider.overrideWith(_SettledBaseline.new),
      ],
    ),
  );
}
