import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// Screen 1 — Welcome (onboarding step 1 of 7).
///
/// Static layout with no API or state. CTA callbacks are no-ops until
/// routing is wired in P3b (TODO P3b).
///
/// Layout mirrors the HTML mockup:
/// - section tag "Lumen · 1 of 7" (small, sage, uppercased)
/// - moon icon in an accent-soft circle
/// - headline "Your cycle, understood"
/// - subtitle copy
/// - primary "Begin" button (accent filled)
/// - "I already have an account" text link (muted)
/// - step-indicator dots (7 total; first dot is active/wide)
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Section tag
                  Text(
                    'LUMEN · 1 OF 7',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: c.sage,
                      letterSpacing: 1.5,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Moon icon in accent-soft circle
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: CustomPaint(
                        size: const Size(48, 48),
                        painter: _MoonPainter(color: c.accent),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Headline
                  Text(
                    'Your cycle, understood',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                      letterSpacing: -0.3,
                      height: 1.25,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Track symptoms, hormones, and patterns across every phase. '
                      'Built for endometriosis. Honest about your body.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: c.muted,
                        height: 1.6,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Primary CTA — "Begin"
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: null, // TODO(P3b): navigate to account screen
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: const Color(0xFFFFFCF7),
                        disabledBackgroundColor: c.accent,
                        disabledForegroundColor: const Color(0xFFFFFCF7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Begin'),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Secondary link — "I already have an account"
                  TextButton(
                    onPressed: null, // TODO(P3b): navigate to login screen
                    style: TextButton.styleFrom(
                      foregroundColor: c.muted,
                      disabledForegroundColor: c.muted,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('I already have an account'),
                  ),

                  const SizedBox(height: 18),

                  // Step-indicator dots (7 total, first is active)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 7; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        _StepDot(active: i == 0, color: c.accent, border: c.border),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the crescent-moon SVG from the mockup:
/// - outer circle stroke
/// - filled moon-arc path
class _MoonPainter extends CustomPainter {
  const _MoonPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2; // 24 @ 48x48

    // Outer circle stroke
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(cx, cy), r - 1, strokePaint);

    // Filled crescent: the full circle minus a smaller offset circle.
    // This replicates the SVG path `M24 8 a16 16 0 0 0 0 32 a12 12 0 0 1 0 -32z`.
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r - 1));

    // Subtract the inner offset circle (shifted right to expose crescent on left)
    final cutPath = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(cx + r * 0.375, cy),
          radius: r * 0.75,
        ),
      );

    final crescent = Path.combine(PathOperation.difference, path, cutPath);
    canvas.drawPath(crescent, fillPaint);
  }

  @override
  bool shouldRepaint(_MoonPainter old) => old.color != color;
}

/// A single step-indicator dot.
///
/// Active dot: accent colour, wider (18×6) pill shape.
/// Inactive dot: border colour, circle (6×6).
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
