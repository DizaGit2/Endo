import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';
import 'package:lumen/shared/widgets/lumen_step_dots.dart';

/// Screen 1 — Welcome (onboarding step 1 of 7).
///
/// Static layout with no API or state. Both CTAs navigate to the account
/// creation screen (Routes.account).
///
/// The HTML mockup draws this inside a 300px "phone frame" so it can be shown
/// in a browser; in the real app that frame IS the device, so it is dropped and
/// the content fills the screen on the frame's interior colour (surface). The
/// mockup's `margin:auto` below the subtitle pushes the CTA group to the bottom,
/// reproduced here with a [Spacer] inside a scroll-safe full-height column.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Section tag — sentence-case source; widget uppercases.
                        const LumenSectionLabel(
                          'Lumen · 1 of 7',
                          fontSize: 11,
                          letterSpacing: 1.5,
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
                            'Track symptoms, hormones, and patterns across every '
                            'phase. Built for endometriosis. Honest about your body.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: c.muted,
                              height: 1.6,
                            ),
                          ),
                        ),

                        // Mockup subtitle has margin-bottom:auto → pushes the CTA
                        // group to the bottom. A fixed min-gap protects small
                        // screens (where the Spacer collapses and content scrolls).
                        const SizedBox(height: 32),
                        const Spacer(),

                        // Primary CTA — "Begin"
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => context.go(Routes.account),
                            style: FilledButton.styleFrom(
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
                          onPressed: () => context.go(Routes.account),
                          style: TextButton.styleFrom(
                            foregroundColor: c.muted,
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
                        const LumenStepDots(count: 7, activeIndex: 0),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
