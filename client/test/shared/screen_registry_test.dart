// ---------------------------------------------------------------------------
// THE SCREEN REGISTRY — every screen ships with a11y + golden coverage
// (P4b-T3, ruling R-07)
// ---------------------------------------------------------------------------
//
// ## The rule
//
// Every `lib/features/**/presentation/*_screen.dart` file discovered at TEST
// TIME must have a golden test, its two committed golden PNGs, and a semantics
// test that runs the glyph check. Nothing is hand-listed: the screens come
// from a filesystem walk, so shipping a screen and testing it are the same act.
//
// "The glyph check" is `expectNoDingbats`, and since P4b-T5d that name is
// shorthand for a rule wider than it: any codepoint above U+007F in a rendered
// `Text` fails unless it is on `kAllowedNonAsciiGlyphs`. It was a three-item
// blocklist holding the wrong chevron, so this gate mandated a check that could
// not catch what it was named for.
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
// `flutter test --update-goldens --tags golden` **on Linux** — since P4b-T25a
// the committed images are Linux renders and the harness skips the comparison
// off Linux, so that command is a no-op on Windows or macOS. Off Linux, run
// the `regenerate-goldens` workflow (`ci-client.yml`) instead. This rule is
// about the files EXISTING; it does not care which host wrote them.
//
// ---------------------------------------------------------------------------
// THE WIDGET RULE — every shared widget ships with the same coverage
// (P4b-T5b, ruling R-07)
// ---------------------------------------------------------------------------
//
// The screen rule above cannot see `lib/shared/widgets/`: it requires
// `lib/features/**`, a `presentation/` segment AND a `_screen.dart` suffix, and
// derives its test directory from that layout. So there is a SECOND discovery
// rule, stated here beside the first because the same thirteen tasks read both.
//
// ## The unit is the WIDGET, not the file
//
// `lumen_scaffold.dart` declares two: `LumenScaffold` and `LumenBottomNav`. A
// per-file rule would have called that file covered off the first widget's
// artifacts while the second shipped with no golden and no semantics test —
// which is exactly what had happened. So every PUBLIC widget class discovered
// under `lib/shared/widgets/**.dart` is its own subject, artifacts are named
// after the WIDGET in snake_case, and every failure names the widget and the
// file it was declared in:
//
//     LumenBottomNav  (declared in lib/shared/widgets/lumen_scaffold.dart)
//         MISSING: test/widgets/lumen_bottom_nav_golden_test.dart …
//
// A file whose single widget is named after it (the norm, and the convention
// for new files) is unaffected: `LumenErrorBanner` in `lumen_error_banner.dart`
// owes `lumen_error_banner_*` either way.
//
// ## The naming convention
//
// For a public widget `LumenFooBar` declared in
// `lib/shared/widgets/<subdir?>/<file>.dart`, all four of these must exist in
// the MIRRORED test directory `test/widgets/<subdir?>/`:
//
//   1. `lumen_foo_bar_golden_test.dart`            — declares the goldens
//   2. `goldens/ci/lumen_foo_bar_light.png`        — committed
//   3. `goldens/ci/lumen_foo_bar_dark.png`         — committed
//   4. `lumen_foo_bar_semantics_test.dart`         — declares a widget test,
//                                                    NAMES the widget, and
//                                                    calls at least one
//                                                    `a11y_guard.dart` matcher
//
// The directory is `lib` -> `test` with the `shared` segment dropped, exactly
// as the screen rule maps `lib` -> `test` and drops `presentation`. Every
// widget lives directly in `lib/shared/widgets/` today, so every test lives
// directly in `test/widgets/` — but subdirectories are MIRRORED, not
// flattened: a widget at `lib/shared/widgets/forms/lumen_date_field.dart` owes
// its four artifacts under `test/widgets/forms/`. (Pinned by
// `a widget in a subdirectory owes its artifacts in the MIRRORED test dir`.)
//
// Item 4's "names the widget" is a real gate, not a description: the file must
// mention `LumenFooBar` as an identifier in live code. See the section below.
//
// ## Why the widget's semantics gate is not `expectNoDingbats`
//
// Because `expectNoDingbats` fails a tree with no `Text` in it. For a screen
// that is correct — it means the harness never mounted anything — but a widget
// is allowed to render no text at all, and `LumenStepDots` is seven coloured
// boxes. So the widget gate asks for ANY of the matchers `a11y_guard.dart`
// declares (`expectNoDingbats`, `expectLabeledButton`, `expectNoButtons`,
// `expectLiveRegion`, `expectLabeledField`, …). The vocabulary is discovered by
// parsing that file, not hand-listed here, so a matcher a later task adds
// counts on the day it is written.
//
// ## … and why the file must also NAME its widget
//
// Dropping `expectNoDingbats` dropped something else with it. That matcher
// asserts `texts, isNotEmpty`, so it fails a tree the screen was never mounted
// into — it was the screens' anti-vacuity guard as much as the dingbat rule.
// Nothing in this vocabulary can play that part: `expectNoButtons(tester)` and
// `expectNoDingbats(tester)` take no finder, so
//
//     testWidgetsWithSemantics('a11y', (t) async {
//       await pumpApp(t, home: const Text('x'));   // NOT the widget
//       expectNoButtons(t);
//     });
//
// passes at runtime and would have satisfied a matcher-only gate while the
// widget shipped untested and the registry stayed green.
//
// So the semantics file must also NAME its subject: `LumenFooBar` has to appear
// as an identifier in the parsed file. A name in a comment or in the text of a
// string is not an identifier node, so it does not count — the same structural
// property the other gates have.
//
// The gate still has teeth: `expect(find.byType(Foo), findsOneWidget)` does not
// satisfy it, and neither does mounting the widget and asserting nothing. What
// it does not prove is that the mount is what the matcher inspected; that needs
// execution, and `describeGateSemantics` states the limit.
//
// ## What is NOT gated
//
// Private widgets (`_StepDot`), classes with no `extends` clause (a Dart class
// can only be a widget by extending one), and the bases in
// `kNonWidgetSuperclasses`. Anything else public that this rule cannot classify
// is REPORTED rather than skipped — see `a public class the rule cannot
// classify is reported, not skipped`.
//
// ## Why the PNGs and the `expectNoDingbats` call are part of the rule
//
// Because otherwise an empty file named `foo_screen_golden_test.dart` passes.
// The PNGs prove the golden actually ran and was committed; the
// `expectNoDingbats` call is what replaced `test/shared/no_dingbats_test.dart`,
// whose screen list was hand-maintained — exactly the second registry this one
// exists to abolish. The glyph rule now travels with each screen's semantics
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

/// `<file>#<WidgetName>` -> the reason it is exempt, and what is owed.
///
/// Also EMPTY. P4b-T5b backfilled all eight uncovered widgets rather than
/// parking any of them, and the stale-exemption guard below means an entry
/// cannot outlive its gap.
const kWidgetCoverageExemptions = <String, String>{};

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
  // The widget rule, against the real tree
  // -------------------------------------------------------------------------

  group('widget registry', () {
    late Directory packageRoot;
    late List<WidgetCoverage> reports;

    setUpAll(() {
      packageRoot = resolvePackageRoot();
      reports = auditWidgetCoverage(
        packageRoot,
        exemptions: kWidgetCoverageExemptions,
      );
    });

    test('discovers the shared widgets that exist on disk', () {
      // Same canary as the screens': a rule that finds nothing enforces
      // nothing. Both halves matter — the files, and the widget classes parsed
      // out of them.
      expect(
        discoverSharedWidgetFiles(packageRoot),
        isNotEmpty,
        reason:
            'No .dart files found under ${packageRoot.path}/lib/shared/widgets '
            '— the widget discovery glob is broken.',
      );
      expect(
        reports,
        isNotEmpty,
        reason:
            'Files were found but no public widget was parsed out of any of '
            'them, so the rule requires nothing of anybody.',
      );
    });

    test('the a11y matcher vocabulary is read off a11y_guard.dart', () {
      // The widget semantics gate is satisfiable only by these names, so a
      // vocabulary that silently came back empty would make every widget look
      // uncovered — and the cheap "fix" for that is to delete the gate.
      final matchers = discoverA11yMatchers(packageRoot);

      expect(matchers, contains('expectNoDingbats'));
      expect(matchers, contains('expectLabeledButton'));
      expect(
        matchers,
        isNot(contains('testWidgetsWithSemantics')),
        reason:
            'Only the expect… assertions are matchers; the declarer wrapper is '
            'not one, or "declares a test" would satisfy "asserts something".',
      );
    });

    test('every shared widget has a golden test, its PNGs, and a semantics '
        'test', () {
      final failure = describeUncoveredWidgets(reports);
      expect(failure, isNull, reason: failure ?? '');
    });

    test('LumenBottomNav is a subject in its own right', () {
      // The multi-widget file, pinned by name. `lumen_scaffold.dart` declares
      // two widgets; a per-FILE rule would report it covered off
      // `LumenScaffold`'s artifacts alone, which is how the second widget
      // shipped with no golden and no semantics test in the first place.
      expect(
        reports.map((r) => r.id),
        containsAll(<String>[
          'lib/shared/widgets/lumen_scaffold.dart#LumenScaffold',
          'lib/shared/widgets/lumen_scaffold.dart#LumenBottomNav',
        ]),
      );

      // And its artifacts are named after IT. Without this the rule could
      // enumerate both widgets and still look them both up under
      // `lumen_scaffold_*`, which exists — so the tree would be green while
      // LumenBottomNav had no golden of its own.
      final nav = reports.singleWhere((r) => r.subject == 'LumenBottomNav');
      expect(nav.artifactStem, 'lumen_bottom_nav');
      expect(nav.testDir, 'test/widgets');
    });

    test('no public widget under lib/shared escapes the widgets/ glob', () {
      final escaped = widgetsEscapingTheSharedGlob(packageRoot);

      // The message comes from the mechanism, not from this reason: the canary
      // carries two kinds of escapee (a widget, and a class the rule cannot
      // classify) and they do NOT have the same remedy.
      expect(
        escaped.map((w) => w.id).toList()..sort(),
        isEmpty,
        reason: describeEscapedWidgets(escaped),
      );
    });

    test('no widget exemption outlives the gap it was granted for', () {
      expect(
        staleWidgetExemptions(reports).map((r) => r.id),
        isEmpty,
        reason:
            'These widgets are now fully covered but are still listed in '
            'kWidgetCoverageExemptions. Delete the entries.',
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

  // -------------------------------------------------------------------------
  // The widget rule is falsifiable
  // -------------------------------------------------------------------------
  //
  // Same discipline as the screen rule's fixtures: hermetic package trees under
  // `Directory.systemTemp`, so the real tree can stay green while every branch
  // of the rule is watched to fail.

  group('widget registry is falsifiable', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('widget_registry_');
      File('${fixture.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
      // Every fixture gets a guard file, because the vocabulary is DISCOVERED
      // from one — see `the matcher vocabulary is read from the guard file`.
      _writeA11yGuard(fixture);
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('a widget with NO tests is reported, naming all four artifacts', () {
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);

      final reports = auditWidgetCoverage(fixture);
      expect(reports, hasLength(1));
      expect(reports.single.isCovered, isFalse);

      final message = describeUncoveredWidgets(reports)!;
      expect(message, contains('LumenGhost'));
      expect(message, contains('lib/shared/widgets/lumen_ghost.dart'));
      expect(message, contains('test/widgets/lumen_ghost_golden_test.dart'));
      expect(message, contains('test/widgets/goldens/ci/lumen_ghost_light.png'));
      expect(message, contains('test/widgets/goldens/ci/lumen_ghost_dark.png'));
      expect(message, contains('test/widgets/lumen_ghost_semantics_test.dart'));
    });

    test('a fully covered widget is reported clean', () {
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');

      expect(describeUncoveredWidgets(auditWidgetCoverage(fixture)), isNull);
    });

    test('a file declaring TWO widgets owes TWO artifact sets', () {
      // The `lumen_scaffold.dart` case, hermetically. Covering the first widget
      // is what a per-FILE rule would have accepted; here the second is still
      // reported, by NAME, with the file it was declared in.
      _writeWidgetFile(
        fixture,
        file: 'lumen_ghost.dart',
        widgets: ['LumenGhost', 'LumenGhostBar'],
      );
      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');

      final reports = auditWidgetCoverage(fixture);
      expect(reports.map((r) => r.subject), ['LumenGhost', 'LumenGhostBar']);
      expect(reports.first.isCovered, isTrue);

      final message = describeUncoveredWidgets(reports)!;
      expect(message, contains('1 shared widget(s)'));
      expect(
        message,
        contains('LumenGhostBar  (declared in lib/shared/widgets/lumen_ghost.dart)'),
        reason:
            'The failure has to name the widget AND its file: "lumen_ghost.dart '
            'is uncovered" is unactionable when the file is covered for one of '
            'the two widgets in it.',
      );
      // Named after the WIDGET, not the file it shares.
      expect(message, contains('test/widgets/lumen_ghost_bar_golden_test.dart'));
    });

    test('artifacts are named after the widget, in snake_case', () {
      expect(snakeCase('LumenBottomNav'), 'lumen_bottom_nav');
      expect(snakeCase('LumenScaffold'), 'lumen_scaffold');
      // An acronym run keeps its boundary at the LAST capital, so a future
      // `LumenOCRField` does not become `lumen_ocrfield`.
      expect(snakeCase('LumenOCRField'), 'lumen_ocr_field');
    });

    test('a private widget class is not a subject', () {
      _writeWidgetFile(
        fixture,
        file: 'lumen_ghost.dart',
        widgets: ['LumenGhost'],
        extra: 'class _GhostDot extends StatelessWidget {}\n',
      );
      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');

      expect(auditWidgetCoverage(fixture).map((r) => r.subject), ['LumenGhost']);
      expect(describeUncoveredWidgets(auditWidgetCoverage(fixture)), isNull);
    });

    test('a known non-widget base is not a subject', () {
      _writeWidgetFile(
        fixture,
        file: 'lumen_ghost.dart',
        widgets: ['LumenGhost'],
        extra: 'class LumenGhostState extends State<LumenGhost> {}\n',
      );
      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');

      expect(describeUncoveredWidgets(auditWidgetCoverage(fixture)), isNull);
    });

    test('a public class the rule cannot classify is reported, not skipped', () {
      // Fail closed. An unrecognised base COULD be a widget (a project-local
      // base class, a package's), and quietly ignoring what it does not
      // understand is how a rule acquires a hole.
      _writeWidgetFile(
        fixture,
        file: 'lumen_ghost.dart',
        widgets: ['LumenGhost'],
        extra: 'class LumenSpectre extends SomeLocalBase {}\n',
      );
      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('LumenSpectre extends SomeLocalBase'));
      expect(message, contains('kWidgetSuperclasses'));
      expect(message, contains('kNonWidgetSuperclasses'));
    });

    test('a widget file that declares no public widget is reported', () {
      // Not a coverage gap so much as a hole in the gate: a file sitting in
      // lib/shared/widgets/ that the rule requires nothing of.
      File('${fixture.path}/lib/shared/widgets/helpers.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('int twice(int x) => x * 2;\n');

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('declares no public widget'));
      expect(message, contains('lib/shared/widgets/helpers.dart'));
    });

    test('a widget file that does not parse is reported as a gap', () {
      File('${fixture.path}/lib/shared/widgets/lumen_ghost.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class LumenGhost extends StatelessWidget {\n');

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('does not parse'));
    });

    test('a semantics test that asserts nothing does not satisfy the gate', () {
      // The whole point of the second gate. This file declares a widget test,
      // mounts something and checks it rendered — which is what "we have a
      // test" usually means and is not accessibility coverage.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource:
            "void main() { testWidgets('renders', (t) async { "
            'expect(find.byType(LumenGhost), findsOneWidget); }); }\n',
      );

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('makes no accessibility assertion'));
      // The message lists what WOULD satisfy it, so nobody has to go looking.
      expect(message, contains('expectNoDingbats'));
    });

    test('ANY a11y_guard matcher satisfies the gate, not just dingbats', () {
      // The widget rule's deliberate difference from the screen rule: a widget
      // that renders no Text (LumenStepDots) cannot call expectNoDingbats,
      // which fails an empty-Text tree by design. It still has to MOUNT its
      // subject — see the next test, which is the half this fixture used to
      // codify as acceptable.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource: _widgetSemanticsSource(matcher: 'expectNoButtons'),
      );

      expect(describeUncoveredWidgets(auditWidgetCoverage(fixture)), isNull);
    });

    test('a semantics test that never mounts its subject FAILS', () {
      // The vacuity a matcher-only gate allowed. Every matcher a text-free
      // widget can use (expectNoButtons, expectNoDingbats) takes no finder, so
      // this file passes at runtime while asserting nothing whatsoever about
      // LumenGhost.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource: _neverMountsSource(),
      );

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('never names LumenGhost in live code'));
      // And it is not the OTHER half complaining: this file does call a
      // matcher.
      expect(message, isNot(contains('makes no accessibility assertion')));
    });

    test('a MENTION of the subject is not a mount', () {
      // The subject binding is structural, like every other gate here: a
      // comment or a string naming the widget contains no identifier node.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource:
            '// TODO: mount LumenGhost here once the fixture exists\n'
            "const owed = 'LumenGhost';\n"
            '${_neverMountsSource()}',
      );

      expect(
        describeUncoveredWidgets(auditWidgetCoverage(fixture)),
        contains('never names LumenGhost in live code'),
      );
    });

    test('a DOC comment naming the subject is not a mount', () {
      // The form that survived round 1, and the one this repo actually writes:
      // `/// Pumps [LumenGhost] under the harness` on a helper. A doc comment is
      // part of the AST — `[LumenGhost]` is a CommentReference holding a real
      // SimpleIdentifier — so the visitor has to refuse it on purpose. Left
      // alone, a helper's dartdoc keeps the gate green forever after the helper
      // stops pumping the widget.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource:
            '/// Pumps [LumenGhost] under the harness.\n'
            '${_neverMountsSource()}',
      );

      expect(
        describeUncoveredWidgets(auditWidgetCoverage(fixture)),
        contains('never names LumenGhost in live code'),
      );
    });

    test('an import combinator naming the subject is not a mount', () {
      // `show LumenGhost` names it without using it, and is what a file left
      // behind after its last real reference was deleted looks like.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource:
            "import 'package:fixture/lumen_ghost.dart' show LumenGhost;\n"
            '${_neverMountsSource()}',
      );

      expect(
        describeUncoveredWidgets(auditWidgetCoverage(fixture)),
        contains('never names LumenGhost in live code'),
      );
    });

    test('a hide combinator naming the subject is not a mount', () {
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource:
            "import 'package:fixture/everything.dart' hide LumenGhost;\n"
            '${_neverMountsSource()}',
      );

      expect(
        describeUncoveredWidgets(auditWidgetCoverage(fixture)),
        contains('never names LumenGhost in live code'),
      );
    });

    test('refusing doc comments does not change what a file DECLARES', () {
      // The other direction: the three overrides must not cost the file its
      // invocations. A comment cannot contain one, so this is an equality, not
      // a hope.
      const documented = """
/// Pumps [LumenGhost]. See [expectNoDingbats] and [goldenTestLightAndDark].
void main() {
  testWidgetsWithSemantics('a11y', (t) async {
    await pumpApp(t, home: const LumenGhost());
    expectNoDingbats(t);
  });
}
""";

      final calls = parseTestCalls(documented);

      expect(calls.declaresAWidgetTest(), isTrue);
      expect(calls.callsNoDingbatGuard(), isTrue);
      expect(calls.mentions('LumenGhost'), isTrue, reason: 'It IS mounted.');
      // Named only in the doc comment, nowhere in live code.
      expect(calls.mentions('goldenTestLightAndDark'), isFalse);
      expect(calls.declaresAGolden(), isFalse);
    });

    test('naming the subject through a finder counts as much as building it', () {
      // find.byType(LumenGhost) names the type through a SimpleIdentifier
      // rather than a NamedType. Both are live code and both must count, or a
      // legitimate test that pumps through a local helper would be rejected.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource:
            "void main() { testWidgetsWithSemantics('a11y', (t) async { "
            'await pumpGhost(t); '
            "expectLabeledButton(t, find.byType(LumenGhost), 'x'); }); }\n",
      );

      expect(describeUncoveredWidgets(auditWidgetCoverage(fixture)), isNull);
    });

    test('a subject named only inside a skipped test does not count', () {
      // Consistent with the skip: true rule the declaration gates already have
      // — everything inside a skipped declaration is dead, the mount included.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource:
            "void main() { testWidgetsWithSemantics('a11y', (t) async { "
            'await pumpApp(t, home: const LumenGhost()); expectNoButtons(t); }, '
            'skip: true); }\n',
      );

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('declares no testWidgets'));
      expect(message, contains('never names LumenGhost in live code'));
    });

    test('the matcher vocabulary is read from the guard file, not hand-listed',
        () {
      // Both directions, against a guard file that declares ONE matcher nobody
      // has ever written: a test calling it passes, and a test calling the real
      // repo's `expectNoDingbats` — absent from THIS guard file — fails.
      _writeA11yGuard(fixture, matchers: const ['expectTheSkyIsBlue']);
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);

      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource: _widgetSemanticsSource(matcher: 'expectTheSkyIsBlue'),
      );
      expect(
        describeUncoveredWidgets(auditWidgetCoverage(fixture)),
        isNull,
        reason: 'A matcher the guard file declares must count.',
      );

      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource: _widgetSemanticsSource(),
      );
      expect(
        describeUncoveredWidgets(auditWidgetCoverage(fixture)),
        contains('makes no accessibility assertion'),
        reason:
            'A name that is NOT in this package\'s guard file must not count, '
            'or the vocabulary is a constant with extra steps.',
      );
    });

    test('a MENTION of a matcher does not satisfy the widget gate', () {
      // Inherited from the screen gates, pinned on the widget path: the check
      // is over the parsed AST, so a comment or a string cannot satisfy it.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_ghost',
        semanticsSource:
            '// expectNoDingbats(tester) — commented out while debugging\n'
            "const note = 'expectNoDingbats(t)';\n"
            "void main() { testWidgetsWithSemantics('x', (t) async { "
            'await pumpApp(t, home: const LumenGhost()); }); }\n',
      );

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('makes no accessibility assertion'));
    });

    test('a package with no a11y_guard.dart fails LOUDLY', () {
      // Fail closed: an empty vocabulary would make the gate unsatisfiable,
      // and the cheapest way out of an unsatisfiable gate is deleting it.
      File('${fixture.path}/test/support/a11y_guard.dart').deleteSync();
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);

      expect(
        () => auditWidgetCoverage(fixture),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('test/support/a11y_guard.dart'),
          ),
        ),
      );
    });

    test('a guard file that declares no matcher fails LOUDLY', () {
      _writeA11yGuard(fixture, matchers: const []);
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);

      expect(
        () => auditWidgetCoverage(fixture),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('declares no top-level expect'),
          ),
        ),
      );
    });

    test('a widget outside lib/shared/widgets escapes the glob but not the '
        'escape check', () {
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      File('${fixture.path}/lib/shared/lumen_stray.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class LumenStray extends StatelessWidget {}\n');
      // A stray on a base the rule cannot classify escapes the glob just as
      // completely. Inside lib/shared/widgets it would have been reported, so
      // the canary has to carry it out here too.
      File('${fixture.path}/lib/shared/lumen_mystery.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class LumenMystery extends SomeLocalBase {}\n');

      expect(auditWidgetCoverage(fixture).map((r) => r.subject), ['LumenGhost']);
      expect(
        widgetsEscapingTheSharedGlob(fixture).map((w) => w.id).toList()..sort(),
        <String>[
          'lib/shared/lumen_mystery.dart#LumenMystery',
          'lib/shared/lumen_stray.dart#LumenStray',
        ],
      );
    });

    test('a golden test that never names its widget FAILS', () {
      // The same hole as the semantics gate's, on the other side: a golden that
      // photographs something else proves nothing about this widget, and the
      // two committed PNGs make it look thoroughly covered.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');
      File('${fixture.path}/test/widgets/lumen_ghost_golden_test.dart')
          .writeAsStringSync(
        "void main() { goldenTest('x', fileName: 'y', "
        'builder: () => const SomethingElse()); }\n',
      );

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('never names LumenGhost in live code'));
      expect(message, contains('lumen_ghost_golden_test.dart'));
      // Not the declaration gate complaining: this file does declare a golden.
      expect(message, isNot(contains('declares no golden test')));
    });

    test('a golden file failing BOTH gates reports both', () {
      // The reason the subject check is its own `if` rather than an `else if`:
      // one answer would send the reader round twice.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');
      File('${fixture.path}/test/widgets/lumen_ghost_golden_test.dart')
          .writeAsStringSync('void main() { final x = 1; }\n');

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('declares no golden test'));
      expect(message, contains('never names LumenGhost in live code'));
    });

    test('a widget source that exists but cannot be read is reported', () {
      // Not the vanished-file race (which no fixture can produce), but its
      // testable sibling: a file that is there and unreadable — a lock, a
      // permission error, or bytes that are not valid UTF-8. Without the catch
      // this throws a FileSystemException out of the audit.
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      File('${fixture.path}/lib/shared/widgets/lumen_ghost.dart')
          .writeAsBytesSync(const <int>[0xFF, 0xFE, 0x00, 0x41]);

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('could not be read back'));
      expect(message, contains('lumen_ghost.dart'));
    });

    test('a widget in a subdirectory owes its artifacts in the MIRRORED test '
        'dir', () {
      // The convention block says subdirectories are mirrored rather than
      // flattened. This is that sentence, executable.
      _writeWidgetFile(
        fixture,
        file: 'forms/lumen_date_field.dart',
        widgets: ['LumenDateField'],
      );

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(
        message,
        contains('test/widgets/forms/lumen_date_field_golden_test.dart'),
      );

      _writeWidgetCoverage(
        fixture,
        stem: 'lumen_date_field',
        subject: 'LumenDateField',
        dir: 'test/widgets/forms',
      );
      expect(describeUncoveredWidgets(auditWidgetCoverage(fixture)), isNull);
    });

    test('a public class type alias is reported, not silently invisible', () {
      // `class LumenAlias = StatelessWidget with M;` is a ClassTypeAlias, not a
      // ClassDeclaration — so before this it was neither a subject nor an
      // unclassified mystery. It was nothing at all, which is the one outcome
      // this rule may not have.
      _writeWidgetFile(
        fixture,
        file: 'lumen_ghost.dart',
        widgets: ['LumenGhost'],
        extra: 'mixin M on StatelessWidget {}\n'
            'class LumenAlias = StatelessWidget with M;\n',
      );
      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');

      final message = describeUncoveredWidgets(auditWidgetCoverage(fixture))!;
      expect(message, contains('LumenAlias = StatelessWidget'));
      expect(message, contains('class type alias'));
    });

    test('the escape message gives the RIGHT remedy for each kind', () {
      // A widget outside the directory should move into it. A class the rule
      // cannot classify may not be a widget at all, and "move it into
      // lib/shared/widgets/" is wrong advice for it — the fix is to say what
      // its base is.
      File('${fixture.path}/lib/shared/lumen_stray.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class LumenStray extends StatelessWidget {}\n');
      File('${fixture.path}/lib/shared/lumen_mystery.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class LumenMystery extends SomeLocalBase {}\n');

      final message = describeEscapedWidgets(
        widgetsEscapingTheSharedGlob(fixture),
      );

      expect(message, contains('lumen_stray.dart#LumenStray  (a widget)'));
      expect(
        message,
        contains('LumenMystery extends SomeLocalBase'),
        reason:
            'The canary must keep WHY the class was not classified, or it '
            'cannot tell the two kinds apart and the advice is a coin flip.',
      );
      expect(message, contains('cannot tell'));
      expect(message, contains('kNonWidgetSuperclasses'));
      expect(message, contains('move it into lib/shared/widgets/'));
    });

    test('an exemption suppresses the failure but is reported when stale', () {
      _writeWidgetFile(fixture, file: 'lumen_ghost.dart', widgets: ['LumenGhost']);
      const id = 'lib/shared/widgets/lumen_ghost.dart#LumenGhost';
      const exemptions = {id: 'TODO(P4b-T99): owes a golden'};

      final exempt = auditWidgetCoverage(fixture, exemptions: exemptions);
      expect(describeUncoveredWidgets(exempt), isNull);
      expect(staleWidgetExemptions(exempt), isEmpty);

      _writeWidgetCoverage(fixture, stem: 'lumen_ghost');
      final afterFix = auditWidgetCoverage(fixture, exemptions: exemptions);
      expect(staleWidgetExemptions(afterFix).single.id, id);
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

// --- widget-rule fixtures --------------------------------------------------

/// A file under `lib/shared/widgets/` declaring [widgets] as public
/// `StatelessWidget`s, plus whatever [extra] declarations the case needs.
void _writeWidgetFile(
  Directory root, {
  required String file,
  required List<String> widgets,
  String extra = '',
}) {
  final source = StringBuffer("import 'package:flutter/material.dart';\n\n");
  for (final widget in widgets) {
    source.writeln('class $widget extends StatelessWidget {}');
  }
  source.write(extra);

  File('${root.path}/lib/shared/widgets/$file')
    ..createSync(recursive: true)
    ..writeAsStringSync(source.toString());
}

/// A widget semantics test written the way the convention requires: it MOUNTS
/// its subject and asserts something from the a11y vocabulary.
///
/// The mount is not decoration in this fixture either — it is what the gate's
/// subject binding checks, so a fixture that skipped it would be testing a
/// weaker rule than the one that ships.
String _widgetSemanticsSource({
  String subject = 'LumenGhost',
  String matcher = 'expectNoDingbats',
  String declarer = 'testWidgetsWithSemantics',
}) =>
    "void main() { $declarer('x', (t) async { "
    'await pumpApp(t, home: const $subject()); $matcher(t); }); }';

/// A semantics test that calls a matcher but never builds its subject — green
/// at runtime, and worthless.
String _neverMountsSource() =>
    "void main() { testWidgetsWithSemantics('a11y', (t) async { "
    "await pumpApp(t, home: const Text('x')); expectNoButtons(t); }); }\n";

/// The four artifacts a widget owes, under `test/widgets/`.
void _writeWidgetCoverage(
  Directory root, {
  required String stem,
  String subject = 'LumenGhost',
  bool pngs = true,
  String? semanticsSource,
  String dir = 'test/widgets',
}) {
  File('${root.path}/$dir/${stem}_golden_test.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      // Names the subject: the golden gate binds to it too, for the same
      // reason the semantics gate does.
      'void main() { goldenTest("x", fileName: "y", '
      'builder: () => const $subject()); }',
    );
  File('${root.path}/$dir/${stem}_semantics_test.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      semanticsSource ?? _widgetSemanticsSource(subject: subject),
    );
  if (pngs) {
    for (final variant in const ['light', 'dark']) {
      File('${root.path}/$dir/goldens/ci/${stem}_$variant.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(const <int>[0x89, 0x50, 0x4E, 0x47]);
    }
  }
}

/// A stand-in `test/support/a11y_guard.dart` declaring [matchers].
///
/// Written per fixture rather than pointed at the real one, so the tests can
/// show that the vocabulary really is read out of this file — including the
/// case where it declares a matcher that exists nowhere in the repo.
void _writeA11yGuard(
  Directory root, {
  List<String> matchers = const [
    'expectNoDingbats',
    'expectNoButtons',
    'expectLabeledButton',
  ],
}) {
  final source = StringBuffer('// fixture guard\n');
  for (final matcher in matchers) {
    source.writeln('void $matcher(Object tester) {}');
  }
  // A non-matcher top-level function, so "every top-level function" would be a
  // visibly wrong implementation.
  source.writeln('void pumpApp(Object tester) {}');

  File('${root.path}/test/support/a11y_guard.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(source.toString());
}

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
