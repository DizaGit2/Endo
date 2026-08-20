// Semantics for screen 11 (P4b-T16, READ SURFACE ONLY).
//
// Screen 11 draws exactly ONE control — the back chevron (the period-event
// and day-log editors are T16b). That makes the positive/negative controls
// unusually sharp: `kAnyButtonSemantics` should find exactly 1 node on this
// screen, always the back button, never a day cell's own content or a
// symptom row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/cycle/presentation/day_detail_screen.dart';
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

    testWidgetsWithSemantics(
      'fix round 1, M-4: symptomsTotal > 0 with an EMPTY returned page '
      'still renders the truncation notice — never the empty-day state',
      (tester) async {
        await _pump(
          tester,
          date,
          DayDetailView(
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
