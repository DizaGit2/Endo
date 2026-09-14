import 'dart:async';

import 'package:dio/dio.dart';
import 'package:lumen/core/auth/oidc_client.dart';
import 'package:lumen/core/auth/token_store.dart';
import 'package:lumen/core/error/failure.dart';

// ---------------------------------------------------------------------------
// Internal option key — marks a retried request so a 401 on retry does NOT
// trigger another refresh (infinite-loop guard).
// ---------------------------------------------------------------------------

const _kRetried = 'auth_interceptor_retried';

// ---------------------------------------------------------------------------
// AuthInterceptor
// ---------------------------------------------------------------------------

/// Dio [Interceptor] that handles bearer-token attachment and token refresh.
///
/// ### Proactive refresh (onRequest)
/// If the stored access-token expiry is within 30 s of the current time
/// (injectable via [clock] for testability), the interceptor refreshes before
/// forwarding the request.
///
/// ### Reactive refresh (onError — 401 only)
/// On a 401 response the interceptor attempts a single token refresh, persists
/// the new tokens, and **retries the original request once** with the new
/// bearer. The retried request carries a marker so a subsequent 401 does NOT
/// loop.
///
/// ### Single-flight guarantee
/// Concurrent requests that all enter the near-expiry window (proactive) or
/// all receive a 401 (reactive) share a single in-flight refresh [Future].
/// Exactly one call to the underlying [refresh] function is made.
///
/// ### onAuthLost — only for an AUTHORITATIVE loss (D2, B-49)
/// When no refresh token is stored, or the authorization server itself rejects
/// the refresh token ([OidcSessionRejected] from [refresh]), tokens are cleared
/// via [TokenStore.clear] and [onAuthLost] is called so the app can navigate to
/// the login screen.
///
/// Any OTHER refresh failure — no network, discovery unreachable, the token
/// endpoint down or answering 5xx, a malformed response — is transient: the
/// tokens are KEPT, the one request that needed the refresh is rejected as a
/// [DioExceptionType.connectionError] carrying a [NetworkFailure] (so
/// `error_mapper.dart` renders the offline state and `cachedRead` serves stale
/// data), and the next request simply refreshes again. Before this distinction
/// a bare `catch (_)` here signed the user out and purged the on-disk cache on
/// the first network-bound request after ~15 minutes offline (walk 2026-08-25).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStore tokenStore,
    required Future<OidcTokens> Function(String refreshToken) refresh,
    required void Function() onAuthLost,
    DateTime Function()? clock,
  })  : _store = tokenStore,
        _refresh = refresh, // ignore: prefer_initializing_formals
        _onAuthLost = onAuthLost, // ignore: prefer_initializing_formals
        // lumen:allow-device-clock token expiry, not a cycle date (D-12); overridable seam
        _clock = clock ?? DateTime.now;

  final TokenStore _store;
  final Future<OidcTokens> Function(String refreshToken) _refresh;
  final void Function() _onAuthLost;
  final DateTime Function() _clock;

  /// The [Dio] instance to use for retrying failed requests.
  ///
  /// Must be set immediately after attaching the interceptor to a [Dio]
  /// instance (see [DioProvider]). Kept as a late field to avoid circular
  /// construction.
  Dio? dio;

  /// Within 30 seconds of expiry → proactive refresh.
  static const _kProactiveRefreshThreshold = Duration(seconds: 30);

  /// Single in-flight refresh future (shared across concurrent callers).
  Future<OidcTokens>? _inflightRefresh;

  // -------------------------------------------------------------------------
  // onRequest
  // -------------------------------------------------------------------------

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      // Proactively refresh if the token is near expiry.
      final expiry = await _store.readAccessTokenExpiry();
      if (expiry != null) {
        final remaining = expiry.difference(_clock());
        if (remaining <= _kProactiveRefreshThreshold) {
          await _doRefresh();
        }
      }

      // Attach the (possibly freshly refreshed) access token.
      final token = await _store.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    } on _AuthLostException {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const AuthFailure(),
          type: DioExceptionType.unknown,
        ),
      );
    } on _RefreshUnavailableException {
      handler.reject(_refreshUnavailable(options));
    } catch (e, st) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // onError
  // -------------------------------------------------------------------------

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final options = err.requestOptions;

    // Only handle 401 responses and only if NOT already a retried request.
    if (response?.statusCode != 401 || options.extra[_kRetried] == true) {
      handler.next(err);
      return;
    }

    try {
      await _doRefresh();

      // Retry the original request, marked as retried (to prevent loops). We do
      // NOT set the Authorization header here: the retry re-enters the
      // interceptor chain, so onRequest re-reads the freshly-persisted access
      // token from the store and attaches it — the store is the single source
      // of truth for the bearer.
      final retryOptions = options.copyWith(
        extra: {...options.extra, _kRetried: true},
      );

      final retryDio = dio ??
          (throw StateError('AuthInterceptor.dio must be set before requests run'));
      final retryResponse = await retryDio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } on _AuthLostException {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const AuthFailure(),
          type: DioExceptionType.unknown,
        ),
      );
    } on _RefreshUnavailableException {
      handler.reject(_refreshUnavailable(options));
    } on DioException catch (e) {
      // Refresh succeeded but the RETRIED request failed for a non-auth reason
      // (timeout, 5xx, repeated 401 caught by the retry guard). Surface the real
      // error so callers map it correctly — do NOT mislabel it as AuthFailure.
      handler.reject(e);
    } catch (_) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: const AuthFailure(),
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  /// Returns (or joins) the in-flight refresh [Future].
  ///
  /// The `whenComplete` clears [_inflightRefresh] so the next call (after the
  /// current one settles) starts a fresh refresh if needed.
  Future<OidcTokens> _doRefresh() {
    _inflightRefresh ??= _performRefresh().whenComplete(() {
      _inflightRefresh = null;
    });
    return _inflightRefresh!;
  }

  Future<OidcTokens> _performRefresh() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _store.clear();
      _onAuthLost();
      throw const _AuthLostException();
    }

    try {
      final tokens = await _refresh(refreshToken);
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        idToken: tokens.idToken,
        accessTokenExpiry: tokens.accessTokenExpiry,
      );
      return tokens;
    } on OidcSessionRejected {
      // The server's own verdict: the refresh token is dead. Nothing but a
      // new interactive login recovers from this, so tear the session down.
      await _store.clear();
      _onAuthLost();
      throw const _AuthLostException();
    } catch (_) {
      // Everything else is a refresh that could not RUN, not one that was
      // refused — the tokens stay, and `whenComplete` in [_doRefresh] has
      // already made the next request try again.
      throw const _RefreshUnavailableException();
    }
  }

  /// The rejection handed to a request whose refresh could not run.
  ///
  /// `type: connectionError`, not `unknown`: `mapDioException` switches on the
  /// type and maps `unknown` to `UnknownFailure` without unwrapping `error`, so
  /// the NetworkFailure has to travel under the type the mapper reads. That is
  /// what lets `cachedRead` answer `Stale` from the box and the screens render
  /// their designed "No network connection" state instead of a generic error.
  DioException _refreshUnavailable(RequestOptions options) => DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const NetworkFailure(),
        message: 'The session could not be refreshed right now; the stored '
            'tokens were kept.',
      );
}

// ---------------------------------------------------------------------------
// Internal sentinel exceptions (never escape this library)
// ---------------------------------------------------------------------------

/// The session is over: tokens cleared, [AuthInterceptor.onAuthLost] fired.
class _AuthLostException implements Exception {
  const _AuthLostException();
}

/// The refresh could not run; the session is untouched.
class _RefreshUnavailableException implements Exception {
  const _RefreshUnavailableException();
}
