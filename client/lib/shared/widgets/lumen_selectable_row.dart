import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// The mockups' selectable row: a token-styled box that reads as ONE button,
/// carries a selected state, and holds whatever the screen draws inside it.
///
/// Promoted at P4b-T5d from two identical private classes — `goals_screen.dart`'s
/// `_GoalTile` and `baseline_screen.dart`'s `_StatusOption`, which were the same
/// `Semantics` over `GestureDetector` over a token-styled `Container` with
/// different padding and radius. T12's seven hormone chips and T13's four
/// reminder toggles would have made four copies.
///
/// ## What it announces, and why it no longer authors a label
///
/// Both originals used `Semantics(label: …, excludeSemantics: true)`. That was
/// a **workaround for a defect in the test guard**, recorded verbatim in
/// `goals_screen.dart`: `expectLabeledButton` read `SemanticsNode.label` — a
/// node's OWN annotation — so the row had to author one. P4b-T5d fixed the
/// matcher to read `getSemanticsData()`, and with the reason gone the
/// workaround is not worth its cost:
///
///  * `excludeSemantics: true` drops **every** descendant node, silently. A
///    badge, a count or a second affordance added later disappears from the
///    tree with nothing to notice it — the failure has no symptom.
///  * An authored label is a second copy of the drawn strings, free to drift
///    from them. `MergeSemantics` makes the announced name **be** the rendered
///    copy: the framework joins sibling labels with a line break, which is the
///    exact string the two originals were hand-assembling.
///
/// So this row is `MergeSemantics` on the outside — the house rule
/// `a11y_guard.dart` already states for an informational row, here over a
/// `Semantics` that adds the button, selected and enabled facts a merge cannot
/// derive. Both migrated call sites announce a byte-identical string; that is
/// pinned in `test/widgets/lumen_selectable_row_semantics_test.dart` and in
/// each screen's own semantics test.
///
/// A descendant added later is therefore **announced** rather than dropped. It
/// joins this row's name, which is loud enough for a test that states the name
/// to catch — the property `excludeSemantics` cannot offer at any price.
///
/// The `onTap` below is on BOTH the `Semantics` and the `GestureDetector`, and
/// that is deliberate twice over. It states the activatable action as an
/// annotation rather than leaving it to whatever gesture widget happens to be
/// the child; and because two configurations whose action bits intersect cannot
/// be folded into one node (`SemanticsConfiguration.isCompatibleWith`,
/// `semantics.dart:6697-6699`), the child keeps a node of its own. So this
/// row's node has an EMPTY own label and carries its name only in
/// `getSemanticsData()` — which is exactly why `a11y_guard.dart`'s matchers had
/// to be fixed before this widget could exist.
///
/// (That is the CONFLICT mechanism. A descendant can also keep its own node by
/// declaring itself a boundary — `MergeSemantics`, `Semantics(container: true)`
/// — which sets `config.isSemanticBoundary` (`object.dart:4929`) and never
/// reaches `isCompatibleWith`. Two mechanisms, one observable effect.)
///
/// ## Geometry belongs to the caller
///
/// [padding] and [borderRadius] default to screen 5's numbers and screen 4
/// passes its own. They are parameters rather than one averaged constant
/// because the mockups' absolute sizes are this phase's fidelity bar: a shared
/// widget that quietly re-spaced two shipped screens would be the opposite of a
/// refactor.
///
/// Colours are not parameters. Selected/unselected is the same token pair on
/// every mockup that draws this row (`accentSoft`/`input` fill,
/// `accent`/`border` outline), and a row that let a caller pick would let one
/// screen drift.
class LumenSelectableRow extends StatelessWidget {
  const LumenSelectableRow({
    required this.selected,
    required this.onTap,
    required this.child,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.borderRadius = 12,
    super.key,
  });

  /// Whether this row is the/an answer currently chosen.
  ///
  /// Drawn as the accent fill and outline, and announced as
  /// `SemanticsFlag.isSelected` — the flag a screen reader turns into "selected".
  final bool selected;

  /// Invoked on tap, and on an assistive technology's "activate" gesture.
  ///
  /// The row is a toggle or a radio depending on what the caller does with it;
  /// this widget only reports the tap.
  final VoidCallback onTap;

  /// The row's content — the caller's `Row` of glyph, title and description.
  final Widget child;

  /// False while the answer cannot be changed (a save in flight, typically).
  ///
  /// A disabled row announces itself as disabled and offers no tap action,
  /// rather than staying a button that silently does nothing.
  final bool enabled;

  /// The box's inner padding. Defaults to screen 5's `.g` row.
  final EdgeInsetsGeometry padding;

  /// The box's corner radius, in logical pixels. Defaults to screen 5's.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final VoidCallback? tap = enabled ? onTap : null;

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        onTap: tap,
        child: GestureDetector(
          onTap: tap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : c.input,
              border: Border.all(color: selected ? c.accent : c.border),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
