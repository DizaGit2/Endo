// Semantics for screen 11 (P4b-T16 read surface; P4b-T16b's day-log
// affordance; P4b-T16c's Period section and period-editor affordance).
//
// **The button-count claim is RAISED BY NAMING, never by loosening.** Through
// T16 this screen drew exactly ONE control; T16b made it TWO; T16c makes it
// THREE. Each time, the sharpness is preserved by identifying every button, so
// a fourth one (a revived `Edit`, a symptom row that became tappable, a section
// header that announced itself) still fails.
//
// The three controls, and nothing else, are:
//   1. the back chevron;
//   2. `kDayDetailEditLogLabel`, which opens the day-log editor sheet;
//   3. `kDayDetailEditPeriodLabel`, which opens the period-event editor sheet.
//
// Still CUT, and asserted as cut below: the mockup's `Edit` (RULING T20-B —
// `PUT /symptoms/{id}` does not exist) and `+ Add to this day` (RULING
// T16-K — screen 12 hard-codes the server's today, so a past day's affordance
// pointed at it would silently log to the wrong day).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/cycle/presentation/day_detail_screen.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/features/cycle/presentation/day_log_editor_screen.dart';
import 'package:lumen/features/cycle/presentation/period_editor_screen.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _SettledDayDetail extends DayDetailController {
  _SettledDayDetail(this.view) : super(view.date);

  final DayDetailView view;

  @override
  Future<DayDetailView> build() async => view;
}

class _MockCycleRepository extends Mock implements CycleRepository {}

class _MockSymptomsRepository extends Mock implements SymptomsRepository {}

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

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  group('the three controls on this screen, and nothing else', () {
    testWidgetsWithSemantics(
      'the back chevron carries a real tap action, named by '
      'MaterialLocalizations rather than by hand-written copy',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        // `backButtonTooltip` resolves to 'Back' under the `en` fallback the
        // harness runs in, so the string is unchanged from T16 — what moved
        // is where it comes from.
        expectLabeledButton(
          tester,
          find.widgetWithIcon(IconButton, Icons.chevron_left),
          'Back',
          exactLabel: true,
        );
      },
    );

    testWidgetsWithSemantics(
      'the chevron is IN THE LAYOUT, above the scroll view — nothing that '
      'scrolls can come to rest under its corner and lose its taps',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: cycleDayLogFixture(pain: 4, mood: 2, notes: 'A note.'),
            symptoms: [symptomResponseFixture()],
            symptomsTotal: 1,
          ),
        );

        expect(
          find.ancestor(
            of: find.widgetWithIcon(IconButton, Icons.chevron_left),
            matching: find.byType(Stack),
          ),
          findsNothing,
          reason:
              'a Positioned overlay is what T20b measured a real tap-miss '
              'against on screen 12; the chevron is a Column child here',
        );

        final chevron = tester.getRect(
          find.widgetWithIcon(IconButton, Icons.chevron_left),
        );
        final scroller = tester.getRect(find.byType(SingleChildScrollView));
        expect(
          chevron.bottom,
          lessThanOrEqualTo(scroller.top + 0.5),
          reason: 'the chevron and the scroll view must not overlap at all',
        );
      },
    );

    testWidgetsWithSemantics(
      'a fully-populated day announces exactly THREE buttons — the chevron, '
      'the day-log editor and the period editor. No day cell, no symptom row, '
      'no period row and no section header announces itself as one, and '
      'neither cut affordance is back.',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: <CycleEventResponse>[
              cycleEventFixture(
                id: 'evt-1',
                kind: 'period_start',
                flowIntensity: 3,
                notes: 'started overnight',
              ),
            ],
            date: date,
            log: cycleDayLogFixture(pain: 4, mood: 2, notes: 'A note.'),
            symptoms: [symptomResponseFixture()],
            symptomsTotal: 1,
          ),
        );

        expect(
          kAnyButtonSemantics,
          findsNWidgets(3),
          reason:
              'the back chevron, kDayDetailEditLogLabel and '
              'kDayDetailEditPeriodLabel, and nothing else. The period ROWS '
              'are read-only and must not have become tappable. If this went '
              'to 4, name the fourth one here rather than raising the number.',
        );
        expectLabeledButton(
          tester,
          find.widgetWithIcon(IconButton, Icons.chevron_left),
          'Back',
          exactLabel: true,
        );
        expectLabeledButton(
          tester,
          find.text(kDayDetailEditLogLabel),
          kDayDetailEditLogLabel,
        );
        expectLabeledButton(
          tester,
          find.text(kDayDetailEditPeriodLabel),
          kDayDetailEditPeriodLabel,
        );
      },
    );

    testWidgetsWithSemantics(
      'the mockup\'s two drawn edit affordances stay CUT — `Edit` (T20-B: '
      'no PUT /symptoms/{id}) and `+ Add to this day` (T16-K: screen 12 '
      'writes the SERVER\'s today, so a past day\'s button would fabricate '
      'the date)',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: cycleDayLogFixture(pain: 4, mood: 2, notes: 'A note.'),
            symptoms: [symptomResponseFixture()],
            symptomsTotal: 1,
          ),
        );

        expect(find.text('Edit'), findsNothing);
        expect(find.textContaining('Add to this day'), findsNothing);
      },
    );

    testWidgetsWithSemantics(
      'the editor affordance is offered on an EMPTY day too — the endpoint '
      'upserts, so a day with nothing on it is exactly as writable, and '
      'hiding it there would leave the empty state with no way forward',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('Nothing logged for this day.'), findsOneWidget);
        expect(find.text(kDayDetailEditLogLabel), findsOneWidget);
        expect(
          find.text(kDayDetailEditPeriodLabel),
          findsOneWidget,
          reason:
              'a day with no period event is exactly the day a first one gets '
              'logged on',
        );
      },
    );

    testWidgetsWithSemantics(
      'tapping it opens the day-log editor sheet',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: cycleDayLogFixture(pain: 4, mood: 2),
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        await tester.tap(find.text(kDayDetailEditLogLabel));
        await tester.pumpAndSettle();

        expect(find.byType(DayLogEditorScreen), findsOneWidget);
        expect(find.text(kDayLogEditorMergeNote), findsOneWidget);
      },
    );

    testWidgetsWithSemantics(
      'tapping the period affordance opens the PERIOD editor sheet, which is '
      'a different sheet saying the OPPOSITE rule',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        await tester.tap(find.text(kDayDetailEditPeriodLabel));
        await tester.pumpAndSettle();

        expect(find.byType(PeriodEditorScreen), findsOneWidget);
        expect(find.byType(DayLogEditorScreen), findsNothing);
        expect(find.text(kPeriodEditorUpsertNote), findsOneWidget);
        expect(
          find.text(kDayLogEditorMergeNote),
          findsNothing,
          reason:
              'the two sheets state opposite rules and must never share copy',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The Period section (P4b-T16c) — the read the editor has no data without
  // ---------------------------------------------------------------------------

  group('the Period section', () {
    testWidgetsWithSemantics(
      'EMPTY STATE — a day with no cycle events renders no Period section at '
      'all: no label, no row, no placeholder',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: cycleDayLogFixture(pain: 4, mood: 2),
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('PERIOD'), findsNothing);
        for (final label in const <String>[
          'Period start',
          'Period end',
          'Spotting',
          'Light',
          'Medium',
          'Heavy',
        ]) {
          expect(find.text(label), findsNothing);
        }
      },
    );

    testWidgetsWithSemantics(
      'HAS-EVENT STATE — the section renders one row per event, in the '
      'SERVER\'s order, with each event\'s own kind, flow chip and note',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: <CycleEventResponse>[
              cycleEventFixture(
                id: 'evt-end',
                kind: 'period_end',
                flowIntensity: 1,
              ),
              cycleEventFixture(
                id: 'evt-start',
                kind: 'period_start',
                flowIntensity: 4,
                notes: 'started overnight',
              ),
            ],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('PERIOD'), findsOneWidget);
        expect(find.text('Period end'), findsOneWidget);
        expect(find.text('Period start'), findsOneWidget);
        expect(find.text('Spotting'), findsOneWidget); // flow level 1
        expect(find.text('Heavy'), findsOneWidget); // flow level 4
        expect(find.text('started overnight'), findsOneWidget);

        // The order the server sent, not re-sorted here.
        expect(
          tester.getTopLeft(find.text('Period end')).dy,
          lessThan(tester.getTopLeft(find.text('Period start')).dy),
        );
      },
    );

    testWidgetsWithSemantics(
      'a day with ONLY a period event is NOT the empty day — the section is '
      'what says so',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: <CycleEventResponse>[
              cycleEventFixture(id: 'evt-1', kind: 'period_start'),
            ],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('Nothing logged for this day.'), findsNothing);
        expect(find.text('Period start'), findsOneWidget);
      },
    );

    testWidgetsWithSemantics(
      'an event with NO flow level draws no flow chip — "no level recorded" '
      'and "the lowest level" are different facts and must not look alike',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: <CycleEventResponse>[
              cycleEventFixture(id: 'evt-1', kind: 'period_start'),
            ],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        for (final label in const <String>[
          'Spotting',
          'Light',
          'Medium',
          'Heavy',
          'None',
        ]) {
          expect(find.text(label), findsNothing);
        }
      },
    );

    testWidgetsWithSemantics(
      'T16-C — a Heavy flow renders as a bare chip: no warning, no alarm '
      'chrome, no advisory copy anywhere on the screen',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: <CycleEventResponse>[
              cycleEventFixture(
                id: 'evt-1',
                kind: 'period_start',
                flowIntensity: 4,
              ),
            ],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('Heavy'), findsOneWidget);
        for (final word in const <String>[
          'heavy bleeding',
          'doctor',
          'clinician',
          'concern',
          'unusual',
          'Warning',
        ]) {
          expect(find.textContaining(word), findsNothing);
        }
        expect(find.byIcon(Icons.warning), findsNothing);
        expect(find.byIcon(Icons.warning_amber), findsNothing);
      },
    );

    testWidgetsWithSemantics(
      'an event whose kind is outside the ratified three still renders, as '
      'its RAW code — a row that exists must not vanish',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: <CycleEventResponse>[
              cycleEventFixture(id: 'evt-1', kind: 'ovulation'),
            ],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('ovulation'), findsOneWidget);
        expect(find.text('Nothing logged for this day.'), findsNothing);
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
          events: const [],
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
          events: const [],
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
          events: const [],
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
          events: const [],
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
            events: const [],
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
            events: const [],
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
          events: const [],
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
            events: const [],
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
            events: const [],
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
            events: const [],
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
            events: const [],
            date: date,
            log: null,
            symptoms: [symptomResponseFixture()],
            symptomsTotal: 1,
          ),
        );

        expect(find.textContaining('Showing'), findsNothing);
      },
    );

    testWidgetsWithSemantics(
      'fix round 1, M-4: symptomsTotal > 0 with an EMPTY returned page '
      'still renders the truncation notice — never the empty-day state',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: null,
            symptoms: const [],
            symptomsTotal: 3,
          ),
        );

        expect(
          find.text('Showing 0 of 3 symptoms logged today.'),
          findsOneWidget,
        );
        expect(find.text('Nothing logged for this day.'), findsNothing);
      },
    );

    testWidgetsWithSemantics(
      'fix round 2, M-4: symptomsTotal: 0 with a NON-EMPTY returned page '
      'still renders the row — the mirror image of round 1\'s shape, '
      'introduced by round 1\'s own fix and caught at re-review',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: null,
            symptoms: [symptomResponseFixture(symptomCode: 'bloating')],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('Bloating'), findsOneWidget);
        expect(find.text('Nothing logged for this day.'), findsNothing);
        // total (0) is not greater than the page (1), so no truncation
        // notice is expected here — only that the row itself survives.
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
          events: const [],
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
          events: const [],
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
            events: const [],
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

  // ---------------------------------------------------------------------------
  // The error state (fix round 1, I-1) — nothing proved the SCREEN renders
  // anything for a failed read; only `day_detail_controller_test.dart`
  // proved the CONTROLLER reaches AsyncError. Real mocked repositories here
  // (not the settled-controller override every other test in this file
  // uses), the same shape screen 10's own error-state test takes, because
  // the point is exercising `DayDetailScreen.build`'s `error:` arm and a
  // real `ref.invalidate` retry — a controller override can't reach either.
  // ---------------------------------------------------------------------------

  group('the error state', () {
    testWidgets(
      'LumenErrorRetry renders the Failure message on a failed read, and '
      'its retry re-issues the day read',
      (tester) async {
        final cycleRepo = _MockCycleRepository();
        final symptomsRepo = _MockSymptomsRepository();

        var calls = 0;
        when(() => cycleRepo.getDay(any())).thenAnswer((_) async {
          calls++;
          if (calls <= 1) {
            return const NetworkRequired(NetworkFailure());
          }
          return Fresh(cycleDayFixture(date: date.toDate()));
        });
        when(() => symptomsRepo.getDay(any())).thenAnswer(
          (_) async =>
              Fresh(symptomListResponseFixture(items: const [], total: 0)),
        );

        await pumpApp(
          tester,
          home: DayDetailScreen(date: date),
          overrides: [
            cycleRepositoryProvider.overrideWithValue(cycleRepo),
            symptomsRepositoryProvider.overrideWithValue(symptomsRepo),
          ],
        );

        expect(find.byType(LumenErrorRetry), findsOneWidget);
        expect(
          find.text(const NetworkFailure().message),
          findsOneWidget,
          reason:
              'the error surface must show the Failure\'s OWN message, not '
              'a hard-coded generic string',
        );
        expect(calls, 1, reason: 'the initial read, which failed');

        await expectRetryReissuesOneRequest(tester, requestCount: () => calls);

        expect(find.byType(LumenErrorRetry), findsNothing);
        expect(
          find.text('Nothing logged for this day.'),
          findsOneWidget,
          reason:
              'retry must render the RECOVERED data, not merely stop '
              'showing the error',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The ratified label map (fix round 1, I-2) — bypassing all 20 entries and
  // going straight to the sentence-cased fallback survived the full suite.
  // Pin the labels that diverge most from their own code, including the one
  // escalated for clinical sign-off, plus the mood scale's own 4 labels.
  // ---------------------------------------------------------------------------

  group('the ratified symptom-code label map', () {
    testWidgetsWithSemantics(
      'renders the RATIFIED label, not a sentence-cased fallback, for '
      'every code whose label diverges from its own code string',
      (tester) async {
        const divergentCodes = <String, String>{
          'inflammation': 'General inflammation',
          'water_retention': 'Fluid retention',
          'joint_pain': 'Cramping / joint pain',
          // The very label escalated for clinical sign-off in this task's
          // report — the frozen ratification block's own word, not C-14/
          // R-16's still-unconfirmed "Low mood".
          'depressed_mood': 'Depressed mood',
          'heavy_menstrual_flow': 'Excessive menstrual flow',
          'brain_fog': 'Mental fog',
          'poor_concentration': 'Trouble concentrating',
        };

        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: null,
            symptoms: [
              for (final code in divergentCodes.keys)
                symptomResponseFixture(id: code, symptomCode: code),
            ],
            symptomsTotal: divergentCodes.length,
          ),
        );

        for (final entry in divergentCodes.entries) {
          expect(
            find.text(entry.value),
            findsOneWidget,
            reason:
                'expected the ratified label "${entry.value}" for code '
                '"${entry.key}"',
          );
          // The sentence-cased fallback a bypass mutation would produce —
          // must NOT appear instead.
          final fallback = entry.key.replaceAll('_', ' ');
          final capitalisedFallback =
              '${fallback[0].toUpperCase()}${fallback.substring(1)}';
          if (capitalisedFallback != entry.value) {
            expect(find.text(capitalisedFallback), findsNothing);
          }
        }
      },
    );

    testWidgetsWithSemantics(
      '`pain` (no ratified label) renders the sentence-cased code "Pain" — '
      'never the mockup\'s fabricated "Pelvic pain" composite',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: null,
            symptoms: [symptomResponseFixture(symptomCode: 'pain')],
            symptomsTotal: 1,
          ),
        );

        expect(find.text('Pain'), findsOneWidget);
        expect(find.textContaining('Pelvic'), findsNothing);
      },
    );
  });

  group('the mood scale label', () {
    testWidgetsWithSemantics(
      'renders each of the 4 ratified mood labels for its own ordinal, '
      'never a neighbouring one',
      (tester) async {
        const moodLabels = <int, String>{
          1: 'Low',
          2: 'Tired',
          3: 'Steady',
          4: 'Bright',
        };

        for (final entry in moodLabels.entries) {
          // Unmount between iterations (the same discipline
          // `cycle_calendar_screen_semantics_test.dart`'s weekday-header
          // test uses): each `_pump` builds a fresh ProviderContainer, and
          // without tearing down the previous tree first a pending
          // animation/timer from it survives into the next `pumpWidget`
          // call and fails the test binding's end-of-test invariant check.
          await tester.pumpWidget(const SizedBox.shrink());
          await _pump(
            tester,
            date,
            DayDetailView(
              events: const [],
              date: date,
              log: cycleDayLogFixture(pain: null, mood: entry.key),
              symptoms: const [],
              symptomsTotal: 0,
            ),
          );

          expect(
            find.text(entry.value),
            findsOneWidget,
            reason: 'mood ordinal ${entry.key} should render "${entry.value}"',
          );
          for (final other in moodLabels.values) {
            if (other != entry.value) {
              expect(find.text(other), findsNothing);
            }
          }
        }
      },
    );

    testWidgets(
      'P4b-T18: an out-of-range mood renders the raw integer, never the '
      'superseded word "Mood" — the same M7 fix promoted to a shared '
      'constant this screen now uses too',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
            events: const [],
            date: date,
            log: cycleDayLogFixture(pain: null, mood: 9),
            symptoms: const [],
            symptomsTotal: 0,
          ),
        );

        expect(find.text('9'), findsOneWidget);
        expect(find.text('Mood'), findsNothing);
      },
    );
  });
}
