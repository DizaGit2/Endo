import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

import '../support/harness.dart';

/// The label at both sizes it ships in — the 10/1.0 default used across
/// settings, and the 11/1.5 variant the dashboard band uses — over the copy it
/// introduces, so the image pins the sage colour and the letter-spaced run
/// rather than a lone word.
Widget _labels(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  Widget section(String label, String body, {double fontSize = 10}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      LumenSectionLabel(
        label,
        fontSize: fontSize,
        letterSpacing: fontSize == 10 ? 1.0 : 1.5,
      ),
      const SizedBox(height: 6),
      Text(body, style: TextStyle(fontSize: 14, color: c.ink)),
    ],
  );

  return ColoredBox(
    color: c.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          section('Today', 'Good morning, Maya', fontSize: 11),
          const SizedBox(height: 22),
          section('App lock', 'Require a passcode to open Lumen'),
          const SizedBox(height: 22),
          section('Data and privacy', 'Export or delete your data'),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenSectionLabel',
    fileName: 'lumen_section_label',
    build: (brightness) =>
        goldenApp(home: _labels(brightness), brightness: brightness),
  );
}
