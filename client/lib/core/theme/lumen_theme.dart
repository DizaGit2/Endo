import 'package:flutter/material.dart';
import 'lumen_tokens.dart';

/// Builds a Material-3 [ThemeData] from Lumen design-system tokens.
///
/// [brightness] selects between the "soft warm" light palette and the
/// "witchy" dark palette defined in [lumenLight] / [lumenDark].
///
/// Typography: no custom [fontFamily] is set — the platform system sans-serif
/// stack is the design spec. The design mandates exactly two weights,
/// [FontWeight.w400] and [FontWeight.w500]. Material-3's
/// [Typography.material2021] already satisfies this for the englishLike script
/// (it uses only w400/w500), and at the [ThemeData.textTheme] level most slots
/// expose `fontWeight: null` (inherit) — the concrete weight is resolved from
/// [Typography] at render time. [_normaliseWeights] is therefore a safety net:
/// it only clamps a slot that carries an *explicit* out-of-range weight
/// (e.g. introduced by a future SDK change or a custom `.apply`), leaving the
/// null/inherit and already-compliant slots untouched.
ThemeData lumenTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  // Readable contrast colours that are not token-named but needed by
  // ColorScheme. These are constant and the same for both themes.
  const white = Color(0xFFFFFCF7); // lumenLight.surface — warm white
  const darkInk = Color(0xFF3B2A20); // lumenLight.ink

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: brightness == Brightness.light ? white : darkInk,
    secondary: c.sage,
    onSecondary: brightness == Brightness.light ? white : darkInk,
    error: const Color(0xFFB3261E), // M3 default error red
    onError: const Color(0xFFFFFFFF),
    surface: c.surface,
    onSurface: c.ink,
    outline: c.border,
  );

  // Build the base theme so we get the M3 text theme with correct sizes and
  // letter-spacing, then normalise every weight to {w400, w500}.
  final baseTheme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: c.bg,
    extensions: <ThemeExtension<dynamic>>[c],
  );

  final normalised = _normaliseWeights(
    baseTheme.textTheme.apply(
      bodyColor: c.ink,
      displayColor: c.ink,
    ),
  );

  return baseTheme.copyWith(textTheme: normalised);
}

/// Replaces any [FontWeight] that is not [FontWeight.w400] or
/// [FontWeight.w500] with the nearest allowed weight:
/// - lighter than w400 (w100, w200, w300) → w400
/// - heavier than w500 (w600, w700, w800, w900) → w500
TextTheme _normaliseWeights(TextTheme tt) {
  return TextTheme(
    displayLarge: _fix(tt.displayLarge),
    displayMedium: _fix(tt.displayMedium),
    displaySmall: _fix(tt.displaySmall),
    headlineLarge: _fix(tt.headlineLarge),
    headlineMedium: _fix(tt.headlineMedium),
    headlineSmall: _fix(tt.headlineSmall),
    titleLarge: _fix(tt.titleLarge),
    titleMedium: _fix(tt.titleMedium),
    titleSmall: _fix(tt.titleSmall),
    bodyLarge: _fix(tt.bodyLarge),
    bodyMedium: _fix(tt.bodyMedium),
    bodySmall: _fix(tt.bodySmall),
    labelLarge: _fix(tt.labelLarge),
    labelMedium: _fix(tt.labelMedium),
    labelSmall: _fix(tt.labelSmall),
  );
}

TextStyle? _fix(TextStyle? style) {
  if (style == null) return null;
  final w = style.fontWeight;
  if (w == null || w == FontWeight.w400 || w == FontWeight.w500) return style;
  // Anything lighter than w400 maps to w400; anything heavier maps to w500.
  final fixed =
      (w.value < FontWeight.w400.value) ? FontWeight.w400 : FontWeight.w500;
  return style.copyWith(fontWeight: fixed);
}

/// Convenience getter: light theme.
ThemeData get lumenLightTheme => lumenTheme(Brightness.light);

/// Convenience getter: dark theme.
ThemeData get lumenDarkTheme => lumenTheme(Brightness.dark);
