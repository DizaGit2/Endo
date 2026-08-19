// Leaving a written onboarding step and coming back to it (P4b-T8b).
//
// `OnboardingFlow.state` is the shell's copy of `GET /onboarding/state`, read
// once when the flow mounts. Every step controller is `autoDispose` and every
// step past the first has a back affordance
// (`onboarding_shell_screen.dart:100,126`), so leaving a step DISPOSES its
// controller and returning REBUILDS it — from that same first read. Until T8b
// nothing refreshed it, so a step the user had already written re-seeded from
// pre-save data.
//
// `autoDispose` is what makes this happen rather than what prevents it, and
// every test below states that premise as an assertion rather than as a
// comment: the controller instance the step comes back to is compared with the
// one it left, and the test is only meaningful because they differ.
//
// What a stale prefill COSTS is decided by the endpoint's write semantics
// (`ARCHITECTURE.md` §C.0.1), which is why there is one test per screen rather
// than one for the shell:
//
//   * screen 3 · `POST /onboarding/cycle` MERGES, but `lastPeriodStart` is
//     REQUIRED on every post — so the stale anchor travels on the next write
//     and drags a corrected date back. A lost EDIT.
//   * screen 4 · `POST /onboarding/baseline` MERGES and screen 4 posts a diff
//     against what it read. It prefills from `GET /me`, not from the flow, so
//     it never had this defect; its test is the guard that says so.
//   * screen 5 · `POST /onboarding/goals` is a FULL REPLACE — the array IS the
//     complete desired state — so the stale prefill is not a stale view, it is
//     the next request's body. A lost STORED ANSWER. That is the one this task
//     exists for, and its test spells out what it prevents.
//
// The fake server below is not a mock that echoes: it holds rows and applies
// each endpoint's own write rule to them, so the closing assertion of each test
// is about WHAT THE SERVER ENDS UP HOLDING rather than about what the client
// happened to send.
//
// Controls are located by KEY or TYPE (`goalTileKey`,
// `find.byType(FilledButton)`, the shell's back icon by widget predicate) — the
// T5c rule. `find.bySemanticsLabel` appears only inside assertions about what a
// day cell announces.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/baseline_response.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/goals_response.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/onboarding/application/baseline_controller.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/features/onboarding/application/goals_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/onboarding/presentation/goals_screen.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// The fake server
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

class _MockCycleSettingsRepository extends Mock
    implements CycleSettingsRepository {}

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockMeRepository extends Mock implements MeRepository {}

/// The rows the server holds, and the §C.0.1 write rule each endpoint applies
/// to them.
///
/// Deliberately stateful. A mock that echoed its request could not tell a
/// client that re-sent stale data from one that did not — and "the user's
/// stored answer survived" is a statement about storage, not about a round
/// trip.
class _Server {
  _Server({
    this.lastPeriodStart,
    this.cycleProvided = false,
    this.baselineProvided = false,
    Map<String, bool>? goals,
  }) : goals = Map<String, bool>.of(goals ?? kSeededGoals);

  // `cycle_events` + `user_cycle_settings`.
  Date? lastPeriodStart;
  int avgCycleLengthDays = 28;
  String regularity = 'somewhat';

  // `user_profile_enc` / `body_metrics`.
  int? heightCm;

  // `user_goals`, complete: every code carries a boolean.
  final Map<String, bool> goals;

  bool cycleProvided;
  bool baselineProvided;
  bool goalsProvided = false;

  /// `GET /onboarding/state`.
  OnboardingStateResponse get state => onboardingStateFixture(
    cycleProvided: cycleProvided,
    baselineProvided: baselineProvided,
    goalsProvided: goalsProvided,
    lastPeriodStart: lastPeriodStart,
    goals: goals,
  );

  /// `GET /me`.
  MeResponse get me =>
      meResponseFixture(onboardingCompleted: false, heightCm: heightCm);

  /// `GET /settings/cycle`.
  CycleSettingsResponse get cycleSettings => cycleSettingsFixture(
    avgCycleLengthDays: avgCycleLengthDays,
    regularity: regularity,
  );

  /// `POST /onboarding/cycle` — MERGE on the two self-reports, and
  /// `lastPeriodStart` written on EVERY post.
  OnboardingCycleResponse saveCycle(
    Date anchor, {
    int? avgCycleLengthDays,
    String? regularity,
  }) {
    lastPeriodStart = anchor;
    if (avgCycleLengthDays != null) {
      this.avgCycleLengthDays = avgCycleLengthDays;
    }
    if (regularity != null) this.regularity = regularity;
    cycleProvided = true;
    return onboardingCycleFixture(
      lastPeriodStart: anchor,
      avgCycleLengthDays: this.avgCycleLengthDays,
      regularity: this.regularity,
    );
  }

  /// `POST /onboarding/baseline` — MERGE: a null leaves the stored value alone.
  BaselineResponse saveBaseline({int? heightCm}) {
    if (heightCm != null) this.heightCm = heightCm;
    baselineProvided = true;
    return baselineFixture(heightCm: this.heightCm);
  }

  /// `POST /onboarding/goals` — FULL REPLACE: every code's flag comes from
  /// membership of [codes], so a code left out is stored as DESELECTED.
  GoalsResponse saveGoals(List<String> codes) {
    for (final String code in goals.keys.toList()) {
      goals[code] = codes.contains(code);
    }
    goalsProvided = true;
    return goalsResponseFixture(goals);
  }
}

// ---------------------------------------------------------------------------
// The world
// ---------------------------------------------------------------------------

/// The whole onboarding shell over [server], with only the repositories faked.
///
/// Every controller in the flow is the real one — that is the point: the defect
/// lives in the seam between `OnboardingFlowController` and a step controller's
/// `build()`, and pinning either end would hide it.
class _World {
  _World(this.server) {
    when(
      onboarding.getState,
    ).thenAnswer((_) async => Fresh<OnboardingStateResponse>(server.state));

    when(
      () => onboarding.saveCycle(
        lastPeriodStart: any(named: 'lastPeriodStart'),
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        regularity: any(named: 'regularity'),
        previousLastPeriodStart: any(named: 'previousLastPeriodStart'),
      ),
    ).thenAnswer((Invocation call) async {
      cycleSaves.add(call.namedArguments[#lastPeriodStart] as Date);
      return server.saveCycle(
        call.namedArguments[#lastPeriodStart] as Date,
        avgCycleLengthDays: call.namedArguments[#avgCycleLengthDays] as int?,
        regularity: call.namedArguments[#regularity] as String?,
      );
    });

    when(
      () => onboarding.saveBaseline(
        dob: any(named: 'dob'),
        heightCm: any(named: 'heightCm'),
        weightKg: any(named: 'weightKg'),
        endoStatus: any(named: 'endoStatus'),
      ),
    ).thenAnswer((Invocation call) async {
      baselineSaves++;
      return server.saveBaseline(
        heightCm: call.namedArguments[#heightCm] as int?,
      );
    });

    answerGoalsSave();

    when(settings.getSettings).thenAnswer(
      (_) async => Fresh<CycleSettingsResponse>(server.cycleSettings),
    );
    when(me.getMe).thenAnswer((_) async => Fresh<MeResponse>(server.me));
    when(today.today).thenAnswer((_) async => Date(2026, 4, 20));

    overrides = <Override>[
      ...lumenOverrides(),
      // Pinned so the day cells' announced dates below are the same on every
      // machine that runs this file.
      deviceLocaleProvider.overrideWithValue('es-ES'),
      onboardingRepositoryProvider.overrideWithValue(onboarding),
      cycleSettingsRepositoryProvider.overrideWithValue(settings),
      meRepositoryProvider.overrideWithValue(me),
      serverTodayRepositoryProvider.overrideWithValue(today),
    ];
  }

  final _Server server;
  final _MockOnboardingRepository onboarding = _MockOnboardingRepository();
  final _MockCycleSettingsRepository settings = _MockCycleSettingsRepository();
  final _MockMeRepository me = _MockMeRepository();
  final _MockServerTodayRepository today = _MockServerTodayRepository();
  late final List<Override> overrides;

  /// The anchor every `POST /onboarding/cycle` carried, in order.
  final List<Date> cycleSaves = <Date>[];

  /// The array every `POST /onboarding/goals` carried, in order.
  final List<List<String>> goalSaves = <List<String>>[];

  int baselineSaves = 0;

  Completer<GoalsResponse>? _heldGoals;
  List<String>? _heldCodes;

  late ProviderContainer container;

  /// The ordinary answer: the server applies the FULL REPLACE and answers at
  /// once.
  void answerGoalsSave() {
    when(() => onboarding.saveGoals(codes: any(named: 'codes'))).thenAnswer((
      Invocation call,
    ) async {
      final List<String> codes = call.namedArguments[#codes] as List<String>;
      goalSaves.add(codes);
      return server.saveGoals(codes);
    });
  }

  /// Holds the next `POST /onboarding/goals` OPEN, so the step can be left
  /// while the request is still in flight.
  ///
  /// That is an ordinary gesture rather than a contrived one: the shell's back
  /// affordance is NOT gated on `submitting`
  /// (`onboarding_shell_screen.dart:100,126`) — only the goal tiles and the CTA
  /// are (`goals_screen.dart`).
  void holdGoalsSave() {
    when(() => onboarding.saveGoals(codes: any(named: 'codes'))).thenAnswer((
      Invocation call,
    ) {
      _heldCodes = call.namedArguments[#codes] as List<String>;
      goalSaves.add(_heldCodes!);
      return (_heldGoals = Completer<GoalsResponse>()).future;
    });
  }

  /// Lets the held write land — the server stores it now, exactly as it would
  /// have done had the user stayed on the step.
  void releaseGoalsSave() {
    _heldGoals!.complete(server.saveGoals(_heldCodes!));
    answerGoalsSave();
  }

  Future<void> pump(WidgetTester tester) async {
    // The surface this mounts at is `kTestSurfaceSize`, which `pumpApp` now
    // sets for every test (P4b-T5d). It matters here more than anywhere: under
    // `flutter_test`'s 800x600 default — WIDER and much SHORTER than any phone
    // — screen 3's calendar pushes the CTA past the bottom of
    // `OnboardingStepSlot`'s scroll viewport, where it is clipped and
    // `tester.tap` misses it. That is a failure INSIDE the tap, which is
    // exactly the shape that cannot be told apart from a broken assertion.
    container = await pumpApp(
      tester,
      home: const OnboardingShellScreen(),
      overrides: overrides,
      // The shell and every step body draw an INDETERMINATE spinner while their
      // reads are open, and an indeterminate spinner never settles. The frames
      // are driven by hand instead.
      settle: false,
    );
    await _settle(tester);
  }

  OnboardingStep get step =>
      container.read(onboardingFlowControllerProvider).value!.step;
}

/// Pumps until the reads have landed and the spinners are gone.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// The SHELL's back affordance.
///
/// Screen 3 draws its own `Icons.chevron_left` for the previous month, so the
/// icon alone does not identify this control; 'Back' is
/// `MaterialLocalizations.backButtonTooltip`. Same finder the shell's own
/// semantics test uses.
final Finder _shellBack = find.byWidgetPredicate(
  (Widget widget) =>
      widget is Icon &&
      widget.icon == Icons.chevron_left &&
      widget.semanticLabel == 'Back',
  description: "the shell's back affordance",
);

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(_shellBack);
  await _settle(tester);
}

Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await _settle(tester);
}

/// Whether the node at [finder] announces itself as selected.
bool _announcesSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isSelected ==
    Tristate.isTrue;

/// Whether the goal row for [code] announces itself as selected.
bool _goalSelected(WidgetTester tester, String code) =>
    _announcesSelected(tester, find.byKey(goalTileKey(code)));

/// The day cell for [date], located by what it announces — under es-ES that is
/// `d/M/yyyy`.
Finder _dayCell(String date) => find.bySemanticsLabel(date);

void main() {
  setUpAll(() {
    registerFallbackValue(Date(2026, 1, 1));
    registerFallbackValue(const <String>['manage_symptoms']);
  });

  // -------------------------------------------------------------------------
  // Screen 5 — the one that loses data
  // -------------------------------------------------------------------------

  testWidgets('screen 5 — coming back shows the goals the server STORED, and '
      'Continue does not write the pre-save set back over them', (
    tester,
  ) async {
    // `POST /onboarding/goals` is a FULL REPLACE: the array is the complete
    // desired state of `user_goals`, so a code left out is stored as
    // deselected. A stale prefill is therefore not a stale view — it is the
    // next request's body, and the request destroys the answer the user gave.
    final server = _Server(cycleProvided: true, baselineProvided: true);
    final world = _World(server);
    await world.pump(tester);

    // Premise: the flow resumed on step 5, showing the D-14 seed the server
    // holds — the first two ON, `just_curious` OFF. Every assertion after the
    // save is the OPPOSITE of this, which is what makes them discriminating.
    expect(world.step, OnboardingStep.goals);
    expect(_goalSelected(tester, 'manage_symptoms'), isTrue);
    expect(_goalSelected(tester, 'understand_hormones'), isTrue);
    expect(_goalSelected(tester, 'just_curious'), isFalse);

    final GoalsController left = world.container.read(
      goalsControllerProvider.notifier,
    );

    // The user's real answer: neither default, `just_curious` only.
    await tester.tap(find.byKey(goalTileKey('manage_symptoms')));
    await tester.tap(find.byKey(goalTileKey('understand_hormones')));
    await tester.tap(find.byKey(goalTileKey('just_curious')));
    await tester.pump();

    await _tapContinue(tester);

    // Premise: the write landed and the step moved on, so what follows is
    // about coming BACK rather than about a save that never happened.
    expect(world.goalSaves, <List<String>>[
      <String>['just_curious'],
    ]);
    expect(server.goals, <String, bool>{
      'manage_symptoms': false,
      'understand_hormones': false,
      'plan_fertility': false,
      'prepare_appointments': false,
      'just_curious': true,
    });
    expect(world.step, OnboardingStep.hormones);

    await _tapBack(tester);
    expect(world.step, OnboardingStep.goals);

    // The premise the whole file rests on: `autoDispose` DISPOSED the
    // controller on the way out, so this is a fresh one seeded from the flow —
    // not the settled form the save left behind. Without this the assertions
    // below could pass on a controller that was never rebuilt.
    expect(
      identical(world.container.read(goalsControllerProvider.notifier), left),
      isFalse,
      reason:
          'leaving the step must dispose its autoDispose controller — this '
          'test is about what the REBUILT one seeds from',
    );

    // What the user sees is what the server holds.
    expect(_goalSelected(tester, 'just_curious'), isTrue);
    expect(_goalSelected(tester, 'manage_symptoms'), isFalse);
    expect(_goalSelected(tester, 'understand_hormones'), isFalse);

    // …and pressing Continue again re-posts the WHOLE set, so a prefill that
    // had reverted would be written. It does not: `just_curious` is still the
    // answer, and the two defaults are still deselected.
    await _tapContinue(tester);

    expect(world.goalSaves, <List<String>>[
      <String>['just_curious'],
      <String>['just_curious'],
    ]);
    expect(server.goals, <String, bool>{
      'manage_symptoms': false,
      'understand_hormones': false,
      'plan_fertility': false,
      'prepare_appointments': false,
      'just_curious': true,
    });
  });

  testWidgets('screen 5 — leaving the step while the save is IN FLIGHT still '
      'records what the server stored', (tester) async {
    // The same silent loss, in a narrower window, and reachable with no back
    // door: the shell's back affordance is NOT gated on `submitting`
    // (`onboarding_shell_screen.dart:100,126`) — only the tiles and the CTA are
    // — so Back during a save is an ordinary gesture. It disposes the step
    // controller, and the 200 then lands on a dead one. A refresh written
    // BEHIND that disposal gate never runs; the user walks back through step 5
    // on the way to 6 and 7, the chips re-seed pre-save, and the next Continue
    // full-replaces their answer away. Once the race fires the loss is
    // guaranteed rather than probable, which is why the record is taken before
    // the gate and the flow notifier is read before the await.
    final server = _Server(cycleProvided: true, baselineProvided: true);
    final world = _World(server);
    await world.pump(tester);

    // Premise: step 5, showing the D-14 seed — the opposite of every assertion
    // after the save.
    expect(world.step, OnboardingStep.goals);
    expect(_goalSelected(tester, 'manage_symptoms'), isTrue);
    expect(_goalSelected(tester, 'understand_hormones'), isTrue);
    expect(_goalSelected(tester, 'just_curious'), isFalse);

    await tester.tap(find.byKey(goalTileKey('manage_symptoms')));
    await tester.tap(find.byKey(goalTileKey('understand_hormones')));
    await tester.tap(find.byKey(goalTileKey('just_curious')));
    await tester.pump();

    final GoalsController left = world.container.read(
      goalsControllerProvider.notifier,
    );

    world.holdGoalsSave();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // Premise: the request is genuinely open. Without this the Back below
    // would be an ordinary back-navigation and this test would duplicate the
    // one above it.
    expect(world.container.read(goalsControllerProvider).submitting, isTrue);

    // Back, mid-flight. This is what disposes the controller the response is
    // about to land on.
    await _tapBack(tester);
    expect(world.step, OnboardingStep.baseline);

    world.releaseGoalsSave();
    await _settle(tester);

    // Premise: the write DID land — the server holds the user's real answer,
    // so anything the client shows from here on is either that or a lie.
    expect(server.goals['just_curious'], isTrue);
    expect(server.goals['manage_symptoms'], isFalse);
    expect(server.goals['understand_hormones'], isFalse);

    // Forward again, the way the user reaches steps 6 and 7 at all.
    await _tapContinue(tester);
    expect(world.step, OnboardingStep.goals);
    expect(
      identical(world.container.read(goalsControllerProvider.notifier), left),
      isFalse,
      reason:
          'the mid-flight Back must have disposed the step controller — this '
          'test is about what the REBUILT one seeds from',
    );

    expect(_goalSelected(tester, 'just_curious'), isTrue);
    expect(_goalSelected(tester, 'manage_symptoms'), isFalse);
    expect(_goalSelected(tester, 'understand_hormones'), isFalse);

    // …and walking on does not full-replace the stored answer away.
    await _tapContinue(tester);

    expect(world.goalSaves, <List<String>>[
      <String>['just_curious'],
      <String>['just_curious'],
    ]);
    expect(server.goals, <String, bool>{
      'manage_symptoms': false,
      'understand_hormones': false,
      'plan_fertility': false,
      'prepare_appointments': false,
      'just_curious': true,
    });
  });

  // -------------------------------------------------------------------------
  // Screen 3 — the lost edit
  // -------------------------------------------------------------------------

  testWidgets('screen 3 — a corrected anchor survives leaving the step, and '
      'the next save does not drag the old date back', (tester) async {
    // `POST /onboarding/cycle` MERGES its two self-reports, but
    // `lastPeriodStart` is REQUIRED on every post — so the anchor on screen
    // travels with any later save of this step. A stale one is a lost edit.
    final server = _Server(
      lastPeriodStart: Date(2026, 4, 1),
      cycleProvided: true,
    );
    final world = _World(server);
    await world.pump(tester);

    // The resume lands on step 4 (cycle is answered); step 3 is reached the way
    // a user reaches it — the back affordance.
    expect(world.step, OnboardingStep.baseline);
    await _tapBack(tester);
    expect(world.step, OnboardingStep.cycle);

    // Premise: the anchor the server holds is 1 April, and 6 April is not
    // chosen. Both halves matter — the second is what the assertions after the
    // correction invert.
    expect(_announcesSelected(tester, _dayCell('1/4/2026')), isTrue);
    expect(_announcesSelected(tester, _dayCell('6/4/2026')), isFalse);

    final CycleSetupController left = world.container.read(
      cycleSetupControllerProvider.notifier,
    );

    // The correction this screen exists for.
    left.chooseDay(Date(2026, 4, 6));
    await tester.pump();
    await _tapContinue(tester);

    expect(server.lastPeriodStart, Date(2026, 4, 6));
    expect(world.step, OnboardingStep.baseline);

    await _tapBack(tester);
    expect(world.step, OnboardingStep.cycle);

    expect(
      identical(
        world.container.read(cycleSetupControllerProvider.notifier),
        left,
      ),
      isFalse,
      reason:
          'leaving the step must dispose its autoDispose controller — this '
          'test is about what the REBUILT one seeds from',
    );

    // The calendar shows the date the server now holds, not the one it held
    // when the flow was first read.
    expect(_announcesSelected(tester, _dayCell('6/4/2026')), isTrue);
    expect(_announcesSelected(tester, _dayCell('1/4/2026')), isFalse);

    // And the cost of getting that wrong: changing anything else on this step
    // re-posts, and the anchor rides along on every post. A reverted prefill is
    // written.
    world.container
        .read(cycleSetupControllerProvider.notifier)
        .chooseRegularity(CycleRegularity.irregular);
    await tester.pump();
    await _tapContinue(tester);

    expect(world.cycleSaves, <Date>[Date(2026, 4, 6), Date(2026, 4, 6)]);
    expect(server.lastPeriodStart, Date(2026, 4, 6));
    expect(server.regularity, 'irregular');
  });

  // -------------------------------------------------------------------------
  // Screen 4 — the guard
  // -------------------------------------------------------------------------

  testWidgets('screen 4 — coming back shows the baseline the server now holds, '
      'and Continue re-posts nothing', (tester) async {
    // Screen 4 prefills from `GET /me`, not from the flow state — which carries
    // `baselineProvided` and no baseline projection at all — so it never had
    // the stale-prefill defect. This is the guard that keeps it that way, and
    // the shape T12 and T13 inherit: a returning step shows what the server
    // holds, and a step with nothing unsent makes no request.
    final server = _Server(cycleProvided: true);
    final world = _World(server);
    await world.pump(tester);

    expect(world.step, OnboardingStep.baseline);

    // Premise: nothing is stored and nothing is drawn, so the `170` asserted
    // after the return is the save's doing.
    expect(server.heightCm, isNull);
    expect(find.text('170'), findsNothing);

    final BaselineController left = world.container.read(
      baselineControllerProvider.notifier,
    );
    left.setHeightCm(170);
    await tester.pump();
    await _tapContinue(tester);

    expect(world.baselineSaves, 1);
    expect(server.heightCm, 170);
    expect(world.step, OnboardingStep.goals);

    await _tapBack(tester);
    expect(world.step, OnboardingStep.baseline);

    expect(
      identical(
        world.container.read(baselineControllerProvider.notifier),
        left,
      ),
      isFalse,
      reason:
          'leaving the step must dispose its autoDispose controller — this '
          'test is about what the REBUILT one seeds from',
    );

    // The field shows the stored height…
    expect(find.text('170'), findsOneWidget);

    // …and Continue posts nothing, because nothing on screen differs from what
    // the server holds. A re-seed that had lost the height would either blank
    // the field or re-assert it as a write.
    await _tapContinue(tester);

    expect(world.baselineSaves, 1);
    expect(world.step, OnboardingStep.goals);
  });
}
