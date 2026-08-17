// ---------------------------------------------------------------------------
// screen_registry.dart — discovery for the a11y/golden coverage rule (P4b-T3)
// ---------------------------------------------------------------------------
//
// Read `test/shared/screen_registry_test.dart` for the CONVENTION and the rule.
// This file is only the mechanism: it walks the filesystem and reports what is
// missing. It is kept separate from the test so the rule can be pointed at a
// temporary fixture tree and watched to fail — a rule nobody has ever seen go
// red is not known to work.
//
// Everything here is pure I/O over an explicit [packageRoot]; there is no
// hidden dependency on the process's working directory except in
// [resolvePackageRoot], which is the one function the real test calls.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// One discovered screen and whatever its required coverage is missing.
class ScreenCoverage {
  ScreenCoverage({
    required this.screenPath,
    required this.screenId,
    required this.testDir,
    required this.missing,
    required this.exemptionReason,
  });

  /// Package-relative, posix-separated, e.g.
  /// `lib/features/settings/presentation/profile_screen.dart`.
  final String screenPath;

  /// The file's basename without `.dart`, e.g. `profile_screen`. This is the
  /// stem every required artifact is named after.
  final String screenId;

  /// Package-relative directory the screen's tests must live in, e.g.
  /// `test/features/settings`.
  final String testDir;

  /// Human-readable descriptions of what is absent. Empty means covered.
  final List<String> missing;

  /// Non-null when the screen is on the exemption list; [missing] is then
  /// reported but not enforced.
  final String? exemptionReason;

  bool get isCovered => missing.isEmpty;
}

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

/// Walks up from the current working directory to the Flutter package root
/// (the directory holding `pubspec.yaml`).
///
/// `flutter test` runs with the package root as cwd, so this normally resolves
/// on the first try; the walk is there so a run from a subdirectory or an IDE
/// with a different cwd does not silently discover zero screens and pass.
Directory resolvePackageRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 10; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'Could not find pubspec.yaml walking up from ${Directory.current.path}. '
    'The screen registry cannot discover screens without a package root.',
  );
}

String _posix(String path) => path.replaceAll(r'\', '/');

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

/// Every `lib/features/**/presentation/*_screen.dart` under [packageRoot],
/// package-relative and sorted.
///
/// This is the whole point of the registry: real file discovery. A
/// hand-maintained list reproduces the bug it exists to kill, because adding a
/// screen and adding it to the list are two separate acts and only one of them
/// is required to ship.
List<String> discoverScreenFiles(Directory packageRoot) {
  final root = _posix(packageRoot.path);
  final featuresDir = Directory('$root/lib/features');
  if (!featuresDir.existsSync()) return const <String>[];

  final screens = <String>[];
  for (final entity in featuresDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = _posix(entity.path);
    if (!path.endsWith('_screen.dart')) continue;
    if (!path.contains('/presentation/')) continue;
    screens.add(path.substring(root.length + 1));
  }
  screens.sort();
  return screens;
}

/// Every `*_screen.dart` under `lib/features`, WHEREVER it sits.
///
/// [discoverScreenFiles] only looks inside `presentation/`, which is correct
/// for the convention but blind to a screen that lands in `screens/`, `ui/` or
/// straight in the feature root. Comparing the two lists is what turns that
/// blindness into a loud failure instead of a silently-skipped screen — the
/// same bug this registry exists to kill, one directory level up.
List<String> discoverScreenFilesAnywhere(Directory packageRoot) {
  final root = _posix(packageRoot.path);
  final featuresDir = Directory('$root/lib/features');
  if (!featuresDir.existsSync()) return const <String>[];

  final screens = <String>[];
  for (final entity in featuresDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = _posix(entity.path);
    if (!path.endsWith('_screen.dart')) continue;
    screens.add(path.substring(root.length + 1));
  }
  screens.sort();
  return screens;
}

// ---------------------------------------------------------------------------
// What counts as declaring a test
// ---------------------------------------------------------------------------
//
// These gates decide whether a test FILE really declares the tests the
// convention requires. They used to be text matches over the file, then text
// matches over a hand-scrubbed copy of it. Both were wrong, and wrong in the
// same direction three times running:
//
//   * `// testWidgets( expectNoDingbats` in a comment satisfied a raw match;
//   * scrubbing comments fixed that, but the hand-written lexer mispaired
//     quotes in `'day ${map['a//b']}'` and read the `//` inside as a real
//     comment, DELETING the genuine test declaration after it;
//   * brace-counting the interpolation fixed that, but `'${/* } */ m['k//y']}'`
//     — valid, compiling Dart — miscounted the `}` inside the comment and
//     deleted the declaration again.
//
// Each fix was correct about the case in front of it and each opened a fresh
// hole, because a correct Dart lexer IS a real lexer. So the file is parsed
// now. `parseString` is a purely syntactic parse: no resolution, no analysis
// context, no SDK processing, no build_runner, no CI step — fast enough for
// the handful of files a registry run touches.
//
// What that buys, stated precisely: a *mention* of a call — in a comment, or in
// the text of a string literal — is not an invocation in the AST and cannot
// satisfy a gate. It does NOT mean "nothing inside a string counts": an
// invocation inside a string INTERPOLATION (`'${goldenTestLightAndDark()}'`) is
// a real call and does satisfy the gate. That is correct, and it is tested.
//
// See [describeGateSemantics] for exactly what a satisfied gate does and does
// not tell you.

/// What a parsed test file declares, and whether it parsed at all.
class DeclaredTestCalls {
  DeclaredTestCalls({required this.invokedNames, required this.syntaxErrors});

  /// The simple name of every method invocation in the file, so a call reached
  /// through a prefix (`a11y.expectNoDingbats(t)`) counts the same as a bare
  /// one.
  final Set<String> invokedNames;

  /// Syntax errors, as `line:column message`. Non-empty means the gates below
  /// cannot be trusted for this file, and the audit reports that instead of
  /// guessing at what the file declares.
  final List<String> syntaxErrors;

  bool get parsed => syntaxErrors.isEmpty;

  bool declaresAWidgetTest() => invokedNames.any(_widgetTestName.hasMatch);
  bool declaresAGolden() => invokedNames.any(_goldenTestName.hasMatch);
  bool callsNoDingbatGuard() => invokedNames.contains('expectNoDingbats');
}

/// `testWidgets` and wrappers that EXTEND it (`testWidgetsWithSemantics`).
///
/// Anchored at both ends, which is the "extend, don't embed" convention: a
/// wrapper adds a suffix to the canonical name rather than burying it
/// (`lumenTestWidgets` does not match, by design).
final RegExp _widgetTestName = RegExp(r'^testWidgets\w*$');

/// `goldenTest` and wrappers that extend it (`goldenTestLightAndDark`).
final RegExp _goldenTestName = RegExp(r'^goldenTest\w*$');

/// What a satisfied gate does and does not tell you.
///
/// **The rule: a gate matches the NAME of a syntactic invocation. It says
/// nothing about what that name resolves to, whether the call runs, or what it
/// does when it runs.**
///
/// So all of these satisfy a gate, and are outside what this registry can see:
/// a locally-defined no-op with a conforming name; a call to a name the file
/// never imports (which would not compile, but the narrow
/// `flutter test <one-file>` command never compiles the audited file); a call
/// that is unreachable; a test whose body asserts nothing.
///
/// Closing any of those needs resolution or execution. The registry's job is
/// narrower and worth keeping honest: it answers "did anyone write the test
/// this screen owes", which is the question that was previously unanswerable.
const String describeGateSemantics =
    'A gate matches the name of a syntactic invocation; it says nothing about '
    'what that name resolves to, whether the call runs, or what it does.';

/// Parses [source] and collects every invoked method name.
DeclaredTestCalls parseTestCalls(String source, {String path = '<memory>'}) {
  final result = parseString(
    // A leading U+FEFF is a byte-order mark, not source. The analyzer's own
    // file-reading path strips it, and dart/flutter compile such a file
    // happily — but `parseString` takes raw content, so passing it through
    // makes this registry STRICTER than both the compiler and the analyzer,
    // and reports a perfectly good file as "does not parse". That matters here
    // specifically: this is a Windows/PowerShell-primary repo where `>` and
    // `Out-File` default to UTF-8-WITH-BOM, and 13 later tasks each create two
    // new test files.
    content: stripBom(source),
    path: path,
    // The parser needs a feature set up front; the fully-correct one requires
    // an AnalysisContextCollection and SDK processing, which is far too much
    // machinery for "does this file call testWidgets". The newest set parses a
    // superset of what this repo writes.
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );

  final collector = _InvocationCollector();
  result.unit.accept(collector);

  return DeclaredTestCalls(
    invokedNames: collector.names,
    syntaxErrors: result.errors
        .map(
          (d) =>
              '${result.lineInfo.getLocation(d.offset).lineNumber}:'
              '${result.lineInfo.getLocation(d.offset).columnNumber} '
              '${d.message}',
        )
        .toList(),
  );
}

/// Removes a leading UTF-8 byte-order mark, if present.
///
/// Written as the escape `\u{FEFF}` rather than the character itself: a literal
/// BOM in source is invisible in every editor and diff, which is how it becomes
/// a bug in the first place.
String stripBom(String source) =>
    source.startsWith('\u{FEFF}') ? source.substring(1) : source;

class _InvocationCollector extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // `testWidgets(…, skip: true)` declares a test that never runs. It is
    // QUIETER than the commented-out body already closed: `flutter test` still
    // reports the file as containing a test, so nothing else in CI notices.
    //
    // Not recursing is deliberate — everything inside a skipped declaration is
    // equally dead, including the `expectNoDingbats(tester)` the guard gate is
    // looking for. Applied to any invocation, so `group(…, skip: true)` is
    // handled by the same three lines.
    //
    // Only the literal form is detected. `skip: someFlag` needs resolution to
    // evaluate and stays open; nobody writes that in practice.
    if (_isSkippedLiteral(node)) return;

    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }

  bool _isSkippedLiteral(MethodInvocation node) {
    for (final argument in node.argumentList.arguments) {
      if (argument is! NamedExpression) continue;
      if (argument.name.label.name != 'skip') continue;
      final value = argument.expression;
      if (value is BooleanLiteral && value.value) return true;
    }
    return false;
  }
}

/// A file that will not parse is a coverage gap in its own right.
///
/// Worth reporting rather than ignoring: `flutter test` would catch a
/// non-compiling test file in a full run, but the narrow dev-iteration command
/// (`flutter test test/shared/screen_registry_test.dart`) never compiles the
/// golden/semantics files it is auditing. Without this, that invocation could
/// give a confident verdict about a file that does not build, with nothing to
/// contradict it.
String _doesNotParse(String path, DeclaredTestCalls calls) {
  final shown = calls.syntaxErrors.take(3).join('; ');
  final more = calls.syntaxErrors.length > 3
      ? ' (+${calls.syntaxErrors.length - 3} more)'
      : '';
  return '$path does not parse, so what it declares cannot be checked: '
      '$shown$more';
}

/// Resolves each discovered screen's required artifacts and reports the gaps.
///
/// [exemptions] maps a package-relative screen path to the reason it is
/// exempt. It exists so a gap is declared out loud with an owner, never
/// silently tolerated — see the test file for the rules on using it.
List<ScreenCoverage> auditScreenCoverage(
  Directory packageRoot, {
  Map<String, String> exemptions = const <String, String>{},
}) {
  final root = _posix(packageRoot.path);

  return discoverScreenFiles(packageRoot).map((screenPath) {
    final screenId = screenPath.split('/').last.replaceFirst('.dart', '');

    // lib/features/<…>/presentation/x_screen.dart -> test/features/<…>
    final segments = screenPath.split('/');
    final dirSegments = segments
        .sublist(0, segments.length - 1) // drop the file itself
        .where((segment) => segment != 'presentation')
        .toList();
    dirSegments[0] = 'test'; // lib -> test
    final testDir = dirSegments.join('/');

    final goldenTest = '$testDir/${screenId}_golden_test.dart';
    final semanticsTest = '$testDir/${screenId}_semantics_test.dart';
    final lightPng = '$testDir/goldens/ci/${screenId}_light.png';
    final darkPng = '$testDir/goldens/ci/${screenId}_dark.png';

    final missing = <String>[];

    final goldenSource = _readOrNull('$root/$goldenTest');
    if (goldenSource == null) {
      missing.add('$goldenTest (no golden test file)');
    } else {
      final golden = parseTestCalls(goldenSource, path: goldenTest);
      if (!golden.parsed) {
        missing.add(_doesNotParse(goldenTest, golden));
      } else if (!golden.declaresAGolden()) {
        missing.add(
          '$goldenTest exists but declares no golden test (a goldenTest…(…) '
          'call in live code — a mention in a comment does not count)',
        );
      }
    }

    if (!File('$root/$lightPng').existsSync()) {
      missing.add('$lightPng (run: flutter test --update-goldens)');
    }
    if (!File('$root/$darkPng').existsSync()) {
      missing.add('$darkPng (run: flutter test --update-goldens)');
    }

    final semanticsSource = _readOrNull('$root/$semanticsTest');
    if (semanticsSource == null) {
      missing.add('$semanticsTest (no semantics test file)');
    } else {
      final semantics = parseTestCalls(semanticsSource, path: semanticsTest);
      if (!semantics.parsed) {
        // Reported instead of, not as well as, the two gates below: a file
        // that does not parse cannot be meaningfully asked what it declares,
        // and two derived complaints would bury the real one.
        missing.add(_doesNotParse(semanticsTest, semantics));
      } else {
        if (!semantics.declaresAWidgetTest()) {
          missing.add(
            '$semanticsTest exists but declares no testWidgets (a '
            'testWidgets…(…) call in live code — a commented-out one does not '
            'count)',
          );
        }
        if (!semantics.callsNoDingbatGuard()) {
          missing.add(
            '$semanticsTest does not call expectNoDingbats(tester) — the '
            'no-dingbat rule now lives in each screen\'s semantics test, not '
            'in a hand-listed cross-screen file',
          );
        }
      }
    }

    return ScreenCoverage(
      screenPath: screenPath,
      screenId: screenId,
      testDir: testDir,
      missing: missing,
      exemptionReason: exemptions[screenPath],
    );
  }).toList();
}

String? _readOrNull(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : null;
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

/// A failure message naming every uncovered screen and every missing file, or
/// `null` when everything non-exempt is covered.
String? describeUncovered(List<ScreenCoverage> reports) {
  final broken = reports
      .where((r) => !r.isCovered && r.exemptionReason == null)
      .toList();
  if (broken.isEmpty) return null;

  final buffer = StringBuffer()
    ..writeln(
      '${broken.length} screen(s) ship without the accessibility and golden '
      'coverage every Lumen screen must have.',
    )
    ..writeln();
  for (final screen in broken) {
    buffer.writeln('  ${screen.screenPath}');
    for (final missing in screen.missing) {
      buffer.writeln('      MISSING: $missing');
    }
    buffer.writeln();
  }
  buffer.writeln(
    'Add the missing test(s). Do NOT add an exemption unless the missing work '
    'is genuinely large, and then list it in kScreenCoverageExemptions with a '
    'TODO naming what is owed and who owes it.',
  );
  return buffer.toString();
}

/// Exemptions that no longer correspond to a real gap, so a stale entry cannot
/// sit in the list forever pretending to be load-bearing.
List<ScreenCoverage> staleExemptions(List<ScreenCoverage> reports) =>
    reports.where((r) => r.isCovered && r.exemptionReason != null).toList();
