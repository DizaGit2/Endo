import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Value type
// ---------------------------------------------------------------------------

/// Immutable container for OIDC tokens returned after a successful
/// authorization or token-refresh flow.
class OidcTokens {
  const OidcTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
    required this.accessTokenExpiry,
  });

  final String accessToken;
  final String refreshToken;
  final String idToken;
  final DateTime accessTokenExpiry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OidcTokens &&
          accessToken == other.accessToken &&
          refreshToken == other.refreshToken &&
          idToken == other.idToken &&
          accessTokenExpiry == other.accessTokenExpiry;

  @override
  int get hashCode => Object.hash(
        accessToken,
        refreshToken,
        idToken,
        accessTokenExpiry,
      );
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/// Compile-time OIDC configuration.
///
/// Dev defaults target the Android emulator reaching the host Keycloak instance
/// via the 10.0.2.2 alias. [allowInsecureConnections] defaults to [kDebugMode]
/// so HTTP / cert-bypass is permitted ONLY in debug/dev builds (required for the
/// emulator→host http run at T10); release builds force TLS and cannot ship an
/// insecure OIDC connection.
// TODO(P11): production must use the https Caddy issuer (allowInsecureConnections
//   is kDebugMode-gated, so release builds are already safe).

/// OIDC issuer. Override at build/run time with
///   `--dart-define=LUMEN_OIDC_ISSUER=http://<host>:<port>/realms/lumen`
/// The default targets the Android emulator's host alias; for a real device pass
/// the host LAN IP, for production the https Caddy host.
const _kDefaultIssuer = String.fromEnvironment(
  'LUMEN_OIDC_ISSUER',
  defaultValue: 'http://10.0.2.2:8080/realms/lumen',
);

class OidcConfig {
  const OidcConfig({
    this.issuer = _kDefaultIssuer,
    this.clientId = 'mobile',
    this.redirectUrl = 'com.lumen.app:/oauth2redirect',
    this.postLogoutRedirectUrl = 'com.lumen.app:/oauth2redirect',
    this.scopes = const ['openid', 'profile', 'offline_access'],
    this.allowInsecureConnections = kDebugMode,
  });

  final String issuer;
  final String clientId;
  final String redirectUrl;

  /// Where Keycloak redirects after RP-initiated logout. Must be registered in
  /// the realm's `post.logout.redirect.uris`. Reuses the app redirect scheme so
  /// the end-session browser tab returns to the app (which then lands on the
  /// welcome screen) instead of stranding the user on Keycloak's logout page.
  final String postLogoutRedirectUrl;

  final List<String> scopes;

  /// Allow plain-HTTP / cert-bypass OIDC endpoints. Defaults to [kDebugMode]
  /// (dev only); never true in release builds.
  final bool allowInsecureConnections;

  /// The Keycloak OIDC endpoints derived from [issuer].
  ///
  /// Passed to AppAuth EXPLICITLY (instead of an issuer) so the native layer
  /// does NOT fetch the discovery document. That fetch ignores
  /// [allowInsecureConnections] for `endSession` on Android and crashes the app
  /// over cleartext ("only https connections are permitted").
  AuthorizationServiceConfiguration get serviceConfiguration {
    final base =
        issuer.endsWith('/') ? issuer.substring(0, issuer.length - 1) : issuer;
    return AuthorizationServiceConfiguration(
      authorizationEndpoint: '$base/protocol/openid-connect/auth',
      tokenEndpoint: '$base/protocol/openid-connect/token',
      endSessionEndpoint: '$base/protocol/openid-connect/logout',
    );
  }
}

// ---------------------------------------------------------------------------
// Refresh-failure classification (D2 — walk 2026-08-25, B-49)
// ---------------------------------------------------------------------------

/// The authorization server has authoritatively rejected the refresh token.
///
/// Thrown by [IOidcClient.refresh] — and ONLY for this — so that the caller can
/// tell "the session is over" apart from "the refresh could not run". Before
/// this distinction existed, `AuthInterceptor` treated every exception from
/// the refresh seam as the end of the session: going offline ~15 minutes after
/// the last token issue signed the user out and purged the on-disk cache, with
/// no user action, on a refresh that would have succeeded online.
class OidcSessionRejected implements Exception {
  const OidcSessionRejected(this.error);

  /// The OAuth 2.0 error code the server answered with (RFC 6749 §5.2), e.g.
  /// `invalid_grant`.
  final String error;

  @override
  String toString() => 'OidcSessionRejected($error)';
}

/// The OAuth 2.0 token-endpoint errors that mean the refresh token itself is
/// dead (RFC 6749 §5.2): the grant is expired, revoked or issued to another
/// client, or this client may not use it. Nothing but a new interactive login
/// can recover from these.
///
/// Deliberately NOT here: `invalid_request`, `invalid_scope` and
/// `unsupported_grant_type` say OUR request was malformed, and
/// `server_error` / `temporarily_unavailable` say the server is having a bad
/// moment. Clearing the user's tokens fixes none of them and would erase the
/// cache for nothing, so they stay transient — the next request tries again.
const Set<String> kAuthoritativeRefreshErrors = <String>{
  FlutterAppAuthOAuthError.invalidGrant,
  FlutterAppAuthOAuthError.invalidClient,
  FlutterAppAuthOAuthError.unauthorizedClient,
};

/// Whether [error], as thrown by `FlutterAppAuth.token`, is the server's own
/// verdict on the refresh token rather than a failure to reach a verdict.
///
/// AppAuth surfaces the server's OAuth error code in
/// `platformErrorDetails.error` on both platforms (Android from
/// `AuthorizationException.error`, iOS from `OIDOAuthErrorFieldError`), and
/// leaves it null when no server answered — `discovery_failed` with a
/// `ConnectException` is what the walk logged offline. Everything that is not
/// a platform exception carrying one of [kAuthoritativeRefreshErrors] is
/// treated as transient: the fail-safe direction, because a wrongly-kept
/// session costs one more failed refresh, while a wrongly-ended one costs the
/// user their session and their cache.
bool isAuthoritativeRefreshRejection(Object error) {
  if (error is! FlutterAppAuthPlatformException) return false;
  final code = error.platformErrorDetails.error?.trim().toLowerCase();
  return code != null && kAuthoritativeRefreshErrors.contains(code);
}

// ---------------------------------------------------------------------------
// Interface
// ---------------------------------------------------------------------------

/// Abstracts the native AppAuth library so that [AuthController] can be
/// unit-tested without platform channels.
///
/// The concrete implementation [AppAuthOidcClient] wraps [FlutterAppAuth] and
/// is **not** unit-tested (platform channels require a live device/emulator);
/// integration coverage is provided at T10.
abstract interface class IOidcClient {
  /// Starts an interactive PKCE login flow and returns the resulting tokens.
  ///
  /// Throws on failure or user cancellation (the caller is responsible for
  /// deciding whether to surface the error or treat it as a no-op).
  Future<OidcTokens> login();

  /// Exchanges [refreshToken] for a fresh set of tokens.
  ///
  /// **What it throws decides whether the session ends** (D2, B-49):
  /// - [OidcSessionRejected] — the authorization server itself refused the
  ///   refresh token (`invalid_grant` and its kin). The session is over;
  ///   `AuthInterceptor` clears the stored tokens and signals `onAuthLost`.
  /// - anything else — the refresh could not be carried out: no network, the
  ///   discovery document or token endpoint unreachable, a timeout, a 5xx, a
  ///   malformed response. The session is NOT over; the interceptor keeps the
  ///   tokens, fails the one request as a connection error, and refreshes
  ///   again on the next.
  Future<OidcTokens> refresh(String refreshToken);

  /// Sends an RP-initiated logout request using [idToken] as the hint.
  ///
  /// Best-effort: the caller should not rely on this succeeding and must
  /// clear local state regardless.
  Future<void> endSession({required String idToken});
}

// ---------------------------------------------------------------------------
// Concrete implementation (native — not unit-tested)
// ---------------------------------------------------------------------------

/// Wraps [FlutterAppAuth] to implement [IOidcClient].
///
/// Platform-channel code cannot be unit-tested; end-to-end coverage is
/// exercised in the live integration test at T10. The one exception is the
/// refresh-failure classification in [refresh], which decides whether the
/// user keeps their session: `oidc_client_test.dart` pins it through an
/// injected [appAuth].
class AppAuthOidcClient implements IOidcClient {
  AppAuthOidcClient({
    OidcConfig? config,
    @visibleForTesting FlutterAppAuth? appAuth,
  })  : _config = config ?? const OidcConfig(),
        _appAuth = appAuth ?? const FlutterAppAuth();

  final OidcConfig _config;
  final FlutterAppAuth _appAuth;

  @override
  Future<OidcTokens> login() async {
    final response = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _config.clientId,
        _config.redirectUrl,
        issuer: _config.issuer,
        scopes: _config.scopes,
        // PKCE is handled automatically by flutter_appauth.
        allowInsecureConnections: _config.allowInsecureConnections,
        // Always show the Keycloak login form rather than silently reusing an
        // existing SSO session. For a health app this is the safer default (no
        // silent session reuse on a shared device); it also avoids an AppAuth
        // race where an instant SSO redirect returns before the request state
        // is persisted ("No stored state").
        promptValues: const ['login'],
      ),
    );
    return _tokensFromResponse(response);
  }

  @override
  Future<OidcTokens> refresh(String refreshToken) async {
    final TokenResponse response;
    try {
      response = await _appAuth.token(
        TokenRequest(
          _config.clientId,
          _config.redirectUrl,
          issuer: _config.issuer,
          scopes: _config.scopes,
          refreshToken: refreshToken,
          grantType: GrantType.refreshToken,
          allowInsecureConnections: _config.allowInsecureConnections,
        ),
      );
    } on FlutterAppAuthPlatformException catch (e) {
      // The server's verdict on the token, or a failure to reach one — see
      // [isAuthoritativeRefreshRejection]. Only the former is re-thrown as
      // [OidcSessionRejected]; the latter propagates as-is and the interceptor
      // keeps the session.
      if (isAuthoritativeRefreshRejection(e)) {
        throw OidcSessionRejected(e.platformErrorDetails.error!.trim().toLowerCase());
      }
      rethrow;
    }
    return _tokensFromResponse(response);
  }

  @override
  Future<void> endSession({required String idToken}) async {
    await _appAuth.endSession(
      EndSessionRequest(
        idTokenHint: idToken,
        // Redirect back into the app after logout so the end-session browser tab
        // closes and the app resumes (then lands on welcome). Must be in the
        // realm's post.logout.redirect.uris.
        postLogoutRedirectUrl: _config.postLogoutRedirectUrl,
        // Use explicit endpoints (NOT `issuer`) so AppAuth does not fetch the
        // discovery document: that fetch ignores allowInsecureConnections for
        // endSession on Android and crashes over cleartext. See OidcConfig.
        serviceConfiguration: _config.serviceConfiguration,
        allowInsecureConnections: _config.allowInsecureConnections,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  OidcTokens _tokensFromResponse(TokenResponse r) {
    final accessToken = r.accessToken;
    final refreshToken = r.refreshToken;
    final idToken = r.idToken;
    final expiry = r.accessTokenExpirationDateTime;

    if (accessToken == null ||
        refreshToken == null ||
        idToken == null ||
        expiry == null) {
      throw StateError(
        'AppAuth returned an incomplete token response '
        '(accessToken=${accessToken == null ? "null" : "ok"}, '
        'refreshToken=${refreshToken == null ? "null" : "ok"}, '
        'idToken=${idToken == null ? "null" : "ok"}, '
        'expiry=${expiry == null ? "null" : "ok"})',
      );
    }

    return OidcTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      accessTokenExpiry: expiry,
    );
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Provides the singleton [IOidcClient] for the app.
///
/// Overridden in tests with a mock; production uses [AppAuthOidcClient].
final oidcClientProvider = Provider<IOidcClient>(
  (_) => AppAuthOidcClient(),
);
