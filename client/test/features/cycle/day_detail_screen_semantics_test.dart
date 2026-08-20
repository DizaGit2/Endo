// Semantics for screen 11 (P4b-T16, READ SURFACE ONLY).
//
// Screen 11 draws exactly ONE control — the back chevron (the period-event
// and day-log editors are T16b). That makes the positive/negative controls
// unusually sharp: `kAnyButtonSemantics` should find exactly 1 node on this
// screen, always the back button, never a day cell's own content or a
// symptom row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/presentation/day_detail_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';

import '../../support/harness.dart';

class _SettledDayDetail extends DayDetailController {
  _SettledDayDetail(this.view) : super(view.date);

  final DayDetailView view;

  @override
  Future<DayDetailView> build() async => view;
}

Future<void> _pump(WidgetTester tester, DateTime date, DayDetailView view) {
  return pumpApp(
    tester,
    home: DayDetailScreen(date: date),
    overrides: [
      dayDetailControllerProvider(
        date,
      ).overrideWith(() => _SettledDayDetail(view)),
    ],
  );
}

void main() {
  final date = DateTime(2026, 4, 7);

  group('the back button — the ONLY control on this screen', () {
    testWidgetsWithSemantics(
      'is labeled "Back" and carries a real tap action',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expectLabeledButton(
          tester,
          find.widgetWithIcon(IconButton, Icons.chevron_left),
          'Back',
          exactLabel: true,
        );
      },
    );

    testWidgetsWithSemantics(
      'is the ONLY button on the whole screen — no day cell, no symptom '
      'row, no section header announces itself as one',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: cycleDayLogFixture(pain: 4, mood: 2, notes: 'A note.'),
            symptoms: [symptomResponseFixture()],
            symptomsTotal: 1,
          ),
        );

        expect(
          kAnyButtonSemantics,
          findsNWidgets(1),
          reason:
              'only the back chevron should be a button; T16 writes nothing '
              'and offers no other action (Edit/+Add are cut — R-10)',
        );
      },
    );
  });

  group('no dingbats', () {
    testWidgetsWithSemantics('a fully-populated day renders no dingbats', (
      tester,
    ) async {
      await _pump(
        tester,
        date,
        DayDetailView(
          date: date,
          log: cycleDayLogFixture(pain: 4, mood: 2, notes: 'A note.'),
          symptoms: [
            symptomResponseFixture(
              symptomCode: 'bloating',
              intensity: 5,
              region: 'lower_back',
              painTypes: const ['cramping'],
              triggers: const ['food'],
            ),
          ],
          symptomsTotal: 1,
        ),
      );

      expectNoDingbats(tester, screen: 'DayDetailScreen');
    });

    testWidgetsWithSemantics('the empty-day state renders no dingbats', (
      tester,
    ) async {
      await _pump(
        tester,
        date,
        DayDetailView(
          date: date,
          log: null,
          symptoms: const [],
          symptomsTotal: 0,
        ),
      );

      expectNoDingbats(tester, screen: 'DayDetailScreen');
    });
  });

  group('the day header', () {
    testWidgetsWithSemantics('renders the weekday and "month day" strings', (
      tester,
    ) async {
      // 2026-04-07 is a Tuesday.
      await _pump(
        tester,
        date,
        DayDetailView(
          date: date,
          log: null,
          symptoms: const [],
          symptomsTotal: 0,
        ),
      );

      expect(find.text('TUESDAY'), findsOneWidget);
      expect(find.text('April 7'), findsOneWidget);
    });

    testWidgetsWithSemantics('renders no phase badge — no data source exists', (
      tester,
    ) async {
      await _pump(
        tester,
        date,
        DayDetailView(
          date: date,
          log: null,
          symptoms: const [],
          symptomsTotal: 0,
        ),
      );

      expect(find.textContaining('Luteal'), findsNothing);
      expect(find.textContaining('Day 20'), findsNothing);
    });
  });

  group('the empty state', () {
    testWidgetsWithSemantics(
      'log:null with empty symptoms renders the empty-day message, not an '
      'error',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('Nothing logged for this day.'), findsOneWidget);
        expect(find.byType(LumenErrorRetry), findsNothing);
      },
    );

    testWidgetsWithSemantics(
      'a day with ONLY a note (no pain/mood/symptoms) does not render the '
      'empty state',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: cycleDayLogFixture(pain: null, mood: null, notes: 'Hi.'),
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('Nothing logged for this day.'), findsNothing);
        expect(find.text('Hi.'), findsOneWidget);
      },
    );
  });

  group('D-08 — 0 is a real datum, never falsiness-tested away', () {
    testWidgetsWithSemantics('pain: 0 renders a "0/10" row, not nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        date,
        DayDetailView(
          date: date,
          log: cycleDayLogFixture(pain: 0, mood: null),
          symptoms: const [],
          symptomsTotal: 0,
        ),
      );

      expect(find.text('Pain'), findsOneWidget);
      expect(find.text('0/10'), findsOneWidget);
      expect(find.text('Nothing logged for this day.'), findsNothing);
    });

    testWidgetsWithSemantics(
      'a symptom with intensity: 0 renders a "0/10" row',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: null,
            symptoms: [symptomResponseFixture(intensity: 0)],
            symptomsTotal: 1,
          ),
        );

        expect(find.text('0/10'), findsOneWidget);
      },
    );

    testWidgetsWithSemantics(
      'a symptom with intensity: null renders NO "N/10" text at all — never '
      'a fabricated 0/10',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: null,
            symptoms: [symptomResponseFixture(intensity: null)],
            symptomsTotal: 1,
          ),
        );

        expect(find.textContaining('/10'), findsNothing);
      },
    );
  });

  group('truncation is visible', () {
    testWidgetsWithSemantics(
      'total greater than the returned count renders a plain count line',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: null,
            symptoms: [
              symptomResponseFixture(id: '1'),
              symptomResponseFixture(id: '2'),
            ],
            symptomsTotal: 5,
          ),
        );

        expect(
          find.text('Showing 2 of 5 symptoms logged today.'),
          findsOneWidget,
        );
      },
    );

    testWidgetsWithSemantics(
      'total equal to the returned count renders NO count line',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: null,
            symptoms: [symptomResponseFixture()],
            symptomsTotal: 1,
          ),
        );

        expect(find.textContaining('Showing'), findsNothing);
      },
    );
  });

  group('chips render only from the ratified vocabulary', () {
    testWidgetsWithSemantics('region, painTypes and triggers render as chips', (
      tester,
    ) async {
      await _pump(
        tester,
        date,
        DayDetailView(
          date: date,
          log: null,
          symptoms: [
            symptomResponseFixture(
              region: 'lower_back',
              painTypes: const ['cramping'],
              triggers: const ['food'],
            ),
          ],
          symptomsTotal: 1,
        ),
      );

      expect(find.text('Lower back'), findsOneWidget);
      expect(find.text('Cramping'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
    });

    testWidgetsWithSemantics('"unspecified" region never renders as a chip', (
      tester,
    ) async {
      await _pump(
        tester,
        date,
        DayDetailView(
          date: date,
          log: null,
          symptoms: [symptomResponseFixture(region: 'unspecified')],
          symptomsTotal: 1,
        ),
      );

      expect(find.text('Unspecified'), findsNothing);
      expect(find.textContaining('unspecified'), findsNothing);
    });

    testWidgetsWithSemantics(
      'a code outside the ratified vocabulary is dropped, never shown as '
      'raw text — the mockup\'s own "After lunch" is exactly this shape '
      '(free text in no ratified trigger set)',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            date: date,
            log: null,
            symptoms: [
              symptomResponseFixture(
                region: 'made_up_region',
                painTypes: const ['made_up_type'],
                triggers: const ['after_lunch'],
              ),
            ],
            symptomsTotal: 1,
          ),
        );

        expect(find.text('made_up_region'), findsNothing);
        expect(find.text('made_up_type'), findsNothing);
        expect(find.text('after_lunch'), findsNothing);
        expect(find.textContaining('lunch'), findsNothing);
      },
    );
  });
}
