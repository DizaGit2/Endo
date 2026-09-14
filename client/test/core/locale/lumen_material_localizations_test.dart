// LumenMaterialLocalizations — the week start Flutter's own widgets read
// (P4b-T10, fix round).
//
// R-04 keeps every UI string English in P4b. It does NOT permit a hard-coded
// week start: its rationale calls Sunday-first a CORRECTNESS bug, and screen 3
// already rotates its grid off `LumenFormats.firstDayOfWeek`. But
// `MaterialApp` wires no `localizationsDelegates`, so every Material widget
// that draws a calendar — `DatePickerDialog` on screen 4, and whatever screens
// 10/11/14 reach for — resolves `DefaultMaterialLocalizations`, whose
// `firstDayOfWeekIndex` is 0 (Sunday) for every locale on earth.
//
// This file pins the mapping and pins the inheritance: the override changes the
// week start and NOTHING else.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/lumen_material_localizations.dart';

void main() {
  group('materialFirstDayOfWeekIndex', () {
    test('it is LumenFormats.firstDayOfWeek in Material\'s own indexing', () {
      // `DateTime` counts 1 = Monday … 7 = Sunday. Material indexes
      // `narrowWeekdays`, which BEGINS at Sunday: 0 = Sunday … 6 = Saturday.
      // Stated against `LumenFormats` rather than against literals so the two
      // cannot drift — D-05 lives there, and this is only a re-indexing of it.
      expect(LumenFormats.firstDayOfWeek('es-ES'), DateTime.monday);
      expect(materialFirstDayOfWeekIndex('es-ES'), 1);

      expect(LumenFormats.firstDayOfWeek('en-US'), DateTime.sunday);
      expect(materialFirstDayOfWeekIndex('en-US'), 0);
    });

    test('every locale lands on a real Material index', () {
      // The conversion is a re-indexing, not an arithmetic coincidence: for
      // each of the seven ISO weekdays the answer must be the slot Material
      // would read that day out of `narrowWeekdays` at.
      final narrow = const DefaultMaterialLocalizations().narrowWeekdays;
      expect(narrow.length, 7, reason: 'premise: Material indexes seven slots');
      for (final locale in <String>['es-ES', 'en-US', 'en-GB', 'fr-FR', 'de']) {
        final index = materialFirstDayOfWeekIndex(locale);
        expect(
          index,
          inInclusiveRange(0, narrow.length - 1),
          reason: '$locale must name a real slot of narrowWeekdays',
        );
      }
      // …and the two conventions the app actually ships disagree, so the
      // function is not a constant wearing a parameter.
      expect(
        materialFirstDayOfWeekIndex('es-ES'),
        isNot(materialFirstDayOfWeekIndex('en-US')),
      );
    });
  });

  group('LumenMaterialLocalizations', () {
    test('it changes the week start and inherits everything else', () {
      const spanish = LumenMaterialLocalizations(firstDayOfWeekIndex: 1);
      const fallback = DefaultMaterialLocalizations();

      expect(spanish.firstDayOfWeekIndex, 1);
      // The control: the default it is derived from says 0, so the line above
      // is a fact about the override rather than about a value that was
      // already there.
      expect(fallback.firstDayOfWeekIndex, 0);

      // Inherited, not re-authored. This class must never become a place
      // where UI copy is written — R-04 keeps P4b's strings English and these
      // are the framework's own.
      expect(spanish.okButtonLabel, fallback.okButtonLabel);
      expect(spanish.cancelButtonLabel, fallback.cancelButtonLabel);
      expect(spanish.datePickerHelpText, fallback.datePickerHelpText);
      expect(spanish.narrowWeekdays, fallback.narrowWeekdays);
    });

    testWidgets('the delegate wins over the ambient MaterialLocalizations', (
      tester,
    ) async {
      late MaterialLocalizations ambient;
      late MaterialLocalizations overridden;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              ambient = MaterialLocalizations.of(context);
              return Localizations.override(
                context: context,
                delegates: const <LocalizationsDelegate<dynamic>>[
                  LumenMaterialLocalizationsDelegate(firstDayOfWeekIndex: 1),
                ],
                child: Builder(
                  builder: (BuildContext context) {
                    overridden = MaterialLocalizations.of(context);
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
        ),
      );

      // Premise: without the override the app really does answer Sunday — this
      // is the bug being fixed, not a hypothetical.
      expect(ambient.firstDayOfWeekIndex, 0);
      expect(overridden.firstDayOfWeekIndex, 1);
      // …and it is still the same vocabulary underneath.
      expect(overridden.okButtonLabel, ambient.okButtonLabel);
    });
  });
}
