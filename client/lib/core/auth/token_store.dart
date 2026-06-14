import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// Private key constants
// ---------------------------------------------------------------------------

const _kAccessToken = 'access_token';
const _kRefreshToken = 'refresh_token';
const _kIdToken = 'id_token';
const _kAccessTokenExpiry = 'access_token_expiry';

// ---------------------------------------------------------------------------
// Default storage instance
// ---------------------------------------------------------------------------

// AndroidOptions() uses v10's modern cipher defaults. Its default
// resetOnError:true means a corrupted Android keystore (OS upgrade, certain
// backup/restore cases) silently clears stored data — acceptable here: the user
// simply re-authenticates (the server-held DEK means no data is lost on re-login).
const _defaultStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

// ---------------------------------------------------------------------------
// TokenStore
// ---------------------------------------------------------------------------

/// Persists OIDC tokens in the platform keychain/keystore via
/// [FlutterSecureStorage].
///
/// Inject [storage] in tests; production code uses the secure default.
class TokenStore {
  final FlutterSecureStorage _storage;

  TokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? _defaultStorage;

  // -------------------------------------------------------------------------
  // Write
  // -------------------------------------------------------------------------

  /// Writes all four token fields (sequentially — the platform API has no batch
  /// write, so a process kill mid-save can leave a partial set; callers treat a
  /// missing/!hasValidSession state as logged-out and re-authenticate).
  ///
  /// [accessTokenExpiry] is stored as an ISO-8601 UTC string.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String idToken,
    required DateTime accessTokenExpiry,
  }) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
    await _storage.write(key: _kIdToken, value: idToken);
    await _storage.write(
      key: _kAccessTokenExpiry,
      value: accessTokenExpiry.toUtc().toIso8601String(),
    );
  }

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Returns the stored access token, or null if absent.
  Future<String?> readAccessToken() => _storage.read(key: _kAccessToken);

  /// Returns the stored refresh token, or null if absent.
  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  /// Returns the stored ID token, or null if absent.
  Future<String?> readIdToken() => _storage.read(key: _kIdToken);

  /// Returns the stored access token expiry parsed from ISO-8601 (UTC), or
  /// null when absent or unparseable.
  Future<DateTime?> readAccessTokenExpiry() async {
    final raw = await _storage.read(key: _kAccessTokenExpiry);
    if (raw == null) return null;
    try {
      return DateTime.parse(raw).toUtc();
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Session check
  // -------------------------------------------------------------------------

  /// Returns true if a non-empty refresh token is stored.
  ///
  /// The access token may be expired; the refresh token is used to obtain
  /// a new one. Callers should not rely on the access token being valid.
  Future<bool> hasValidSession() async {
    final token = await _storage.read(key: _kRefreshToken);
    return token != null && token.isNotEmpty;
  }

  // -------------------------------------------------------------------------
  // Clear
  // -------------------------------------------------------------------------

  /// Deletes the four token keys individually.
  ///
  /// Does NOT call [FlutterSecureStorage.deleteAll] so unrelated keychain
  /// entries (e.g., biometric keys) are untouched.
  Future<void> clear() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kIdToken);
    await _storage.delete(key: _kAccessTokenExpiry);
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Provides the singleton [TokenStore] for the app.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
