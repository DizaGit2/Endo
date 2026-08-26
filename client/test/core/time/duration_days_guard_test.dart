// ---------------------------------------------------------------------------
// duration_days_guard_test.dart — P4b-T17b
// ---------------------------------------------------------------------------
//
// THE RULE THIS FILE HOLDS
//
// Production code does not compute a DATE by adding or subtracting a
// day-valued `Duration`. `d.subtract(const Duration(days: 1))` is exact
// arithmetic on an INSTANT — 86 400 seconds — and a calendar day is not
// always 86 400 seconds. On a `DateTime` carrying a zone that observes DST it
// is wrong twice a year, in both directions:
//
//   * spring-forward (a 23-hour day): from local midnight 2026-03-30 in
//     Europe/Madrid, −24 h lands on 2026-03-28 23:00 — the day BEFORE
//     yesterday. This is the defect T17 fixed in `dashboard_controller.dart`.
//   * fall-back (a 25-hour day): from 2026-10-25 23:00 in the same zone,
//     −24 h lands on 2026-10-25 00:00 — the SAME calendar day, so "yesterday"
//     silently disappears.
//
// A calendar day is what the app deals in, so calendar-field construction
// (`DateTime.utc(y, m, d - 1)`, which normalises day 0 into the previous
// month) is the only correct spelling. That is what every date computation in
// `lib/` already does — this audit is what keeps it that way after the next
// person, on the next screen, reaches for the shorter form.
//
// Why a static audit rather than a unit test: the failing case needs a
// DST-observing local zone, and Dart on this repo's primary dev machine
// (Windows, Mexico Central, no DST since 2022) IGNORES the POSIX `TZ`
// variable entirely — so the unit test that WOULD catch it passes against the
// buggy form here. The audit does not depend on the zone at all: it fails on
// the source text, in every run of `flutter test`, on every machine.
//
// What it cannot see is stated in `test/support/duration_days_guard.dart` and
// pinned by the `limits` group below. It catches the shape people write.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/duration_days_guard.dart';
import '../../support/screen_registry.dart' show resolvePackageRoot;

void main() {
  // -------------------------------------------------------------------------
  // The real tree
  // -------------------------------------------------------------------------

  group('the audit reads the real production tree', () {
    late Directory packageRoot;

    setUp(() => packageRoot = resolvePackageRoot());

    // Without this, a walker bug that finds NOTHING would make the rule below
    // pass forever — the exact failure mode of an audit nobody has seen red.
    // Discovery is shared with `formatting_guard.dart` (same `auditedFiles`),
    // where the generated-code exclusions are pinned in full; what is asserted
    // here is only that this guard is pointed at a populated tree.
    test('it finds the production sources, including the dated ones', () {
      final files = auditedDurationFiles(packageRoot);

      expect(
        files,
        contains('lib/features/symptoms/data/symptoms_repository.dart'),
      );
      expect(
        files,
        contains('lib/features/home/application/dashboard_controller.dart'),
      );
      expect(files, contains('lib/core/cache/hive_boot.dart'));
      expect(files.where((f) => f.startsWith('lib/api/')), isEmpty);
    });

    test('no production file does day-valued Duration arithmetic', () {
      final violations = auditDurationArithmetic(packageRoot);
      expect(
        violations,
        isEmpty,
        reason: describeDurationViolations(violations),
      );
    });

    test('and no line in lib/ waives the rule — the registry is EMPTY', () {
      // The same control `deviceClockWaivers` gives the device-clock rule: a
      // waiver stops being a silent local decision, because this assertion has
      // to be edited too.
      //
      // It is empty for a reason worth stating, because "no waivers" reads as
      // "nothing needed one". T17b found TWO shipped call sites —
      // `_dayWindow`'s `instant.subtract(const Duration(days: 1))` and its
      // `.add` twin in `symptoms_repository.dart` — and did NOT waive them.
      // Their safety rested on the input being a UTC instant, which nothing
      // enforced; the resolution enforces it (`.toUtc()`) and then builds the
      // neighbouring days from calendar fields, so there is no day-valued
      // Duration left to waive. A waiver resting on a dartdoc is not a
      // control.
      expect(durationDaysWaivers(packageRoot), isEmpty);
    });

    test('the legitimate absolute-time add in hive_boot is NOT reported', () {
      // `fetchedAt.add(Duration(milliseconds: ttlMs))` is a TTL on an absolute
      // instant — genuinely absolute-time arithmetic, and correctly out of
      // scope. Audited against the REAL file rather than a fixture, so a rule
      // that grew to flag every `add(Duration(...))` would fail here.
      const path = 'lib/core/cache/hive_boot.dart';
      final source = File('${packageRoot.path}/$path').readAsStringSync();
      expect(source, contains('.add(Duration(milliseconds:'));
      expect(auditDurationSource(source, path: path), isEmpty);
    });

    test(
      'the `days:` inside dashboard_controller\'s comment is NOT reported',
      () {
        // T17 left a comment reading "never `.subtract(Duration(days: 1))`".
        // A raw-text audit would flag the very comment warning against the bug.
        const path = 'lib/features/home/application/dashboard_controller.dart';
        final source = File('${packageRoot.path}/$path').readAsStringSync();
        expect(source, contains('.subtract(Duration(days:'));
        expect(auditDurationSource(source, path: path), isEmpty);
      },
    );
  });

  // -------------------------------------------------------------------------
  // …and it can go red. Against fixtures.
  // -------------------------------------------------------------------------

  group('the rule fires', () {
    test('subtracting a day-valued Duration is reported', () {
      const source = '''
class Ghost {
  DateTime yesterday(DateTime d) => d.subtract(const Duration(days: 1));
}
''';
      final violations = auditDurationSource(
        source,
        path: 'lib/features/ghost/x.dart',
      );

      expect(violations, hasLength(1));
      expect(violations.single.rule, DurationRule.dayValuedDuration);
      expect(violations.single.line, 2);
      expect(violations.single.describe(), contains('days'));
      expect(violations.single.describe(), contains('calendar'));
    });

    test('adding one is reported the same way', () {
      const source = '''
class Ghost {
  DateTime tomorrow(DateTime d) => d.add(const Duration(days: 1));
}
''';
      final violations = auditDurationSource(
        source,
        path: 'lib/features/ghost/x.dart',
      );
      expect(violations, hasLength(1));
      expect(violations.single.rule, DurationRule.dayValuedDuration);
    });

    test('`weeks:` is the same bug seven times over', () {
      const source = '''
class Ghost {
  DateTime lastWeek(DateTime d) => d.subtract(const Duration(weeks: 1));
  DateTime nextWeek(DateTime d) => d.add(const Duration(weeks: 1));
}
''';
      final violations = auditDurationSource(
        source,
        path: 'lib/features/ghost/x.dart',
      );
      expect(violations, hasLength(2));
      expect(violations.map((v) => v.line), <int>[2, 3]);
      expect(violations.first.describe(), contains('weeks'));
    });

    test('dropping `const` does not hide it', () {
      const source = '''
class Ghost {
  DateTime yesterday(DateTime d) => d.subtract(Duration(days: 1));
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        hasLength(1),
      );
    });

    test('a mixed Duration still counts if it names days', () {
      const source = '''
class Ghost {
  DateTime x(DateTime d) => d.add(const Duration(days: 1, hours: 2));
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        hasLength(1),
      );
    });

    test('the reported line is the `add`/`subtract`, not the start of the '
        'expression — so a waiver goes where the arithmetic is', () {
      const source = '''
class Ghost {
  DateTime x(DateTime d) => d
      .toUtc()
      .subtract(const Duration(days: 1));
}
''';
      final violations = auditDurationSource(
        source,
        path: 'lib/features/ghost/x.dart',
      );
      expect(violations.single.line, 4);
    });
  });

  // -------------------------------------------------------------------------
  // …and it stays quiet on everything else.
  // -------------------------------------------------------------------------

  group('the rule does not fire on', () {
    test('sub-day units — the only Durations that mean what they say', () {
      for (final unit in <String>[
        'milliseconds',
        'seconds',
        'minutes',
        'hours',
      ]) {
        final source =
            '''
class Ghost {
  DateTime x(DateTime d) => d.add(const Duration($unit: 3));
}
''';
        expect(
          auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
          isEmpty,
          reason: unit,
        );
      }
    });

    test('`days:` in a comment, a doc comment or a string', () {
      const source = '''
/// Calendar arithmetic on the day FIELD, never `.subtract(Duration(days: 1))`.
class Ghost {
  // d.subtract(const Duration(days: 1)) is what NOT to write.
  static const advice = 'never call d.add(const Duration(days: 1))';
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        isEmpty,
      );
    });

    test('a day-valued Duration that is not date arithmetic', () {
      // The rule is about `add`/`subtract` ON A DATE. A `days:`-valued
      // Duration held as a constant, or passed as a retention window, is
      // neither wrong nor this rule's business.
      const source = '''
class Ghost {
  static const retention = Duration(days: 30);
  void purge(Duration window) {}
  void run() => purge(const Duration(days: 30));
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        isEmpty,
      );
    });

    test('calendar-field construction — the shape the rule exists to push '
        'people towards', () {
      const source = '''
class Ghost {
  DateTime yesterday(DateTime d) => DateTime.utc(d.year, d.month, d.day - 1);
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        isEmpty,
      );
    });
  });

  // -------------------------------------------------------------------------
  // The limits, pinned. A limit nobody wrote down is a limit somebody will
  // later mistake for a guarantee.
  // -------------------------------------------------------------------------

  group('limits', () {
    test('`Duration(hours: 24)` is the SAME bug and is NOT caught', () {
      const source = '''
class Ghost {
  DateTime yesterday(DateTime d) => d.subtract(const Duration(hours: 24));
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        isEmpty,
      );
    });

    test('a Duration arriving through a VARIABLE is NOT caught', () {
      const source = '''
class Ghost {
  static const oneDay = Duration(days: 1);
  DateTime yesterday(DateTime d) => d.subtract(oneDay);
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        isEmpty,
      );
    });

    test('the OPERATOR form `d + const Duration(days: 1)` is NOT caught', () {
      // `DateTime` has no `operator +`, so this exact line does not compile
      // for a `DateTime` today — but it does for any type that defines one,
      // and the rule matches method NAMES, not receivers. Recorded so nobody
      // reads "the guard covers day arithmetic" off the file name.
      const source = '''
class Ghost {
  Object x(dynamic d) => d + const Duration(days: 1);
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        isEmpty,
      );
    });

    test(
      '`add`/`subtract` on something that is NOT a date is still reported',
      () {
        // The mirror-image limit: the audit does not resolve types, so a
        // `List<Duration>.add(const Duration(days: 1))` is a false positive.
        // It has no instance in `lib/` today; when one appears, the waiver is
        // the answer, and the registry test above is what makes that visible.
        const source = '''
class Ghost {
  final windows = <Duration>[];
  void seed() => windows.add(const Duration(days: 1));
}
''';
        expect(
          auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
          hasLength(1),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // The waiver, enforced exactly as `kDeviceClockEscape` is.
  // -------------------------------------------------------------------------

  group('the waiver', () {
    test('a marker WITH a reason waives it, on the line or the line above', () {
      const sameLine =
          '''
class Ghost {
  DateTime x(DateTime d) => d.add(const Duration(days: 1)); $kDurationDaysEscape a fixed-length SLA window, not a date
}
''';
      const lineAbove =
          '''
class Ghost {
  $kDurationDaysEscape a fixed-length SLA window, not a date
  DateTime x(DateTime d) => d.add(const Duration(days: 1));
}
''';
      expect(
        auditDurationSource(sameLine, path: 'lib/features/ghost/x.dart'),
        isEmpty,
      );
      expect(
        auditDurationSource(lineAbove, path: 'lib/features/ghost/x.dart'),
        isEmpty,
      );
    });

    test('a BARE marker with no reason does NOT waive it', () {
      const source =
          '''
class Ghost {
  DateTime x(DateTime d) => d.add(const Duration(days: 1)); $kDurationDaysEscape
}
''';
      final violations = auditDurationSource(
        source,
        path: 'lib/features/ghost/x.dart',
      );
      expect(
        violations,
        hasLength(1),
        reason: 'a waiver without a reason is a silent opt-out',
      );
      expect(violations.single.rule, DurationRule.dayValuedDuration);
    });

    test('a marker inside a STRING does not waive the line below it', () {
      const source =
          '''
class Ghost {
  static const help = 'mark it $kDurationDaysEscape <reason>';
  DateTime x(DateTime d) => d.add(const Duration(days: 1));
}
''';
      final violations = auditDurationSource(
        source,
        path: 'lib/features/ghost/x.dart',
      );
      expect(violations, hasLength(1));
      expect(violations.single.line, 3);
    });

    test('a marker two lines away does NOT waive it', () {
      const source =
          '''
class Ghost {
  $kDurationDaysEscape too far away to be read together
  final int filler = 0;
  DateTime x(DateTime d) => d.add(const Duration(days: 1));
}
''';
      expect(
        auditDurationSource(source, path: 'lib/features/ghost/x.dart'),
        hasLength(1),
      );
    });

    test('the waiver registry lists a waived line as `path:line`', () {
      final fixture = Directory.systemTemp.createTempSync('duration_guard_');
      addTearDown(() => fixture.deleteSync(recursive: true));
      File('${fixture.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
      final file = File('${fixture.path}/lib/features/ghost/x.dart')
        ..parent.createSync(recursive: true);
      file.writeAsStringSync('''
class Ghost {
  $kDurationDaysEscape an SLA window, not a date
  DateTime x(DateTime d) => d.add(const Duration(days: 1));
}
''');

      expect(durationDaysWaivers(fixture), <String>[
        'lib/features/ghost/x.dart:2',
      ]);
      expect(auditDurationArithmetic(fixture), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Robustness
  // -------------------------------------------------------------------------

  group('robustness', () {
    test('a file that does not parse is reported, not skipped silently', () {
      final violations = auditDurationSource(
        'class Ghost {',
        path: 'lib/features/ghost/x.dart',
      );
      expect(violations, hasLength(1));
      expect(violations.single.rule, 'does-not-parse');
    });

    test('a leading BOM does not blind the audit', () {
      // PowerShell writes UTF-8 WITH a BOM by default and this is a
      // Windows-primary repo. A BOM reaching `parseString` makes a good file
      // look broken — and a broken file cannot be audited.
      const source =
          '\u{FEFF}'
          'class Ghost {\n'
          '  DateTime x(DateTime d) => d.add(const Duration(days: 1));\n'
          '}\n';
      expect(source.codeUnitAt(0), 0xFEFF);

      final violations = auditDurationSource(
        source,
        path: 'lib/features/ghost/x.dart',
      );
      expect(violations, hasLength(1));
      expect(violations.single.rule, DurationRule.dayValuedDuration);
    });
  });

  // -------------------------------------------------------------------------
  // The walker, against a temporary tree
  // -------------------------------------------------------------------------

  group('the walker is falsifiable', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('duration_guard_');
      File('${fixture.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    void write(String relative, String content) {
      final file = File('${fixture.path}/$relative');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    const violating = '''
class Ghost {
  DateTime yesterday(DateTime d) => d.subtract(const Duration(days: 1));
}
''';

    test('a violating file anywhere under lib/ is found', () {
      write('lib/features/ghost/presentation/ghost_screen.dart', violating);

      final violations = auditDurationArithmetic(fixture);
      expect(violations, hasLength(1));
      expect(
        violations.single.path,
        'lib/features/ghost/presentation/ghost_screen.dart',
      );
      expect(describeDurationViolations(violations), contains('calendar'));
    });

    test('the same violation inside generated code is NOT reported', () {
      write('lib/api/model/ghost.dart', violating);
      write('lib/features/ghost/ghost.g.dart', violating);

      expect(auditDurationArithmetic(fixture), isEmpty);
    });

    test('describeDurationViolations is null when there is nothing to say', () {
      expect(describeDurationViolations(const []), isNull);
    });
  });
}
