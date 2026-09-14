import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';

import '../../support/harness.dart';

void main() {
  goldenTestLightAndDark(
    subject: 'WelcomeScreen',
    fileName: 'welcome_screen',
    build: (brightness) =>
        goldenApp(home: const WelcomeScreen(), brightness: brightness),
  );
}
