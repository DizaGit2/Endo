import 'package:flutter/foundation.dart' show kDebugMode;
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
// TODO(P3b-T10): point issuer at the live host for the emulator run.
// TODO(P11): production must use the https Caddy issuer (allowInsecureConnections
//   is kDebugMode-gated, so release builds are already safe).
class OidcConfig {
  const OidcConfig({
    this.issuer = 'http://10.0.2.2:8080/realms/lumen',
    this.clientId = 'mobile',
    this.redirectUrl = 'com.lumen.app:/oauth2redirect',
    this.scopes = const ['openid', 'profile', 'offline_access'],
    this.allowInsecureConnections = kDebugMode,
  });

  final String issuer;
  final String clientId;
  final String redirectUrl;
  final List<String> scopes;

  /// Allow plain-HTTP / cert-bypass OIDC endpoints. Defaults to [kDebugMode]
  /// (dev only); never true in release builds.
  final bool allowInsecureConnections;
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
/// exercised in the live integration test at T10.
class AppAuthOidcClient implements IOidcClient {
  AppAuthOidcClient({OidcConfig? config})
      : _config = config ?? const OidcConfig(),
        _appAuth = const FlutterAppAuth();

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
    final response = await _appAuth.token(
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
    return _tokensFromResponse(response);
  }

  @override
  Future<void> endSession({required String idToken}) async {
    await _appAuth.endSession(
      EndSessionRequest(
        idTokenHint: idToken,
        issuer: _config.issuer,
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
