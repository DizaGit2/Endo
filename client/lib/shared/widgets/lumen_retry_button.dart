import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// The secondary (outlined) retry affordance.
///
/// Promoted from `profile_screen.dart`'s private `_RetryButton` (P4b-T5),
/// which P4b-T1 had already copied verbatim into `app_router.dart`'s splash
/// gate surface.
///
/// Deliberately a dumb [StatelessWidget] with no Riverpod dependency of its
/// own: `ref.invalidate(...)` happens at the call site, which is what lets one
/// button serve the profile controller, the onboarding-status controller and
/// whatever the P4b screens invalidate. Token colours only —
/// [LumenColors.accent] for the label, [LumenColors.border] for the outline.
class LumenRetryButton extends StatelessWidget {
  const LumenRetryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// The button's visible (and accessible) name — 'Try again' / 'Retry'.
  final String label;

  /// What to re-run. Usually `() => ref.invalidate(someProvider)`.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.accent,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}
