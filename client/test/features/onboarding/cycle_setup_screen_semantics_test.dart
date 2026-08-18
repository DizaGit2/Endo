// Semantics + behaviour for screen 3 (P4b-T9).
//
// Two things on this screen are correctness rather than polish, and both are
// asserted here rather than left to a golden:
//
//   * the week starts on MONDAY under es-ES (D-05), so the column a date lands
//     in is locale-dependent and a hard-coded `S M T W T F S` header is wrong;
//   * a future day is not a control, and TODAY is — the server rejects
//     `lastPeriodStart > today` and accepts today itself.
//
// Everything else here is the a11y rule set the phase already ships: chips
// announce what they mean, an uppercased label is not what a screen reader
// hears, and the one non-blocking advisory this screen can show announces
// itself.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/onboarding/presentation/cycle_setup_screen.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockCycleSettingsRepository extends Mock
    implements CycleSettingsRepository {}

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

class _SettledFlow extends OnboardingFlowController {
  _SettledFlow({this.lastPeriodStart});

  final Date? lastPeriodStart;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: OnboardingStep.cycle,
      state: onboardingStateFixture(lastPeriodStart: lastPeriodStart),
    ),
  );
}

class _Harness {
  _Harness({
    Date? resumeAnchor,
    CycleSettingsResponse? settings,
    Failure? settingsFailure,
    Date? today,
    Failure? todayFailure,
    String deviceLocale = 'es-ES',
  }) {
    if (settingsFailure != null) {
      when(settingsRepo.getSettings).thenAnswer((_) async {
        settingsCalls++;
        return NetworkRequired<CycleSettingsResponse>(settingsFailure);
      });
    } else {
      when(settingsRepo.getSettings).thenAnswer((_) async {
        settingsCalls++;
        return Fresh<CycleSettingsResponse>(settings ?? cycleSettingsFixture());
      });
    }

    if (todayFailure != null) {
      when(todayRepo.today).thenAnswer((_) async => throw todayFailure);
    } else {
      when(todayRepo.today).thenAnswer((_) async => today ?? Date(2026, 4, 20));
    }

    overrides = <Override>[
      ...lumenOverrides(),
      deviceLocaleProvider.overrideWithValue(deviceLocale),
      onboardingFlowControllerProvider.overrideWith(
        () => _SettledFlow(lastPeriodStart: resumeAnchor),
      ),
      cycleSettingsRepositoryProvider.overrideWithValue(settingsRepo),
      serverTodayRepositoryProvider.overrideWithValue(todayRepo),
      onboardingRepositoryProvider.overrideWithValue(onboardingRepo),
    ];
  }

  final _MockCycleSettingsRepository settingsRepo =
      _MockCycleSettingsRepository();
  final _MockServerTodayRepository todayRepo = _MockServerTodayRepository();
  final _MockOnboardingRepository onboardingRepo = _MockOnboardingRepository();
  late final List<Override> overrides;
  int settingsCalls = 0;

  void answerSave([OnboardingCycleResponse? body]) {
    when(
      () => onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    ).thenAnswer((_) async => body ?? onboardingCycleFixture());
  }

  void rejectSave(Failure failure) {
    when(
      () => onboardingRepo.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    ).thenAnswer((_) async => throw failure);
  }

  /// The frame the shell puts around a step body — [onboardingStepHost], built
  /// out of the shell's own insets and its own step slot, so this file drives
  /// screen 3 under the constraints it actually ships under.
  Future<void> pump(WidgetTester tester) async {
    await pumpApp(
      tester,
      home: onboardingStepHost(const CycleSetupScreen()),
      overrides: overrides,
    );
  }
}

/// The x-centre of the cell drawn for [day].
double _columnOf(WidgetTester tester, String day) {
  final box = tester.getRect(find.text(day));
  return box.center.dx;
}

/// A control, located by what it ANNOUNCES rather than by what it draws.
///
/// The calendar and the chip row both render "28" in April, so `find.text` is
/// ambiguous on this screen by construction — and the accessible name is the
/// thing worth pinning anyway.
Finder announcing(String label) => find.bySemanticsLabel(label);

/// Whether the node at [finder] announces itself as selected.
bool isSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isSelected ==
    Tristate.isTrue;

void main() {
  setUpAll(() => registerFallbackValue(Date(2026, 1, 1)));

  // -------------------------------------------------------------------------
  // What it says
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('it renders the mockup\'s copy and no dingbats', (
    tester,
  ) async {
    await _Harness().pump(tester);

    expect(find.text('When did your last period start?'), findsOneWidget);
    expect(find.text("We'll predict your phases from here."), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    // The mockup's `‹`/`›` month chevrons became `Icon`s, which is the whole
    // reason this guard travels with every screen.
    expectNoDingbats(tester, screen: 'Screen 3');
  });

  testWidgetsWithSemantics('the field labels are drawn shouted and announced '
      'in sentence case', (tester) async {
    await _Harness().pump(tester);

    // Positive control: the shouted label IS on screen, so the two assertions
    // below are about the semantics rather than about a screen that never
    // built its labels.
    expect(find.text('AVERAGE CYCLE LENGTH'), findsOneWidget);
    expect(find.text('REGULARITY'), findsOneWidget);

    expect(find.bySemanticsLabel('Average cycle length'), findsOneWidget);
    expect(find.bySemanticsLabel('Regularity'), findsOneWidget);
    expect(find.bySemanticsLabel('AVERAGE CYCLE LENGTH'), findsNothing);
    expect(find.bySemanticsLabel('REGULARITY'), findsNothing);
  });

  testWidgetsWithSemantics('a cycle-length chip announces its unit, not a bare '
      'number', (tester) async {
    await _Harness().pump(tester);

    // Drawn as the mockup draws it…
    expect(
      find.descendant(of: announcing('28 days'), matching: find.text('28')),
      findsOneWidget,
    );
    // …and announced as something a person can act on. "28" alone answers no
    // question; `definitions.md` gives these chips the unit, and screen 32
    // renders it ("29 days").
    expectLabeledButton(
      tester,
      announcing('28 days'),
      '28 days',
      exactLabel: true,
    );
    expect(announcing('28'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // The calendar, and the one correctness requirement in it
  // -------------------------------------------------------------------------

  testWidgets('the week starts where the LOCALE says, not where the mockup '
      'drew it', (tester) async {
    // April 2026 opens on a Wednesday. Under es-ES (Monday-first) that is the
    // third column; under en-US (Sunday-first) the fourth. Getting this wrong
    // shifts every date in the grid by one column — a wrong date, not a wrong
    // pixel.
    await _Harness(deviceLocale: 'es-ES').pump(tester);

    final spanish = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    // The seven headings, in the order they are drawn.
    expect(
      spanish.sublist(spanish.indexOf('M'), spanish.indexOf('M') + 7),
      <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'],
    );
    final spanishFirst = _columnOf(tester, '1');

    await tester.pumpWidget(const SizedBox.shrink());

    await _Harness(deviceLocale: 'en-US').pump(tester);

    final american = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(
      american.sublist(american.indexOf('S'), american.indexOf('S') + 7),
      <String>['S', 'M', 'T', 'W', 'T', 'F', 'S'],
    );

    // The load-bearing half: the heading row could be right while the days
    // below it were laid out from a fixed offset. Under a Sunday-first locale
    // the 1st moves exactly one column to the RIGHT.
    expect(_columnOf(tester, '1'), greaterThan(spanishFirst));
  });

  testWidgetsWithSemantics('today can be chosen; tomorrow is announced but is '
      'not a control', (tester) async {
    await _Harness(today: Date(2026, 4, 20)).pump(tester);

    // The ACCEPTING boundary: the server rejects only `> today`, so today
    // itself is a real answer and refusing it would lose one.
    expectLabeledButton(
      tester,
      announcing('20/4/2026'),
      '20/4/2026',
      exactLabel: true,
    );

    // The rejecting one, in the same test so the pair discriminates: a screen
    // with no calendar at all would satisfy either alone.
    expect(announcing('21/4/2026'), findsOneWidget);
    expectNotAButton(tester, announcing('21/4/2026'));
  });

  testWidgetsWithSemantics('choosing a day marks it selected', (tester) async {
    await _Harness(today: Date(2026, 4, 20)).pump(tester);

    // Premise: nothing is selected before the tap, so the flag below is a fact
    // about the tap and not about a cell that renders selected always.
    expect(isSelected(tester, announcing('6/4/2026')), isFalse);

    await tester.tap(announcing('6/4/2026'));
    await tester.pump();

    expect(isSelected(tester, announcing('6/4/2026')), isTrue);
    expect(isSelected(tester, announcing('7/4/2026')), isFalse);
  });

  testWidgets('it opens on the month the user already answered', (
    tester,
  ) async {
    await _Harness(
      resumeAnchor: Date(2026, 3, 9),
      today: Date(2026, 4, 20),
    ).pump(tester);

    // March 2026, not April: the resume read had an answer, and showing the
    // current month would hide it.
    expect(find.text('3/2026'), findsOneWidget);
    expect(find.text('31'), findsOneWidget, reason: 'March has 31 days');
  });

  // -------------------------------------------------------------------------
  // Submitting
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('Continue is inert until a day is chosen', (
    tester,
  ) async {
    final harness = _Harness(today: Date(2026, 4, 20))..answerSave();
    await harness.pump(tester);

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason:
          'the endpoint requires lastPeriodStart on every post, and it is the '
          'one mandatory answer of onboarding',
    );

    await tester.tap(announcing('6/4/2026'));
    await tester.pump();

    // The control: the same button, enabled and named, once the mandatory
    // answer exists.
    expectLabeledButton(
      tester,
      find.byType(FilledButton),
      'Continue',
      exactLabel: true,
    );

    await tester.tap(find.text('Continue'));
    await tester.pump();

    verify(
      () => harness.onboardingRepo.saveCycle(
        lastPeriodStart: Date(2026, 4, 6),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    ).called(1);
  });

  testWidgetsWithSemantics('a rejection is announced and names the field', (
    tester,
  ) async {
    final harness = _Harness(today: Date(2026, 4, 20))
      ..rejectSave(
        const ValidationFailure(
          message: 'The request contained invalid data.',
          fields: <String, List<String>>{
            'lastPeriodStart': <String>[
              'date is before the earliest allowed date',
            ],
          },
        ),
      );
    await harness.pump(tester);

    // Control: no banner before the attempt. "No banner" is also the state of
    // a screen that never renders one.
    expect(find.byType(LumenErrorBanner), findsNothing);

    await tester.tap(announcing('6/4/2026'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(LumenErrorBanner), findsOneWidget);
    // The server's own words, under the calendar. This is the ONLY way the
    // backdate floor reaches the user: it is `users.created_at - 2 years` and
    // no endpoint returns `created_at`.
    expect(
      find.text('date is before the earliest allowed date'),
      findsOneWidget,
    );
  });

  testWidgetsWithSemantics('a warned save shows an advisory, and it announces '
      'itself', (tester) async {
    final harness = _Harness(today: Date(2026, 4, 20))
      ..answerSave(
        onboardingCycleFixture(
          warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
        ),
      );
    await harness.pump(tester);

    const advisory =
        "Saved. That cycle length is unusual — double-check the number if it "
        "wasn't intended.";

    // Control: the note is absent before the save. It is an advisory ABOUT a
    // save, so a screen showing it up front would be describing nothing.
    expect(find.text(advisory), findsNothing);

    await tester.tap(announcing('6/4/2026'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text(advisory), findsOneWidget);
    // Nothing failed: the value was stored and the band never blocks a write.
    expect(find.byType(LumenErrorBanner), findsNothing);
    expectLiveRegion(tester, advisory);
  });

  testWidgets('a clean save shows no advisory at all', (tester) async {
    final harness = _Harness(today: Date(2026, 4, 20))..answerSave();
    await harness.pump(tester);

    await tester.tap(announcing('6/4/2026'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The control for the test above, and the reason an unknown code renders
    // nothing: no copy is authored for a warning the server did not send.
    expect(find.textContaining('double-check'), findsNothing);
  });

  test('an unknown warning code has no copy, and none is invented', () {
    expect(
      cycleWarningMessage('avg_cycle_length_out_of_sanity_band'),
      isNotNull,
    );
    expect(cycleWarningMessage('some_future_code'), isNull);
  });

  // -------------------------------------------------------------------------
  // The state with nothing to draw
  // -------------------------------------------------------------------------

  testWidgets('with no month to open, it offers a retry that re-reads', (
    tester,
  ) async {
    final harness = _Harness(todayFailure: const NetworkFailure());
    await harness.pump(tester);

    expect(find.text('When did your last period start?'), findsNothing);
    await expectRetryReissuesOneRequest(
      tester,
      requestCount: () => harness.settingsCalls,
      label: 'Try again',
    );
  });

  testWidgetsWithSemantics('a failed settings read still lets the user answer '
      'the mandatory question', (tester) async {
    final harness = _Harness(
      resumeAnchor: Date(2026, 4, 6),
      settingsFailure: const NetworkFailure(),
    )..answerSave();
    await harness.pump(tester);

    // The screen is usable: the anchor came from the other read, so the one
    // mandatory answer can still be given and corrected.
    expect(find.text('When did your last period start?'), findsOneWidget);
    // …and neither self-report is shown as chosen, because nothing knows what
    // they are. Drawing 28 / Somewhat here is exactly what would overwrite
    // them on the next save.
    for (final days in kAvgCycleLengthQuickPicks) {
      expect(
        isSelected(tester, announcing('$days days')),
        isFalse,
        reason: 'chip $days must not look chosen when nothing was read',
      );
    }

    // Control: with a working read the chip the server named IS chosen.
    await tester.pumpWidget(const SizedBox.shrink());
    await _Harness(
      resumeAnchor: Date(2026, 4, 6),
      settings: cycleSettingsFixture(avgCycleLengthDays: 29),
    ).pump(tester);
    expect(isSelected(tester, announcing('29 days')), isTrue);
  });

  testWidgetsWithSemantics('a stored length outside the five quick picks gets '
      'its own chip', (tester) async {
    await _Harness(
      resumeAnchor: Date(2026, 4, 6),
      settings: cycleSettingsFixture(avgCycleLengthDays: 33),
    ).pump(tester);

    // The column is a free positive smallint and screen 32 sets values outside
    // the mockup's five. Hiding a stored 33 behind an unselected row would make
    // the next save look like a fresh answer.
    expect(
      find.descendant(of: announcing('33 days'), matching: find.text('33')),
      findsOneWidget,
    );
    expect(isSelected(tester, announcing('33 days')), isTrue);
    // Control: the five quick picks are still there, and none of them is
    // pretending to be the answer.
    expect(announcing('28 days'), findsOneWidget);
    expect(isSelected(tester, announcing('28 days')), isFalse);
  });

  testWidgetsWithSemantics('trying a quick pick does not destroy the way back '
      'to a stored value', (tester) async {
    await _Harness(
      resumeAnchor: Date(2026, 4, 6),
      settings: cycleSettingsFixture(avgCycleLengthDays: 33),
    ).pump(tester);

    expect(isSelected(tester, announcing('33 days')), isTrue);

    await tester.tap(announcing('30 days'));
    await tester.pump();

    // A row derived from the SELECTION alone loses the 33 the moment anything
    // else is tapped — and with it the only affordance that could put the
    // user's own answer back. Continue would then write 30 over it.
    expect(isSelected(tester, announcing('30 days')), isTrue);
    expect(announcing('33 days'), findsOneWidget);
    expect(isSelected(tester, announcing('33 days')), isFalse);

    // …and it is the real chip, not a leftover label.
    await tester.tap(announcing('33 days'));
    await tester.pump();
    expect(isSelected(tester, announcing('33 days')), isTrue);
    expect(isSelected(tester, announcing('30 days')), isFalse);
  });
}
