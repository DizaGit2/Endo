import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// The inline failure banner: an accent-soft card that announces itself the
/// moment it appears.
///
/// Promoted verbatim from `account_screen.dart`'s private `_ErrorBanner`
/// (P4b-T5). Every P4b write screen surfaces a failed write this way, and the
/// part worth having exactly once is not the decoration — it is
/// `Semantics(liveRegion: true)`. Thirteen hand-written banners is thirteen
/// chances to leave it off, and a missing live region is invisible to everyone
/// who is not using a screen reader.
///
/// Use it for a failure that is part of the page (a rejected form, a failed
/// save the user can retry in place). For a failure that replaced the whole
/// screen, use `LumenErrorRetry`.
class LumenErrorBanner extends StatelessWidget {
  const LumenErrorBanner({required this.message, super.key});

  /// The user-safe message — typically `Failure.message`.
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    // liveRegion: true — a screen reader announces this banner as soon as it
    // appears, rather than staying silent about a failed attempt until the
    // user happens to swipe onto it.
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.accent.withValues(alpha: 0.3)),
        ),
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: c.accent,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
