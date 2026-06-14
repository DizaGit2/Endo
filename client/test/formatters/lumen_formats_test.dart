import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';

void main() {
  // Locale data must be initialised before any DateFormat/NumberFormat call
  // with a non-default locale. initializeDateFormatting() is idempotent.
  setUpAll(() async {
    await initializeDateFormatting('es_ES');
    await initializeDateFormatting('en_US');
    await initializeDateFormatting('fr_FR');
  });

  // ---------------------------------------------------------------------------
  // date()
  // ---------------------------------------------------------------------------
  group('LumenFormats.date', () {
    // 2026-03-07 — March 7th. es → 7/3/… (day first), en_US → 3/7/… (month first).
    final d = DateTime(2026, 3, 7);

    test('es_ES: day appears before month', () {
      final result = LumenFormats.date(d, 'es_ES');
      // The formatted string starts with "7" for the day
      expect(result.startsWith('7'), isTrue,
          reason: 'es_ES short date should begin with day "7", got "$result"');
    });

    test('en_US: month appears before day', () {
      final result = LumenFormats.date(d, 'en_US');
      // The formatted string starts with "3" for the month
      expect(result.startsWith('3'), isTrue,
          reason: 'en_US short date should begin with month "3", got "$result"');
    });

    test('es_ES and en_US produce different strings', () {
      expect(LumenFormats.date(d, 'es_ES'), isNot(LumenFormats.date(d, 'en_US')));
    });
  });

  // ---------------------------------------------------------------------------
  // time()
  // ---------------------------------------------------------------------------
  group('LumenFormats.time', () {
    // 16:30 — an afternoon time that tests AM/PM vs 24-hour.
    final t = DateTime(2026, 1, 1, 16, 30);

    test('es_ES: no AM/PM marker, contains "16"', () {
      final result = LumenFormats.time(t, 'es_ES');
      expect(result.contains('AM'), isFalse,
          reason: 'es_ES time should not contain AM, got "$result"');
      expect(result.contains('PM'), isFalse,
          reason: 'es_ES time should not contain PM, got "$result"');
      expect(result.contains('16'), isTrue,
          reason: 'es_ES time should use 24-hour format "16", got "$result"');
    });

    test('en_US: contains "PM" for 16:30', () {
      final result = LumenFormats.time(t, 'en_US');
      expect(result.contains('PM'), isTrue,
          reason: 'en_US time should contain "PM" for 16:30, got "$result"');
    });
  });

  // ---------------------------------------------------------------------------
  // decimal()
  // ---------------------------------------------------------------------------
  group('LumenFormats.decimal', () {
    test('es_ES: comma as decimal separator', () {
      final result = LumenFormats.decimal(1.5, 'es_ES');
      expect(result.contains(','), isTrue,
          reason: 'es_ES decimal should use comma separator, got "$result"');
      expect(result.contains('.'), isFalse,
          reason: 'es_ES decimal should NOT use period, got "$result"');
    });

    test('en_US: period as decimal separator', () {
      final result = LumenFormats.decimal(1.5, 'en_US');
      expect(result.contains('.'), isTrue,
          reason: 'en_US decimal should use period separator, got "$result"');
      expect(result.contains(','), isFalse,
          reason: 'en_US decimal should NOT use comma, got "$result"');
    });

    test('decimalDigits=0 rounds to integer', () {
      final result = LumenFormats.decimal(1.9, 'en_US', decimalDigits: 0);
      // With 0 decimal digits, no decimal point expected
      expect(result.contains('.'), isFalse,
          reason: 'decimalDigits=0 should produce no decimal point, got "$result"');
    });

    test('decimalDigits=2 shows two decimal places', () {
      final result = LumenFormats.decimal(1.5, 'en_US', decimalDigits: 2);
      expect(result, contains('1.50'));
    });
  });

  // ---------------------------------------------------------------------------
  // firstDayOfWeek()
  // ---------------------------------------------------------------------------
  group('LumenFormats.firstDayOfWeek', () {
    test('es_ES → DateTime.monday (1)', () {
      expect(LumenFormats.firstDayOfWeek('es_ES'), DateTime.monday);
    });

    test('es (bare) → DateTime.monday (1)', () {
      expect(LumenFormats.firstDayOfWeek('es'), DateTime.monday);
    });

    test('en_US → DateTime.sunday (7)', () {
      expect(LumenFormats.firstDayOfWeek('en_US'), DateTime.sunday);
    });

    test('en-US (hyphen form) → DateTime.sunday (7)', () {
      expect(LumenFormats.firstDayOfWeek('en-US'), DateTime.sunday);
    });

    test('bare "en" → DateTime.monday (1) — only en_US is Sunday-first', () {
      expect(LumenFormats.firstDayOfWeek('en'), DateTime.monday);
    });

    test('en_GB → DateTime.monday (1) — UK is Monday-first', () {
      expect(LumenFormats.firstDayOfWeek('en_GB'), DateTime.monday);
    });

    test('unknown locale fr_FR → DateTime.monday (1) — safe default', () {
      expect(LumenFormats.firstDayOfWeek('fr_FR'), DateTime.monday);
    });
  });

  // ---------------------------------------------------------------------------
  // UnitSystem enum
  // ---------------------------------------------------------------------------
  group('UnitSystem', () {
    test('has metric and imperial values', () {
      expect(UnitSystem.values, containsAll([UnitSystem.metric, UnitSystem.imperial]));
    });

    test('default is metric', () {
      // The enum is declared with metric as the first (index 0) value
      expect(UnitSystem.values.first, UnitSystem.metric);
    });
  });

  // ---------------------------------------------------------------------------
  // mass()
  // ---------------------------------------------------------------------------
  group('LumenFormats.mass', () {
    test('es_ES: comma decimal + " kg" suffix', () {
      final result = LumenFormats.mass(60.4, 'es_ES');
      expect(result.contains(','), isTrue,
          reason: 'es_ES mass should use comma, got "$result"');
      expect(result.endsWith(' kg'), isTrue,
          reason: 'mass should end with " kg", got "$result"');
    });

    test('en_US: period decimal + " kg" suffix', () {
      final result = LumenFormats.mass(60.4, 'en_US');
      expect(result.contains('.'), isTrue,
          reason: 'en_US mass should use period, got "$result"');
      expect(result.endsWith(' kg'), isTrue,
          reason: 'mass should end with " kg", got "$result"');
    });

    test('imperial throws UnimplementedError', () {
      expect(
        () => LumenFormats.mass(60.4, 'en_US', system: UnitSystem.imperial),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // length()
  // ---------------------------------------------------------------------------
  group('LumenFormats.length', () {
    test('es_ES: 0 decimals + " cm" suffix', () {
      final result = LumenFormats.length(165.0, 'es_ES');
      expect(result.endsWith(' cm'), isTrue,
          reason: 'length should end with " cm", got "$result"');
      // 0 decimal digits — no decimal separator in output
      expect(result.contains(','), isFalse,
          reason: 'length(0 decimals) should have no comma, got "$result"');
      expect(result.contains('.'), isFalse,
          reason: 'length(0 decimals) should have no period, got "$result"');
    });

    test('en_US: "165 cm"', () {
      final result = LumenFormats.length(165.0, 'en_US');
      expect(result, '165 cm');
    });

    test('imperial throws UnimplementedError', () {
      expect(
        () => LumenFormats.length(165.0, 'en_US', system: UnitSystem.imperial),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // percent()
  // ---------------------------------------------------------------------------
  group('LumenFormats.percent', () {
    test('es_ES: comma decimal + " %" suffix', () {
      final result = LumenFormats.percent(23.5, 'es_ES');
      expect(result.contains(','), isTrue,
          reason: 'es_ES percent should use comma, got "$result"');
      expect(result.endsWith(' %'), isTrue,
          reason: 'percent should end with " %", got "$result"');
    });

    test('en_US: period decimal + " %" suffix', () {
      final result = LumenFormats.percent(23.5, 'en_US');
      expect(result.contains('.'), isTrue,
          reason: 'en_US percent should use period, got "$result"');
      expect(result.endsWith(' %'), isTrue,
          reason: 'percent should end with " %", got "$result"');
    });
  });
}
