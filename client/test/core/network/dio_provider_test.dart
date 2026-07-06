// Tests for dioProvider.
//
// The online-only / stale-while-revalidate design depends on the network call
// eventually failing with a Dio timeout so cachedRead can fall back to cache.
// Because a pre-built Dio is handed to the generated client, the generator's
// default timeouts are bypassed — so the shared Dio MUST set its own.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/auth/oidc_client.dart';
import 'package:lumen/core/auth/token_store.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/network/dio_provider.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockIOidcClient extends Mock implements IOidcClient {}

class MockTokenStore extends Mock implements TokenStore {}

class MockCacheStore extends Mock implements CacheStore {}

// ---------------------------------------------------------------------------
// A minimal HttpClientAdapter that always answers 401 (unauthorized)
// ---------------------------------------------------------------------------

/// Since the refresh in the tests below always fails, only the original
/// request ever reaches the adapter (AuthInterceptor never gets to retry),
/// so a fixed 401 response is all that's needed here.
class _Always401Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"unauthorized"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ---------------------------------------------------------------------------
// Helpers — capture `print()` output without it reaching real stdout
// ---------------------------------------------------------------------------

/// Runs [body] inside a zone that redirects `print()` calls into a list of
/// captured lines instead of real stdout. [PiiSafeLogInterceptor] logs via
/// the top-level `print()` (guarded by `kDebugMode`, which is true under
/// `flutter test`), so this is how the tests observe what it would log
/// without polluting the test runner's console.
List<String> _capturePrints(void Function() body) {
  final captured = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => captured.add(line),
    ),
  );
  return captured;
}

void main() {
  test('shared Dio sets explicit connect and receive timeouts', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dio = container.read(dioProvider);

    expect(dio.options.connectTimeout, isNotNull,
        reason: 'a hung connect must time out, not hang forever');
    expect(dio.options.receiveTimeout, isNotNull,
        reason: 'a server that never responds must time out so SWR can fall '
            'back to cache');
    expect(dio.options.connectTimeout! > Duration.zero, isTrue);
    expect(dio.options.receiveTimeout! > Duration.zero, isTrue);
  });

  test('base URL comes from the LUMEN_API_BASE dart-define (emulator default)',
      () {
    // Same key + default as production: equal with no --dart-define (both the
    // emulator default), and equal under a --dart-define override ONLY if the
    // shared Dio actually reads the key. Run with
    //   flutter test --dart-define=LUMEN_API_BASE=http://host:port
    // to prove the override propagates.
    const expected = String.fromEnvironment(
      'LUMEN_API_BASE',
      defaultValue: 'http://10.0.2.2:8085',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(dioProvider).options.baseUrl, expected);
  });

  // -------------------------------------------------------------------------
  // PiiSafeLogInterceptor — PII redaction (P3c-T12)
  // -------------------------------------------------------------------------
  //
  // Exercised directly against the interceptor (not through a full Dio
  // pipeline): onRequest/onResponse/onError are plain synchronous `void`
  // methods that print, then call `handler.next(...)`, so calling them
  // directly with a throwaway handler is enough to observe the logging
  // side-effect deterministically.

  group('PiiSafeLogInterceptor — PII redaction', () {
    test('an Authorization header value never appears in captured output',
        () {
      final interceptor = PiiSafeLogInterceptor();
      final options = RequestOptions(
        path: '/health', // non-sensitive: headers ARE logged unless redacted
        method: 'GET',
        headers: const {'Authorization': 'Bearer super-secret-token'},
      );

      final lines = _capturePrints(() {
        interceptor.onRequest(options, RequestInterceptorHandler());
      });
      final joined = lines.join('\n');

      expect(joined, isNot(contains('super-secret-token')));
      expect(joined, isNot(contains('Bearer')));
      // Sanity: the line was still logged, just without the header value.
      expect(joined, contains('GET'));
      expect(joined, contains('/health'));
    });

    test('sensitive request path (/onboarding/start) omits headers entirely',
        () {
      final interceptor = PiiSafeLogInterceptor();
      final options = RequestOptions(
        path: '/onboarding/start',
        method: 'POST',
        headers: const {
          'Authorization': 'Bearer secret',
          'X-Trace-Id': 'trace-abc-123',
        },
      );

      final lines = _capturePrints(() {
        interceptor.onRequest(options, RequestInterceptorHandler());
      });
      final joined = lines.join('\n');

      expect(joined, isNot(contains('headers=')));
      expect(joined, isNot(contains('trace-abc-123')));
      // Sanity: method + path are still logged for a sensitive path.
      expect(joined, contains('POST'));
      expect(joined, contains('/onboarding/start'));
    });

    test('sensitive response path (/me) omits the response body from output',
        () {
      final interceptor = PiiSafeLogInterceptor();
      final requestOptions = RequestOptions(path: '/me', method: 'GET');
      final response = Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 200,
        data: const {'ssn': 'do-not-leak-me', 'displayName': 'María'},
      );

      final lines = _capturePrints(() {
        interceptor.onResponse(response, ResponseInterceptorHandler());
      });
      final joined = lines.join('\n');

      expect(joined, isNot(contains('do-not-leak-me')));
      expect(joined, isNot(contains('data=')));
      // Sanity: status/method/path are still logged for a sensitive path.
      expect(joined, contains('200'));
      expect(joined, contains('/me'));
    });

    test('non-sensitive path still logs method + path (sanity check)', () {
      final interceptor = PiiSafeLogInterceptor();
      final options = RequestOptions(path: '/health', method: 'GET');

      final lines = _capturePrints(() {
        interceptor.onRequest(options, RequestInterceptorHandler());
      });

      expect(lines, isNotEmpty);
      expect(lines.join('\n'), contains('GET'));
      expect(lines.join('\n'), contains('/health'));
    });

    test(
        'non-sensitive response path still logs the body (sanity: logging '
        'is not globally disabled)', () {
      final interceptor = PiiSafeLogInterceptor();
      final requestOptions = RequestOptions(path: '/health', method: 'GET');
      final response = Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 200,
        data: const {'status': 'ok'},
      );

      final lines = _capturePrints(() {
        interceptor.onResponse(response, ResponseInterceptorHandler());
      });

      expect(lines.join('\n'), contains('data='));
    });
  });

  // -------------------------------------------------------------------------
  // dioProvider — onAuthLost wiring (P3c-T12)
  // -------------------------------------------------------------------------
  //
  // dioProvider wires AuthInterceptor's onAuthLost callback to
  // `authStatusProvider.notifier.logout()` (fire-and-forget). This proves the
  // end-to-end wiring: a 401 whose refresh fails must clear tokens and drive
  // authStatusProvider to unauthenticated — not just that AuthInterceptor or
  // AuthController individually behave (already covered by
  // auth_interceptor_test.dart / auth_controller_test.dart).

  group('dioProvider — onAuthLost wiring', () {
    test(
      '401 with a failing refresh clears tokens and drives authStatusProvider '
      'to unauthenticated',
      () async {
        final oidc = MockIOidcClient();
        final store = MockTokenStore();
        final cache = MockCacheStore();

        when(() => store.hasValidSession()).thenAnswer((_) async => true);
        when(() => store.readAccessTokenExpiry())
            .thenAnswer((_) async => DateTime.utc(2099, 1, 1));
        when(() => store.readAccessToken()).thenAnswer((_) async => 'old-at');
        when(() => store.readRefreshToken()).thenAnswer((_) async => 'rt');
        when(() => store.readIdToken()).thenAnswer((_) async => null);
        when(() => store.clear()).thenAnswer((_) async {});
        when(() => cache.purge()).thenAnswer((_) async => 0);
        when(() => oidc.refresh(any()))
            .thenThrow(Exception('token server unreachable'));

        final container = ProviderContainer(
          overrides: [
            tokenStoreProvider.overrideWithValue(store),
            oidcClientProvider.overrideWithValue(oidc),
            cacheStoreProvider.overrideWithValue(cache),
          ],
        );
        addTearDown(container.dispose);

        // Establish an authenticated baseline so the transition is observable.
        await container.read(authStatusProvider.notifier).initialized;
        expect(container.read(authStatusProvider), AuthStatus.authenticated);

        // The onAuthLost -> logout() call is fire-and-forget (unawaited), so
        // observe the eventual state transition via a listener instead of
        // assuming it has landed by the time dio.get() rejects.
        final becameUnauthenticated = Completer<void>();
        container.listen<AuthStatus>(authStatusProvider, (previous, next) {
          if (next == AuthStatus.unauthenticated) {
            becameUnauthenticated.complete();
          }
        });

        final dio = container.read(dioProvider);
        dio.httpClientAdapter = _Always401Adapter();

        await expectLater(
          () => dio.get<void>('/api/data'),
          throwsA(isA<DioException>()),
        );

        await becameUnauthenticated.future.timeout(const Duration(seconds: 5));

        // Tokens cleared: AuthInterceptor clears on refresh failure, and
        // AuthController.logout() clears again — either way, "at least once"
        // proves the DioException actually drove a clear, not just a reject.
        verify(() => store.clear()).called(greaterThanOrEqualTo(1));
        expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
      },
    );
  });
}
