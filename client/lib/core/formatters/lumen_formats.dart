/// Locale-driven display formatters for Lumen (D-05) and unit-system enum (D-06).
///
/// **API payloads are always locale-neutral** (ISO 8601 dates, period decimal).
/// This file is for DISPLAY formatting only — never use these in serialisation.
/// The other side of that boundary is `lumen_wire.dart` (`LumenWire`), which is
/// locale-neutral by construction: nothing in it takes a locale.
///
/// The locale itself comes from `localeProvider` (`core/locale/`), never from a
/// literal — `test/core/locale/formatting_guard_test.dart` fails the build on
/// both mistakes.
///
/// ## Locale data initialisation
/// Handled here: every **date/time** entry point ([date], [monthYear], [time],
/// [hasLocaleData]) calls [LumenFormats.ensureLocaleData] first, which is
/// idempotent and does its work synchronously. Callers do **not** need a
/// `setUpAll` or a bootstrap step — before P4b-T6 they did, and forgetting it
/// threw `LocaleDataException` from deep inside `intl` at the first date a
/// screen rendered.
///
/// The number formatters ([decimal], [mass], [length], [percent]) do not call
/// it and do not need to: `intl`'s `numberFormatSymbols` is a plain const map
/// that is always populated, whereas its date symbols start as an
/// `UninitializedLocaleData` that throws on lookup. Calling it there would pull
/// the whole date-symbol table into a process that only ever formats a number.
///
/// `initializeDateFormatting` ignores its `locale` argument (see
/// `date_symbol_data_local.dart`: *"Both the [locale] and [ignored] parameter
/// are ignored, as the data for all locales is directly available"*), so one
/// call covers every locale and there is no per-locale bootstrap to keep in
/// sync with `localeProvider`.
library;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Unit-system enum (D-06)
// ---------------------------------------------------------------------------

/// Supported unit systems for measurement display.
///
/// **Default is [metric]** (kg / cm / %).
/// [imperial] is **RESERVED** per decision D-06 and is NOT implemented in v1.
/// Formatters that receive [imperial] will throw [UnimplementedError].
/// Imperial display support is deferred to phase 2.
enum UnitSystem {
  /// SI metric units: kg, cm, % (v1 default).
  metric,

  /// Imperial units: lb, ft/in (RESERVED — not implemented in v1 per D-06).
  imperial,
}

// ---------------------------------------------------------------------------
// Formatter surface (D-05)
// ---------------------------------------------------------------------------

/// Static locale-driven formatters for dates, times, numbers, and measurements.
///
/// Every method's result is a pure function of its arguments. The one piece of
/// state is [LumenFormats._localeDataLoaded], a latch over `intl`'s one-time
/// data load — it changes what the first call *does*, never what any call
/// *returns*.
///
/// ### First-day-of-week mapping (D-05)
/// The [firstDayOfWeek] mapping is explicit and documented rather than relying
/// on undocumented intl internals:
/// - Language `en` with country `US` (and bare `en` / `en_US`) → Sunday-first.
/// - Everything else (including `es`, `es_ES`, EU locales) → Monday-first.
/// This matches D-05 and can be extended by editing [_sundayFirstLocales].
abstract final class LumenFormats {
  // -------------------------------------------------------------------------
  // Locale data
  // -------------------------------------------------------------------------

  /// Whether `intl` carries date **and** number data for [locale].
  ///
  /// This is what the locale resolver leans on to guarantee that whatever
  /// `localeProvider` returns can actually be formatted with: `DateFormat`
  /// throws `ArgumentError('Invalid locale …')` for a tag it has no data for,
  /// and that would surface as a crash on a screen rather than as a fallback.
  ///
  /// Note the asymmetry that catches people out: `intl` has `de` but **no**
  /// `de_DE` entry, so a caller must be willing to shorten a tag rather than
  /// treat a `false` here as "this language is unsupported".
  static bool hasLocaleData(String locale) {
    ensureLocaleData();
    return DateFormat.localeExists(locale) && NumberFormat.localeExists(locale);
  }

  /// Loads `intl`'s locale data once, synchronously.
  ///
  /// `initializeDateFormatting` returns a `Future` but performs its work before
  /// returning it, so awaiting is unnecessary — and being able to skip the
  /// await is what lets a widget format a date during `build`.
  static void ensureLocaleData() {
    if (_localeDataLoaded) return;
    initializeDateFormatting();
    // Latched AFTER the call, not before: setting it first would mean that a
    // throw inside `initializeDateFormatting` disables initialisation
    // permanently, and every later call returns early into a formatter that
    // then throws `LocaleDataException` for the rest of the process.
    _localeDataLoaded = true;
  }

  static bool _localeDataLoaded = false;

  // -------------------------------------------------------------------------
  // Date
  // -------------------------------------------------------------------------

  /// Returns a locale-aware short date string for [d].
  ///
  /// Uses [DateFormat.yMd] so locale conventions drive day/month ordering:
  /// - `es_ES` → `"7/3/2026"` (day/month/year)
  /// - `en_US` → `"3/7/2026"` (month/day/year)
  static String date(DateTime d, String locale) {
    ensureLocaleData();
    return DateFormat.yMd(locale).format(d);
  }

  /// Returns a locale-aware **month-precision** string for [d] — the display
  /// side of `diagnosedOn`, which is a `yyyy-MM` string on the wire and has no
  /// day to render (§C.0.2).
  ///
  /// Numeric on purpose ([DateFormat.yM], `"8/2026"`): a month NAME would put
  /// a translated word into a UI whose strings stay English in P4b (R-04).
  static String monthYear(DateTime d, String locale) {
    ensureLocaleData();
    return DateFormat.yM(locale).format(d);
  }

  /// Returns `"April 2026"` — an English month name plus the year — for [d].
  ///
  /// **No [locale] parameter, on purpose.** Screen 10 (the cycle calendar) is
  /// the one screen whose title needs a month NAME rather than [monthYear]'s
  /// numeric form — a numeric `"4/2026"` is right for `diagnosedOn`, which this
  /// formatter is not for. Naming the month is exactly the move [monthYear]'s
  /// own dartdoc rules out for a translated word (R-04: every string in P4b
  /// stays English), so this formatter cannot honestly take a locale — there is
  /// nothing for one to select between. That is the same split T6 already made
  /// for [orderedWeekdays]: the **locale** decides the week's *order* (D-05),
  /// the **app** owns the *words*. A screen wanting locale-ordered digits still
  /// has [monthYear]; this is for the one screen that needs the name instead.
  static String monthName(DateTime d) =>
      '${_englishMonths[d.month - 1]} ${d.year}';

  /// English month names, indexed by `DateTime.month - 1`. Not translated, and
  /// not meant to be — see [monthName].
  static const List<String> _englishMonths = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Returns `"Tuesday"` — the English weekday name for [d].
  ///
  /// **No [locale] parameter, on purpose — exactly [monthName]'s reasoning.**
  /// Screen 11 (the day detail) is the one screen whose header needs a
  /// weekday NAME rather than a numeric or locale-ordered form, and R-04
  /// keeps every P4b string English — there is nothing for a locale to
  /// select between, so this formatter cannot honestly take one. This is
  /// the same split [orderedWeekdays] already makes for the WEEK's order:
  /// the locale decides which day starts the week (D-05), the app owns the
  /// day's name.
  ///
  /// [DateTime.weekday] is `1` (Monday) through `7` (Sunday); indexed
  /// directly rather than reaching for `intl`'s `DateFormat.EEEE`, which
  /// would pull in a translated name this app does not want.
  static String weekdayName(DateTime d) => _englishWeekdays[d.weekday - 1];

  /// English weekday names, indexed by `DateTime.weekday - 1` (Monday
  /// first). Not translated, and not meant to be — see [weekdayName].
  static const List<String> _englishWeekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// Returns `"April 7"` — an English month name plus the day, no year — for
  /// [d].
  ///
  /// **No [locale] parameter** — same reasoning as [monthName]. Screen 11's
  /// header needs a month-and-day form with no year: not [date]
  /// (`DateFormat.yMd`, which is locale-ordered, numeric, AND carries a
  /// year screen 11 has no room for) and not [monthName] (which carries the
  /// year, not the day) — a third shape neither existing formatter makes.
  static String monthDay(DateTime d) =>
      '${_englishMonths[d.month - 1]} ${d.day}';

  // -------------------------------------------------------------------------
  // Time
  // -------------------------------------------------------------------------

  /// Returns a locale-aware time string for [d].
  ///
  /// Uses [DateFormat.jm] which respects each locale's clock convention:
  /// - `es_ES` → 24-hour `"16:30"` (no AM/PM marker)
  /// - `en_US` → 12-hour `"4:30 PM"`
  static String time(DateTime d, String locale) {
    ensureLocaleData();
    return DateFormat.jm(locale).format(d);
  }

  // -------------------------------------------------------------------------
  // Decimal
  // -------------------------------------------------------------------------

  /// Returns [value] formatted with [decimalDigits] decimal places using the
  /// decimal separator convention of [locale].
  ///
  /// - `es_ES` → comma separator: `"1,5"`
  /// - `en_US` → period separator: `"1.5"`
  static String decimal(num value, String locale, {int decimalDigits = 1}) =>
      _numberFmt(value, locale, decimalDigits);

  // -------------------------------------------------------------------------
  // Reading a typed number back (P4b-T10)
  // -------------------------------------------------------------------------

  /// The character [locale] separates a number's fraction with — `","` under
  /// `es_ES`, `"."` under `en_US`.
  ///
  /// Taken from the same `intl` symbols [decimal] formats with, so a field that
  /// only accepts this character can never refuse what the app itself printed
  /// into it.
  ///
  /// It is here rather than in a screen because `NumberFormat` may be named in
  /// this file alone (`test/core/locale/formatting_guard_test.dart`), and
  /// because a screen that hard-coded `'.'` would silently reject the comma a
  /// Spanish keyboard puts under the user's thumb.
  static String decimalSeparator(String locale) =>
      NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

  /// Reads [text] as a number written in [locale]'s own convention, or `null`
  /// when it is not one.
  ///
  /// The inverse of [decimal], and the reason it takes a locale at all: `"60,4"`
  /// is sixty-point-four in `es_ES` and `double.tryParse` answers `null` for it,
  /// while a client that stripped commas first would read it as six hundred and
  /// four in `en_US`.
  ///
  /// **Null, never zero, for unreadable input.** A field that cannot be read is
  /// an unanswered field: screen 4 sends nothing for it, and the endpoint's
  /// MERGE leaves whatever is stored alone. A coerced `0` would be a datum the
  /// user never gave.
  ///
  /// This is a DISPLAY-side entry point (it reads what a person typed); the
  /// value it returns still goes through `LumenWire` before it is serialised.
  static double? parseDecimal(String text, String locale) {
    try {
      return NumberFormat.decimalPattern(locale).parse(text).toDouble();
    } on FormatException {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // First day of week
  // -------------------------------------------------------------------------

  /// Explicitly maps locales to their first day of week per D-05.
  ///
  /// Returns [DateTime.sunday] (7) for `en` / `en_US`; [DateTime.monday] (1)
  /// for everything else (including `es`, `es_ES`, EU locales).
  ///
  /// This is an explicit, documented mapping — not derived from intl internals —
  /// so it is predictable, testable, and easy to extend.
  ///
  /// To add a new Sunday-first locale, add it to [_sundayFirstLocales].
  static int firstDayOfWeek(String locale) {
    // Normalise to lower-case, replace hyphens with underscores.
    final normalised = locale.toLowerCase().replaceAll('-', '_');
    for (final pattern in _sundayFirstLocales) {
      if (normalised == pattern || normalised.startsWith('${pattern}_')) {
        return DateTime.sunday;
      }
    }
    return DateTime.monday;
  }

  /// Locale identifiers (lower-case, underscore-separated) that use Sunday as
  /// the first day of the week per D-05.
  ///
  /// Only `en_US` is Sunday-first in v1. Other English locales (en_GB, en_AU,
  /// en_CA, en_IE, and bare `en`) are Monday-first and therefore fall through
  /// to the [DateTime.monday] default — do NOT add a bare `en` entry here, as
  /// that would wrongly classify those Monday-first English regions as
  /// Sunday-first. Extend this list per-locale when adding support (e.g. `he`,
  /// `ar` variants).
  static const List<String> _sundayFirstLocales = [
    'en_us', // explicit en_US — Sunday-first per D-05
  ];

  /// The seven [DateTime] weekday constants in the order [locale] displays a
  /// week, starting at [firstDayOfWeek].
  ///
  /// - `es_ES` → `[1, 2, 3, 4, 5, 6, 7]` (Monday … Sunday)
  /// - `en_US` → `[7, 1, 2, 3, 4, 5, 6]` (Sunday … Saturday)
  ///
  /// Weekday **labels** are deliberately not returned. P4b keeps every UI string
  /// English (ruling R-04), so a screen owns its own seven labels and indexes
  /// them by this order — the grid rotates without a single string being
  /// translated. The mockups' fixed `S M T W T F S` header is an English
  /// artifact, not the spec (D-05).
  static List<int> orderedWeekdays(String locale) {
    final first = firstDayOfWeek(locale);
    return List<int>.generate(7, (i) => ((first - 1 + i) % 7) + 1);
  }

  /// How many empty cells precede the 1st of [monthStart]'s month in a
  /// [locale]-ordered month grid. Always `0..6`.
  ///
  /// April 2026 begins on a Wednesday, so it is **2** under `es_ES`
  /// (Monday-first) and **3** under `en_US` (Sunday-first). Getting this
  /// constant wrong shifts every date in the grid by a column, which is why it
  /// lives here once rather than in each of screens 3, 10 and 11.
  ///
  /// Only [DateTime.weekday] is read, so passing any day of the month gives the
  /// answer for the month it belongs to **only if** it is the 1st — pass the
  /// 1st.
  static int leadingBlankDays(DateTime monthStart, String locale) =>
      (monthStart.weekday - firstDayOfWeek(locale) + 7) % 7;

  // -------------------------------------------------------------------------
  // Measurement formatters — metric only (D-06)
  // -------------------------------------------------------------------------

  /// Returns [kg] formatted with 1 decimal place and a `" kg"` suffix using
  /// the decimal separator of [locale].
  ///
  /// Example: `mass(60.4, 'es_ES')` → `"60,4 kg"`, `mass(60.4, 'en_US')` → `"60.4 kg"`.
  ///
  /// [system] must be [UnitSystem.metric] (the default). Passing
  /// [UnitSystem.imperial] throws [UnimplementedError] — imperial display is
  /// deferred to phase 2 per D-06.
  static String mass(
    double kg,
    String locale, {
    UnitSystem system = UnitSystem.metric,
  }) {
    _assertMetric(system, 'mass');
    return '${_numberFmt(kg, locale, 1)} kg';
  }

  /// Returns [cm] formatted with 0 decimal places and a `" cm"` suffix.
  ///
  /// Example: `length(165.0, 'en_US')` → `"165 cm"`.
  ///
  /// [system] must be [UnitSystem.metric] (the default). Passing
  /// [UnitSystem.imperial] throws [UnimplementedError] per D-06.
  static String length(
    double cm,
    String locale, {
    UnitSystem system = UnitSystem.metric,
  }) {
    _assertMetric(system, 'length');
    return '${_numberFmt(cm, locale, 0)} cm';
  }

  /// Returns [pct] formatted with 1 decimal place and a `" %"` suffix using
  /// the decimal separator of [locale].
  ///
  /// Example: `percent(23.5, 'es_ES')` → `"23,5 %"`.
  static String percent(double pct, String locale) =>
      '${_numberFmt(pct, locale, 1)} %';

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Formats [value] with [decimalDigits] decimal places using [locale]'s
  /// number symbols (decimal point, grouping separator).
  static String _numberFmt(num value, String locale, int decimalDigits) {
    final fmt = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: decimalDigits,
    );
    return fmt.format(value);
  }

  /// Throws [UnimplementedError] if [system] is not [UnitSystem.metric].
  static void _assertMetric(UnitSystem system, String formatterName) {
    if (system != UnitSystem.metric) {
      throw UnimplementedError(
        'imperial display deferred to phase 2 (D-06) — '
        '$formatterName does not support UnitSystem.imperial in v1.',
      );
    }
  }
}
