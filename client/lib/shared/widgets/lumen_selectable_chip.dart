import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// Screen 12's selectable chip: a bare-label pill, two states, colour-only
/// selection.
///
/// Built ahead of T20 (P4b-T19c) so screen 12's own commit does not debut two
/// new shared widgets alongside a screen. T20 assembles rows of these — the
/// four symptom/region/pain-type/trigger rows — and decides single- vs
/// multi-select, vocabulary order and progressive disclosure (R-14); none of
/// that is this widget's concern. See "Scope" below.
///
/// ## This is NOT a promotion of either private `_Chip`
///
/// The plan's T19c line claimed the app had "no selectable chip". Half of
/// that was wrong: a survey found TWO private classes both named `_Chip`, and
/// only one of them is even selectable.
///
/// | where | selectable? | radius | padding | font | unselected | selected |
/// |---|---|---|---|---|---|---|
/// | `day_detail_screen.dart`'s `_Chip` | **no** — `DecoratedBox`, no tap, no `Semantics` at all | 7 | 8×3 | 9 | `input`/`border`/`ink` | — |
/// | `cycle_setup_screen.dart` (~:563-609) | **yes** | 10 | 6×10 | 12 | `input`/`border`/`ink` | `accentSoft`/`accent`/`accent`, weight w500 |
///
/// **Controller ruling — neither was migrated, on purpose.** The
/// `day_detail_screen.dart` chip is read-only and a different component
/// entirely ("They are not the same widget and `_Chip` must not be lifted
/// as-is"). The `cycle_setup_screen.dart` chip IS selectable but at a
/// different radius, font size and unselected text colour, WITH a weight
/// change on select, laid out full-width inside an `Expanded`, and belongs to
/// a shipped screen — absorbing it would re-space screen 3 and force its
/// goldens to regenerate inside what should be a widget-only commit, which is
/// the entanglement T19c exists to prevent. This widget is built fresh, at
/// screen 12's own measured geometry, and both private `_Chip`s are left
/// alone.
///
/// `cycle_setup_screen.dart`'s chip also authors its label via
/// `Semantics(label: announced ?? text, excludeSemantics: true)`. That is the
/// OBSOLETE pattern — see `lumen_selectable_row.dart:13-39` for why it existed
/// (a workaround for a since-fixed test-guard defect that read a node's own
/// label instead of the merged one) and why it is not worth its cost anymore
/// (a descendant added later would vanish from the tree with no symptom).
/// This chip uses the current house pattern instead: [MergeSemantics] over a
/// [Semantics] that states button/selected/enabled, with the NAME arriving
/// from the child [Text] through the merge.
///
/// ## Geometry — `Screens/screen_12_symptom_form.html`, measured
///
/// Both states: 11 px label, 6 px vertical / 10 px horizontal padding, 14 px
/// corner radius, 1 px border. Selection changes ONLY the three colours:
///
/// | | background | border | text |
/// |---|---|---|---|
/// | unselected | [LumenColors.input] | [LumenColors.border] | **[LumenColors.muted]** |
/// | selected | [LumenColors.accentSoft] | [LumenColors.accent] | [LumenColors.accent] |
///
/// The unselected text is **muted, not ink** — where both private `_Chip`s
/// differ from the mockup. There is no font-weight change on selection either
/// (`cycle_setup_screen.dart`'s chip has one; it is not this widget's model),
/// and no icon or check mark is drawn — every chip is a bare label, matching
/// the mockup exactly.
///
/// Colours are read from the ambient theme
/// (`Theme.of(context).extension<LumenColors>()!`), never passed in.
/// `lumen_selectable_row.dart:64-67` states the rule this widget follows: a
/// widget that lets a caller pick colours lets one screen drift.
///
/// ## The contrast finding — recorded, not patched
///
/// Computed independently for this task (`node`, the standard WCAG relative-
/// luminance formula) and cross-checked against the phase survey's own
/// figures — they agree:
///
/// | state | light | dark |
/// |---|---|---|
/// | unselected — muted on input | `#8A6F5E` on `#FAF6EF` = **4.32:1** — FAILS AA (4.5:1) | `#A99BB8` on `#1F1428` = 6.79:1 — passes |
/// | selected — accent on accentSoft | `#C25A36` on `#F3D9CC` = **3.25:1** — FAILS AA | `#E8A87C` on `#3A2438` = 6.93:1 — passes |
///
/// **Ruling: ship the tokens as specified; do not deviate.** Precedent:
/// `lumen_intensity_scale.dart`'s `_Stop.build` recorded an identical
/// light-theme failure rather than patching it, and the phase already carries
/// a standing entry that the light-theme accent token pair "needs a design
/// decision, not an implementer's judgement." Changing a design-system colour
/// inside a widget commit is an implementer making a design decision.
///
/// Selection is also signalled by **colour alone** — no icon, no weight
/// change — which compounds the contrast failure for colour-blind users on
/// top of low-vision ones. Same treatment: recorded here, not patched with an
/// invented second cue.
///
/// ## Scope — what this widget deliberately does NOT do
///
/// R-12 requires every selected RELATED chip on screen 12 to carry its own
/// required 0-10 intensity, and R-14 requires frozen vocabulary order with
/// progressive disclosure. Neither belongs here. [LumenIntensityScale]
/// already has R-12's tri-state shape (`ValueChanged<int?>`, tap-to-clear)
/// and is ~55 px tall and full-width — structurally incapable of living
/// inside an 11 px pill. The chip+scale composite is *screen-level assembly*:
/// T20 renders a chip, and renders a scale near it when that chip is
/// selected. Two separate widgets, combined by their caller — never merged
/// into one.
///
/// This chip is a plain two-state toggle that reports taps. Whether a row is
/// single-select or multi-select, what order chips render in, and whether
/// some are hidden behind a disclosure affordance are all decided by the
/// caller — the same discipline `lumen_selectable_row.dart:94-96` states for
/// its own widget: "the row is a toggle or a radio depending on what the
/// caller does with it; this widget only reports the tap."
class LumenSelectableChip extends StatelessWidget {
  const LumenSelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
    this.enabled = true,
  });

  /// The chip's text, rendered as-is. No case transform — that is
  /// [LumenFieldLabel]'s job for the row label above the chips, not this
  /// widget's for the chip text itself.
  final String label;

  /// Whether this chip is the/an answer currently chosen. Unlike
  /// [LumenSelectableRow.selected], this is required and non-nullable: a
  /// chip always has a selection concept, so there is no launcher case to
  /// accommodate.
  final bool selected;

  /// Invoked on tap, and on an assistive technology's "activate" gesture.
  ///
  /// Whether this chip behaves as a toggle or as one option in a single-select
  /// group is entirely the caller's decision; this widget only reports the
  /// tap.
  ///
  /// **`null` means "a tap here would do nothing", and the chip then says
  /// so** — the node drops its tap action and reports itself unavailable,
  /// rather than staying a button whose activation silently does nothing.
  /// Pass it wherever the caller would otherwise have ignored the callback:
  /// the already-selected chip of a single-select row with no deselect
  /// (screen 11's mood row, whose endpoint cannot un-log a mood) is the
  /// shipped case. That is the SAME MECHANISM, not merely the same intent, as
  /// [LumenIntensityScale]'s `allowClear: false` stop — which is the point,
  /// because two controls on one sheet expressing "this gesture is not
  /// offered" two different ways is how one of them ends up lying.
  ///
  /// Still `required`, so no call site drifts into inertness by omission:
  /// passing `null` has to be written down.
  final VoidCallback? onTap;

  /// False while the answer cannot be changed. A disabled chip announces
  /// itself as disabled and offers no tap action, rather than staying a
  /// button that silently does nothing.
  ///
  /// Distinct from a null [onTap] only in intent — "no answer can be changed
  /// right now" vs. "this particular chip's tap is a no-op". The node the two
  /// produce is deliberately identical.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // One value drives BOTH the gesture and the announcement, from either
    // source of "no": a disabled chip, or a chip whose tap the caller would
    // have ignored.
    final VoidCallback? tap = enabled ? onTap : null;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        // The enabled FLAG follows the ACTION, never the parameter. A node
        // that keeps `isButton`, has no tap action and still claims to be
        // enabled is "looks like a button, cannot be activated, never says
        // why" — the same rule `lumen_intensity_scale.dart`'s `_Stop` states
        // for its own selected stop.
        enabled: tap != null,
        onTap: tap,
        child: GestureDetector(
          onTap: tap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : c.input,
              border: Border.all(color: selected ? c.accent : c.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: selected ? c.accent : c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
