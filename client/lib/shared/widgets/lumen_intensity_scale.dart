import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// The NRS-11 intensity control: eleven stops, `0`-`10`, anchored "None" and
/// "Worst".
///
/// Used by screens 9 (quick check-in), 12 (symptom form) and 13 (body map).
///
/// ## The two rules this widget exists to enforce
///
/// **1. Eleven stops, not ten (D-08).** The backend accepts `0..10` on both
/// `Symptom.IntensityScale` and `CycleDayLog.PainScale`. Screen 9's mockup
/// draws a ten-button `0..9` row; `definitions.md:24` records that as a mockup
/// artifact P4b corrects, so the row here has eleven.
///
/// **2. `0` is a datum; `null` is the absence of one (ruling R-12).** `0` means
/// "none today" and, sent to `POST /checkin/quick`, overwrites a stored `8`.
/// `null` means "not recorded". They are different states and this widget
/// renders them differently: at `0` the first stop is filled, at `null` no stop
/// is. [value] is therefore `int?` and [onChanged] hands back a non-null `int`,
/// so **no caller can tell the two apart with a falsiness test** — which is the
/// bug the ruling exists to prevent, on either side of the wire.
///
/// ## No intermediate labels
///
/// The anchors are fixed constants rather than parameters. There are exactly
/// two labels, "None" and "Worst", and there is deliberately no way to add a
/// third: naming the middle of a pain scale ("moderate", "severe") is clinical
/// inference, it is forbidden here, and a `midAnchor` parameter is all the
/// invitation that decision would need.
///
/// ## Accessibility
///
/// Every stop is its own labelled, selectable button — no drag gesture is
/// involved, so the control is fully operable by tap and by an assistive
/// technology's "activate". The row as a whole additionally carries a
/// [Semantics] label and value plus increase/decrease actions, so a screen
/// reader can read the current value and nudge it without hunting for the
/// right one of eleven targets.
class LumenIntensityScale extends StatelessWidget {
  const LumenIntensityScale({
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
    super.key,
    this.enabled = true,
  });

  /// The lowest selectable value.
  static const int minValue = 0;

  /// The highest selectable value.
  static const int maxValue = 10;

  /// How many stops the row has — eleven, per D-08 (NRS-11).
  static const int stopCount = maxValue - minValue + 1;

  /// The low-end anchor. Not a parameter — see the class doc.
  static const String lowAnchor = 'None';

  /// The high-end anchor. Not a parameter — see the class doc.
  static const String highAnchor = 'Worst';

  /// The logged intensity, or `null` for "not recorded".
  ///
  /// `0` is a real logged value and must never be conflated with `null`.
  final int? value;

  /// Called with the stop the user chose. Always a non-null `int`, including
  /// `0` — so the caller cannot lose the distinction on the way out.
  final ValueChanged<int> onChanged;

  /// What this scale is measuring, for a screen reader — e.g. 'Pain level'.
  /// The visible label above the control is the screen's to render (the
  /// mockups draw it as a separate element), so this is what ties the two
  /// together for someone who cannot see the layout.
  final String semanticsLabel;

  /// Whether the stops accept taps. `false` while a write is in flight.
  final bool enabled;

  /// How a value is announced. `null` is "Not recorded", never "0".
  static String describeValue(int? value) =>
      value == null ? 'Not recorded' : '$value out of $maxValue';

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final current = value;

    // From "not recorded", increasing selects the lowest stop — an explicit
    // user action, not a default. Decreasing from it does nothing: there is no
    // value below "no value", and offering the action would imply there is.
    final next = current == null
        ? minValue
        : (current < maxValue ? current + 1 : null);
    final previous = (current != null && current > minValue)
        ? current - 1
        : null;

    return Semantics(
      container: true,
      label: semanticsLabel,
      value: describeValue(current),
      increasedValue: next == null ? null : describeValue(next),
      decreasedValue: previous == null ? null : describeValue(previous),
      onIncrease: enabled && next != null ? () => onChanged(next) : null,
      onDecrease: enabled && previous != null ? () => onChanged(previous) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var stop = minValue; stop <= maxValue; stop++) ...[
                if (stop > minValue) const SizedBox(width: 4),
                Expanded(
                  child: _Stop(
                    stop: stop,
                    // `current == stop`, never `current != null && current > 0`
                    // or any other shape that could collapse 0 into null.
                    selected: current == stop,
                    onTap: enabled ? () => onChanged(stop) : null,
                    colors: c,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Anchor(lowAnchor, colors: c),
              _Anchor(highAnchor, colors: c),
            ],
          ),
        ],
      ),
    );
  }
}

/// One stop on the row.
///
/// Mockup: `.s{ height:30px; border-radius:7px; background:var(--in);
/// border:1px solid var(--bd); font-size:11px; color:var(--mut); }` and
/// `.s.on{ background:var(--ac); color:#FFFCF7; border-color:var(--ac);
/// font-weight:500; }`.
class _Stop extends StatelessWidget {
  const _Stop({
    required this.stop,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final int stop;
  final bool selected;
  final VoidCallback? onTap;
  final LumenColors colors;

  @override
  Widget build(BuildContext context) {
    // The mockup hard-codes `#FFFCF7` on the selected fill in BOTH themes.
    // In dark that is a near-white label on the light-gold accent `#E8A87C` —
    // 1.99:1, well under any readability bar. `ColorScheme.onPrimary` is the
    // app's already-decided answer to "what reads on the accent" (warm white in
    // light, dark ink in dark) and is what every FilledButton already uses; it
    // takes dark to 6.71:1. It does NOT fix light, where `onPrimary` IS
    // `#FFFCF7` and the 11 px label sits at 4.27:1 on `#C25A36`, under AA's
    // 4.5:1 — that is a design-system-level issue every FilledButton inherits,
    // recorded as a phase-level finding rather than patched here.
    final onAccent = Theme.of(context).colorScheme.onPrimary;

    return Semantics(
      button: true,
      selected: selected,
      label: '$stop',
      container: true,
      excludeSemantics: true,
      // Without this, a disabled stop keeps `isButton` and loses its tap
      // action: a screen reader announces eleven buttons, double-tap does
      // nothing, and nothing says "dimmed". `enabled: false` gives the node
      // the enabled-state flag assistive tech needs to announce it as
      // unavailable.
      enabled: onTap != null,
      // excludeSemantics drops the child's own tap action, so this node needs
      // its own — wired to the SAME callback, never a second closure.
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.accent : colors.input,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? colors.accent : colors.border,
            ),
          ),
          child: Text(
            '$stop',
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? onAccent : colors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the two anchor labels under the row.
class _Anchor extends StatelessWidget {
  const _Anchor(this.text, {required this.colors});

  final String text;
  final LumenColors colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: colors.muted,
      ),
    );
  }
}
