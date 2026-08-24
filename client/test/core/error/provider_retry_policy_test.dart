// ---------------------------------------------------------------------------
// The app-wide provider retry policy (P4b-T26)
// ---------------------------------------------------------------------------
//
// riverpod 3.3.2 retries a failed provider build by default, and a `Failure` is
// exactly the shape it decides to retry:
//
//   * `ProviderContainer.defaultRetry` (`provider_container.dart`, the
//     `defaultRetry` static) returns `null` — "stop" — only for
//     `error is ProviderException || error is Error`. Every member of this
//     app's sealed `Failure` hierarchy is neither, so it is retried, ten times,
//     with 200 ms → 6.4 s exponential backoff (~38 s in total).
//   * While a retry is pending, `ProviderElement.triggerRetry`
//     (`element.dart`, the `triggerRetry` method) returns
//     `AsyncLoading(error: …, retrying: true)`.
//   * `AsyncValue.when` (`async_value.dart`, the `when` method) tests
//     `isLoading` FIRST. That state is `isReloading` (it carries an error, so
//     `_hasState` is true) and `skipLoadingOnReload` defaults to `false`, so
//     `when` calls `loading()`.
//
// Net effect, before this file existed: a screen whose read fails renders its
// SPINNER for most of a minute instead of the error/retry body designed for it.
//
// This file pins the cure at every place a Lumen provider container is built —
// the production root scope and the two test harnesses that stand in for it —
// and proves the user-visible consequence on two real screens.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/app.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:lumen/features/settings/presentation/cycle_settings_screen.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';
import '../../support/screen_registry.dart' show resolvePackageRoot, stripBom;

class _MockCycleSettingsRepository extends Mock
    implements CycleSettingsRepository {}

class _MockMeRepository extends Mock implements MeRepository {}

/// A provider whose build always throws a [NetworkFailure] — the shape
/// riverpod's own default policy decides IS worth retrying.
final _throwingProvider = FutureProvider<int>(
  (ref) async => throw const NetworkFailure('boom'),
);

/// Renders which arm of [AsyncValue.when] the throwing provider lands in.
class _Probe extends ConsumerWidget {
  const _Probe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> v = ref.watch(_throwingProvider);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: v.when(
        data: (int n) => Text('data $n'),
        error: (Object e, _) => Text('error ${e.runtimeType}'),
        loading: () => const Text('loading'),
      ),
    );
  }
}

CycleSettingsResponse _settingsFixture() => CycleSettingsResponse(
  (b) => b
    ..avgCycleLengthDays = 29
    ..avgPeriodLengthDays = 5
    ..regularity = 'somewhat'
    ..phasePredictionEnabled = true
    ..autoDetectPeriodStartEnabled = true
    ..showFertilityWindowEnabled = true
    ..trackingPaused = false,
);

void main() {
  // -------------------------------------------------------------------------
  // The user-visible consequence — the reason this task exists
  // -------------------------------------------------------------------------

  group('a read failure reaches the designed error body, not the spinner', () {
    testWidgets(
      'screen 32 (cycle settings) renders LumenErrorRetry when its read '
      'fails — its controller carries no retry opt-out of its own, so this '
      'is the app-wide policy doing the work',
      (tester) async {
        final repo = _MockCycleSettingsRepository();
        when(() => repo.getSettings()).thenAnswer(
          (_) async => const NetworkRequired<CycleSettingsResponse>(
            NetworkFailure('No network connection.'),
          ),
        );

        await pumpApp(
          tester,
          home: const CycleSettingsScreen(),
          overrides: <Override>[
            ...lumenOverrides(cacheStore: emptyCacheStore()),
            cycleSettingsRepositoryProvider.overrideWithValue(repo),
          ],
          // `settle: false`: under the defect the tree holds an indeterminate
          // CircularProgressIndicator, and `pumpAndSettle` would time out
          // instead of reporting which body rendered.
          settle: false,
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byType(LumenErrorRetry),
          findsOneWidget,
          reason:
              'A failed read must land on the screen\'s designed error/retry '
              'body immediately. If this finds nothing, the provider is being '
              'retried and the state is AsyncLoading(retrying: true), which '
              'AsyncValue.when routes to loading().',
        );
        expect(
          find.text('No network connection.'),
          findsOneWidget,
          reason: 'The error body renders the Failure\'s own message.',
        );
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason:
              'The spinner is the defect: it is what the user stares at for '
              '~38 s while ten silent retries run.',
        );
      },
    );

    testWidgets(
      'screen 31 (profile) renders its error body on a thrown Failure — the '
      'shape production actually throws, not the StateError its own retry '
      'test had to substitute to dodge the retry timer',
      (tester) async {
        final repo = _MockMeRepository();
        when(
          () => repo.getMe(),
        ).thenAnswer((_) async => throw const TlsFailure());

        await pumpApp(
          tester,
          home: const ProfileScreen(),
          overrides: <Override>[
            ...lumenOverrides(cacheStore: emptyCacheStore()),
            meRepositoryProvider.overrideWithValue(repo),
          ],
          settle: false,
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byType(LumenErrorRetry),
          findsOneWidget,
          reason:
              'A TlsFailure is a HARD failure — failure.dart says it must '
              'never be treated as a transient offline state. Retrying it ten '
              'times behind a spinner is exactly that.',
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The policy itself
  // -------------------------------------------------------------------------

  group('lumenRetry — the decision, pinned in both directions', () {
    test('declines to retry EVERY shape, at every retry count', () {
      const List<Object> failures = <Object>[
        NetworkFailure(),
        ServerFailure(),
        AuthFailure(),
        ValidationFailure(),
        NotFoundFailure(),
        ConflictFailure(),
        RateLimitFailure(),
        TlsFailure(),
        UnknownFailure(),
      ];
      for (final Object error in <Object>[
        ...failures,
        Exception('plain exception'),
        StateError('a plain Error'),
        'a bare string',
      ]) {
        for (var attempt = 0; attempt < 12; attempt++) {
          expect(
            lumenRetry(attempt, error),
            isNull,
            reason:
                'lumenRetry must answer "do not retry" for every error and '
                'every attempt — it is unconditional on purpose. See its '
                'dartdoc for why the NetworkFailure/ServerFailure "ambiguous" '
                'split cachedWrite uses is deliberately NOT reused here.',
          );
        }
      }
    });

    test(
      'the OTHER direction: riverpod 3.3.2 really would retry a Failure, and '
      'really would not retry an Error — so the override is load-bearing, and '
      'the finding it rests on is an assertion rather than a comment',
      () {
        expect(
          ProviderContainer.defaultRetry(0, const NetworkFailure()),
          const Duration(milliseconds: 200),
          reason:
              'A Failure is neither a ProviderException nor an Error, so '
              'defaultRetry schedules the first backoff. If this ever answers '
              'null, riverpod has changed and lumenRetry became redundant.',
        );
        expect(
          ProviderContainer.defaultRetry(9, const TlsFailure()),
          const Duration(milliseconds: 6400),
          reason: 'The tenth attempt is still scheduled, capped at maxDelay.',
        );
        expect(
          ProviderContainer.defaultRetry(10, const NetworkFailure()),
          isNull,
          reason: 'retryCount >= maxRetries (10) is where the default stops.',
        );
        expect(
          ProviderContainer.defaultRetry(0, StateError('x')),
          isNull,
          reason:
              'error is Error — the exemption two test files in this repo had '
              'to exploit, by throwing a StateError instead of the Failure '
              'production throws, to reach an error body at all.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Where it is applied
  // -------------------------------------------------------------------------

  group('the policy is carried by every container Lumen builds', () {
    testWidgets('LumenRootScope — the production root', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        LumenRootScope(
          overrides: const <Override>[],
          child: Builder(
            builder: (BuildContext context) {
              container = ProviderScope.containerOf(context, listen: false);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        container.retry,
        same(lumenRetry),
        reason:
            'main() builds its root scope through LumenRootScope. If this '
            'stops being lumenRetry, every AsyncNotifier screen in the '
            'shipped app goes back to spinning through ten silent retries.',
      );
    });

    testWidgets(
      'LumenRootScope, behaviourally: a build that throws a Failure settles '
      'in AsyncError on the very next frame, with no retry timer left behind',
      (tester) async {
        await tester.pumpWidget(
          const LumenRootScope(overrides: <Override>[], child: _Probe()),
        );
        await tester.pump();

        expect(find.text('error NetworkFailure'), findsOneWidget);
        expect(find.text('loading'), findsNothing);
        // Reaching the end of this test without "A Timer is still pending" is
        // the second half of the assertion: under riverpod's default policy
        // ProviderElement.triggerRetry schedules a 200 ms backoff Timer, and
        // flutter_test fails the test for exactly that.
      },
    );

    testWidgets('pumpApp', (tester) async {
      final ProviderContainer c = await pumpApp(
        tester,
        home: const SizedBox.shrink(),
      );
      expect(c.retry, same(lumenRetry));
    });

    testWidgets(
      'pumpApp REJECTS a caller-supplied container carrying some OTHER '
      'policy — the branch the first cut of this fix left open',
      (tester) async {
        // `container:` used to bypass the harness's `retry:` entirely: the
        // policy was applied only on the `container == null` branch, so any
        // widget test that brought its own container silently ran the very
        // default this task removed. Three files pass a container today; none
        // of them had a throwing build, so nothing was visibly wrong — which
        // is exactly the shape of hole that gets found later rather than now.
        //
        // The source audit now covers ProviderContainer, but it can only see
        // that a `retry:` is PRESENT. Identity is checked here, where the
        // container is actually mounted, and the rogue below is the old policy
        // named out loud rather than an omission.
        final rogue = ProviderContainer(retry: ProviderContainer.defaultRetry);
        addTearDown(rogue.dispose);

        await expectLater(
          pumpApp(tester, home: const SizedBox.shrink(), container: rogue),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains('retry: lumenRetry'),
            ),
          ),
        );
      },
    );

    testWidgets('pumpLumenApp', (tester) async {
      final ProviderContainer c = await pumpLumenApp(
        tester,
        overrides: lumenOverrides(auth: AuthStatus.unauthenticated),
        settle: false,
      );
      expect(c.retry, same(lumenRetry));
    });

    testWidgets('the golden frame', (tester) async {
      ProviderContainer? container;
      await tester.pumpWidget(
        goldenApp(
          brightness: Brightness.light,
          home: Builder(
            builder: (BuildContext context) {
              container = ProviderScope.containerOf(context, listen: false);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        container?.retry,
        same(lumenRetry),
        reason:
            'Inert for the goldens that exist (rule 5: none draws a loading '
            'state), but a third container disagreeing with the other two '
            'about when a provider rebuilds is a difference nobody would '
            'think to look for.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // What must NOT change
  // -------------------------------------------------------------------------

  group('the designed LOADING state is not collateral damage', () {
    testWidgets(
      'a read that is genuinely still in flight still shows the spinner — '
      'this policy removes the retry, not the loading state',
      (tester) async {
        final repo = _MockCycleSettingsRepository();
        final completer = Completer<CacheResult<CycleSettingsResponse>>();
        when(() => repo.getSettings()).thenAnswer((_) => completer.future);

        await pumpApp(
          tester,
          home: const CycleSettingsScreen(),
          overrides: <Override>[
            ...lumenOverrides(cacheStore: emptyCacheStore()),
            cycleSettingsRepositoryProvider.overrideWithValue(repo),
          ],
          settle: false,
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(LumenErrorRetry), findsNothing);

        // Let it land, so the test does not end mid-flight.
        completer.complete(Fresh(_settingsFixture()));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });

  _auditTests();
}

// ---------------------------------------------------------------------------
// The source audit — "app-wide" as a property the source carries
// ---------------------------------------------------------------------------
//
// The behaviour tests above prove that the containers which exist TODAY carry
// the policy. This proves the same of the one somebody adds tomorrow, which is
// the distinction T22b settled and T23 reused: a behaviour test pins what
// today's code does, a source audit pins what tomorrow's edit cannot quietly
// do.
//
// **It walks BOTH constructors, and that is a correction (fix round 1).** The
// first cut walked `ProviderScope` only, and booked the exclusion of bare
// `ProviderContainer` as a bounded judgement: ~40 test sites, and a file-level
// allowlist over 40 sites is a rule nobody reads. The judgement was wrong twice
// over. `pump_app.dart` accepts a caller's OWN container, so the uncovered
// constructor was reachable straight through the covered harness — a policy
// applied on one of two branches is the same species of hole as a guard that
// cannot fail. And "every provider whose build can throw either names
// `lumenRetry` itself or is exercised by a container that names it" was a fact
// about the tests that happened to be checked in, not a property anything
// enforced.
//
// Requiring the argument at all ~40 sites is not an allowlist — it is one
// uniform rule with no membership list to maintain. It is also what makes a
// controller test observe the policy the USER gets, and it removes the
// asymmetry ("some containers name it, so the rest must not need it") that let
// this defect survive four separate private per-provider fixes.
//
// **Limits, stated rather than left to be inferred.** It is syntactic
// (`parseString`, no resolution) and matches on the constructor NAME, so a
// container handed back by a helper in another library is invisible to it. And
// it reads `retry:` as PRESENT, not as `lumenRetry` — a site naming some OTHER
// policy passes here, and is caught by the behaviour tests and by
// `pump_app.dart`'s identity check instead.

/// One `ProviderScope(...)` / `ProviderContainer(...)` found in the source, and
/// whether it named `retry:`.
typedef _RetrySite = ({String path, int line, String ctor, bool namesRetry});

/// The two constructors that decide a provider's retry policy.
const Set<String> _kRetryCtors = <String>{'ProviderScope', 'ProviderContainer'};

class _RetryVisitor extends RecursiveAstVisitor<void> {
  _RetryVisitor(this.path, this.lineOf, this.sites);
  final String path;
  final int Function(int offset) lineOf;
  final List<_RetrySite> sites;

  void _record(String ctor, int offset, ArgumentList arguments) {
    sites.add((
      path: path,
      line: lineOf(offset),
      ctor: ctor,
      namesRetry: arguments.arguments.whereType<NamedExpression>().any(
        (NamedExpression a) => a.name.label.name == 'retry',
      ),
    ));
  }

  // BOTH spellings, and they are different node types — the same trap
  // `duration_days_guard.dart` documents on `_dayValuedField`, and it cost this
  // audit a red positive control before it was noticed here too. Without
  // resolution `ProviderScope(...)` is indistinguishable from a call to a
  // function of that name, so the parser hands it back as a MethodInvocation;
  // only the `const`/`new` form arrives as an InstanceCreationExpression.
  //
  // `.test` is matched as well: `ProviderContainer.test(...)` is riverpod's own
  // recommended test constructor (`provider_container.dart` says so in
  // [ProviderContainer]'s dartdoc) and it takes the same `retry` argument, so a
  // finder that only knew the unnamed constructor would wave through the very
  // spelling the next person is most likely to reach for.
  //
  // Nothing filters on `node.target`, and that is deliberate. A prefixed
  // spelling from an aliased import (`riverpod.ProviderScope(...)`) arrives as
  // a MethodInvocation WITH a target, so dropping those would be a hole rather
  // than a refinement. `ProviderContainer.defaultRetry(0, e)` — which this file
  // calls four times — stays out for a different reason entirely: its
  // `methodName` is `defaultRetry`. A `node.target == null` clause written here
  // "to keep the static call out" was measured to change nothing, which is how
  // it was caught; the control source is what actually pins that exclusion.
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final String name = node.constructorName.type.name.lexeme;
    final String? ctor = node.constructorName.name?.name;
    if (_kRetryCtors.contains(name) && (ctor == null || ctor == 'test')) {
      _record(name, node.offset, node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final String name = node.methodName.name;
    final AstNode? target = node.target;
    if (_kRetryCtors.contains(name)) {
      _record(name, node.offset, node.argumentList);
    } else if (name == 'test' &&
        target is SimpleIdentifier &&
        _kRetryCtors.contains(target.name)) {
      _record(target.name, node.offset, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

List<_RetrySite> _sitesInSource(String source, String path) {
  final sites = <_RetrySite>[];
  final ParseStringResult result = parseString(
    content: stripBom(source),
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) return sites;
  result.unit.visitChildren(
    _RetryVisitor(
      path,
      (int offset) => result.lineInfo.getLocation(offset).lineNumber,
      sites,
    ),
  );
  return sites;
}

List<_RetrySite> _retrySites() {
  final Directory root = resolvePackageRoot();
  final String rootPath = root.path.replaceAll(r'\', '/');
  final sites = <_RetrySite>[];

  for (final String dir in <String>['lib', 'test']) {
    final Directory d = Directory('$rootPath/$dir');
    if (!d.existsSync()) continue;
    for (final FileSystemEntity entity in d.listSync(recursive: true)) {
      if (entity is! File) continue;
      final String path = entity.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart')) continue;
      final String relative = path.substring(rootPath.length + 1);
      if (relative.startsWith('lib/api/')) continue;

      sites.addAll(_sitesInSource(File(path).readAsStringSync(), relative));
    }
  }
  return sites;
}

/// A hand-written source the walker must classify EXACTLY right.
///
/// The disk sweep can only assert what happens to be checked in, so a finder
/// that silently stopped matching would keep reporting an empty offender list
/// and look greener the more broken it got. This control carries known
/// offenders, in both spellings, plus the one shape it must NOT report.
const String _controlSource = '''
void main() {
  ProviderScope(child: x);
  const ProviderScope(retry: lumenRetry, child: x);
  ProviderContainer(overrides: <Override>[]);
  ProviderContainer(retry: lumenRetry);
  ProviderContainer.test(overrides: <Override>[]);
  ProviderContainer.test(retry: lumenRetry);
  ProviderContainer.defaultRetry(0, e);
}
''';

void _auditTests() {
  group('every ProviderScope and ProviderContainer names a retry policy', () {
    test(
      'positive control: the walker classifies a known source exactly, '
      'including the static call it must NOT report',
      () {
        final List<String> found =
            <String>[
              for (final _RetrySite s in _sitesInSource(
                _controlSource,
                'control.dart',
              ))
                '${s.ctor}:${s.line}:${s.namesRetry}',
            ]..sort();

        expect(found, <String>[
          // line 4 — unnamed constructor, no `retry:`
          'ProviderContainer:4:false',
          // line 5 — unnamed constructor, names it
          'ProviderContainer:5:true',
          // line 6 — riverpod's own `.test` constructor, no `retry:`
          'ProviderContainer:6:false',
          // line 7 — `.test`, names it
          'ProviderContainer:7:true',
          // line 2 — MethodInvocation spelling, no `retry:`
          'ProviderScope:2:false',
          // line 3 — `const`, so InstanceCreationExpression, names it
          'ProviderScope:3:true',
          // line 8 — `ProviderContainer.defaultRetry(0, e)` is ABSENT: a static
          // call, not a construction. If it ever appears here the offender list
          // gains a permanent false positive.
        ]);
      },
    );

    test('positive control: the walker finds the real scopes on disk', () {
      final List<String> paths =
          <String>{
            for (final _RetrySite s in _retrySites())
              if (s.ctor == 'ProviderScope') s.path,
          }.toList()..sort();

      expect(paths, <String>[
        'lib/app.dart',
        'test/features/checkin/quick_checkin_screen_golden_test.dart',
        'test/support/golden_app.dart',
      ]);
    });

    test(
      'positive control: the walker finds the containers on disk too — the '
      'branch this audit did NOT cover before fix round 1',
      () {
        final List<_RetrySite> containers = <_RetrySite>[
          for (final _RetrySite s in _retrySites())
            if (s.ctor == 'ProviderContainer') s,
        ];

        // A floor, not an exact count: this list grows with every new
        // controller test, and a number that must be edited on unrelated
        // commits is a number people edit without reading. The offender check
        // below is the one that has to be exact.
        expect(
          containers.length,
          greaterThanOrEqualTo(30),
          reason:
              'There are ~40 bare ProviderContainer sites in this repo. If '
              'this collapses, the walker has stopped matching and the '
              'offender list below is empty for the wrong reason.',
        );
        expect(
          containers.map((_RetrySite s) => s.path).toSet(),
          contains('test/support/pump_app.dart'),
          reason:
              'The harness every widget test mounts through builds one. It is '
              'the site that joins the two constructors, so a walker that '
              'misses it misses the point of covering containers at all.',
        );
      },
    );

    test('none of them omits `retry:`', () {
      final List<String> offenders =
          <String>[
            for (final _RetrySite s in _retrySites())
              if (!s.namesRetry) '${s.ctor} ${s.path}:${s.line}',
          ]..sort();

      expect(
        offenders,
        isEmpty,
        reason:
            'A ProviderScope or ProviderContainer without `retry:` runs on '
            'riverpod 3.3.2\'s defaultRetry, which rebuilds a build that threw '
            'a Failure ten times over ~38 s while publishing '
            'AsyncLoading(retrying: true) — so a screen under it shows a '
            'spinner where its designed error body belongs, and a test under '
            'it observes a policy the shipped app does not have. Pass '
            '`retry: lumenRetry` (core/error/retry_policy.dart).',
      );
    });
  });
}
