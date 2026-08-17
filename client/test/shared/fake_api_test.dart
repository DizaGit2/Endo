// Tests for the shared fake-API archetypes (P4b-T3).
//
// The four archetypes are the input to every P4b screen's error/retry state,
// so they are worth proving BEFORE thirteen tasks build on them. Each is
// checked end-to-end through the production `mapDioException`, because what a
// screen actually sees is the typed [Failure], not the DioException.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/error/error_mapper.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:mocktail/mocktail.dart';

import '../support/harness.dart';

/// Runs [answer] and returns the [Failure] the app would surface.
Future<Failure> _failureFrom(ApiAnswer<MeResponse> answer) async {
  try {
    await answer(Invocation.method(#meGet, const []));
    fail('Expected the archetype to throw.');
  } on DioException catch (e) {
    return mapDioException(e);
  }
}

void main() {
  group('apiSuccess', () {
    test('yields a 200 Response carrying the body', () async {
      final me = meResponseFixture(displayName: 'Ada');
      final response = await apiSuccess(me)(
        Invocation.method(#meGet, const []),
      );

      expect(response.statusCode, 200);
      expect(response.data?.displayName, 'Ada');
    });

    test('drives a mocktail-stubbed LumenApiApi end to end', () async {
      final api = MockLumenApiApi();
      when(() => api.meGet()).thenAnswer(apiSuccess(meResponseFixture()));

      final response = await api.meGet();

      expect(response.data?.id, 'user-abc123');
      verify(() => api.meGet()).called(1);
    });
  });

  group('apiNetworkFailure', () {
    test('maps to NetworkFailure — the screen\'s offline surface', () async {
      final failure = await _failureFrom(apiNetworkFailure<MeResponse>());
      expect(failure, isA<NetworkFailure>());
    });
  });

  group('apiValidationProblem', () {
    test('maps to ValidationFailure carrying the per-field errors', () async {
      final failure = await _failureFrom(
        apiValidationProblem<MeResponse>(
          detail: 'Display name is too long.',
          fields: const {
            'displayName': ['Must be 60 characters or fewer.'],
          },
        ),
      );

      expect(failure, isA<ValidationFailure>());
      final validation = failure as ValidationFailure;
      expect(validation.detail, 'Display name is too long.');
      expect(validation.fields['displayName'], [
        'Must be 60 characters or fewer.',
      ]);
    });

    test('is a REAL failure — cachedRead must not mask it as offline', () {
      // NetworkFailure/ServerFailure fall back to Stale/NetworkRequired;
      // everything else is rethrown. A validation problem must land in the
      // second group or a form screen silently shows stale data instead of the
      // field error.
      expect(const ValidationFailure(), isNot(isA<NetworkFailure>()));
      expect(const ValidationFailure(), isNot(isA<ServerFailure>()));
    });
  });

  group('apiPending', () {
    test('never completes', () async {
      final pending = apiPending<MeResponse>()(
        Invocation.method(#meGet, const []),
      );
      var completed = false;
      unawaited(pending.then((_) => completed = true));

      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
    });

    test('completes when the test releases it', () async {
      final release = Completer<Response<MeResponse>>();
      final pending = apiPending<MeResponse>(release: release)(
        Invocation.method(#meGet, const []),
      );

      release.complete(
        Response<MeResponse>(
          requestOptions: RequestOptions(path: '/me'),
          statusCode: 200,
          data: meResponseFixture(),
        ),
      );

      expect((await pending).statusCode, 200);
    });
  });

  group('apiScript', () {
    test('answers in order, then repeats the last answer', () async {
      final log = ApiCallLog();
      final api = MockLumenApiApi();
      when(() => api.meGet()).thenAnswer(
        apiScript([
          apiNetworkFailure<MeResponse>(),
          apiSuccess(meResponseFixture(id: 'second')),
        ], log: log),
      );

      await expectLater(api.meGet(), throwsA(isA<DioException>()));
      expect((await api.meGet()).data?.id, 'second');
      // Exhausted — the last answer repeats rather than throwing a range error.
      expect((await api.meGet()).data?.id, 'second');
      expect(log.calls, 3);
    });

    test('rejects an empty script rather than failing later', () {
      expect(() => apiScript<MeResponse>([]), throwsArgumentError);
    });
  });
}
