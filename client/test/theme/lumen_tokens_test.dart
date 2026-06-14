import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

void main() {
  group('lumenLight token values', () {
    test('bg', () => expect(lumenLight.bg, const Color(0xFFF1EFE8)));
    test('surface', () => expect(lumenLight.surface, const Color(0xFFFFFCF7)));
    test('ink', () => expect(lumenLight.ink, const Color(0xFF3B2A20)));
    test('muted', () => expect(lumenLight.muted, const Color(0xFF8A6F5E)));
    test('accent', () => expect(lumenLight.accent, const Color(0xFFC25A36)));
    test('accentSoft', () => expect(lumenLight.accentSoft, const Color(0xFFF3D9CC)));
    test('sage', () => expect(lumenLight.sage, const Color(0xFF7B8F6B)));
    test('sageSoft', () => expect(lumenLight.sageSoft, const Color(0xFFE4EADD)));
    test('border', () => expect(lumenLight.border, const Color(0x1F3B2A20)));
    test('input', () => expect(lumenLight.input, const Color(0xFFFAF6EF)));
  });

  group('lumenDark token values', () {
    test('bg', () => expect(lumenDark.bg, const Color(0xFF1A1220)));
    test('surface', () => expect(lumenDark.surface, const Color(0xFF241830)));
    test('ink', () => expect(lumenDark.ink, const Color(0xFFF2E4D4)));
    test('muted', () => expect(lumenDark.muted, const Color(0xFFA99BB8)));
    test('accent', () => expect(lumenDark.accent, const Color(0xFFE8A87C)));
    test('accentSoft', () => expect(lumenDark.accentSoft, const Color(0xFF3A2438)));
    test('sage', () => expect(lumenDark.sage, const Color(0xFF9BAE85)));
    test('sageSoft', () => expect(lumenDark.sageSoft, const Color(0xFF28321F)));
    test('border', () => expect(lumenDark.border, const Color(0x1FF2E4D4)));
    test('input', () => expect(lumenDark.input, const Color(0xFF1F1428)));
  });

  group('copyWith', () {
    test('overrides accent while preserving other fields', () {
      const someColor = Color(0xFFABCDEF);
      final result = lumenLight.copyWith(accent: someColor);
      expect(result.accent, someColor);
      expect(result.bg, lumenLight.bg);
      expect(result.surface, lumenLight.surface);
      expect(result.ink, lumenLight.ink);
      expect(result.muted, lumenLight.muted);
      expect(result.accentSoft, lumenLight.accentSoft);
      expect(result.sage, lumenLight.sage);
      expect(result.sageSoft, lumenLight.sageSoft);
      expect(result.border, lumenLight.border);
      expect(result.input, lumenLight.input);
    });

    test('no-arg copyWith returns equal instance', () {
      final result = lumenLight.copyWith();
      expect(result.bg, lumenLight.bg);
      expect(result.accent, lumenLight.accent);
    });
  });

  group('lerp', () {
    test('lerp at t=0.0 yields light values', () {
      final result = lumenLight.lerp(lumenDark, 0.0);
      expect(result.bg, lumenLight.bg);
      expect(result.accent, lumenLight.accent);
    });

    test('lerp at t=1.0 yields dark values', () {
      final result = lumenLight.lerp(lumenDark, 1.0);
      expect(result.bg, lumenDark.bg);
      expect(result.accent, lumenDark.accent);
    });

    test('lerp with null other returns this', () {
      final result = lumenLight.lerp(null, 0.5);
      // Should return a LumenColors that matches lumenLight
      expect(result.runtimeType, LumenColors);
      expect(result.bg, lumenLight.bg);
      expect(result.accent, lumenLight.accent);
    });
  });
}
