import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';

import '../support/harness.dart';

/// The message where both screens put it — under the control that was
/// rejected — so the image pins the accent colour, the 12 px size and the 6 px
/// gap rather than a lone floating sentence.
///
/// Two lengths: one that fits a line and one that wraps, because the `1.4`
/// line height is only visible on the second.
Widget _messages(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  Widget rejectedField(String value, String message) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Text(value, style: TextStyle(fontSize: 13, color: c.ink)),
      ),
      const SizedBox(height: 6),
      LumenFieldMessage(message),
    ],
  );

  return ColoredBox(
    color: c.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          rejectedField('6/4/2026', 'date is before the earliest allowed date'),
          const SizedBox(height: 18),
          rejectedField(
            '410 cm',
            'height must be a plausible measurement in centimetres, and this '
                'one wraps onto a second line so the line height is part of '
                'the image',
          ),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenFieldMessage',
    fileName: 'lumen_field_message',
    build: (brightness) =>
        goldenApp(home: _messages(brightness), brightness: brightness),
  );
}
