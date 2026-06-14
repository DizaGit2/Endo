import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/hormone_palette.dart';

void main() {
  group('HormonePalette — const members', () {
    test('estrogen is Color(0xFFC25A36)', () {
      expect(HormonePalette.estrogen, const Color(0xFFC25A36));
    });

    test('progesterone is Color(0xFF7B8F6B)', () {
      expect(HormonePalette.progesterone, const Color(0xFF7B8F6B));
    });

    test('lh is Color(0xFFD4537E)', () {
      expect(HormonePalette.lh, const Color(0xFFD4537E));
    });

    test('fsh is Color(0xFF378ADD)', () {
      expect(HormonePalette.fsh, const Color(0xFF378ADD));
    });

    test('testosterone is Color(0xFFBA7517)', () {
      expect(HormonePalette.testosterone, const Color(0xFFBA7517));
    });

    test('cortisol is Color(0xFF7F77DD)', () {
      expect(HormonePalette.cortisol, const Color(0xFF7F77DD));
    });

    test('glp1 is Color(0xFF1D9E75)', () {
      expect(HormonePalette.glp1, const Color(0xFF1D9E75));
    });
  });

  group('HormonePalette.forCode — known codes', () {
    test('"estrogen" → estrogen', () {
      expect(HormonePalette.forCode('estrogen'), HormonePalette.estrogen);
    });

    test('"estradiol" alias → estrogen', () {
      expect(HormonePalette.forCode('estradiol'), HormonePalette.estrogen);
    });

    test('"progesterone" → progesterone', () {
      expect(HormonePalette.forCode('progesterone'), HormonePalette.progesterone);
    });

    test('"lh" → lh', () {
      expect(HormonePalette.forCode('lh'), HormonePalette.lh);
    });

    test('"fsh" → fsh', () {
      expect(HormonePalette.forCode('fsh'), HormonePalette.fsh);
    });

    test('"testosterone" → testosterone', () {
      expect(HormonePalette.forCode('testosterone'), HormonePalette.testosterone);
    });

    test('"cortisol" → cortisol', () {
      expect(HormonePalette.forCode('cortisol'), HormonePalette.cortisol);
    });

    test('"glp1" → glp1', () {
      expect(HormonePalette.forCode('glp1'), HormonePalette.glp1);
    });
  });

  group('HormonePalette.forCode — unknown codes fall back to muted', () {
    const muted = Color(0xFF8A6F5E);

    test('"unknown" → muted fallback', () {
      expect(HormonePalette.forCode('unknown'), muted);
    });

    test('"" (empty) → muted fallback', () {
      expect(HormonePalette.forCode(''), muted);
    });
  });
}
