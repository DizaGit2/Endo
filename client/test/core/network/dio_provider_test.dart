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
///
/// [body] MUST be synchronous — `print()` calls it schedules asynchronously
/// land after this returns and are not captured. This zone intercepts `print`
/// and NOTHING else: errors are left entirely alone, so a failing `expect`
/// inside [body] still fails its test.
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

/// An [ErrorInterceptorHandler] whose internal future is already observed.
///
/// `handler.next(err)` completes that future **with an error**. In production
/// the interceptor pipeline listens to it; a test driving `onError` directly is
/// the only caller that does not, so without this Dart reports an unhandled
/// async error and fails whichever test happens to be running when it lands.
///
/// dio marks the getter `@protected` (`_BaseHandler.future`) because the
/// pipeline is normally its only reader. Observing it here is strictly narrower
/// than the alternative — a `runZonedGuarded` around the capture would swallow
/// every async error in the zone, including ones a future test means to catch.
ErrorInterceptorHandler _observedErrorHandler() {
  final handler = ErrorInterceptorHandler();
  // ignore: invalid_use_of_protected_member
  handler.future.ignore();
  return handler;
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
      // /me is its own route identity with no parameter segment, so it is
      // logged in full — the server logs the same template.
      expect(joined, contains('/me'));
      expect(joined, contains('200'));
      expect(joined, contains('GET'));
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
  // PiiSafeLogInterceptor — endpoint identity is logged, values never (P4b-T4)
  // -------------------------------------------------------------------------
  //
  // The client mirrors the server's posture, which is NOT "never log the path":
  // Program.cs:244-259 logs the ROUTE TEMPLATE ("/cycle/day/{date}", or the
  // constant "(unrouted)") and PiiRedactionEnricher.cs:106-112 redacts the raw
  // RequestPath. So endpoint identity survives and parameter values do not.
  //
  // Every case drives onRequest, onResponse AND onError in one capture: onError
  // carried no sensitivity check at all before this task, so a fix covering
  // only onRequest must not be able to pass.

  group('PiiSafeLogInterceptor — endpoint identity is logged, values never', () {
    // (concrete path, the identity that must survive, the values that must
    //  not, whether the endpoint is body/header-sensitive)
    const cases = <(String, String, List<String>, bool)>[
      // ── parameterised paths: identity kept, value dropped ────────────────
      ('/cycle/day/2026-06-14', '/cycle/day/<redacted>', ['2026-06-14'], true),
      (
        '/cycle/events/3fa85f64-5717-4562-b3fc-2c963f66afa6',
        '/cycle/events/<redacted>',
        ['3fa85f64-5717-4562-b3fc-2c963f66afa6'],
        true,
      ),
      (
        '/symptoms/9c1e2d40-0000-4000-8000-000000000001',
        '/symptoms/<redacted>',
        ['9c1e2d40-0000-4000-8000-000000000001'],
        true,
      ),
      // ── un-parameterised health endpoints: identity IS the whole path ────
      ('/cycle/events', '/cycle/events', <String>[], true),
      ('/cycle/phase-override', '/cycle/phase-override', <String>[], true),
      ('/checkin/quick', '/checkin/quick', <String>[], true),
      ('/symptoms', '/symptoms', <String>[], true),
      ('/me', '/me', <String>[], true),
      ('/cycle/calendar', '/cycle/calendar', <String>[], true),
      ('/onboarding/start', '/onboarding/start', <String>[], true),
      // ── the over-redaction a prefix rule would cause ─────────────────────
      ('/me/devices', '/me/devices', <String>[], true),
      ('/settings/cycle', '/settings/cycle', <String>[], true),
      // ── the positive control: not health data, so the body IS logged ─────
      ('/health/ready', '/health/ready', <String>[], false),
    ];

    for (final (path, identity, secrets, sensitive) in cases) {
      test('$path logs as $identity', () {
        final interceptor = PiiSafeLogInterceptor();
        final options = RequestOptions(
          path: path,
          method: 'POST',
          headers: const {
            'Authorization': 'Bearer super-secret-token',
            'X-Trace-Id': 'trace-abc-123',
          },
          data: const {'notes': 'do-not-leak-me'},
        );
        final response = Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const {'notes': 'do-not-leak-me'},
        );
        final error = DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 400,
            data: const {'detail': 'do-not-leak-me'},
          ),
        );

        final lines = _capturePrints(() {
          interceptor.onRequest(options, RequestInterceptorHandler());
          interceptor.onResponse(response, ResponseInterceptorHandler());
          interceptor.onError(error, _observedErrorHandler());
        });
        final joined = lines.join('\n');

        // Identity survives — in all THREE lines, not just the first.
        for (final line in lines) {
          expect(line, contains(identity),
              reason: 'every hook must log the endpoint identity');
        }
        // …and no parameter value does.
        for (final secret in secrets) {
          expect(joined, isNot(contains(secret)),
              reason: 'a parameter value must never reach the console');
        }

        // Credentials are gone on EVERY path, health data or not.
        expect(joined, isNot(contains('super-secret-token')));
        expect(joined, isNot(contains('Bearer')));

        if (sensitive) {
          expect(joined, isNot(contains('do-not-leak-me')),
              reason: 'no body on a health-data path');
          expect(joined, isNot(contains('headers=')));
        } else {
          // The positive control: this row proves the assertions above are
          // about redaction, not about logging having been switched off.
          expect(joined, contains('do-not-leak-me'),
              reason: 'a non-sensitive endpoint still logs its body');
          expect(joined, contains('headers='));
        }

        // Not vacuous: three lines, carrying the method and both statuses.
        expect(lines, hasLength(3),
            reason: 'redaction must not become "log nothing"');
        expect(joined, contains('POST'));
        expect(joined, contains('200'));
        expect(joined, contains('400'));
      });
    }

    test('an unmatched path logs as (unrouted), never as itself', () {
      // The server's constant for a request that matched no endpoint. The
      // route table's failure mode is therefore over-redaction, not a leak —
      // which is the gap that let POST /cycle/events print in full.
      final interceptor = PiiSafeLogInterceptor();
      final options = RequestOptions(
        path: '/labs/studies/8f2c-secret',
        method: 'GET',
      );

      final lines = _capturePrints(() {
        interceptor.onRequest(options, RequestInterceptorHandler());
      });
      final joined = lines.join('\n');

      expect(joined, contains('(unrouted)'));
      expect(joined, isNot(contains('8f2c-secret')));
      expect(joined, isNot(contains('/labs')));
    });

    test('an (unrouted) path suppresses its body and headers by default', () {
      // The allowlist is `/health` and `/health/ready` and nothing else, and
      // `(unrouted)` is deliberately not in it. So an endpoint the route table
      // has never heard of — every surface P5 adds until someone updates the
      // table — is body-suppressed on the day it lands, rather than logging
      // pain scores in full until someone remembers a blocklist entry.
      final interceptor = PiiSafeLogInterceptor();
      final options = RequestOptions(
        path: '/insights/weekly',
        method: 'POST',
        headers: const {'X-Trace-Id': 'trace-abc-123'},
      );
      final response = Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {'painScore': 'do-not-leak-me'},
      );

      final lines = _capturePrints(() {
        interceptor.onRequest(options, RequestInterceptorHandler());
        interceptor.onResponse(response, ResponseInterceptorHandler());
      });
      final joined = lines.join('\n');

      expect(joined, isNot(contains('do-not-leak-me')));
      expect(joined, isNot(contains('data=')));
      expect(joined, isNot(contains('headers=')));
      expect(joined, isNot(contains('trace-abc-123')));
      // Not vacuous: both hooks still logged, under the unrouted constant.
      expect(lines, hasLength(2));
      expect(joined, contains('(unrouted)'));
      expect(joined, contains('200'));
    });

    test('a segment-prefix collision does not borrow another route identity',
        () {
      // '/mexico' must not match '/me'. A contains/startsWith rule without
      // segment alignment would log it as the profile endpoint.
      final interceptor = PiiSafeLogInterceptor();
      final options = RequestOptions(path: '/mexico', method: 'GET');

      final lines = _capturePrints(() {
        interceptor.onRequest(options, RequestInterceptorHandler());
      });

      expect(lines.join('\n'), contains('(unrouted)'));
    });

    test('query parameter values never reach the log (/cycle/calendar)', () {
      // The calendar window is NOT in the path: the generated client passes
      // from/to as queryParameters and the interceptor prints `options.path`,
      // so the dates are suppressed by construction today. Nothing pinned
      // that, so a later `print(options.uri)` would leak them silently.
      final interceptor = PiiSafeLogInterceptor();
      final options = RequestOptions(
        path: '/cycle/calendar',
        method: 'GET',
        queryParameters: const {'from': '2026-06-01', 'to': '2026-06-30'},
      );
      final response = Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {'days': <dynamic>[]},
      );
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<void>(requestOptions: options, statusCode: 400),
      );

      final lines = _capturePrints(() {
        interceptor.onRequest(options, RequestInterceptorHandler());
        interceptor.onResponse(response, ResponseInterceptorHandler());
        interceptor.onError(error, _observedErrorHandler());
      });
      final joined = lines.join('\n');

      expect(joined, isNot(contains('2026-06-01')));
      expect(joined, isNot(contains('2026-06-30')));
      expect(joined, isNot(contains('from=')));
      // Identity is still there — the point is the values, not the endpoint.
      expect(joined, contains('/cycle/calendar'));
    });

    test('a query string smuggled into the path is stripped, not logged', () {
      // Defence in depth: if a caller ever passes the query inside `path`,
      // route matching must not fall through to (unrouted) with the values
      // still attached.
      final interceptor = PiiSafeLogInterceptor();
      final options = RequestOptions(
        path: '/cycle/calendar?from=2026-06-01&to=2026-06-30',
        method: 'GET',
      );

      final lines = _capturePrints(() {
        interceptor.onRequest(options, RequestInterceptorHandler());
      });
      final joined = lines.join('\n');

      expect(joined, isNot(contains('2026-06-01')));
      expect(joined, contains('/cycle/calendar'));
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
