import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

import '../support/harness.dart';

/// The band as screens 8/10/11/14 will show it: in the place the mockups draw
/// a live "Luteal · Day 22" readout.
Widget _band(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ColoredBox(
    color: c.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const LumenSectionLabel('Today', fontSize: 11, letterSpacing: 1.5),
          const SizedBox(height: 4),
          Text(
            'Good morning, Maya',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 14),
          const LumenPhaseUnavailable(reason: kPhaseEngineNotImplemented),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenPhaseUnavailable',
    fileName: 'lumen_phase_unavailable',
    build: (brightness) =>
        goldenApp(home: _band(brightness), brightness: brightness),
  );
}
