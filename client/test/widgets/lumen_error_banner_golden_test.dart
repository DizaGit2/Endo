import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';

import '../support/harness.dart';

/// The banner where screens put it: under the form it is complaining about,
/// above the button the user is about to press again.
///
/// Two lengths, because the banner is width-filling and its wrapping is the
/// part a token change would break first.
Widget _banner(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ColoredBox(
    color: c.bg,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const LumenErrorBanner(message: 'That email is already registered.'),
          const SizedBox(height: 14),
          const LumenErrorBanner(
            message:
                'We could not save your check-in. You are offline, so it will '
                'be sent when you are back on a connection.',
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () {}, child: const Text('Continue')),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenErrorBanner',
    fileName: 'lumen_error_banner',
    build: (brightness) =>
        goldenApp(home: _banner(brightness), brightness: brightness),
  );
}
