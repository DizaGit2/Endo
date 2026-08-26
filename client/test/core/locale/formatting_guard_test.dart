// ---------------------------------------------------------------------------
// formatting_guard_test.dart — P4b-T6
// ---------------------------------------------------------------------------
//
// THE RULE THIS FILE HOLDS
//
// A screen must not format a date, a time or a number by itself. It calls
// [LumenFormats], and the locale it passes comes from `localeProvider` — never
// from a literal, never from `DateFormat` directly, and "today" never from the
// device clock (D-05, D-12).
//
// Why a static audit rather than a widget test: a widget test can only prove
// that ONE widget consulted the provider. The thing worth preventing is the
// fourteenth screen, written months from now, quietly calling
// `DateFormat.yMd('en_US')` because that was faster — and no widget test that
// does not yet exist can catch that. This audit fails on the file, in every run
// of `flutter test`, for every screen anyone adds.
//
// What it cannot see is stated in `test/support/formatting_guard.dart`: it is a
// syntactic audit, so an alias it cannot resolve slips past. It catches the
// shape people actually write.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/formatting_guard.dart';
import '../../support/screen_registry.dart' show resolvePackageRoot;

// ---------------------------------------------------------------------------
// Fixture sources
// ---------------------------------------------------------------------------

const String _cleanScreen = '''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/locale_provider.dart';

class GhostScreen extends ConsumerWidget {
  const GhostScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return Text(LumenFormats.date(DateTime(2026, 3, 7), locale));
  }
}
''';

void main() {
  // -------------------------------------------------------------------------
  // The real tree
  // -------------------------------------------------------------------------

  group('the audit reads the real production tree', () {
    late Directory packageRoot;

    setUp(() => packageRoot = resolvePackageRoot());

    // Without this, a walker bug that finds NOTHING would make the rule below
    // pass forever — the exact failure mode of an audit nobody has seen red.
    test('it finds the production sources, and skips the generated ones', () {
      final files = auditedFiles(packageRoot);

      expect(files, contains('lib/core/formatters/lumen_formats.dart'));
      expect(files, contains('lib/core/locale/locale_provider.dart'));
      expect(
        files,
        contains('lib/features/settings/presentation/profile_screen.dart'),
      );
      expect(
        files.where((f) => f.startsWith('lib/api/')),
        isEmpty,
        reason: 'lib/api is generated; the analyzer excludes it too',
      );
      expect(files.where((f) => f.endsWith('.g.dart')), isEmpty);

      // Positive control for the line above, and an honest label on it.
      //
      // There ARE generated files on disk, so the assertion is not vacuous
      // over an empty input:
      final generatedOnDisk = Directory('${packageRoot.path}/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.g.dart'));
      expect(generatedOnDisk, isNotEmpty);

      // …but every one of them lives under `lib/api/`, which the PREVIOUS
      // assertion already excludes — so no state of `kGeneratedSuffixes` can
      // redden that line here. The suffix rule is proved where it can fail:
      // `the same violation inside generated code is NOT reported`, in the
      // walker group below, writes a `ghost.g.dart` OUTSIDE `lib/api/`.
      expect(
        // `File.uri.path` is always forward-slash, on Windows too.
        generatedOnDisk.every((file) => file.uri.path.contains('/lib/api/')),
        isTrue,
        reason:
            'a .g.dart appeared outside lib/api — the assertion above is '
            'now load-bearing here and this control should be revisited',
      );
    });

    test('no production file formats outside the locale-aware path', () {
      final violations = auditFormatting(packageRoot);
      expect(violations, isEmpty, reason: describeViolations(violations));
    });

    test('exactly three lines are allowed to read the device clock', () {
      // The waiver registry. All three are the SAME shape — an injectable
      // `clock ?? DateTime.now` default that every caller overrides in tests —
      // and none of them is a cycle date, which is what D-12 governs.
      //
      // This list is the control that makes a line-level waiver better than a
      // directory exemption: a fourth one cannot appear without this assertion
      // being edited, which is a reviewed act rather than a local decision.
      // Compared by FILE, not `file:line`: pinning the line number would make
      // an unrelated edit above either waiver fail this test, and the control
      // being defended is "who may read the clock", not "on which line". It is
      // a LIST, not a set, so a second waiver inside the same file still shows
      // up as a further entry.
      //
      // The third entry (P4b-T17) is `greeting_clock.dart`'s wall-clock
      // "Good morning/afternoon/evening" band for screen 8's greeting — a
      // deliberately non-cycle read living under `lib/core/time/`, which
      // this rule's own "no directory exemption" clause means gets it
      // nothing without the line-level waiver below also being present.
      expect(
        deviceClockWaivers(
          packageRoot,
        ).map((waiver) => waiver.split(':').first).toList(),
        <String>[
          'lib/core/auth/auth_interceptor.dart',
          'lib/core/cache/hive_boot.dart',
          'lib/core/time/greeting_clock.dart',
        ],
      );
    });
  });

  // -------------------------------------------------------------------------
  // …and it can go red. Every rule, against a fixture.
  // -------------------------------------------------------------------------

  group('direct-intl', () {
    test('a screen calling DateFormat itself is reported', () {
      const source = '''
import 'package:intl/intl.dart';

String label(DateTime d) => DateFormat.yMd('es_ES').format(d);
''';
      final violations = auditSource(
        source,
        path: 'lib/features/ghost/presentation/ghost_screen.dart',
      );

      expect(violations, hasLength(1));
      expect(violations.single.rule, FormattingRule.directIntl);
      expect(violations.single.line, 3);
      expect(violations.single.describe(), contains('DateFormat'));
    });

    test('a NumberFormat variable declaration is reported too', () {
      const source = '''
import 'package:intl/intl.dart';

NumberFormat? fmt;
''';
      final violations = auditSource(source, path: 'lib/features/ghost/x.dart');
      expect(violations.single.rule, FormattingRule.directIntl);
    });

    test('the formatter library itself may use intl — that is its job', () {
      const source = '''
import 'package:intl/intl.dart';

String date(DateTime d, String locale) => DateFormat.yMd(locale).format(d);
''';
      expect(
        auditSource(source, path: 'lib/core/formatters/lumen_formats.dart'),
        isEmpty,
      );
      expect(kIntlOwners, contains('lib/core/formatters/lumen_formats.dart'));
    });

    test('a mention in a comment, a doc comment or a string is not a use', () {
      const source = '''
/// Prefer LumenFormats over [DateFormat] — see the guard.
// DateFormat.yMd('es_ES') is what NOT to write.
const String advice = 'do not call NumberFormat directly';
''';
      expect(auditSource(source, path: 'lib/features/ghost/x.dart'), isEmpty);
    });

    test('an `import … show DateFormat` alone is not a use', () {
      const source = "import 'package:intl/intl.dart' show DateFormat;\n";
      expect(auditSource(source, path: 'lib/features/ghost/x.dart'), isEmpty);
    });
  });

  group('literal-locale', () {
    test('a hard-coded locale is reported', () {
      const source = '''
import 'package:lumen/core/formatters/lumen_formats.dart';

String label(DateTime d) => LumenFormats.date(d, 'es_ES');
''';
      final violations = auditSource(source, path: 'lib/features/ghost/x.dart');
      expect(violations, hasLength(1));
      expect(violations.single.rule, FormattingRule.literalLocale);
      expect(violations.single.describe(), contains('localeProvider'));
    });

    test('a locale read from the provider is fine', () {
      expect(
        auditSource(
          _cleanScreen,
          path: 'lib/features/ghost/presentation/ghost_screen.dart',
        ),
        isEmpty,
      );
    });

    test(
      'a same-file const string is the same hard-coding, one line later',
      () {
        const source = '''
import 'package:lumen/core/formatters/lumen_formats.dart';

const _l = 'en_US';
String label(DateTime d) => LumenFormats.date(d, _l);
''';
        final violations = auditSource(
          source,
          path: 'lib/features/ghost/x.dart',
        );
        expect(violations, hasLength(1));
        expect(violations.single.rule, FormattingRule.literalLocale);
        expect(violations.single.line, 4);
      },
    );

    test('a final string variable counts too', () {
      const source = '''
import 'package:lumen/core/formatters/lumen_formats.dart';

final fallback = 'es_ES';
String label(DateTime d) => LumenFormats.date(d, fallback);
''';
      expect(
        auditSource(source, path: 'lib/features/ghost/x.dart'),
        hasLength(1),
      );
    });

    test('an import-aliased target does not hide the call', () {
      const source = '''
import 'package:lumen/core/formatters/lumen_formats.dart' as fmt;

String label(DateTime d) => fmt.LumenFormats.date(d, 'es_ES');
''';
      final violations = auditSource(source, path: 'lib/features/ghost/x.dart');
      expect(violations, hasLength(1));
      expect(violations.single.rule, FormattingRule.literalLocale);
    });

    test('a CROSS-FILE constant is NOT caught — the limit, pinned', () {
      // `kFallbackLocale` is declared in locale_provider.dart, so seeing that
      // it holds a string needs resolution, which this audit does not do. It
      // reads as a safe default and hard-codes es-ES for an en-US user.
      // Asserted rather than left implicit: a limit nobody wrote down is a
      // limit somebody will later mistake for a guarantee.
      const source = '''
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/locale_provider.dart';

String label(DateTime d) => LumenFormats.date(d, kFallbackLocale);
''';
      expect(auditSource(source, path: 'lib/features/ghost/x.dart'), isEmpty);
    });

    test('one violation per call, not one per literal argument', () {
      const source = '''
import 'package:lumen/core/formatters/lumen_formats.dart';

String label(DateTime d) => LumenFormats.date(d, 'es_ES') + 'x';
''';
      expect(
        auditSource(source, path: 'lib/features/ghost/x.dart'),
        hasLength(1),
      );
    });
  });

  group('device-clock', () {
    const call = '''
class Ghost {
  DateTime today() => DateTime.now();
}
''';

    test('DateTime.now() in feature code is reported', () {
      final violations = auditSource(call, path: 'lib/features/cycle/x.dart');
      expect(violations, hasLength(1));
      expect(violations.single.rule, FormattingRule.deviceClock);
      expect(violations.single.line, 2);
      expect(violations.single.describe(), contains('D-12'));
    });

    test('the tear-off form is reported as well', () {
      const source = '''
class Ghost {
  Ghost({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
}
''';
      final violations = auditSource(source, path: 'lib/features/cycle/x.dart');
      expect(violations, hasLength(1));
      expect(violations.single.rule, FormattingRule.deviceClock);
    });

    test(
      'there is NO directory exemption — core is audited like everything else',
      () {
        // This replaced a `lib/core/` exemption. A directory stands in for
        // whatever is later put inside it: a future `lib/core/time/`, or a core
        // repository reading the device clock, was invisible to the rule. The
        // two real clock reads carry a line-level waiver instead (below).
        for (final path in <String>[
          'lib/core/cache/hive_boot.dart',
          'lib/core/auth/auth_interceptor.dart',
          'lib/core/router/app_router.dart',
          'lib/core/time/lumen_clock.dart',
          'lib/shared/widgets/lumen_month_grid.dart',
          'lib/app.dart',
        ]) {
          expect(auditSource(call, path: path), hasLength(1), reason: path);
        }
      },
    );

    test('the escape marker waives it, on the line or the line above', () {
      const sameLine =
          '''
class Ghost {
  DateTime stamp() => DateTime.now(); $kDeviceClockEscape not a cycle date
}
''';
      const lineAbove =
          '''
class Ghost {
  $kDeviceClockEscape not a cycle date
  DateTime stamp() => DateTime.now();
}
''';
      expect(auditSource(sameLine, path: 'lib/features/cycle/x.dart'), isEmpty);
      expect(
        auditSource(lineAbove, path: 'lib/features/cycle/x.dart'),
        isEmpty,
      );
    });

    test('a BARE marker with no reason does NOT waive it', () {
      const source =
          '''
class Ghost {
  DateTime stamp() => DateTime.now(); $kDeviceClockEscape
}
''';
      final violations = auditSource(source, path: 'lib/features/cycle/x.dart');
      expect(
        violations,
        hasLength(1),
        reason: 'a waiver without a reason is a silent opt-out',
      );
      expect(violations.single.rule, FormattingRule.deviceClock);
    });

    test('a marker inside a STRING does not waive the line below it', () {
      // The bug this closes: matching raw line text meant the help string
      // below waived the very call it was describing. `direct-intl` already
      // treats a mention in a string as not-a-use; the waiver now agrees.
      const source =
          '''
class Ghost {
  static const help = 'mark it $kDeviceClockEscape <reason>';
  DateTime stamp() => DateTime.now();
}
''';
      final violations = auditSource(source, path: 'lib/features/cycle/x.dart');
      expect(violations, hasLength(1));
      expect(violations.single.line, 3);
    });

    test('a marker two lines away does NOT waive it', () {
      const source =
          '''
class Ghost {
  $kDeviceClockEscape too far away to be read together
  final int filler = 0;
  DateTime stamp() => DateTime.now();
}
''';
      expect(
        auditSource(source, path: 'lib/features/cycle/x.dart'),
        hasLength(1),
      );
    });
  });

  group('robustness', () {
    test('a file that does not parse is reported, not skipped silently', () {
      final violations = auditSource(
        'class Ghost {',
        path: 'lib/features/ghost/x.dart',
      );
      expect(violations, hasLength(1));
      expect(violations.single.rule, 'does-not-parse');
    });

    test('a leading BOM does not blind the audit', () {
      // PowerShell's `>` and `Out-File` write UTF-8 WITH a BOM by default and
      // this is a Windows-primary repo. A BOM reaching `parseString` makes a
      // good file look broken — and a broken file cannot be audited.
      const source =
          '\u{FEFF}'
          "import 'package:intl/intl.dart';\n"
          "String label(DateTime d) => DateFormat.yMd('es_ES').format(d);\n";
      expect(source.codeUnitAt(0), 0xFEFF);

      final violations = auditSource(source, path: 'lib/features/ghost/x.dart');
      expect(violations, hasLength(1));
      expect(violations.single.rule, FormattingRule.directIntl);
    });
  });

  // -------------------------------------------------------------------------
  // The walker, against a temporary tree
  // -------------------------------------------------------------------------

  group('the walker is falsifiable', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('formatting_guard_');
      File('${fixture.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    void write(String relative, String content) {
      final file = File('${fixture.path}/$relative');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('a violating screen anywhere under lib/ is found', () {
      write(
        'lib/features/ghost/presentation/ghost_screen.dart',
        "import 'package:intl/intl.dart';\nvar f = DateFormat.yMd('es_ES');\n",
      );

      final violations = auditFormatting(fixture);
      expect(violations, hasLength(1));
      expect(
        violations.single.path,
        'lib/features/ghost/presentation/ghost_screen.dart',
      );
      expect(describeViolations(violations), contains('LumenFormats'));
    });

    test('the same violation inside generated code is NOT reported', () {
      const violating =
          "import 'package:intl/intl.dart';\nvar f = DateFormat.yMd('es_ES');\n";
      write('lib/api/model/ghost.dart', violating);
      for (final suffix in kGeneratedSuffixes) {
        write('lib/features/ghost/ghost$suffix', violating);
      }

      expect(auditFormatting(fixture), isEmpty);
      expect(describeViolations(const <FormattingViolation>[]), isNull);
    });

    test('the skipped suffixes are exactly the analyzer excludes', () {
      // Set EQUALITY, not "each of mine is in yours". The one-directional form
      // was written first and it could not fail in the direction that matters:
      // deleting a suffix from kGeneratedSuffixes left it green, which is the
      // exact drift this test exists to catch.
      final yaml = File(
        '${resolvePackageRoot().path}/analysis_options.yaml',
      ).readAsStringSync();
      final excluded = RegExp(
        r'-\s*"\*\*/\*(\.[\w.]+)"',
      ).allMatches(yaml).map((match) => match.group(1)!).toSet();

      expect(
        excluded,
        isNotEmpty,
        reason:
            'no `- "**/*.x"` entries found — either analysis_options.yaml '
            'changed shape or this regex has drifted from it',
      );
      expect(kGeneratedSuffixes.toSet(), excluded);
    });

    test('a clean tree reports nothing', () {
      write('lib/features/ghost/presentation/ghost_screen.dart', _cleanScreen);
      expect(auditFormatting(fixture), isEmpty);
    });
  });
}
