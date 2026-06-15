// Tests for AuthController.
//
// AppAuthOidcClient (the real flutter_appauth wrapper) is deliberately NOT
// tested here — it exercises platform channels and must be verified live at T10.
// A brief comment in oidc_client.dart notes this.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/auth/oidc_client.dart';
import 'package:lumen/core/auth/token_store.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockIOidcClient extends Mock implements IOidcClient {}

class MockTokenStore extends Mock implements TokenStore {}

class MockCacheStore extends Mock implements CacheStore {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a fresh [ProviderContainer] with mocked [IOidcClient], [TokenStore],
/// and [CacheStore].
ProviderContainer makeContainer({
  required MockIOidcClient oidc,
  required MockTokenStore store,
  MockCacheStore? cache,
}) {
  return ProviderContainer(
    overrides: [
      oidcClientProvider.overrideWithValue(oidc),
      tokenStoreProvider.overrideWithValue(store),
      if (cache != null) cacheStoreProvider.overrideWithValue(cache),
    ],
  );
}

/// A sample [OidcTokens] for use in tests.
OidcTokens fakeTokens({
  String accessToken = 'at',
  String refreshToken = 'rt',
  String idToken = 'it',
  DateTime? accessTokenExpiry,
}) =>
    OidcTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      accessTokenExpiry: accessTokenExpiry ?? DateTime.utc(2099, 1, 1),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Register fallback values for any() matchers on custom types.
  setUpAll(() {
    registerFallbackValue(fakeTokens());
    registerFallbackValue(DateTime.utc(2099));
  });

  late MockIOidcClient oidc;
  late MockTokenStore store;
  late MockCacheStore cache;

  setUp(() {
    oidc = MockIOidcClient();
    store = MockTokenStore();
    cache = MockCacheStore();
  });

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  group('AuthController init', () {
    test('sets authenticated when hasValidSession is true', () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => true);

      final container = makeContainer(oidc: oidc, store: store);
      addTearDown(container.dispose);

      // Allow async init to complete.
      await container.read(authStatusProvider.notifier).initialized;

      expect(container.read(authStatusProvider), AuthStatus.authenticated);
    });

    test('sets unauthenticated when hasValidSession is false', () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => false);

      final container = makeContainer(oidc: oidc, store: store);
      addTearDown(container.dispose);

      await container.read(authStatusProvider.notifier).initialized;

      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });

    test('falls back to unauthenticated when hasValidSession throws', () async {
      // e.g. an Android keystore / iOS keychain read failure. flutter_secure_storage
      // rejects its Future asynchronously, so model the error that way. The app
      // must NOT be stranded at AuthStatus.unknown (which pins every route to
      // /splash with no recovery).
      when(() => store.hasValidSession())
          .thenAnswer((_) async => throw Exception('keystore unavailable'));

      final container = makeContainer(oidc: oidc, store: store);
      addTearDown(container.dispose);

      // initialized must complete normally (not rethrow).
      await container.read(authStatusProvider.notifier).initialized;

      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });
  });

  // -------------------------------------------------------------------------
  // login()
  // -------------------------------------------------------------------------

  group('AuthController.login()', () {
    test('on success: saves all token fields and state becomes authenticated',
        () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => false);
      when(() => store.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            idToken: any(named: 'idToken'),
            accessTokenExpiry: any(named: 'accessTokenExpiry'),
          )).thenAnswer((_) async {});

      final expiry = DateTime.utc(2099, 6, 1);
      final tokens = fakeTokens(
        accessToken: 'at-ok',
        refreshToken: 'rt-ok',
        idToken: 'id-ok',
        accessTokenExpiry: expiry,
      );
      when(() => oidc.login()).thenAnswer((_) async => tokens);

      final container = makeContainer(oidc: oidc, store: store);
      addTearDown(container.dispose);

      await container.read(authStatusProvider.notifier).initialized;
      await container.read(authStatusProvider.notifier).login();

      // Verify saveTokens was called with the correct fields.
      verify(
        () => store.saveTokens(
          accessToken: 'at-ok',
          refreshToken: 'rt-ok',
          idToken: 'id-ok',
          accessTokenExpiry: expiry,
        ),
      ).called(1);

      expect(container.read(authStatusProvider), AuthStatus.authenticated);
    });

    test('on oidc failure: state is unauthenticated and error is rethrown',
        () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => false);
      when(() => oidc.login()).thenThrow(Exception('auth cancelled'));

      final container = makeContainer(oidc: oidc, store: store);
      addTearDown(container.dispose);

      await container.read(authStatusProvider.notifier).initialized;

      await expectLater(
        () => container.read(authStatusProvider.notifier).login(),
        throwsA(isA<Exception>()),
      );

      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });
  });

  // -------------------------------------------------------------------------
  // logout()
  // -------------------------------------------------------------------------

  group('AuthController.logout()', () {
    test(
        'calls endSession with stored idToken, then clear; state → unauthenticated',
        () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => true);
      when(() => store.readIdToken()).thenAnswer((_) async => 'id-tok');
      when(() => oidc.endSession(idToken: any(named: 'idToken')))
          .thenAnswer((_) async {});
      when(() => store.clear()).thenAnswer((_) async {});
      when(() => cache.purge()).thenAnswer((_) async => 0);

      final container = makeContainer(oidc: oidc, store: store, cache: cache);
      addTearDown(container.dispose);

      await container.read(authStatusProvider.notifier).initialized;
      await container.read(authStatusProvider.notifier).logout();

      verify(() => oidc.endSession(idToken: 'id-tok')).called(1);
      verify(() => store.clear()).called(1);
      verify(() => cache.purge()).called(1);
      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });

    test(
        'if endSession throws, clear and purge still run and state is unauthenticated',
        () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => true);
      when(() => store.readIdToken()).thenAnswer((_) async => 'id-tok');
      when(() => oidc.endSession(idToken: any(named: 'idToken')))
          .thenThrow(Exception('network error'));
      when(() => store.clear()).thenAnswer((_) async {});
      when(() => cache.purge()).thenAnswer((_) async => 0);

      final container = makeContainer(oidc: oidc, store: store, cache: cache);
      addTearDown(container.dispose);

      await container.read(authStatusProvider.notifier).initialized;
      await container.read(authStatusProvider.notifier).logout();

      // clear and purge must have run despite endSession throwing.
      verify(() => store.clear()).called(1);
      verify(() => cache.purge()).called(1);
      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });

    test(
        'if purge throws, logout still completes and state is unauthenticated',
        () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => true);
      when(() => store.readIdToken()).thenAnswer((_) async => 'id-tok');
      when(() => oidc.endSession(idToken: any(named: 'idToken')))
          .thenAnswer((_) async {});
      when(() => store.clear()).thenAnswer((_) async {});
      when(() => cache.purge()).thenThrow(Exception('purge error'));

      final container = makeContainer(oidc: oidc, store: store, cache: cache);
      addTearDown(container.dispose);

      await container.read(authStatusProvider.notifier).initialized;
      // Must NOT throw — purge failure is best-effort.
      await container.read(authStatusProvider.notifier).logout();

      verify(() => store.clear()).called(1);
      // State is still unauthenticated even though purge threw.
      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });

    test('completes and reaches unauthenticated even if readIdToken throws',
        () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => true);
      when(() => store.readIdToken())
          .thenThrow(Exception('keystore read failed'));
      when(() => store.clear()).thenAnswer((_) async {});
      when(() => cache.purge()).thenAnswer((_) async => 0);

      final container = makeContainer(oidc: oidc, store: store, cache: cache);
      addTearDown(container.dispose);

      await container.read(authStatusProvider.notifier).initialized;
      // Must NOT throw even though reading the id token failed.
      await container.read(authStatusProvider.notifier).logout();

      verify(() => store.clear()).called(1);
      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });

    test('completes and reaches unauthenticated even if clear() throws',
        () async {
      when(() => store.hasValidSession()).thenAnswer((_) async => true);
      when(() => store.readIdToken()).thenAnswer((_) async => 'id-tok');
      when(() => oidc.endSession(idToken: any(named: 'idToken')))
          .thenAnswer((_) async {});
      when(() => store.clear()).thenThrow(Exception('keystore delete failed'));
      when(() => cache.purge()).thenAnswer((_) async => 0);

      final container = makeContainer(oidc: oidc, store: store, cache: cache);
      addTearDown(container.dispose);

      await container.read(authStatusProvider.notifier).initialized;
      // Must NOT throw even though clear() failed.
      await container.read(authStatusProvider.notifier).logout();

      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });
  });
}
