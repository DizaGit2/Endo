import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

import '../support/harness.dart';

/// Both states side by side, then a wrapped row of several — the shape that
/// actually varies between selection states is the fill/outline/text colour
/// triple (see the class doc for the AA-contrast finding those tokens carry),
/// and a single chip cannot prove that; two side by side, at the SAME label
/// width, can.
///
/// `obscureText: true` means the image never shows which glyphs were drawn
/// (see `golden_app.dart` rule 6), so what this pins is geometry, fill,
/// outline and — because rule 7 also applies — nothing about text colour
/// beyond what a widget test already asserts token-for-token in
/// `lumen_selectable_chip_test.dart`.
Widget _chips(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  return ColoredBox(
    color: c.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LumenSectionLabel('Both states'),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LumenSelectableChip(
                label: 'Unselected',
                selected: false,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              LumenSelectableChip(
                label: 'Selected',
                selected: true,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 24),
          const LumenSectionLabel('A wrapped row'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              LumenSelectableChip(
                label: 'Bloating',
                selected: true,
                onTap: () {},
              ),
              LumenSelectableChip(
                label: 'Nausea',
                selected: false,
                onTap: () {},
              ),
              LumenSelectableChip(
                label: 'Fatigue',
                selected: false,
                onTap: () {},
              ),
              LumenSelectableChip(
                label: 'Cramping',
                selected: true,
                onTap: () {},
              ),
              LumenSelectableChip(
                label: 'Headache',
                selected: false,
                onTap: () {},
              ),
              LumenSelectableChip(
                label: 'Disabled',
                selected: false,
                enabled: false,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenSelectableChip',
    fileName: 'lumen_selectable_chip',
    build: (brightness) =>
        goldenApp(home: _chips(brightness), brightness: brightness),
  );
}
