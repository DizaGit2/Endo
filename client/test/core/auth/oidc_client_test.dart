// Tests for the refresh-failure classification in oidc_client.dart (D2 — PR #4
// review, walk 2026-08-25, B-49).
//
// `AppAuthOidcClient.refresh` is the only place the app can tell WHY a refresh
// failed: AppAuth hands it a `FlutterAppAuthPlatformException` whose
// `platformErrorDetails.error` is the OAuth 2.0 error code the server answered
// with — or null when no server answered at all (offline, discovery
// unreachable, timeout). The interceptor above it must end the session only
// for the first kind. So the classification is pinned here, twice: as the pure
// predicate, and through `refresh()` itself with the AppAuth facade injected.
//
// The rest of `AppAuthOidcClient` is platform-channel code and stays untested
// here, as its dartdoc says; only the seam that decides the user's session is
// worth a mock of the facade.

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/oidc_client.dart';
import 'package:mocktail/mocktail.dart';

class _MockFlutterAppAuth extends Mock implements FlutterAppAuth {}

FlutterAppAuthPlatformException _platformError({
  required String code,
  String? error,
}) => FlutterAppAuthPlatformException(
  code: code,
  message: 'Failed to refresh token',
  platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
    type: '2',
    code: '0',
    error: error,
    errorDescription: error == null ? null : 'Token is not active',
  ),
);

void main() {
  // -------------------------------------------------------------------------
  // The predicate
  // -------------------------------------------------------------------------

  group('isAuthoritativeRefreshRejection', () {
    for (final code in ['invalid_grant', 'invalid_client', 'unauthorized_client']) {
      test('$code from the token endpoint IS authoritative', () {
        expect(
          isAuthoritativeRefreshRejection(
            _platformError(code: 'token_failed', error: code),
          ),
          isTrue,
        );
      });
    }

    test('the OAuth code is matched case-insensitively and trimmed', () {
      expect(
        isAuthoritativeRefreshRejection(
          _platformError(code: 'token_failed', error: ' Invalid_Grant '),
        ),
        isTrue,
      );
    });

    test('a discovery failure (no server verdict) is NOT authoritative', () {
      // What AppAuth-Android throws offline: `discovery_failed` with no OAuth
      // error — the walk's exact logcat line.
      expect(
        isAuthoritativeRefreshRejection(
          _platformError(code: 'discovery_failed'),
        ),
        isFalse,
      );
    });

    test('a token-endpoint failure with no OAuth error (network, 5xx) is NOT '
        'authoritative', () {
      expect(
        isAuthoritativeRefreshRejection(_platformError(code: 'token_failed')),
        isFalse,
      );
    });

    test('an OAuth error that does not name the grant is NOT authoritative', () {
      // `invalid_request` / `invalid_scope` / `unsupported_grant_type` mean
      // OUR request was wrong, not that the user's session is over; clearing
      // the tokens would not fix them and would erase the cache for nothing.
      for (final code in [
        'invalid_request',
        'invalid_scope',
        'unsupported_grant_type',
        'server_error',
        'temporarily_unavailable',
      ]) {
        expect(
          isAuthoritativeRefreshRejection(
            _platformError(code: 'token_failed', error: code),
          ),
          isFalse,
          reason: code,
        );
      }
    });

    test('anything that is not an AppAuth platform exception is NOT '
        'authoritative', () {
      expect(isAuthoritativeRefreshRejection(Exception('boom')), isFalse);
      expect(
        isAuthoritativeRefreshRejection(StateError('incomplete response')),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Through refresh() itself
  // -------------------------------------------------------------------------

  group('AppAuthOidcClient.refresh', () {
    late _MockFlutterAppAuth appAuth;
    late AppAuthOidcClient client;

    setUpAll(() {
      registerFallbackValue(
        TokenRequest(
          'mobile',
          'com.lumen.app:/oauth2redirect',
          issuer: 'http://10.0.2.2:8080/realms/lumen',
        ),
      );
    });

    setUp(() {
      appAuth = _MockFlutterAppAuth();
      client = AppAuthOidcClient(appAuth: appAuth);
    });

    test('maps an authoritative rejection to OidcSessionRejected carrying the '
        'OAuth code', () async {
      when(() => appAuth.token(any())).thenThrow(
        _platformError(code: 'token_failed', error: 'invalid_grant'),
      );

      await expectLater(
        () => client.refresh('rt'),
        throwsA(
          isA<OidcSessionRejected>().having((e) => e.error, 'error', 'invalid_grant'),
        ),
      );
    });

    test('rethrows a transient platform failure unchanged — the interceptor '
        'keeps the tokens for anything that is not OidcSessionRejected',
        () async {
      final offline = _platformError(code: 'discovery_failed');
      when(() => appAuth.token(any())).thenThrow(offline);

      await expectLater(
        () => client.refresh('rt'),
        throwsA(same(offline)),
      );
    });

    test('a token response missing a field is a StateError, not a rejection',
        () async {
      when(() => appAuth.token(any())).thenAnswer(
        // Positional, per flutter_appauth_platform_interface's TokenResponse:
        // accessToken, refreshToken (missing here), expiry, idToken,
        // tokenType, scopes, tokenAdditionalParameters.
        (_) async => TokenResponse(
          'at',
          null,
          DateTime.utc(2099),
          'it',
          'Bearer',
          const ['openid'],
          null,
        ),
      );

      await expectLater(() => client.refresh('rt'), throwsStateError);
    });
  });
}
