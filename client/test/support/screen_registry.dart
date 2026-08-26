// ---------------------------------------------------------------------------
// screen_registry.dart — discovery for the a11y/golden coverage rule
// (P4b-T3: screens · P4b-T5b: shared widgets)
// ---------------------------------------------------------------------------
//
// Read `test/shared/screen_registry_test.dart` for the CONVENTIONS and the
// rules. This file is only the mechanism: it walks the filesystem and reports
// what is missing. It is kept separate from the test so a rule can be pointed
// at a temporary fixture tree and watched to fail — a rule nobody has ever seen
// red is not known to work.
//
// TWO discovery rules live here, deliberately side by side rather than merged
// into one widened glob:
//
//   * SCREENS  — `lib/features/**/presentation/*_screen.dart`, one subject per
//                FILE, artifacts under `test/features/<feature>/`.
//   * WIDGETS  — `lib/shared/widgets/**.dart`, one subject per PUBLIC WIDGET
//                CLASS, artifacts under `test/widgets/`.
//
// They are not one rule with a looser pattern: the screen rule's `lib` -> `test`
// derivation drops `presentation/`, the widget rule's drops `shared/`; the
// screen rule names artifacts after the file, the widget rule after the widget;
// and the two semantics gates ask for different things (see
// [kScreenSemanticsGate] and [widgetSemanticsGate]). Widening one pattern to
// cover both would have silently changed the screen rule, which is
// load-bearing.
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
// The SUBJECT binding added in P4b-T5b round 1 needed more than parsing to be
// able to say the same thing. A `///` doc comment IS part of the AST and
// `[LumenFoo]` inside one is a real CommentReference; so are the names in an
// `import '…' show LumenFoo;` combinator. Both are refused explicitly in
// [_InvocationCollector] rather than by luck — without that, documenting a
// helper as `/// Pumps [LumenFoo]` binds the gate forever after the helper
// stops pumping it.
//
// See [describeGateSemantics] for exactly what a satisfied gate does and does
// not tell you.

/// What a parsed test file declares, and whether it parsed at all.
class DeclaredTestCalls {
  DeclaredTestCalls({
    required this.invokedNames,
    required this.identifiers,
    required this.syntaxErrors,
  });

  /// The simple name of every method invocation in the file, so a call reached
  /// through a prefix (`a11y.expectNoDingbats(t)`) counts the same as a bare
  /// one.
  final Set<String> invokedNames;

  /// Every identifier and type name the file NAMES in live code — which is how
  /// a gate can ask "does this test go anywhere near its subject".
  ///
  /// Both halves are needed: `const LumenFoo()` names its type through a
  /// `NamedType` token, while `find.byType(LumenFoo)` names it through a
  /// `SimpleIdentifier`. Collected under the same skip-aware walk as
  /// [invokedNames], so a `skip: true` test cannot mention its way to a pass.
  final Set<String> identifiers;

  /// Syntax errors, as `line:column message`. Non-empty means the gates below
  /// cannot be trusted for this file, and the audit reports that instead of
  /// guessing at what the file declares.
  final List<String> syntaxErrors;

  bool get parsed => syntaxErrors.isEmpty;

  bool declaresAWidgetTest() => invokedNames.any(_widgetTestName.hasMatch);
  bool declaresAGolden() => invokedNames.any(_goldenTestName.hasMatch);
  bool callsNoDingbatGuard() => invokedNames.contains('expectNoDingbats');

  /// Whether [subject]'s name occurs as an identifier in the file's LIVE code.
  ///
  /// Precisely that, and no more:
  ///
  ///  * a name in a `//` or `/* */` comment, or in the text of a string
  ///    literal, is not an identifier node and does not count;
  ///  * a name in a `///` DOC comment does not count either — a doc comment is
  ///    part of the AST and `[LumenFoo]` inside one is a real
  ///    `CommentReference`, so the visitor has to refuse it deliberately;
  ///  * `import '…' show LumenFoo;` does not count, for the same reason;
  ///  * it is FILE-scoped, not test-scoped: a mount in one test and a matcher
  ///    in another satisfy both halves of the widget gate.
  ///
  /// It does not prove the widget was built, only that the file names it where
  /// naming it has an effect.
  bool mentions(String subject) => identifiers.contains(subject);
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
    identifiers: collector.identifiers,
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
  final identifiers = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    identifiers.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  // A documentation comment is part of the AST: `AnnotatedNode.visitChildren`
  // descends into it, and `/// See [LumenGhost].` holds a CommentReference with
  // a real SimpleIdentifier inside. Without this override a dartdoc satisfies
  // the subject binding — so a helper documented as `/// Pumps [LumenFoo]`
  // keeps the gate green forever after it stops pumping it, and this repo's
  // house style writes exactly that comment.
  @override
  void visitComment(Comment node) {}

  // `import 'x.dart' show LumenGhost;` and its hide twin name the subject
  // without using it. Both are SimpleIdentifiers and neither is a mount.
  @override
  void visitShowCombinator(ShowCombinator node) {}

  @override
  void visitHideCombinator(HideCombinator node) {}

  @override
  void visitNamedType(NamedType node) {
    // `const LumenFoo()` and `LumenFoo(...)` name their type through a token on
    // a NamedType, not through a SimpleIdentifier, so both visitors are needed
    // to answer "is the subject named here".
    identifiers.add(node.name.lexeme);
    super.visitNamedType(node);
  }

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

/// What a semantics test must call BEYOND declaring a widget test.
///
/// The two rules genuinely differ here, which is why this is a parameter and
/// not a constant:
///
///   * a SCREEN's semantics test must call `expectNoDingbats` — that call is
///     what replaced the hand-listed `no_dingbats_test.dart`, so the rule has
///     to travel with every screen;
///   * a WIDGET's semantics test must make at least one assertion from
///     `a11y_guard.dart`'s vocabulary. `expectNoDingbats` cannot be the widget
///     gate: it fails a tree with no `Text` in it (deliberately — for a screen
///     that means the harness never mounted anything), and a widget is allowed
///     to render no text at all. `LumenStepDots` is seven coloured boxes.
typedef SemanticsGate = ({
  bool Function(DeclaredTestCalls calls) isSatisfiedBy,
  String Function(String semanticsTestPath, DeclaredTestCalls calls) describeGap,
});

/// The screen rule's gate: `expectNoDingbats(tester)`. Wording unchanged since
/// P4b-T3 — the failure message is what six screens were fixed against.
final SemanticsGate kScreenSemanticsGate = (
  isSatisfiedBy: (calls) => calls.callsNoDingbatGuard(),
  describeGap: (path, _) =>
      '$path does not call expectNoDingbats(tester) — the no-dingbat rule now '
      'lives in each screen\'s semantics test, not in a hand-listed '
      'cross-screen file',
);

/// The widget rule's gate: the file must NAME [subject], and call at least one
/// matcher out of [matchers].
///
/// **Both halves, and the first is not decoration.** The screen rule gets its
/// subject binding for free: `expectNoDingbats` asserts `texts, isNotEmpty`, so
/// it fails a tree the screen was never mounted into. No matcher in this
/// vocabulary can do that — `expectNoButtons(tester)` and
/// `expectNoDingbats(tester)` take no finder at all — so
///
/// ```dart
/// testWidgetsWithSemantics('a11y', (t) async {
///   await pumpApp(t, home: const Text('x'));   // NOT the widget
///   expectNoButtons(t);
/// });
/// ```
///
/// passes at runtime, and would satisfy a matcher-only gate while the widget
/// the file is named after was never built. Requiring the subject's own type
/// name to appear as an identifier in the parsed file is the cheapest binding
/// that closes it, and it is structural in the same way every other gate here
/// is: a name in a comment or in the text of a string is not an identifier
/// node.
///
/// **What the subject half proves, exactly:** the subject's name occurs as an
/// identifier in live code — excluding documentation comments and import
/// combinators, which are AST nodes too and are refused deliberately. It does
/// NOT prove the widget was mounted, that the mount is what the matcher
/// inspected, or that the two are even in the same test: [DeclaredTestCalls.mentions]
/// is file-scoped. That weaker property is still worth its cost, because it
/// kills the `pumpApp(t, home: const Text('x'))` vacuity outright — but it is
/// the property, and [describeGateSemantics] states the general limit.
SemanticsGate widgetSemanticsGate(
  Set<String> matchers, {
  required String subject,
}) {
  final listed = (matchers.toList()..sort()).join(', ');
  return (
    isSatisfiedBy: (calls) =>
        calls.mentions(subject) && calls.invokedNames.any(matchers.contains),
    describeGap: (path, calls) => calls.mentions(subject)
        ? '$path declares a widget test but makes no accessibility assertion: '
              "it calls none of test/support/a11y_guard.dart's matchers "
              '($listed). Mounting the widget is not coverage — assert what '
              'a screen reader gets from it'
        : '$path never names $subject in live code, so whatever it asserts, it '
              'does not assert it about $subject (a mention in a comment or in '
              'a string is not a mount). Build the widget the file is named '
              'after',
  );
}

/// The four artifacts both rules require, and whichever of them is absent.
///
/// Shared by [auditScreenCoverage] and [auditWidgetCoverage] so there is one
/// implementation of "does the golden test declare a golden, are both PNGs
/// committed, does the semantics test declare a test and assert something".
/// The order of the reported gaps is part of the contract — the P4b-T3 failure
/// messages read golden, light PNG, dark PNG, semantics.
List<String> _missingArtifacts({
  required String root,
  required String testDir,
  required String stem,
  required SemanticsGate semanticsGate,
  String? goldenSubject,
}) {
  final goldenTest = '$testDir/${stem}_golden_test.dart';
  final semanticsTest = '$testDir/${stem}_semantics_test.dart';
  final lightPng = '$testDir/goldens/ci/${stem}_light.png';
  final darkPng = '$testDir/goldens/ci/${stem}_dark.png';

  final missing = <String>[];

  final goldenSource = _readOrNull('$root/$goldenTest');
  if (goldenSource == null) {
    missing.add('$goldenTest (no golden test file)');
  } else {
    final golden = parseTestCalls(goldenSource, path: goldenTest);
    if (!golden.parsed) {
      missing.add(_doesNotParse(goldenTest, golden));
    } else {
      // Two independent gaps, reported independently: a file that declares no
      // golden AND photographs something else owes both answers, and an
      // `else if` would hand back one of them.
      if (!golden.declaresAGolden()) {
        missing.add(
          '$goldenTest exists but declares no golden test (a goldenTest…(…) '
          'call in live code — a mention in a comment does not count)',
        );
      }
      // [goldenSubject] is null for screens: the screen rule holds its subject
      // as a file stem, and deriving `ProfileScreen` from `profile_screen` is a
      // PascalCase guess. The widget rule holds the real class name, so only it
      // passes one — the screen rule's behaviour is unchanged by construction.
      if (goldenSubject != null && !golden.mentions(goldenSubject)) {
        missing.add(
          '$goldenTest never names $goldenSubject in live code, so whatever it '
          'photographs, it is not $goldenSubject (a mention in a comment, a doc '
          'comment or a string does not count). Build the widget the golden is '
          'named after',
        );
      }
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
      if (!semanticsGate.isSatisfiedBy(semantics)) {
        missing.add(semanticsGate.describeGap(semanticsTest, semantics));
      }
    }
  }

  return missing;
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

    return ScreenCoverage(
      screenPath: screenPath,
      screenId: screenId,
      testDir: testDir,
      missing: _missingArtifacts(
        root: root,
        testDir: testDir,
        stem: screenId,
        semanticsGate: kScreenSemanticsGate,
      ),
      exemptionReason: exemptions[screenPath],
    );
  }).toList();
}

/// The file's contents, or null when it is absent OR present-but-unreadable.
///
/// The catch is the testable half of the same failure class as the vanished
/// file: a Windows exclusive lock, a permission error, or bytes that are not
/// valid UTF-8 all reach here as a `FileSystemException` from
/// `readAsStringSync` (invalid UTF-8 included — dart:io wraps the decode
/// failure rather than letting a FormatException out). Every caller already
/// has a "cannot say what this file contains" branch, and a registry whose
/// thesis is loud failure must not answer any of them with a stack trace.
///
/// The cost, stated: for the two TEST files a caller then reports "no golden
/// test file" / "no semantics test file" about a file that does exist. That is
/// a slightly wrong noun on a gap that is real either way; the widget SOURCE
/// caller distinguishes the two and says so.
String? _readOrNull(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

// ---------------------------------------------------------------------------
// The shared-widget rule (P4b-T5b)
// ---------------------------------------------------------------------------
//
// The unit of coverage is the WIDGET, not the file. `lumen_scaffold.dart`
// declares two of them — `LumenScaffold` and `LumenBottomNav` — and a per-file
// rule would have called the file covered while the second widget shipped with
// no golden and no semantics test at all. Ruling R-07 says "13 widgets shipped"
// and "13 widgets tested" must be the same variable; the variable is a widget.
//
// So the artifacts are named after the widget (snake_cased), never after the
// file it happens to share, and every failure names both:
//
//     LumenBottomNav  (declared in lib/shared/widgets/lumen_scaffold.dart)
//         MISSING: test/widgets/lumen_bottom_nav_golden_test.dart …

/// One public widget declared under `lib/shared/widgets/`.
class DeclaredWidget {
  const DeclaredWidget({
    required this.name,
    required this.declaredIn,
    this.unclassified,
  });

  /// The class name, e.g. `LumenBottomNav`.
  final String name;

  /// Package-relative posix path of the file declaring it, e.g.
  /// `lib/shared/widgets/lumen_scaffold.dart`.
  final String declaredIn;

  /// The stem every required artifact is named after — `lumen_bottom_nav`.
  /// Derived from the WIDGET, so two widgets in one file cannot collide.
  String get artifactStem => snakeCase(name);

  /// Why this class could not be classified as a widget — `Foo extends Bar`,
  /// or the class-type-alias form — or null when its base IS a known widget
  /// base.
  ///
  /// Only ever set by [widgetsEscapingTheSharedGlob]: inside
  /// `lib/shared/widgets/` an unclassifiable class is reported as its own gap
  /// and never becomes a subject. Outside it, the canary has to carry both
  /// kinds, and they need different advice — which is what this field is for.
  final String? unclassified;

  /// A stable identity for exemptions and reporting.
  String get id => '$declaredIn#$name';

  @override
  String toString() => id;
}

/// What a parsed widget file declares.
class DeclaredWidgets {
  const DeclaredWidgets({
    required this.widgets,
    required this.unclassified,
    required this.syntaxErrors,
  });

  /// Public classes whose superclass is a known widget base.
  final List<DeclaredWidget> widgets;

  /// Public classes with an `extends` clause this registry cannot classify,
  /// as `Name extends Super`. These are NOT silently skipped: an unknown base
  /// could be a widget, and a rule that quietly ignores what it does not
  /// understand is a rule with a hole in it.
  final List<String> unclassified;

  /// Syntax errors, as `line:column message`.
  final List<String> syntaxErrors;

  bool get parsed => syntaxErrors.isEmpty;
}

/// Superclasses that make a class a widget, for the purposes of this rule.
///
/// Everything in `lib/shared/widgets/` extends `StatelessWidget` today; the
/// rest are here so the first `ConsumerWidget` or `StatefulWidget` a P4b task
/// promotes is gated on the day it lands rather than on the day someone
/// notices. An unrecognised base is reported (see [DeclaredWidgets.unclassified]),
/// not ignored.
const kWidgetSuperclasses = <String>{
  'StatelessWidget',
  'StatefulWidget',
  'ConsumerWidget',
  'ConsumerStatefulWidget',
  'InheritedWidget',
  'InheritedModel',
  'ImplicitlyAnimatedWidget',
  'AnimatedWidget',
  'LeafRenderObjectWidget',
  'SingleChildRenderObjectWidget',
  'MultiChildRenderObjectWidget',
  'PreferredSizeWidget',
};

/// Bases that are known NOT to be widgets, so a public `FooState` does not get
/// reported as an unclassified mystery. Kept deliberately short: anything not
/// on either list is reported.
const kNonWidgetSuperclasses = <String>{
  'State',
  'ConsumerState',
  'ThemeExtension',
  'ChangeNotifier',
  'Error',
  'Exception',
};

/// `LumenBottomNav` -> `lumen_bottom_nav`.
///
/// Two rules, because one is not enough: a boundary between a lower-case (or
/// digit) and an upper-case letter, and a boundary inside an acronym run before
/// its final capital (`LumenOCRField` -> `lumen_ocr_field`, not
/// `lumen_ocrfield`).
String snakeCase(String className) => className
    .replaceAllMapped(
      RegExp('(?<=[A-Z])([A-Z][a-z])'),
      (m) => '_${m[1]}',
    )
    .replaceAllMapped(RegExp('(?<=[a-z0-9])([A-Z])'), (m) => '_${m[1]}')
    .toLowerCase();

/// Parses [source] and reports the public widget classes it declares.
///
/// A class with no `extends` clause is not a widget and is not reported as
/// unclassified: a Dart class can only be a widget by extending one, so this
/// is a fact about the language rather than a guess.
DeclaredWidgets parseWidgetDeclarations(
  String source, {
  required String path,
}) {
  final result = parseString(
    content: stripBom(source),
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );

  final widgets = <DeclaredWidget>[];
  final unclassified = <String>[];

  for (final declaration in result.unit.declarations) {
    // `class LumenFoo = StatelessWidget with M;` is a ClassTypeAlias, not a
    // ClassDeclaration — a public widget this rule would otherwise not see at
    // all, which is the silent pass the whole file argues against. Its
    // superclass is a NamedType like any other, but the mixin application can
    // move behaviour into it, so it is reported for a human to classify rather
    // than accepted as a subject.
    if (declaration is ClassTypeAlias) {
      final aliasName = declaration.name.lexeme;
      if (aliasName.startsWith('_')) continue;
      unclassified.add(
        '$aliasName = ${declaration.superclass.name.lexeme} '
        '(a class type alias)',
      );
      continue;
    }
    if (declaration is! ClassDeclaration) continue;
    // analyzer 12's ClassDeclaration exposes its name through `namePart`, and
    // a NamedType's identifier through `name` — both are Tokens.
    final name = declaration.namePart.typeName.lexeme;
    if (name.startsWith('_')) continue; // private: not part of the surface
    final superclass = declaration.extendsClause?.superclass.name.lexeme;
    if (superclass == null) continue; // cannot be a widget
    if (kWidgetSuperclasses.contains(superclass)) {
      widgets.add(DeclaredWidget(name: name, declaredIn: path));
    } else if (!kNonWidgetSuperclasses.contains(superclass)) {
      unclassified.add('$name extends $superclass');
    }
  }

  return DeclaredWidgets(
    widgets: widgets,
    unclassified: unclassified,
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

/// Every `.dart` file under `lib/shared/widgets`, package-relative and sorted.
List<String> discoverSharedWidgetFiles(Directory packageRoot) =>
    _dartFilesUnder(packageRoot, 'lib/shared/widgets');

/// Every `.dart` file under `lib/shared`, wherever it sits.
///
/// The widget-rule twin of [discoverScreenFilesAnywhere]: comparing the two
/// lists is what turns "a shared widget filed one directory to the left" into
/// a loud failure instead of an ungated widget.
List<String> discoverSharedDartFiles(Directory packageRoot) =>
    _dartFilesUnder(packageRoot, 'lib/shared');

List<String> _dartFilesUnder(Directory packageRoot, String relativeDir) {
  final root = _posix(packageRoot.path);
  final dir = Directory('$root/$relativeDir');
  if (!dir.existsSync()) return const <String>[];

  final files = <String>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = _posix(entity.path);
    if (!path.endsWith('.dart')) continue;
    files.add(path.substring(root.length + 1));
  }
  files.sort();
  return files;
}

/// Public widgets — and public classes that MIGHT be widgets — declared under
/// `lib/shared` but OUTSIDE `lib/shared/widgets`, which the widget rule
/// therefore never sees.
///
/// The unclassifiable ones are included on purpose. Inside `lib/shared/widgets`
/// an unrecognised base is reported and someone classifies it; if the same
/// class sits one directory to the left, collecting only [DeclaredWidgets.widgets]
/// would let it escape the glob AND the canary that exists to catch exactly
/// that. Fail closed: report it, and let the reader say "not a widget" by
/// moving it or adding its base to [kNonWidgetSuperclasses].
List<DeclaredWidget> widgetsEscapingTheSharedGlob(Directory packageRoot) {
  final root = _posix(packageRoot.path);
  final gated = discoverSharedWidgetFiles(packageRoot).toSet();

  final escaped = <DeclaredWidget>[];
  for (final path in discoverSharedDartFiles(packageRoot)) {
    if (gated.contains(path)) continue;
    final source = _readOrNull('$root/$path');
    if (source == null) continue;
    final declared = parseWidgetDeclarations(source, path: path);
    escaped.addAll(declared.widgets);
    escaped.addAll(
      declared.unclassified.map(
        (mystery) => DeclaredWidget(
          name: mystery.split(' ').first,
          declaredIn: path,
          unclassified: mystery,
        ),
      ),
    );
  }
  return escaped;
}

/// The accessibility assertions a widget's semantics test may satisfy its gate
/// with: every top-level `expect…` function `test/support/a11y_guard.dart`
/// declares.
///
/// Discovered, not hand-listed, for the same reason the screens are: a list
/// maintained beside the thing it describes is a list that drifts from it. A
/// matcher added by a later task counts the day it is written.
///
/// Fails LOUDLY — a missing, unparseable or matcher-free guard file throws
/// rather than returning an empty set, because an empty set would make the
/// gate unsatisfiable and a caller could "fix" that by deleting the gate.
Set<String> discoverA11yMatchers(Directory packageRoot) {
  const guardPath = 'test/support/a11y_guard.dart';
  final root = _posix(packageRoot.path);
  final source = _readOrNull('$root/$guardPath');
  if (source == null) {
    throw StateError(
      'The widget coverage rule needs $guardPath to know what an accessibility '
      'assertion is, and there is no such file under $root. Point the audit at '
      'a package root that has one, or pass a11yMatchers: explicitly.',
    );
  }

  final result = parseString(
    content: stripBom(source),
    path: guardPath,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) {
    throw StateError(
      '$guardPath does not parse, so the set of accessibility matchers cannot '
      'be read: ${result.errors.take(3).map((d) => d.message).join('; ')}',
    );
  }

  final matchers = <String>{
    for (final declaration in result.unit.declarations)
      if (declaration is FunctionDeclaration &&
          RegExp(r'^expect[A-Z]').hasMatch(declaration.name.lexeme))
        declaration.name.lexeme,
  };
  if (matchers.isEmpty) {
    throw StateError(
      '$guardPath declares no top-level expect… matcher, so every widget '
      'semantics test would fail the accessibility gate. That is a broken '
      'registry, not a coverage gap.',
    );
  }
  return matchers;
}

/// One discovered shared widget and whatever its required coverage is missing.
class WidgetCoverage {
  WidgetCoverage({
    required this.subject,
    required this.declaredIn,
    required this.artifactStem,
    required this.testDir,
    required this.missing,
    required this.exemptionReason,
  });

  /// The widget's class name, or — for a problem with the FILE rather than a
  /// widget in it — a description of the file-level gap's subject.
  final String subject;

  /// Package-relative path of the file that declares it.
  final String declaredIn;

  /// The stem this subject's artifacts are named after — the WIDGET in
  /// snake_case, not the file. Empty for a file-level gap, which owes a fix
  /// rather than an artifact.
  final String artifactStem;

  /// Package-relative directory the widget's tests must live in
  /// (`test/widgets`).
  final String testDir;

  /// Human-readable descriptions of what is absent. Empty means covered.
  final List<String> missing;

  /// Non-null when this subject is on the exemption list.
  final String? exemptionReason;

  String get id => '$declaredIn#$subject';

  bool get isCovered => missing.isEmpty;
}

/// Resolves each public shared widget's required artifacts and reports gaps.
///
/// [exemptions] is keyed by [WidgetCoverage.id] (`<file>#<WidgetName>`).
/// [a11yMatchers] defaults to [discoverA11yMatchers] over the same root.
List<WidgetCoverage> auditWidgetCoverage(
  Directory packageRoot, {
  Map<String, String> exemptions = const <String, String>{},
  Set<String>? a11yMatchers,
}) {
  final root = _posix(packageRoot.path);
  final matchers = a11yMatchers ?? discoverA11yMatchers(packageRoot);

  final reports = <WidgetCoverage>[];
  for (final path in discoverSharedWidgetFiles(packageRoot)) {
    // lib/shared/widgets/x.dart -> test/widgets   (lib -> test, drop `shared`,
    // exactly as the screen rule maps lib -> test and drops `presentation`).
    final segments = path.split('/');
    final dirSegments = segments
        .sublist(0, segments.length - 1)
        .where((segment) => segment != 'shared')
        .toList();
    dirSegments[0] = 'test';
    final testDir = dirSegments.join('/');

    WidgetCoverage fileLevel(String subject, String gap) => WidgetCoverage(
      subject: subject,
      declaredIn: path,
      artifactStem: '',
      testDir: testDir,
      missing: <String>[gap],
      exemptionReason: exemptions['$path#$subject'],
    );

    final source = _readOrNull('$root/$path');
    if (source == null) {
      // Walked, then gone. Rare, but a registry whose thesis is loud failure
      // must not answer a disappearing file with a null-check TypeError.
      reports.add(
        fileLevel(
          '(unreadable file)',
          '$path was discovered by the directory walk but could not be read '
              'back — deleted mid-run, locked by another process, or not valid '
              'UTF-8. The registry cannot say what it declares',
        ),
      );
      continue;
    }
    final declared = parseWidgetDeclarations(source, path: path);

    if (!declared.parsed) {
      reports.add(
        fileLevel(
          '(unparsed file)',
          '$path does not parse, so the widgets it declares cannot be '
              'checked: ${declared.syntaxErrors.take(3).join('; ')}',
        ),
      );
      continue;
    }

    for (final mystery in declared.unclassified) {
      reports.add(
        fileLevel(
          mystery.split(' ').first,
          '$path declares public class `$mystery`, and this rule cannot tell '
              'whether that is a widget. If it is, add its base class to '
              'kWidgetSuperclasses in test/support/screen_registry.dart; if it '
              'is not, add the base to kNonWidgetSuperclasses, make the class '
              'private, or move it out of lib/shared/widgets/',
        ),
      );
    }

    if (declared.widgets.isEmpty && declared.unclassified.isEmpty) {
      reports.add(
        fileLevel(
          '(no public widget)',
          '$path is under lib/shared/widgets/ but declares no public widget, '
              'so nothing about it is gated. Move it out of the widgets '
              'directory, or make what it exports a widget',
        ),
      );
      continue;
    }

    for (final widget in declared.widgets) {
      reports.add(
        WidgetCoverage(
          subject: widget.name,
          declaredIn: path,
          artifactStem: widget.artifactStem,
          testDir: testDir,
          missing: _missingArtifacts(
            root: root,
            testDir: testDir,
            stem: widget.artifactStem,
            semanticsGate: widgetSemanticsGate(
              matchers,
              subject: widget.name,
            ),
            goldenSubject: widget.name,
          ),
          exemptionReason: exemptions[widget.id],
        ),
      );
    }
  }
  return reports;
}

/// The escape canary's failure message, with the right remedy per kind.
///
/// Two kinds land in [escaped] and they do NOT have the same fix. A public
/// widget outside `lib/shared/widgets/` should move into it. A class the rule
/// could not classify may not be a widget at all, and telling its author to
/// move it into the widgets directory is wrong advice — the fix there is to
/// name its base in [kNonWidgetSuperclasses], or to move it if it IS a widget.
String describeEscapedWidgets(List<DeclaredWidget> escaped) {
  final buffer = StringBuffer()
    ..writeln(
      'These public classes live under lib/shared but outside '
      'lib/shared/widgets/, so the widget registry never sees them and never '
      'requires a test for them:',
    );
  for (final widget in escaped) {
    buffer.writeln(
      widget.unclassified == null
          ? '  ${widget.id}  (a widget)'
          : '  ${widget.id}  (${widget.unclassified} — this rule cannot tell '
                'whether that is a widget)',
    );
  }
  buffer.writeln(
    'If it is a widget, move it into lib/shared/widgets/ so the rule gates it. '
    'If it is not, say so where the rule can read it: add its base class to '
    'kNonWidgetSuperclasses in test/support/screen_registry.dart, or move the '
    'file out of lib/shared.',
  );
  return buffer.toString();
}

/// A failure message naming every uncovered shared widget and every missing
/// file, or `null` when everything non-exempt is covered.
String? describeUncoveredWidgets(List<WidgetCoverage> reports) {
  final broken = reports
      .where((r) => !r.isCovered && r.exemptionReason == null)
      .toList();
  if (broken.isEmpty) return null;

  final buffer = StringBuffer()
    ..writeln(
      '${broken.length} shared widget(s) ship without the accessibility and '
      'golden coverage every Lumen widget must have.',
    )
    ..writeln();
  for (final widget in broken) {
    buffer.writeln('  ${widget.subject}  (declared in ${widget.declaredIn})');
    for (final missing in widget.missing) {
      buffer.writeln('      MISSING: $missing');
    }
    buffer.writeln();
  }
  buffer.writeln(
    'The unit is the WIDGET, not the file: artifacts are named after the '
    'widget in snake_case, so a file declaring two widgets owes two sets. Add '
    'the missing test(s) with goldenTestLightAndDark(...) and an '
    'a11y_guard.dart assertion. Do NOT add an exemption unless the missing '
    'work is genuinely large, and then list it in kWidgetCoverageExemptions '
    'with a TODO naming what is owed and who owes it.',
  );
  return buffer.toString();
}

/// Widget exemptions that no longer correspond to a real gap.
List<WidgetCoverage> staleWidgetExemptions(List<WidgetCoverage> reports) =>
    reports.where((r) => r.isCovered && r.exemptionReason != null).toList();

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
