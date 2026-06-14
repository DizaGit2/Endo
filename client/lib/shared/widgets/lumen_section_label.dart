import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// A reusable section-label widget that renders its text uppercased with the
/// appropriate letter-spacing and muted color from the Lumen design tokens.
///
/// CSS equivalent: `text-transform: uppercase; letter-spacing: 1px;
/// color: var(--sg); font-size: 10–11px; font-weight: 500`.
///
/// Usage:
/// ```dart
/// const LumenSectionLabel('App lock'),
/// ```
class LumenSectionLabel extends StatelessWidget {
  const LumenSectionLabel(
    this.text, {
    super.key,
    this.letterSpacing = 1.0,
    this.fontSize = 10.0,
  });

  final String text;
  final double letterSpacing;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: c.sage,
        letterSpacing: letterSpacing,
      ),
    );
  }
}
