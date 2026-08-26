import 'package:lumen/features/settings/presentation/help_about_screen.dart';

import '../../support/harness.dart';

void main() {
  goldenTestLightAndDark(
    subject: 'HelpAboutScreen',
    fileName: 'help_about_screen',
    build: (brightness) =>
        goldenApp(home: const HelpAboutScreen(), brightness: brightness),
  );
}
