// Coverage gate for the Lumen client.
//
// Parses `coverage/lcov.info` directly (no lcov dependency, version-independent)
// and computes the line-hit percentage EXCLUDING generated code — anything under
// `lib/api/` (the OpenAPI-generated dio/built_value client) and any `*.g.dart`
// (built_value / codegen part files). Fails (exit 1) if coverage is below the
// threshold.
//
// Why not `lcov --remove`? Its glob semantics (`*` crossing `/`) differ across
// lcov 1.x/2.x, which silently under-excludes nested generated files. Parsing the
// raw DA records here is deterministic and matches what the analyzer excludes.
//
// Usage: `dart run tool/check_coverage.dart` from the `client/` directory.

import 'dart:io';

const double threshold = 60.0;

bool _isGenerated(String sourceFile) {
  final sf = sourceFile.replaceAll('\\', '/');
  return sf.contains('lib/api/') || sf.endsWith('.g.dart');
}

void main() {
  final lcov = File('coverage/lcov.info');
  if (!lcov.existsSync()) {
    stderr.writeln('coverage/lcov.info not found — run `flutter test --coverage` first.');
    exit(2);
  }

  var total = 0;
  var hit = 0;
  var excludedFiles = 0;
  var excluded = false;

  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      excluded = _isGenerated(line.substring(3));
      if (excluded) excludedFiles++;
    } else if (line.startsWith('DA:') && !excluded) {
      final hits = int.tryParse(line.substring(3).split(',').last) ?? 0;
      total++;
      if (hits > 0) hit++;
    }
  }

  final pct = total == 0 ? 0.0 : 100.0 * hit / total;
  stdout.writeln(
      'Coverage (excluding lib/api/** and *.g.dart): $hit/$total = '
      '${pct.toStringAsFixed(2)}%  ($excludedFiles generated files skipped)');

  if (pct < threshold) {
    stderr.writeln('GATE FAIL: ${pct.toStringAsFixed(2)}% < ${threshold.toStringAsFixed(0)}% threshold.');
    exit(1);
  }
  stdout.writeln('GATE PASS: ${pct.toStringAsFixed(2)}% >= ${threshold.toStringAsFixed(0)}%.');
}
