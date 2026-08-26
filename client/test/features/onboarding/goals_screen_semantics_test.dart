// Semantics + behaviour for screen 5 (P4b-T11).
//
// Three things on this screen are correctness rather than polish:
//
//   * the list it draws is the SERVER's. `POST /onboarding/goals` and
//     `GET /onboarding/state` both answer the complete vocabulary in frozen
//     order with a boolean per code, and the screen renders that — so the
//     fixtures below hand it a list that contradicts the ratified seed, in an
//     order the client would not have produced, and assert it followed the wire;
//   * Continue writes a FULL REPLACE. A code left out of the array is stored as
//     DESELECTED (`OnboardingStepsService.cs:381-407`), so an untouched-but-
//     selected goal has to travel or the user's earlier answer is discarded;
//   * an empty selection is a 400 whose message is `select at least one goal`
//     (`OnboardingStepResult.cs:371`) — not the generic `value is required`,
//     because the field WAS supplied. The screen states that rule with the
//     server's own sentence rather than one it invented.
//
// Controls are located by KEY or TYPE throughout (`goalTileKey`,
// `find.byType(FilledButton)`), never by what they announce — the T5c rule:
// `find.bySemanticsLabel` appears only inside assertions ABOUT what is
// announced, so a semantics change elsewhere cannot redden a test by failing
// inside `tester.tap`.
//
// Everything else here is the a11y rule set the phase already ships.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/goals_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/goals_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/onboarding/presentation/goals_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// The shell's flow, settled on step 5 carrying [goals] as its resume read.
class _SettledFlow extends OnboardingFlowController {
  _SettledFlow(this.goals);

  final Map<String, bool>? goals;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: OnboardingStep.goals,
      state: onboardingStateFixture(cycleProvided: true, goals: goals),
    ),
  );
}

class _Harness {
  _Harness({Map<String, bool>? goals}) {
    overrides = <Override>[
      ...lumenOverrides(),
      onboardingFlowControllerProvider.overrideWith(() => _SettledFlow(goals)),
      onboardingRepositoryProvider.overrideWithValue(repo),
    ];
  }

  final _MockOnboardingRepository repo = _MockOnboardingRepository();
  late final List<Override> overrides;

  void answerSave([GoalsResponse? body]) {
    when(
      () => repo.saveGoals(codes: any(named: 'codes')),
    ).thenAnswer((_) async => body ?? goalsResponseFixture());
  }

  void rejectSave(Failure failure) {
    when(
      () => repo.saveGoals(codes: any(named: 'codes')),
    ).thenAnswer((_) async => throw failure);
  }

  /// Holds the save open so the in-flight surface can be asserted on.
  Completer<GoalsResponse> holdSave() {
    final completer = Completer<GoalsResponse>();
    when(
      () => repo.saveGoals(codes: any(named: 'codes')),
    ).thenAnswer((_) => completer.future);
    return completer;
  }

  /// The array the repository was actually handed. Captured ONCE per call —
  /// `verify` consumes the recorded invocation.
  List<String> get postedCodes =>
      verify(
            () => repo.saveGoals(codes: captureAny(named: 'codes')),
          ).captured.last
          as List<String>;

  void verifyNoSave() =>
      verifyNever(() => repo.saveGoals(codes: any(named: 'codes')));

  /// The frame the shell puts around a step body — [onboardingStepHost], built
  /// out of the shell's own insets and its own step slot, so this file drives
  /// screen 5 under the constraints it actually ships under.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool settle = true,
  }) async {
    final container = await pumpApp(
      tester,
      home: onboardingStepHost(const GoalsScreen()),
      overrides: overrides,
      settle: settle,
    );
    // The flow is autoDispose and the SHELL is what watches it in the app;
    // this file mounts the step body alone, so without a subscription the
    // `ref.read(...notifier)` inside the advance would build it, move it and
    // watch it disposed in the same turn.
    container.listen(onboardingFlowControllerProvider, (_, _) {});
    return container;
  }
}

/// One goal row, by its stable handle.
Finder _tile(String code) => find.byKey(goalTileKey(code));

/// Whether the node at [finder] announces itself as selected.
bool _isSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isSelected ==
    Tristate.isTrue;

/// The codes whose rows are drawn, top to bottom.
List<String> _drawnOrder(WidgetTester tester, List<String> candidates) {
  final drawn = <String>[
    for (final String code in candidates)
      if (_tile(code).evaluate().isNotEmpty) code,
  ];
  drawn.sort(
    (String a, String b) => tester
        .getTopLeft(_tile(a))
        .dy
        .compareTo(tester.getTopLeft(_tile(b)).dy),
  );
  return drawn;
}

void main() {
  setUpAll(() => registerFallbackValue(const <String>['manage_symptoms']));

  // -------------------------------------------------------------------------
  // What it says
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('it renders the mockup\'s copy and no dingbats', (
    tester,
  ) async {
    await _Harness().pump(tester);

    expect(find.text('What brings you here?'), findsOneWidget);
    expect(
      find.text('Pick all that fit. Shapes your dashboard.'),
      findsOneWidget,
    );
    expect(find.text('Manage symptoms'), findsOneWidget);
    expect(find.text('Find pain & flare patterns'), findsOneWidget);
    expect(find.text('Understand my hormones'), findsOneWidget);
    expect(find.text('Compare labs to baseline'), findsOneWidget);
    expect(find.text('Plan for fertility'), findsOneWidget);
    expect(find.text('Track ovulation windows'), findsOneWidget);
    expect(find.text('Prepare for appointments'), findsOneWidget);
    expect(find.text('Doctor-ready reports'), findsOneWidget);
    expect(find.text('Just curious'), findsOneWidget);
    expect(find.text('Learn my own rhythm'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    expectNoDingbats(tester, screen: 'Screen 5');
  });

  testWidgetsWithSemantics('the mockup\'s glyphs are Icons, and silent ones', (
    tester,
  ) async {
    await _Harness().pump(tester);

    // The mockup draws `✦ ◐ ♡ ↗ ✿` in a `.ic` circle. They are decoration: the
    // P3c rule replaces them with `Icon`s, and an `Icon` with no `semanticLabel`
    // contributes no node at all — which is what keeps the row announcing its
    // title and sub-description rather than "star, Manage symptoms".
    for (final GoalOption option in GoalOption.values) {
      final Finder icon = find.descendant(
        of: _tile(option.wireName),
        matching: find.byType(Icon),
      );
      expect(icon, findsOneWidget, reason: '${option.title} draws one glyph');
      expect(
        tester.widget<Icon>(icon).semanticLabel,
        isNull,
        reason: '${option.title}\'s glyph is decorative and must stay silent',
      );
    }

    // The control that makes "silent" a fact about the icons: the row itself is
    // NOT silent — it announces both strings the mockup draws.
    final label = tester
        .getSemantics(_tile('manage_symptoms'))
        .getSemanticsData()
        .label;
    // An equality, not two containments: byte-identical to the string this row
    // authored by hand before P4b-T5d promoted it to `LumenSelectableRow` —
    // title, one line break, sub-description, and nothing else. A containment
    // pair would not notice the glyph starting to announce itself.
    expect(label, 'Manage symptoms\nFind pain & flare patterns');
  });

  testWidgetsWithSemantics('the heading is a header', (tester) async {
    await _Harness().pump(tester);

    expect(
      tester
          .getSemantics(find.text('What brings you here?'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    // The control: the subhead beside it is ordinary prose, not a second
    // landmark for a screen reader to stop on.
    expect(
      tester
          .getSemantics(find.text('Pick all that fit. Shapes your dashboard.'))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isFalse,
    );
  });

  // -------------------------------------------------------------------------
  // The list is the server's
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('what is drawn as chosen comes from the RESPONSE, '
      'not from the ratified seed', (tester) async {
    // A stored answer that contradicts the seed on every code.
    await _Harness(
      goals: const <String, bool>{
        'manage_symptoms': false,
        'understand_hormones': false,
        'plan_fertility': true,
        'prepare_appointments': true,
        'just_curious': true,
      },
    ).pump(tester);

    expect(_isSelected(tester, _tile('plan_fertility')), isTrue);
    expect(_isSelected(tester, _tile('prepare_appointments')), isTrue);
    expect(_isSelected(tester, _tile('just_curious')), isTrue);

    // The positive control: the two the client's own table seeds ON are drawn
    // OFF, because the server said so. A screen that drew the seed would have
    // these two the other way round and the three above would still pass on a
    // list that happens to agree.
    expect(GoalOption.manageSymptoms.defaultSelected, isTrue);
    expect(_isSelected(tester, _tile('manage_symptoms')), isFalse);
    expect(_isSelected(tester, _tile('understand_hormones')), isFalse);
  });

  testWidgetsWithSemantics('the rows are drawn in the RESPONSE\'s order', (
    tester,
  ) async {
    // Deliberately not the ratified order: the point is to prove the screen
    // renders the order it was sent rather than one it holds itself.
    const scrambled = <String, bool>{
      'just_curious': true,
      'manage_symptoms': false,
      'prepare_appointments': false,
      'understand_hormones': true,
      'plan_fertility': false,
    };
    await _Harness(goals: scrambled).pump(tester);

    expect(
      _drawnOrder(tester, scrambled.keys.toList()),
      scrambled.keys.toList(),
    );

    // Positive control: that order is NOT the client's own, so the row above
    // cannot pass for a screen that ignored the wire.
    expect(
      scrambled.keys.toList(),
      isNot(GoalOption.values.map((GoalOption o) => o.wireName).toList()),
    );
  });

  testWidgetsWithSemantics('a code with no copy is not drawn, and is still '
      'carried into the write', (tester) async {
    // The vocabulary is append-only on the server. There is no title, no
    // sub-description and no icon for a code this build has never seen, and
    // inventing one from the wire code would be authoring copy — but on a FULL
    // REPLACE endpoint, dropping it from the array stores the user's answer as
    // a deselection.
    final harness = _Harness(
      goals: const <String, bool>{
        'manage_symptoms': true,
        'sleep_quality': true,
        'just_curious': false,
      },
    )..answerSave();
    await harness.pump(tester);

    expect(_tile('sleep_quality'), findsNothing);
    expect(find.textContaining('sleep'), findsNothing);
    // The control: a code this build DOES know is drawn, so the absence above
    // is a fact about the unknown one rather than about a list that never
    // rendered.
    expect(_tile('manage_symptoms'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(harness.postedCodes, <String>['manage_symptoms', 'sleep_quality']);
  });

  // -------------------------------------------------------------------------
  // Toggling
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a row is an activatable, named toggle', (
    tester,
  ) async {
    await _Harness().pump(tester);

    // Premise: this is the state before the tap, so what changes below is the
    // tap's doing.
    expect(_isSelected(tester, _tile('plan_fertility')), isFalse);
    expect(_isSelected(tester, _tile('manage_symptoms')), isTrue);

    await tester.tap(_tile('plan_fertility'));
    await tester.pump();

    expect(_isSelected(tester, _tile('plan_fertility')), isTrue);
    // …and its neighbour is untouched: this is a multi-select, not a radio
    // group.
    expect(_isSelected(tester, _tile('manage_symptoms')), isTrue);

    expectLabeledButton(tester, _tile('plan_fertility'), 'Plan for fertility');

    // It flips back — a toggle that only ever turned things on would pass every
    // row above, and deselection is the datum this screen exists to record.
    await tester.tap(_tile('plan_fertility'));
    await tester.pump();
    expect(_isSelected(tester, _tile('plan_fertility')), isFalse);
  });

  // -------------------------------------------------------------------------
  // Continue — the FULL REPLACE
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('Continue posts the COMPLETE selected set, never a '
      'diff', (tester) async {
    final harness = _Harness(
      goals: const <String, bool>{
        'manage_symptoms': true,
        'understand_hormones': true,
        'plan_fertility': false,
        'prepare_appointments': false,
        'just_curious': false,
      },
    )..answerSave();
    final container = await harness.pump(tester);

    await tester.tap(_tile('plan_fertility')); // off -> on
    await tester.pump();
    await tester.tap(_tile('manage_symptoms')); // on  -> off
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final List<String> posted = harness.postedCodes;
    // The whole test is the middle element. `understand_hormones` was not
    // touched on this visit — a screen that sent the diff would post
    // `['plan_fertility']`, and the server's FULL REPLACE would then store
    // `understand_hormones` as DESELECTED. That is the silent discard.
    expect(posted, <String>['understand_hormones', 'plan_fertility']);
    // …and the deselected code is absent rather than sent as `false`: on this
    // wire shape, absence IS the deselection.
    expect(posted, isNot(contains('manage_symptoms')));

    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.hormones,
    );
  });

  testWidgetsWithSemantics('an untouched screen still posts the whole set', (
    tester,
  ) async {
    // Unlike screen 4 — which posts nothing when nothing changed, because its
    // endpoint MERGES and D-02's skip means not calling it — this step's answer
    // IS the set on screen, and a full replace is idempotent.
    final harness = _Harness()..answerSave();
    await harness.pump(tester);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(harness.postedCodes, <String>[
      'manage_symptoms',
      'understand_hormones',
    ]);
  });

  // -------------------------------------------------------------------------
  // The min-1 rule
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('with nothing selected Continue is inert and the '
      'server\'s own sentence says why', (tester) async {
    final harness = _Harness()..answerSave();
    await harness.pump(tester);

    // Premise / control: with a selection the CTA IS a labeled, activatable
    // button and the sentence is nowhere on screen.
    expectLabeledButton(
      tester,
      find.byType(FilledButton),
      'Continue',
      exactLabel: true,
    );
    expect(find.text(kGoalsEmptyMessage), findsNothing);

    await tester.tap(_tile('manage_symptoms'));
    await tester.pump();
    await tester.tap(_tile('understand_hormones'));
    await tester.pump();

    // The server's words, not this task's: `select at least one goal`
    // (`OnboardingStepResult.cs:371`), deliberately NOT the generic
    // `value is required`, because the field was supplied.
    expect(kGoalsEmptyMessage, 'select at least one goal');
    expect(find.text(kGoalsEmptyMessage), findsOneWidget);
    // It appears because the user emptied the list, so it has to announce
    // itself rather than wait to be swiped onto.
    expectLiveRegion(tester, kGoalsEmptyMessage);

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    harness.verifyNoSave();
  });

  testWidgetsWithSemantics('one goal is enough', (tester) async {
    // The accepting boundary, asserted as deliberately as the rejecting one: a
    // client that refused what the server stores is a defect.
    final harness = _Harness()..answerSave();
    await harness.pump(tester);

    await tester.tap(_tile('manage_symptoms'));
    await tester.pump();

    expect(find.text(kGoalsEmptyMessage), findsNothing);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(harness.postedCodes, <String>['understand_hormones']);
  });

  // -------------------------------------------------------------------------
  // States
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('a rejection is announced and names the field', (
    tester,
  ) async {
    final harness = _Harness()
      ..rejectSave(
        const ValidationFailure(
          message: 'The request contained invalid data.',
          fields: <String, List<String>>{
            'goals': <String>['value is not an allowed value'],
          },
        ),
      );
    await harness.pump(tester);

    // Control: no banner before the attempt. "No banner" is also the state of a
    // screen that never renders one.
    expect(find.byType(LumenErrorBanner), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(LumenErrorBanner), findsOneWidget);
    expectLiveRegionAt(
      tester,
      find.byType(LumenErrorBanner),
      describedAs: 'the failure banner',
    );
    // The server's own words, under the list it named.
    expect(find.text('value is not an allowed value'), findsOneWidget);
  });

  testWidgetsWithSemantics('an offline save says so and leaves the answers '
      'alone', (tester) async {
    final harness = _Harness()..rejectSave(const NetworkFailure());
    final container = await harness.pump(tester);

    await tester.tap(_tile('just_curious'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(LumenErrorBanner), findsOneWidget);
    // The user's answer survives the failure — there is nothing to re-enter,
    // and Continue is live again.
    expect(_isSelected(tester, _tile('just_curious')), isTrue);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    // …and the flow stayed put.
    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.goals,
    );
  });

  testWidgetsWithSemantics('the save reports itself while it is in flight', (
    tester,
  ) async {
    final harness = _Harness();
    final gate = harness.holdSave();
    await harness.pump(tester);

    // Control: no spinner before the attempt.
    expect(
      find.byWidgetPredicate((Widget w) => w is ProgressIndicator),
      findsNothing,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expectLabeledSpinner(tester, 'Loading');

    gate.complete(goalsResponseFixture());
    await tester.pumpAndSettle();
  });
}
