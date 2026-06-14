import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/auth/auth_interceptor.dart';
import 'package:lumen/core/auth/oidc_client.dart';
import 'package:lumen/core/auth/token_store.dart';

// ---------------------------------------------------------------------------
// API base URL
// ---------------------------------------------------------------------------

// TODO(P3b-T10): finalize API base (Caddy https vs 10.0.2.2)
const _kApiBase = 'http://10.0.2.2:8080';

// ---------------------------------------------------------------------------
// PII-safe path set
// ---------------------------------------------------------------------------

/// Request paths whose bodies must NEVER be logged (they carry PII / health
/// data). Matched via [String.contains] so a prefix-match is sufficient.
const _kSensitivePaths = <String>[
  '/me',
  '/onboarding',
  '/settings',
  '/symptoms',
  '/cycle',
  '/body',
  '/labs',
];

bool _isSensitivePath(String path) =>
    _kSensitivePaths.any(path.contains);

// ---------------------------------------------------------------------------
// PII-safe logger interceptor
// ---------------------------------------------------------------------------

/// A Dio [Interceptor] that logs only method + path + status (no
/// Authorization header, no request/response bodies for sensitive paths).
///
/// Active only in [kDebugMode] — a no-op in release builds.
class _PiiSafeLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      // NEVER log the Authorization header.
      final safeHeaders = Map<String, dynamic>.from(options.headers)
        ..remove('Authorization')
        ..remove('authorization');

      final sensitive = _isSensitivePath(options.path);
      // ignore: avoid_print
      print(
        '[Dio ▶] ${options.method} ${options.path}'
        '${sensitive ? '' : ' headers=$safeHeaders'}',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final path = response.requestOptions.path;
      final sensitive = _isSensitivePath(path);
      // ignore: avoid_print
      print(
        '[Dio ◀] ${response.statusCode} ${response.requestOptions.method} $path'
        '${sensitive ? '' : ' data=${response.data}'}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[Dio ✗] ${err.response?.statusCode} '
        '${err.requestOptions.method} ${err.requestOptions.path} '
        '${err.type}',
      );
    }
    handler.next(err);
  }
}

// ---------------------------------------------------------------------------
// dioProvider
// ---------------------------------------------------------------------------

/// Provides the singleton [Dio] instance wired with [AuthInterceptor] and
/// the PII-safe logger.
///
/// The [AuthInterceptor] is constructed with:
/// - [TokenStore] from [tokenStoreProvider]
/// - A refresh function delegating to [IOidcClient.refresh] from
///   [oidcClientProvider]
/// - An [onAuthLost] callback that calls [AuthController.logout] so the router
///   guard redirects to the login screen
final dioProvider = Provider<Dio>((ref) {
  final tokenStore = ref.read(tokenStoreProvider);
  final oidcClient = ref.read(oidcClientProvider);

  final dio = Dio(
    BaseOptions(baseUrl: _kApiBase),
  );

  final authInterceptor = AuthInterceptor(
    tokenStore: tokenStore,
    refresh: (refreshToken) => oidcClient.refresh(refreshToken),
    onAuthLost: () {
      // Notify the auth controller so the router redirects to login.
      ref.read(authStatusProvider.notifier).logout();
    },
  );

  dio.interceptors.addAll([
    authInterceptor,
    _PiiSafeLogInterceptor(),
  ]);

  // Provide the interceptor a reference to Dio so it can retry 401 requests.
  authInterceptor.dio = dio;

  return dio;
});
