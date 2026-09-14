import 'package:lumen/features/shell/presentation/tab_placeholder_screen.dart';

import '../../support/harness.dart';

void main() {
  goldenTestLightAndDark(
    subject: 'TabPlaceholderScreen',
    fileName: 'tab_placeholder_screen',
    build: (brightness) => goldenApp(
      home: const TabPlaceholderScreen(heading: 'Hormones aren\'t here yet'),
      brightness: brightness,
    ),
  );
}
