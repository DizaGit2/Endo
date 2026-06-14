import 'package:flutter/material.dart';

/// Hard-coded hormone colors. These do NOT switch with theme.
abstract final class HormonePalette {
  static const Color estrogen     = Color(0xFFC25A36);
  static const Color progesterone = Color(0xFF7B8F6B);
  static const Color lh           = Color(0xFFD4537E);
  static const Color fsh          = Color(0xFF378ADD);
  static const Color testosterone = Color(0xFFBA7517);
  static const Color cortisol     = Color(0xFF7F77DD);
  static const Color glp1         = Color(0xFF1D9E75);

  /// Maps a wire [hormoneCode] to its designated color.
  /// Unknown codes fall back to the design's light muted ink.
  static Color forCode(String hormoneCode) => switch (hormoneCode) {
        'estradiol' || 'estrogen' => estrogen,
        'progesterone'            => progesterone,
        'lh'                      => lh,
        'fsh'                     => fsh,
        'testosterone'            => testosterone,
        'cortisol'                => cortisol,
        'glp1'                    => glp1,
        _                         => const Color(0xFF8A6F5E),
      };
}
