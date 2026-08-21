// Semantics for screen 8 (P4b-T17, READ SURFACE ONLY).
//
// The four states this screen must design for (brief: "following screen 31's
// four-state pattern") — loading / error / empty (NetworkRequired) / stale —
// plus the content rules the brief pins directly: the date comes from the
// controller's own `today`, never the device clock; a null `displayName`
// greets without a name; `pain: 0` renders as `0 / 10`; the "vs yesterday"
// drop caption renders ONLY on a genuine decrease with both values present;
// and every element the brief cuts (confidence ring, cycle-day counter,
// insight card, labs nudge, Energy card, quick-log row, month link) stays
// absent.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/checkin/presentation/quick_checkin_screen.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Fakes — settled controllers for the states that don't need a real retry
// ---------------------------------------------------------------------------

class _FreshDashboard extends DashboardController {
  _FreshDashboard(this.view);
  final DashboardView view;

  @override
  Future<CacheResult<DashboardView>> build() async => Fresh(view);
}

class _StaleDashboard extends DashboardController {
  _StaleDashboard(this.view);
  final DashboardView view;

  @override
  Future<CacheResult<DashboardView>> build() async => Stale(view);
}

class _NetworkRequiredDashboard extends DashboardController {
  @override
  Future<CacheResult<DashboardView>> build() async =>
      const NetworkRequired<DashboardView>(NetworkFailure());
}

/// Never resolves — keeps the provider in AsyncLoading for the whole test.
class _PendingDashboard extends DashboardController {
  @override
  Future<CacheResult<DashboardView>> build() =>
      Completer<CacheResult<DashboardView>>().future;
}

class _ErrorDashboard extends DashboardController {
  @override
  Future<CacheResult<DashboardView>> build() async {
    throw StateError('Simulated failure for test.');
  }
}

DashboardView _view({
  DateTime? today,
  String? displayName = 'Maya',
  int? todayPain,
  int? todayMood,
  int? yesterdayPain,
  String? phaseUnavailableReason,
}) {
  return DashboardView(
    today: today ?? DateTime(2026, 4, 9),
    displayName: displayName,
    todayPain: todayPain,
    todayMood: todayMood,
    yesterdayPain: yesterdayPain,
    phaseUnavailableReason: phaseUnavailableReason,
  );
}

Future<void> _pump(
  WidgetTester tester,
  DashboardController Function() controller, {
  bool settle = true,
  List<Override> extraOverrides = const [],
}) {
  return pumpApp(
    tester,
    home: const DashboardScreen(),
    settle: settle,
    overrides: [
      dashboardControllerProvider.overrideWith(controller),
      // Fixed so a golden/semantics assertion never depends on the wall
      // clock the suite happens to run at.
      greetingTimeOfDayProvider.overrideWithValue('Good morning'),
      ...extraOverrides,
    ],
  );
}

// ---------------------------------------------------------------------------
// Real-repo harness — for the error state's genuine retry
// ---------------------------------------------------------------------------

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockCycleRepository extends Mock implements CycleRepository {}

class _MockMeRepository extends Mock implements MeRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  // ---------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------

  testWidgetsWithSemantics('Loading state: spinner has a semanticsLabel', (
    tester,
  ) async {
    await _pump(tester, _PendingDashboard.new, settle: false);

    expectLabeledSpinner(tester, 'Loading');
  });

  // ---------------------------------------------------------------------
  // Error — a genuine thrown Failure, real retry
  // ---------------------------------------------------------------------

  group('the error state', () {
    testWidgetsWithSemantics('announces itself via a live region', (
      tester,
    ) async {
      await _pump(tester, _ErrorDashboard.new);

      expectLiveRegion(tester, 'Something went wrong. Please try again.');
    });

    testWidgetsWithSemantics(
      'never renders the raw failure message (PII/server-detail safety, '
      "screen 31's own precedent)",
      (tester) async {
        await _pump(tester, _ErrorDashboard.new);

        expect(find.text('Simulated failure for test.'), findsNothing);
      },
    );

    testWidgetsWithSemantics('retry re-issues exactly one full read cycle', (
      tester,
    ) async {
      final todayRepo = _MockServerTodayRepository();
      final cycleRepo = _MockCycleRepository();
      final meRepo = _MockMeRepository();

      when(todayRepo.today).thenAnswer((_) async => Date(2026, 4, 20));
      when(
        () => cycleRepo.getCalendarMonth(any()),
      ).thenAnswer((_) async => Fresh(cycleCalendarFixture()));

      var meCalls = 0;
      var first = true;
      when(meRepo.getMe).thenAnswer((_) async {
        meCalls++;
        if (first) {
          first = false;
          throw const ServerFailure();
        }
        return Fresh(meResponseFixture());
      });

      await pumpApp(
        tester,
        home: const DashboardScreen(),
        overrides: [
          serverTodayRepositoryProvider.overrideWithValue(todayRepo),
          cycleRepositoryProvider.overrideWithValue(cycleRepo),
          meRepositoryProvider.overrideWithValue(meRepo),
          greetingTimeOfDayProvider.overrideWithValue('Good morning'),
        ],
      );

      await expectRetryReissuesOneRequest(tester, requestCount: () => meCalls);
    });
  });

  // ---------------------------------------------------------------------
  // NetworkRequired ("empty" — no network, no cache)
  // ---------------------------------------------------------------------

  testWidgetsWithSemantics(
    'NetworkRequired state announces itself via a live region',
    (tester) async {
      await _pump(tester, _NetworkRequiredDashboard.new);

      expectLiveRegion(tester, 'Connect to load your dashboard');
    },
  );

  // ---------------------------------------------------------------------
  // Stale
  // ---------------------------------------------------------------------

  testWidgets('Stale state shows the cached-data notice', (tester) async {
    await _pump(tester, () => _StaleDashboard(_view()));

    expect(
      find.text('Showing cached data — connect to refresh'),
      findsOneWidget,
    );
  });

  // ---------------------------------------------------------------------
  // The date — from the view's own `today`, never the device clock
  // ---------------------------------------------------------------------

  testWidgets(
    'the date line renders the FIXTURE\'s today, not whatever day the '
    'suite is actually running on',
    (tester) async {
      final fixtureToday = DateTime(2026, 4, 9);
      await _pump(tester, () => _FreshDashboard(_view(today: fixtureToday)));

      expect(
        find.text(
          '${LumenFormats.weekdayName(fixtureToday)}, '
          '${LumenFormats.monthDay(fixtureToday)}',
        ),
        findsOneWidget,
      );
    },
  );

  // ---------------------------------------------------------------------
  // The phase-unavailable hero (fix round 1, I1)
  // ---------------------------------------------------------------------
  //
  // Before this fix, the ENTIRE hero card — the screen's own defining
  // positive requirement (`ARCHITECTURE.md` §C.0.3: render the unavailable
  // state, do not infer one) — was guarded only by the two goldens.
  // Deleting `const LumenPhaseUnavailable(reason: null)` from
  // `dashboard_screen.dart` left 41 of 43 `test/features/home/` tests
  // green; only the goldens caught it, and `--update-goldens` is run
  // routinely. Mirrors `cycle_calendar_screen_semantics_test.dart:487`'s
  // own pattern exactly: `phaseUnavailableCopy` renders the SAME neutral
  // text for every reason today, so a text assertion alone cannot tell "the
  // real reason was forwarded" apart from "null was silently substituted"
  // — only reading the mounted widget's OWN `reason` field can.

  group('the phase-unavailable hero', () {
    testWidgets(
      'renders, and carries the response\'s OWN unavailableReason, not a '
      'hard-coded null',
      (tester) async {
        await _pump(
          tester,
          () => _FreshDashboard(
            _view(phaseUnavailableReason: kPhaseEngineNotImplemented),
          ),
        );

        expect(find.byType(LumenPhaseUnavailable), findsOneWidget);
        expect(find.text("Cycle phases aren't available yet"), findsOneWidget);
        expect(
          tester
              .widget<LumenPhaseUnavailable>(find.byType(LumenPhaseUnavailable))
              .reason,
          kPhaseEngineNotImplemented,
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // The greeting
  // ---------------------------------------------------------------------

  group('the greeting', () {
    testWidgets('a present displayName is greeted by name', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view(displayName: 'Maya')));

      expect(find.text('Good morning, Maya'), findsOneWidget);
    });

    testWidgets('a null displayName greets WITHOUT a name — no empty slot, no '
        'literal "null"', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view(displayName: null)));

      expect(find.text('Good morning'), findsOneWidget);
      expect(find.text('Good morning, '), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('a blank (whitespace-only) displayName greets without a '
        'name too', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view(displayName: '   ')));

      expect(find.text('Good morning'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // Pain card
  // ---------------------------------------------------------------------

  group('the pain card', () {
    testWidgets('pain: 0 is a real logged value (D-08) and renders as '
        '"0 / 10", never as "not logged"', (tester) async {
      await _pump(
        tester,
        () => _FreshDashboard(_view(todayPain: 0, yesterdayPain: null)),
      );

      expect(find.text('0 / 10'), findsOneWidget);
      expect(find.text('Not logged today'), findsOneWidget); // the mood card
    });

    testWidgets('no pain logged today renders "Not logged today"', (
      tester,
    ) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.text('Not logged today'), findsNWidgets(2)); // pain + mood
    });

    testWidgets(
      'a genuine 3 -> 0 drop renders "vs yesterday" — pain:0 is a real '
      'value, not falsiness-tested away',
      (tester) async {
        await _pump(
          tester,
          () => _FreshDashboard(_view(todayPain: 0, yesterdayPain: 3)),
        );

        expect(find.text('0 / 10'), findsOneWidget);
        expect(find.text('vs yesterday'), findsOneWidget);
      },
    );

    testWidgets(
      '"vs yesterday" renders NOTHING when yesterday has no value — the '
      'absence is asserted directly, not just the presence case',
      (tester) async {
        await _pump(
          tester,
          () => _FreshDashboard(_view(todayPain: 2, yesterdayPain: null)),
        );

        expect(find.text('2 / 10'), findsOneWidget);
        expect(find.text('vs yesterday'), findsNothing);
        expect(find.text('—'), findsNothing);
        expect(find.text('no change'), findsNothing);
      },
    );

    testWidgets('"vs yesterday" renders NOTHING when today has no value, even '
        'though yesterday does', (tester) async {
      await _pump(
        tester,
        () => _FreshDashboard(_view(todayPain: null, yesterdayPain: 3)),
      );

      expect(find.text('vs yesterday'), findsNothing);
    });

    testWidgets(
      '"vs yesterday" renders NOTHING when pain went UP, not just when '
      'it stayed flat',
      (tester) async {
        await _pump(
          tester,
          () => _FreshDashboard(_view(todayPain: 5, yesterdayPain: 3)),
        );

        expect(find.text('5 / 10'), findsOneWidget);
        expect(find.text('vs yesterday'), findsNothing);
      },
    );

    testWidgets('"vs yesterday" renders NOTHING when pain is unchanged', (
      tester,
    ) async {
      await _pump(
        tester,
        () => _FreshDashboard(_view(todayPain: 3, yesterdayPain: 3)),
      );

      expect(find.text('vs yesterday'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------
  // Mood card
  // ---------------------------------------------------------------------

  group('the mood card', () {
    testWidgets('mood 1..4 renders its ratified label', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view(todayMood: 1)));
      expect(find.text('Low'), findsOneWidget);
    });

    testWidgets('mood 4 renders "Bright"', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view(todayMood: 4)));
      expect(find.text('Bright'), findsOneWidget);
    });

    testWidgets(
      'fix round 1, M7: an out-of-range mood (contract-constrained to 1-4, '
      'so unreachable today, but a malformed value must not be dishonest) '
      'renders the raw integer, never the word "Mood" — which, beside the '
      'card\'s own "MOOD" label, would read as the redundant "MOOD / Mood"',
      (tester) async {
        await _pump(tester, () => _FreshDashboard(_view(todayMood: 9)));

        expect(find.text('9'), findsOneWidget);
        // Narrowed at P4b-T18, not deleted: the Mood QUICK-LOG TILE (a
        // different element — a launcher, not the card) now legitimately
        // renders the word "Mood" once. `findsOneWidget` here is what
        // proves the CARD's own fallback still does NOT ALSO say "Mood" —
        // if it did, this would read `findsNWidgets(2)` and fail.
        expect(find.text('Mood'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------
  // Every cut element is genuinely absent
  // ---------------------------------------------------------------------

  group('the cut elements are absent', () {
    testWidgets('no confidence ring / percentage', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.textContaining('%'), findsNothing);
      expect(find.text('conf'), findsNothing);
    });

    testWidgets('no cycle-day counter or phase name', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.textContaining('Luteal'), findsNothing);
      expect(find.textContaining('Day 22'), findsNothing);
      expect(find.text('of 28'), findsNothing);
    });

    testWidgets('no insight card', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.textContaining('Insight'), findsNothing);
      expect(find.textContaining('Cortisol'), findsNothing);
    });

    testWidgets('no "add labs" nudge', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.textContaining('labs'), findsNothing);
    });

    testWidgets('no Energy card', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.text('Energy'), findsNothing);
      expect(find.textContaining('Typical for phase'), findsNothing);
    });

    testWidgets('P4b-T20b: the "Quick log" row now ships its two real members, '
        'Symptom and Mood — Activity (P5) is still absent, and shipping it '
        'without a destination is what R-20 forbids, not a row whose every '
        'tile works', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      // LumenFieldLabel DRAWS its text uppercased ("QUICK LOG") — the
      // sentence-case string is what it ANNOUNCES, a separate Semantics
      // value, not what a plain `find.text` search sees.
      expect(find.text('QUICK LOG'), findsOneWidget);
      // T18 asserted this findsNothing. **The flip is the intended
      // signal**, not a broken test: T20b ships screen 12 and the
      // `/symptoms/new` route in the same commit as this tile, which is
      // exactly what R-20 asks for.
      expect(find.text('Symptom'), findsOneWidget);
      expect(find.text('Activity'), findsNothing);
    });

    testWidgets('the Mood CARD\'s "MOOD" label and the Mood TILE\'s "Mood" '
        'label are both present, distinguishably cased', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.text('MOOD'), findsOneWidget);
      expect(find.text('Mood'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // Interactive affordances — exactly the Mood tile (R-20)
  // ---------------------------------------------------------------------
  //
  // Originally "zero interactive affordances" (fix round 1, M2+M3): the old
  // "no month-link shortcut" test (`find.byIcon(Icons.calendar_month),
  // findsNothing`) could not fail for the reason it named — nothing in this
  // screen ever imported that icon — so the real guard became a whole-screen
  // button COUNT, exactly as screens 10 and 11 pin their own. **P4b-T18 was
  // built to redden this the moment the Mood tile shipped, and that
  // reddening is the intended signal, not a failure** — the count below is
  // updated from 0 to 1, not deleted, and the reasoning stays: any button
  // beyond the Mood tile today would point at nothing (Symptom/Activity have
  // no destination yet).

  group('interactive affordances (R-20)', () {
    testWidgetsWithSemantics(
      'the loaded dashboard offers EXACTLY TWO buttons — the Symptom and '
      'Mood tiles — no tile ships without its destination',
      (tester) async {
        await _pump(tester, () => _FreshDashboard(_view()));

        expect(
          kAnyButtonSemantics,
          findsNWidgets(2),
          reason:
              'screen 8 ships with exactly the Mood tile (T18) and the '
              'Symptom tile (T20b, together with screen 12 and its route); '
              'any OTHER button here today would point at nothing — '
              'Activity has no destination until P5. The count moved from '
              '1 to 2 rather than being deleted, the same way T18 moved it '
              'from 0 to 1.',
        );
      },
    );

    testWidgetsWithSemantics(
      'positive control: the harness DOES detect a button when one exists '
      '— the NetworkRequired body\'s own Retry button',
      (tester) async {
        await _pump(tester, _NetworkRequiredDashboard.new);

        expect(
          kAnyButtonSemantics,
          findsNWidgets(1),
          reason:
              'if this finds 0, the "no buttons" assertion above is not '
              'proving anything — this is what makes it a real guard '
              'rather than a broken harness passing vacuously',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // The Symptom quick-log tile (P4b-T20b)
  // ---------------------------------------------------------------------
  //
  // Where it NAVIGATES to is proven against the real route table in
  // `test/core/router/symptom_form_route_test.dart` — a plain `pumpApp` has
  // no GoRouter to push into. What belongs here is the tile itself.

  group('the Symptom quick-log tile', () {
    testWidgetsWithSemantics('is a labelled, tappable button', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expectLabeledButton(tester, find.text('Symptom'), 'Symptom');
    });

    testWidgetsWithSemantics(
      'announces no selected state at all — a pure launcher, not a toggle',
      (tester) async {
        await _pump(tester, () => _FreshDashboard(_view()));

        final data = tester
            .getSemantics(find.text('Symptom'))
            .getSemanticsData();
        expect(
          data.flagsCollection.isSelected,
          Tristate.none,
          reason:
              'the same defect M-3 fixed on the Mood tile: `selected: '
              'false` would announce "not selected" for a control that was '
              'never selectable',
        );
      },
    );

    testWidgets('its glyph does not judge the user — Icons.healing, never '
        'Icons.sick', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.byIcon(Icons.healing), findsOneWidget);
      expect(
        find.byIcon(Icons.sick),
        findsNothing,
        reason:
            'a face with a thermometer asserts a state about the USER on a '
            'control that is only an entry point — a symptom logged at '
            'intensity 0 is a valid entry here',
      );
    });
  });

  // ---------------------------------------------------------------------
  // The Mood quick-log tile (P4b-T18)
  // ---------------------------------------------------------------------

  group('the Mood quick-log tile', () {
    testWidgetsWithSemantics('is a labelled, tappable button', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expectLabeledButton(tester, find.text('Mood'), 'Mood');
    });

    // Fix round 2, item 1: M-3 (round 1) fixed LumenSelectableRow so
    // `selected: null` omits the flag, and this call site passes `null` —
    // but nothing pinned the CALL SITE itself. Reverting it to `selected:
    // false` (the exact bug M-3 exists to fix) left the widget-level tests
    // untouched and the whole suite green; only a test that reads THIS
    // tile's own node catches a regression here.
    testWidgetsWithSemantics(
      'announces no selected state at all — a pure launcher, not a toggle',
      (tester) async {
        await _pump(tester, () => _FreshDashboard(_view()));

        final data = tester.getSemantics(find.text('Mood')).getSemanticsData();
        expect(
          data.flagsCollection.isSelected,
          Tristate.none,
          reason:
              'selected: false (round 1\'s original shape) would announce '
              '"not selected" for a control that was never selectable; '
              'selected: null omits the flag entirely',
        );
      },
    );

    testWidgets('opens screen 9, the quick check-in sheet', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      await tester.tap(find.text('Mood'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickCheckinScreen), findsOneWidget);
      expect(find.byType(LumenBottomSheet), findsOneWidget);
    });

    // Fix round 1, I-3: drag-to-dismiss cannot be gated per-attempt (see
    // `showLumenBottomSheet`'s own dartdoc — `BottomSheet`'s `onClosing`
    // calls `Navigator.pop` directly, bypassing `PopScope`), so this call
    // site closes it permanently instead. A downward drag on the open
    // sheet must do nothing.
    testWidgets('the opened sheet does not respond to a downward drag — '
        'enableDrag: false at this call site', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      await tester.tap(find.text('Mood'));
      await tester.pumpAndSettle();
      expect(find.byType(LumenBottomSheet), findsOneWidget);

      await tester.drag(find.byType(LumenBottomSheet), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(
        find.byType(LumenBottomSheet),
        findsOneWidget,
        reason:
            'a drag gesture must not dismiss screen 9\'s sheet at '
            'all — enableDrag: false removes the vertical-drag '
            'recognizer entirely, regardless of submitting state',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Dingbats
  // ---------------------------------------------------------------------

  testWidgets('no dingbat glyphs anywhere on the screen', (tester) async {
    await _pump(
      tester,
      () =>
          _FreshDashboard(_view(todayPain: 0, todayMood: 3, yesterdayPain: 4)),
    );

    expectNoDingbats(tester, screen: 'DashboardScreen');
  });
}
