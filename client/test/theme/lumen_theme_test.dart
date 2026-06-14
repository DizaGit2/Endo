import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

void main() {
  group('lumenTheme — light', () {
    late ThemeData theme;

    setUpAll(() {
      theme = lumenTheme(Brightness.light);
    });

    test('useMaterial3 is true', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('brightness matches', () {
      expect(theme.brightness, Brightness.light);
    });

    test('colorScheme.brightness matches', () {
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('colorScheme.primary == lumenLight.accent', () {
      expect(theme.colorScheme.primary, lumenLight.accent);
    });

    test('colorScheme.secondary == lumenLight.sage', () {
      expect(theme.colorScheme.secondary, lumenLight.sage);
    });

    test('colorScheme.surface == lumenLight.surface', () {
      expect(theme.colorScheme.surface, lumenLight.surface);
    });

    test('scaffoldBackgroundColor == lumenLight.bg', () {
      expect(theme.scaffoldBackgroundColor, lumenLight.bg);
    });

    test('extension<LumenColors>() returns lumenLight', () {
      final ext = theme.extension<LumenColors>();
      expect(ext, isNotNull);
      expect(ext!.bg, lumenLight.bg);
      expect(ext.surface, lumenLight.surface);
      expect(ext.ink, lumenLight.ink);
      expect(ext.muted, lumenLight.muted);
      expect(ext.accent, lumenLight.accent);
      expect(ext.accentSoft, lumenLight.accentSoft);
      expect(ext.sage, lumenLight.sage);
      expect(ext.sageSoft, lumenLight.sageSoft);
      expect(ext.border, lumenLight.border);
      expect(ext.input, lumenLight.input);
    });
  });

  group('lumenTheme — dark', () {
    late ThemeData theme;

    setUpAll(() {
      theme = lumenTheme(Brightness.dark);
    });

    test('useMaterial3 is true', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('brightness matches', () {
      expect(theme.brightness, Brightness.dark);
    });

    test('colorScheme.brightness matches', () {
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('colorScheme.primary == lumenDark.accent', () {
      expect(theme.colorScheme.primary, lumenDark.accent);
    });

    test('colorScheme.secondary == lumenDark.sage', () {
      expect(theme.colorScheme.secondary, lumenDark.sage);
    });

    test('colorScheme.surface == lumenDark.surface', () {
      expect(theme.colorScheme.surface, lumenDark.surface);
    });

    test('scaffoldBackgroundColor == lumenDark.bg', () {
      expect(theme.scaffoldBackgroundColor, lumenDark.bg);
    });

    test('extension<LumenColors>() returns lumenDark', () {
      final ext = theme.extension<LumenColors>();
      expect(ext, isNotNull);
      expect(ext!.bg, lumenDark.bg);
      expect(ext.surface, lumenDark.surface);
      expect(ext.ink, lumenDark.ink);
      expect(ext.muted, lumenDark.muted);
      expect(ext.accent, lumenDark.accent);
      expect(ext.accentSoft, lumenDark.accentSoft);
      expect(ext.sage, lumenDark.sage);
      expect(ext.sageSoft, lumenDark.sageSoft);
      expect(ext.border, lumenDark.border);
      expect(ext.input, lumenDark.input);
    });
  });

  group('lumenTheme — typography weight guard', () {
    // The design mandates exactly two weights: w400 and w500.
    // We verify this for both brightness modes to catch regressions.
    for (final brightness in [Brightness.light, Brightness.dark]) {
      test('all named TextStyles use only w400 or w500 (${brightness.name})', () {
        final theme = lumenTheme(brightness);
        final tt = theme.textTheme;
        final styles = [
          tt.displayLarge,
          tt.displayMedium,
          tt.displaySmall,
          tt.headlineLarge,
          tt.headlineMedium,
          tt.headlineSmall,
          tt.titleLarge,
          tt.titleMedium,
          tt.titleSmall,
          tt.bodyLarge,
          tt.bodyMedium,
          tt.bodySmall,
          tt.labelLarge,
          tt.labelMedium,
          tt.labelSmall,
        ];
        final allowed = {FontWeight.w400, FontWeight.w500};
        for (final style in styles) {
          if (style == null) continue;
          final weight = style.fontWeight;
          if (weight == null) continue; // null means "inherit" — acceptable
          expect(
            allowed.contains(weight),
            isTrue,
            reason:
                'Style "${style.debugLabel}" has fontWeight $weight, '
                'but only w400 and w500 are allowed.',
          );
        }
      });
    }
  });
}
