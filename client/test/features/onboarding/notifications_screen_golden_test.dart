import 'package:lumen/features/onboarding/application/notifications_controller.dart';
import 'package:lumen/features/onboarding/presentation/notifications_screen.dart';

import '../../support/harness.dart';

/// A controller pinned to one settled form.
///
/// Rule 5 of `golden_app.dart`: never golden a loading state. This screen has
/// no loading state to golden — it makes no read of its own — but the real
/// controller seeds itself from `onboardingFlowControllerProvider`, and pinning
/// the form is cheaper and more legible than overriding the whole flow to get
/// the state below.
class _SettledForm extends NotificationsController {
  _SettledForm(this.form);

  final NotificationsForm form;

  @override
  NotificationsForm build() => form;
}

void main() {
  // The mockup's own state, and the onboarding seed: the first two ON, the
  // other two OFF (`Screens/screen_07_notifications.html`, where the first two
  // `.n` carry `.on`). Unlike screen 6's all-ON form this pair photographs BOTH
  // row appearances, which is why the goldens are worth their bytes here.
  final form = NotificationsForm(
    categories: <NotificationChoice>[
      for (final NotificationOption option in NotificationOption.values)
        NotificationChoice(
          code: option.wireName,
          enabled: option.defaultEnabled,
        ),
    ],
  );

  goldenTestLightAndDark(
    subject: 'NotificationsScreen',
    fileName: 'notifications_screen',
    build: (brightness) => goldenApp(
      // The frame the shell puts around a step body — the shell's own insets
      // and its own step slot, not a copy of them, so this pair cannot go on
      // photographing a layout the app has stopped drawing. It leaves out the
      // eyebrow, the dots and the back affordance, which T8 already goldens.
      home: onboardingStepHost(const NotificationsScreen()),
      brightness: brightness,
      overrides: [
        notificationsControllerProvider.overrideWith(() => _SettledForm(form)),
      ],
    ),
  );
}
