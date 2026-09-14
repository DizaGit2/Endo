import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

import '../support/harness.dart';

/// The three states the scale can be in, stacked so one image proves they are
/// visually distinct — in particular that `0` (a logged "none today") does not
/// look like `null` (nothing recorded). That is ruling R-12's whole point, and
/// it is the one thing a golden CAN prove here: `obscureText: true` means the
/// image never shows the numerals, only which stop is filled.
Widget _states(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  Widget labelled(String label, int? value) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      LumenSectionLabel(label),
      const SizedBox(height: 8),
      LumenIntensityScale(
        value: value,
        semanticsLabel: 'Pain level',
        onChanged: (_) {},
      ),
    ],
  );

  return ColoredBox(
    color: c.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          labelled('Not recorded', null),
          const SizedBox(height: 24),
          labelled('None today', 0),
          const SizedBox(height: 24),
          labelled('Seven', 7),
          const SizedBox(height: 24),
          labelled('Worst', 10),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenIntensityScale',
    fileName: 'lumen_intensity_scale',
    build: (brightness) =>
        goldenApp(home: _states(brightness), brightness: brightness),
  );
}
