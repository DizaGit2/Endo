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

    test('422 with problem+json errors map → ValidationFailure carries fields',
        () {
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 422,
          data: {
            'title': 'Unprocessable entity',
            'detail': 'Input is invalid',
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

    test('422 with no fields map → ValidationFailure with empty fields', () {
      final f = mapDioException(
        _dioError(
          type: DioExceptionType.badResponse,
          statusCode: 422,
          data: {'title': 'Bad input'},
        ),
      ) as ValidationFailure;
      expect(f.fields, isEmpty);
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
