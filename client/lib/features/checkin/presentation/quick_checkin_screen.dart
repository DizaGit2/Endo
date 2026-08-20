// Screen 9 — the quick check-in (P4b-T18, the first client WRITE of the
// logging half).
//
// A bottom sheet over the dashboard (`showLumenBottomSheet`, opened by
// `dashboard_screen.dart`'s Mood tile). `POST /checkin/quick` has no clear
// affordance — nothing written here can ever be removed by the user, on any
// screen, in any later phase — so this file is built against the
// anti-fabrication rules in `quick_checkin_controller.dart`'s own header, not
// merely against the mockup. Read that file first.
//
// Cut from the mockup, and why:
//  * `+ Add details` — its destination (screen 12) does not exist until T20,
//    and R-20 forbids shipping an affordance without one. T20 ships the
//    button together with screen 12 and R-13's save-first behaviour.
//  * the mockup's 0-9 pain row — D-08 corrects it to 0-10 (eleven stops);
//    see `LumenIntensityScale`.
//  * the mockup's "Luteal · Day 22" text dimmed behind the sheet — that is
//    the DASHBOARD's own hero content, cut at T17 (no phase engine in P4a);
//    this sheet draws no dimmed-page content of its own.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/checkin/application/quick_checkin_controller.dart';
import 'package:lumen/shared/mood_labels.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

/// The retry/save affordance's label while a previous attempt failed.
///
/// `expectRetryReissuesOneRequest` (`test/support/retry_trap.dart`) locates a
/// write screen's retry control by exactly this text or `'Retry'` — a P4b
/// exit criterion for every write screen, this one included
/// (`lumen-build.md:847,:907`). The CTA becomes this label rather than
/// gaining a second button beside "Save check-in": the same control that
/// tried and failed is what tries again, so there is exactly one place a
/// second, duplicate tap could come from, and the retry trap's "exactly one
/// request" assertion is meaningful against it.
const String kQuickCheckinRetryLabel = 'Try again';

/// Screen 9's content, hosted inside a [LumenBottomSheet] by
/// `showLumenBottomSheet`. Not a route — it is a modal, opened from the
/// dashboard's Mood tile.
class QuickCheckinScreen extends ConsumerWidget {
  const QuickCheckinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final form = ref.watch(quickCheckinControllerProvider);
    final controller = ref.read(quickCheckinControllerProvider.notifier);
    final bannerMessage = _bannerMessage(form.failure);

    // Fix round 1, I-3. `canPop: !form.submitting` blocks the scrim tap AND
    // the system/predictive back gesture while a write is in flight — both
    // route through `Navigator.maybePop`, which consults this freshly on
    // every attempt (`showLumenBottomSheet`'s own dartdoc has the measured
    // mechanism). Drag-to-dismiss is closed a DIFFERENT way, at the call
    // site (`dashboard_screen.dart`'s `enableDrag: false`) — PopScope cannot
    // reach it; see the same dartdoc for why. Before this fix, dismissing
    // the sheet mid-submit let the write commit while the dashboard kept
    // rendering the pre-write pain/mood — including the "↓ vs yesterday"
    // arithmetic — for the rest of the session, because `submit()`'s own
    // `!ref.mounted` guard (correctly) returns before `_refreshDependents()`
    // once the controller is gone.
    return PopScope(
      canPop: !form.submitting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const LumenSectionLabel('Daily check-in'),
          const SizedBox(height: 4),
          Text(
            "How's today?",
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
          // announce: false — LumenIntensityScale carries its OWN
          // semanticsLabel ('Pain level') on the control below, so an
          // announced caption here would be a second, duplicate "Pain level"
          // in the reading order.
          const LumenFieldLabel('Pain level', announce: false),
          const SizedBox(height: 8),
          LumenIntensityScale(
            value: form.pain,
            enabled: !form.submitting,
            semanticsLabel: 'Pain level',
            onChanged: controller.setPain,
          ),
          const SizedBox(height: 18),
          // announce: true (default) — no single control below carries "Mood"
          // as its own name; each tile announces its OWN mood word instead.
          const LumenFieldLabel('Mood'),
          const SizedBox(height: 8),
          _MoodGrid(
            selected: form.mood,
            enabled: !form.submitting,
            onSelect: controller.setMood,
          ),
          const SizedBox(height: 18),
          if (bannerMessage != null) ...[
            LumenErrorBanner(message: bannerMessage),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (!form.canSubmit || form.submitting)
                  ? null
                  : () async {
                      final saved = await controller.submit();
                      if (saved && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                elevation: 0,
              ),
              child: form.submitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.surface,
                        semanticsLabel: 'Loading',
                      ),
                    )
                  : Text(
                      form.failure != null
                          ? kQuickCheckinRetryLabel
                          : 'Save check-in',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the banner above the CTA says, or null when there is nothing wrong.
///
/// The **write** precedent (`goals_screen.dart:228-234`), not the read-failure
/// generic-copy rule: this endpoint's only actionable string is the
/// `request`-keyed cross-field message (`at least one of pain or mood is
/// required`), and suppressing it in favour of generic copy would hide the
/// one thing the user could act on.
String? _bannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    return crossField.isEmpty ? failure.message : crossField.first;
  }
  return failure.message;
}

// ---------------------------------------------------------------------------
// The mood grid
// ---------------------------------------------------------------------------

/// The mockup's `.moods` 4-column grid, built from [LumenSelectableRow] —
/// its own dartdoc names chip-grids as the reuse it was promoted for, and
/// four production call sites already exist. [AspectRatio] at 1, the same
/// precedent `cycle_calendar_screen.dart:391-392` uses for its own square
/// tiles.
class _MoodGrid extends StatelessWidget {
  const _MoodGrid({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  /// The WIRE ordinal (`1..4`) currently chosen, or null.
  final int? selected;
  final bool enabled;

  /// Called with the WIRE ordinal of the tapped tile — `index + 1`, never a
  /// bare list index — or `null` when the user tapped the ALREADY-selected
  /// tile, the clear gesture (fix round 1, M-2: mirrors
  /// [LumenIntensityScale]'s own clear-to-null tap, so a mistaken mood tap
  /// is reachable, not permanent, the same way a mistaken pain tap is).
  /// Mood is 1-based on the wire (D-08/D-11); pain is 0-based. A grid built
  /// on the list index alone writes `low` (ordinal 1) when the user tapped
  /// `tired` (ordinal 2) — a fabricated value that looks completely real,
  /// and permanent. The `+ 1` below is the whole fix for THAT hazard.
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Row(
      children: [
        for (final (index, label) in kMoodLabels.indexed) ...[
          if (index > 0) const SizedBox(width: 6),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: _MoodTile(
                label: label,
                ordinal: index + 1,
                selected: selected == index + 1,
                enabled: enabled,
                selectedColor: c.accent,
                unselectedColor: c.muted,
                // Tapping the ALREADY-selected tile clears it to `null`
                // (the one gesture that can produce `null`); every other
                // tile still reports its own wire ordinal.
                onTap: () => onSelect(selected == index + 1 ? null : index + 1),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({
    required this.label,
    required this.ordinal,
    required this.selected,
    required this.enabled,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final String label;
  final int ordinal;
  final bool selected;
  final bool enabled;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;

    return LumenSelectableRow(
      selected: selected,
      enabled: enabled,
      onTap: onTap,
      padding: const EdgeInsets.all(4),
      borderRadius: 10,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The mockup's `.mi` glyphs `◔ ◐ ◑ ●` — above U+007F and not on
          // kAllowedNonAsciiGlyphs, so each becomes an Icon
          // (a11y_guard.dart's dingbat rule). Mapped by ROLE — the four
          // tiles are an increasing-positivity mood scale, not four
          // unrelated circle-fill shapes — to Material's own sentiment_*
          // family, which exists for exactly this scale. No `semanticLabel`:
          // MergeSemantics already folds this tile's own [label] Text into
          // its announced name, so a second name on the icon would repeat
          // it (screen 5's `_GoalTile` precedent).
          Icon(_moodGlyph(ordinal), size: 18, color: color),
          const SizedBox(height: 1),
          Text(label, style: TextStyle(fontSize: 9, color: color)),
        ],
      ),
    );
  }
}

/// [ordinal] (`1..4`) -> the sentiment icon for that mood level. An
/// exhaustive-by-construction mapping over the same 4-member scale
/// [kMoodLabels] enumerates, so a fifth mood level would need this function
/// updated deliberately rather than silently falling through.
///
/// **Fix round 1, M-4.** Material's `sentiment_*` family is a FIVE-point
/// valence scale — `very_dissatisfied` / `dissatisfied` / `neutral` /
/// `satisfied` / `very_satisfied` — and the ratified 4-member vocabulary
/// `{low, tired, steady, bright}` (`definitions.md`'s 2026-07-08
/// ratification block) does not make an affect JUDGEMENT about its middle
/// value: "Steady" names a plateau, not a positive one. The first shipped
/// version skipped `sentiment_neutral` and used `sentiment_satisfied` for
/// "Steady" instead, which rendered a value the vocabulary is deliberately
/// silent on as a positive judgement — the same "naming the middle of a
/// scale is clinical inference" rule `LumenIntensityScale`'s own dartdoc
/// states for pain applies here too. `sentiment_satisfied` is skipped
/// instead, not `sentiment_neutral`.
IconData _moodGlyph(int ordinal) => switch (ordinal) {
  1 => Icons.sentiment_very_dissatisfied, // Low    — mockup's ◔
  2 => Icons.sentiment_dissatisfied, // Tired  — mockup's ◐
  3 => Icons.sentiment_neutral, // Steady — mockup's ◑
  4 => Icons.sentiment_very_satisfied, // Bright — mockup's ●
  _ => throw ArgumentError.value(ordinal, 'ordinal', 'must be 1..4'),
};
