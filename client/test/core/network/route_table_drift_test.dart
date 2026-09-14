// ---------------------------------------------------------------------------
// Route-table drift detector (P4b-T4, fix round 2)
// ---------------------------------------------------------------------------
//
// `_kRouteTemplates` in `lib/core/network/dio_provider.dart` is the client's
// mirror of the server's route table, and it is now load-bearing twice over:
// it decides what a log line says, and — since the body allowlist is keyed on
// route identity — whether a request body is logged at all. Nothing failed when
// the contract gained a path, so the table could silently go stale.
//
// Staleness is not merely cosmetic. A missing entry logs as `(unrouted)`, which
// is safe but useless, and the tempting "fix" for a developer who meets it in
// P5 is to relax `_safePath` rather than to add the entry. This test makes
// staleness a CI failure that names the path to add.
//
// Method: read the generated client's `final _path = r'…'` strings — the exact
// paths production sends — and assert none of them resolves to `(unrouted)`.
// Read-only; it touches neither the contract nor the generated code.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/network/dio_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// `flutter test` runs with the package root as its working directory; this
/// falls back to `client/` so the file is also found from the repo root.
File _generatedClientFile() {
  const relative = 'lib/api/api/lumen_api_api.dart';
  for (final candidate in [relative, 'client/$relative']) {
    final file = File(candidate);
    if (file.existsSync()) return file;
  }
  fail(
    'Could not find $relative from ${Directory.current.path}. This test reads '
    'the generated client to detect route-table drift; if the generated client '
    'moved, update this path.',
  );
}

/// The raw string literal of every `final _path = r'…'` in the generated client.
///
/// The parameterised operations render as
/// `final _path = r'/cycle/day/{date}'.replaceAll(…)`, so the literal captured
/// here is the route TEMPLATE, placeholders intact.
Set<String> _generatedPaths(String source) {
  final pattern = RegExp(r"final _path = r'([^']+)'");
  return pattern.allMatches(source).map((m) => m.group(1)!).toSet();
}

/// Substitutes a value for every `{placeholder}` segment.
///
/// The substituted value is a sentinel with no bearing on route matching — the
/// matcher is segment-structural — which lets the same loop assert that no
/// parameter value survives into the log line.
String _withValues(String template, String sentinel) =>
    template.replaceAll(RegExp(r'\{[^}]+\}'), sentinel);

/// What `_safePath` substitutes for a parameter segment.
const _kRedactedSegment = '<redacted>';

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Set<String> generatedPaths;

  setUpAll(() {
    generatedPaths = _generatedPaths(_generatedClientFile().readAsStringSync());
  });

  group('route table vs the generated client', () {
    test('the parse found the generated paths at all', () {
      // Without this the suite passes vacuously if the generator changes its
      // emitted shape, or if the regex is broken by a refactor: an empty set
      // makes every `for` below a no-op.
      expect(
        generatedPaths.length,
        greaterThanOrEqualTo(21),
        reason: 'backend/contract/openapi.json declares 21 distinct paths; '
            'parsing found ${generatedPaths.length}',
      );
      // Spot-checks across the three shapes: plain, nested, parameterised.
      expect(generatedPaths, contains('/me'));
      expect(generatedPaths, contains('/me/devices'));
      expect(generatedPaths, contains('/cycle/day/{date}'));
    });

    test('every generated path resolves to a route identity, not (unrouted)',
        () {
      const sentinel = 'ROUTE-PARAM-SENTINEL';
      final interceptor = PiiSafeLogInterceptor();
      final stale = <String>[];

      for (final template in generatedPaths) {
        final concrete = _withValues(template, sentinel);
        final lines = _capturePrints(() {
          interceptor.onRequest(
            RequestOptions(path: concrete, method: 'GET'),
            RequestInterceptorHandler(),
          );
        });
        final joined = lines.join('\n');

        if (joined.contains('(unrouted)')) {
          stale.add(template);
          continue;
        }
        // While we are here: a parameter value must not survive either.
        expect(
          joined,
          isNot(contains(sentinel)),
          reason: '$template logged its parameter value',
        );
      }

      expect(
        stale,
        isEmpty,
        reason: 'These generated paths have no entry in _kRouteTemplates '
            '(lib/core/network/dio_provider.dart), so they log as (unrouted) '
            'and their bodies are suppressed as unknown. Add each one, with '
            'its parameter segments dropped:\n'
            '${stale.map((p) => '  - $p').join('\n')}',
      );
    });

    test('the table has no entry the generated client never calls', () {
      // Drift in the other direction: a stale entry keeps logging identity for
      // an endpoint that no longer exists, and worse, could allowlist its body
      // if it were ever added to _kBodySafeIdentities.
      const sentinel = 'ROUTE-PARAM-SENTINEL';
      final interceptor = PiiSafeLogInterceptor();

      // Every identity the table can emit, derived by asking it.
      final reachable = <String>{};
      for (final template in generatedPaths) {
        final lines = _capturePrints(() {
          interceptor.onRequest(
            RequestOptions(path: _withValues(template, sentinel), method: 'GET'),
            RequestInterceptorHandler(),
          );
        });
        // '[Dio ▶] GET /cycle/day/<redacted>' — and for the two body-safe
        // endpoints the line continues ' headers={…}', so take the path field
        // positionally rather than as the last token.
        final match = RegExp(r'^\[Dio .\] \w+ (\S+)').firstMatch(lines.single);
        expect(match, isNotNull, reason: 'unparsed log line: ${lines.single}');
        reachable.add(match!.group(1)!.replaceAll('/$_kRedactedSegment', ''));
      }

      // 19 identities: the 21 contract paths with the three parameterised ones
      // collapsing onto /cycle/day, /cycle/events and /symptoms — and
      // /cycle/events and /symptoms each already exist un-parameterised.
      expect(
        reachable.length,
        19,
        reason: 'reachable identities: ${(reachable.toList()..sort()).join(', ')}',
      );
    });
  });
}
