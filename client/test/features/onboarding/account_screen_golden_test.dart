import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/features/onboarding/application/account_controller.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';

import '../../support/harness.dart';

/// An idle [AccountController] (`AsyncData<void>`) with no-op actions —
/// goldens only ever photograph the idle state (a spinner never settles).
class _IdleAccountController extends AccountController {
  @override
  Future<void> build() async {}
}

void main() {
  goldenTestLightAndDark(
    subject: 'AccountScreen',
    fileName: 'account_screen',
    build: (brightness) => goldenApp(
      home: const AccountScreen(),
      brightness: brightness,
      overrides: [
        ...lumenOverrides(auth: AuthStatus.unauthenticated),
        accountControllerProvider.overrideWith(_IdleAccountController.new),
      ],
    ),
  );
}
