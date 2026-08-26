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
      expect(
        result.startsWith('7'),
        isTrue,
        reason: 'es_ES short date should begin with day "7", got "$result"',
      );
    });

    test('en_US: month appears before day', () {
      final result = LumenFormats.date(d, 'en_US');
      // The formatted string starts with "3" for the month
      expect(
        result.startsWith('3'),
        isTrue,
        reason: 'en_US short date should begin with month "3", got "$result"',
      );
    });

    test('es_ES and en_US produce different strings', () {
      expect(
        LumenFormats.date(d, 'es_ES'),
        isNot(LumenFormats.date(d, 'en_US')),
      );
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
      expect(
        result.contains('AM'),
        isFalse,
        reason: 'es_ES time should not contain AM, got "$result"',
      );
      expect(
        result.contains('PM'),
        isFalse,
        reason: 'es_ES time should not contain PM, got "$result"',
      );
      expect(
        result.contains('16'),
        isTrue,
        reason: 'es_ES time should use 24-hour format "16", got "$result"',
      );
    });

    test('en_US: contains "PM" for 16:30', () {
      final result = LumenFormats.time(t, 'en_US');
      expect(
        result.contains('PM'),
        isTrue,
        reason: 'en_US time should contain "PM" for 16:30, got "$result"',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // decimal()
  // ---------------------------------------------------------------------------
  group('LumenFormats.decimal', () {
    test('es_ES: comma as decimal separator', () {
      final result = LumenFormats.decimal(1.5, 'es_ES');
      expect(
        result.contains(','),
        isTrue,
        reason: 'es_ES decimal should use comma separator, got "$result"',
      );
      expect(
        result.contains('.'),
        isFalse,
        reason: 'es_ES decimal should NOT use period, got "$result"',
      );
    });

    test('en_US: period as decimal separator', () {
      final result = LumenFormats.decimal(1.5, 'en_US');
      expect(
        result.contains('.'),
        isTrue,
        reason: 'en_US decimal should use period separator, got "$result"',
      );
      expect(
        result.contains(','),
        isFalse,
        reason: 'en_US decimal should NOT use comma, got "$result"',
      );
    });

    test('decimalDigits=0 rounds to integer', () {
      final result = LumenFormats.decimal(1.9, 'en_US', decimalDigits: 0);
      // With 0 decimal digits, no decimal point expected
      expect(
        result.contains('.'),
        isFalse,
        reason:
            'decimalDigits=0 should produce no decimal point, got "$result"',
      );
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
      expect(
        UnitSystem.values,
        containsAll([UnitSystem.metric, UnitSystem.imperial]),
      );
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
      expect(
        result.contains(','),
        isTrue,
        reason: 'es_ES mass should use comma, got "$result"',
      );
      expect(
        result.endsWith(' kg'),
        isTrue,
        reason: 'mass should end with " kg", got "$result"',
      );
    });

    test('en_US: period decimal + " kg" suffix', () {
      final result = LumenFormats.mass(60.4, 'en_US');
      expect(
        result.contains('.'),
        isTrue,
        reason: 'en_US mass should use period, got "$result"',
      );
      expect(
        result.endsWith(' kg'),
        isTrue,
        reason: 'mass should end with " kg", got "$result"',
      );
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
      expect(
        result.endsWith(' cm'),
        isTrue,
        reason: 'length should end with " cm", got "$result"',
      );
      // 0 decimal digits — no decimal separator in output
      expect(
        result.contains(','),
        isFalse,
        reason: 'length(0 decimals) should have no comma, got "$result"',
      );
      expect(
        result.contains('.'),
        isFalse,
        reason: 'length(0 decimals) should have no period, got "$result"',
      );
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
      expect(
        result.contains(','),
        isTrue,
        reason: 'es_ES percent should use comma, got "$result"',
      );
      expect(
        result.endsWith(' %'),
        isTrue,
        reason: 'percent should end with " %", got "$result"',
      );
    });

    test('en_US: period decimal + " %" suffix', () {
      final result = LumenFormats.percent(23.5, 'en_US');
      expect(
        result.contains('.'),
        isTrue,
        reason: 'en_US percent should use period, got "$result"',
      );
      expect(
        result.endsWith(' %'),
        isTrue,
        reason: 'percent should end with " %", got "$result"',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // orderedWeekdays() — the week LAYOUT, added in P4b-T6
  // ---------------------------------------------------------------------------
  //
  // Weekday LABELS are deliberately not returned: strings stay English in P4b
  // (ruling R-04). A screen holds its own seven labels and indexes them by the
  // order this returns, so the grid rotates without any string being translated.
  group('LumenFormats.orderedWeekdays', () {
    test('es_ES starts on Monday', () {
      expect(LumenFormats.orderedWeekdays('es_ES'), [
        1,
        2,
        3,
        4,
        5,
        6,
        DateTime.sunday,
      ]);
    });

    test('en_US starts on Sunday', () {
      expect(LumenFormats.orderedWeekdays('en_US'), [
        DateTime.sunday,
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
    });

    test('every locale yields each weekday exactly once, STARTING where it '
        'should', () {
      // The set-equality half is satisfied by EVERY rotation, including a
      // locale-blind one — so on its own it cannot fail in the direction that
      // matters. The expected first day is the positive control that can.
      const expectedFirst = <String, int>{
        'es_ES': DateTime.monday,
        'en_US': DateTime.sunday,
        'fr_FR': DateTime.monday,
        'es': DateTime.monday,
      };

      for (final entry in expectedFirst.entries) {
        final ordered = LumenFormats.orderedWeekdays(entry.key);
        expect(ordered, hasLength(7), reason: entry.key);
        expect(ordered.toSet(), {1, 2, 3, 4, 5, 6, 7}, reason: entry.key);
        expect(ordered.first, entry.value, reason: entry.key);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // leadingBlankDays() — the month grid's offset, added in P4b-T6
  // ---------------------------------------------------------------------------
  group('LumenFormats.leadingBlankDays', () {
    // 2026-04-01 is a Wednesday.
    final april = DateTime(2026, 4, 1);
    // 2026-03-01 is a Sunday — the case where the two conventions disagree most.
    final march = DateTime(2026, 3, 1);

    test('sanity: the fixtures really are a Wednesday and a Sunday', () {
      expect(april.weekday, DateTime.wednesday);
      expect(march.weekday, DateTime.sunday);
    });

    test('April 2026: 2 blanks Monday-first, 3 Sunday-first', () {
      expect(LumenFormats.leadingBlankDays(april, 'es_ES'), 2);
      expect(LumenFormats.leadingBlankDays(april, 'en_US'), 3);
    });

    test('March 2026: 6 blanks Monday-first, 0 Sunday-first', () {
      expect(LumenFormats.leadingBlankDays(march, 'es_ES'), 6);
      expect(LumenFormats.leadingBlankDays(march, 'en_US'), 0);
    });

    test('every month of 2026, both conventions, pinned', () {
      // The range invariant (0..6) is kept, but it is NOT the assertion with
      // teeth: EVERY `% 7` implementation satisfies it, locale-blind ones
      // included. The expected offsets are the positive control — the en_US
      // column is exactly one more than the es_ES column except where the
      // month starts on a Sunday, and a locale-blind implementation cannot
      // produce both columns.
      const mondayFirst = <int>[3, 6, 6, 2, 4, 0, 2, 5, 1, 3, 6, 1];
      const sundayFirst = <int>[4, 0, 0, 3, 5, 1, 3, 6, 2, 4, 0, 2];

      for (var month = 1; month <= 12; month++) {
        final first = DateTime(2026, month);
        for (final entry in <String, List<int>>{
          'es_ES': mondayFirst,
          'en_US': sundayFirst,
        }.entries) {
          final blanks = LumenFormats.leadingBlankDays(first, entry.key);
          expect(
            blanks,
            inInclusiveRange(0, 6),
            reason: '${entry.key} month $month',
          );
          expect(
            blanks,
            entry.value[month - 1],
            reason:
                '${entry.key} 2026-$month starts on weekday '
                '${first.weekday}',
          );
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // monthYear() — month-precision display for `diagnosedOn`, added in P4b-T6
  // ---------------------------------------------------------------------------
  group('LumenFormats.monthYear', () {
    final august = DateTime(2026, 8);

    test('renders month precision — no invented day', () {
      expect(LumenFormats.monthYear(august, 'en_US'), '8/2026');
      expect(LumenFormats.monthYear(august, 'es_ES'), '8/2026');
    });

    test('ignores the day component it is handed', () {
      expect(LumenFormats.monthYear(DateTime(2026, 8, 15), 'en_US'), '8/2026');
    });

    test('is locale-driven rather than one fixed pattern', () {
      // ja puts the year first. Not a supported app locale — it is here purely
      // as proof that the locale argument is consulted at all.
      expect(LumenFormats.monthYear(august, 'ja'), startsWith('2026'));
    });

    test('is numeric, so no month NAME is translated into the UI (R-04)', () {
      expect(LumenFormats.monthYear(august, 'es_ES'), isNot(contains('ago')));
      expect(LumenFormats.monthYear(august, 'en_US'), isNot(contains('Aug')));
    });
  });

  // ---------------------------------------------------------------------------
  // monthName() — the ENGLISH month-name title screen 10 needs (P4b-T15).
  // No [locale] parameter — see the formatter's own dartdoc for why.
  // ---------------------------------------------------------------------------
  group('LumenFormats.monthName', () {
    test('renders the English month name plus the year', () {
      expect(LumenFormats.monthName(DateTime(2026, 4, 1)), 'April 2026');
    });

    test('ignores the day component it is handed', () {
      expect(LumenFormats.monthName(DateTime(2026, 4, 15)), 'April 2026');
    });

    test("January and December — the month array's own two boundaries", () {
      expect(LumenFormats.monthName(DateTime(2026, 1, 1)), 'January 2026');
      expect(LumenFormats.monthName(DateTime(2026, 12, 1)), 'December 2026');
    });

    // fix-round-1, M-4: retitled. The ORIGINAL title claimed this proves
    // monthName "takes no locale" — it cannot: that is a compile-time fact
    // the function's own signature enforces (there is no parameter to pass
    // one to), and no runtime assertion can exercise a fact the compiler
    // already guarantees. What this body actually checks is a month that is
    // neither array boundary (January/December, covered above) nor the
    // April fixture used everywhere else in this file.
    test('a non-boundary month (August) renders correctly too', () {
      expect(LumenFormats.monthName(DateTime(2026, 8, 1)), 'August 2026');
    });
  });

  // ---------------------------------------------------------------------------
  // weekdayName() — the ENGLISH weekday name screen 11 needs (P4b-T16).
  // No [locale] parameter — same reasoning as monthName.
  // ---------------------------------------------------------------------------
  group('LumenFormats.weekdayName', () {
    test('renders the English weekday name', () {
      // 2026-04-07 is a Tuesday.
      expect(LumenFormats.weekdayName(DateTime(2026, 4, 7)), 'Tuesday');
    });

    test("Monday and Sunday — DateTime.weekday's own two boundaries", () {
      // 2026-04-06 is a Monday (weekday == 1); 2026-04-12 is a Sunday
      // (weekday == 7) — the array's first and last index.
      expect(LumenFormats.weekdayName(DateTime(2026, 4, 6)), 'Monday');
      expect(LumenFormats.weekdayName(DateTime(2026, 4, 12)), 'Sunday');
    });

    test('a non-boundary weekday (Thursday) renders correctly too', () {
      expect(LumenFormats.weekdayName(DateTime(2026, 4, 9)), 'Thursday');
    });
  });

  // ---------------------------------------------------------------------------
  // monthDay() — the ENGLISH "month day" header screen 11 needs (P4b-T16).
  // No [locale] parameter — same reasoning as monthName.
  // ---------------------------------------------------------------------------
  group('LumenFormats.monthDay', () {
    test('renders the English month name plus the day, no year', () {
      expect(LumenFormats.monthDay(DateTime(2026, 4, 7)), 'April 7');
    });

    test('ignores the year and time-of-day components it is handed', () {
      expect(LumenFormats.monthDay(DateTime(2099, 4, 7, 23, 59)), 'April 7');
    });

    test("January and December — the month array's own two boundaries", () {
      expect(LumenFormats.monthDay(DateTime(2026, 1, 1)), 'January 1');
      expect(LumenFormats.monthDay(DateTime(2026, 12, 31)), 'December 31');
    });
  });

  // ---------------------------------------------------------------------------
  // hasLocaleData() — what the locale resolver leans on, added in P4b-T6
  // ---------------------------------------------------------------------------
  group('LumenFormats.hasLocaleData', () {
    test('true for the locales this app ships', () {
      expect(LumenFormats.hasLocaleData('es_ES'), isTrue);
      expect(LumenFormats.hasLocaleData('en_US'), isTrue);
      expect(LumenFormats.hasLocaleData('es'), isTrue);
    });

    test('false for a well-formed locale intl carries no data for', () {
      expect(LumenFormats.hasLocaleData('zz_ZZ'), isFalse);
      // The one that surprises: intl has `de`, but no `de_DE` entry at all.
      expect(LumenFormats.hasLocaleData('de'), isTrue);
      expect(LumenFormats.hasLocaleData('de_DE'), isFalse);
    });

    test('false, rather than throwing, for junk', () {
      expect(LumenFormats.hasLocaleData('not a locale!!'), isFalse);
      expect(LumenFormats.hasLocaleData(''), isFalse);
    });

    // NOTE: "works before initializeDateFormatting has run" is NOT asserted
    // here — this file's setUpAll has already run it, so the assertion could
    // not fail. It is proved instead by `test/core/locale/locale_provider_test`
    // and `test/formatters/lumen_wire_test`, which format dates and never
    // initialise anything; `flutter test` gives each FILE its own isolate, so
    // a lazy-init regression turns both of them red with LocaleDataException.
  });

  // ---------------------------------------------------------------------------
  // decimalSeparator() / parseDecimal() — the READ side, added in P4b-T10
  // ---------------------------------------------------------------------------
  group('LumenFormats.decimalSeparator', () {
    test('it is the separator the same locale FORMATS with', () {
      // Stated against `decimal`'s own output rather than against a literal:
      // the two must agree, or a field would refuse the character the app
      // itself prints.
      expect(LumenFormats.decimalSeparator('es_ES'), ',');
      expect(LumenFormats.decimal(1.5, 'es_ES'), contains(','));

      expect(LumenFormats.decimalSeparator('en_US'), '.');
      expect(LumenFormats.decimal(1.5, 'en_US'), contains('.'));
    });
  });

  group('LumenFormats.parseDecimal', () {
    test('it reads back what the same locale wrote', () {
      // The round trip is the property worth having: screen 4 prefills a
      // stored weight through `decimal` and parses the edited text back.
      expect(
        LumenFormats.parseDecimal(LumenFormats.decimal(60.4, 'es_ES'), 'es_ES'),
        60.4,
      );
      expect(
        LumenFormats.parseDecimal(LumenFormats.decimal(60.4, 'en_US'), 'en_US'),
        60.4,
      );
    });

    test('the separator is the LOCALE\'s, not a fixed period', () {
      expect(LumenFormats.parseDecimal('60,4', 'es_ES'), 60.4);
      expect(LumenFormats.parseDecimal('60.4', 'en_US'), 60.4);
      // The control that makes the pair above a fact about the locale: a
      // `double.tryParse` that ignored the locale would answer 60.4 for the
      // es_ES row above and null here, and a parser that always stripped
      // commas would answer 604 for this one.
      expect(LumenFormats.parseDecimal('60.4', 'es_ES'), isNot(60.4));
    });

    test('an integer with no separator parses in either locale', () {
      expect(LumenFormats.parseDecimal('62', 'es_ES'), 62.0);
      expect(LumenFormats.parseDecimal('62', 'en_US'), 62.0);
    });

    test('junk is null, never a coerced number', () {
      // A field that cannot be read is an empty answer, not a zero: screen 4
      // sends nothing for a field it cannot parse, and the endpoint's MERGE
      // leaves the stored value alone.
      expect(LumenFormats.parseDecimal('', 'en_US'), isNull);
      expect(LumenFormats.parseDecimal('abc', 'en_US'), isNull);
      expect(LumenFormats.parseDecimal('.', 'en_US'), isNull);
      // Control: the same call with a readable string does answer.
      expect(LumenFormats.parseDecimal('7', 'en_US'), 7.0);
    });
  });
}
