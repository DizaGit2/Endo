// Semantics + behaviour for screen 4 (P4b-T10).
//
// Three things on this screen are correctness rather than polish:
//
//   * "Continue" with nothing filled in must issue NO request. The step is
//     skippable (D-02) and `POST /onboarding/baseline` answers 400 to a body
//     carrying none of its fields — the only endpoint on the P4a surface with
//     that check — so a skip that posted would show the user an error for doing
//     nothing wrong;
//   * a typed weight is read in the LOCALE's convention ("62,5" is
//     sixty-two-and-a-half in es-ES) and cannot carry more than the one decimal
//     place the backend stores;
//   * the date of birth has an upper bound and NO lower one. C-12 makes the
//     population a design target, explicitly "not a data-entry/age gate", and
//     the server applies no floor either.
//
// Everything else here is the a11y rule set the phase already ships.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/baseline_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/onboarding/application/baseline_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/onboarding/presentation/baseline_screen.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockMeRepository extends Mock implements MeRepository {}

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

class _SettledFlow extends OnboardingFlowController {
  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: OnboardingStep.baseline,
      state: onboardingStateFixture(cycleProvided: true),
    ),
  );
}

class _Harness {
  _Harness({
    MeResponse? profile,
    Failure? profileFailure,
    Date? today,
    Failure? todayFailure,
    String deviceLocale = 'es-ES',
  }) {
    if (profileFailure != null) {
      when(
        meRepo.getMe,
      ).thenAnswer((_) async => NetworkRequired<MeResponse>(profileFailure));
    } else {
      when(meRepo.getMe).thenAnswer(
        (_) async => Fresh<MeResponse>(profile ?? meResponseFixture()),
      );
    }

    if (todayFailure != null) {
      when(todayRepo.today).thenAnswer((_) async => throw todayFailure);
    } else {
      when(todayRepo.today).thenAnswer((_) async => today ?? Date(2026, 4, 20));
    }

    overrides = <Override>[
      ...lumenOverrides(),
      deviceLocaleProvider.overrideWithValue(deviceLocale),
      onboardingFlowControllerProvider.overrideWith(_SettledFlow.new),
      meRepositoryProvider.overrideWithValue(meRepo),
      serverTodayRepositoryProvider.overrideWithValue(todayRepo),
      onboardingRepositoryProvider.overrideWithValue(onboardingRepo),
    ];
  }

  final _MockMeRepository meRepo = _MockMeRepository();
  final _MockServerTodayRepository todayRepo = _MockServerTodayRepository();
  final _MockOnboardingRepository onboardingRepo = _MockOnboardingRepository();
  late final List<Override> overrides;

  void answerSave([BaselineResponse? body]) {
    when(
      () => onboardingRepo.saveBaseline(
        dob: any(named: 'dob'),
        heightCm: any(named: 'heightCm'),
        weightKg: any(named: 'weightKg'),
        endoStatus: any(named: 'endoStatus'),
      ),
    ).thenAnswer((_) async => body ?? baselineFixture());
  }

  void rejectSave(Failure failure) {
    when(
      () => onboardingRepo.saveBaseline(
        dob: any(named: 'dob'),
        heightCm: any(named: 'heightCm'),
        weightKg: any(named: 'weightKg'),
        endoStatus: any(named: 'endoStatus'),
      ),
    ).thenAnswer((_) async => throw failure);
  }

  VerificationResult verifySaves() => verify(
    () => onboardingRepo.saveBaseline(
      dob: captureAny(named: 'dob'),
      heightCm: captureAny(named: 'heightCm'),
      weightKg: captureAny(named: 'weightKg'),
      endoStatus: captureAny(named: 'endoStatus'),
    ),
  );

  void verifyNoSave() => verifyNever(
    () => onboardingRepo.saveBaseline(
      dob: any(named: 'dob'),
      heightCm: any(named: 'heightCm'),
      weightKg: any(named: 'weightKg'),
      endoStatus: any(named: 'endoStatus'),
    ),
  );

  /// The frame the shell puts around a step body — [onboardingStepHost], built
  /// out of the shell's own insets and its own step slot, so this file drives
  /// screen 4 under the constraints it actually ships under.
  Future<ProviderContainer> pump(WidgetTester tester, {bool settle = true}) async {
    final container = await pumpApp(
      tester,
      home: onboardingStepHost(const BaselineScreen()),
      overrides: overrides,
      settle: settle,
    );
    // The flow is autoDispose and the SHELL is what watches it in the app;
    // this file mounts the step body alone, so without a subscription the
    // `ref.read(...notifier)` inside `_advance` would build it, move it and
    // watch it disposed in the same turn.
    container.listen(onboardingFlowControllerProvider, (_, _) {});
    return container;
  }
}

/// The editable inside the [LumenInputField] whose accessible name is [label].
Finder _fieldNamed(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (Widget widget) => widget is LumenInputField && widget.label == label,
    description: 'the "$label" input',
  ),
  matching: find.byType(TextField),
);

/// What the unit inside a field is actually PAINTED at.
///
/// Material renders `suffixText` through `_AffixText`, which wraps it in
/// `AnimatedOpacity(opacity: labelIsFloating ? 1.0 : 0.0)`
/// (`input_decorator.dart:1827-1830`). On an empty, unfocused field that is
/// zero, so the unit is in the tree and reserving its strip while being
/// invisible — a distinction `find.text` cannot make and a golden diff of a
/// 14 px strip is easy to wave through.
double _suffixOpacity(WidgetTester tester, String suffix) {
  return tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.text(suffix),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;
}

/// A control, located by what it ANNOUNCES rather than by what it draws.
Finder announcing(String label) => find.bySemanticsLabel(label);

/// Taps [year] in the open picker's year grid, scrolling it into view first.
///
/// The grid runs from [kDobFloor] to the server's today and opens anchored on
/// today's year, so any date of birth worth entering is off-screen above it.
/// That is the cost of having no lower bound, and it is a scroll rather than a
/// wall — which is the difference this control is built around.
Future<void> _tapYear(WidgetTester tester, String year) async {
  final Finder target = find.text(year);
  final Finder grid = find.byType(GridView);
  for (var attempt = 0; attempt < 400 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(grid, const Offset(0, 300));
    await tester.pump();
  }
  // The grid builds a cache extent beyond its clip, so "in the tree" is not
  // yet "tappable" — this is what puts the cell inside the viewport.
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// The seven weekday initials the open date picker draws, in drawn order.
///
/// Read off the `Text` widgets Material's own day-header row builds, so this
/// is what the user sees rather than what a localizations lookup answers.
List<String> _weekdayHeader(WidgetTester tester) {
  final letters = tester
      .widgetList<Text>(find.byType(Text))
      .map((Text t) => t.data)
      .whereType<String>()
      .where((String d) => d.length == 1 && RegExp('[A-Z]').hasMatch(d))
      .toList();
  return letters.sublist(0, 7);
}

/// Whether the node at [finder] announces itself as selected.
bool isSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isSelected ==
    Tristate.isTrue;

void main() {
  // -------------------------------------------------------------------------
  // What it says
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('it renders the mockup\'s copy and no dingbats', (
    tester,
  ) async {
    await _Harness().pump(tester);

    expect(find.text('A few baseline details'), findsOneWidget);
    expect(
      find.text('Used to personalize hormone ranges. Edit anytime.'),
      findsOneWidget,
    );
    expect(find.text('Diagnosed'), findsOneWidget);
    expect(find.text('Suspected, undiagnosed'), findsOneWidget);
    expect(find.text('Not applicable'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    expectNoDingbats(tester, screen: 'Screen 4');
  });

  testWidgetsWithSemantics('it draws no rASRM stage control and no diagnosis '
      'month, because the mockup draws neither', (tester) async {
    // Both are real columns with a real write path, and both are deliberately
    // unbuilt: `Screens/screen_04_baseline.html` has no control for either and
    // `definitions.md` carries no copy for one. Inventing a stage control would
    // mean authoring clinical wording — and C-14 is explicit that rASRM does
    // not correlate with pain, so there is no safe default sentence to write.
    await _Harness(
      profile: meResponseFixture(rasrmStage: 3, diagnosedOn: '2026-08'),
    ).pump(tester);

    // The positive control first: the screen DID render, and it did read the
    // profile — so the absences below are facts about this screen rather than
    // about a tree that never built.
    expect(find.text('A few baseline details'), findsOneWidget);
    expect(find.text('ENDOMETRIOSIS STATUS'), findsOneWidget);

    expect(find.textContaining('stage', findRichText: true), findsNothing);
    expect(find.text('III'), findsNothing);
    expect(find.textContaining('2026'), findsNothing);
  });

  testWidgetsWithSemantics('the field labels are drawn shouted and announced '
      'in sentence case', (tester) async {
    await _Harness().pump(tester);

    // Positive control: the shouted labels ARE on screen, so the assertions
    // below are about the semantics rather than about labels that never built.
    expect(find.text('DATE OF BIRTH'), findsOneWidget);
    expect(find.text('HEIGHT'), findsOneWidget);
    expect(find.text('WEIGHT'), findsOneWidget);
    expect(find.text('ENDOMETRIOSIS STATUS'), findsOneWidget);

    // The group label is announced: what it names is three separate buttons,
    // and nothing else would say what they are for.
    expect(find.bySemanticsLabel('Endometriosis status'), findsOneWidget);
    expect(find.bySemanticsLabel('ENDOMETRIOSIS STATUS'), findsNothing);
    expect(find.bySemanticsLabel('HEIGHT'), findsNothing);

    // The three labels whose CONTROL already carries the same name are drawn
    // and not announced — one node each, not two. A second, unassociated
    // "Date of birth" immediately before the box that is called Date of birth
    // is noise in the reading order. (The two fields announce "Height\ncm"
    // while they are empty — Flutter appends the placeholder — hence the
    // anchored patterns rather than equality.)
    expect(find.bySemanticsLabel('Date of birth'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Height')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Weight')), findsOneWidget);
  });

  testWidgetsWithSemantics('the two measurements are named fields, not bare '
      'placeholders', (tester) async {
    await _Harness().pump(tester);

    // The units are painted on the EMPTY form — the state a first-time user
    // starts in, and the one the old `hint: 'cm'` did serve.
    //
    // Asserted by OPACITY, not by presence. Material lays a suffix out and
    // paints it at zero on an empty, unfocused field
    // (`input_decorator.dart:1827-1830, 1969, 2434`), so `find.text('cm')`
    // passes against a unit nobody can see — which is how this shipped once:
    // a presence check written to prove a persistence fix. The presence line
    // stays as the finder's premise; the opacity line is the assertion.
    expect(find.text('cm'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(_suffixOpacity(tester, 'cm'), 1.0);
    expect(_suffixOpacity(tester, 'kg'), 1.0);

    // The T5b failure this guard exists for: a field with only hint text
    // announces its PLACEHOLDER, and the label drawn above it is associated
    // with nothing.
    expectLabeledField(tester, _fieldNamed('Height'), 'Height');
    expectLabeledField(tester, _fieldNamed('Weight'), 'Weight');
  });

  // -------------------------------------------------------------------------
  // The status options
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('choosing a status marks it selected', (
    tester,
  ) async {
    await _Harness().pump(tester);

    // Premise: nothing is chosen before the tap. There is no default — an
    // unanswered question stays null — so a screen that pre-selected
    // "Diagnosed" would be recording an answer the user never gave.
    expect(isSelected(tester, announcing('Diagnosed')), isFalse);
    expect(isSelected(tester, announcing('Not applicable')), isFalse);

    await tester.tap(announcing('Not applicable'));
    await tester.pump();

    expect(isSelected(tester, announcing('Not applicable')), isTrue);
    expect(isSelected(tester, announcing('Diagnosed')), isFalse);
    expectLabeledButton(
      tester,
      announcing('Not applicable'),
      'Not applicable',
      exactLabel: true,
    );
  });

  testWidgetsWithSemantics('a stored status comes back chosen', (tester) async {
    await _Harness(
      profile: meResponseFixture(endoStatus: 'suspected'),
    ).pump(tester);

    expect(isSelected(tester, announcing('Suspected, undiagnosed')), isTrue);
    // The control: the other two are not.
    expect(isSelected(tester, announcing('Diagnosed')), isFalse);
    expect(isSelected(tester, announcing('Not applicable')), isFalse);
  });

  // -------------------------------------------------------------------------
  // The measurements
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a weight is read in the LOCALE\'s convention', (
    tester,
  ) async {
    final spanish = _Harness(deviceLocale: 'es-ES')..answerSave();
    await spanish.pump(tester);

    await tester.enterText(_fieldNamed('Weight'), '62,5');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect((spanish.verifySaves()..called(1)).captured[2], 62.5);

    // The control that makes the row above a fact about the LOCALE: the same
    // digits with the same separator under en-US are not sixty-two and a half,
    // and the period that is are.
    await tester.pumpWidget(const SizedBox.shrink());

    final american = _Harness(deviceLocale: 'en-US')..answerSave();
    await american.pump(tester);

    await tester.enterText(_fieldNamed('Weight'), '62.5');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect((american.verifySaves()..called(1)).captured[2], 62.5);
  });

  testWidgetsWithSemantics('the weight field takes at most ONE decimal', (
    tester,
  ) async {
    final harness = _Harness(deviceLocale: 'en-US')..answerSave();
    await harness.pump(tester);

    // The backend REJECTS more precision rather than rounding it
    // (`OnboardingStepsService.cs:192-197`), and rounding it away here would
    // store a number the user did not type. So the field never takes it.
    await tester.enterText(_fieldNamed('Weight'), '62.55');
    await tester.pump();
    expect(tester.widget<TextField>(_fieldNamed('Weight')).controller!.text,
        isNot('62.55'));

    // The control: one decimal place is accepted, so the row above is a fact
    // about the second digit and not about a field that refuses everything.
    await tester.enterText(_fieldNamed('Weight'), '62.5');
    await tester.pump();
    expect(
      tester.widget<TextField>(_fieldNamed('Weight')).controller!.text,
      '62.5',
    );
  });

  testWidgetsWithSemantics('a stored height and weight come back in the field',
      (tester) async {
    await _Harness(
      profile: meResponseFixture(heightCm: 165, latestWeightKg: 62.4),
      deviceLocale: 'es-ES',
    ).pump(tester);

    expect(
      tester.widget<TextField>(_fieldNamed('Height')).controller!.text,
      '165',
    );
    expect(
      tester.widget<TextField>(_fieldNamed('Weight')).controller!.text,
      '62,4',
    );
    // …and the units are painted beside them. This is the state a hint could
    // not survive: the field is non-empty from its first frame. It is also the
    // state Material paints a suffix in *anyway*, which is why the empty-form
    // assertion above is the one that discriminates.
    expect(_suffixOpacity(tester, 'cm'), 1.0);
    expect(_suffixOpacity(tester, 'kg'), 1.0);
  });

  // -------------------------------------------------------------------------
  // The date of birth
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('the picker is bounded ABOVE by the server\'s '
      'today and below by nothing', (tester) async {
    await _Harness(today: Date(2026, 4, 20)).pump(tester);

    await tester.tap(announcing('Date of birth'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    // The server rejects `dob > today` and nothing else
    // (`OnboardingStepsService.cs:172-173`).
    expect(dialog.lastDate, DateTime(2026, 4, 20));
    // …and there is NO age gate. C-12 makes the population a design target,
    // "not a data-entry/age gate", and the server's own floor is `DateOnly`
    // itself. Year 1 is that domain; a "born before 19xx" floor would be an
    // age gate under another name.
    expect(dialog.firstDate, DateTime(1));
  });

  testWidgetsWithSemantics('the picker\'s "today" is the SERVER\'s, not the '
      'device\'s', (tester) async {
    // Unset, `currentDate` falls back to `calendarDelegate.now()`
    // (`date_picker.dart:338`) — the device clock D-12 forbids — and this
    // screen then paints that marker with an accent ring, so a phone a day
    // fast would ring the first day `lastDate` refuses.
    //
    // TWO server todays, decades apart, in one test: no device clock can
    // satisfy both, so this cannot pass by coincidence on the machine that
    // runs it. That pair IS the control — a single date would agree with a
    // fallback clock on exactly one day of the year.
    await _Harness(today: Date(2026, 4, 20)).pump(tester);
    await tester.tap(announcing('Date of birth'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .currentDate,
      DateTime(2026, 4, 20),
    );

    await tester.pumpWidget(const SizedBox.shrink());

    await _Harness(today: Date(2019, 1, 1)).pump(tester);
    await tester.tap(announcing('Date of birth'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .currentDate,
      DateTime(2019, 1, 1),
    );
  });

  testWidgetsWithSemantics('the picker starts the week where the LOCALE says, '
      'not where Material\'s default does', (tester) async {
    // The app wires no `localizationsDelegates`, so without the override the
    // dialog resolves `DefaultMaterialLocalizations`, whose
    // `firstDayOfWeekIndex` is 0 — Sunday — for every locale. Screen 3's grid
    // is Monday-first under es-ES, and these two screens are one Back tap
    // apart.
    await _Harness(
      today: Date(2026, 4, 20),
      deviceLocale: 'es-ES',
    ).pump(tester);
    await tester.tap(announcing('Date of birth'));
    await tester.pumpAndSettle();

    // Premise: the ambient localizations really do say Sunday, so what is
    // asserted below is the override doing its job and not the default
    // happening to agree.
    expect(
      MaterialLocalizations.of(
        tester.element(find.byType(BaselineScreen)),
      ).firstDayOfWeekIndex,
      0,
    );
    expect(
      MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)),
      ).firstDayOfWeekIndex,
      1,
    );

    // …and it reaches the pixels, not just the lookup: the drawn header row
    // starts on Monday. (Tapping a year switches the picker to the day grid.)
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    expect(_weekdayHeader(tester), <String>['M', 'T', 'W', 'T', 'F', 'S', 'S']);

    // The control: the same screen under en-US draws Sunday first, so the row
    // above is a fact about the locale rather than a second hard-coding.
    await tester.pumpWidget(const SizedBox.shrink());
    await _Harness(
      today: Date(2026, 4, 20),
      deviceLocale: 'en-US',
    ).pump(tester);
    await tester.tap(announcing('Date of birth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    expect(_weekdayHeader(tester), <String>['S', 'M', 'T', 'W', 'T', 'F', 'S']);
  });

  testWidgetsWithSemantics('confirming without choosing records NOTHING', (
    tester,
  ) async {
    final harness = _Harness(today: Date(2026, 4, 20))..answerSave();
    await harness.pump(tester);

    await tester.tap(announcing('Date of birth'));
    await tester.pumpAndSettle();

    // `initialDate` seeds `_selectedDate`, which is what OK pops
    // (`date_picker.dart:468,507`). Seeded with today, an accidental OK writes
    // a date of birth the user never entered — onto a field §C.0.1 gives no
    // way to clear.
    expect(
      tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .initialDate,
      isNull,
    );

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The control is the test below: a date actually chosen DOES travel, so
    // this is a fact about the untouched picker and not about a screen whose
    // date of birth never reaches the wire.
    harness.verifyNoSave();
  });

  testWidgetsWithSemantics('a chosen date of birth travels', (tester) async {
    final harness = _Harness(today: Date(2026, 4, 20))..answerSave();
    await harness.pump(tester);

    await tester.tap(announcing('Date of birth'));
    await tester.pumpAndSettle();
    // Year first (the picker opens on the year grid), then the day.
    await _tapYear(tester, '1996');
    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect((harness.verifySaves()..called(1)).captured[0], Date(1996, 4, 6));
  });

  testWidgetsWithSemantics('an empty picker opens on the server\'s today, not '
      'on the bottom of the range', (tester) async {
    // The year grid anchors on `_currentDisplayedMonthDate`
    // (`calendar_date_picker.dart:372`), which is `initialDate ?? currentDate`
    // (`:217`). With `initialDate` null — as it must be, see above — the ONLY
    // thing standing between an empty picker and a two-thousand-year scroll
    // back from year 1 is `currentDate`.
    await _Harness(today: Date(2026, 4, 20)).pump(tester);
    await tester.tap(announcing('Date of birth'));
    await tester.pumpAndSettle();

    expect(find.text('2026'), findsOneWidget);
    // The control: year 1 IS in the range — there is no floor above it — and
    // is simply nowhere near the viewport.
    expect(find.text('1'), findsNothing);
  });

  testWidgetsWithSemantics('with no today the picker cannot be opened, and no '
      'bound is guessed', (tester) async {
    final harness = _Harness(todayFailure: const NetworkFailure());
    await harness.pump(tester);

    // D-12: the only thing left to derive a bound from is the device clock.
    expect(announcing('Date of birth'), findsOneWidget);
    expectNotAButton(tester, announcing('Date of birth'));

    // The control: with a today it IS a button.
    await tester.pumpWidget(const SizedBox.shrink());
    await _Harness(today: Date(2026, 4, 20)).pump(tester);
    expectLabeledButton(
      tester,
      announcing('Date of birth'),
      'Date of birth',
      exactLabel: true,
    );
  });

  // -------------------------------------------------------------------------
  // Continue — the skip path
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('Continue with nothing filled in posts nothing', (
    tester,
  ) async {
    final harness = _Harness()..answerSave();
    final container = await harness.pump(tester);

    // The CTA is ENABLED with nothing answered — this step is skippable and
    // Continue is the only way past it. A disabled button here would trap the
    // user on an optional question.
    expectLabeledButton(
      tester,
      find.byType(FilledButton),
      'Continue',
      exactLabel: true,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    harness.verifyNoSave();
    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.goals,
    );
  });

  testWidgetsWithSemantics('an answered step DOES post — the control for the '
      'skip path', (tester) async {
    final harness = _Harness()..answerSave();
    await harness.pump(tester);

    await tester.tap(announcing('Diagnosed'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect((harness.verifySaves()..called(1)).captured[3], 'diagnosed');
  });

  // -------------------------------------------------------------------------
  // States
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a rejection is announced and names the field', (
    tester,
  ) async {
    final harness = _Harness(deviceLocale: 'en-US')
      ..rejectSave(
        const ValidationFailure(
          message: 'The request contained invalid data.',
          fields: <String, List<String>>{
            'weightKg': <String>['value must be greater than 0 and at most '
                '9999.9'],
          },
        ),
      );
    await harness.pump(tester);

    // Control: no banner before the attempt. "No banner" is also the state of
    // a screen that never renders one.
    expect(find.byType(LumenErrorBanner), findsNothing);

    await tester.enterText(_fieldNamed('Weight'), '0');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(LumenErrorBanner), findsOneWidget);
    // The server's own words, under the field it named. The structural bound
    // behind them is not restated on this side of the wire.
    expect(
      find.text('value must be greater than 0 and at most 9999.9'),
      findsOneWidget,
    );
  });

  testWidgetsWithSemantics('the resume read reports itself while it is '
      'loading', (tester) async {
    final harness = _Harness();
    // A read that never answers — the only honest way to hold the loading
    // surface still long enough to assert on it.
    when(
      harness.meRepo.getMe,
    ).thenAnswer((_) => Completer<CacheResult<MeResponse>>().future);
    await harness.pump(tester, settle: false);

    expectLabeledSpinner(tester, 'Loading');
  });

  testWidgetsWithSemantics('a failed profile read still lets the user answer',
      (tester) async {
    final harness = _Harness(profileFailure: const NetworkFailure())
      ..answerSave();
    await harness.pump(tester);

    // The step is skippable and skipping needs no network, so a failed prefill
    // must never take the screen away.
    expect(find.text('A few baseline details'), findsOneWidget);
    expect(find.byType(LumenErrorBanner), findsOneWidget);

    // …and nothing is drawn as chosen, because nothing knows what the answers
    // are. Drawing a default here is exactly what would overwrite one.
    for (final status in EndoStatus.values) {
      expect(
        isSelected(tester, announcing(status.label)),
        isFalse,
        reason: '${status.label} must not look chosen when nothing was read',
      );
    }

    // The control: with a working read the option the server named IS chosen.
    await tester.pumpWidget(const SizedBox.shrink());
    await _Harness(
      profile: meResponseFixture(endoStatus: 'diagnosed'),
    ).pump(tester);
    expect(isSelected(tester, announcing('Diagnosed')), isTrue);
  });
}
