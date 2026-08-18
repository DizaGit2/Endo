/// Locale-NEUTRAL conversions for values leaving or entering the client.
///
/// [LumenFormats] is the display side: it is locale-driven, and a comma decimal
/// or a day-first date is exactly what it is for. This file is the other side of
/// the same boundary — **API payloads are always ISO-8601 and period-separated
/// (D-05)**, and a comma decimal reaching the backend is a defect.
///
/// Only the two fields whose rules do not survive codegen live here
/// (`docs/ARCHITECTURE.md` §C.0.2); everything else the generated serializers
/// already get right.
library;

/// Wire-format conversions. Never locale-aware, by construction: no method here
/// takes a locale, so there is nothing to pass one to.
abstract final class LumenWire {
  // -------------------------------------------------------------------------
  // weightKg — `number` / `format: double` on the wire (§C.0.2)
  // -------------------------------------------------------------------------

  /// Rounds [kg] to the ONE decimal place the backend accepts.
  ///
  /// The backend **rejects** more precision, it never rounds: `(0, 9999.9]`, at
  /// most one decimal, or a 400. Reading a stored value back is safe — Dart's
  /// shortest-round-trip printing renders `60.4` as `60.4` — but a *computed*
  /// one is not: a slider step or an lbs→kg conversion serialises as
  /// `0.30000000000000004`, and a two-decimal keyboard entry as `60.35`. Both
  /// are 400s. Call this immediately before building the request.
  ///
  /// Rounds half away from zero (`60.05 → 60.1`), matching what a user reading
  /// their own entry expects, rather than banker's rounding.
  ///
  /// The range is NOT enforced here: an out-of-range weight is a validation
  /// message on the field, not a silently altered number.
  static double weightKg(double kg) => (kg * 10).round() / 10;

  // -------------------------------------------------------------------------
  // diagnosedOn — `String?` of exact form `yyyy-MM` (§C.0.2)
  // -------------------------------------------------------------------------

  /// Parses the `yyyy-MM` wire form into the first day of that month, or
  /// returns `null` when [value] is absent or is not exactly that form.
  ///
  /// This exists because `diagnosedOn` is a `String?`, not a `Date?`: the
  /// contract deliberately does not declare `format: date`, because the
  /// generated `DateSerializer` calls `DateTime.parse`, which **throws** on
  /// `"2026-08"`. It is the only date-ish member on the P4a surface that must
  /// be parsed by hand.
  ///
  /// Strict on purpose — a full date, an unpadded month, or a month outside
  /// 1–12 all return `null` rather than being coerced. `DateTime(2026, 13)` is
  /// a legal Dart value meaning January 2027, so a lenient parser would show a
  /// user a year they never entered.
  static DateTime? parseDiagnosedOn(String? value) {
    if (value == null) return null;
    final match = _diagnosedOnPattern.firstMatch(value);
    if (match == null) return null;
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return null;
    return DateTime(int.parse(match.group(1)!), month);
  }

  /// Renders [year] and [month] as the exact `yyyy-MM` wire form.
  static String diagnosedOn(int year, int month) =>
      '${_pad(year, 4)}-${_pad(month, 2)}';

  /// `yyyy-MM`, anchored at both ends so `"2026-08-01"` cannot match a prefix.
  static final RegExp _diagnosedOnPattern = RegExp(r'^(\d{4})-(\d{2})$');

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');
}
