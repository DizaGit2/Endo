import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/auth/auth_interceptor.dart';
import 'package:lumen/core/auth/oidc_client.dart';
import 'package:lumen/core/auth/token_store.dart';

// ---------------------------------------------------------------------------
// API base URL
// ---------------------------------------------------------------------------

// API base URL. Override at build/run time with
//   --dart-define=LUMEN_API_BASE=http://<host>:<port>
// The default targets the Android emulator's host alias 10.0.2.2:8085 (compose
// maps 127.0.0.1:8085 -> api:8080). For a real device pass the host LAN IP; for
// production pass the public https Caddy host (release builds force TLS).
const _kApiBase = String.fromEnvironment(
  'LUMEN_API_BASE',
  defaultValue: 'http://10.0.2.2:8085',
);

// ---------------------------------------------------------------------------
// Route identity — the client's mirror of the server's route table
// ---------------------------------------------------------------------------

/// The API's route templates with their parameter segments dropped.
///
/// This is the client half of the server's posture, which is **not** "never log
/// the path" but *endpoint identity is logged, parameter values never are*:
/// `Program.cs:244-259` logs `{RouteTemplate}` — `/cycle/day/{date}`, or the
/// constant `(unrouted)` when no endpoint matched — and
/// `PiiRedactionEnricher.cs:106-112` redacts the raw `RequestPath` outright, on
/// every request, because `/cycle/day/2026-08-06` asserts that this user logged
/// something on that day while `/cycle/day/{date}` carries the same operational
/// signal with none of the datum.
///
/// It is also the substitution `docs/ARCHITECTURE.md:367` (§F) prescribes for
/// path IDs — `/users/{guid}` → `/users/{sha256-short}`: keep the identity,
/// replace the value. Blanking the path is not a stricter reading of that rule,
/// it is a different one.
///
/// Dio has no route table, so this is it. Keeping identity is what lets a
/// developer tell `/symptoms` from `/settings/cycle` in a debug log; dropping
/// the trailing segment is what keeps the date and the record GUID out of it.
///
/// **[_safePath] is fail-closed as a property of the function, not as a
/// consequence of maintaining this list.** `identity` is only ever assigned
/// from an element of this list, and `raw` never reaches the return value, so
/// the function's codomain is a closed set of compile-time constants: these 19
/// identities, those 19 with `/$_kRedacted` appended, and [_kUnrouted]. No byte
/// of caller input can appear in the output unless it is byte-identical to a
/// template. An endpoint added without touching this list therefore logs as
/// `(unrouted)` — it over-redacts — which is the opposite of the gap that let
/// `POST /cycle/events` and `PUT /cycle/events/{id}` print in full.
///
/// Sorted as the contract lists them (`backend/contract/openapi.json`); the
/// longest matching entry wins, so `/me/devices` and `/health/ready` keep their
/// second segment while `/cycle/day/2026-06-14` loses its third.
/// `route_table_drift_test.dart` fails if the generated client gains a path
/// that is missing here.
const _kRouteTemplates = <String>[
  '/checkin/quick',
  '/cycle/calendar',
  '/cycle/day', // + {date}
  '/cycle/events', // + {id}
  '/cycle/phase-override',
  '/health',
  '/health/ready',
  '/me',
  '/me/devices',
  '/onboarding/baseline',
  '/onboarding/complete',
  '/onboarding/cycle',
  '/onboarding/goals',
  '/onboarding/hormones',
  '/onboarding/notifications',
  '/onboarding/start',
  '/onboarding/state',
  '/settings/cycle',
  '/symptoms', // + {id}
];

/// What the server calls a request that matched no endpoint.
const _kUnrouted = '(unrouted)';

/// Stands in for any path segment that is a parameter value.
const _kRedacted = '<redacted>';

/// The path as it may appear in a log line: endpoint identity, values dropped.
String _safePath(String path) {
  // A query string is never identity. `options.path` carries none today (the
  // generated client passes `from`/`to` via queryParameters), but stripping it
  // here means a caller that starts passing one cannot turn this into a leak.
  final raw = path.split('?').first.split('#').first;

  String? identity;
  for (final template in _kRouteTemplates) {
    // Segment-aligned, so '/me' does not match '/mexico'.
    final matches = raw == template || raw.startsWith('$template/');
    if (matches && (identity == null || template.length > identity.length)) {
      identity = template;
    }
  }

  if (identity == null) return _kUnrouted;
  return raw == identity ? identity : '$identity/$_kRedacted';
}

// ---------------------------------------------------------------------------
// Body safety — an allowlist, not a blocklist
// ---------------------------------------------------------------------------

/// The only endpoints whose bodies and headers are safe to log.
///
/// This is deliberately an **allowlist**. It used to be a blocklist of eight
/// path prefixes, which meant every endpoint still to be built — `/insights`,
/// `/reports`, `/hormones`, `/activity`, `/medications` — matched none of them
/// and would have logged its body in full on the day it landed. In this app
/// those bodies are pain scores, mood, symptom rows and cycle events, so that
/// was a leak on a timer rather than a hypothetical.
///
/// There is no judgement call in the membership: these two are the only
/// operations in `backend/contract/openapi.json` with no user-scoped payload
/// (`{"200": {"description": "OK"}}`, no schema). Every other identity is
/// authenticated and user-scoped.
///
/// [_kUnrouted] is deliberately absent, so an endpoint the route table does not
/// know is body-suppressed by default — the same fail-closed property as
/// [_safePath], extended to the tier that actually carries the health data.
const _kBodySafeIdentities = <String>{'/health', '/health/ready'};

/// Whether this request's body and headers must be kept out of the log.
///
/// Keyed on route identity rather than on the raw path, so the route table is
/// the single thing to maintain — there is no second list to fall out of sync
/// with it, and the two tiers can no longer disagree about what an endpoint is.
bool _isSensitivePath(String path) =>
    !_kBodySafeIdentities.contains(_safePath(path));

// ---------------------------------------------------------------------------
// PII-safe logger interceptor
// ---------------------------------------------------------------------------

/// A Dio [Interceptor] that logs only method + endpoint + status, where:
/// - the Authorization header is NEVER logged, on any path;
/// - bodies and headers are dropped for every endpoint except the two in
///   [_kBodySafeIdentities];
/// - the path is reduced to its route identity by [_safePath], on every path,
///   so no parameter value (a date, a record GUID) is ever printed;
/// - all three of onRequest / onResponse / **onError** apply those rules.
///
/// Active only in [kDebugMode] — a no-op in release builds.
///
/// Public (unlike the rest of this file's helpers) and [visibleForTesting]
/// so tests can drive its onRequest/onResponse/onError hooks directly instead
/// of reconstructing a full Dio pipeline — production code must still only
/// reach it via [dioProvider].
@visibleForTesting
class PiiSafeLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      // NEVER log the Authorization header.
      final safeHeaders = Map<String, dynamic>.from(options.headers)
        ..remove('Authorization')
        ..remove('authorization');

      final sensitive = _isSensitivePath(options.path);
      // ignore: avoid_print
      print(
        '[Dio ▶] ${options.method} ${_safePath(options.path)}'
        '${sensitive ? '' : ' headers=$safeHeaders'}',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final path = response.requestOptions.path;
      final sensitive = _isSensitivePath(path);
      // ignore: avoid_print
      print(
        '[Dio ◀] ${response.statusCode} ${response.requestOptions.method} '
        '${_safePath(path)}'
        '${sensitive ? '' : ' data=${response.data}'}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      // The error path carried no sensitivity check at all before P4b-T4 — it
      // printed the raw path for every failing request. The error BODY is
      // never logged on any path: a 400 problem+json echoes field names, and a
      // 5xx body can carry server internals.
      final path = err.requestOptions.path;
      // ignore: avoid_print
      print(
        '[Dio ✗] ${err.response?.statusCode} '
        '${err.requestOptions.method} ${_safePath(path)} '
        '${err.type}',
      );
    }
    handler.next(err);
  }
}

// ---------------------------------------------------------------------------
// dioProvider
// ---------------------------------------------------------------------------

/// Provides the singleton [Dio] instance wired with [AuthInterceptor] and
/// the PII-safe logger.
///
/// The [AuthInterceptor] is constructed with:
/// - [TokenStore] from [tokenStoreProvider]
/// - A refresh function delegating to [IOidcClient.refresh] from
///   [oidcClientProvider]
/// - An [onAuthLost] callback that calls [AuthController.logout] so the router
///   guard redirects to the login screen
final dioProvider = Provider<Dio>((ref) {
  final tokenStore = ref.read(tokenStoreProvider);
  final oidcClient = ref.read(oidcClientProvider);

  // Explicit timeouts are required: a pre-built Dio is handed to the generated
  // client, so the generator's default timeouts are bypassed. Without these a
  // server that accepts the connection but never responds would hang forever,
  // and the online-only SWR fallback (which depends on a Dio timeout becoming a
  // NetworkFailure) would never fire.
  final dio = Dio(
    BaseOptions(
      baseUrl: _kApiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
    ),
  );

  final authInterceptor = AuthInterceptor(
    tokenStore: tokenStore,
    refresh: (refreshToken) => oidcClient.refresh(refreshToken),
    onAuthLost: () {
      // Notify the auth controller so the router redirects to login. logout()
      // is fully guarded (never throws), so fire-and-forget is safe; mark it
      // unawaited to make the intent explicit and avoid a dropped-Future lint.
      unawaited(ref.read(authStatusProvider.notifier).logout());
    },
  );

  dio.interceptors.addAll([
    authInterceptor,
    PiiSafeLogInterceptor(),
  ]);

  // Provide the interceptor a reference to Dio so it can retry 401 requests.
  authInterceptor.dio = dio;

  return dio;
});
