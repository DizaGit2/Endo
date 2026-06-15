// Tests for AuthInterceptor.
//
// Strategy:
//   - Real Dio with a SequentialAdapter (custom HttpClientAdapter) that returns
//     a pre-configured list of responses in order — allows 401→200 retry tests.
//   - Mock TokenStore (mocktail) to control stored tokens.
//   - Header-capturing interceptor appended after AuthInterceptor.
//   - Injectable clock for proactive-refresh window tests.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_interceptor.dart';
import 'package:lumen/core/auth/oidc_client.dart';
import 'package:lumen/core/auth/token_store.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockTokenStore extends Mock implements TokenStore {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _baseUrl = 'http://test.local';

/// Fresh [OidcTokens] for use in tests.
OidcTokens freshTokens({
  String accessToken = 'new-at',
  String refreshToken = 'new-rt',
  String idToken = 'new-it',
}) =>
    OidcTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      accessTokenExpiry: DateTime.utc(2099, 1, 1),
    );

// ---------------------------------------------------------------------------
// Sequential mock HTTP adapter
// ---------------------------------------------------------------------------

/// A minimal [HttpClientAdapter] that serves canned responses in order.
///
/// Each call to [fetch] pops the next [MockEntry] from the queue.
/// If the queue is exhausted, returns 200 with empty body.
class SequentialAdapter implements HttpClientAdapter {
  final List<MockEntry> _queue;

  SequentialAdapter(this._queue);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future? cancelFuture,
  ) async {
    final entry = _queue.isNotEmpty ? _queue.removeAt(0) : MockEntry(200, '{}');
    return ResponseBody.fromString(
      entry.body,
      entry.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class MockEntry {
  MockEntry(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

// Convenience entry constructors.
MockEntry ok([String body = '{}']) => MockEntry(200, body);
MockEntry unauthorized() => MockEntry(401, '{"error":"unauthorized"}');

// ---------------------------------------------------------------------------
// Header-capturing interceptor
// ---------------------------------------------------------------------------

/// Captures every outgoing request's Authorization header before it reaches
/// the adapter. Added AFTER [AuthInterceptor] in the chain.
class HeaderCapture extends Interceptor {
  final List<String?> captured = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    captured.add(options.headers['Authorization'] as String?);
    handler.next(options);
  }
}

// ---------------------------------------------------------------------------
// Test setup helper
// ---------------------------------------------------------------------------

typedef Env = ({
  Dio dio,
  MockTokenStore store,
  AuthInterceptor interceptor,
  HeaderCapture capture,
  SequentialAdapter adapter,
});

// ignore: library_private_types_in_public_api
Env buildDio({
  required List<MockEntry> responses,
  required Future<OidcTokens> Function(String) refreshFn,
  required void Function() onAuthLost,
  DateTime Function()? clock,
  MockTokenStore? tokenStore,
}) {
  final store = tokenStore ?? MockTokenStore();
  final dio = Dio(BaseOptions(baseUrl: _baseUrl));
  final capture = HeaderCapture();
  final interceptor = AuthInterceptor(
    tokenStore: store,
    refresh: refreshFn,
    onAuthLost: onAuthLost,
    clock: clock,
  );
  interceptor.dio = dio;

  // Order: AuthInterceptor → capture → (adapter handles fetch).
  dio.interceptors.add(interceptor);
  dio.interceptors.add(capture);

  final adapter = SequentialAdapter(responses);
  dio.httpClientAdapter = adapter;

  return (
    dio: dio,
    store: store,
    interceptor: interceptor,
    capture: capture,
    adapter: adapter,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime.utc(2099));
  });

  // -------------------------------------------------------------------------
  // 1. Bearer header attached from stored token
  // -------------------------------------------------------------------------

  group('onRequest: bearer token attachment', () {
    test('attaches Authorization: Bearer header from stored access token',
        () async {
      final env = buildDio(
        responses: [ok()],
        refreshFn: (_) async => freshTokens(),
        onAuthLost: () {},
      );

      when(() => env.store.readAccessTokenExpiry())
          .thenAnswer((_) async => DateTime.utc(2099, 1, 1));
      when(() => env.store.readAccessToken()).thenAnswer((_) async => 'my-at');

      await env.dio.get('/api/data');

      expect(env.capture.captured.last, 'Bearer my-at');
    });

    test('no Authorization header when no stored token (public endpoint)',
        () async {
      final env = buildDio(
        responses: [ok()],
        refreshFn: (_) async => freshTokens(),
        onAuthLost: () {},
      );

      when(() => env.store.readAccessTokenExpiry()).thenAnswer((_) async => null);
      when(() => env.store.readAccessToken()).thenAnswer((_) async => null);

      await env.dio.get('/health');

      expect(
        env.capture.captured.last,
        isNull,
        reason: 'Public endpoints must not receive an Authorization header',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 2. Proactive refresh (access token near expiry)
  // -------------------------------------------------------------------------

  group('onRequest: proactive refresh within 30 s window', () {
    test('refreshes before request when token expires within 30 s', () async {
      var refreshCalled = false;

      // Clock fixed at T=0; token expires at T+20 s (inside 30 s threshold).
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final nearExpiry = now.add(const Duration(seconds: 20));
      DateTime clock() => now;

      final env = buildDio(
        responses: [ok()],
        refreshFn: (rt) async {
          refreshCalled = true;
          return freshTokens(accessToken: 'proactive-at');
        },
        onAuthLost: () {},
        clock: clock,
      );

      when(() => env.store.readAccessTokenExpiry())
          .thenAnswer((_) async => nearExpiry);
      when(() => env.store.readRefreshToken()).thenAnswer((_) async => 'rt-old');
      when(() => env.store.readAccessToken())
          .thenAnswer((_) async => 'proactive-at');
      when(
        () => env.store.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          idToken: any(named: 'idToken'),
          accessTokenExpiry: any(named: 'accessTokenExpiry'),
        ),
      ).thenAnswer((_) async {});

      await env.dio.get('/api/data');

      expect(refreshCalled, isTrue, reason: 'Proactive refresh must be called');
      expect(env.capture.captured.last, 'Bearer proactive-at');
    });

    test('does NOT refresh when token is not near expiry (10 min remaining)',
        () async {
      var refreshCalled = false;

      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final farExpiry = now.add(const Duration(minutes: 10));
      DateTime clock() => now;

      final env = buildDio(
        responses: [ok()],
        refreshFn: (rt) async {
          refreshCalled = true;
          return freshTokens();
        },
        onAuthLost: () {},
        clock: clock,
      );

      when(() => env.store.readAccessTokenExpiry())
          .thenAnswer((_) async => farExpiry);
      when(() => env.store.readAccessToken()).thenAnswer((_) async => 'valid-at');

      await env.dio.get('/api/data');

      expect(refreshCalled, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // 3. Reactive refresh: 401 → refresh success → retry returns 200
  // -------------------------------------------------------------------------

  group('onError: 401 reactive refresh', () {
    test('401 → refresh → retry once → 200 returned to caller', () async {
      var refreshCalled = 0;

      final env = buildDio(
        // First request gets 401; retry gets 200.
        responses: [unauthorized(), ok('{"data":"ok"}')],
        refreshFn: (rt) async {
          refreshCalled++;
          return freshTokens(accessToken: 'refreshed-at');
        },
        onAuthLost: () {},
      );

      when(() => env.store.readAccessTokenExpiry())
          .thenAnswer((_) async => DateTime.utc(2099));
      when(() => env.store.readAccessToken()).thenAnswer((_) async => 'old-at');
      when(() => env.store.readRefreshToken()).thenAnswer((_) async => 'rt');
      when(
        () => env.store.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          idToken: any(named: 'idToken'),
          accessTokenExpiry: any(named: 'accessTokenExpiry'),
        ),
      ).thenAnswer((_) async {});

      final response = await env.dio.get('/api/data');

      expect(response.statusCode, 200);
      expect(refreshCalled, 1, reason: 'Exactly one refresh');
    });

    test('saveTokens is called with the refreshed tokens on 401 recovery',
        () async {
      final env = buildDio(
        responses: [unauthorized(), ok()],
        refreshFn: (_) async => freshTokens(
          accessToken: 'new-at',
          refreshToken: 'new-rt',
          idToken: 'new-it',
        ),
        onAuthLost: () {},
      );

      when(() => env.store.readAccessTokenExpiry())
          .thenAnswer((_) async => DateTime.utc(2099));
      when(() => env.store.readAccessToken()).thenAnswer((_) async => 'old-at');
      when(() => env.store.readRefreshToken()).thenAnswer((_) async => 'rt');
      when(
        () => env.store.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          idToken: any(named: 'idToken'),
          accessTokenExpiry: any(named: 'accessTokenExpiry'),
        ),
      ).thenAnswer((_) async {});

      await env.dio.get('/api/data');

      verify(
        () => env.store.saveTokens(
          accessToken: 'new-at',
          refreshToken: 'new-rt',
          idToken: 'new-it',
          accessTokenExpiry: any(named: 'accessTokenExpiry'),
        ),
      ).called(1);
    });

    test('retry sends the bearer read from the store (single source of truth)',
        () async {
      var readCount = 0;
      final env = buildDio(
        responses: [unauthorized(), ok()],
        // refresh() returns a DIFFERENT token than what the store yields on
        // retry — proving the retry's bearer comes from the store (which
        // _performRefresh persists), not from this return value.
        refreshFn: (_) async => freshTokens(accessToken: 'returned-at'),
        onAuthLost: () {},
      );

      when(() => env.store.readAccessTokenExpiry())
          .thenAnswer((_) async => DateTime.utc(2099));
      when(() => env.store.readAccessToken()).thenAnswer((_) async {
        readCount++;
        return readCount == 1 ? 'old-at' : 'persisted-at';
      });
      when(() => env.store.readRefreshToken()).thenAnswer((_) async => 'rt');
      when(
        () => env.store.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          idToken: any(named: 'idToken'),
          accessTokenExpiry: any(named: 'accessTokenExpiry'),
        ),
      ).thenAnswer((_) async {});

      await env.dio.get('/api/data');

      // The retry carries the store's current token, NOT refresh()'s return.
      expect(env.capture.captured.last, 'Bearer persisted-at');
    });
  });

  // -------------------------------------------------------------------------
  // 4. Single-flight: N concurrent 401s → exactly ONE refresh call
  // -------------------------------------------------------------------------

  group('single-flight: concurrent 401s trigger exactly one refresh', () {
    test('3 concurrent requests all 401 → refresh called once, all succeed',
        () async {
      // The refresh function uses a Completer so it stays in-flight while all
      // 3 requests' onError handlers are queued. Only one call to _performRefresh
      // should occur; the others should join the same Future.
      final refreshCompleter = Completer<OidcTokens>();
      var refreshCallCount = 0;

      // 3 requests × (401 + 200 retry) = 6 responses in order.
      final env = buildDio(
        responses: [
          unauthorized(), // /a → 401
          unauthorized(), // /b → 401
          unauthorized(), // /c → 401
          ok(), // /a retry → 200
          ok(), // /b retry → 200
          ok(), // /c retry → 200
        ],
        refreshFn: (rt) async {
          refreshCallCount++;
          // Stay pending so all concurrent onError handlers call _doRefresh
          // before we complete — proving they share the inflight future.
          return refreshCompleter.future;
        },
        onAuthLost: () {},
      );

      when(() => env.store.readAccessTokenExpiry())
          .thenAnswer((_) async => DateTime.utc(2099));
      when(() => env.store.readAccessToken()).thenAnswer((_) async => 'old-at');
      when(() => env.store.readRefreshToken()).thenAnswer((_) async => 'rt');
      when(
        () => env.store.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
          idToken: any(named: 'idToken'),
          accessTokenExpiry: any(named: 'accessTokenExpiry'),
        ),
      ).thenAnswer((_) async {});

      // Fire all three requests concurrently.
      final futures = [
        env.dio.get('/a'),
        env.dio.get('/b'),
        env.dio.get('/c'),
      ];

      // Give the event loop several turns so all 3 requests hit the adapter,
      // get 401, and call _doRefresh() — at which point they all wait on the
      // same Completer-backed Future (single-flight).
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Now complete the single shared refresh.
      refreshCompleter.complete(freshTokens(accessToken: 'shared-at'));

      final responses = await Future.wait(futures);

      expect(
        refreshCallCount,
        1,
        reason: 'Single-flight: refresh must be called exactly once',
      );
      for (final r in responses) {
        expect(r.statusCode, 200);
      }
    });
  });

  // -------------------------------------------------------------------------
  // 5. Refresh failure → tokens cleared, onAuthLost called
  // -------------------------------------------------------------------------

  group('onError: refresh failure handling', () {
    test(
      'refresh throws → clear() called, onAuthLost invoked, DioException thrown',
      () async {
        var authLostCalled = false;

        final env = buildDio(
          responses: [unauthorized()],
          refreshFn: (_) async => throw Exception('Token server down'),
          onAuthLost: () {
            authLostCalled = true;
          },
        );

        when(() => env.store.readAccessTokenExpiry())
            .thenAnswer((_) async => DateTime.utc(2099));
        when(() => env.store.readAccessToken()).thenAnswer((_) async => 'old-at');
        when(() => env.store.readRefreshToken()).thenAnswer((_) async => 'rt');
        when(() => env.store.clear()).thenAnswer((_) async {});

        await expectLater(
          () => env.dio.get('/api/data'),
          throwsA(
            isA<DioException>().having(
              (e) => e.error,
              'error',
              isA<AuthFailure>(),
            ),
          ),
        );

        verify(() => env.store.clear()).called(1);
        expect(authLostCalled, isTrue);
      },
    );

    test('no refresh token → clear() called, onAuthLost invoked', () async {
      var authLostCalled = false;

      final env = buildDio(
        responses: [unauthorized()],
        refreshFn: (_) async => freshTokens(),
        onAuthLost: () {
          authLostCalled = true;
        },
      );

      when(() => env.store.readAccessTokenExpiry())
          .thenAnswer((_) async => DateTime.utc(2099));
      when(() => env.store.readAccessToken()).thenAnswer((_) async => 'old-at');
      when(() => env.store.readRefreshToken()).thenAnswer((_) async => null);
      when(() => env.store.clear()).thenAnswer((_) async {});

      await expectLater(
        () => env.dio.get('/api/data'),
        throwsA(isA<DioException>()),
      );

      verify(() => env.store.clear()).called(1);
      expect(authLostCalled, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 6. No infinite loop: retried 401 does NOT trigger second refresh
  // -------------------------------------------------------------------------

  group('infinite-loop guard', () {
    test(
      'retried request returning 401 does NOT trigger another refresh',
      () async {
        var refreshCallCount = 0;

        // Both the original and retried request return 401.
        final env = buildDio(
          responses: [unauthorized(), unauthorized()],
          refreshFn: (rt) async {
            refreshCallCount++;
            return freshTokens(accessToken: 'after-refresh-at');
          },
          onAuthLost: () {},
        );

        when(() => env.store.readAccessTokenExpiry())
            .thenAnswer((_) async => DateTime.utc(2099));
        when(() => env.store.readAccessToken()).thenAnswer((_) async => 'old-at');
        when(() => env.store.readRefreshToken()).thenAnswer((_) async => 'rt');
        when(
          () => env.store.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            idToken: any(named: 'idToken'),
            accessTokenExpiry: any(named: 'accessTokenExpiry'),
          ),
        ).thenAnswer((_) async {});
        when(() => env.store.clear()).thenAnswer((_) async {});

        // Should fail (retried 401 is not re-refreshed) — throws DioException.
        await expectLater(
          () => env.dio.get('/api/data'),
          throwsA(isA<DioException>()),
        );

        expect(
          refreshCallCount,
          1,
          reason: 'Refresh must not be called again for the retried 401',
        );
      },
    );
  });
}
