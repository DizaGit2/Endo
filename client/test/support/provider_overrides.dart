// ---------------------------------------------------------------------------
// provider_overrides.dart — the common-case Riverpod scope (P4b-T3)
// ---------------------------------------------------------------------------
//
// Almost every widget test needs the same three seams pinned: auth status, the
// API client, and the cache store (which THROWS when read un-overridden, by
// design — see `hive_boot.dart`). [lumenOverrides] builds that list once.
//
// Feature-specific overrides (a controller, a repository) are appended by the
// caller, so this file never grows a dependency on a feature:
//
//   overrides: [
//     ...lumenOverrides(api: api),
//     profileControllerProvider.overrideWith(_Fake.new),
//   ],

import 'package:flutter_riverpod/misc.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/auth/token_store.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/network/api_client.dart';
import 'package:lumen/core/time/device_timezone.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Shared mock types (mocktail — the house mocking style; do not add a second)
// ---------------------------------------------------------------------------

class MockCacheStore extends Mock implements CacheStore {}

class MockTokenStore extends Mock implements TokenStore {}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// An [AuthController] pinned to one [AuthStatus], with no [TokenStore] or
/// [IOidcClient] behind it.
///
/// `initialized` is always completed: it is a `late final` on the real
/// controller, so a fake that leaves it unset throws a
/// `LateInitializationError` the moment app-level code awaits it — which is
/// why half the pre-T3 fakes set it and half did not, depending on whether
/// their test happened to mount `LumenApp`.
class FakeAuthController extends AuthController {
  FakeAuthController(this._status);

  final AuthStatus _status;

  @override
  AuthStatus build() {
    initialized = Future<void>.value();
    return _status;
  }
}

/// A [CacheStore] that always misses and accepts every write — the "no cached
/// data" starting point a screen test almost always wants.
///
/// Reads return `null`, `isFresh` is false, so `cachedRead` always attempts the
/// network and its result is decided entirely by the fake API.
MockCacheStore emptyCacheStore() {
  // `any()` needs a fallback for the non-nullable Map argument of putJson.
  // registerFallbackValue is idempotent, so calling it per-store is safe.
  registerFallbackValue(<String, dynamic>{});

  final store = MockCacheStore();
  when(() => store.isFresh(any())).thenReturn(false);
  when(() => store.getJson(any())).thenReturn(null);
  when(
    () => store.putJson(any(), any(), ttl: any(named: 'ttl')),
  ).thenAnswer((_) async {});
  when(() => store.invalidate(any())).thenAnswer((_) async {});
  when(() => store.purge()).thenAnswer((_) async {});
  // A constant stamp: this store is never invalidated or purged mid-test, so
  // `cachedRead` sees every pending read as still current (hive_boot.dart's
  // `versionOf`).
  when(() => store.versionOf(any())).thenReturn((purge: 0, key: 0));
  return store;
}

/// A [TokenStore] holding no session — reads return `null`, `clear()` is a
/// no-op. Enough for any screen test that does not assert on token IO.
MockTokenStore emptyTokenStore() {
  final store = MockTokenStore();
  when(() => store.readAccessToken()).thenAnswer((_) async => null);
  when(() => store.readRefreshToken()).thenAnswer((_) async => null);
  when(() => store.readIdToken()).thenAnswer((_) async => null);
  when(() => store.readAccessTokenExpiry()).thenAnswer((_) async => null);
  when(() => store.hasValidSession()).thenAnswer((_) async => false);
  when(() => store.clear()).thenAnswer((_) async {});
  return store;
}

// ---------------------------------------------------------------------------
// The override list
// ---------------------------------------------------------------------------

/// Overrides for the seams every screen test shares.
///
/// Nothing is overridden unless it is asked for, except two seams that are
/// always pinned:
///  * [authStatusProvider] — the real one reaches for `FlutterSecureStorage`
///    and a live OIDC client on its first build;
///  * [deviceTimezoneProvider] — the real one asks a platform channel, and a
///    channel with no handler NEVER answers inside a widget test (it does not
///    fail, it hangs — and under `testWidgets`'s fake clock no timeout fires
///    either). The onboarding gate awaits it before opening (D1 / D-12), so an
///    unpinned test that reaches the gate would hang forever. [deviceTimezone]
///    defaults to `null` — "the device will not say" — which is also the value
///    that keeps every test that is not about the zone sync from having to
///    stub `PATCH /me`.
///
/// ```dart
/// await pumpApp(
///   tester,
///   home: const ProfileScreen(),
///   overrides: [
///     ...lumenOverrides(api: api, cacheStore: emptyCacheStore()),
///     profileControllerProvider.overrideWith(_FreshProfile.new),
///   ],
/// );
/// ```
List<Override> lumenOverrides({
  AuthStatus auth = AuthStatus.authenticated,
  LumenApiApi? api,
  CacheStore? cacheStore,
  TokenStore? tokenStore,
  String? deviceTimezone,
}) {
  return <Override>[
    authStatusProvider.overrideWith(() => FakeAuthController(auth)),
    deviceTimezoneProvider.overrideWith((_) async => deviceTimezone),
    if (api != null) lumenApiProvider.overrideWithValue(api),
    if (cacheStore != null) cacheStoreProvider.overrideWithValue(cacheStore),
    if (tokenStore != null) tokenStoreProvider.overrideWithValue(tokenStore),
  ];
}
