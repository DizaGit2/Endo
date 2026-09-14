import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// A reusable section-label widget that renders its text uppercased with the
/// appropriate letter-spacing and muted color from the Lumen design tokens —
/// and announces it in sentence case, as a heading.
///
/// CSS equivalent: `text-transform: uppercase; letter-spacing: 1px;
/// color: var(--sg); font-size: 10–11px; font-weight: 500`.
///
/// **Drawn and announced are deliberately different strings** (B-12, fixed at
/// the PR #4 review hand-back). `text-transform` in CSS leaves the accessible
/// text alone; `toUpperCase()` in Dart does not, and an all-caps run is spelled
/// out letter by letter by many screen readers — "D, A, T, A" for a section
/// called Data, on every one of this widget's twenty-odd call sites. So the
/// uppercasing is applied to the painted [Text] only, and a [Semantics] node
/// carries [text] as written, the same split `LumenFieldLabel` already makes.
///
/// **It is a heading.** A section label is what a section is called, and it is
/// what a screen reader's heading-navigation gesture should land on; without
/// the header flag that gesture skipped every section on every screen.
/// `LumenStepChrome` wraps this widget in a header of its own with
/// `excludeSemantics: true`, so the eyebrow does not become two headings.
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

  /// The label, in sentence case. [build] uppercases it for the reader's eyes
  /// and announces this string unchanged.
  final String text;
  final double letterSpacing;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Semantics(
      header: true,
      label: text,
      // The painted Text would otherwise contribute its own node with the
      // uppercased string — exactly the announcement this widget exists to
      // avoid.
      excludeSemantics: true,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: c.sage,
          letterSpacing: letterSpacing,
        ),
      ),
    );
  }
}
