// ---------------------------------------------------------------------------
// Failure — sealed hierarchy for typed error handling across the app.
// ---------------------------------------------------------------------------

/// Base class for all application-level failures.
///
/// Failures are user-safe: [message] must never contain raw server internals,
/// stack traces, or PII.
sealed class Failure {
  const Failure(this.message);

  /// A human-safe description of the failure (suitable for display or logging).
  final String message;
}

/// No connectivity, or a timeout before a response was received.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No network connection or request timed out.']);
}

/// The server rejected the request with a 401 after a token-refresh attempt
/// also failed, or when no refresh token was available.
final class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed. Please sign in again.']);
}

/// The server rejected the request due to invalid input (400).
///
/// [fields] carries per-field validation errors parsed from RFC 7807
/// `problem+json` (key = field name, value = list of error messages).
/// [detail] is the overall human-readable description from the `detail`
/// or `title` property of the problem document.
///
/// The keys are the camelCase JSON paths **exactly as they appear on the
/// wire**, including indexed ones — `entries[3].intensity`,
/// `boundaries[0].occurredOn`, `painTypes[1]` — plus the reserved
/// [requestKey] for cross-field errors that name no single input. Bind a
/// message to one input with [messageFor], building indexed keys with [path]:
///
/// ```dart
/// errorText: failure.messageFor(ValidationFailure.path('entries', i, 'intensity')),
/// ```
final class ValidationFailure extends Failure {
  const ValidationFailure({
    String message = 'The request contained invalid data.',
    this.detail,
    this.fields = const {},
  }) : super(message);

  /// The reserved key the server uses for cross-field / whole-body errors.
  ///
  /// It names no input, so it cannot be attached to a field — render
  /// [requestMessages] as a form-level banner instead.
  static const requestKey = 'request';

  /// Builds the indexed key the server uses for an element of a collection:
  /// `path('entries', 3, 'intensity')` → `entries[3].intensity`, and
  /// `path('painTypes', 1)` → `painTypes[1]`.
  ///
  /// A batch write (up to 50 symptom rows) needs this: a single top-level
  /// string cannot tell the user which row was rejected.
  ///
  /// Calls **compose** for the nested form the symptom batch actually emits
  /// (`SymptomResult.cs:20` / `SymptomService.cs:576`) — pass a built path as
  /// [field]:
  ///
  /// ```dart
  /// ValidationFailure.path('entries', 0, ValidationFailure.path('painTypes', 1))
  /// // → 'entries[0].painTypes[1]'
  /// ```
  static String path(String collection, int index, [String? field]) =>
      field == null ? '$collection[$index]' : '$collection[$index].$field';

  /// Overall detail from the `detail` or `title` field of the problem document.
  final String? detail;

  /// Per-field validation errors (may be empty).
  final Map<String, List<String>> fields;

  /// Every message the server returned for [field]; empty when it had none.
  List<String> messagesFor(String field) => fields[field] ?? const <String>[];

  /// The first message for [field], or `null` when the server did not reject
  /// it — the shape a `TextField.errorText` wants.
  String? messageFor(String field) {
    final messages = messagesFor(field);
    return messages.isEmpty ? null : messages.first;
  }

  /// Cross-field / whole-body messages (the reserved [requestKey]).
  List<String> get requestMessages => messagesFor(requestKey);
}

/// The requested resource does not exist (404).
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'The requested resource was not found.']);
}

/// The request conflicts with existing state (409) — e.g. registering with an
/// email that already has an account. [message] carries the server's
/// problem+json `detail`/`title` when present.
///
/// [code] and [missingSteps] are the problem-details **extensions** the
/// onboarding endpoints add; neither is on the generated `ProblemDetails`
/// model, so `error_mapper.dart` lifts them off the raw body here. Completing
/// onboarding with a step unanswered answers 409 with
/// `code: "onboarding_incomplete"` and `missingSteps: ["cycle"]`, which is how
/// screen 7 knows where to send the user back to. A screen must read them from
/// this failure and never from `DioException.response.data`.
final class ConflictFailure extends Failure {
  const ConflictFailure({
    String message = 'That request conflicts with existing data.',
    this.code,
    this.missingSteps = const <String>[],
  }) : super(message);

  /// The machine-readable conflict code (e.g. `onboarding_incomplete`), or
  /// `null` when the server sent none.
  final String? code;

  /// The onboarding steps still unanswered (e.g. `['cycle']`); empty when the
  /// server sent none.
  final List<String> missingSteps;
}

/// The client is being rate-limited (429).
final class RateLimitFailure extends Failure {
  const RateLimitFailure([super.message = 'Too many attempts. Please wait a moment and try again.']);
}

/// The server's TLS certificate could not be validated (possible MITM or
/// tampering). This is a HARD failure: it must NEVER be treated as a transient
/// offline state, so cached (decrypted) data is never served in its place.
final class TlsFailure extends Failure {
  const TlsFailure([super.message = 'A secure connection to the server could not be verified.']);
}

/// An unexpected server-side error (5xx).
final class ServerFailure extends Failure {
  const ServerFailure([super.message = 'A server error occurred. Please try again later.']);
}

/// A failure that does not fit any of the above categories.
final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'An unexpected error occurred.']);
}
