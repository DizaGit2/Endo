import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/phase_palette.dart';

void main() {
  group('PhasePalette.menstrual', () {
    test('Brightness.light → Color(0xFFF3D9CC)', () {
      expect(PhasePalette.menstrual(Brightness.light), const Color(0xFFF3D9CC));
    });

    test('Brightness.dark → Color(0xFF4A1B0C)', () {
      expect(PhasePalette.menstrual(Brightness.dark), const Color(0xFF4A1B0C));
    });
  });

  group('PhasePalette.follicular', () {
    test('Brightness.light → Color(0xFFFAEEDA)', () {
      expect(PhasePalette.follicular(Brightness.light), const Color(0xFFFAEEDA));
    });

    test('Brightness.dark → Color(0xFF412402)', () {
      expect(PhasePalette.follicular(Brightness.dark), const Color(0xFF412402));
    });
  });

  group('PhasePalette.ovulatory', () {
    test('Brightness.light → Color(0xFFE4EADD)', () {
      expect(PhasePalette.ovulatory(Brightness.light), const Color(0xFFE4EADD));
    });

    test('Brightness.dark → Color(0xFF28321F)', () {
      expect(PhasePalette.ovulatory(Brightness.dark), const Color(0xFF28321F));
    });
  });

  group('PhasePalette.luteal', () {
    test('Brightness.light → Color(0xFFEEEDFE)', () {
      expect(PhasePalette.luteal(Brightness.light), const Color(0xFFEEEDFE));
    });

    test('Brightness.dark → Color(0xFF26215C)', () {
      expect(PhasePalette.luteal(Brightness.dark), const Color(0xFF26215C));
    });
  });
}
