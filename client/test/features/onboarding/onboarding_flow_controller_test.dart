// OnboardingFlowController — resume, step navigation, and finishing (P4b-T8).
//
// CONTROLLER SHAPE. `build()` here awaits NOTHING: it returns
// `const AsyncValue.loading()` and hands the read to a microtask. That makes it
// a `Notifier<AsyncValue<OnboardingFlow>>`, not an `AsyncNotifier`, and the
// choice is the difference between a working finish button and a dead one — an
// `AsyncNotifier`'s synchronous `state =` races its own build future, which
// Riverpod assigns unconditionally when it lands, so a rejection written first
// is silently dropped. With no build future there is nothing to lose to.
//
// TEST RULE that follows from it: every test below SETTLES the container before
// it mutates. Reading a notifier and immediately calling a mutating method
// asserts on a race between two writers, not on the code.

import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/goal_selection.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// A container with the flow's repository stubbed and the router's gate real,
/// so `markCompleted` can be observed where it actually lands.
ProviderContainer _container(
  OnboardingRepository repo, {
  List<Override> extra = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      // The gate controller reads `/me` when auth is authenticated; pinning it
      // unauthenticated keeps this file about the FLOW controller while leaving
      // `onboardingStatusProvider` itself real, so `markCompleted()` is
      // observed on the production notifier rather than on a stand-in.
      authStatusProvider.overrideWith(
        () => FakeAuthController(AuthStatus.unauthenticated),
      ),
      onboardingRepositoryProvider.overrideWithValue(repo),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  // The controller is `autoDispose`, and a bare `container.read` of an
  // autoDispose provider disposes it again the moment the read returns — its
  // deferred load would then find `ref.mounted == false` and resolve nothing.
  // A screen's `ref.watch` is what keeps it alive in production; this
  // subscription is that, and without it every test here would be asserting on
  // a controller that had already been torn down.
  container.listen(onboardingFlowControllerProvider, (_, _) {});
  return container;
}

/// Reads the controller and pumps microtasks until its deferred load lands.
///
/// This is the settle the controller-shape rule requires: a test that mutates
/// without it is asserting on an undefined race.
Future<OnboardingFlow> _settled(ProviderContainer container) async {
  container.read(onboardingFlowControllerProvider);
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
    final value = container.read(onboardingFlowControllerProvider).value;
    if (value != null) return value;
  }
  fail('The flow controller never settled on a value.');
}

Future<AsyncValue<OnboardingFlow>> _settledOrError(
  ProviderContainer container,
) async {
  container.read(onboardingFlowControllerProvider);
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
    final state = container.read(onboardingFlowControllerProvider);
    if (!state.isLoading) return state;
  }
  return container.read(onboardingFlowControllerProvider);
}

OnboardingFlowController _notifier(ProviderContainer container) =>
    container.read(onboardingFlowControllerProvider.notifier);

void main() {
  late _MockOnboardingRepository repo;

  setUp(() {
    repo = _MockOnboardingRepository();
    when(repo.complete).thenAnswer((_) async => onboardingCompleteFixture());
  });

  void stubState(OnboardingStateResponse state) {
    when(repo.getState).thenAnswer((_) async => Fresh(state));
  }

  // -------------------------------------------------------------------------
  // Resume
  // -------------------------------------------------------------------------

  group('resume', () {
    test('the first frame is loading, before any answer exists', () async {
      stubState(onboardingStateFixture());
      final container = _container(repo);

      // Read once, synchronously: this is the state a screen paints on frame
      // one. If it were `AsyncData` of a guessed step, the user would see the
      // wrong step flash before the real one.
      expect(
        container.read(onboardingFlowControllerProvider),
        isA<AsyncLoading<OnboardingFlow>>(),
      );

      await _settled(container);
    });

    test('it lands on the step GET /onboarding/state says is next', () async {
      // Two different servers, two different landings. One case alone would
      // pass against a controller that hard-codes a step.
      stubState(onboardingStateFixture());
      expect((await _settled(_container(repo))).step, OnboardingStep.cycle);

      final second = _MockOnboardingRepository();
      when(second.getState).thenAnswer(
        (_) async => Fresh(
          onboardingStateFixture(cycleProvided: true, baselineProvided: true),
        ),
      );
      expect((await _settled(_container(second))).step, OnboardingStep.goals);
    });

    test('it keeps the whole state response for the step screens', () async {
      // Screens 3-7 prefill from four different parts of this response
      // (`lastPeriodStart`, the three preference lists). A flow that carried
      // only the landing step would send five later tasks back to the network.
      final response = onboardingStateFixture(
        cycleProvided: true,
        lastPeriodStart: null,
      );
      stubState(response);

      expect((await _settled(_container(repo))).state, response);
    });

    test('a stale (cached) resume is usable, not an error', () async {
      when(repo.getState).thenAnswer(
        (_) async => Stale(onboardingStateFixture(cycleProvided: true)),
      );

      expect((await _settled(_container(repo))).step, OnboardingStep.baseline);
    });

    test(
      'offline with no cache is an error state the screen can retry',
      () async {
        when(repo.getState).thenAnswer(
          (_) async =>
              const NetworkRequired<OnboardingStateResponse>(NetworkFailure()),
        );

        final state = await _settledOrError(_container(repo));

        expect(state, isA<AsyncError<OnboardingFlow>>());
        expect(
          (state as AsyncError<OnboardingFlow>).error,
          isA<NetworkFailure>(),
        );
      },
    );

    test(
      'a thrown failure becomes an error state, never an exception',
      () async {
        when(repo.getState).thenAnswer((_) async => throw const AuthFailure());

        final state = await _settledOrError(_container(repo));

        expect(state, isA<AsyncError<OnboardingFlow>>());
        expect((state as AsyncError<OnboardingFlow>).error, isA<AuthFailure>());
      },
    );

    test(
      'a state that reports onboarding already complete opens the router gate',
      () async {
        // The stuck case: a cached `/me` says not-onboarded (so the gate sent
        // the user here) while the server says it is done. Without this the
        // user sits in a flow they have already finished.
        stubState(
          onboardingStateFixture(
            completed: true,
            cycleProvided: true,
            completedAt: DateTime.utc(2026, 4, 1),
          ),
        );
        final container = _container(repo);

        // Positive control: the gate is NOT open before the read lands, so the
        // assertion below cannot be satisfied by the default.
        expect(
          container.read(onboardingStatusProvider),
          isNot(OnboardingStatus.completed),
        );

        await _settled(container);

        expect(
          container.read(onboardingStatusProvider),
          OnboardingStatus.completed,
        );
      },
    );

    test('an unfinished flow leaves the router gate alone', () async {
      // The converse of the test above, and the reason it is here: "the gate
      // was not opened" is also true of a controller that never opens it, so
      // the two tests are only meaningful as a pair.
      stubState(onboardingStateFixture(completed: false, cycleProvided: true));
      final container = _container(repo);

      await _settled(container);

      expect(
        container.read(onboardingStatusProvider),
        isNot(OnboardingStatus.completed),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Walking the flow
  // -------------------------------------------------------------------------

  group('navigation', () {
    test('goTo moves the flow and keeps everything else', () async {
      stubState(onboardingStateFixture());
      final container = _container(repo);
      final before = await _settled(container);
      expect(before.step, OnboardingStep.cycle);

      _notifier(container).goTo(OnboardingStep.hormones);

      final after = container.read(onboardingFlowControllerProvider).value!;
      expect(after.step, OnboardingStep.hormones);
      expect(after.state, before.state);
    });

    test('back walks one step and stops at the first', () async {
      stubState(
        onboardingStateFixture(cycleProvided: true, baselineProvided: true),
      );
      final container = _container(repo);
      expect((await _settled(container)).step, OnboardingStep.goals);

      _notifier(container).back();
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.baseline,
      );

      _notifier(container).back();
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.cycle,
      );

      // The first step has nowhere to go back TO — screen 2 created an account
      // that already exists.
      _notifier(container).back();
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.cycle,
      );
    });

    test('walking on clears what the last attempt to finish said', () async {
      // `complete()`'s own 409 path creates this state: it routes the user to
      // the step that owes an answer AND leaves the banner up. Once they answer
      // it and walk on, that message describes a condition they have fixed.
      //
      // The control is the 409 itself, asserted landed before the walk — so
      // "there is no failure now" is a fact about `goTo` rather than about a
      // flow that never had one.
      stubState(
        onboardingStateFixture(
          baselineProvided: true,
          goalsProvided: true,
          hormonesProvided: true,
        ),
      );
      final container = _container(repo);
      await _settled(container);
      _notifier(container).goTo(OnboardingStep.notifications);

      when(repo.complete).thenAnswer(
        (_) async => throw const ConflictFailure(
          message:
              'Onboarding cannot be completed until every mandatory step is '
              'answered.',
          code: 'onboarding_incomplete',
          missingSteps: ['cycle'],
        ),
      );
      await _notifier(container).complete();

      final rejected = container.read(onboardingFlowControllerProvider).value!;
      expect(rejected.step, OnboardingStep.cycle, reason: 'premise: it routed');
      expect(rejected.failure, isNotNull, reason: 'premise: the banner is up');

      _notifier(container).next();

      final moved = container.read(onboardingFlowControllerProvider).value!;
      expect(moved.step, OnboardingStep.baseline);
      expect(
        moved.failure,
        isNull,
        reason:
            'A message about an unanswered mandatory step must not follow the '
            'user onto steps 4, 5, 6 and 7 once they have answered it.',
      );
    });

    test('a step change does not clear a failure it never left', () async {
      // The converse, and the reason the pair means anything: a `goTo` to the
      // step you are already on is a no-op, so it must not quietly discard the
      // banner a rejection put there. That is the 409's own landing state.
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      await _settled(container);

      when(repo.complete).thenAnswer((_) async => throw const NetworkFailure());
      await _notifier(container).complete();
      final before = container.read(onboardingFlowControllerProvider).value!;
      expect(before.failure, isNotNull, reason: 'premise');

      _notifier(container).goTo(before.step);

      expect(
        container.read(onboardingFlowControllerProvider).value!.failure,
        isNotNull,
      );
    });

    test('next walks one step and stops at the last', () async {
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      expect((await _settled(container)).step, OnboardingStep.baseline);

      _notifier(container)
        ..next()
        ..next()
        ..next();
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.notifications,
      );

      _notifier(container).next();
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.notifications,
      );
    });

    test('navigating before the resume read lands changes nothing', () async {
      // The controller-shape rule's other half: an action on an unsettled
      // controller must be a no-op, not a write that the load then clobbers (or
      // worse, does not).
      when(repo.getState).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return Fresh(onboardingStateFixture());
      });
      final container = _container(repo);

      container.read(onboardingFlowControllerProvider);
      _notifier(container).goTo(OnboardingStep.notifications);
      expect(
        container.read(onboardingFlowControllerProvider),
        isA<AsyncLoading<OnboardingFlow>>(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The resume answer wins, and the discarded `goTo` did not corrupt it.
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.cycle,
      );
      // Positive control: the SAME call, made once the controller is settled,
      // does move the flow — so the no-op above is a fact about the gate, not
      // about `goTo` being unwired.
      _notifier(container).goTo(OnboardingStep.notifications);
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.notifications,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Recording what a step write stored (P4b-T8b)
  // -------------------------------------------------------------------------
  //
  // `OnboardingFlow.state` is what a step controller prefills from when it is
  // rebuilt, and every step controller is `autoDispose` behind a back
  // affordance — so a step the user has already written re-seeds from this
  // value. These tests are about the value; what it costs to get it wrong is in
  // `onboarding_back_navigation_test.dart`, one test per screen.

  group('recording a step write', () {
    test(
      'it replaces that step\'s projection and leaves the flow standing',
      () async {
        stubState(
          onboardingStateFixture(
            cycleProvided: true,
            lastPeriodStart: Date(2026, 4, 1),
            goals: const <String, bool>{
              'manage_symptoms': true,
              'just_curious': false,
            },
          ),
        );
        final container = _container(repo);
        final before = await _settled(container);

        // Premises: the flow is on a step that is NOT the first, and it holds the
        // pre-save values. Both assertions below are the opposite of these.
        expect(before.step, OnboardingStep.baseline);
        expect(before.state.lastPeriodStart, Date(2026, 4, 1));
        expect(before.state.goals!.first.selected, isTrue);

        _notifier(container)
          ..recordCycleSaved(Date(2026, 4, 6))
          ..recordGoalsSaved(
            BuiltList<GoalSelection>(
              goalSelections(const <String, bool>{
                'manage_symptoms': false,
                'just_curious': true,
              }),
            ),
          );

        final after = container.read(onboardingFlowControllerProvider).value!;
        expect(after.state.lastPeriodStart, Date(2026, 4, 6));
        expect(
          <String, bool>{
            for (final GoalSelection g in after.state.goals!)
              g.code!: g.selected!,
          },
          <String, bool>{'manage_symptoms': false, 'just_curious': true},
        );

        // The step is untouched: recording is not navigation. Recording the
        // cycle write from step 4 must not send the user back to step 3.
        expect(after.step, OnboardingStep.baseline);
        // …and neither write disturbed the other's projection, nor the booleans
        // `resumeStepFrom` reads.
        expect(after.state.cycleProvided, isTrue);
        expect(after.state.goalsProvided, isFalse);
      },
    );

    test(
      'a response that carried no goal list is recorded as no list',
      () async {
        // `GoalsForm.fromWire(null)` falls back to the ratified D-14 seed, and
        // `fromWire([])` produces a form with NO codes at all — a screen that
        // could never be submitted. So a null must stay a null here; a builder
        // written the auto-vivifying way (`b.goals.replace(...)`) would turn it
        // into an empty list.
        stubState(
          onboardingStateFixture(
            cycleProvided: true,
            goals: const <String, bool>{'manage_symptoms': true},
          ),
        );
        final container = _container(repo);
        final before = await _settled(container);
        // Premise: there IS a list to lose.
        expect(before.state.goals, isNotNull);

        _notifier(container).recordGoalsSaved(null);

        expect(
          container.read(onboardingFlowControllerProvider).value!.state.goals,
          isNull,
        );
      },
    );

    test('recording before the resume read lands changes nothing', () async {
      // The controller-shape rule's other half, the same way `goTo` states it:
      // an action on an unsettled controller is a no-op, never a write the
      // load then clobbers.
      when(repo.getState).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return Fresh(onboardingStateFixture(lastPeriodStart: Date(2026, 4, 1)));
      });
      final container = _container(repo);

      container.read(onboardingFlowControllerProvider);
      _notifier(container).recordCycleSaved(Date(2026, 4, 6));
      expect(
        container.read(onboardingFlowControllerProvider),
        isA<AsyncLoading<OnboardingFlow>>(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The resume answer wins, and the discarded record did not corrupt it.
      expect(
        container
            .read(onboardingFlowControllerProvider)
            .value!
            .state
            .lastPeriodStart,
        Date(2026, 4, 1),
      );
      // Positive control: the SAME call, once settled, does move it — so the
      // no-op above is a fact about the gate and not about an unwired method.
      _notifier(container).recordCycleSaved(Date(2026, 4, 6));
      expect(
        container
            .read(onboardingFlowControllerProvider)
            .value!
            .state
            .lastPeriodStart,
        Date(2026, 4, 6),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Finishing
  // -------------------------------------------------------------------------

  group('complete', () {
    test('a successful completion opens the router gate', () async {
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      await _settled(container);

      expect(
        container.read(onboardingStatusProvider),
        isNot(OnboardingStatus.completed),
        reason: 'premise: the gate is shut before finishing',
      );

      await _notifier(container).complete();

      verify(repo.complete).called(1);
      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.completed,
      );
      expect(
        container.read(onboardingFlowControllerProvider).value!.failure,
        isNull,
      );
    });

    test(
      'the four skippable steps do not have to be answered to finish (D-02)',
      () async {
        // Only the mandatory step is answered. The client must not add a gate
        // the server does not have: D-02 makes baseline/goals/hormones/
        // notifications skippable, and skipping means never calling them.
        stubState(
          onboardingStateFixture(
            cycleProvided: true,
            baselineProvided: false,
            goalsProvided: false,
            hormonesProvided: false,
            notificationsProvided: false,
          ),
        );
        final container = _container(repo);
        await _settled(container);

        await _notifier(container).complete();

        verify(repo.complete).called(1);
        expect(
          container.read(onboardingStatusProvider),
          OnboardingStatus.completed,
        );
      },
    );

    test('completion reports itself as in flight while it is', () async {
      stubState(onboardingStateFixture(cycleProvided: true));
      final release = Completer<OnboardingCompleteResponse>();
      when(repo.complete).thenAnswer((_) => release.future);
      final container = _container(repo);
      final before = await _settled(container);

      expect(before.submitting, isFalse, reason: 'premise');

      final pending = _notifier(container).complete();
      expect(
        container.read(onboardingFlowControllerProvider).value!.submitting,
        isTrue,
      );

      release.complete(onboardingCompleteFixture());
      await pending;

      expect(
        container.read(onboardingFlowControllerProvider).value!.submitting,
        isFalse,
      );
    });

    test('a completion already in flight is not issued twice', () async {
      stubState(onboardingStateFixture(cycleProvided: true));
      final release = Completer<OnboardingCompleteResponse>();
      when(repo.complete).thenAnswer((_) => release.future);
      final container = _container(repo);
      await _settled(container);

      final first = _notifier(container).complete();
      await _notifier(container).complete();

      verify(repo.complete).called(1);

      release.complete(onboardingCompleteFixture());
      await first;

      // Positive control: once the first one has landed, a second completion
      // DOES reach the repository — so the assertion above is about the
      // in-flight guard, not about a repository nobody calls.
      await _notifier(container).complete();
      verify(repo.complete).called(1);
    });

    // -----------------------------------------------------------------------
    // The 409
    // -----------------------------------------------------------------------

    test('a 409 naming a missing step sends the user to that step', () async {
      // POSITIVE CONTROL: the flow starts on the LAST step, and that is
      // asserted before the completion runs. Starting it on `cycle` would
      // make "the flow is on cycle afterwards" true with the routing deleted.
      stubState(
        onboardingStateFixture(
          baselineProvided: true,
          goalsProvided: true,
          hormonesProvided: true,
        ),
      );
      final container = _container(repo);
      // Resume lands on cycle (it is unanswered), so move deliberately to the
      // finish screen — which is where a user pressing "Allow & finish" is.
      await _settled(container);
      _notifier(container).goTo(OnboardingStep.notifications);
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.notifications,
        reason: 'premise: the user is on the finish screen, not on cycle',
      );

      when(repo.complete).thenAnswer(
        (_) async => throw const ConflictFailure(
          message:
              'Onboarding cannot be completed until every mandatory step is '
              'answered.',
          code: 'onboarding_incomplete',
          missingSteps: ['cycle'],
        ),
      );

      await _notifier(container).complete();

      final flow = container.read(onboardingFlowControllerProvider).value!;
      expect(flow.step, OnboardingStep.cycle);
      expect(flow.submitting, isFalse);
      expect(flow.failure, isA<ConflictFailure>());
      expect(
        container.read(onboardingStatusProvider),
        isNot(OnboardingStatus.completed),
      );
    });

    test(
      'a conflict that names no step leaves the user where they are',
      () async {
        // Same 409 machinery, a different body: `missingSteps` empty. Moving the
        // user on the strength of a code alone would send them to a step the
        // server never asked for.
        stubState(onboardingStateFixture(cycleProvided: true));
        final container = _container(repo);
        await _settled(container);
        _notifier(container).goTo(OnboardingStep.notifications);

        when(repo.complete).thenAnswer(
          (_) async => throw const ConflictFailure(
            message: 'That request conflicts with existing data.',
            code: 'onboarding_incomplete',
          ),
        );

        await _notifier(container).complete();

        final flow = container.read(onboardingFlowControllerProvider).value!;
        expect(flow.step, OnboardingStep.notifications);
        expect(flow.failure, isA<ConflictFailure>());
      },
    );

    test('a 409 carrying a DIFFERENT code routes nobody', () async {
      // The `code` guard, which nothing else reaches: every other 409 test
      // varies `missingSteps` and leaves the code at `onboarding_incomplete`,
      // so deleting `if (failure.code != incompleteCode) return null;` left the
      // suite green.
      //
      // `onboarding_already_completed` is a real second code on this surface —
      // it is what `POST /onboarding/cycle` answers after completion — and the
      // body below is otherwise IDENTICAL to the routing one, `missingSteps`
      // included. That identity is the control: the first half proves this
      // exact payload DOES move the user when the code is the routing one.
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      await _settled(container);
      _notifier(container).goTo(OnboardingStep.notifications);

      when(repo.complete).thenAnswer(
        (_) async => throw const ConflictFailure(
          code: 'onboarding_incomplete',
          missingSteps: ['cycle'],
        ),
      );
      await _notifier(container).complete();
      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.cycle,
        reason: 'positive control: this payload routes when the code matches',
      );

      _notifier(container).goTo(OnboardingStep.notifications);
      when(repo.complete).thenAnswer(
        (_) async => throw const ConflictFailure(
          code: 'onboarding_already_completed',
          missingSteps: ['cycle'],
        ),
      );
      await _notifier(container).complete();

      final flow = container.read(onboardingFlowControllerProvider).value!;
      expect(flow.step, OnboardingStep.notifications);
      expect(flow.failure, isA<ConflictFailure>());
    });

    test('a 409 with no code at all routes nobody', () async {
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      await _settled(container);
      _notifier(container).goTo(OnboardingStep.hormones);

      when(repo.complete).thenAnswer(
        (_) async => throw const ConflictFailure(missingSteps: ['cycle']),
      );
      await _notifier(container).complete();

      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.hormones,
      );
    });

    test('an unknown step code is not a destination', () async {
      // `missingSteps` is append-only on the server. A code this client does
      // not know must leave the user where they are with the message, not send
      // them to a guessed screen.
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      await _settled(container);
      _notifier(container).goTo(OnboardingStep.goals);

      when(repo.complete).thenAnswer(
        (_) async => throw const ConflictFailure(
          code: 'onboarding_incomplete',
          missingSteps: ['consent'],
        ),
      );

      await _notifier(container).complete();

      expect(
        container.read(onboardingFlowControllerProvider).value!.step,
        OnboardingStep.goals,
      );
    });

    test('a network failure keeps the user on the finish screen', () async {
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      await _settled(container);
      _notifier(container).goTo(OnboardingStep.notifications);

      when(repo.complete).thenAnswer((_) async => throw const NetworkFailure());

      await _notifier(container).complete();

      final flow = container.read(onboardingFlowControllerProvider).value!;
      expect(flow.step, OnboardingStep.notifications);
      expect(flow.failure, isA<NetworkFailure>());
      expect(
        container.read(onboardingStatusProvider),
        isNot(OnboardingStatus.completed),
      );
    });

    test('a rejection does not survive the next attempt', () async {
      // The trap the controller-shape rule names: `await future` resolves with
      // the first non-loading state, so a controller that awaited it would
      // rethrow the PREVIOUS rejection on the next submit and the button would
      // look permanently broken.
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      await _settled(container);

      when(repo.complete).thenAnswer((_) async => throw const NetworkFailure());
      await _notifier(container).complete();
      expect(
        container.read(onboardingFlowControllerProvider).value!.failure,
        isNotNull,
        reason: 'premise: the first attempt was rejected',
      );

      when(repo.complete).thenAnswer((_) async => onboardingCompleteFixture());
      await _notifier(container).complete();

      expect(
        container.read(onboardingFlowControllerProvider).value!.failure,
        isNull,
      );
      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.completed,
      );
    });

    test('a retry clears the previous failure BEFORE it lands', () async {
      // Not the same assertion as the test above it, and the difference is
      // what the user sees: that one is about the state a retry SETTLES on,
      // this one about the state it passes through. Leaving the old banner up
      // beside the new spinner tells the user the attempt they are watching has
      // already failed.
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      await _settled(container);

      when(repo.complete).thenAnswer((_) async => throw const NetworkFailure());
      await _notifier(container).complete();
      expect(
        container.read(onboardingFlowControllerProvider).value!.failure,
        isNotNull,
        reason: 'premise: there is a failure on screen to clear',
      );

      final release = Completer<OnboardingCompleteResponse>();
      when(repo.complete).thenAnswer((_) => release.future);
      final pending = _notifier(container).complete();

      final inFlight = container.read(onboardingFlowControllerProvider).value!;
      expect(inFlight.submitting, isTrue, reason: 'premise: it is in flight');
      expect(inFlight.failure, isNull);

      release.complete(onboardingCompleteFixture());
      await pending;
    });

    test('an error that is not a Failure still settles the button', () async {
      // `cachedWrite` invalidates its keys UNGUARDED after a successful write,
      // so a concurrent logout-purge closing the Hive box throws from
      // `complete()` — after the account was completed server-side. With
      // `on Failure` alone that escapes as an unhandled async error and the
      // flow keeps `submitting: true` forever: a spinner that never stops, on
      // an account that is already done.
      stubState(onboardingStateFixture(cycleProvided: true));
      final container = _container(repo);
      final before = await _settled(container);

      when(
        repo.complete,
      ).thenAnswer((_) async => throw StateError('the cache box was closed'));

      await _notifier(container).complete();

      final flow = container.read(onboardingFlowControllerProvider).value!;
      expect(
        flow.submitting,
        isFalse,
        reason: 'the finish button must become pressable again',
      );
      expect(
        flow.failure,
        isNotNull,
        reason: 'and it must say something, or the tap looks like a no-op',
      );
      expect(flow.step, before.step, reason: 'nothing routes anyone');

      // …and the retry works, which is what makes settling the right answer: a
      // repeat completion answers 200 with `alreadyCompleted: true`.
      when(repo.complete).thenAnswer(
        (_) async => onboardingCompleteFixture(alreadyCompleted: true),
      );
      await _notifier(container).complete();

      expect(
        container.read(onboardingStatusProvider),
        OnboardingStatus.completed,
      );
    });

    test('completing before the resume read lands issues no request', () async {
      when(repo.getState).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return Fresh(onboardingStateFixture(cycleProvided: true));
      });
      final container = _container(repo);

      container.read(onboardingFlowControllerProvider);
      await _notifier(container).complete();
      verifyNever(repo.complete);

      // Positive control: the same call after the settle DOES reach the
      // repository, so the `verifyNever` is about the settled-gate rather than
      // about a stub nobody wired.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _notifier(container).complete();
      verify(repo.complete).called(1);
    });
  });
}
