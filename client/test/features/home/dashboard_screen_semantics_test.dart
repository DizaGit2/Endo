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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
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
}) {
  return DashboardView(
    today: today ?? DateTime(2026, 4, 9),
    displayName: displayName,
    todayPain: todayPain,
    todayMood: todayMood,
    yesterdayPain: yesterdayPain,
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

    testWidgets('no quick-log row of any kind', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.textContaining('Quick log'), findsNothing);
      expect(find.text('Symptom'), findsNothing);
      expect(find.text('Mood'), findsNothing); // the CARD says "MOOD", but
      // never the standalone quick-log tile label — see the next test for
      // the card's own (differently-cased) label.
      expect(find.text('Activity'), findsNothing);
    });

    testWidgets('the Mood CARD label is present, distinguishing it from '
        'the cut quick-log tile', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.text('MOOD'), findsOneWidget);
    });

    testWidgets('no month-link shortcut to the calendar', (tester) async {
      await _pump(tester, () => _FreshDashboard(_view()));

      expect(find.byIcon(Icons.calendar_month), findsNothing);
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
