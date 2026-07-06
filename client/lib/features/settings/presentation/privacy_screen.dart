import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

/// Screen 36 — Privacy & security (Settings).
///
/// Static layout with no API/state. D-07: the "Anonymous analytics" toggle
/// from the DATA section has been omitted — there is no analytics in v1.
///
/// Sections:
/// - APP LOCK: Face ID, Hide content in app switcher, Disguised app icon
/// - DATA: Encryption status (no analytics toggle per D-07)
/// - DANGER ZONE: Delete all data
/// - Warrant-canary notice (reproduced as-is from mockup)
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 44, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back affordance row (icon + section tag)
                Row(
                  children: [
                    Icon(Icons.chevron_left, color: c.muted, size: 22),
                    const SizedBox(width: 2),
                    const LumenSectionLabel(
                      'Settings',
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Screen title
                Text(
                  'Privacy & security',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),

                const SizedBox(height: 14),

                // --- APP LOCK section ---
                const LumenSectionLabel('App lock'),
                const SizedBox(height: 6),
                const _SettingsToggleRow(
                  label: 'Face ID',
                  subtitle: 'Required to open',
                  enabled: true,
                ),
                const SizedBox(height: 5),
                const _SettingsToggleRow(
                  label: 'Hide content in app switcher',
                  subtitle: 'Show blank screen',
                  enabled: true,
                ),
                const SizedBox(height: 5),
                const _SettingsToggleRow(
                  label: 'Disguised app icon',
                  subtitle: 'Show as "Notes"',
                  enabled: false,
                ),

                const SizedBox(height: 14),

                // --- DATA section ---
                const LumenSectionLabel('Data'),
                const SizedBox(height: 6),
                _SettingsInfoRow(
                  label: 'Encryption status',
                  value: 'AES-256',
                  valueColor: c.sage,
                  trailingIcon: Icon(Icons.check, size: 14, color: c.sage),
                ),

                // NOTE: D-07 — "Anonymous analytics" toggle omitted (no analytics in v1).
                const SizedBox(height: 14),

                // --- DANGER ZONE section ---
                const LumenSectionLabel('Danger zone'),
                const SizedBox(height: 6),
                _SettingsNavRow(label: 'Delete all data', labelColor: c.accent),

                const SizedBox(height: 14),

                // Warrant-canary notice (reproduced from mockup as-is,
                // '✦' dingbat replaced by an inline Icons.auto_awesome via
                // WidgetSpan so it wraps as part of the same paragraph).
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.sageSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            Icons.auto_awesome,
                            size: 12,
                            color: c.sage,
                          ),
                        ),
                        const TextSpan(
                          text: '  Lumen has never received a data request',
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: c.sage,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helper widgets
// ---------------------------------------------------------------------------

/// A settings row with a label, optional subtitle, and a toggle (on/off).
class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.label,
    required this.enabled,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // MergeSemantics: label + subtitle read as one unit. _MiniToggle is
    // documented visual-only (no onTap anywhere on this row today), so it is
    // safe to merge in too — unlike profile_screen.dart's _InfoRow, there is
    // no independently-actionable descendant here to protect.
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: c.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: c.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _MiniToggle(enabled: enabled),
          ],
        ),
      ),
    );
  }
}

/// A settings row showing a label and a static value string on the right,
/// with an optional trailing icon beside the value (e.g. a check mark).
class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.trailingIcon,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Widget? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // MergeSemantics: label + value (+ decorative icon, silent by default)
    // read as one unit, e.g. "Encryption status, AES-256".
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: c.ink,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: valueColor,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              trailingIcon!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A settings row with a label and a right-chevron (navigation intent).
class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({required this.label, this.labelColor});

  final String label;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final textColor = labelColor ?? c.ink;
    // MergeSemantics + a decorative (silent) chevron Icon: this row has no
    // destination screen wired up yet (see privacy_screen_semantics_test.dart)
    // so it stays informational rather than a fabricated button.
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: textColor),
          ],
        ),
      ),
    );
  }
}

/// A compact visual-only toggle pill (26×16 px) matching the mockup's design.
class _MiniToggle extends StatelessWidget {
  const _MiniToggle({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // OFF track: a low-opacity muted tint — visible in both light and dark themes
    // without referencing hard-coded brand hex. ON track: full accent colour.
    final trackColor = enabled ? c.accent : c.muted.withValues(alpha: 0.35);
    // Thumb: surface colour — contrasts clearly against both accent (ON) and the
    // muted tint (OFF) in light AND dark themes.
    final thumbColor = c.surface;
    return SizedBox(
      width: 26,
      height: 16,
      child: Stack(
        children: [
          // Track
          Container(
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          // Thumb
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            left: enabled ? null : 2,
            right: enabled ? 2 : null,
            top: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: thumbColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
