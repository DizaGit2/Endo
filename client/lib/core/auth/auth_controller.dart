import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/auth/oidc_client.dart';
import 'package:lumen/core/auth/token_store.dart';

// ---------------------------------------------------------------------------
// Auth status
// ---------------------------------------------------------------------------

/// Represents the overall authentication state of the app.
enum AuthStatus {
  /// Not yet determined (init in progress).
  unknown,

  /// A valid session exists.
  authenticated,

  /// No session — user must log in.
  unauthenticated,
}

// ---------------------------------------------------------------------------
// AuthController
// ---------------------------------------------------------------------------

/// Manages the [AuthStatus] for the app and coordinates OIDC flows.
///
/// Depends on [IOidcClient] (for PKCE login / refresh / end-session) and
/// [TokenStore] (for persisting tokens).
///
/// The [authStatusProvider] is the entry point for router guards (T5) and UI.
class AuthController extends Notifier<AuthStatus> {
  // Lazily completed when the async init is done.
  late final Future<void> initialized;

  IOidcClient get _oidc => ref.read(oidcClientProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  @override
  AuthStatus build() {
    initialized = _init();
    return AuthStatus.unknown;
  }

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    final hasSession = await _store.hasValidSession();
    state = hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;
  }

  // ---------------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------------

  /// Starts an interactive PKCE login.
  ///
  /// On success, tokens are persisted and state becomes [AuthStatus.authenticated].
  /// On failure or user-cancel, [IOidcClient.login] rethrows; state becomes
  /// [AuthStatus.unauthenticated] so the router can redirect to the login screen.
  Future<void> login() async {
    try {
      final tokens = await _oidc.login();
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        idToken: tokens.idToken,
        accessTokenExpiry: tokens.accessTokenExpiry,
      );
      state = AuthStatus.authenticated;
    } catch (_) {
      state = AuthStatus.unauthenticated;
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------

  /// Logs the user out.
  ///
  /// Sends an RP-initiated end-session request (best-effort — errors are
  /// swallowed so a network failure never blocks local sign-out), then clears
  /// persisted tokens and transitions to [AuthStatus.unauthenticated].
  ///
  /// TODO(P3b-T9): hook cache purge here before `_store.clear()`.
  Future<void> logout() async {
    final idToken = await _store.readIdToken();
    try {
      await _oidc.endSession(idToken: idToken ?? '');
    } catch (_) {
      // Best-effort: a failed end-session must not block local sign-out.
    }
    await _store.clear();
    state = AuthStatus.unauthenticated;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Exposes [AuthStatus] for router guards and UI.
///
/// Router guards (T5) listen to this provider to redirect unauthenticated
/// users to the login screen.
final authStatusProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);
