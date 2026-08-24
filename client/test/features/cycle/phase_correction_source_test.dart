// The two SOURCE facts screen 14 ships with (P4b-T23).
//
// Both of this task's structural rulings are facts about the source, not about
// a rendered frame, and neither can be proved by pumping a widget:
//
//  * **R-08 — no write path exists.** `POST /cycle/phase-override` is P6's.
//    The behavioural half lives in `phase_correction_screen_test.dart` ("one
//    control, and it is Back"); it proves what TODAY's screen sends. This file
//    proves what tomorrow's edit cannot quietly add — the distinction T22b's
//    review settled one screen over: *behaviour tests prove what today's
//    callers send, not what tomorrow's caller COULD send.*
//  * **R3 — the route ships with NO entry affordance, on purpose.** R-08
//    requires the route, the screen, the goldens and the semantics to land; it
//    does not require reachability. An affordance whose destination can only
//    say "not available yet" is inert navigation, which R-10 hides rather than
//    disables, and R-20 forbids shipping half an affordance — so the entry
//    point lands in P6 together with the write. **This is a TRIPWIRE, and it
//    is meant to be deleted**: the P6 task that adds the affordance deletes
//    the `no entry affordance` group in the same commit as the write. Until
//    then it is what tells a reviewer that the missing affordance is the
//    decision it is rather than an oversight.
//
// **A purely syntactic audit, and its limits are the ones every other audit in
// this package states.** `parseString`, no resolution: a call reaching the
// endpoint through a variable, a dynamic dispatch or a second indirection is
// invisible here, and so is a path string assembled from fragments. What it
// COLLECTS is every identifier and every simple string literal written in LIVE
// code — doc comments are refused deliberately, which is what lets this screen
// name in prose the endpoint it must not call.
//
// **What it CHECKS, stated separately, because collecting is not asserting.**
// Fix round 1, I-2: this header used to describe the collector and leave the
// coverage to be inferred, which over-described the guard — the R-08 half
// tested identifiers only, so a phase-override symbol reached through a string
// would have passed. The three subjects, and which half each is checked
// against:
//
//   * [kPhaseOverrideSymbols] — the five GENERATED names, checked against the
//     IDENTIFIERS. A call through the generated client names one of them.
//   * [kPhaseOverridePath] — the endpoint PATH, checked against the STRINGS.
//     A write that bypasses the generated client entirely names no generated
//     symbol at all, and `dioProvider` is reachable from feature code, so that
//     shape is not theoretical. Exactly one production file is exempt
//     ([kPathHolders]) and a positive control keeps the exemption honest.
//   * screen 14's route constants and [Routes.cyclePhase]'s own literal,
//     checked against BOTH halves — that is the R3 tripwire below.
//
// Everything else this audit can see, it collects and does not judge.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/router/routes.dart';

import '../../support/formatting_guard.dart' show auditedFiles;
import '../../support/screen_registry.dart' show resolvePackageRoot, stripBom;

// ---------------------------------------------------------------------------
// The audit
// ---------------------------------------------------------------------------

/// Every identifier and simple string literal written in LIVE code.
class _LiveSource {
  _LiveSource(this.identifiers, this.strings);

  final Set<String> identifiers;
  final Set<String> strings;
}

_LiveSource _liveSourceOf(String source, {required String path}) {
  final parsed = parseString(
    content: stripBom(source),
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  expect(
    parsed.errors,
    isEmpty,
    reason: '$path does not parse, so this audit saw nothing in it.',
  );
  final visitor = _LiveSourceCollector();
  parsed.unit.accept(visitor);
  return _LiveSource(_identifierTokens(parsed.unit), visitor.strings);
}

/// Every identifier TOKEN in the unit's own token chain.
///
/// **Tokens, not [SimpleIdentifier] AST nodes, and the difference is
/// load-bearing.** Since analyzer 7 a declaration's name is a bare [Token]
/// rather than an identifier node, so an AST walk sees `Routes.cyclePhase` at
/// every USE site and misses `static const cyclePhase = …` at the declaration
/// — an audit asking "does any file name this" would then be blind to the one
/// spelling that introduces it. The token chain sees both. It also excludes
/// comments for free: the analyzer keeps comment tokens off the main chain (in
/// `Token.precedingComments`), which is what lets a screen name in prose the
/// endpoint it must not call.
Set<String> _identifierTokens(CompilationUnit unit) {
  final names = <String>{};
  for (
    Token? token = unit.beginToken;
    token != null && token.type != TokenType.EOF;
    token = token.next
  ) {
    if (token.type == TokenType.IDENTIFIER) names.add(token.lexeme);
  }
  return names;
}

_LiveSource _liveSource(String relativePath) {
  final root = resolvePackageRoot().path.replaceAll(r'\', '/');
  return _liveSourceOf(
    File('$root/$relativePath').readAsStringSync(),
    path: relativePath,
  );
}

/// Collects the string literals. Identifiers come from the token chain
/// ([_identifierTokens]) rather than from here, so there is no `visitComment`
/// override on this class and none is needed: a doc comment carries
/// [SimpleIdentifier]s (which is why `screen_registry.dart`'s `mentions` must
/// refuse them) but never a [SimpleStringLiteral].
class _LiveSourceCollector extends RecursiveAstVisitor<void> {
  final Set<String> strings = <String>{};

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    strings.add(node.value);
    super.visitSimpleStringLiteral(node);
  }
}

// ---------------------------------------------------------------------------
// Subjects
// ---------------------------------------------------------------------------

/// The generated symbols that reach `POST /cycle/phase-override`
/// (`lib/api/api/lumen_api_api.dart`, `cyclePhaseOverridePost`). Every one of
/// them belongs to P6 under R-08.
const List<String> kPhaseOverrideSymbols = <String>[
  'cyclePhaseOverridePost',
  'SavePhaseOverridesRequest',
  'PhaseOverrideInput',
  'PhaseOverrideBoundary',
  'PhaseOverridesResponse',
];

/// The endpoint itself, checked as a STRING literal rather than as a symbol.
///
/// Fix round 1, I-2. [kPhaseOverrideSymbols] are generated Dart names, so a
/// write that never touches the generated client names none of them:
/// `ref.read(dioProvider).post('/cycle/phase-override', data: …)` reaches P6's
/// endpoint while satisfying every identifier assertion in this file. The
/// collector has gathered string literals since it was written; until this
/// constant existed only the R3 half ever asked it anything.
const String kPhaseOverridePath = '/cycle/phase-override';

/// The only production file allowed to hold [kPhaseOverridePath] as a literal.
///
/// `dio_provider.dart` lists it among `_kRouteTemplates` so the PII-safe logger
/// can redact that path rather than print it — it HOLDS the string, it does not
/// call the endpoint, and an endpoint missing from that list logs as
/// `(unrouted)`. The positive control below asserts the file really still holds
/// it, so this exemption cannot outlive the line it exempts.
const Set<String> kPathHolders = <String>{'lib/core/network/dio_provider.dart'};

const String kScreenPath =
    'lib/features/cycle/presentation/phase_correction_screen.dart';

/// The only two production files allowed to name screen 14's route: the file
/// that DECLARES the constants, and the file that REGISTERS the `GoRoute`.
/// Anything else naming it would be an entry affordance.
const Set<String> kRouteOwners = <String>{
  'lib/core/router/routes.dart',
  'lib/core/router/app_router.dart',
};

void main() {
  // -------------------------------------------------------------------------
  // The mechanism, driven by fixtures — an audit nobody has seen answer both
  // ways is not known to work
  // -------------------------------------------------------------------------

  group('the audit itself', () {
    test('sees a phase-override call written in live code', () {
      final live = _liveSourceOf('''
void save(dynamic api, Object body) {
  api.cyclePhaseOverridePost(savePhaseOverridesRequest: body);
}
''', path: 'fixture.dart');

      expect(live.identifiers, contains('cyclePhaseOverridePost'));
    });

    test('does NOT see one written in a doc comment or a line comment', () {
      final live = _liveSourceOf('''
/// Never calls [SavePhaseOverridesRequest] — see R-08.
// cyclePhaseOverridePost stays unwired until the read endpoint exists.
const int untilP6 = 6;
''', path: 'fixture.dart');

      expect(live.identifiers, isNot(contains('SavePhaseOverridesRequest')));
      expect(live.identifiers, isNot(contains('cyclePhaseOverridePost')));
      // The DECLARED name, which an AST walk over `SimpleIdentifier` would
      // miss (since analyzer 7 a declaration's name is a bare `Token`), and
      // which is the reason [_identifierTokens] reads the token chain.
      expect(live.identifiers, contains('untilP6'));
    });

    test(
      'its one blind spot, stated: a name that is a CONTEXTUAL KEYWORD is not '
      'an IDENTIFIER token',
      () {
        // `deferred` is a built-in identifier (`import … deferred as …`), so
        // the lexer types it as a keyword and this audit cannot see it. None
        // of [kPhaseOverrideSymbols] or screen 14's route constants is a
        // reserved or contextual keyword, so the blind spot is empty for the
        // subjects here — but a future subject must be checked against this.
        final live = _liveSourceOf(
          'const int deferred = 6;',
          path: 'fixture.dart',
        );

        expect(live.identifiers, isNot(contains('deferred')));
        expect(live.identifiers, contains('int'));
      },
    );

    test('sees a RAW dio write to the endpoint — the shape that names no '
        'generated symbol at all (fix round 1, I-2)', () {
      final live = _liveSourceOf('''
Future<void> save(dynamic ref, Object body) async {
  await ref.read(dioProvider).post('/cycle/phase-override', data: body);
}
''', path: 'fixture.dart');

      // Not one of the five generated names appears — which is exactly why
      // checking the identifiers alone was not enough.
      expect(live.identifiers.any(kPhaseOverrideSymbols.contains), isFalse);
      expect(live.strings, contains(kPhaseOverridePath));
    });

    test('sees a route path written as a bare string literal', () {
      final live = _liveSourceOf('''
const String somewhere = '/cycle/phase';
''', path: 'fixture.dart');

      expect(live.strings, contains('/cycle/phase'));
    });
  });

  // -------------------------------------------------------------------------
  // R-08 — no write path
  // -------------------------------------------------------------------------

  group('screen 14 names no phase-override symbol', () {
    test(
      'the screen source reaches none of the generated write symbols in live '
      'code',
      () {
        final live = _liveSource(kScreenPath);

        for (final symbol in kPhaseOverrideSymbols) {
          expect(
            live.identifiers,
            isNot(contains(symbol)),
            reason:
                '$kScreenPath names $symbol. R-08 defers the phase-override '
                'write to P6: there is no predicted timeline to correct from, '
                'no endpoint to read a cycle\'s overrides back, and '
                'ARCHITECTURE.md §C.0.1 calls that field "the most dangerous '
                'on the P4a surface".',
          );
        }
      },
    );

    test('nor the endpoint PATH as a live string — the generated client is not '
        'the only way to reach it (fix round 1, I-2)', () {
      final live = _liveSource(kScreenPath);

      expect(
        live.strings,
        isNot(contains(kPhaseOverridePath)),
        reason:
            '$kScreenPath holds $kPhaseOverridePath as a live string. The '
            'screen names that endpoint in PROSE deliberately — this audit '
            'refuses comments, which is what makes prose safe — but a '
            'literal is a call waiting for an argument.',
      );
    });

    test(
      'and no production file has grown one since — by SYMBOL or by PATH',
      () {
        final root = resolvePackageRoot();
        final offenders = <String>[];
        for (final relative in auditedFiles(root)) {
          final live = _liveSource(relative);
          final namesSymbol = kPhaseOverrideSymbols.any(
            live.identifiers.contains,
          );
          // The path half skips its one holder (`dio_provider.dart`, which
          // REDACTS the path rather than calling it) — one file, pinned
          // by the positive control below.
          final namesPath =
              !kPathHolders.contains(relative) &&
              live.strings.contains(kPhaseOverridePath);
          if (namesSymbol || namesPath) offenders.add(relative);
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'P4b writes no phase override anywhere (R-08). When P6 wires it, '
              'this assertion is what it edits — deliberately, and in the same '
              'commit as the screen that offers the control.',
        );
      },
    );

    test(
      'the ONE file exempted from the path check really does hold the literal '
      '— a positive control, so a dead exemption cannot silently excuse a '
      'file that has stopped needing it',
      () {
        for (final holder in kPathHolders) {
          final live = _liveSource(holder);
          expect(
            live.strings,
            contains(kPhaseOverridePath),
            reason:
                '$holder no longer holds $kPhaseOverridePath. If the '
                'redaction template list moved or was renamed, DELETE the '
                'exemption rather than leaving a production file blanket-'
                'excused from the path check.',
          );
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // R3 — no entry affordance (TRIPWIRE: P6 deletes this group with the write)
  // -------------------------------------------------------------------------

  group('no entry affordance reaches screen 14', () {
    test('only routes.dart and app_router.dart name the route — every other '
        'production file would be an affordance', () {
      final root = resolvePackageRoot();
      final offenders = <String>[];
      for (final relative in auditedFiles(root)) {
        if (kRouteOwners.contains(relative)) continue;
        final live = _liveSource(relative);
        final namesIt =
            live.identifiers.contains('cyclePhase') ||
            live.identifiers.contains('cyclePhaseSegment') ||
            live.strings.contains(Routes.cyclePhase);
        if (namesIt) offenders.add(relative);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Screen 14 ships UNREACHABLE on purpose (R3). R-08 requires the '
            'route, the screen, the goldens and the semantics; it does not '
            'require reachability, and R-20 forbids shipping half an '
            'affordance — a control whose destination can only say "not '
            'available yet" is the inert navigation R-10 hides. The entry '
            'point lands in P6 WITH the override write. **When it does, '
            'delete this group** rather than adding the file to an '
            'allowlist.',
      );
    });

    test('both owners really do name it — a positive control, so an audit that '
        'stopped matching cannot read as "nothing reaches it"', () {
      for (final owner in kRouteOwners) {
        final live = _liveSource(owner);
        expect(
          live.identifiers.contains('cyclePhase') ||
              live.identifiers.contains('cyclePhaseSegment'),
          isTrue,
          reason: '$owner should name screen 14\'s route.',
        );
      }
    });
  });
}
