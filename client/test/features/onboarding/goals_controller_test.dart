// GoalsController — screen 5's state (P4b-T11).
//
// Screen 5 is the flow's first FULL REPLACE surface, and the first where
// DESELECTION IS DATA. `POST /onboarding/goals` stores the body as the complete
// desired state of `user_goals`: a code left out is written as
// `Selected = false`, not left standing
// (`backend/src/Lumen.Api/Onboarding/OnboardingStepsService.cs:381-407`,
// `ARCHITECTURE.md` §C.0.1). So the failure mode inverts from screens 3 and 4 —
// on a merge endpoint a diff bug loses the user's *edit*; here a diff bug
// silently discards an answer they already gave, because a still-selected goal
// that is left out of the array is stored as deselected.
//
// Two rules therefore carry most of this file:
//
//   * the write is the WHOLE selected set, every time, never a diff. The
//     discriminating assertion is that an untouched-but-selected code travels;
//   * the vocabulary is the SERVER's. The response lists every code in frozen
//     order with a boolean each, and the client renders that list rather than
//     re-deriving it — so the prefill tests hand over a list that CONTRADICTS
//     the ratified seed, in an order that is not the ratified order, and assert
//     the form followed the wire.
//
// The ratified table (`survey/decisions-and-vocabularies.md` §2.8) survives here
// only as [GoalOption]'s copy and as the seed for the one case the wire cannot
// answer — a response that carries no list at all.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/goals_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/goals_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// The shell's flow, settled on step 5 with [state] as its resume read.
class _SettledFlow extends OnboardingFlowController {
  _SettledFlow(this.state0);

  final OnboardingStateResponse state0;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(step: OnboardingStep.goals, state: state0),
  );
}

/// One assembled screen-5 world.
class _World {
  _World({Map<String, bool>? goals, bool goalsProvided = false})
    : repo = _MockOnboardingRepository() {
    container = ProviderContainer(
      overrides: <Override>[
        onboardingFlowControllerProvider.overrideWith(
          () => _SettledFlow(
            onboardingStateFixture(
              cycleProvided: true,
              goalsProvided: goalsProvided,
              goals: goals,
            ),
          ),
        ),
        onboardingRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    // Both providers are autoDispose. A bare `read` disposes them as it
    // returns; a subscription is what a screen's `ref.watch` does.
    container.listen(goalsControllerProvider, (_, _) {});
    container.listen(onboardingFlowControllerProvider, (_, _) {});
  }

  final _MockOnboardingRepository repo;
  late final ProviderContainer container;

  GoalsController get notifier =>
      container.read(goalsControllerProvider.notifier);

  GoalsForm get form => container.read(goalsControllerProvider);

  OnboardingStep get step =>
      container.read(onboardingFlowControllerProvider).value!.step;

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

  /// The array the repository was actually handed.
  List<String> get postedCodes =>
      verify(
            () => repo.saveGoals(codes: captureAny(named: 'codes')),
          ).captured.last
          as List<String>;

  void verifyNoSave() =>
      verifyNever(() => repo.saveGoals(codes: any(named: 'codes')));
}

/// `code -> selected`, in the order the form holds them.
Map<String, bool> _shape(GoalsForm form) => <String, bool>{
  for (final GoalChoice choice in form.goals) choice.code: choice.selected,
};

void main() {
  setUpAll(() => registerFallbackValue(const <String>['manage_symptoms']));

  // -------------------------------------------------------------------------
  // The vocabulary comes off the wire
  // -------------------------------------------------------------------------

  test('the selections come from the RESPONSE, not from the ratified seed', () {
    // A stored answer that contradicts the seed on all five codes. A screen
    // that re-derived the vocabulary — or that drew the seed and called it a
    // prefill — reads exactly the opposite of this.
    final world = _World(
      goals: const <String, bool>{
        'manage_symptoms': false,
        'understand_hormones': false,
        'plan_fertility': true,
        'prepare_appointments': true,
        'just_curious': true,
      },
      goalsProvided: true,
    );

    expect(_shape(world.form), <String, bool>{
      'manage_symptoms': false,
      'understand_hormones': false,
      'plan_fertility': true,
      'prepare_appointments': true,
      'just_curious': true,
    });

    // The positive control, and the only thing that makes the row above
    // discriminating: the client-side seed says the OPPOSITE for the two codes
    // D-14 defaults ON. If the form had been built from [GoalOption] the first
    // two would read true.
    expect(GoalOption.manageSymptoms.defaultSelected, isTrue);
    expect(GoalOption.understandHormones.defaultSelected, isTrue);
    expect(GoalOption.planFertility.defaultSelected, isFalse);
  });

  test('the order is the RESPONSE\'s order, not a client-side one', () {
    // The server sends `UserGoal.Codes.All` order and the client renders what
    // it is sent. Proving that needs an order the client would not have
    // produced on its own, so this one is deliberately scrambled.
    const scrambled = <String, bool>{
      'just_curious': true,
      'manage_symptoms': false,
      'prepare_appointments': false,
      'understand_hormones': true,
      'plan_fertility': false,
    };
    final world = _World(goals: scrambled, goalsProvided: true);

    expect(
      world.form.goals.map((GoalChoice c) => c.code).toList(),
      scrambled.keys.toList(),
    );

    // Positive control: that order is NOT the client's own. Without this the
    // assertion above would still pass for a screen that ignored the wire, on
    // the day someone reorders the enum to match.
    expect(
      scrambled.keys.toList(),
      isNot(GoalOption.values.map((GoalOption o) => o.wireName).toList()),
    );
  });

  test('a code this build has no copy for is CARRIED, never dropped', () {
    // The vocabulary is append-only on the server. A sixth code arrives at a
    // build that has no title, no sub-description and no icon for it — and on
    // a FULL REPLACE endpoint, dropping it from the array is not "ignoring an
    // unknown"; it is storing the user's answer as a deselection.
    final world = _World(
      goals: const <String, bool>{
        'manage_symptoms': true,
        'sleep_quality': true,
        'just_curious': false,
      },
      goalsProvided: true,
    );

    expect(
      world.form.goals.map((GoalChoice c) => c.code),
      contains('sleep_quality'),
    );
    expect(world.form.selectedCodes, contains('sleep_quality'));

    // …and it is not DRAWN, because there is no copy to draw. The control is
    // the known code beside it: `drawable` is not simply empty.
    expect(world.form.drawable.map((GoalChoice c) => c.code).toList(), <String>[
      'manage_symptoms',
      'just_curious',
    ]);

    // The other half of the same rule: an unknown code the user does NOT have
    // selected is not silently added either.
    final off = _World(
      goals: const <String, bool>{
        'manage_symptoms': true,
        'sleep_quality': false,
      },
      goalsProvided: true,
    );
    expect(off.form.selectedCodes, <String>['manage_symptoms']);
  });

  test('with no list on the wire it falls back to the ratified seed', () {
    // Every generated property is nullable (§C.0.2) and a P3b-era cached state
    // predates this member entirely, so "the response carried no goals" is a
    // shape the client must survive. This is the ONE case the ratified table is
    // a source of truth for.
    final world = _World();

    expect(_shape(world.form), <String, bool>{
      'manage_symptoms': true,
      'understand_hormones': true,
      'plan_fertility': false,
      'prepare_appointments': false,
      'just_curious': false,
    });

    // Positive controls: the fallback is neither "everything off" (which a form
    // built from an empty list would give) nor "everything on".
    expect(world.form.selectedCodes, <String>[
      'manage_symptoms',
      'understand_hormones',
    ]);
    expect(world.form.goals.length, 5);
  });

  // -------------------------------------------------------------------------
  // Toggling
  // -------------------------------------------------------------------------

  test('toggling flips exactly one code and leaves the rest standing', () {
    final world = _World();

    // Premise: this is the state before the tap, so what changes below is the
    // tap's doing.
    expect(_shape(world.form)['plan_fertility'], isFalse);
    expect(_shape(world.form)['manage_symptoms'], isTrue);

    world.notifier.toggle('plan_fertility');

    expect(_shape(world.form), <String, bool>{
      'manage_symptoms': true,
      'understand_hormones': true,
      'plan_fertility': true,
      'prepare_appointments': false,
      'just_curious': false,
    });

    // …and it flips BACK. A toggle that only ever turned things on would pass
    // every row above.
    world.notifier.toggle('plan_fertility');
    expect(_shape(world.form)['plan_fertility'], isFalse);

    // Deselection is a real state, not a floor: the last two go off too.
    world.notifier.toggle('manage_symptoms');
    world.notifier.toggle('understand_hormones');
    expect(world.form.selectedCodes, isEmpty);
  });

  // -------------------------------------------------------------------------
  // The write — FULL REPLACE
  // -------------------------------------------------------------------------

  test('Continue posts the COMPLETE selected set, never a diff', () async {
    final world = _World(
      goals: const <String, bool>{
        'manage_symptoms': true,
        'understand_hormones': true,
        'plan_fertility': false,
        'prepare_appointments': false,
        'just_curious': false,
      },
      goalsProvided: true,
    )..answerSave();

    world.notifier.toggle('plan_fertility'); // off -> on
    world.notifier.toggle('manage_symptoms'); // on  -> off

    await world.notifier.submit();

    // Captured ONCE: `verify` consumes the recorded call, so reading it twice
    // would fail the second read against a repository that was called.
    final List<String> posted = world.postedCodes;

    // The whole test is the middle element. `understand_hormones` was NOT
    // touched by this visit — a client that sent the diff, or only what the
    // user just switched on, would send `['plan_fertility']` and the server's
    // FULL REPLACE would then store `understand_hormones` as DESELECTED. That
    // is the silent discard this screen exists to avoid.
    expect(posted, <String>['understand_hormones', 'plan_fertility']);

    // …and the deselected code is absent rather than sent as `false`. The wire
    // shape is an array of codes: absence IS the deselection.
    expect(posted, isNot(contains('manage_symptoms')));
  });

  test('an untouched screen still posts the whole set', () async {
    // Unlike screen 4 — which posts nothing when nothing changed, because its
    // endpoint MERGES and D-02's skip means not calling it — this step's answer
    // IS the set on screen, and a full replace is idempotent. Pressing Continue
    // on the defaults is a user accepting them, and it is what makes
    // `goalsProvided` true.
    final world = _World()..answerSave();

    await world.notifier.submit();

    expect(world.postedCodes, <String>[
      'manage_symptoms',
      'understand_hormones',
    ]);
  });

  test('one goal is enough — the boundary is at one, not at two', () async {
    // The accepting boundary, asserted as deliberately as the rejecting one
    // below it: a client that refused what the server stores is a defect.
    final world = _World()..answerSave();

    world.notifier.toggle('manage_symptoms');
    expect(world.form.selectedCodes, <String>['understand_hormones']);
    expect(world.form.canSubmit, isTrue);

    await world.notifier.submit();

    expect(world.postedCodes, <String>['understand_hormones']);
  });

  test('with nothing selected it posts nothing', () async {
    final world = _World()..answerSave();

    world.notifier.toggle('manage_symptoms');
    world.notifier.toggle('understand_hormones');
    expect(world.form.canSubmit, isFalse);

    await world.notifier.submit();

    // `select at least one goal` (`OnboardingStepResult.cs:371`) is a 400, and
    // it is knowable here — so the request is not spent to be told.
    world.verifyNoSave();
    // …and the step does NOT advance: a user cannot walk past this one by
    // emptying it.
    expect(world.step, OnboardingStep.goals);

    // The control: re-select one and the same button posts.
    world.notifier.toggle('just_curious');
    await world.notifier.submit();
    expect(world.postedCodes, <String>['just_curious']);
  });

  // -------------------------------------------------------------------------
  // After the write
  // -------------------------------------------------------------------------

  test(
    'the form is replaced by the server\'s re-read, not by the request',
    () async {
      // The 200 is the server's re-read of what is STORED, not an echo, so it is
      // the best answer to "what does the server hold now". This fixture answers
      // something the request did not ask for, which is what makes the assertion
      // about the response rather than about the round trip.
      final world = _World()
        ..answerSave(
          goalsResponseFixture(const <String, bool>{
            'manage_symptoms': false,
            'understand_hormones': false,
            'plan_fertility': true,
            'prepare_appointments': false,
            'just_curious': false,
          }),
        );

      // Premise: the form does NOT already look like that.
      expect(world.form.selectedCodes, <String>[
        'manage_symptoms',
        'understand_hormones',
      ]);

      await world.notifier.submit();

      expect(world.form.selectedCodes, <String>['plan_fertility']);
      expect(world.step, OnboardingStep.hormones);
    },
  );

  test(
    'a rejection is held on the form and the step does not advance',
    () async {
      const failure = ValidationFailure(
        message: 'The request contained invalid data.',
        fields: <String, List<String>>{
          'goals': <String>['select at least one goal'],
        },
      );
      final world = _World()..rejectSave(failure);

      // Premise: nothing is wrong before the attempt.
      expect(world.form.failure, isNull);

      await world.notifier.submit();

      expect(world.form.failure, failure);
      expect(world.form.submitting, isFalse);
      expect(world.step, OnboardingStep.goals);

      // The control: a save that succeeds DOES advance, so the row above is a
      // fact about the rejection and not about a controller that never moves.
      world.answerSave();
      await world.notifier.submit();
      expect(world.step, OnboardingStep.hormones);
      expect(world.form.failure, isNull);
    },
  );

  test('an untyped error still stops the spinner and says something', () async {
    // `cachedWrite` invalidates its keys UNGUARDED after a successful write, so
    // a concurrent logout purge closing the Hive box lands here — after the
    // answer was stored. Unhandled, that is a spinner that never stops.
    final world = _World();
    when(
      () => world.repo.saveGoals(codes: any(named: 'codes')),
    ).thenAnswer((_) async => throw StateError('box closed'));

    await world.notifier.submit();

    expect(world.form.submitting, isFalse);
    expect(world.form.failure, isA<UnknownFailure>());
  });

  test(
    'a second Continue while the first is in flight issues one request',
    () async {
      final world = _World();
      var calls = 0;
      when(() => world.repo.saveGoals(codes: any(named: 'codes'))).thenAnswer((
        _,
      ) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return goalsResponseFixture();
      });

      final first = world.notifier.submit();
      // Premise: the guard is only meaningful while a request is actually open.
      expect(world.form.submitting, isTrue);
      await world.notifier.submit();
      await first;

      expect(calls, 1);
    },
  );

  test('a rejection is dropped as soon as the user answers again', () async {
    final world = _World()..rejectSave(const NetworkFailure());

    await world.notifier.submit();
    // Premise: there IS a rejection to drop. Without this the assertion below
    // passes against a controller that never records one.
    expect(world.form.failure, isA<NetworkFailure>());

    world.notifier.toggle('just_curious');

    // The banner describes an attempt the user has moved on from; leaving it up
    // asserts something about a form that no longer exists.
    expect(world.form.failure, isNull);
  });
}
