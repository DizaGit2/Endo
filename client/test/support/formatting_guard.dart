// ---------------------------------------------------------------------------
// formatting_guard.dart — "format through the provider" audit (P4b-T6)
// ---------------------------------------------------------------------------
//
// Read `test/core/locale/formatting_guard_test.dart` for the rules and why each
// one exists. This file is only the mechanism: it parses every production
// source and reports what breaks the rules. It is kept separate from the test
// so the audit can be pointed at a temporary fixture tree and watched to go
// red — same convention as `screen_registry.dart`, for the same reason.
//
// WHAT THIS CAN AND CANNOT SEE. Like the screen registry, this is a purely
// SYNTACTIC audit: `parseString`, no resolution. So a name in a comment or
// inside the text of a string literal is not flagged — that is the point, a
// doc comment explaining `DateFormat` must not fail the build.
//
// It holds TWO paths honest — `intl` and the device clock — and nothing more.
// Stated as the list of things that pass clean, because an audit whose limits
// are vague gets read as a guarantee it never made:
//
//   * HAND-ROLLED formatting. `Text('${d.day}/${d.month}/${d.year}')` and
//     `(firstOfMonth.weekday % 7)` for a grid offset are invisible here — and
//     the second IS the Sunday-first week-grid bug this whole task exists to
//     prevent. No rule is attempted: matching arithmetic on a `.weekday` would
//     be both fragile and noisy. Review and `LumenFormats.leadingBlankDays`
//     are what cover it.
//   * A locale that arrives from ANOTHER FILE. `LumenFormats.date(d, kSomething)`
//     where `kSomething` is a const declared elsewhere needs resolution to see
//     through; only same-file const/final string variables are caught.
//   * A formatter reached through an alias the audit cannot resolve
//     (`final f = DateFormat.yMd; f('en_US')`).
//   * `kIntlOwners` is a path list. Widening it is a one-line change that this
//     audit cannot object to; the review of that line is the control.
//
// The device-clock rule has NO directory exemption: it applies to every audited
// file, `lib/core/` included. The two legitimate clock reads in the codebase
// carry a line-level waiver instead, and [deviceClockWaivers] lists them, so
// "who is allowed to read the clock" is an enumerable answer rather than a
// directory that quietly covers whatever is put inside it.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

// One BOM lesson, one implementation. `stripBom` is here for the same reason it
// is there: this is a Windows-primary repo whose shells write UTF-8-with-BOM by
// default, and a BOM makes `parseString` report a perfectly good file as broken.
import 'screen_registry.dart' show stripBom;

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

/// Rule names, so a test asserts on a constant rather than on prose.
abstract final class FormattingRule {
  /// `DateFormat` / `NumberFormat` used outside [kIntlOwners].
  static const String directIntl = 'direct-intl';

  /// A [LumenFormats] call whose locale is a string literal instead of the
  /// value of `localeProvider`.
  static const String literalLocale = 'literal-locale';

  /// `DateTime.now()` in feature code — "today" is the server's (D-12).
  static const String deviceClock = 'device-clock';
}

/// The only production files allowed to name `DateFormat` / `NumberFormat`.
///
/// Package-relative, forward slashes. Everything else must go through
/// [LumenFormats], so there is exactly one place where a locale turns into a
/// pattern.
const Set<String> kIntlOwners = <String>{
  'lib/core/formatters/lumen_formats.dart',
};

/// The line comment that opts one line out of [FormattingRule.deviceClock].
///
/// Deliberately explicit and greppable: a reviewer can list every place the
/// client trusts its own clock with one search.
///
/// Two conditions, both enforced ([_escapeWithReason]), because a waiver that
/// is easier to write than the rule it waives is not a control:
///  * it must be a REAL `//` comment — matching raw line text let a marker
///    quoted inside a string literal waive the line below it, which is also
///    inconsistent with `direct-intl`, where a mention in a string is
///    deliberately not a use;
///  * it must carry a REASON. A bare marker is a silent opt-out.
const String kDeviceClockEscape = '// lumen:allow-device-clock';

/// Generated-file suffixes, mirroring `analysis_options.yaml`'s `exclude:`.
const List<String> kGeneratedSuffixes = <String>[
  '.g.dart',
  '.gr.dart',
  '.freezed.dart',
  '.config.dart',
];

/// The marker followed by at least one non-space character — the "and a
/// reason" half of [kDeviceClockEscape]. Applied to comment token text only.
final RegExp _escapeWithReason = RegExp(r'lumen:allow-device-clock\s+\S');

// ---------------------------------------------------------------------------
// Findings
// ---------------------------------------------------------------------------

/// One place where production code formats outside the sanctioned path.
class FormattingViolation {
  const FormattingViolation({
    required this.path,
    required this.line,
    required this.rule,
    required this.detail,
  });

  /// Package-relative, forward slashes: `lib/features/x/presentation/y.dart`.
  final String path;
  final int line;
  final String rule;
  final String detail;

  String describe() => '$path:$line  [$rule] $detail';

  @override
  String toString() => describe();
}

/// A human-readable report, or `null` when [violations] is empty.
String? describeViolations(List<FormattingViolation> violations) {
  if (violations.isEmpty) return null;
  return <String>[
    'Production code formats outside the locale-aware path:',
    ...violations.map((v) => '  ${v.describe()}'),
    '',
    'Dates, times, numbers and week layout go through LumenFormats, and the '
        'locale comes from localeProvider — never from a literal and never '
        'from the device clock (D-05, D-12).',
  ].join('\n');
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

/// Every production Dart file the audit reads, package-relative and sorted.
///
/// `lib/api/**` is excluded because it is generated, and so is every suffix
/// `analysis_options.yaml` excludes ([kGeneratedSuffixes]) — the two lists are
/// kept identical on purpose: a file the analyzer does not lint is a file
/// nobody edits by hand, and flagging it would only teach people to widen
/// [kIntlOwners]. A contract change is not this rule's business.
List<String> auditedFiles(Directory packageRoot) {
  final root = _posix(packageRoot.path);
  final lib = Directory('$root/lib');
  if (!lib.existsSync()) return const <String>[];

  final paths = <String>[];
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = _posix(entity.path);
    if (!path.endsWith('.dart')) continue;
    if (kGeneratedSuffixes.any(path.endsWith)) continue;
    final relative = path.substring(root.length + 1);
    if (relative.startsWith('lib/api/')) continue;
    paths.add(relative);
  }
  paths.sort();
  return paths;
}

/// Every waived device-clock line under [packageRoot], as `path:line`.
///
/// The point of an escape hatch with a registry: adding a waiver stops being a
/// silent local decision, because the test asserting this list has to be
/// edited too. Sorted, so the list is stable to compare against.
List<String> deviceClockWaivers(Directory packageRoot) {
  final root = _posix(packageRoot.path);
  final waivers = <String>[];
  for (final relative in auditedFiles(packageRoot)) {
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

/// Audits every file [auditedFiles] finds under [packageRoot].
List<FormattingViolation> auditFormatting(Directory packageRoot) {
  final root = _posix(packageRoot.path);
  final violations = <FormattingViolation>[];
  for (final relative in auditedFiles(packageRoot)) {
    final source = File('$root/$relative').readAsStringSync();
    violations.addAll(auditSource(source, path: relative));
  }
  return violations;
}

/// Audits one source file. [path] is package-relative and decides which rules
/// apply to it, so this is the function a fixture test drives directly.
List<FormattingViolation> auditSource(String source, {required String path}) {
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
    return <FormattingViolation>[
      FormattingViolation(
        path: path,
        line: result.lineInfo.getLocation(first.offset).lineNumber,
        rule: 'does-not-parse',
        detail: first.message,
      ),
    ];
  }

  int lineOf(int offset) => result.lineInfo.getLocation(offset).lineNumber;

  final visitor = _FormattingVisitor(
    path: path,
    lineOf: lineOf,
    waivedLines: _waiverLines(result.unit, lineOf),
    constStrings: _constStringNames(result.unit),
  );
  result.unit.accept(visitor);
  return visitor.violations;
}

/// The 1-based lines carrying a well-formed device-clock waiver.
///
/// Read off the COMMENT TOKENS, not the raw text of the line: a marker quoted
/// inside a string literal is not a comment and must not waive anything, which
/// is the same standard `direct-intl` already applies in the other direction.
Set<int> _waiverLines(CompilationUnit unit, int Function(int) lineOf) {
  final lines = <int>{};
  for (final comment in lineComments(unit)) {
    if (_escapeWithReason.hasMatch(comment.lexeme)) {
      lines.add(lineOf(comment.offset));
    }
  }
  return lines;
}

/// Every `//` (and `///`) comment token in [unit].
///
/// Comments are not AST nodes in general — the scanner hangs them off the token
/// that follows them — so they are walked here through the token chain rather
/// than by a visitor. The EOF token is included: it carries any comment at the
/// very end of the file.
///
/// PUBLIC because `duration_days_guard.dart` enforces its own line-level
/// waiver the same way and must read comments the same way (P4b-T17b): two
/// copies of this walk could disagree about what counts as a comment, and the
/// whole point of reading tokens instead of raw text is that the answer is not
/// negotiable.
List<Token> lineComments(CompilationUnit unit) {
  final comments = <Token>[];
  Token? token = unit.beginToken;
  while (token != null) {
    Token? comment = token.precedingComments;
    while (comment != null) {
      if (comment.lexeme.startsWith('//')) comments.add(comment);
      comment = comment.next;
    }
    if (token.type == TokenType.EOF) break;
    token = token.next;
  }
  return comments;
}

/// Names of same-file `const`/`final` variables initialised to a string.
///
/// `const _l = 'en_US'; … LumenFormats.date(d, _l)` is a hard-coded locale
/// wearing one line of indirection, and it reads as innocent code. A constant
/// declared in ANOTHER file cannot be seen without resolution — see the limits
/// at the top of this file.
Set<String> _constStringNames(CompilationUnit unit) {
  final collector = _ConstStringCollector();
  unit.accept(collector);
  return collector.names;
}

class _ConstStringCollector extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    if (node.isConst || node.isFinal) {
      for (final variable in node.variables) {
        if (variable.initializer is StringLiteral) {
          names.add(variable.name.lexeme);
        }
      }
    }
    super.visitVariableDeclarationList(node);
  }
}

class _FormattingVisitor extends RecursiveAstVisitor<void> {
  _FormattingVisitor({
    required this.path,
    required this.lineOf,
    required this.waivedLines,
    required this.constStrings,
  });

  final String path;
  final int Function(int offset) lineOf;

  /// Lines carrying a well-formed device-clock waiver.
  final Set<int> waivedLines;

  /// Same-file constants whose value is a string literal.
  final Set<String> constStrings;

  final violations = <FormattingViolation>[];

  bool get _ownsIntl => kIntlOwners.contains(path);

  void _add(int offset, String rule, String detail) => violations.add(
        FormattingViolation(
          path: path,
          line: lineOf(offset),
          rule: rule,
          detail: detail,
        ),
      );

  // A `///` doc comment is part of the AST and `[DateFormat]` inside one is a
  // real CommentReference. Documenting the rule must not violate it.
  @override
  void visitComment(Comment node) {}

  // `import '…' show DateFormat;` names it without using it.
  @override
  void visitShowCombinator(ShowCombinator node) {}

  @override
  void visitHideCombinator(HideCombinator node) {}

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _checkIntlName(node.name, node.offset);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    // `DateFormat fmt = …` names the type through a token, not an identifier.
    _checkIntlName(node.name.lexeme, node.offset);
    super.visitNamedType(node);
  }

  void _checkIntlName(String name, int offset) {
    if (_ownsIntl) return;
    if (name != 'DateFormat' && name != 'NumberFormat') return;
    _add(
      offset,
      FormattingRule.directIntl,
      '$name is used directly; format through LumenFormats instead.',
    );
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // The tear-off form: `clock ?? DateTime.now`.
    if (node.prefix.name == 'DateTime' &&
        node.identifier.name == 'now') {
      _reportDeviceClock(node.offset, 'DateTime.now');
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;

    // `DateTime.now()` — the call form.
    if (node.methodName.name == 'now' &&
        target is SimpleIdentifier &&
        target.name == 'DateTime') {
      _reportDeviceClock(node.offset, 'DateTime.now()');
    }

    // `LumenFormats.date(d, 'es_ES')` — a locale that did not come from the
    // provider. Checked on the ARGUMENTS, so `LumenFormats.date(d, locale)` is
    // fine however `locale` was obtained; what is refused is hard-coding it.
    if (_isLumenFormats(target) && _hasHardCodedString(node.argumentList)) {
      _add(
        node.offset,
        FormattingRule.literalLocale,
        'LumenFormats.${node.methodName.name} is called with a hard-coded '
            'locale; pass ref.watch(localeProvider).',
      );
    }

    super.visitMethodInvocation(node);
  }

  /// Whether [target] is `LumenFormats`, however it was reached.
  ///
  /// The prefixed form matters: `import '…' as fmt;` makes the target a
  /// `PrefixedIdentifier`, and a rule that only knew `SimpleIdentifier` was one
  /// import alias away from seeing nothing.
  bool _isLumenFormats(Expression? target) => switch (target) {
        SimpleIdentifier(:final name) => name == 'LumenFormats',
        PrefixedIdentifier(:final identifier) =>
          identifier.name == 'LumenFormats',
        _ => false,
      };

  /// Whether any argument is a string literal, or a same-file constant holding
  /// one.
  bool _hasHardCodedString(ArgumentList arguments) {
    for (final argument in arguments.arguments) {
      final value =
          argument is NamedExpression ? argument.expression : argument;
      if (value is StringLiteral) return true;
      if (value is SimpleIdentifier && constStrings.contains(value.name)) {
        return true;
      }
    }
    return false;
  }

  void _reportDeviceClock(int offset, String what) {
    final line = lineOf(offset);
    if (_isEscaped(line)) return;
    _add(
      offset,
      FormattingRule.deviceClock,
      '$what reads the device clock; "today" is the server\'s (D-12). '
          'Inject a clock, or mark the line `$kDeviceClockEscape <reason>`.',
    );
  }

  /// True when [line] (1-based) or the line above it carries a well-formed
  /// waiver — a real `//` comment carrying the marker AND a reason.
  ///
  /// Both lines are accepted because the marker rarely fits on the line it
  /// applies to; a violation and its waiver one line apart are still visible in
  /// the same glance during review.
  bool _isEscaped(int line) =>
      waivedLines.contains(line) || waivedLines.contains(line - 1);
}

String _posix(String path) => path.replaceAll(r'\', '/');
