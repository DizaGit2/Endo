import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_retry_button.dart';

/// A whole-surface failure state: a message that announces itself, and one
/// affordance to try again.
///
/// This existed twice, verbatim, in two different layers — `_ErrorBody` in
/// `profile_screen.dart` and `_GateUnavailableBody` in `app_router.dart`. The
/// second was written as a deliberate copy by P4b-T1 with a comment saying T5
/// would collapse it; this is that collapse.
///
/// It is NOT [LumenErrorBanner]. The banner is part of a page that is still
/// usable (a rejected form field, a save the user can retry in place); this is
/// what a screen renders when it has nothing else to show.
///
/// It takes no provider: like [LumenRetryButton], the invalidation belongs at
/// the call site, so the same widget serves the profile read, the onboarding
/// gate read and every P4b screen controller.
///
/// The affordance always reads 'Try again'; there is no label parameter. Both
/// call sites say exactly that, and a screen whose failure needs different
/// wording (screen 31's network-required surface, which says 'Retry' under an
/// icon and two lines of its own copy) is not this widget at all — it composes
/// [LumenRetryButton] directly.
///
/// Props:
/// - [message] — the user-safe failure text. Announced as a live region.
/// - [onRetry] — usually `() => ref.invalidate(someProvider)`.
class LumenErrorRetry extends StatelessWidget {
  const LumenErrorRetry({
    required this.message,
    required this.onRetry,
    super.key,
  });

  /// The label on the retry affordance. Not a parameter — see the class doc.
  static const String retryLabel = 'Try again';

  /// The user-safe failure text.
  final String message;

  /// What the retry affordance re-runs.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // liveRegion: true — announces the failure as soon as it renders,
            // rather than relying on the user to swipe onto it.
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            ),
            const SizedBox(height: 16),
            LumenRetryButton(label: retryLabel, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
