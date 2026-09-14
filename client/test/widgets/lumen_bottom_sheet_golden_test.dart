import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

import '../support/harness.dart';

/// Screen 9's sheet, reproduced from shared widgets only: the scrim over a
/// dimmed page, the sheet's top-only corners and grab handle, and the pain
/// scale that will sit in it.
///
/// The sheet is composed here rather than opened through
/// [showLumenBottomSheet] because a golden's `builder:` has no `WidgetTester`
/// and therefore cannot drive a route. What it photographs is the same
/// [LumenBottomSheet] the modal route wraps its content in.
Widget _sheetOverPage(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return Stack(
    fit: StackFit.expand,
    children: [
      // The dimmed page behind the scrim.
      ColoredBox(
        color: c.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 44, 22, 0),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              'Good morning, Maya',
              style: TextStyle(fontSize: 18, color: c.ink),
            ),
          ),
        ),
      ),
      ColoredBox(color: scrimFor(brightness)),
      Align(
        alignment: Alignment.bottomCenter,
        child: LumenBottomSheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const LumenSectionLabel('Daily check-in'),
              const SizedBox(height: 4),
              Text(
                'How\'s today?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '15 seconds. Add detail later.',
                style: TextStyle(fontSize: 11, color: c.muted),
              ),
              const SizedBox(height: 18),
              const LumenSectionLabel('Pain level'),
              const SizedBox(height: 8),
              LumenIntensityScale(
                value: 3,
                semanticsLabel: 'Pain level',
                onChanged: (_) {},
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {},
                child: const Text('Save check-in'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenBottomSheet',
    fileName: 'lumen_bottom_sheet',
    build: (brightness) =>
        goldenApp(home: _sheetOverPage(brightness), brightness: brightness),
  );
}
