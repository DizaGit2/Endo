import 'package:flutter/material.dart';

@immutable
class LumenColors extends ThemeExtension<LumenColors> {
  const LumenColors({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.sage,
    required this.sageSoft,
    required this.border,
    required this.input,
  });

  final Color bg;         // --b
  final Color surface;    // --f
  final Color ink;        // --ink
  final Color muted;      // --mut
  final Color accent;     // --ac
  final Color accentSoft; // --acs
  final Color sage;       // --sg
  final Color sageSoft;   // --sgs
  final Color border;     // --bd
  final Color input;      // --in

  @override
  LumenColors copyWith({
    Color? bg,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? accent,
    Color? accentSoft,
    Color? sage,
    Color? sageSoft,
    Color? border,
    Color? input,
  }) {
    return LumenColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      sage: sage ?? this.sage,
      sageSoft: sageSoft ?? this.sageSoft,
      border: border ?? this.border,
      input: input ?? this.input,
    );
  }

  @override
  LumenColors lerp(ThemeExtension<LumenColors>? other, double t) {
    if (other is! LumenColors) return this;
    return LumenColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      sageSoft: Color.lerp(sageSoft, other.sageSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      input: Color.lerp(input, other.input, t)!,
    );
  }
}

const lumenLight = LumenColors(
  bg: Color(0xFFF1EFE8),
  surface: Color(0xFFFFFCF7),
  ink: Color(0xFF3B2A20),
  muted: Color(0xFF8A6F5E),
  accent: Color(0xFFC25A36),
  accentSoft: Color(0xFFF3D9CC),
  sage: Color(0xFF7B8F6B),
  sageSoft: Color(0xFFE4EADD),
  border: Color(0x1F3B2A20),
  input: Color(0xFFFAF6EF),
);

const lumenDark = LumenColors(
  bg: Color(0xFF1A1220),
  surface: Color(0xFF241830),
  ink: Color(0xFFF2E4D4),
  muted: Color(0xFFA99BB8),
  accent: Color(0xFFE8A87C),
  accentSoft: Color(0xFF3A2438),
  sage: Color(0xFF9BAE85),
  sageSoft: Color(0xFF28321F),
  border: Color(0x1FF2E4D4),
  input: Color(0xFF1F1428),
);
