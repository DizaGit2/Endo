import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_retry_button.dart';

import '../support/harness.dart';

/// Both labels the button ships with — `Try again` (every error surface) and
/// `Retry` (screen 31's network-required body) — beside the primary button it
/// must read as secondary to.
Widget _buttons(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ColoredBox(
    color: c.bg,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LumenRetryButton(label: 'Try again', onPressed: () {}),
          const SizedBox(height: 20),
          LumenRetryButton(label: 'Retry', onPressed: () {}),
          const SizedBox(height: 20),
          FilledButton(onPressed: () {}, child: const Text('Save')),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenRetryButton',
    fileName: 'lumen_retry_button',
    build: (brightness) =>
        goldenApp(home: _buttons(brightness), brightness: brightness),
  );
}
