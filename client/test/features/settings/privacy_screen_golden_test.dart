import 'package:lumen/features/settings/presentation/privacy_screen.dart';

import '../../support/harness.dart';

void main() {
  goldenTestLightAndDark(
    subject: 'PrivacyScreen',
    fileName: 'privacy_screen',
    build: (brightness) =>
        goldenApp(home: const PrivacyScreen(), brightness: brightness),
  );
}
