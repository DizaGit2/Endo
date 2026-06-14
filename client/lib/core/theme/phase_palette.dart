import 'package:flutter/material.dart';

/// Cycle-phase colors. These DO switch with theme (light / dark pairs).
abstract final class PhasePalette {
  /// Menstrual phase color.
  static Color menstrual(Brightness b) => b == Brightness.light
      ? const Color(0xFFF3D9CC)
      : const Color(0xFF4A1B0C);

  /// Follicular phase color.
  static Color follicular(Brightness b) => b == Brightness.light
      ? const Color(0xFFFAEEDA)
      : const Color(0xFF412402);

  /// Ovulatory phase color.
  static Color ovulatory(Brightness b) => b == Brightness.light
      ? const Color(0xFFE4EADD)
      : const Color(0xFF28321F);

  /// Luteal phase color.
  static Color luteal(Brightness b) => b == Brightness.light
      ? const Color(0xFFEEEDFE)
      : const Color(0xFF26215C);
}
