import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';

import '../support/harness.dart';

/// The whole-surface failure state, filling the frame the way it does when a
/// screen has nothing else to show — which is the difference from
/// `LumenErrorBanner` and the reason both goldens exist.
Widget _surface(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ColoredBox(
    color: c.bg,
    child: LumenErrorRetry(
      message: 'Something went wrong. Please try again.',
      onRetry: () {},
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenErrorRetry',
    fileName: 'lumen_error_retry',
    build: (brightness) =>
        goldenApp(home: _surface(brightness), brightness: brightness),
  );
}
