// ---------------------------------------------------------------------------
// duration_days_guard.dart — "a calendar day is not 86 400 seconds" audit
// (P4b-T17b)
// ---------------------------------------------------------------------------
//
// Read `test/core/time/duration_days_guard_test.dart` for the rule and why it
// exists. This file is only the mechanism: it parses every production source
// and reports every `add`/`subtract` whose argument is a `Duration` naming
// `days:` or `weeks:`. It is kept separate from the test so the audit can be
// pointed at a temporary fixture tree and watched to go red — same convention
// as `formatting_guard.dart` and `screen_registry.dart`, for the same reason.
//
// WHAT THIS CAN AND CANNOT SEE. Like the other two, this is a purely SYNTACTIC
// audit: `parseString`, no resolution. Stated as the list of things that pass
// clean, because an audit whose limits are vague gets read as a guarantee it
// never made — every one of these is pinned by a test in the `limits` group:
//
//   * `Duration(hours: 24)` — the IDENTICAL bug, spelled in a unit this rule
//     does not look at. Nothing here sees it.
//   * A `Duration` arriving through a VARIABLE (`static const oneDay =
//     Duration(days: 1); d.subtract(oneDay)`). Seeing through the name needs
//     resolution; only a `Duration` literal written at the call site is
//     matched.
//   * The OPERATOR form (`d + const Duration(days: 1)`). The rule matches
//     method invocations named `add`/`subtract`, and an operator is not one.
//     `DateTime` defines no `operator +` today, so this costs nothing for
//     dates — but the gap is real for any type that does.
//   * Nothing is TYPE-checked, in either direction. `list.add(const
//     Duration(days: 1))` on a `List<Duration>` IS reported (a false positive
//     with no instance in `lib/` today), and an `add`/`subtract` on a
//     non-`DateTime` receiver is reported the same way. When a real one
//     appears, the waiver is the answer and [durationDaysWaivers] is what
//     makes it visible.
//
// This rule is about DATES. Sub-day units are exact by definition and are not
// touched: `hive_boot.dart`'s `fetchedAt.add(Duration(milliseconds: ttlMs))`
// is a TTL on an absolute instant, which is genuinely absolute-time
// arithmetic and correctly out of scope.
//
// A `days:` occurrence inside a comment or a string literal is invisible here,
// and that is the point — `dashboard_controller.dart` carries a comment
// warning against the very form this audit bans, and a raw-text scan would
// flag the warning. The exclusion is not a branch that can be deleted: it
// falls out of reading the AST rather than the file's text.
//
// There is NO directory exemption. Every audited file is subject to the rule;
// the escape hatch is line-level ([kDurationDaysEscape]) and enumerable
// ([durationDaysWaivers]), so "who is allowed day-valued Duration arithmetic"
// is an answerable question rather than a directory that quietly covers
// whatever is put inside it. As of T17b the answer is: nobody.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

// Discovery and the comment-token walk are SHARED with the formatting audit
// rather than re-derived: two audits over "every production file" must not be
// able to disagree about which files those are, and the BOM lesson has one
// implementation (`stripBom`, imported there from `screen_registry.dart`) for
// the same reason. Widening `auditedFiles` widens both audits — that coupling
// is deliberate, and the review of that one line is the control.
import 'formatting_guard.dart' show auditedFiles, lineComments;
import 'screen_registry.dart' show stripBom;

// ---------------------------------------------------------------------------
// Rule
// ---------------------------------------------------------------------------

/// Rule names, so a test asserts on a constant rather than on prose.
abstract final class DurationRule {
  /// `add`/`subtract` of a `Duration` naming `days:` or `weeks:`.
  static const String dayValuedDuration = 'day-valued-duration';
}

/// The `Duration` fields that do not mean a fixed number of seconds once a
/// zone is involved.
///
/// `weeks:` is here for the same reason `days:` is — it is seven of them, and
/// a week that crosses a DST boundary is 167 or 169 hours long.
const Set<String> kDayValuedFields = <String>{'days', 'weeks'};

/// The line comment that opts one line out of [DurationRule.dayValuedDuration].
///
/// Deliberately explicit and greppable, and enforced exactly the way
/// `kDeviceClockEscape` is — one waiver idiom in this codebase, not two.
/// Two conditions, both enforced ([_escapeWithReason]), because a waiver that
/// is easier to write than the rule it waives is not a control:
///  * it must be a REAL `//` comment — a marker quoted inside a string literal
///    waives nothing, which is also what the audit's own treatment of
///    `days:`-in-a-string demands;
///  * it must carry a REASON. A bare marker is a silent opt-out.
const String kDurationDaysEscape = '// lumen:allow-duration-days';

/// The marker followed by at least one non-space character — the "and a
/// reason" half of [kDurationDaysEscape]. Applied to comment token text only.
final RegExp _escapeWithReason = RegExp(r'lumen:allow-duration-days\s+\S');

// ---------------------------------------------------------------------------
// Findings
// ---------------------------------------------------------------------------

/// One place where production code computes a date by instant arithmetic.
class DurationViolation {
  const DurationViolation({
    required this.path,
    required this.line,
    required this.rule,
    required this.detail,
  });

  /// Package-relative, forward slashes: `lib/features/x/data/y.dart`.
  final String path;
  final int line;
  final String rule;
  final String detail;

  String describe() => '$path:$line  [$rule] $detail';

  @override
  String toString() => describe();
}

/// A human-readable report, or `null` when [violations] is empty.
String? describeDurationViolations(List<DurationViolation> violations) {
  if (violations.isEmpty) return null;
  return <String>[
    'Production code computes a date by adding or subtracting a Duration:',
    ...violations.map((v) => '  ${v.describe()}'),
    '',
    'A calendar day is not always 86400 seconds — across a DST boundary it is '
        '23 or 25 hours, so this arithmetic silently reads the wrong day twice '
        'a year. Build the day from calendar FIELDS instead '
        '(DateTime.utc(y, m, d - 1), which normalises day 0 into the previous '
        'month), or mark the line `$kDurationDaysEscape <reason>`.',
  ].join('\n');
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

/// Every production Dart file this audit reads, package-relative and sorted.
///
/// The formatting audit's list, unchanged and deliberately not a second one:
/// `lib/api/**` and every generated suffix are already excluded there, for
/// reasons that apply here identically. Re-exported under its own name so a
/// test can import both guards without an ambiguous-import clash.
List<String> auditedDurationFiles(Directory packageRoot) =>
    auditedFiles(packageRoot);

/// Every waived day-arithmetic line under [packageRoot], as `path:line`.
///
/// The point of an escape hatch with a registry: adding a waiver stops being a
/// silent local decision, because the test asserting this list has to be
/// edited too. Sorted, so the list is stable to compare against.
List<String> durationDaysWaivers(Directory packageRoot) {
  final root = _posix(packageRoot.path);
  final waivers = <String>[];
  for (final relative in auditedDurationFiles(packageRoot)) {
    final content = stripBom(File('$root/$relative').readAsStringSync());
    final result = parseString(
      content: content,
      path: relative,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    if (result.errors.isNotEmpty) continue;
    int lineOf(int offset) => result.lineInfo.getLocation(offset).lineNumber;
    for (final line in _waiverLines(result.unit, lineOf).toList()..sort()) {
      waivers.add('$relative:$line');
    }
  }
  return waivers..sort();
}

// ---------------------------------------------------------------------------
// The audit
// ---------------------------------------------------------------------------

/// Audits every file [auditedDurationFiles] finds under [packageRoot].
List<DurationViolation> auditDurationArithmetic(Directory packageRoot) {
  final root = _posix(packageRoot.path);
  final violations = <DurationViolation>[];
  for (final relative in auditedDurationFiles(packageRoot)) {
    final source = File('$root/$relative').readAsStringSync();
    violations.addAll(auditDurationSource(source, path: relative));
  }
  return violations;
}

/// Audits one source file. [path] only labels the findings — this rule has no
/// per-directory behaviour — so this is the function a fixture test drives
/// directly.
List<DurationViolation> auditDurationSource(
  String source, {
  required String path,
}) {
  final content = stripBom(source);
  final result = parseString(
    content: content,
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );

  // A file that does not parse cannot be audited, and staying silent about it
  // would be the quiet failure this whole file exists to prevent.
  if (result.errors.isNotEmpty) {
    final first = result.errors.first;
    return <DurationViolation>[
      DurationViolation(
        path: path,
        line: result.lineInfo.getLocation(first.offset).lineNumber,
        rule: 'does-not-parse',
        detail: first.message,
      ),
    ];
  }

  int lineOf(int offset) => result.lineInfo.getLocation(offset).lineNumber;

  final visitor = _DurationVisitor(
    path: path,
    lineOf: lineOf,
    waivedLines: _waiverLines(result.unit, lineOf),
  );
  result.unit.accept(visitor);
  return visitor.violations;
}

/// The 1-based lines carrying a well-formed waiver.
///
/// Read off the COMMENT TOKENS, not the raw text of the line: a marker quoted
/// inside a string literal is not a comment and must not waive anything.
Set<int> _waiverLines(CompilationUnit unit, int Function(int) lineOf) {
  final lines = <int>{};
  for (final comment in lineComments(unit)) {
    if (_escapeWithReason.hasMatch(comment.lexeme)) {
      lines.add(lineOf(comment.offset));
    }
  }
  return lines;
}

class _DurationVisitor extends RecursiveAstVisitor<void> {
  _DurationVisitor({
    required this.path,
    required this.lineOf,
    required this.waivedLines,
  });

  final String path;
  final int Function(int offset) lineOf;

  /// Lines carrying a well-formed waiver.
  final Set<int> waivedLines;

  final violations = <DurationViolation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name == 'add' || name == 'subtract') {
      for (final argument in node.argumentList.arguments) {
        final field = _dayValuedField(argument);
        if (field == null) continue;
        // The line of the `add`/`subtract` token, not of the whole expression:
        // in a wrapped chain the two differ, and a waiver belongs where the
        // arithmetic is written rather than where its receiver starts.
        final line = lineOf(node.methodName.offset);
        if (_isEscaped(line)) continue;
        violations.add(
          DurationViolation(
            path: path,
            line: line,
            rule: DurationRule.dayValuedDuration,
            detail:
                '$name(Duration($field: …)) computes a date by instant '
                'arithmetic; a calendar day is 23 or 25 hours across a DST '
                'boundary. Use calendar fields, or mark the line '
                '`$kDurationDaysEscape <reason>`.',
          ),
        );
      }
    }
    super.visitMethodInvocation(node);
  }

  /// The `days`/`weeks` field named by [argument] if it is a `Duration`
  /// literal carrying one, else `null`.
  ///
  /// BOTH spellings are matched, and they are different node types — a fact
  /// that cost this rule a red test before it was noticed. Without resolution
  /// `Duration(days: 1)` is syntactically indistinguishable from a call to a
  /// function named `Duration`, so the parser hands it back as a
  /// [MethodInvocation]; only the `const` form, whose keyword settles the
  /// question, arrives as an [InstanceCreationExpression]. Matching just the
  /// latter would have let every non-`const` occurrence through — the
  /// commoner spelling of the two.
  String? _dayValuedField(Expression argument) {
    final value = argument is NamedExpression ? argument.expression : argument;
    final ArgumentList arguments;
    switch (value) {
      case InstanceCreationExpression(
            :final constructorName,
            :final argumentList,
          )
          when constructorName.type.name.lexeme == 'Duration':
        arguments = argumentList;
      case MethodInvocation(:final methodName, :final argumentList)
          when methodName.name == 'Duration':
        arguments = argumentList;
      default:
        return null;
    }
    for (final field in arguments.arguments) {
      if (field is! NamedExpression) continue;
      final label = field.name.label.name;
      if (kDayValuedFields.contains(label)) return label;
    }
    return null;
  }

  /// True when [line] (1-based) or the line above it carries a well-formed
  /// waiver — a real `//` comment carrying the marker AND a reason.
  ///
  /// Both lines are accepted because the marker rarely fits on the line it
  /// applies to; a violation and its waiver one line apart are still visible
  /// in the same glance during review.
  bool _isEscaped(int line) =>
      waivedLines.contains(line) || waivedLines.contains(line - 1);
}

String _posix(String path) => path.replaceAll(r'\', '/');
