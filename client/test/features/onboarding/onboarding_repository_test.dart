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
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
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
}
