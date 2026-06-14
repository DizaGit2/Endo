import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

/// Screen 37 — Help & about (Settings).
///
/// Static layout with no API/state.
///
/// Sections:
/// - App identity card (icon, name, version)
/// - SUPPORT: Quick start guide, How predictions work, Endo resources, Contact support
/// - LEGAL: Privacy policy, Terms of service, Open source licenses
/// - Footer notice (reproduced from mockup as-is)
class HelpAboutScreen extends StatelessWidget {
  const HelpAboutScreen({super.key});

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
                          letterSpacing: 1.5),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Screen title
                  Text(
                    'Help & about',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // App identity card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.input,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      children: [
                        // Lumen icon — asterism glyph in accent
                        Text(
                          '✦',
                          style: TextStyle(
                            fontSize: 32,
                            color: c.accent,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lumen',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Version 1.0 · build 142',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // --- SUPPORT section ---
                  const LumenSectionLabel('Support'),
                  const SizedBox(height: 6),
                  const _NavRow(label: 'Quick start guide'),
                  const SizedBox(height: 5),
                  const _NavRow(label: 'How predictions work'),
                  const SizedBox(height: 5),
                  const _NavRow(label: 'Endo resources'),
                  const SizedBox(height: 5),
                  const _NavRow(label: 'Contact support'),

                  const SizedBox(height: 14),

                  // --- LEGAL section ---
                  const LumenSectionLabel('Legal'),
                  const SizedBox(height: 6),
                  const _NavRow(label: 'Privacy policy'),
                  const SizedBox(height: 5),
                  const _NavRow(label: 'Terms of service'),
                  const SizedBox(height: 5),
                  const _NavRow(label: 'Open source licenses'),

                  const SizedBox(height: 14),

                  // Footer notice (reproduced from mockup as-is)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.sageSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '✦ Made with care for everyone who\'s been told it\'s just cramps',
                      textAlign: TextAlign.center,
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
// Private helper widget
// ---------------------------------------------------------------------------

/// A simple navigation list row with label on left and '›' chevron on right.
class _NavRow extends StatelessWidget {
  const _NavRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Container(
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
            '›',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}
