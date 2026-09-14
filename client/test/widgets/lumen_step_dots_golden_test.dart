import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_step_dots.dart';

import '../support/harness.dart';

/// The onboarding row at three positions in the seven-step flow.
///
/// Stacked so one image proves the pill MOVES with `activeIndex` — a row that
/// hard-coded the first dot would look right in any single-position golden.
Widget _dots(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ColoredBox(
    color: c.bg,
    child: const Padding(
      padding: EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LumenStepDots(count: 7, activeIndex: 0),
          SizedBox(height: 28),
          LumenStepDots(count: 7, activeIndex: 3),
          SizedBox(height: 28),
          LumenStepDots(count: 7, activeIndex: 6),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenStepDots',
    fileName: 'lumen_step_dots',
    build: (brightness) =>
        goldenApp(home: _dots(brightness), brightness: brightness),
  );
}
