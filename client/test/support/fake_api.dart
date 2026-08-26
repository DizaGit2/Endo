// ---------------------------------------------------------------------------
// fake_api.dart — the four states every screen must have a design for (P4b-T3)
// ---------------------------------------------------------------------------
//
// P4b's exit criteria require each screen to have a DESIGNED error/retry state,
// not an accidental one. That is only testable if faking each state is cheap,
// so this file gives the four archetypes as mocktail *answers*:
//
//   [apiSuccess]           — 200 with a body.
//   [apiNetworkFailure]    — no connectivity -> NetworkFailure -> Stale /
//                            NetworkRequired, i.e. the offline surface.
//   [apiValidationProblem] — 400 problem+json with per-field `errors` ->
//                            ValidationFailure, i.e. the inline-field surface.
//   [apiPending]           — never answers, i.e. the loading surface (and the
//                            input a bounded-wait test needs).
//
// They are answers rather than whole fake classes because `LumenApiApi` has 27
// differently-typed methods; one archetype per method-shape would be 100+
// classes. The mocking style is unchanged from the pre-T3 tests — mocktail,
// `class Mock... extends Mock implements LumenApiApi` — deliberately: this
// repo has `http_mock_adapter` as an unused dev dependency and adding a second
// mocking idiom is how it got there.
//
//   final api = MockLumenApiApi();
//   when(() => api.meGet()).thenAnswer(apiSuccess(meResponseFixture()));
//   when(() => api.mePatch(updateMeRequest: any(named: 'updateMeRequest')))
//       .thenAnswer(apiValidationProblem(fields: {'displayName': ['Too long']}));

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:mocktail/mocktail.dart';

/// The one API mock type. Every test uses it; nobody declares a second.
class MockLumenApiApi extends Mock implements LumenApiApi {}

/// What `thenAnswer` wants for a generated `Future<Response<T>>` endpoint.
typedef ApiAnswer<T> = Future<Response<T>> Function(Invocation invocation);

// ---------------------------------------------------------------------------
// Call counting
// ---------------------------------------------------------------------------

/// Counts how many times an archetype answered.
///
/// `verify(...).called(n)` covers the simple case; this exists for the ones it
/// does not — a retry assertion that must compare counts BEFORE and AFTER a
/// tap (see `retry_trap.dart`), and any test that scripts a sequence.
class ApiCallLog {
  int calls = 0;

  /// Pass as `onCall:` — `apiSuccess(body, onCall: log.record)`.
  void record() => calls++;

  void reset() => calls = 0;
}

// ---------------------------------------------------------------------------
// The four archetypes
// ---------------------------------------------------------------------------

/// 200 (or [statusCode]) carrying [body].
ApiAnswer<T> apiSuccess<T>(
  T body, {
  int statusCode = 200,
  String path = '/',
  void Function()? onCall,
}) {
  return (_) async {
    onCall?.call();
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: statusCode,
      data: body,
    );
  };
}

/// No connectivity / the request never reached the server.
///
/// Maps through `mapDioException` to [NetworkFailure], which `cachedRead`
/// turns into `Stale` (cache hit) or `NetworkRequired` (cache miss) — the
/// screen's offline state. It is NOT an `AsyncError`, so a screen that only
/// designs an error body will render nothing useful here; that is the bug this
/// archetype exists to expose.
ApiAnswer<T> apiNetworkFailure<T>({
  String path = '/',
  void Function()? onCall,
}) {
  return (_) async {
    onCall?.call();
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.connectionError,
    );
  };
}

/// A 400 RFC 7807 `problem+json` response with per-field [fields].
///
/// Maps to `ValidationFailure`, which `cachedRead` deliberately RETHROWS
/// rather than masking as offline — so the screen sees a real error, and a
/// form screen is expected to surface [fields] against its inputs.
ApiAnswer<T> apiValidationProblem<T>({
  Map<String, List<String>> fields = const {},
  String detail = 'The request contained invalid data.',
  String title = 'One or more validation errors occurred.',
  int statusCode = 400,
  String path = '/',
  void Function()? onCall,
}) {
  return (_) async {
    onCall?.call();
    final options = RequestOptions(path: path);
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: statusCode,
        data: <String, dynamic>{
          'type': 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
          'title': title,
          'status': statusCode,
          'detail': detail,
          'errors': fields,
        },
      ),
    );
  };
}

/// Never answers.
///
/// The loading state, and the only honest way to test a bounded wait: pass
/// [release] to complete it from the test once the assertion about the
/// in-flight state has been made.
ApiAnswer<T> apiPending<T>({
  Completer<Response<T>>? release,
  void Function()? onCall,
}) {
  return (_) {
    onCall?.call();
    return (release ?? Completer<Response<T>>()).future;
  };
}

// ---------------------------------------------------------------------------
// Sequencing (not a fifth archetype — a composer over the four)
// ---------------------------------------------------------------------------

/// Answers with [answers] in order, repeating the last one once exhausted.
///
/// This is what a retry test needs: the first call fails, the second succeeds,
/// and the assertion is that the retry affordance is what moved it along.
///
/// ```dart
/// when(() => api.meGet()).thenAnswer(
///   apiScript([apiNetworkFailure<MeResponse>(), apiSuccess(meResponseFixture())]),
/// );
/// ```
ApiAnswer<T> apiScript<T>(List<ApiAnswer<T>> answers, {ApiCallLog? log}) {
  if (answers.isEmpty) {
    throw ArgumentError('apiScript needs at least one answer.');
  }
  var index = 0;
  return (invocation) {
    log?.record();
    final answer = answers[index < answers.length ? index : answers.length - 1];
    index++;
    return answer(invocation);
  };
}
