// HormonesController — screen 6's state (P4b-T12).
//
// Screen 6 is the flow's SECOND full-replace surface and, in one way, the
// sharpest: `POST /onboarding/hormones` stores the body as the complete desired
// state of `user_hormone_prefs`, so a code left out is written as
// `Charted = false` rather than left standing
// (`backend/src/Lumen.Api/Onboarding/OnboardingStepsService.cs:448-464`,
// `ARCHITECTURE.md` §C.0.1). But unlike screen 5 this endpoint has **no
// minimum**: `chartedHormones: []` is a real answer — "chart nothing" — and the
// server rejects only a NULL (`OnboardingStepsService.cs:435-436`, where
// `SaveGoalsAsync` adds a second arm for `Count == 0` at `:369-375`). So the
// empty case is tested here as a SUCCESS, and screen 5's min-1 rule is absent
// on purpose rather than by omission.
//
// Three rules carry this file:
//
//   * the write is the WHOLE charted set, every time, never a diff. The
//     discriminating assertion is that an untouched-but-charted code travels;
//   * the vocabulary is the SERVER's. The response lists every code in frozen
//     order with a boolean each, and the client renders that list rather than
//     re-deriving it — so the prefill tests hand over a list that CONTRADICTS
//     the D-14 all-ON seed, in an order that is not the frozen order, and
//     assert the form followed the wire;
//   * the array carries WIRE CODES. `estradiol` is drawn as "Estrogen" and
//     `glp1` as "GLP-1" (B16); the labels are i18n source strings that are
//     never stored and never sent, and a label on this array is a 400.
//
// The ratified table (`survey/decisions-and-vocabularies.md` §2.9) survives
// here only as [HormoneOption]'s copy and as the seed for the one case the wire
// cannot answer — a response that carries no list at all.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/hormone_prefs_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/features/onboarding/application/hormones_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// The shell's flow, settled on step 6 with [state0] as its resume read.
class _SettledFlow extends OnboardingFlowController {
  _SettledFlow(this.state0);

  final OnboardingStateResponse state0;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(step: OnboardingStep.hormones, state: state0),
  );
}

/// One assembled screen-6 world.
class _World {
  /// [keepFlowAlive] false leaves NOTHING watching the flow, so it is disposed
  /// again the moment `HormonesController.build()` has read it — which is what
  /// a screen test that mounts a step body without the shell already does, and
  /// what the app does once the shell itself is gone.
  _World({
    Map<String, bool>? hormones,
    bool hormonesProvided = false,
    bool keepFlowAlive = true,
  }) : repo = _MockOnboardingRepository() {
    container = ProviderContainer(
      retry: lumenRetry,
      overrides: <Override>[
        onboardingFlowControllerProvider.overrideWith(
          () => _SettledFlow(
            onboardingStateFixture(
              cycleProvided: true,
              hormonesProvided: hormonesProvided,
              hormones: hormones,
            ),
          ),
        ),
        onboardingRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    // Both providers are autoDispose. A bare `read` disposes them as it
    // returns; a subscription is what a screen's `ref.watch` does.
    container.listen(hormonesControllerProvider, (_, _) {});
    if (keepFlowAlive) {
      container.listen(onboardingFlowControllerProvider, (_, _) {});
    }
  }

  final _MockOnboardingRepository repo;
  late final ProviderContainer container;

  HormonesController get notifier =>
      container.read(hormonesControllerProvider.notifier);

  HormonesForm get form => container.read(hormonesControllerProvider);

  OnboardingStep get step =>
      container.read(onboardingFlowControllerProvider).value!.step;

  void answerSave([HormonePrefsResponse? body]) {
    when(
      () => repo.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) async => body ?? hormonePrefsResponseFixture());
  }

  void rejectSave(Failure failure) {
    when(
      () => repo.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) async => throw failure);
  }

  /// The array the repository was actually handed.
  List<String> get postedCodes =>
      verify(
            () => repo.saveHormones(codes: captureAny(named: 'codes')),
          ).captured.last
          as List<String>;

  void verifyNoSave() =>
      verifyNever(() => repo.saveHormones(codes: any(named: 'codes')));
}

/// `code -> charted`, in the order the form holds them.
Map<String, bool> _shape(HormonesForm form) => <String, bool>{
  for (final HormoneChoice choice in form.hormones) choice.code: choice.charted,
};

void main() {
  setUpAll(() => registerFallbackValue(const <String>['estradiol']));

  // -------------------------------------------------------------------------
  // The vocabulary comes off the wire
  // -------------------------------------------------------------------------

  test('the selections come from the RESPONSE, not from the ratified seed', () {
    // A stored answer that contradicts the D-14 seed on every code. A client
    // that re-derived the vocabulary — or that drew the seed and called it a
    // prefill — reads exactly the opposite of this.
    final world = _World(
      hormones: const <String, bool>{
        'estradiol': false,
        'progesterone': false,
        'lh': true,
        'fsh': false,
        'testosterone': false,
        'cortisol': false,
        'glp1': false,
      },
    );

    expect(world.form.chartedCodes, <String>['lh']);

    // The positive control: the seed this build holds is ALL SEVEN ON, so the
    // assertion above is a fact about the wire rather than about a list that
    // happens to agree with the client's own table.
    expect(
      HormoneOption.values.every((HormoneOption o) => o.defaultCharted),
      isTrue,
      reason: 'D-14 seeds all seven ON — the fixture above is its opposite',
    );
  });

  test('the order is the RESPONSE\'s order, not a client-side one', () {
    // Deliberately not the frozen order: the point is that the form holds the
    // order it was sent rather than one it re-derives.
    const scrambled = <String, bool>{
      'glp1': true,
      'lh': false,
      'estradiol': true,
      'cortisol': false,
    };
    final world = _World(hormones: scrambled);

    expect(_shape(world.form).keys.toList(), scrambled.keys.toList());

    // Positive control: that is NOT the frozen order, so the row above cannot
    // pass for a form that ignored the wire and listed its own table.
    expect(
      scrambled.keys.toList(),
      isNot(HormoneOption.values.map((HormoneOption o) => o.wireName).toList()),
    );
  });

  test('a code this build has no copy for is CARRIED, never dropped', () async {
    // The vocabulary is append-only on the server. There is no label, no
    // category and no swatch for a code this build has never seen — inventing
    // one from the wire code would be authoring copy — but on a FULL REPLACE
    // endpoint, dropping it from the array stores the user's answer as a
    // deselection.
    final world = _World(
      hormones: const <String, bool>{
        'estradiol': true,
        'shbg': true,
        'glp1': false,
      },
    )..answerSave();

    expect(_shape(world.form), <String, bool>{
      'estradiol': true,
      'shbg': true,
      'glp1': false,
    });
    // …and it is not drawable, because there is nothing to draw.
    expect(world.form.drawable.map((HormoneChoice c) => c.code), <String>[
      'estradiol',
      'glp1',
    ]);

    await world.notifier.submit();

    expect(world.postedCodes, <String>['estradiol', 'shbg']);
  });

  test('with no list on the wire it falls back to the D-14 all-ON seed', () {
    // The one case the ratified table is a source of truth for: every generated
    // property is nullable (§C.0.2) and a P3b-era cached `GET /onboarding/state`
    // predates this member entirely. The fallback is `UserHormonePref.
    // DefaultCharted` — the same per-code seed `ReadHormonePrefsAsync` applies
    // (`OnboardingStepsService.cs:620-633`) for a user who has never answered.
    final world = _World();

    expect(_shape(world.form), kSeededHormones);
    expect(world.form.chartedCodes, <String>[
      'estradiol',
      'progesterone',
      'lh',
      'fsh',
      'testosterone',
      'cortisol',
      'glp1',
    ]);
  });

  // -------------------------------------------------------------------------
  // Toggling
  // -------------------------------------------------------------------------

  test('toggling flips exactly one code and leaves the rest standing', () {
    final world = _World();

    // Premise: the code under test is ON and so is its neighbour, so what
    // changes below is the toggle's doing.
    expect(world.form.chartedCodes, contains('cortisol'));
    expect(world.form.chartedCodes, contains('glp1'));

    world.notifier.toggle('cortisol');

    expect(world.form.chartedCodes, isNot(contains('cortisol')));
    expect(world.form.chartedCodes, contains('glp1'));

    // It flips back — a toggle that only ever turned things off would satisfy
    // every row above, and this step's whole datum is the pair of directions.
    world.notifier.toggle('cortisol');
    expect(world.form.chartedCodes, contains('cortisol'));
  });

  test('a toggle during a save is refused', () async {
    // That request already carries its codes and the 200 replaces the form with
    // the server's re-read, so a toggle accepted here would be silently
    // discarded a moment later.
    final world = _World();
    final Completer<HormonePrefsResponse> gate =
        Completer<HormonePrefsResponse>();
    when(
      () => world.repo.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) => gate.future);

    unawaited(world.notifier.submit());
    expect(world.form.submitting, isTrue, reason: 'premise: a save is open');

    world.notifier.toggle('cortisol');
    expect(world.form.chartedCodes, contains('cortisol'));

    gate.complete(hormonePrefsResponseFixture());
    await Future<void>.delayed(Duration.zero);

    // The control: with no save open the same toggle IS accepted, so the
    // refusal above is a fact about the guard and not about an unwired method.
    world.notifier.toggle('cortisol');
    expect(world.form.chartedCodes, isNot(contains('cortisol')));
  });

  // -------------------------------------------------------------------------
  // Continue — the FULL REPLACE
  // -------------------------------------------------------------------------

  test('Continue posts the COMPLETE charted set, never a diff', () async {
    final world = _World(
      hormones: const <String, bool>{
        'estradiol': true,
        'progesterone': true,
        'lh': false,
        'fsh': false,
        'testosterone': false,
        'cortisol': false,
        'glp1': false,
      },
    )..answerSave();

    world.notifier
      ..toggle('lh') // off -> on
      ..toggle('estradiol'); // on  -> off

    await world.notifier.submit();

    // Captured ONCE — `verify` consumes the recorded invocation.
    final List<String> posted = world.postedCodes;
    // The whole test is the middle element. `progesterone` was not touched on
    // this visit — a client that sent the diff would post `['lh']`, and the
    // server's FULL REPLACE would then store `progesterone` as DESELECTED.
    expect(posted, <String>['progesterone', 'lh']);
    // …and the deselected code is absent rather than sent as `false`: on this
    // wire shape, absence IS the deselection.
    expect(posted, isNot(contains('estradiol')));

    expect(world.step, OnboardingStep.notifications);
  });

  test('an untouched screen still posts the whole set', () async {
    // A full replace is idempotent, and re-posting is what makes
    // `hormonesProvided` true for a user who accepted the defaults without
    // touching a row.
    final world = _World()..answerSave();

    await world.notifier.submit();

    expect(world.postedCodes, kSeededHormones.keys.toList());
  });

  // -------------------------------------------------------------------------
  // Charting nothing — a valid answer, NOT screen 5's min-1 rule
  // -------------------------------------------------------------------------

  test('charting NOTHING is a valid answer: it posts an empty array and '
      'walks on', () async {
    // `chartedHormones: []` is VALID. This endpoint has no minimum at all: the
    // server keys `value is required` on a NULL and on nothing else
    // (`OnboardingStepsService.cs:435-436`). Screen 5's min-1 gate must NOT be
    // copied here — an inert Continue would refuse an answer the server stores,
    // and "chart nothing" is a different state from having skipped the step.
    //
    // It costs the user nothing to say: charted decides only whether a series
    // is DRAWN. P7b extracts all seven hormones from every lab regardless
    // (D-14, `OnboardingContracts.cs:210-214`).
    final world = _World()
      ..answerSave(
        hormonePrefsResponseFixture(const <String, bool>{
          'estradiol': false,
          'progesterone': false,
          'lh': false,
          'fsh': false,
          'testosterone': false,
          'cortisol': false,
          'glp1': false,
        }),
      );

    for (final String code in kSeededHormones.keys) {
      world.notifier.toggle(code);
    }
    // Premise: there is genuinely nothing selected, so the empty array below is
    // the user's answer rather than a form that never seeded.
    expect(world.form.hormones, hasLength(7));
    expect(world.form.chartedCodes, isEmpty);

    await world.notifier.submit();

    expect(world.postedCodes, isEmpty);
    // It is a SUCCESS: the step advances and nothing is held as a failure.
    expect(world.step, OnboardingStep.notifications);
    expect(world.form.failure, isNull);
    expect(world.form.submitting, isFalse);
  });

  test('the empty answer is a POST, not a skip', () async {
    // The control that separates "it posted []" from "it posted nothing at
    // all": screen 5 answers this same shape by making no request, and a
    // controller that copied it would look identical on the step counter.
    final world = _World()..answerSave();

    for (final String code in kSeededHormones.keys) {
      world.notifier.toggle(code);
    }
    await world.notifier.submit();

    verify(() => world.repo.saveHormones(codes: any(named: 'codes'))).called(1);
  });

  // -------------------------------------------------------------------------
  // Codes on the wire, labels on the screen
  // -------------------------------------------------------------------------

  test('the array carries WIRE CODES, never the display labels', () async {
    final world = _World()..answerSave();

    await world.notifier.submit();

    final List<String> posted = world.postedCodes;
    expect(posted, contains('estradiol'));
    expect(posted, contains('glp1'));

    // The positive control, and it is the whole point: these two codes have
    // labels that DIFFER from them, the labels are real strings this build
    // holds and draws, and neither may travel. Without this pair the two rows
    // above would pass for a client whose codes and labels were the same string.
    expect(HormoneOption.estradiol.label, 'Estrogen');
    expect(HormoneOption.glp1.label, 'GLP-1');
    expect(posted, isNot(contains('Estrogen')));
    expect(posted, isNot(contains('GLP-1')));
    // …and no member's label reaches the wire, not just those two.
    for (final HormoneOption option in HormoneOption.values) {
      if (option.label == option.wireName) continue;
      expect(
        posted,
        isNot(contains(option.label)),
        reason: '${option.label} is an i18n source string, never a wire code',
      );
    }
  });

  test('a display label is not a code this build recognises', () {
    // Matched exactly and never case-folded: the server compares with
    // `StringComparer.Ordinal` (`OnboardingStepsService.cs:1127-1149`), so a
    // client that folded case would treat `Estradiol` as a hormone it knows and
    // then send a code the server answers 400 for.
    expect(HormoneOption.fromWireName('Estrogen'), isNull);
    expect(HormoneOption.fromWireName('GLP-1'), isNull);
    expect(HormoneOption.fromWireName('Estradiol'), isNull);
    // The control: the real codes DO resolve, so the nulls above are about the
    // strings rather than about a lookup that always answers null.
    expect(HormoneOption.fromWireName('estradiol'), HormoneOption.estradiol);
    expect(HormoneOption.fromWireName('glp1'), HormoneOption.glp1);
  });

  // -------------------------------------------------------------------------
  // The response, the flow, and the failures
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
          hormonePrefsResponseFixture(const <String, bool>{
            'estradiol': false,
            'progesterone': false,
            'lh': false,
            'fsh': true,
            'testosterone': false,
            'cortisol': false,
            'glp1': false,
          }),
        );

      // Premise: the form does NOT already look like that.
      expect(world.form.chartedCodes, hasLength(7));

      await world.notifier.submit();

      expect(world.form.chartedCodes, <String>['fsh']);
      expect(world.step, OnboardingStep.notifications);
    },
  );

  test('a successful save refreshes the FLOW, so a rebuilt controller seeds '
      'from what the server stored', () async {
    // T8b, at the controller seam. Every step controller is `autoDispose` and
    // the shell draws a back affordance on every step past the first, so
    // leaving this step disposes it and returning REBUILDS it out of
    // `OnboardingFlow.state`. On a FULL REPLACE endpoint a stale seed is not a
    // stale view — it is the next request's body.
    final world = _World(hormones: kSeededHormones)
      ..answerSave(
        hormonePrefsResponseFixture(const <String, bool>{
          'estradiol': false,
          'progesterone': false,
          'lh': false,
          'fsh': false,
          'testosterone': false,
          'cortisol': true,
          'glp1': false,
        }),
      );

    world.notifier.toggle('cortisol');
    await world.notifier.submit();

    // The rebuild, forced the way `autoDispose` does it for real.
    world.container.invalidate(hormonesControllerProvider);

    expect(world.form.chartedCodes, <String>['cortisol']);
  });

  test(
    'a rejection is held on the form and the step does not advance',
    () async {
      const failure = ValidationFailure(
        message: 'The request contained invalid data.',
        fields: <String, List<String>>{
          'chartedHormones[0]': <String>['value is not an allowed value'],
        },
      );
      final world = _World()..rejectSave(failure);

      // Premise: nothing is wrong before the attempt.
      expect(world.form.failure, isNull);

      await world.notifier.submit();

      expect(world.form.failure, failure);
      expect(world.form.submitting, isFalse);
      expect(world.step, OnboardingStep.hormones);

      // The control: a save that succeeds DOES advance, so the row above is a
      // fact about the rejection and not about a controller that never moves.
      world.answerSave();
      await world.notifier.submit();
      expect(world.step, OnboardingStep.notifications);
      expect(world.form.failure, isNull);
    },
  );

  test('an untyped error still stops the spinner and says something', () async {
    // `cachedWrite` invalidates its keys UNGUARDED after a successful write, so
    // a concurrent logout purge closing the Hive box lands here — after the
    // answer was stored. Unhandled, that is a spinner that never stops.
    final world = _World();
    when(
      () => world.repo.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) async => throw StateError('box closed'));

    await world.notifier.submit();

    expect(world.form.submitting, isFalse);
    expect(world.form.failure, isA<UnknownFailure>());
    // …and the flow keeps the PRE-SAVE list, which is the documented cost of
    // the stored-but-reported-failure arm (T8b invariant 2): the row may have
    // landed server-side. The user sees a banner, so it is not silent.
    expect(world.step, OnboardingStep.hormones);
  });

  test(
    'a second Continue while the first is in flight issues one request',
    () async {
      final world = _World();
      var calls = 0;
      when(
        () => world.repo.saveHormones(codes: any(named: 'codes')),
      ).thenAnswer((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return hormonePrefsResponseFixture();
      });

      final first = world.notifier.submit();
      // Premise: the guard is only meaningful while a request is actually open.
      expect(world.form.submitting, isTrue);
      await world.notifier.submit();
      await first;

      expect(calls, 1);
    },
  );

  test('a save that lands after the FLOW is gone records nothing and throws '
      'nothing', () async {
    // The record is taken BEFORE this controller's own disposal gate, because
    // the flow outlives the step — that is what makes the shell's Back safe
    // during a save (`onboarding_back_navigation_test.dart`). But the flow is
    // `autoDispose` too, and it can be the one that goes: here nothing watches
    // it, which is the shape a screen test using `onboardingStepHost` has and
    // what the app has once the shell is gone.
    //
    // Writing to a disposed notifier throws, and this write sits OUTSIDE
    // `submit`'s try — so without `_recordSaved`'s own `ref.mounted` gate it
    // escapes as an unhandled async error.
    final world = _World(keepFlowAlive: false);

    final Completer<HormonePrefsResponse> pendingSave =
        Completer<HormonePrefsResponse>();
    when(
      () => world.repo.saveHormones(codes: any(named: 'codes')),
    ).thenAnswer((_) => pendingSave.future);

    expect(
      world.form.chartedCodes,
      isNotEmpty,
      reason: 'premise: there is an answer to save',
    );

    // The error handler is attached IMMEDIATELY, so a throw is captured rather
    // than escaping to the test zone as an unhandled async error.
    Object? escaped;
    final Future<void> pending = world.notifier.submit().catchError((
      Object error,
    ) {
      escaped = error;
    });

    // autoDispose is not synchronous — it runs on a later turn — so the gap is
    // what makes the assertion below a fact rather than a race.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(
      world.container.exists(onboardingFlowControllerProvider),
      isFalse,
      reason:
          'PREMISE: nothing is watching the flow, so it must be gone by the '
          'time the response lands — that is the state the gate is for',
    );

    pendingSave.complete(
      hormonePrefsResponseFixture(const <String, bool>{
        'estradiol': false,
        'progesterone': false,
        'lh': false,
        'fsh': false,
        'testosterone': false,
        'cortisol': false,
        'glp1': true,
      }),
    );

    await pending;

    // THE CONTROL for the assertion below, and it has to come first: an
    // `escaped == null` on its own is satisfied by a `submit` that never ran at
    // all. These three say the continuation ran to the end and did everything
    // the save does.
    expect(world.form.chartedCodes, <String>['glp1']);
    expect(world.form.submitting, isFalse);
    expect(world.form.failure, isNull);

    expect(
      escaped,
      isNull,
      reason: 'recording onto a flow that has gone must decline, not throw',
    );
  });

  test('a rejection is dropped as soon as the user answers again', () async {
    final world = _World()..rejectSave(const NetworkFailure());

    await world.notifier.submit();
    // Premise: there IS a rejection to drop. Without this the assertion below
    // passes against a controller that never records one.
    expect(world.form.failure, isA<NetworkFailure>());

    world.notifier.toggle('cortisol');

    // The banner describes an attempt the user has moved on from; leaving it up
    // asserts something about a form that no longer exists.
    expect(world.form.failure, isNull);
  });
}
