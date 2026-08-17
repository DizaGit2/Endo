import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/error/error_mapper.dart';
import 'package:lumen/core/error/failure.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DioException _dioError({
  required DioExceptionType type,
  int? statusCode,
  dynamic data,
}) {
  final options = RequestOptions(path: '/test');
  return DioException(
    requestOptions: options,
    type: type,
    response: statusCode != null
        ? Response(
            requestOptions: options,
            statusCode: statusCode,
            data: data,
          )
        : null,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('mapDioException', () {
    // -----------------------------------------------------------------------
    // Network failures
    // -----------------------------------------------------------------------

    test('connectionTimeout → NetworkFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.connectionTimeout),
      );
      expect(f, isA<NetworkFailure>());
    });

    test('sendTimeout → NetworkFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.sendTimeout),
      );
      expect(f, isA<NetworkFailure>());
    });

    test('receiveTimeout → NetworkFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.receiveTimeout),
      );
      expect(f, isA<NetworkFailure>());
    });

    test('connectionError → NetworkFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.connectionError),
      );
      expect(f, isA<NetworkFailure>());
    });

    // -----------------------------------------------------------------------
    // Auth failure
    // -----------------------------------------------------------------------

    test('401 → AuthFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.badResponse, statusCode: 401),
      );
      expect(f, isA<AuthFailure>());
    });

    // -----------------------------------------------------------------------
    // Not found
    // -----------------------------------------------------------------------

    test('404 → NotFoundFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.badResponse, statusCode: 404),
      );
      expect(f, isA<NotFoundFailure>());
    });

    // -----------------------------------------------------------------------
    // Conflict (409) — duplicate resource / state conflict
    // -----------------------------------------------------------------------

    test('409 → ConflictFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.badResponse, statusCode: 409),
      );
      expect(f, isA<ConflictFailure>());
    });

    test('409 with problem+json detail → ConflictFailure carries the detail',
        () {
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 409,
          data: {'detail': 'An account with that email already exists.'},
        ),
      );
      expect(f, isA<ConflictFailure>());
      expect(f.message, 'An account with that email already exists.');
    });

    test(
        '409 onboarding_incomplete → ConflictFailure lifts `code` and '
        '`missingSteps` off the problem-details extensions', () {
      // The exact body POST /onboarding/complete answers with when a mandatory
      // step is unanswered (survey/backend-endpoints.md, GET/POST onboarding).
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 409,
          data: {
            'type': 'https://tools.ietf.org/html/rfc9110#section-15.5.10',
            'title': 'The request conflicts with the current onboarding state.',
            'status': 409,
            'detail':
                'Onboarding cannot be completed until every mandatory step is answered.',
            'code': 'onboarding_incomplete',
            'missingSteps': ['cycle'],
          },
        ),
      ) as ConflictFailure;

      expect(f.code, 'onboarding_incomplete');
      expect(f.missingSteps, ['cycle']);
      expect(
        f.message,
        'Onboarding cannot be completed until every mandatory step is answered.',
      );
    });

    test('409 without extensions → null code and empty missingSteps', () {
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 409,
          data: {'detail': 'An account with that email already exists.'},
        ),
      ) as ConflictFailure;

      expect(f.code, isNull);
      expect(f.missingSteps, isEmpty);
    });

    test('409 with a malformed missingSteps extension degrades to empty', () {
      // A wire shape the client must not crash on: the list is not a list of
      // strings. Screen 7 gets "no steps named", not a TypeError.
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 409,
          data: {
            'detail': 'Conflict.',
            'code': 42, // not a string
            'missingSteps': {'cycle': true}, // not a list
          },
        ),
      ) as ConflictFailure;

      expect(f.code, isNull);
      expect(f.missingSteps, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Rate limit (429)
    // -----------------------------------------------------------------------

    test('429 → RateLimitFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.badResponse, statusCode: 429),
      );
      expect(f, isA<RateLimitFailure>());
    });

    // -----------------------------------------------------------------------
    // TLS / certificate validation — a HARD failure, never transient-offline
    // -----------------------------------------------------------------------

    test('badCertificate → TlsFailure (NOT NetworkFailure, so no stale cache)',
        () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.badCertificate),
      );
      expect(f, isA<TlsFailure>());
      expect(f, isNot(isA<NetworkFailure>()));
    });

    // -----------------------------------------------------------------------
    // Server errors
    // -----------------------------------------------------------------------

    test('500 → ServerFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.badResponse, statusCode: 500),
      );
      expect(f, isA<ServerFailure>());
    });

    test('503 → ServerFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.badResponse, statusCode: 503),
      );
      expect(f, isA<ServerFailure>());
    });

    // -----------------------------------------------------------------------
    // Validation failures — 400
    // -----------------------------------------------------------------------

    test('400 with no body → ValidationFailure with default message', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.badResponse, statusCode: 400),
      );
      expect(f, isA<ValidationFailure>());
    });

    test('400 with problem+json title → ValidationFailure carries title', () {
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 400,
          data: {'title': 'Validation error', 'detail': 'Name is required'},
        ),
      ) as ValidationFailure;
      expect(f, isA<ValidationFailure>());
      expect(f.detail, 'Name is required');
      expect(f.message, 'Name is required');
    });

    test('400 with problem+json errors map → ValidationFailure carries fields',
        () {
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 400,
          data: {
            'title': 'One or more validation errors occurred.',
            'detail': 'The request contained invalid data.',
            'errors': {
              'email': ['must be a valid email'],
              'name': ['must not be blank', 'too short'],
            },
          },
        ),
      ) as ValidationFailure;
      expect(f, isA<ValidationFailure>());
      expect(f.fields['email'], ['must be a valid email']);
      expect(f.fields['name'], ['must not be blank', 'too short']);
    });

    test('400 with no fields map → ValidationFailure with empty fields', () {
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 400,
          data: {'title': 'Bad input'},
        ),
      ) as ValidationFailure;
      expect(f.fields, isEmpty);
    });

    test(
        'the P4a 400 envelope keeps indexed error keys verbatim, so a batch row '
        'can bind its own message', () {
      // The exact body from survey/backend-endpoints.md §5.
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 400,
          data: {
            'type': 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
            'title': 'One or more validation errors occurred.',
            'status': 400,
            'detail': 'The request contained invalid data.',
            'errors': {
              'occurredOn': ['date must not be in the future'],
              'entries[3].intensity': ['value must be between 0 and 10'],
              'request': ['at least one of pain, mood or notes is required'],
            },
          },
        ),
      ) as ValidationFailure;

      expect(
        f.messageFor(ValidationFailure.path('entries', 3, 'intensity')),
        'value must be between 0 and 10',
      );
      expect(
        f.messageFor(ValidationFailure.path('entries', 4, 'intensity')),
        isNull,
        reason: 'the index must survive the mapper, not be collapsed away',
      );
      expect(f.requestMessages, ['at least one of pain, mood or notes is required']);
    });

    // -----------------------------------------------------------------------
    // 422 is NOT part of the shipped contract
    // -----------------------------------------------------------------------

    test('422 → UnknownFailure (P4a ships exactly one 400 validation envelope)',
        () {
      // Nothing in backend/src or backend/contract/openapi.json emits 422; the
      // branch that mapped it to ValidationFailure was dead code claiming a
      // status the server never sends.
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 422,
          data: {
            'title': 'Unprocessable entity',
            'errors': {
              'email': ['must be a valid email'],
            },
          },
        ),
      );
      expect(f, isNot(isA<ValidationFailure>()));
      expect(f, isA<UnknownFailure>());
    });

    // -----------------------------------------------------------------------
    // Unknown / cancel
    // -----------------------------------------------------------------------

    test('unknown type → UnknownFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.unknown),
      );
      expect(f, isA<UnknownFailure>());
    });

    test('cancel type → UnknownFailure', () {
      final f = mapDioException(
        _dioError(type: DioExceptionType.cancel),
      );
      expect(f, isA<UnknownFailure>());
    });

    // -----------------------------------------------------------------------
    // Safety: server internals not in message
    // -----------------------------------------------------------------------

    test('5xx response body is NOT included in message', () {
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 500,
          data: 'Internal server error: NullPointerException at line 42',
        ),
      );
      expect(f, isA<ServerFailure>());
      // The raw server body must not appear in message.
      expect(
        f.message.contains('NullPointerException'),
        isFalse,
        reason: 'Raw server internals must not be surfaced',
      );
    });
  });
}
