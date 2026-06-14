/// Locale-driven display formatters for Lumen (D-05) and unit-system enum (D-06).
///
/// **API payloads are always locale-neutral** (ISO 8601 dates, period decimal).
/// This file is for DISPLAY formatting only — never use these in serialisation.
///
/// ## Locale data initialisation
/// Call `initializeDateFormatting(locale)` from
/// `package:intl/date_symbol_data_local.dart` **before** using [LumenFormats.date]
/// or [LumenFormats.time] with a non-default locale. In tests, do this in
/// `setUpAll`. In app bootstrap, call it once per supported locale during startup.
library;

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
/// All methods are pure functions of their arguments; there is no mutable state.
///
/// ### First-day-of-week mapping (D-05)
/// The [firstDayOfWeek] mapping is explicit and documented rather than relying
/// on undocumented intl internals:
/// - Language `en` with country `US` (and bare `en` / `en_US`) → Sunday-first.
/// - Everything else (including `es`, `es_ES`, EU locales) → Monday-first.
/// This matches D-05 and can be extended by editing [_sundayFirstLocales].
abstract final class LumenFormats {
  // -------------------------------------------------------------------------
  // Date
  // -------------------------------------------------------------------------

  /// Returns a locale-aware short date string for [d].
  ///
  /// Uses [DateFormat.yMd] so locale conventions drive day/month ordering:
  /// - `es_ES` → `"7/3/2026"` (day/month/year)
  /// - `en_US` → `"3/7/2026"` (month/day/year)
  ///
  /// **Prerequisite:** call `initializeDateFormatting(locale)` before use.
  static String date(DateTime d, String locale) =>
      DateFormat.yMd(locale).format(d);

  // -------------------------------------------------------------------------
  // Time
  // -------------------------------------------------------------------------

  /// Returns a locale-aware time string for [d].
  ///
  /// Uses [DateFormat.jm] which respects each locale's clock convention:
  /// - `es_ES` → 24-hour `"16:30"` (no AM/PM marker)
  /// - `en_US` → 12-hour `"4:30 PM"`
  ///
  /// **Prerequisite:** call `initializeDateFormatting(locale)` before use.
  static String time(DateTime d, String locale) =>
      DateFormat.jm(locale).format(d);

  // -------------------------------------------------------------------------
  // Decimal
  // -------------------------------------------------------------------------

  /// Returns [value] formatted with [decimalDigits] decimal places using the
  /// decimal separator convention of [locale].
  ///
  /// - `es_ES` → comma separator: `"1,5"`
  /// - `en_US` → period separator: `"1.5"`
  static String decimal(
    num value,
    String locale, {
    int decimalDigits = 1,
  }) =>
      _numberFmt(value, locale, decimalDigits);

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

  /// Locale language codes (lower-case, underscore-separated) that use
  /// Sunday as the first day of the week per D-05.
  ///
  /// Currently only `en` with country `US` (and bare `en`) is Sunday-first.
  /// Extend this list when adding support for additional locales (e.g. `he`
  /// for Hebrew, `ar` for Arabic variants).
  static const List<String> _sundayFirstLocales = [
    'en',    // bare "en" and any en_XX except those overridden below
    'en_us', // explicit en_US — Sunday-first per D-05
  ];

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
