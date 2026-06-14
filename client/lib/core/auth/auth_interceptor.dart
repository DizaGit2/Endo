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
/// ### onAuthLost
/// When refresh fails (or no refresh token is stored), tokens are cleared via
/// [TokenStore.clear] and [onAuthLost] is called so the app can navigate to
/// the login screen.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStore tokenStore,
    required Future<OidcTokens> Function(String refreshToken) refresh,
    required void Function() onAuthLost,
    DateTime Function()? clock,
  })  : _store = tokenStore,
        _refresh = refresh, // ignore: prefer_initializing_formals
        _onAuthLost = onAuthLost, // ignore: prefer_initializing_formals
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
      final tokens = await _doRefresh();

      // Retry the original request marked as retried (to prevent loops).
      final retryOptions = options.copyWith(
        extra: {...options.extra, _kRetried: true},
        headers: {
          ...options.headers,
          'Authorization': 'Bearer ${tokens.accessToken}',
        },
      );

      final retryDio = dio ?? Dio();
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
    } catch (_) {
      await _store.clear();
      _onAuthLost();
      throw const _AuthLostException();
    }
  }
}

// ---------------------------------------------------------------------------
// Internal sentinel exception (never escapes this library)
// ---------------------------------------------------------------------------

class _AuthLostException implements Exception {
  const _AuthLostException();
}
