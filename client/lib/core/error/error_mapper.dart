import 'package:dio/dio.dart';
import 'package:lumen/core/error/failure.dart';

// ---------------------------------------------------------------------------
// RFC 7807 problem+json helpers
// ---------------------------------------------------------------------------

/// Attempts to extract the `title` field from a problem+json response body.
String? _problemTitle(dynamic data) {
  if (data is Map<String, dynamic>) {
    final v = data['title'];
    return v is String ? v : null;
  }
  return null;
}

/// Attempts to extract the `detail` field from a problem+json response body.
String? _problemDetail(dynamic data) {
  if (data is Map<String, dynamic>) {
    final v = data['detail'];
    return v is String ? v : null;
  }
  return null;
}

/// Attempts to extract per-field errors from the `errors` map in a problem+json
/// response body.
///
/// Expected shape:
/// ```json
/// { "errors": { "fieldName": ["error1", "error2"] } }
/// ```
Map<String, List<String>> _problemFields(dynamic data) {
  if (data is! Map<String, dynamic>) return {};
  final errors = data['errors'];
  if (errors is! Map<String, dynamic>) return {};

  return errors.map((key, value) {
    final messages = value is List
        ? value.whereType<String>().toList()
        : <String>[];
    return MapEntry(key, messages);
  });
}

// ---------------------------------------------------------------------------
// Mapper
// ---------------------------------------------------------------------------

/// Maps a [DioException] to a typed [Failure].
///
/// Rules:
/// - Connection/timeout types → [NetworkFailure]
/// - HTTP 400 / 422 → [ValidationFailure] (parse RFC 7807 `problem+json`)
/// - HTTP 401 → [AuthFailure]
/// - HTTP 404 → [NotFoundFailure]
/// - HTTP 5xx → [ServerFailure]
/// - Anything else → [UnknownFailure]
///
/// Raw server internals (stack traces, internal error IDs) are never surfaced
/// in [Failure.message].
Failure mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return const NetworkFailure();

    case DioExceptionType.badResponse:
      final status = e.response?.statusCode;
      final data = e.response?.data;

      if (status == 400 || status == 422) {
        final detail = _problemDetail(data) ?? _problemTitle(data);
        final fields = _problemFields(data);
        return ValidationFailure(
          message: detail ?? 'The request contained invalid data.',
          detail: detail,
          fields: fields,
        );
      }

      if (status == 401) return const AuthFailure();
      if (status == 404) return const NotFoundFailure();
      if (status != null && status >= 500 && status < 600) {
        return const ServerFailure();
      }

      return const UnknownFailure();

    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
    case DioExceptionType.badCertificate:
      return const UnknownFailure();
  }
}
