// ---------------------------------------------------------------------------
// THE SCREEN REGISTRY — every screen ships with a11y + golden coverage
// (P4b-T3, ruling R-07)
// ---------------------------------------------------------------------------
//
// ## The rule
//
// Every `lib/features/**/presentation/*_screen.dart` file discovered at TEST
// TIME must have a golden test, its two committed golden PNGs, and a semantics
// test that runs the no-dingbat check. Nothing is hand-listed: the screens come
// from a filesystem walk, so shipping a screen and testing it are the same act.
//
// ## The naming convention — 13 P4b screen tasks depend on this
//
// For a screen at `lib/features/<feature>/presentation/<id>_screen.dart`, with
// stem `<id>_screen` (the basename minus `.dart`), all four of these must
// exist under `test/features/<feature>/`:
//
//   1. `<id>_screen_golden_test.dart`            — declares the goldens
//   2. `goldens/ci/<id>_screen_light.png`        — committed, 390x874 on disk
//   3. `goldens/ci/<id>_screen_dark.png`         — committed
//   4. `<id>_screen_semantics_test.dart`         — declares a widget test
//                                                  AND calls
//                                                  `expectNoDingbats(tester)`
//
// The three content checks all require a real CALL in LIVE CODE:
//   * golden file:    a `goldenTest…(…)` call
//   * semantics file: a `testWidgets…(…)` call AND an `expectNoDingbats(…)` call
//
// "…" means a wrapper is fine as long as it EXTENDS the canonical name —
// `goldenTestLightAndDark(`, `testWidgetsWithSemantics(` — rather than
// embedding it (`lumenGoldenTest(` will not match).
//
// "Call" means a real invocation in the PARSED file, not a text match. The
// file is parsed with `package:analyzer`'s `parseString` (`parseTestCalls` in
// test/support/screen_registry.dart) and the gates ask the AST what it
// invokes, so a mention inside a comment or a string literal is structurally
// incapable of satisfying one. A file that does not parse at all is itself
// reported as a gap.
//
// The case this is really defending against is not fraud: it is commenting out
// a failing body while debugging and forgetting to put it back. `flutter test`
// reports 0 tests for such a file and passes, so nothing else would notice.
//
// e.g. `lib/features/settings/presentation/profile_screen.dart` requires
// `test/features/settings/profile_screen_golden_test.dart`,
// `test/features/settings/goldens/ci/profile_screen_{light,dark}.png` and
// `test/features/settings/profile_screen_semantics_test.dart`.
//
// Use `goldenTestLightAndDark(...)` from `test/support/golden_app.dart` and the
// filenames come out right by construction. Regenerate the PNGs with
// `flutter test --update-goldens --tags golden`.
//
// ## Why the PNGs and the `expectNoDingbats` call are part of the rule
//
// Because otherwise an empty file named `foo_screen_golden_test.dart` passes.
// The PNGs prove the golden actually ran and was committed; the
// `expectNoDingbats` call is what replaced `test/shared/no_dingbats_test.dart`,
// whose screen list was hand-maintained — exactly the second registry this one
// exists to abolish. The dingbat rule now travels with each screen's semantics
// test, and this file is what makes sure it travels.
//
// ## Why this rule and not the other gates
//
// Nothing else can catch an untested screen. Goldens run with
// `obscureText: true`, so they never see a string; the coverage gate is a flat
// 60% floor against ~88% actual, so an untested screen has thousands of lines
// of headroom before it reddens anything; and a screen with no test at all
// contributes 0/0 to coverage, so it cannot lower the number by existing.
//
// ## Exemptions
//
// `kScreenCoverageExemptions` below. Adding to it is a last resort, allowed
// only when the missing test is genuinely large, and only with a TODO naming
// what is owed and who owes it. A stale entry — one whose screen is now
// covered — fails this test too, so the list cannot quietly accumulate.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/screen_registry.dart';

// ---------------------------------------------------------------------------
// Exemptions
// ---------------------------------------------------------------------------

/// Screen path -> the reason it is exempt, and what is owed.
///
/// EMPTY, and it should stay that way. Every screen in the tree as of P4b-T3
/// (welcome, account, profile, privacy, help_about, tab_placeholder) satisfies
/// the rule with no exemption. If you are about to add an entry, add the
/// missing test instead — it is three lines with `test/support/a11y_guard.dart`
/// and `goldenTestLightAndDark`.
const kScreenCoverageExemptions = <String, String>{};

void main() {
  // -------------------------------------------------------------------------
  // The rule, against the real tree
  // -------------------------------------------------------------------------

  group('screen registry', () {
    late Directory packageRoot;
    late List<ScreenCoverage> reports;

    setUpAll(() {
      packageRoot = resolvePackageRoot();
      reports = auditScreenCoverage(
        packageRoot,
        exemptions: kScreenCoverageExemptions,
      );
    });

    test('discovers the screens that exist on disk', () {
      // A registry that discovers nothing passes everything. This is the
      // canary for a broken glob or a wrong working directory.
      expect(
        reports,
        isNotEmpty,
        reason:
            'No screens discovered under ${packageRoot.path}/lib/features/**/'
            'presentation/*_screen.dart — the discovery glob is broken, and a '
            'registry that finds nothing enforces nothing.',
      );
    });

    test('no *_screen.dart under lib/features escapes the glob', () {
      // The non-empty canary above only proves the glob finds SOMETHING. It
      // stays green off the other five screens while a sixth, shipped at
      // `features/logging/screens/…` or `features/logging/ui/…`, is silently
      // undiscovered and therefore silently untested — the very bug this
      // registry exists to kill, one directory level up.
      final everywhere = discoverScreenFilesAnywhere(packageRoot).toSet();
      final discovered = discoverScreenFiles(packageRoot).toSet();
      final escaped = everywhere.difference(discovered).toList()..sort();

      expect(
        escaped,
        isEmpty,
        reason:
            'These files are named like screens but sit outside a '
            '`presentation/` directory, so the registry never sees them and '
            'never requires a test for them:\n'
            '${escaped.map((p) => '  $p').join('\n')}\n'
            'Either move the screen under `presentation/` (the convention), or '
            'rename the file so it does not end in `_screen.dart` if it is not '
            'a screen.',
      );
    });

    test('every screen has a golden test, its PNGs, and a semantics test', () {
      final failure = describeUncovered(reports);
      expect(failure, isNull, reason: failure ?? '');
    });

    test('no exemption outlives the gap it was granted for', () {
      final stale = staleExemptions(reports);
      expect(
        stale.map((s) => s.screenPath),
        isEmpty,
        reason:
            'These screens are now fully covered but are still listed in '
            'kScreenCoverageExemptions. Delete the entries — a permanent '
            'exemption list is how the rule stops meaning anything.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // The rule is falsifiable
  // -------------------------------------------------------------------------
  //
  // Run hermetically against temporary fixture trees, because the real tree is
  // (and should stay) green: a rule only ever observed passing is not known to
  // be able to fail.

  group('screen registry is falsifiable', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('screen_registry_');
      File('${fixture.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('a screen with NO tests is reported, naming all four artifacts', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');

      final reports = auditScreenCoverage(fixture);
      expect(reports, hasLength(1));
      expect(reports.single.isCovered, isFalse);

      final message = describeUncovered(reports)!;
      expect(
        message,
        contains('lib/features/ghost/presentation/ghost_screen.dart'),
      );
      expect(
        message,
        contains('test/features/ghost/ghost_screen_golden_test.dart'),
      );
      expect(
        message,
        contains('test/features/ghost/goldens/ci/ghost_screen_light.png'),
      );
      expect(
        message,
        contains('test/features/ghost/goldens/ci/ghost_screen_dark.png'),
      );
      expect(
        message,
        contains('test/features/ghost/ghost_screen_semantics_test.dart'),
      );
    });

    test('a fully covered screen is reported clean', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(fixture, feature: 'ghost', id: 'ghost_screen');

      final reports = auditScreenCoverage(fixture);
      expect(reports.single.missing, isEmpty);
      expect(describeUncovered(reports), isNull);
    });

    test('a golden test with no committed PNGs is not enough', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(
        fixture,
        feature: 'ghost',
        id: 'ghost_screen',
        pngs: false,
      );

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('ghost_screen_light.png'));
      expect(message, contains('ghost_screen_dark.png'));
      expect(message, isNot(contains('no golden test file')));
    });

    test('an empty stub test file does not satisfy the rule', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(fixture, feature: 'ghost', id: 'ghost_screen');
      // Truncate both test files to nothing but a comment.
      File(
        '${fixture.path}/test/features/ghost/ghost_screen_golden_test.dart',
      ).writeAsStringSync('// TODO: goldens\n');
      File(
        '${fixture.path}/test/features/ghost/ghost_screen_semantics_test.dart',
      ).writeAsStringSync('// TODO: semantics\n');

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('declares no golden test'));
      expect(message, contains('declares no testWidgets'));
    });

    test('a semantics test that skips the dingbat check is reported', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(fixture, feature: 'ghost', id: 'ghost_screen');
      File(
        '${fixture.path}/test/features/ghost/ghost_screen_semantics_test.dart',
      ).writeAsStringSync("void main() { testWidgets('x', (t) async {}); }");

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('does not call expectNoDingbats'));
    });

    test('an exemption suppresses the failure but is reported when stale', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      const path = 'lib/features/ghost/presentation/ghost_screen.dart';

      final exempt = auditScreenCoverage(
        fixture,
        exemptions: const {path: 'TODO(P4b-T99): owes a semantics test'},
      );
      expect(describeUncovered(exempt), isNull);
      expect(staleExemptions(exempt), isEmpty);

      // Once the screen is actually covered, the exemption is stale.
      _writeCoverage(fixture, feature: 'ghost', id: 'ghost_screen');
      final afterFix = auditScreenCoverage(
        fixture,
        exemptions: const {path: 'TODO(P4b-T99): owes a semantics test'},
      );
      expect(staleExemptions(afterFix).single.screenPath, path);
    });

    // Both idioms a real semantics test can be declared with. The house idiom
    // is `testWidgetsWithSemantics`, whose next character after `testWidgets`
    // is `W` — a plain `contains('testWidgets(')` check rejects it and tells
    // the implementer their perfectly good test "declares no testWidgets".
    for (final declarer in const ['testWidgets', 'testWidgetsWithSemantics']) {
      test('a semantics test declared with $declarer satisfies the rule', () {
        _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
        _writeCoverage(
          fixture,
          feature: 'ghost',
          id: 'ghost_screen',
          semanticsSource: _semanticsSource(declarer: declarer),
        );

        expect(describeUncovered(auditScreenCoverage(fixture)), isNull);
      });
    }

    test('a non-screen file under presentation/ is not a screen', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      File('${fixture.path}/lib/features/ghost/presentation/ghost_card.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class GhostCard {}');

      expect(discoverScreenFiles(fixture), hasLength(1));
    });

    test('a *_screen.dart outside presentation/ is not a screen', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      File('${fixture.path}/lib/features/ghost/data/cached_screen.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class CachedScreen {}');

      expect(discoverScreenFiles(fixture), hasLength(1));
    });

    test('a screen shipped outside presentation/ escapes the glob but not '
        'the escape check', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      // The realistic miss: a screen filed under `screens/` or `ui/` instead
      // of `presentation/`. The glob cannot see it, so nothing would ever
      // require a test for it — which is why the real-tree canary compares
      // these two lists.
      File('${fixture.path}/lib/features/logging/screens/symptom_screen.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class SymptomScreen {}');

      expect(discoverScreenFiles(fixture), hasLength(1));
      expect(
        discoverScreenFilesAnywhere(fixture),
        containsAll(<String>[
          'lib/features/ghost/presentation/ghost_screen.dart',
          'lib/features/logging/screens/symptom_screen.dart',
        ]),
      );
    });

    // -----------------------------------------------------------------------
    // The gates match live code, not text
    // -----------------------------------------------------------------------
    //
    // Every gate is a text match, so without scrubbing the cheapest way to
    // satisfy all three is a file that declares nothing:
    //
    //     // testWidgets( expectNoDingbats
    //     void main() {}
    //
    // `flutter test` reports 0 tests for that and passes. The realistic route
    // to it is an implementer commenting out a failing body while debugging.

    test('a semantics file whose only test is commented out FAILS', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(
        fixture,
        feature: 'ghost',
        id: 'ghost_screen',
        semanticsSource:
            '// testWidgets( expectNoDingbats\n'
            'void main() {}\n',
      );

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('declares no testWidgets'));
      expect(message, contains('does not call expectNoDingbats'));
    });

    test('a semantics file whose test is inside a BLOCK comment FAILS', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(
        fixture,
        feature: 'ghost',
        id: 'ghost_screen',
        semanticsSource:
            '/* ${_semanticsSource()} */\n'
            'void main() {}\n',
      );

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('declares no testWidgets'));
      expect(message, contains('does not call expectNoDingbats'));
    });

    test('a golden file whose only goldenTest is commented out FAILS', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(fixture, feature: 'ghost', id: 'ghost_screen');
      File(
        '${fixture.path}/test/features/ghost/ghost_screen_golden_test.dart',
      ).writeAsStringSync('// goldenTest(\nvoid main() {}\n');

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('declares no golden test'));
    });

    test('a bare MENTION of goldenTest is not a golden test', () {
      // The old gate was RegExp('goldentest', caseSensitive: false) — a
      // substring with no call shape, strictly weaker than the semantics gate
      // beside it. This is what that asymmetry let through.
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(fixture, feature: 'ghost', id: 'ghost_screen');
      File(
        '${fixture.path}/test/features/ghost/ghost_screen_golden_test.dart',
      ).writeAsStringSync('void main() { final goldenTest = 1; }\n');

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('declares no golden test'));
    });

    test('doc comments ABOUT the helpers do not mask a real test', () {
      // The other direction: scrubbing must not create false negatives. Both
      // files here are legitimate and heavily commented — including comments
      // that name the very identifiers being matched.
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(
        fixture,
        feature: 'ghost',
        id: 'ghost_screen',
        semanticsSource:
            '/// See testWidgets( and expectNoDingbats in a11y_guard.dart.\n'
            '/* a nested /* block */ comment */\n'
            "const url = 'https://example.test/testWidgets(';\n"
            '${_semanticsSource()}\n',
      );

      expect(describeUncovered(auditScreenCoverage(fixture)), isNull);
    });

    test('only a real invocation counts — not comments or strings', () {
      const source = '''
// testWidgets( in a line comment
/* testWidgets( in a /* nested */ block comment */
const a = 'testWidgets( in a string';
const b = r"testWidgets( in a raw string";
const c = \'\'\'
testWidgets( in a triple-quoted string
\'\'\';
void main() { testWidgetsWithSemantics(); }
''';

      final calls = parseTestCalls(source);

      expect(calls.parsed, isTrue);
      // Six mentions of `testWidgets(` in the text; exactly one invocation.
      expect(calls.invokedNames, contains('testWidgetsWithSemantics'));
      expect(calls.invokedNames, isNot(contains('testWidgets')));
      expect(calls.declaresAWidgetTest(), isTrue);
    });

    test('a file that does not parse is reported as a gap, not guessed at', () {
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(
        fixture,
        feature: 'ghost',
        id: 'ghost_screen',
        // Unterminated string: the old lexer would have run past it and made
        // a confident wrong call. `flutter test <one file>` never compiles
        // this file, so nothing else would contradict it.
        semanticsSource:
            "void main() { testWidgetsWithSemantics('x, (t) async {\n",
      );

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('does not parse'));
    });

    // -----------------------------------------------------------------------
    // String interpolation must not be mistaken for code
    // -----------------------------------------------------------------------
    //
    // `'day ${map['date']}'` is ONE string, but the interior quote reuses the
    // outer delimiter. A scanner that pairs quotes naively closes the string
    // early and re-enters code mode inside string content — and then a `//` or
    // `/*` sitting in there is read as a real comment opener, swallowing the
    // rest of the line (or, for an unclosed `/*`, the rest of the file)
    // INCLUDING a genuine testWidgets( call.
    //
    // That fails CLOSED: "declares no testWidgets" about a file that plainly
    // does. `route_table_test.dart` already writes
    // `_Probe('day ${state.pathParameters['date']}')`, so this is reachable in
    // this repo, not hypothetical.

    test('the repo\'s own interpolation idiom does not hide the test', () {
      // Lifted from route_table_test.dart:128, which already writes
      // `_Probe('day ${state.pathParameters['date']}')`.
      const semantics = r"""
void main() {
  testWidgetsWithSemantics('renders the day', (t) async {
    await pumpApp(t, home: _Probe('day ${state.pathParameters['date']}'));
    expectNoDingbats(t);
  });
}
""";

      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(
        fixture,
        feature: 'ghost',
        id: 'ghost_screen',
        semanticsSource: semantics,
      );

      expect(describeUncovered(auditScreenCoverage(fixture)), isNull);

      // Also assert nothing from inside the interpolation is mistaken for an
      // invocation. Under the old lexer this shape leaked `date` as live code;
      // a parser cannot leak, because interpolation contents are expressions
      // in the AST, not text.
      final calls = parseTestCalls(semantics);
      expect(calls.parsed, isTrue);
      expect(calls.invokedNames, contains('testWidgetsWithSemantics'));
      expect(calls.invokedNames, contains('expectNoDingbats'));
    });

    test(
      'a // inside an interpolation does not swallow the rest of the line',
      () {
        _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
        _writeCoverage(
          fixture,
          feature: 'ghost',
          id: 'ghost_screen',
          semanticsSource: r"""
void main() {
  final label = 'day ${map['a//b']}'; testWidgetsWithSemantics('x', (t) async { expectNoDingbats(t); });
}
""",
        );

        expect(describeUncovered(auditScreenCoverage(fixture)), isNull);
      },
    );

    test(
      'an unclosed /* inside an interpolation does not swallow the file',
      () {
        _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
        _writeCoverage(
          fixture,
          feature: 'ghost',
          id: 'ghost_screen',
          // No `*/` anywhere later, so a scanner that treats this as a real
          // block-comment opener loses every remaining line of the file.
          semanticsSource: r"""
void main() {
  final label = 'day ${map['a/*b']}';
  testWidgetsWithSemantics('x', (t) async { expectNoDingbats(t); });
}
""",
        );

        expect(describeUncovered(auditScreenCoverage(fixture)), isNull);
      },
    );

    test(
      'a comment containing } inside an interpolation does not hide the test',
      () {
        // The case that broke brace counting: the `}` inside `/* } */` was
        // read as the interpolation's closing brace, the scan resynced inside
        // string content, and `k//y`'s `//` then ate the rest of the line —
        // the whole declaration. Valid, compiling Dart.
        _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
        _writeCoverage(
          fixture,
          feature: 'ghost',
          id: 'ghost_screen',
          semanticsSource: r"""
void main() {
  final label = '${/* } */ m['k//y']}'; testWidgetsWithSemantics('x', (t) async { expectNoDingbats(t); });
}
""",
        );

        expect(describeUncovered(auditScreenCoverage(fixture)), isNull);
      },
    );

    test('interpolation contents are expressions, never invocations', () {
      // Every line is VALID Dart, and every line pairs a hostile string with a
      // real declaration that must survive it. The `void main() { … }` wrapper
      // is not decoration: a bare expression statement is illegal at the top
      // level, and with a real parser an invalid fixture is a failing fixture
      // rather than something the matcher shrugs at.
      const source = r"""
void main() {
  final a = 'day ${map['a//b']}'; testWidgetsWithSemantics('one');
  final b = 'x ${{'k': 'v'}.length} y'; goldenTestLightAndDark('two');
  final c = r'raw ${notInterpolated} text'; expectNoDingbats(t);
  final d = '${/* } */ m['k/*z']}'; testWidgetsWithSemantics('three');
}
""";

      final calls = parseTestCalls(source);

      expect(calls.parsed, isTrue);
      expect(calls.declaresAWidgetTest(), isTrue);
      expect(calls.declaresAGolden(), isTrue);
      expect(calls.callsNoDingbatGuard(), isTrue);
    });

    test('a call is a call wherever it is; only a MENTION is inert', () {
      // Replaces an assertion that could not fail: `isNot(contains(…))` on a
      // bare identifier inside an interpolation, which is a SimpleIdentifier
      // and never a MethodInvocation, so it was true by construction.
      //
      // These two differ, and that difference is the honest statement of what
      // parsing buys. A raw string has no interpolation at all, so its `${…}`
      // is inert TEXT…
      final inRawString = parseTestCalls(
        r"void main() { final s = r'${goldenTestLightAndDark()}'; }",
      );
      expect(inRawString.parsed, isTrue);
      expect(
        inRawString.declaresAGolden(),
        isFalse,
        reason: 'A raw string is text; nothing in it is an expression.',
      );

      // …whereas in a normal string the interpolation IS an expression, so a
      // call inside it is a REAL call and does satisfy the gate. Nobody writes
      // this on purpose, but the claim "nothing inside a string counts" is
      // false and must not be written down as if it were true.
      final interpolated = parseTestCalls(
        r"void main() { final s = '${goldenTestLightAndDark()}'; }",
      );
      expect(interpolated.parsed, isTrue);
      expect(
        interpolated.declaresAGolden(),
        isTrue,
        reason:
            'An invocation inside an interpolation is an invocation. What '
            'parsing rules out is a MENTION — in a comment, or in the text of '
            'a string — not an expression that happens to sit inside quotes.',
      );
    });

    // -----------------------------------------------------------------------
    // What a satisfied gate does NOT tell you
    // -----------------------------------------------------------------------
    //
    // Executable documentation for the residual, so it cannot rot into prose
    // that stops matching the code. The rule: a gate matches the NAME of a
    // syntactic invocation, and says nothing about what it resolves to,
    // whether it runs, or what it does.

    test('a conforming name is all a gate sees — resolution is out of reach', () {
      // A locally-defined no-op. Reachable, executed, and utterly useless —
      // and indistinguishable from the real thing without resolution.
      final localNoOp = parseTestCalls('''
void goldenTestStub(String s) {}
void main() { goldenTestStub('x'); }
''');
      expect(localNoOp.declaresAGolden(), isTrue);

      // A file with NO imports at all. This would never compile under a full
      // `flutter test` — but the narrow `flutter test <one-file>` command that
      // the parse gate exists to serve never compiles the audited file either.
      final noImports = parseTestCalls('''
void main() {
  testWidgetsWithSemantics('x', (t) async { expectNoDingbats(t); });
}
''');
      expect(noImports.parsed, isTrue);
      expect(noImports.declaresAWidgetTest(), isTrue);
      expect(noImports.callsNoDingbatGuard(), isTrue);

      // Both are the SAME limitation, which is why the residual is stated as a
      // rule rather than a list of examples.
      expect(
        describeGateSemantics,
        contains('says nothing about what that name resolves to'),
      );
    });

    // -----------------------------------------------------------------------
    // Byte-order marks
    // -----------------------------------------------------------------------

    test('a UTF-8 BOM does not make a good file "not parse"', () {
      // This is a Windows/PowerShell-primary repo: `>` and `Out-File` default
      // to UTF-8-WITH-BOM, and 13 later tasks each add two test files. Passing
      // the BOM through to parseString made the registry stricter than both
      // the compiler and `dart analyze`, and reported the screen as uncovered
      // with a message nobody would read as "BOM".
      const bom = '\u{FEFF}';

      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(
        fixture,
        feature: 'ghost',
        id: 'ghost_screen',
        semanticsSource: bom + _semanticsSource(),
      );

      expect(describeUncovered(auditScreenCoverage(fixture)), isNull);

      // And directly, so the failure names the cause if it ever regresses.
      final calls = parseTestCalls(bom + _semanticsSource());
      expect(
        calls.parsed,
        isTrue,
        reason:
            'A leading BOM is an encoding artifact, not source: ${calls.syntaxErrors}',
      );
      expect(stripBom('${bom}abc'), 'abc');
      expect(
        stripBom('abc'),
        'abc',
        reason: 'stripBom must be a no-op without one.',
      );
    });

    // -----------------------------------------------------------------------
    // skip: true
    // -----------------------------------------------------------------------

    test('a test declared with skip: true does not satisfy the gates', () {
      // Quieter than the commented-out body already closed: `flutter test`
      // still reports the file as containing a test, so nothing else notices.
      _writeScreen(fixture, feature: 'ghost', id: 'ghost_screen');
      _writeCoverage(
        fixture,
        feature: 'ghost',
        id: 'ghost_screen',
        semanticsSource:
            "void main() { testWidgetsWithSemantics('x', "
            '(t) async { expectNoDingbats(t); }, skip: true); }\n',
      );

      final message = describeUncovered(auditScreenCoverage(fixture))!;
      expect(message, contains('declares no testWidgets'));
      // The guard call inside a skipped test is equally dead, so it must not
      // count either — the visitor stops descending at the skipped node.
      expect(message, contains('does not call expectNoDingbats'));
    });

    test('skip: false, and a non-literal skip, still count as declared', () {
      final skipFalse = parseTestCalls(
        "void main() { testWidgetsWithSemantics('x', (t) async {}, "
        'skip: false); }',
      );
      expect(skipFalse.declaresAWidgetTest(), isTrue);

      // `skip: someFlag` needs resolution to evaluate. Deliberately treated as
      // declared — failing open here beats a spurious "declares no
      // testWidgets" on a file that may well run.
      final skipVariable = parseTestCalls(
        "void main() { testWidgetsWithSemantics('x', (t) async {}, "
        'skip: onCi); }',
      );
      expect(skipVariable.declaresAWidgetTest(), isTrue);
    });

    test('skip: true on a group also stops the descent', () {
      final calls = parseTestCalls('''
void main() {
  group('g', () {
    testWidgetsWithSemantics('x', (t) async { expectNoDingbats(t); });
  }, skip: true);
}
''');
      expect(calls.declaresAWidgetTest(), isFalse);
      expect(calls.callsNoDingbatGuard(), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

void _writeScreen(
  Directory root, {
  required String feature,
  required String id,
}) {
  File('${root.path}/lib/features/$feature/presentation/$id.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('class GhostScreen {}');
}

/// A semantics test written the way this repo's semantics tests are written —
/// `testWidgetsWithSemantics`, NOT plain `testWidgets`. The default fixture
/// uses the house idiom on purpose: a fixture that only ever exercises
/// `testWidgets(` cannot catch a content check that rejects the idiom every
/// screen task is told to use.
String _semanticsSource({String declarer = 'testWidgetsWithSemantics'}) =>
    "void main() { $declarer('x', (t) async { expectNoDingbats(t); }); }";

void _writeCoverage(
  Directory root, {
  required String feature,
  required String id,
  bool pngs = true,
  String? semanticsSource,
}) {
  final dir = '${root.path}/test/features/$feature';
  File('$dir/${id}_golden_test.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('void main() { goldenTest("x", fileName: "y"); }');
  File('$dir/${id}_semantics_test.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(semanticsSource ?? _semanticsSource());
  if (pngs) {
    for (final variant in const ['light', 'dark']) {
      File('$dir/goldens/ci/${id}_$variant.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(const <int>[0x89, 0x50, 0x4E, 0x47]);
    }
  }
}
