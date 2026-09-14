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

/// Reads a string-valued problem-details **extension** (a member outside the
/// RFC 7807 core, e.g. `code`), returning `null` when absent or not a string.
String? _problemString(dynamic data, String member) {
  if (data is! Map<String, dynamic>) return null;
  final value = data[member];
  return value is String ? value : null;
}

/// Reads a string-list problem-details **extension** (e.g. `missingSteps`).
///
/// Degrades to an empty list rather than throwing: these members are not on the
/// generated `ProblemDetails` model, so nothing but this function validates
/// their shape, and a malformed one must not become a `TypeError` inside a
/// screen's error handler.
List<String> _problemStringList(dynamic data, String member) {
  if (data is! Map<String, dynamic>) return const <String>[];
  final value = data[member];
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

// ---------------------------------------------------------------------------
// Mapper
// ---------------------------------------------------------------------------

/// Maps a [DioException] to a typed [Failure].
///
/// Rules:
/// - Connection/timeout types → [NetworkFailure]
/// - TLS certificate validation failure → [TlsFailure] (HARD failure — never
///   served from stale cache)
/// - HTTP 400 → [ValidationFailure] (parse RFC 7807 `problem+json`). 400 is the
///   ONLY validation status the backend emits — there is no 422 anywhere in
///   `backend/src` or `backend/contract/openapi.json`, so a 422 is as unknown
///   as any other unexpected status.
/// - HTTP 401 → [AuthFailure]
/// - HTTP 404 → [NotFoundFailure]
/// - HTTP 409 → [ConflictFailure] (carries the problem+json `detail`/`title`
///   plus the `code` / `missingSteps` extensions)
/// - HTTP 429 → [RateLimitFailure]
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

    case DioExceptionType.badCertificate:
      // A TLS validation failure (possible MITM / cert tampering) is a HARD
      // error, not a transient offline state — callers must NOT fall back to
      // cached (decrypted) data, so this is deliberately not a NetworkFailure.
      return const TlsFailure();

    case DioExceptionType.badResponse:
      final status = e.response?.statusCode;
      final data = e.response?.data;

      if (status == 400) {
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
      if (status == 409) {
        final detail = _problemDetail(data) ?? _problemTitle(data);
        // `code` and `missingSteps` are problem-details extensions: they are on
        // the wire but not on the generated ProblemDetails model, so they are
        // lifted here. A screen must never reach into e.response.data itself.
        final code = _problemString(data, 'code');
        final missingSteps = _problemStringList(data, 'missingSteps');
        return ConflictFailure(
          message: detail ?? 'That request conflicts with existing data.',
          code: code,
          missingSteps: missingSteps,
        );
      }
      if (status == 429) return const RateLimitFailure();
      if (status != null && status >= 500 && status < 600) {
        return const ServerFailure();
      }

      return const UnknownFailure();

    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return const UnknownFailure();
  }
}
