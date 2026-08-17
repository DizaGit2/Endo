import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// The onboarding step indicator: [count] dots with the one at [activeIndex]
/// drawn as a wide accent pill.
///
/// Promoted from the `_StepDot` that existed **twice, verbatim** — in
/// `welcome_screen.dart` and `account_screen.dart` (P4b-T5). What is promoted
/// is the whole ROW rather than the single dot, because both call sites also
/// hand-rolled the same centred [Row] with the same 6 px gaps, and screens 3-7
/// need that row five more times. Promoting only the dot would have left five
/// copies of the row behind.
///
/// The dot itself stays private ([_StepDot]) for the same reason: there is one
/// arrangement of these dots in the design system, and a second public name
/// with no caller is how the next duplicate starts.
///
/// Props:
/// - [count] — how many steps the flow has (7 for onboarding).
/// - [activeIndex] — zero-based; screen 1 passes 0, screen 2 passes 1.
class LumenStepDots extends StatelessWidget {
  const LumenStepDots({
    required this.count,
    required this.activeIndex,
    super.key,
  });

  /// Total number of steps.
  final int count;

  /// Zero-based index of the step the user is on.
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _StepDot(active: i == activeIndex, color: c.accent, border: c.border),
        ],
      ],
    );
  }
}

/// A single step-indicator dot.
///
/// Active: accent colour, wider (18x6) pill. Inactive: border colour, circle.
class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.active,
    required this.color,
    required this.border,
  });

  final bool active;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? color : border,
        borderRadius: BorderRadius.circular(active ? 3 : 50),
      ),
    );
  }
}
