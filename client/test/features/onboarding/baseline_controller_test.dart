// BaselineController — screen 4's state (P4b-T10).
//
// Screen 4 is the first SKIPPABLE step of the flow (D-02), and that one fact
// decides most of this file. "Skip" means *not calling the endpoint*, because
// `POST /onboarding/baseline` answers **400** to a body carrying none of its
// six fields (`provide at least one baseline field`,
// `backend/src/Lumen.Api/Onboarding/OnboardingStepResult.cs:332`) — the only
// endpoint on the P4a surface with that check. So "Continue with nothing filled
// in" has to issue no request at all, and that is asserted here against a
// control that proves the same button DOES post when there is something to say.
//
// The endpoint MERGES: an omitted field is left unchanged, never reset. The
// controller therefore sends a DIFF against what the resume read said the
// server holds, for the same reason screen 3 does — filling a field in
// "helpfully" would overwrite a real answer with a default.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/baseline_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/onboarding/application/baseline_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockMeRepository extends Mock implements MeRepository {}

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// The shell's flow, settled on step 4.
class _SettledFlow extends OnboardingFlowController {
  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: OnboardingStep.baseline,
      state: onboardingStateFixture(cycleProvided: true),
    ),
  );
}

/// One assembled screen-4 world.
class _World {
  _World({
    MeResponse? profile,
    Failure? profileFailure,
    Date? today,
    Failure? todayFailure,
    Completer<CacheResult<MeResponse>>? profileGate,
  }) : meRepo = _MockMeRepository(),
       todayRepo = _MockServerTodayRepository(),
       onboardingRepo = _MockOnboardingRepository() {
    if (profileGate != null) {
      when(meRepo.getMe).thenAnswer((_) => profileGate.future);
    } else if (profileFailure != null) {
      when(
        meRepo.getMe,
      ).thenAnswer((_) async => NetworkRequired<MeResponse>(profileFailure));
    } else {
      when(
        meRepo.getMe,
      ).thenAnswer((_) async => Fresh<MeResponse>(profile ?? meResponseFixture()));
    }

    if (todayFailure != null) {
      when(todayRepo.today).thenAnswer((_) async => throw todayFailure);
    } else {
      when(todayRepo.today).thenAnswer((_) async => today ?? Date(2026, 4, 20));
    }

    container = ProviderContainer(
      overrides: <Override>[
        onboardingFlowControllerProvider.overrideWith(_SettledFlow.new),
        meRepositoryProvider.overrideWithValue(meRepo),
        serverTodayRepositoryProvider.overrideWithValue(todayRepo),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepo),
      ],
    );
    addTearDown(container.dispose);

    // Both providers are autoDispose. A bare `read` disposes them as it
    // returns, so the deferred load would find `ref.mounted == false` and
    // resolve nothing; a subscription is what a screen's `ref.watch` does.
    container.listen(baselineControllerProvider, (_, _) {});
    container.listen(onboardingFlowControllerProvider, (_, _) {});
  }

  final _MockMeRepository meRepo;
  final _MockServerTodayRepository todayRepo;
  final _MockOnboardingRepository onboardingRepo;
  late final ProviderContainer container;

  BaselineController get notifier =>
      container.read(baselineControllerProvider.notifier);

  AsyncValue<BaselineForm> get state =>
      container.read(baselineControllerProvider);

  BaselineForm get form => state.value!;

  OnboardingStep get step =>
      container.read(onboardingFlowControllerProvider).value!.step;

  /// Lets the deferred load run to completion.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

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

  void rejectSave(Object error) {
    when(
      () => onboardingRepo.saveBaseline(
        dob: any(named: 'dob'),
        heightCm: any(named: 'heightCm'),
        weightKg: any(named: 'weightKg'),
        endoStatus: any(named: 'endoStatus'),
      ),
    ).thenAnswer((_) async => throw error);
  }

  void pendSave(Completer<BaselineResponse> release) {
    when(
      () => onboardingRepo.saveBaseline(
        dob: any(named: 'dob'),
        heightCm: any(named: 'heightCm'),
        weightKg: any(named: 'weightKg'),
        endoStatus: any(named: 'endoStatus'),
      ),
    ).thenAnswer((_) => release.future);
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
}

void main() {
  // -------------------------------------------------------------------------
  // The vocabulary
  // -------------------------------------------------------------------------

  group('EndoStatus', () {
    test('it carries the three ratified codes and the mockup\'s labels', () {
      // Codes: `UserProfileEnc.EndoStatuses` (UserProfileEnc.cs:68-75).
      expect(EndoStatus.values.map((s) => s.wireName).toList(), <String>[
        'diagnosed',
        'suspected',
        'not_applicable',
      ]);
      // Labels: `Screens/screen_04_baseline.html`, the three `.opt` rows.
      expect(EndoStatus.values.map((s) => s.label).toList(), <String>[
        'Diagnosed',
        'Suspected, undiagnosed',
        'Not applicable',
      ]);
    });

    test('it matches a wire code exactly, and nothing else', () {
      // The server compares with StringComparer.Ordinal and answers 400 for
      // anything else, so a client that normalised case would send a value it
      // believed was valid.
      expect(EndoStatus.fromWireName('not_applicable'), EndoStatus.notApplicable);
      expect(EndoStatus.fromWireName('Not_Applicable'), isNull);
      expect(EndoStatus.fromWireName('notApplicable'), isNull);
      expect(EndoStatus.fromWireName(null), isNull);
      // A code this build has never seen reads as "no answer" rather than
      // being coerced onto a member: the vocabulary is append-only.
      expect(EndoStatus.fromWireName('surgically_confirmed'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // The resume
  // -------------------------------------------------------------------------

  group('the resume read', () {
    test('it prefills from GET /me and treats what it read as SAVED', () async {
      final world = _World(
        profile: meResponseFixture(
          dob: Date(1996, 4, 6),
          heightCm: 165,
          latestWeightKg: 62.4,
          endoStatus: 'diagnosed',
        ),
      );
      await world.settle();

      expect(world.form.answers.dob, Date(1996, 4, 6));
      expect(world.form.answers.heightCm, 165);
      expect(world.form.answers.weightKg, 62.4);
      expect(world.form.answers.endoStatus, EndoStatus.diagnosed);

      // The half that matters on a MERGE endpoint: what was READ must not be
      // re-asserted as a WRITE. `saved` is what stops a returning user's
      // untouched Continue from posting the values back.
      expect(world.form.saved, world.form.answers);
      expect(world.form.hasUnsentAnswers, isFalse);
    });

    test('a stored diagnosis month does not break the prefill', () async {
      // §C.0.2: `diagnosedOn` is a `String?` of exact form `yyyy-MM`, NOT a
      // `Date?` — the generated `DateSerializer` calls `DateTime.parse`, which
      // THROWS on "2026-08". Screen 4 draws no control for it, so the only way
      // it can reach this controller is on the prefill; anything here that
      // parsed it as a date would take the whole screen down.
      final world = _World(
        profile: meResponseFixture(
          diagnosedOn: '2026-08',
          heightCm: 165,
          rasrmStage: 3,
        ),
      );
      await world.settle();

      // The positive control, in the same test: the OTHER stored values did
      // arrive, so this is a fact about surviving the month string rather than
      // about a controller that read nothing at all.
      expect(world.form.answers.heightCm, 165);
      expect(world.state.hasError, isFalse);
    });

    test('an unanswered status stays null — and not_applicable is an ANSWER',
        () async {
      final blank = _World();
      await blank.settle();
      expect(
        blank.form.answers.endoStatus,
        isNull,
        reason: 'there is no default: an unanswered question stays null',
      );

      // The control that makes the null above mean something: the same
      // controller reading a stored `not_applicable` shows a real answer, not
      // an absence.
      final answered = _World(
        profile: meResponseFixture(endoStatus: 'not_applicable'),
      );
      await answered.settle();
      expect(answered.form.answers.endoStatus, EndoStatus.notApplicable);
    });

    test('a failed profile read leaves every answer unknown, and says so',
        () async {
      final world = _World(profileFailure: const NetworkFailure());
      await world.settle();

      // Nothing is invented. Drawing a default here is exactly what would
      // overwrite a stored answer on the next save.
      expect(world.form.answers.heightCm, isNull);
      expect(world.form.answers.weightKg, isNull);
      expect(world.form.answers.endoStatus, isNull);
      expect(world.form.failure, isA<NetworkFailure>());
      // …and the step is still usable, because skipping it must work offline.
      expect(world.state.hasError, isFalse);
    });

    test('a stale profile is used exactly as a fresh one', () async {
      final world = _World();
      when(world.meRepo.getMe).thenAnswer(
        (_) async => Stale<MeResponse>(meResponseFixture(heightCm: 170)),
      );
      // The container was built in the constructor, so re-arm and rebuild.
      world.container.invalidate(baselineControllerProvider);
      await world.settle();

      expect(world.form.answers.heightCm, 170);
    });
  });

  // -------------------------------------------------------------------------
  // Today, and the one bound on the date of birth
  // -------------------------------------------------------------------------

  group('the date of birth', () {
    test('today is choosable; tomorrow is not', () async {
      final world = _World(today: Date(2026, 4, 20));
      await world.settle();

      // The ACCEPTING boundary: the server rejects only `dob > today`
      // (OnboardingStepsService.cs:172-173), so today itself is a real answer.
      world.notifier.chooseDob(Date(2026, 4, 20));
      expect(world.form.answers.dob, Date(2026, 4, 20));

      // The rejecting one, in the same test so the pair discriminates.
      world.notifier.chooseDob(Date(2026, 4, 21));
      expect(world.form.answers.dob, Date(2026, 4, 20));
    });

    test('there is no lower bound of any kind — C-12 forbids an age gate',
        () async {
      final world = _World(today: Date(2026, 4, 20));
      await world.settle();

      // A date of birth that would make the user sixteen days old, and one
      // that would make her a hundred and twenty. Neither is refused here, and
      // neither is refused by the server: the population is a DESIGN TARGET,
      // not a data-entry gate, and a "born before 19xx" floor would be an age
      // gate under another name.
      world.notifier.chooseDob(Date(2026, 4, 4));
      expect(world.form.answers.dob, Date(2026, 4, 4));

      world.notifier.chooseDob(Date(1906, 1, 1));
      expect(world.form.answers.dob, Date(1906, 1, 1));
    });

    test('with no today there is no picker, and no guess', () async {
      final world = _World(todayFailure: const NetworkFailure());
      await world.settle();

      // D-12: the one thing left to derive a bound from is the device clock.
      expect(world.form.today, isNull);
      expect(world.form.canPickDob, isFalse);
      world.notifier.chooseDob(Date(1996, 4, 6));
      expect(world.form.answers.dob, isNull);

      // The control: with a today the same control is open.
      final ok = _World(today: Date(2026, 4, 20));
      await ok.settle();
      expect(ok.form.canPickDob, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Continue — the skip path, and the diff
  // -------------------------------------------------------------------------

  group('submit', () {
    test('with nothing answered it issues NO request and walks on', () async {
      final world = _World()..answerSave();
      await world.settle();

      await world.notifier.submit();

      // THE test of this task. D-02 makes the step skippable and this endpoint
      // 400s an empty body, so a "skip" that posted would be a client bug that
      // shows the user an error for doing nothing wrong.
      world.verifyNoSave();
      expect(world.step, OnboardingStep.goals);
    });

    test('with one answer it DOES post — the control for the skip path',
        () async {
      final world = _World()..answerSave();
      await world.settle();

      world.notifier.chooseEndoStatus(EndoStatus.notApplicable);
      await world.notifier.submit();

      final captured = world.verifySaves()..called(1);
      expect(captured.captured, <Object?>[null, null, null, 'not_applicable']);
      expect(world.step, OnboardingStep.goals);
    });

    test('a resume the user did not touch walks on without re-posting',
        () async {
      final world = _World(
        profile: meResponseFixture(heightCm: 165, endoStatus: 'diagnosed'),
      )..answerSave();
      await world.settle();

      await world.notifier.submit();

      // Re-asserting a READ as a WRITE is the failure mode `saved` exists to
      // prevent — the profile read is stale-while-revalidate, so the 165 on
      // screen can be a cache entry served after a failed refresh while screen
      // 31 on another device set 170.
      world.verifyNoSave();
      expect(world.step, OnboardingStep.goals);
    });

    test('it sends the fields that CHANGED and omits the ones that did not',
        () async {
      final world = _World(
        profile: meResponseFixture(
          heightCm: 165,
          latestWeightKg: 62.4,
          endoStatus: 'diagnosed',
        ),
      )..answerSave();
      await world.settle();

      world.notifier.setWeightKg(63.1);
      await world.notifier.submit();

      final captured = world.verifySaves()..called(1);
      // The weight, and nothing else. An omitted field is left unchanged by the
      // endpoint's MERGE; echoing the unchanged 165 back would re-assert as a
      // write something this device only ever observed as a read.
      expect(captured.captured, <Object?>[null, null, 63.1, null]);
    });

    test('clearing a field sends nothing for it — a merge cannot clear',
        () async {
      final world = _World(profile: meResponseFixture(heightCm: 165))
        ..answerSave();
      await world.settle();

      world.notifier.setHeightCm(null);
      expect(world.form.answers.heightCm, isNull);

      await world.notifier.submit();

      // §C.0.1's accepted cost: `int?` cannot distinguish absent from
      // explicit-null under System.Text.Json and `built_value` omits nulls, so
      // there is no way to CLEAR a stored baseline field from this client. The
      // honest behaviour is to send nothing rather than to post an empty body
      // that would 400.
      world.verifyNoSave();
      expect(world.step, OnboardingStep.goals);

      // The control: a field CHANGED rather than cleared does travel.
      final changed = _World(profile: meResponseFixture(heightCm: 165))
        ..answerSave();
      await changed.settle();
      changed.notifier.setHeightCm(170);
      await changed.notifier.submit();
      expect((changed.verifySaves()..called(1)).captured[1], 170);
    });

    test('a rejection keeps the user on the step and reports itself', () async {
      final world = _World()
        ..rejectSave(
          const ValidationFailure(
            message: 'The request contained invalid data.',
            fields: <String, List<String>>{
              'weightKg': <String>['value must have at most 1 decimal place'],
            },
          ),
        );
      await world.settle();

      world.notifier.setWeightKg(60.35);
      await world.notifier.submit();

      expect(world.form.failure, isA<ValidationFailure>());
      expect(world.form.submitting, isFalse);
      expect(
        world.step,
        OnboardingStep.baseline,
        reason: 'a rejected answer must not be walked past',
      );
    });

    test('an untyped error is reported rather than escaping as a dead spinner',
        () async {
      // `cachedWrite` invalidates its keys UNGUARDED after a successful write,
      // so a concurrent logout purge closing the Hive box throws here — after
      // the answer was stored. Left unhandled it is a spinner that never stops.
      final world = _World()..rejectSave(StateError('box is closed'));
      await world.settle();

      world.notifier.setHeightCm(165);
      await world.notifier.submit();

      expect(world.form.failure, isA<UnknownFailure>());
      expect(world.form.submitting, isFalse);
      expect(world.step, OnboardingStep.baseline);
    });

    test('a second press while a save is in flight issues no second request',
        () async {
      final release = Completer<BaselineResponse>();
      final world = _World()..pendSave(release);
      await world.settle();

      world.notifier.setHeightCm(165);
      unawaited(world.notifier.submit());
      await world.settle();
      expect(world.form.submitting, isTrue);

      unawaited(world.notifier.submit());
      await world.settle();

      world.verifySaves().called(1);

      release.complete(baselineFixture(heightCm: 165));
      await world.settle();
      expect(world.step, OnboardingStep.goals);
    });

    test('an action on an unsettled controller is a no-op', () async {
      // The controller-shape rule's other half: `build()` is synchronous and
      // the load runs in a microtask, so there IS a window in which the form
      // does not exist yet. Every action must survive it.
      final gate = Completer<CacheResult<MeResponse>>();
      final world = _World(profileGate: gate)..answerSave();

      expect(world.state.value, isNull, reason: 'premise: not settled yet');
      world.notifier.setHeightCm(165);
      world.notifier.chooseEndoStatus(EndoStatus.diagnosed);
      await world.notifier.submit();
      world.verifyNoSave();
      expect(world.step, OnboardingStep.baseline);

      // The control: the same calls on the settled controller do apply.
      gate.complete(Fresh<MeResponse>(meResponseFixture()));
      await world.settle();
      world.notifier.setHeightCm(165);
      expect(world.form.answers.heightCm, 165);
    });

    test('a successful save adopts what the server re-read', () async {
      final world = _World()
        ..answerSave(baselineFixture(heightCm: 165, latestWeightKg: 62.4));
      await world.settle();

      world.notifier.setHeightCm(165);
      await world.notifier.submit();

      // The response is the server's RE-READ of the stored row, not an echo of
      // the request, so it is what the client should believe is stored — the
      // weight included, which this save never sent.
      expect(world.form.saved.heightCm, 165);
      expect(world.form.saved.weightKg, 62.4);
      expect(world.form.hasUnsentAnswers, isFalse);
    });
  });
}
