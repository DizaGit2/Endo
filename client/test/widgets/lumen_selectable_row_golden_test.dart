import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

import '../support/harness.dart';

/// Both shipped geometries in both states, stacked so one image proves the
/// promotion re-spaced neither screen: screen 5's `.g` row (14/12 padding,
/// radius 12, a 32 px glyph circle) and screen 4's tighter `.opt` row (12/11,
/// radius 10, a 14 px radio dot).
///
/// `obscureText: true` means the image never shows the copy, so what it pins is
/// exactly what this widget owns — box size, corner radius, fill and outline.
Widget _rows(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  Widget goalRow({required bool selected, bool enabled = true}) =>
      LumenSelectableRow(
        selected: selected,
        enabled: enabled,
        onTap: () {},
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.accent : c.surface,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: selected ? c.surface : c.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Manage symptoms',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected ? c.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Find pain & flare patterns',
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget statusRow({required bool selected}) => LumenSelectableRow(
    selected: selected,
    onTap: () {},
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    borderRadius: 10,
    child: Row(
      children: <Widget>[
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? c.accent : null,
            border: Border.all(
              color: selected ? c.accent : c.border,
              width: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Diagnosed',
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? c.accent : c.ink,
          ),
        ),
      ],
    ),
  );

  return ColoredBox(
    color: c.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LumenSectionLabel('Screen 5 row'),
          const SizedBox(height: 8),
          goalRow(selected: true),
          const SizedBox(height: 8),
          goalRow(selected: false),
          const SizedBox(height: 8),
          goalRow(selected: false, enabled: false),
          const SizedBox(height: 24),
          const LumenSectionLabel('Screen 4 row'),
          const SizedBox(height: 8),
          statusRow(selected: true),
          const SizedBox(height: 6),
          statusRow(selected: false),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenSelectableRow',
    fileName: 'lumen_selectable_row',
    build: (brightness) =>
        goldenApp(home: _rows(brightness), brightness: brightness),
  );
}
