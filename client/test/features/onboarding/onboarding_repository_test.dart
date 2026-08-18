// OnboardingRepository — the resume read and the completion write (P4b-T8).
//
// Two endpoints, and the interesting behaviour is almost entirely at their
// edges:
//
//   * `GET /onboarding/state` is a stale-while-revalidate read filed under the
//     ONE key policy (`CacheKeys.onboardingState`), so a write elsewhere can
//     name it. It must survive a round trip through the cache without dropping
//     `lastPeriodStart` — screen 3's prefill is the only place that date comes
//     from on a resume.
//   * `POST /onboarding/complete` flips `MeResponse.onboardingCompleted`, so it
//     invalidates the PROFILE key as well as its own; and its 409 carries the
//     `code` / `missingSteps` extensions that tell the shell which step still
//     owes an answer. Those must arrive as a typed `ConflictFailure` — no
//     caller may read `DioException.response.data`.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/baseline_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/api/model/save_baseline_request.dart';
import 'package:lumen/api/model/save_onboarding_cycle_request.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// The exact strings this repository must file its reads and invalidations
/// under, written out rather than read back from [CacheKeys].
///
/// Comparing the repository's key to `CacheKeys.onboardingState` would pass for
/// any pair of values as long as both sides moved together — including the
/// wrong one. The literal is the only spelling a `POST /checkin/quick` in T18
/// can be checked against.
const _stateKey = 'GET:/onboarding/state';
const _profileKey = 'GET:/me';
const _cycleSettingsKey = 'GET:/settings/cycle';

/// A 409 shaped exactly like the `POST /onboarding/cycle` conflict on the wire
/// (`OnboardingStepResult.cs`): a DIFFERENT code from the completion's, and it
/// means the opposite thing.
DioException _alreadyCompleted409() {
  final options = RequestOptions(path: '/onboarding/cycle');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 409,
      data: <String, dynamic>{
        'title': 'The request conflicts with the current onboarding state.',
        'status': 409,
        'detail':
            'Onboarding is already complete; the cycle anchor can no longer '
            'be moved here.',
        'code': 'onboarding_already_completed',
      },
    ),
  );
}

/// The request the repository actually put on the wire.
SaveOnboardingCycleRequest _capturedCycleRequest(MockLumenApiApi api) {
  return verify(
        () => api.onboardingCyclePost(
          saveOnboardingCycleRequest: captureAny(
            named: 'saveOnboardingCycleRequest',
          ),
        ),
      ).captured.last
      as SaveOnboardingCycleRequest;
}

/// The baseline request the repository actually put on the wire.
SaveBaselineRequest _capturedBaselineRequest(MockLumenApiApi api) {
  return verify(
        () => api.onboardingBaselinePost(
          saveBaselineRequest: captureAny(named: 'saveBaselineRequest'),
        ),
      ).captured.last
      as SaveBaselineRequest;
}

/// A 409 shaped exactly like `OnboardingConflict.Incomplete` on the wire.
DioException _incomplete409({
  String code = 'onboarding_incomplete',
  List<String> missingSteps = const ['cycle'],
}) {
  final options = RequestOptions(path: '/onboarding/complete');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 409,
      data: <String, dynamic>{
        'title': 'The request conflicts with the current onboarding state.',
        'status': 409,
        'detail':
            'Onboarding cannot be completed until every mandatory step is '
            'answered.',
        'code': code,
        'missingSteps': missingSteps,
      },
    ),
  );
}

void main() {
  late MockLumenApiApi api;
  late MockCacheStore store;
  late OnboardingRepository repo;

  setUp(() {
    api = MockLumenApiApi();
    store = emptyCacheStore();
    repo = OnboardingRepository(api: api, store: store);
  });

  // -------------------------------------------------------------------------
  // GET /onboarding/state
  // -------------------------------------------------------------------------

  group('getState', () {
    test(
      'fetches the state and files it under the shared key and TTL',
      () async {
        when(
          api.onboardingStateGet,
        ).thenAnswer(apiSuccess(onboardingStateFixture(cycleProvided: true)));

        final result = await repo.getState();

        expect(result, isA<Fresh<OnboardingStateResponse>>());
        expect(
          (result as Fresh<OnboardingStateResponse>).value.cycleProvided,
          isTrue,
        );
        verify(
          () => store.putJson(_stateKey, any(), ttl: CacheKeys.ttl),
        ).called(1);
      },
    );

    test('serves a fresh cache entry without touching the network', () async {
      // The positive control is the second half: the SAME api mock, in the SAME
      // test, must be shown to answer when it is asked. Without it,
      // `verifyNever` here is satisfied by a mock nobody ever wired up.
      when(() => store.isFresh(_stateKey)).thenReturn(true);
      when(() => store.getJson(_stateKey)).thenReturn(<String, dynamic>{
        'cycleProvided': true,
        'completed': false,
      });
      when(
        api.onboardingStateGet,
      ).thenAnswer(apiSuccess(onboardingStateFixture()));

      final cached = await repo.getState();

      expect(cached, isA<Fresh<OnboardingStateResponse>>());
      expect(
        (cached as Fresh<OnboardingStateResponse>).value.cycleProvided,
        isTrue,
      );
      verifyNever(api.onboardingStateGet);

      // Positive control: the same mock DOES answer once the entry goes stale,
      // so the `verifyNever` above is a fact about the short-circuit rather
      // than about an unwired mock.
      when(() => store.isFresh(_stateKey)).thenReturn(false);
      await repo.getState();
      verify(api.onboardingStateGet).called(1);
    });

    test(
      'a cached state keeps lastPeriodStart across the round trip',
      () async {
        // `Date` is the one non-primitive on this response, and screen 3's
        // resume prefill is the only consumer of it. A cache round trip that
        // dropped or mangled it would show an empty calendar to a user who has
        // already answered — and `Date` serialises through a custom serializer,
        // so this is not free.
        Map<String, dynamic>? written;
        when(
          () => store.putJson(any(), any(), ttl: any(named: 'ttl')),
        ).thenAnswer((invocation) async {
          written = invocation.positionalArguments[1] as Map<String, dynamic>;
        });
        when(api.onboardingStateGet).thenAnswer(
          apiSuccess(
            onboardingStateFixture(
              cycleProvided: true,
              lastPeriodStart: Date(2026, 4, 6),
            ),
          ),
        );

        await repo.getState();
        expect(written, isNotNull, reason: 'premise: the read wrote through');
        expect(written!['lastPeriodStart'], '2026-04-06');

        // Now read it back from the cache alone — no network — and require the
        // date to survive as a `Date`, not as a string the caller has to parse.
        when(() => store.isFresh(_stateKey)).thenReturn(true);
        when(() => store.getJson(_stateKey)).thenReturn(written);

        final cached = await repo.getState() as Fresh<OnboardingStateResponse>;

        expect(cached.value.lastPeriodStart, Date(2026, 4, 6));
      },
    );

    test(
      'falls back to a cached state when the network is unreachable',
      () async {
        when(() => store.getJson(_stateKey)).thenReturn(<String, dynamic>{
          'cycleProvided': true,
          'completed': false,
        });
        when(
          api.onboardingStateGet,
        ).thenAnswer(apiNetworkFailure<OnboardingStateResponse>());

        final result = await repo.getState();

        expect(result, isA<Stale<OnboardingStateResponse>>());
        expect(
          (result as Stale<OnboardingStateResponse>).value.cycleProvided,
          isTrue,
        );
      },
    );

    test(
      'reports NetworkRequired when there is no network and no cache',
      () async {
        when(
          api.onboardingStateGet,
        ).thenAnswer(apiNetworkFailure<OnboardingStateResponse>());

        final result = await repo.getState();

        expect(result, isA<NetworkRequired<OnboardingStateResponse>>());
        expect(
          (result as NetworkRequired<OnboardingStateResponse>).failure,
          isA<NetworkFailure>(),
        );
      },
    );

    test('a 200 with no body is a server failure, not a null state', () async {
      // `cachedRead` classifies a `ServerFailure` as transient, so with no
      // cached entry the caller sees `NetworkRequired` WRAPPING the typed
      // failure — never a null state and never a raw TypeError from a
      // force-unwrap. Both halves are asserted: the arm AND what it carries.
      when(api.onboardingStateGet).thenAnswer(
        (_) async => Response<OnboardingStateResponse>(
          requestOptions: RequestOptions(path: '/onboarding/state'),
          statusCode: 200,
        ),
      );

      final result = await repo.getState();

      expect(result, isA<NetworkRequired<OnboardingStateResponse>>());
      expect(
        (result as NetworkRequired<OnboardingStateResponse>).failure,
        isA<ServerFailure>(),
      );
      // The positive control for the line above: a genuinely offline read is
      // also `NetworkRequired`, and it carries a DIFFERENT failure. Asserting
      // the arm alone could not tell the two apart.
      when(
        api.onboardingStateGet,
      ).thenAnswer(apiNetworkFailure<OnboardingStateResponse>());
      final offline = await repo.getState();
      expect(
        (offline as NetworkRequired<OnboardingStateResponse>).failure,
        isA<NetworkFailure>(),
      );
    });
  });

  // -------------------------------------------------------------------------
  // POST /onboarding/complete
  // -------------------------------------------------------------------------

  group('complete', () {
    test('posts the completion and returns what the server stamped', () async {
      when(api.onboardingCompletePost).thenAnswer(
        apiSuccess(
          onboardingCompleteFixture(completedAt: DateTime.utc(2026, 4, 6, 9)),
        ),
      );

      final response = await repo.complete();

      expect(response.completedAt, DateTime.utc(2026, 4, 6, 9));
      expect(response.alreadyCompleted, isFalse);
      verify(api.onboardingCompletePost).called(1);
    });

    test('invalidates BOTH the onboarding state and the profile, because '
        'completion flips MeResponse.onboardingCompleted', () async {
      when(
        api.onboardingCompletePost,
      ).thenAnswer(apiSuccess(onboardingCompleteFixture()));

      await repo.complete();

      verify(() => store.invalidate(_stateKey)).called(1);
      verify(() => store.invalidate(_profileKey)).called(1);
    });

    test('a rejected completion invalidates nothing', () async {
      // The positive control is the first half. "No invalidation happened" is
      // also true of a store nobody ever calls, so the same store is first
      // shown recording two invalidations on a SUCCESSFUL completion; only then
      // is the failing one asserted to add none.
      when(
        api.onboardingCompletePost,
      ).thenAnswer(apiSuccess(onboardingCompleteFixture()));
      await repo.complete();
      verify(() => store.invalidate(any())).called(2);

      when(
        api.onboardingCompletePost,
      ).thenAnswer((_) async => throw _incomplete409());

      await expectLater(repo.complete(), throwsA(isA<ConflictFailure>()));

      verifyNever(() => store.invalidate(any()));
    });

    test('the 409 arrives as a typed ConflictFailure carrying its code and '
        'missing steps', () async {
      when(
        api.onboardingCompletePost,
      ).thenAnswer((_) async => throw _incomplete409());

      final failure = await repo.complete().then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );

      expect(failure, isA<ConflictFailure>());
      final conflict = failure! as ConflictFailure;
      expect(conflict.code, 'onboarding_incomplete');
      expect(conflict.missingSteps, ['cycle']);
      expect(
        conflict.message,
        'Onboarding cannot be completed until every mandatory step is answered.',
      );
    });

    test('a repeat completion is a success, not a conflict', () async {
      // The server answers a second `POST /onboarding/complete` with 200 and
      // the ORIGINAL timestamp. A client that treated `alreadyCompleted` as an
      // error would strand a user whose first response was lost in transit.
      when(api.onboardingCompletePost).thenAnswer(
        apiSuccess(
          onboardingCompleteFixture(
            alreadyCompleted: true,
            completedAt: DateTime.utc(2026, 4, 1, 8),
          ),
        ),
      );

      final response = await repo.complete();

      expect(response.alreadyCompleted, isTrue);
      expect(response.completedAt, DateTime.utc(2026, 4, 1, 8));
    });

    test('a 200 with no body is a server failure', () async {
      when(api.onboardingCompletePost).thenAnswer(
        (_) async => Response<OnboardingCompleteResponse>(
          requestOptions: RequestOptions(path: '/onboarding/complete'),
          statusCode: 200,
        ),
      );

      await expectLater(repo.complete(), throwsA(isA<ServerFailure>()));
      verifyNever(() => store.invalidate(any()));
    });
  });

  // -------------------------------------------------------------------------
  // POST /onboarding/cycle
  // -------------------------------------------------------------------------
  //
  // The endpoint is a MERGE on the three self-reports and `lastPeriodStart` is
  // required on every post (ARCHITECTURE.md §C.0.1). Screen 3 is where a user
  // comes back to fix a mistyped date, sending the anchor and NOTHING else —
  // assigning all three columns unconditionally is what silently reset the
  // user's own answers, and it is why the endpoint stopped doing that.

  group('saveCycle', () {
    // mocktail needs a real instance before `any(named:)` can match a
    // non-nullable argument of this type.
    setUpAll(
      () => registerFallbackValue(
        SaveOnboardingCycleRequest(
          (b) => b..lastPeriodStart = Date(2026, 1, 1),
        ),
      ),
    );

    void answerSave([OnboardingCycleResponse? body]) {
      when(
        () => api.onboardingCyclePost(
          saveOnboardingCycleRequest: any(named: 'saveOnboardingCycleRequest'),
        ),
      ).thenAnswer(apiSuccess(body ?? onboardingCycleFixture()));
    }

    test(
      'it sends the anchor every time and only the answers it was given',
      () async {
        answerSave();

        await repo.saveCycle(lastPeriodStart: Date(2026, 4, 6));

        final anchorOnly = _capturedCycleRequest(api);
        expect(anchorOnly.lastPeriodStart, Date(2026, 4, 6));
        expect(anchorOnly.avgCycleLengthDays, isNull);
        expect(anchorOnly.regularity, isNull);
        // Never collected on screen 3, and there is no way to clear it back to
        // null on any P4a surface — so it is not a parameter and never a key.
        expect(anchorOnly.avgPeriodLengthDays, isNull);

        // The positive control, and the whole point of this test: those three
        // nulls are also what a builder that sets NOTHING produces. The same
        // repository, called with the two answers, must carry them.
        await repo.saveCycle(
          lastPeriodStart: Date(2026, 4, 6),
          avgCycleLengthDays: 29,
          regularity: 'irregular',
        );

        final full = _capturedCycleRequest(api);
        expect(full.avgCycleLengthDays, 29);
        expect(full.regularity, 'irregular');
        expect(full.avgPeriodLengthDays, isNull);
      },
    );

    test('it invalidates the onboarding state, the cycle settings and the '
        "anchor's own day", () async {
      answerSave();

      await repo.saveCycle(lastPeriodStart: Date(2026, 4, 6));

      final keys = verify(() => store.invalidate(captureAny())).captured;
      expect(keys, contains(_stateKey));
      expect(keys, contains(_cycleSettingsKey));
      // One POST writes two tables: `user_cycle_settings` AND the
      // `cycle_events.period_start` anchor. The dated keys come from the one
      // policy that can name every key a date appears in.
      expect(keys, contains('GET:/cycle/day/2026-04-06'));
      expect(keys, contains('GET:/symptoms?day=2026-04-06'));
      expect(keys, contains('GET:/cycle/calendar?month=2026-04'));
      // Not the profile: this endpoint does not stamp
      // `onboarding_completed_at`, and a client that invalidated `/me` here
      // would re-read it on every correction of a mistyped date.
      expect(keys, isNot(contains(_profileKey)));
    });

    test(
      'correcting the date invalidates the day the anchor LEFT as well',
      () async {
        answerSave();

        await repo.saveCycle(
          lastPeriodStart: Date(2026, 4, 6),
          previousLastPeriodStart: Date(2026, 3, 9),
        );

        final moved = verify(() => store.invalidate(captureAny())).captured;
        // The server MOVES the onboarding seed rather than adding a second one
        // (`StageOnboardingAnchorAsync`, case 2), so the old day loses a
        // `period_start` it used to have. Invalidating only the new day leaves a
        // cached March calendar drawing an anchor that is no longer there.
        expect(moved, contains('GET:/cycle/calendar?month=2026-03'));
        expect(moved, contains('GET:/cycle/day/2026-03-09'));

        // Positive control: the March keys are absent when the anchor did NOT
        // move, so the two assertions above are about the move rather than about
        // a repository that invalidates every month it can think of.
        await repo.saveCycle(
          lastPeriodStart: Date(2026, 4, 6),
          previousLastPeriodStart: Date(2026, 4, 6),
        );
        final unmoved = verify(() => store.invalidate(captureAny())).captured;
        expect(unmoved, isNot(contains('GET:/cycle/calendar?month=2026-03')));
        expect(unmoved, contains('GET:/cycle/calendar?month=2026-04'));
      },
    );

    test('a rejected save invalidates nothing', () async {
      answerSave();
      await repo.saveCycle(lastPeriodStart: Date(2026, 4, 6));
      final afterSuccess = verify(
        () => store.invalidate(captureAny()),
      ).captured;
      // The control: this store DOES record invalidations, so the emptiness
      // below is a fact about the rejection rather than about a mock nobody
      // wired.
      expect(afterSuccess, isNotEmpty);

      when(
        () => api.onboardingCyclePost(
          saveOnboardingCycleRequest: any(named: 'saveOnboardingCycleRequest'),
        ),
      ).thenAnswer(apiNetworkFailure<OnboardingCycleResponse>());

      await expectLater(
        repo.saveCycle(lastPeriodStart: Date(2026, 4, 6)),
        throwsA(isA<NetworkFailure>()),
      );
      verifyNever(() => store.invalidate(any()));
    });

    test('it returns the resolved values the server echoed', () async {
      answerSave(
        onboardingCycleFixture(
          lastPeriodStart: Date(2026, 4, 6),
          avgCycleLengthDays: 28,
          regularity: 'somewhat',
        ),
      );

      // Sent nothing but the anchor; the response still names the 28 and the
      // `somewhat` the server applied, which is what lets screen 3 show a user
      // a value they never typed.
      final response = await repo.saveCycle(lastPeriodStart: Date(2026, 4, 6));

      expect(response.avgCycleLengthDays, 28);
      expect(response.regularity, 'somewhat');
      expect(response.warnings, isEmpty);
    });

    test('the sanity warnings arrive alongside a SUCCESSFUL save', () async {
      answerSave(
        onboardingCycleFixture(
          avgCycleLengthDays: 400,
          warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
        ),
      );

      // The value was STORED and the call did not throw: the band is a hint,
      // never a rejection. Both halves are asserted — a save that threw would
      // also fail to return a bad value.
      final response = await repo.saveCycle(
        lastPeriodStart: Date(2026, 4, 6),
        avgCycleLengthDays: 400,
      );

      expect(response.avgCycleLengthDays, 400);
      expect(response.warnings, <String>[
        'avg_cycle_length_out_of_sanity_band',
      ]);
    });

    test('a 400 arrives as a ValidationFailure that names the field', () async {
      when(
        () => api.onboardingCyclePost(
          saveOnboardingCycleRequest: any(named: 'saveOnboardingCycleRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem<OnboardingCycleResponse>(
          fields: <String, List<String>>{
            'lastPeriodStart': <String>[
              'date is before the earliest allowed date',
            ],
          },
        ),
      );

      // The backdate floor is `users.created_at - 2 years` and NO endpoint
      // returns `created_at`, so the client cannot pre-validate it. The whole
      // mirror is this: carry the server's own message back to its own field.
      final failure = await repo
          .saveCycle(lastPeriodStart: Date(2020, 1, 1))
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(failure, isA<ValidationFailure>());
      expect(
        (failure as ValidationFailure).messageFor('lastPeriodStart'),
        'date is before the earliest allowed date',
      );
      // …and it names only the field the server named.
      expect(failure.messageFor('avgCycleLengthDays'), isNull);
    });

    test(
      'the post-completion 409 arrives as a typed ConflictFailure',
      () async {
        when(
          () => api.onboardingCyclePost(
            saveOnboardingCycleRequest: any(
              named: 'saveOnboardingCycleRequest',
            ),
          ),
        ).thenThrow(_alreadyCompleted409());

        final failure = await repo
            .saveCycle(lastPeriodStart: Date(2026, 4, 6))
            .then<Object?>((_) => null, onError: (Object e) => e);

        expect(failure, isA<ConflictFailure>());
        // `onboarding_already_completed`, NOT `onboarding_incomplete`: the two
        // codes live on the same surface and mean opposite things.
        expect(
          (failure as ConflictFailure).code,
          'onboarding_already_completed',
        );
        expect(failure.message, contains('can no longer be moved'));
      },
    );

    test('a 200 with no body is a server failure', () async {
      when(
        () => api.onboardingCyclePost(
          saveOnboardingCycleRequest: any(named: 'saveOnboardingCycleRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<OnboardingCycleResponse>(
          requestOptions: RequestOptions(path: '/onboarding/cycle'),
          statusCode: 200,
        ),
      );

      await expectLater(
        repo.saveCycle(lastPeriodStart: Date(2026, 4, 6)),
        throwsA(isA<ServerFailure>()),
      );
      verifyNever(() => store.invalidate(any()));
    });
  });

  // -------------------------------------------------------------------------
  // POST /onboarding/baseline (P4b-T10)
  // -------------------------------------------------------------------------

  group('saveBaseline', () {
    setUpAll(
      () => registerFallbackValue(SaveBaselineRequest((b) => b..heightCm = 1)),
    );

    void answerSave([BaselineResponse? body]) {
      when(
        () => api.onboardingBaselinePost(
          saveBaselineRequest: any(named: 'saveBaselineRequest'),
        ),
      ).thenAnswer(apiSuccess(body ?? baselineFixture()));
    }

    test('it sends only the fields it was given — an omitted one is absent, '
        'never a default', () async {
      answerSave();

      await repo.saveBaseline(heightCm: 165);

      final one = _capturedBaselineRequest(api);
      expect(one.heightCm, 165);
      expect(one.dob, isNull);
      expect(one.weightKg, isNull);
      expect(one.endoStatus, isNull);
      // Neither has a control on screen 4 (the mockup draws none), so neither
      // is a parameter — a dead one would invite a caller to believe it was
      // persisted.
      expect(one.rasrmStage, isNull);
      expect(one.diagnosedOn, isNull);

      // The positive control, and the whole point: those nulls are also what a
      // builder that sets NOTHING produces. The same repository, called with
      // the other three, must carry them.
      await repo.saveBaseline(
        dob: Date(1996, 4, 6),
        weightKg: 62,
        endoStatus: 'diagnosed',
      );

      final rest = _capturedBaselineRequest(api);
      expect(rest.dob, Date(1996, 4, 6));
      expect(rest.weightKg, 62);
      expect(rest.endoStatus, 'diagnosed');
      expect(rest.heightCm, isNull);
    });

    test('the weight is rounded to ONE decimal before it is serialised',
        () async {
      answerSave();

      // The case §C.0.2 names: a computed kilogram — an lbs conversion, a
      // slider step — does not land on a tenth, and the backend REJECTS extra
      // precision rather than rounding it (OnboardingStepsService.cs:192-197).
      await repo.saveBaseline(weightKg: 0.1 + 0.2);
      expect(_capturedBaselineRequest(api).weightKg, 0.3);

      await repo.saveBaseline(weightKg: 60.35);
      expect(_capturedBaselineRequest(api).weightKg, 60.4);

      // The control: rounding must not move a value that is already storable.
      // Without it the two rows above pass for a repository that rounded to
      // the nearest whole kilogram.
      await repo.saveBaseline(weightKg: 60.4);
      expect(_capturedBaselineRequest(api).weightKg, 60.4);
    });

    test('a body carrying none of the fields never reaches the wire',
        () async {
      answerSave();

      // The 400 unique to this endpoint (`provide at least one baseline
      // field`, OnboardingStepResult.cs:332) exists because D-02's skip means
      // NOT calling the endpoint. An empty body is therefore a client bug, and
      // this is the last place it can be stopped.
      expect(repo.saveBaseline, throwsA(isA<ArgumentError>()));
      verifyNever(
        () => api.onboardingBaselinePost(
          saveBaselineRequest: any(named: 'saveBaselineRequest'),
        ),
      );

      // Control: one supplied field is enough, and the same call then posts.
      await repo.saveBaseline(endoStatus: 'not_applicable');
      verify(
        () => api.onboardingBaselinePost(
          saveBaselineRequest: any(named: 'saveBaselineRequest'),
        ),
      ).called(1);
    });

    test('it invalidates the profile and the onboarding state', () async {
      answerSave();

      await repo.saveBaseline(heightCm: 165);

      final keys = verify(() => store.invalidate(captureAny())).captured;
      // `GET /me` splices this very projection into `MeResponse`, so a cached
      // profile is wrong the moment this returns.
      expect(keys, contains(_profileKey));
      // `baselineProvided` moves.
      expect(keys, contains(_stateKey));
      // Not the cycle settings: this endpoint writes neither
      // `user_cycle_settings` nor `cycle_events`.
      expect(keys, isNot(contains(_cycleSettingsKey)));
    });

    test('a 400 arrives as a ValidationFailure keyed by wire field name',
        () async {
      when(
        () => api.onboardingBaselinePost(
          saveBaselineRequest: any(named: 'saveBaselineRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem<BaselineResponse>(
          path: '/onboarding/baseline',
          fields: const <String, List<String>>{
            'weightKg': <String>['value must have at most 1 decimal place'],
          },
        ),
      );

      await expectLater(
        repo.saveBaseline(weightKg: 60.4),
        throwsA(
          isA<ValidationFailure>().having(
            (ValidationFailure f) => f.messageFor('weightKg'),
            'messageFor(weightKg)',
            'value must have at most 1 decimal place',
          ),
        ),
      );
      // Nothing was stored, so nothing cached is wrong.
      verifyNever(() => store.invalidate(any()));
    });

    test('an empty 200 body is a typed failure, not a force-unwrap', () async {
      when(
        () => api.onboardingBaselinePost(
          saveBaselineRequest: any(named: 'saveBaselineRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<BaselineResponse>(
          requestOptions: RequestOptions(path: '/onboarding/baseline'),
          statusCode: 200,
        ),
      );

      await expectLater(
        repo.saveBaseline(heightCm: 165),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}
