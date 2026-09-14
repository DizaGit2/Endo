import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_step_chrome.dart';

import '../support/harness.dart';

/// The eyebrow at three points in the flow, plus screen 1's overridden form.
///
/// Stacked so one image proves the string CHANGES with `step` and `title` — a
/// chrome that hard-coded either would look right in any single-step golden.
Widget _chrome(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ColoredBox(
    color: c.surface,
    child: const Padding(
      padding: EdgeInsets.fromLTRB(24, 44, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LumenStepChrome(step: 1, totalSteps: 7, lead: 'Lumen'),
          SizedBox(height: 24),
          LumenStepChrome(step: 3, totalSteps: 7, title: 'Cycle'),
          SizedBox(height: 24),
          LumenStepChrome(step: 4, totalSteps: 7, title: 'About you'),
          SizedBox(height: 24),
          LumenStepChrome(step: 7, totalSteps: 7, title: 'Reminders'),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenStepChrome',
    fileName: 'lumen_step_chrome',
    build: (brightness) =>
        goldenApp(home: _chrome(brightness), brightness: brightness),
  );
}
