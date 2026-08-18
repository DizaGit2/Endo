import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';

// ---------------------------------------------------------------------------
// The week start Flutter's OWN widgets read (P4b-T10)
// ---------------------------------------------------------------------------
//
// D-05 puts the first day of the week on the locale, and `LumenFormats`
// implements it — but only for grids Lumen draws itself. Every calendar that
// comes out of the framework (`DatePickerDialog`, `CalendarDatePicker`) reads
// `MaterialLocalizations.firstDayOfWeekIndex` instead, and this app wires no
// `localizationsDelegates`, so that resolves `DefaultMaterialLocalizations` —
// whose answer is 0, Sunday, for every locale (`material_localizations.dart:941`).
//
// The consequence, before this file existed: an es-ES user could step back from
// screen 4's date picker to screen 3's month grid and see two calendars one
// screen apart disagreeing about which column is Monday.
//
// **This is not the thing R-04 permits.** R-04 keeps P4b's UI strings English;
// its rationale names a hard-coded Sunday-first week as a *correctness* bug.
// The strings here stay the framework's own — nothing below authors copy.

/// [locale]'s first day of week, in the indexing Material uses.
///
/// `LumenFormats.firstDayOfWeek` answers a [DateTime] weekday constant, where
/// 1 is Monday and 7 is Sunday. Material indexes
/// [MaterialLocalizations.narrowWeekdays], which **begins at Sunday**: 0 is
/// Sunday and 6 is Saturday. `% 7` is exactly that re-indexing — it maps 7 to 0
/// and leaves 1..6 untouched.
///
/// **This is not the `weekday % 7` the formatting guard's header warns about.**
/// That one is a *leading-blank count* for a month grid, whose correct form is
/// `(weekday - firstDayOfWeek + 7) % 7` — a different quantity, computed in
/// [LumenFormats.leadingBlankDays]. This converts one weekday numbering into
/// another and is pinned in both conventions by
/// `test/core/locale/lumen_material_localizations_test.dart`.
int materialFirstDayOfWeekIndex(String locale) =>
    LumenFormats.firstDayOfWeek(locale) % 7;

/// [DefaultMaterialLocalizations] with the week start corrected, and nothing
/// else touched.
///
/// A subclass rather than a fresh implementation on purpose: every string
/// Material needs — `OK`, `Cancel`, the picker's help text, the month and
/// weekday names — keeps coming from the framework, so this class can never
/// become a place where UI copy is written.
///
/// It does not make the app localised. `flutter_localizations` is not a
/// dependency and P4b's copy is English by R-04; what this fixes is the one
/// piece of that default which is not a *string* but a *convention*, and which
/// Lumen already answers differently everywhere it draws a calendar itself.
class LumenMaterialLocalizations extends DefaultMaterialLocalizations {
  const LumenMaterialLocalizations({required this.firstDayOfWeekIndex});

  /// 0 = Sunday … 6 = Saturday. Build it with [materialFirstDayOfWeekIndex] —
  /// it is the only thing that knows how D-05's answer maps onto this one.
  @override
  final int firstDayOfWeekIndex;
}

/// Supplies [LumenMaterialLocalizations] to a subtree.
///
/// Reached through `Localizations.override(context:, delegates: [...])`, which
/// inserts a delegate at the FRONT of the ambient list
/// (`localizations.dart:528-533`) and loads only the first delegate per type
/// (`localizations.dart:57-66`) — so this wins over whatever `MaterialApp`
/// installed, for that subtree alone.
class LumenMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const LumenMaterialLocalizationsDelegate({required this.firstDayOfWeekIndex});

  /// 0 = Sunday … 6 = Saturday.
  final int firstDayOfWeekIndex;

  /// Every locale: what it overrides is a convention, not a translation, and
  /// the strings underneath are the framework's for all of them.
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // Synchronous, so `Localizations` resolves it in the same frame and no
    // widget below ever renders against the default it is replacing.
    return SynchronousFuture<MaterialLocalizations>(
      LumenMaterialLocalizations(firstDayOfWeekIndex: firstDayOfWeekIndex),
    );
  }

  @override
  bool shouldReload(LumenMaterialLocalizationsDelegate old) =>
      old.firstDayOfWeekIndex != firstDayOfWeekIndex;
}
