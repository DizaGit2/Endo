// Semantics + geometry for screen 10 (P4b-T15, guards inverted at P4b-T16).
//
// Two kinds of test live here, deliberately side by side:
//
//  * PURE tests of `buildCycleCalendarGrid` — no widget pump at all, because
//    the geometry (row count, which column the 1st lands in under a given
//    locale) is a fact about that function, not about the tree it feeds.
//    `cycle_setup_screen_semantics_test.dart` mixes plain `test()`s with
//    `testWidgetsWithSemantics()` the same way, for a pure helper of its own.
//  * WIDGET tests of the rendered screen — the a11y rules, and (until T16)
//    requirement 2's correctness constraint that no day cell exposes button
//    semantics.
//
// **P4b-T16 inverts the group below named "day cells are buttons now — the
// tappable set is the 30 current-month cells".** Before T16 this file's day
// cells carried no semantics config at all (T15's own comments — preserved
// where still accurate — explain why `tester.getSemantics` on a cell's key
// used to resolve to the scroll container). T16 gives EVERY current-month
// cell its own `Semantics(button: true)` node, so per-cell assertions are
// meaningful for the first time; adjacent-month cells stay exactly as they
// were. `view()`'s April 2026 fixture is 35 drawn cells, 30 of them
// current-month (2 leading + 3 trailing dimmed) — that 30 is what both
// guards below are now keyed on.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/cycle/presentation/cycle_calendar_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

// ---------------------------------------------------------------------------
// Pure geometry tests
// ---------------------------------------------------------------------------

void main() {
  group('buildCycleCalendarGrid — pure geometry, no pump', () {
    test(
      'a 6-week month renders 6 rows — sized to the month, never a fixed row '
      'count',
      () {
        // August 2026 opens on a Saturday (chained from the codebase's own
        // documented anchor: April 2026 opens on a Wednesday, and
        // April(30)+May(31)+June(30)+July(31) walks Wed -> Fri -> Mon -> Wed
        // -> Sat). Under es-ES (Monday-first) that is leading=5, 31 days ->
        // 36 cells -> 6 rows; under en-US (Sunday-first) leading=6 -> 37
        // cells -> 6 rows too. The mockup shows April's 5 rows because April
        // happens to fit in 5 — a hard-coded 5x7 grid cannot reveal a month
        // that does not.
        final esES = buildCycleCalendarGrid(
          month: DateTime(2026, 8, 1),
          locale: 'es-ES',
        );
        final enUS = buildCycleCalendarGrid(
          month: DateTime(2026, 8, 1),
          locale: 'en-US',
        );

        expect(esES.length, 42, reason: '6 rows x 7 columns');
        expect(enUS.length, 42, reason: '6 rows x 7 columns');
      },
    );

    test('the row count always matches leadingBlankDays + the month\'s own '
        'length, for a month that is NOT 6 rows either', () {
      // April 2026: documented to open on a Wednesday. Under es-ES that is
      // leading=2, +30 days = 32 -> ceil(32/7) = 5 rows, not 6 — the
      // control against the test above.
      final leading = LumenFormats.leadingBlankDays(DateTime(2026, 4), 'es-ES');
      final grid = buildCycleCalendarGrid(
        month: DateTime(2026, 4),
        locale: 'es-ES',
      );
      final expectedRows = ((leading + 30) / 7).ceil();

      expect(expectedRows, 5);
      expect(grid.length, expectedRows * 7);
    });

    test('leadingBlankDays places the 1st in the right column under BOTH es-ES '
        'and en-US — proving the locale is actually consulted, not a constant '
        'returned', () {
      // April 2026 opens on a Wednesday (documented at
      // lumen_formats.dart's leadingBlankDays and cache_keys.dart's
      // monthWindow dartdoc): es-ES (Monday-first) -> leading 2; en-US
      // (Sunday-first) -> leading 3.
      final esES = buildCycleCalendarGrid(
        month: DateTime(2026, 4, 1),
        locale: 'es-ES',
      );
      final enUS = buildCycleCalendarGrid(
        month: DateTime(2026, 4, 1),
        locale: 'en-US',
      );

      expect(esES[2].date, DateTime(2026, 4, 1));
      expect(esES[2].dimmed, isFalse);
      expect(enUS[3].date, DateTime(2026, 4, 1));
      expect(enUS[3].dimmed, isFalse);
    });

    test('leading and trailing cells carry REAL adjacent-month day numbers, '
        'dimmed — never a blank box', () {
      final grid = buildCycleCalendarGrid(
        month: DateTime(2026, 4, 1),
        locale: 'es-ES',
      );

      // Leading: the last two days of March.
      expect(grid[0].date, DateTime(2026, 3, 30));
      expect(grid[0].dimmed, isTrue);
      expect(grid[1].date, DateTime(2026, 3, 31));
      expect(grid[1].dimmed, isTrue);

      // Trailing: 5 rows = 35 cells (leading 2 + 30 days = 32 -> ceil/7 =
      // 5), so 3 trailing cells complete the last row with May 1-3.
      expect(grid.length, 35);
      expect(grid[32].date, DateTime(2026, 5, 1));
      expect(grid[32].dimmed, isTrue);
      expect(grid[34].date, DateTime(2026, 5, 3));
      expect(grid[34].dimmed, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget / semantics tests
  // ---------------------------------------------------------------------------

  group('CycleCalendarScreen', () {
    Future<void> pump(
      WidgetTester tester,
      CycleCalendarView view, {
      String locale = 'es-ES',
    }) {
      return pumpApp(
        tester,
        home: const CycleCalendarScreen(),
        overrides: [
          deviceLocaleProvider.overrideWithValue(locale),
          cycleCalendarControllerProvider.overrideWith(
            () => _SettledCalendar(view),
          ),
        ],
      );
    }

    /// April 2026 under es-ES: today the 22nd, a dot on the 16th (an
    /// ORDINARY current-month day), a dot on March 30th (a DIMMED leading
    /// day — proving the opacity wrap dims the dot too), and the 5th left
    /// bare as a negative control.
    CycleCalendarView view() => CycleCalendarView(
      visibleMonth: DateTime(2026, 4),
      today: Date(2026, 4, 22),
      phase: null,
      dayByDate: <Date, CycleCalendarDay>{
        Date(2026, 4, 16): cycleCalendarDayFixture(
          date: Date(2026, 4, 16),
          eventCount: 1,
        ),
        Date(2026, 3, 30): cycleCalendarDayFixture(
          date: Date(2026, 3, 30),
          eventCount: 1,
        ),
      },
    );

    testWidgetsWithSemantics('renders the mockup\'s copy and no dingbats', (
      tester,
    ) async {
      await pump(tester, view());

      expect(find.text('CYCLE'), findsOneWidget);
      expect(find.text('April 2026'), findsOneWidget);
      // The h1 and the .mh stepper are ONE control now (requirement 4) —
      // "April 2026" appears exactly once, not once at each size.
      expect(find.text('April'), findsNothing);

      expectNoDingbats(tester, screen: 'CycleCalendarScreen');
    });

    testWidgets(
      'the weekday header follows the LOCALE\'s order, not a fixed one — '
      'M T W T F S S under es-ES, S M T W T F S under en-US',
      (tester) async {
        await pump(tester, view(), locale: 'es-ES');

        final spanish = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .toList();
        // The seven headings, in the order they are drawn. `indexOf('M')`
        // finds the header's own 'M' — no other Text on this screen is the
        // bare single character 'M'.
        expect(
          spanish.sublist(spanish.indexOf('M'), spanish.indexOf('M') + 7),
          <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'],
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await pump(tester, view(), locale: 'en-US');

        final american = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .toList();
        expect(
          american.sublist(american.indexOf('S'), american.indexOf('S') + 7),
          <String>['S', 'M', 'T', 'W', 'T', 'F', 'S'],
        );
      },
    );

    testWidgets(
      'a 6-week month is actually RENDERED as 6 rows — not just computed '
      'as one. buildCycleCalendarGrid\'s own pure tests prove the geometry; '
      'this exercises the WIDGET (`_MonthGrid`\'s `rows = cells.length ~/ '
      '7` and its row-building loop) that consumes it',
      (tester) async {
        await pump(
          tester,
          CycleCalendarView(
            visibleMonth: DateTime(2026, 8),
            today: Date(2026, 8, 1),
            phase: null,
            dayByDate: const <Date, CycleCalendarDay>{},
          ),
        );

        // August 2026 under es-ES is 6 rows / 42 cells (leading 5 + 31 days
        // = 36 -> ceil/7 = 6, trailing 6). The LAST cell of a 6-row grid is
        // September 6th — a date that exists in the tree only if the 6th
        // row was genuinely built, not merely computed.
        expect(
          find.byKey(ValueKey<DateTime>(DateTime(2026, 9, 6))),
          findsOneWidget,
        );
      },
    );

    testWidgetsWithSemantics(
      'the month chevrons ARE buttons — the positive control for the '
      'day-cell assertions below',
      (tester) async {
        await pump(tester, view());
        final materialLocalizations = MaterialLocalizations.of(
          tester.element(find.byType(CycleCalendarScreen)),
        );

        expectLabeledButton(
          tester,
          find.widgetWithIcon(IconButton, Icons.chevron_left),
          materialLocalizations.previousMonthTooltip,
          exactLabel: true,
        );
        expectLabeledButton(
          tester,
          find.widgetWithIcon(IconButton, Icons.chevron_right),
          materialLocalizations.nextMonthTooltip,
          exactLabel: true,
        );
      },
    );

    testWidgetsWithSemantics(
      'the 30 current-month cells are buttons; the 5 adjacent-month cells '
      'are not — requirement 2, inverted at P4b-T16: only the visible '
      'MONTH is tappable',
      (tester) async {
        await pump(tester, view());

        // The GLOBAL count: the two month chevrons (asserted as buttons
        // above) PLUS exactly the 30 current-month day cells. Before T16
        // this asserted "2" — no day cell had its own semantics node at
        // all, so `tester.getSemantics` on a cell's key resolved to
        // whatever ancestor DID (the scroll container), and every cell key
        // resolved to that SAME node. T16 gives every current-month cell
        // `Semantics(button: true)`, so a day cell — leading, trailing,
        // today, marked, or plain — that gained OR LOST that flag moves
        // this count away from 32, regardless of which cell it was.
        expect(
          kAnyButtonSemantics,
          findsNWidgets(32),
          reason:
              'the two month chevrons plus the 30 current-month day cells '
              'should be the only buttons on this screen; a dimmed '
              'adjacent-month cell gaining button semantics, or a '
              'current-month cell losing it, would move this count away '
              'from 32',
        );

        // SCOPED to the grid, not the whole screen: Material 3's own
        // `IconButton` implementation gives the two month chevrons an
        // `InkWell` each (measured — `_IconButtonM3` wraps its child in
        // one), so an unscoped count would always include those two
        // legitimate ones. Before T16 this asserted `findsNothing`;
        // inverted now that every current-month cell IS an `InkWell` (the
        // tap that reaches screen 11).
        expect(
          find.descendant(
            of: find.byKey(cycleCalendarGridKey),
            matching: find.byType(InkWell),
          ),
          findsNWidgets(30),
        );
      },
    );

    testWidgetsWithSemantics(
      'a current-month cell announces itself as a button named "<Month> '
      '<day>" — the positive control the per-cell assertion above could not '
      'be written without',
      (tester) async {
        await pump(tester, view());

        // April 16, 2026 is the fixture's ordinary marked current-month
        // day (`view()`, above).
        expectLabeledButton(
          tester,
          find.byKey(ValueKey<DateTime>(DateTime(2026, 4, 16))),
          'April 16',
          exactLabel: true,
        );
      },
    );

    testWidgetsWithSemantics(
      'an adjacent-month cell is not wrapped in an InkWell — the negative '
      'control: dimmed cells stay context, never targets',
      (tester) async {
        await pump(tester, view());

        // NOT `expectNotAButton` on the cell's own key: a dimmed cell
        // contributes no `Semantics` config of its own, so
        // `tester.getSemantics` would walk UP past it to whatever ancestor
        // DOES have one — silently asserting about that ancestor instead
        // of the cell (the a11y_guard rule: a negative assertion needs a
        // handle that owns a node). The WHOLE-SCREEN count above (exactly
        // 32) is the real negative control for "no adjacent-month cell
        // gained button semantics"; this is the complementary WIDGET-tree
        // check that this SPECIFIC dimmed cell — March 30, 2026, the
        // fixture's leading cell that still carries a dot — has no
        // `InkWell` of its own, which is unambiguous because
        // `find.descendant` is scoped to that cell's subtree rather than
        // walking the semantics tree.
        expect(
          find.descendant(
            of: find.byKey(ValueKey<DateTime>(DateTime(2026, 3, 30))),
            matching: find.byType(InkWell),
          ),
          findsNothing,
        );
      },
    );

    testWidgetsWithSemantics(
      'the today ring is drawn on the RESPONSE\'s today, not on any other '
      'cell',
      (tester) async {
        await pump(tester, view());

        Border? borderOf(DateTime date) {
          final decoratedBox = tester.widget<DecoratedBox>(
            find.descendant(
              of: find.byKey(ValueKey<DateTime>(date)),
              matching: find.byType(DecoratedBox),
            ),
          );
          return (decoratedBox.decoration as BoxDecoration).border as Border?;
        }

        expect(
          borderOf(DateTime(2026, 4, 22)),
          isNotNull,
          reason: 'the fixture\'s today (the 22nd) must carry the ring',
        );
        expect(
          borderOf(DateTime(2026, 4, 21)),
          isNull,
          reason: 'the day either side of today must not',
        );
        expect(borderOf(DateTime(2026, 4, 23)), isNull);
      },
    );

    testWidgetsWithSemantics(
      'the marker dot renders for a marked day, including a DIMMED '
      'adjacent-month one, and never for an unmarked day',
      (tester) async {
        await pump(tester, view());

        bool hasDot(DateTime date) {
          final cell = find.byKey(ValueKey<DateTime>(date));
          return find
              .descendant(
                of: cell,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Container &&
                      w.decoration is BoxDecoration &&
                      (w.decoration! as BoxDecoration).shape == BoxShape.circle,
                ),
              )
              .evaluate()
              .isNotEmpty;
        }

        expect(
          hasDot(DateTime(2026, 4, 16)),
          isTrue,
          reason: 'ordinary marked day',
        );
        expect(
          hasDot(DateTime(2026, 3, 30)),
          isTrue,
          reason:
              'a DIMMED leading day can still carry a dot — the brief\'s own '
              'fix for the earlier grid-shaped-read ruling exists so every '
              'drawn cell, adjacent-month ones included, has accurate dot '
              'data',
        );
        expect(hasDot(DateTime(2026, 4, 5)), isFalse, reason: 'unmarked day');
      },
    );

    testWidgetsWithSemantics(
      'an adjacent-month cell is drawn at 0.3 opacity; a current-month cell '
      'is drawn at full opacity — `.d.dim{opacity:.3}`, reproduced on the '
      'WHOLE cell rather than just its text colour',
      (tester) async {
        await pump(tester, view());

        double? opacityOf(DateTime date) {
          final finder = find.descendant(
            of: find.byKey(ValueKey<DateTime>(date)),
            matching: find.byType(Opacity),
          );
          if (finder.evaluate().isEmpty) return null;
          return tester.widget<Opacity>(finder).opacity;
        }

        expect(
          opacityOf(DateTime(2026, 3, 30)),
          0.3,
          reason: 'a leading (adjacent-month) cell must be dimmed',
        );
        expect(
          opacityOf(DateTime(2026, 4, 16)),
          isNull,
          reason: 'a current-month cell must not be wrapped in Opacity at all',
        );
      },
    );

    testWidgetsWithSemantics(
      'the phase-unavailable block renders and carries the response\'s '
      'unavailableReason',
      (tester) async {
        await pump(
          tester,
          CycleCalendarView(
            visibleMonth: DateTime(2026, 4),
            today: Date(2026, 4, 22),
            phase: CyclePhaseAvailabilityResponse(
              (b) => b
                ..available = false
                ..unavailableReason = kPhaseEngineNotImplemented,
            ),
            dayByDate: const <Date, CycleCalendarDay>{},
          ),
        );

        expect(find.byType(LumenPhaseUnavailable), findsOneWidget);
        expect(find.text("Cycle phases aren't available yet"), findsOneWidget);
        // `phaseUnavailableCopy` renders the SAME neutral text for every
        // reason today (P6 is what adds reason-specific copy), so the text
        // assertion above cannot tell "the real reason was forwarded" apart
        // from "null was silently substituted". Reading the mounted
        // widget's OWN `reason` field is what actually pins the brief's
        // requirement.
        expect(
          tester
              .widget<LumenPhaseUnavailable>(find.byType(LumenPhaseUnavailable))
              .reason,
          kPhaseEngineNotImplemented,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The error state (fix-round-1, I-3) — brief §7 requires it; the
  // controller test only proves the AsyncError STATE, not that the SCREEN
  // renders a retry and that using it re-reads. Real repository + real API
  // mock here, not `_SettledCalendar` — the whole point is exercising the
  // three-window read twice (the failing one, then retry's).
  // ---------------------------------------------------------------------------

  group('the error state', () {
    testWidgets(
      'LumenErrorRetry renders on failure, and its retry re-issues the '
      'three-window read',
      (tester) async {
        final api = MockLumenApiApi();
        final todayRepo = _MockServerTodayRepository();
        when(todayRepo.today).thenAnswer((_) async => Date(2026, 4, 20));

        var calls = 0;
        when(
          () => api.cycleCalendarGet(
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async {
          calls++;
          if (calls <= 3) {
            // The initial three-window read — all three fail, and with an
            // empty cache that becomes NetworkRequired -> the controller
            // throws (see cycle_calendar_controller.dart's own comment on
            // `_loadMonth`), which surfaces as AsyncError.
            throw DioException(
              requestOptions: RequestOptions(path: '/cycle/calendar'),
              type: DioExceptionType.connectionError,
            );
          }
          return Response<CycleCalendarResponse>(
            requestOptions: RequestOptions(path: '/cycle/calendar'),
            statusCode: 200,
            data: cycleCalendarFixture(today: Date(2026, 4, 20)),
          );
        });

        final repo = CycleRepository(api: api, store: emptyCacheStore());

        await pumpApp(
          tester,
          home: const CycleCalendarScreen(),
          overrides: [
            deviceLocaleProvider.overrideWithValue('es-ES'),
            serverTodayRepositoryProvider.overrideWithValue(todayRepo),
            cycleRepositoryProvider.overrideWithValue(repo),
          ],
        );

        expect(find.byType(LumenErrorRetry), findsOneWidget);
        expect(
          calls,
          3,
          reason: 'the initial three-window read, all three failing',
        );

        await tester.tap(find.text(LumenErrorRetry.retryLabel));
        await tester.pumpAndSettle();

        expect(
          calls,
          6,
          reason:
              'retry must re-issue the SAME three-window read, not one '
              'request and not a re-derived single-month one',
        );
        expect(find.byType(LumenErrorRetry), findsNothing);
        expect(
          find.text('April 2026'),
          findsOneWidget,
          reason:
              'the screen must actually render the recovered data, not '
              'merely stop showing the error',
        );
      },
    );
  });
}

class _SettledCalendar extends CycleCalendarController {
  _SettledCalendar(this.view);

  final CycleCalendarView view;

  // `async` because CycleCalendarController's OWN build() is declared
  // `Future<CycleCalendarView> Function()` — see the golden test's identical
  // fixture for why an override must match it rather than the bare
  // `FutureOr<T>` the AsyncNotifier base allows.
  @override
  Future<CycleCalendarView> build() async => view;
}
