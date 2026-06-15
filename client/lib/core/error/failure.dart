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

/// The server rejected the request due to invalid input (400 / 422).
///
/// [fields] carries per-field validation errors parsed from RFC 7807
/// `problem+json` (key = field name, value = list of error messages).
/// [detail] is the overall human-readable description from the `detail`
/// or `title` property of the problem document.
final class ValidationFailure extends Failure {
  const ValidationFailure({
    String message = 'The request contained invalid data.',
    this.detail,
    this.fields = const {},
  }) : super(message);

  /// Overall detail from the `detail` or `title` field of the problem document.
  final String? detail;

  /// Per-field validation errors (may be empty).
  final Map<String, List<String>> fields;
}

/// The requested resource does not exist (404).
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'The requested resource was not found.']);
}

/// The request conflicts with existing state (409) — e.g. registering with an
/// email that already has an account. [message] carries the server's
/// problem+json `detail`/`title` when present.
final class ConflictFailure extends Failure {
  const ConflictFailure([super.message = 'That request conflicts with existing data.']);
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
