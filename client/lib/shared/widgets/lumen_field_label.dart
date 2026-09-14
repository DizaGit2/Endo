import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// The mockups' `.lb` field label — uppercased by presentation, announced in
/// sentence case.
///
/// The split is P4b-T8's lesson: an all-caps run is spelled out letter by
/// letter by many screen readers, so what is drawn and what is announced are
/// deliberately different strings.
///
/// Promoted from the `_FieldLabel` that existed **twice** (P4b-T5c) — verbatim
/// in `cycle_setup_screen.dart` (screen 3) and, after P4b-T10 added
/// [announce], in a strictly more capable form in `baseline_screen.dart`
/// (screen 4). Promoting the more capable copy is what lets screens 5-7 be
/// written against this class instead of adding three more.
///
/// **Do not confuse it with `account_screen.dart:285-297`, which still declares
/// a private class of the same name and is a different widget**: screen 2's
/// `_FieldLabel` draws sentence case (no `toUpperCase()`) at `fontSize: 12`,
/// takes a required `color` instead of reading the token, and carries no
/// `Semantics` at all. It was NOT promoted here and this class does not
/// replace it. If you arrived by grepping `_FieldLabel`, that is the other one.
///
/// CSS equivalent: `text-transform: uppercase; letter-spacing: .5px;
/// color: var(--mut); font-size: 11px; font-weight: 500`.
///
/// Props:
/// - [text] — written in sentence case, drawn uppercased.
/// - [announce] — whether a screen reader hears the label as a node of its
///   own. It changes **nothing** about what is painted.
class LumenFieldLabel extends StatelessWidget {
  const LumenFieldLabel(this.text, {this.announce = true, super.key});

  /// The label, in sentence case. [build] uppercases it for the reader's eyes
  /// and announces this string unchanged.
  final String text;

  /// Whether a screen reader hears this label as a node of its own.
  ///
  /// Leave it true — that is the case for a label naming something that would
  /// otherwise have no name (screen 3's chip rows, screen 4's three status
  /// buttons), and it is what every screen 3 call site relies on.
  ///
  /// Pass false only for a label whose CONTROL already carries the same name:
  /// a `LumenInputField` takes a required `label`, so announcing the caption
  /// above it puts a second, unassociated "Height" in the reading order right
  /// before the field that is actually called Height — noise rather than help.
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final drawn = Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: c.muted,
        letterSpacing: 0.5,
      ),
    );

    if (!announce) return ExcludeSemantics(child: drawn);

    return Semantics(label: text, excludeSemantics: true, child: drawn);
  }
}
