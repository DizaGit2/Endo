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
// Behaviour tests above prove the three containers that exist TODAY carry the
// policy. This proves the same of the one somebody adds tomorrow, which is the
// distinction T22b settled and T23 reused: a behaviour test pins what today's
// code does, a source audit pins what tomorrow's edit cannot quietly do.
//
// **Limits, stated rather than left to be inferred.** It is syntactic
// (`parseString`, no resolution), it matches on the constructor name
// `ProviderScope`, and it reads `retry:` as PRESENT — not as `lumenRetry`, so
// a scope naming some other policy passes here and is caught by the behaviour
// tests instead. And it deliberately does NOT audit bare `ProviderContainer`
// construction: ~40 controller tests build one, and every provider whose build
// can throw either names `lumenRetry` at its own declaration
// (`sessionTodayProvider`, `cycleCalendarControllerProvider`,
// `dayDetailControllerProvider`, `dashboardControllerProvider`) or is exercised
// by a container that names it (`cycle_settings_controller_test.dart`). A
// file-level allowlist over 40 sites would be a rule nobody reads; this is the
// bounded half that is worth enforcing.

/// One `ProviderScope(...)` found in the source, and whether it named `retry:`.
typedef _ScopeSite = ({String path, int line, bool namesRetry});

class _ScopeVisitor extends RecursiveAstVisitor<void> {
  _ScopeVisitor(this.path, this.lineOf, this.sites);
  final String path;
  final int Function(int offset) lineOf;
  final List<_ScopeSite> sites;

  void _record(int offset, ArgumentList arguments) {
    sites.add((
      path: path,
      line: lineOf(offset),
      namesRetry: arguments.arguments.whereType<NamedExpression>().any(
        (NamedExpression a) => a.name.label.name == 'retry',
      ),
    ));
  }

  // BOTH spellings, and they are different node types — the same trap
  // `duration_days_guard.dart` documents on `_dayValuedField`, and it cost
  // this audit a red positive control before it was noticed here too. Without
  // resolution `ProviderScope(...)` is indistinguishable from a call to a
  // function of that name, so the parser hands it back as a MethodInvocation;
  // only the `const`/`new` form arrives as an InstanceCreationExpression. All
  // three sites in this repo are the former.
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'ProviderScope') {
      _record(node.offset, node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'ProviderScope') {
      _record(node.offset, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

List<_ScopeSite> _providerScopeSites() {
  final Directory root = resolvePackageRoot();
  final String rootPath = root.path.replaceAll(r'\', '/');
  final sites = <_ScopeSite>[];

  for (final String dir in <String>['lib', 'test']) {
    final Directory d = Directory('$rootPath/$dir');
    if (!d.existsSync()) continue;
    for (final FileSystemEntity entity in d.listSync(recursive: true)) {
      if (entity is! File) continue;
      final String path = entity.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart')) continue;
      final String relative = path.substring(rootPath.length + 1);
      if (relative.startsWith('lib/api/')) continue;

      final ParseStringResult result = parseString(
        content: stripBom(File(path).readAsStringSync()),
        path: relative,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      if (result.errors.isNotEmpty) continue;
      result.unit.visitChildren(
        _ScopeVisitor(
          relative,
          (int offset) => result.lineInfo.getLocation(offset).lineNumber,
          sites,
        ),
      );
    }
  }
  return sites;
}

void _auditTests() {
  group('every ProviderScope in the repo names a retry policy', () {
    test('the walker actually finds the scopes — a blind finder passes '
        'vacuously, so this is the positive control', () {
      final List<String> paths =
          _providerScopeSites().map((_ScopeSite s) => s.path).toSet().toList()
            ..sort();

      expect(paths, <String>[
        'lib/app.dart',
        'test/features/checkin/quick_checkin_screen_golden_test.dart',
        'test/support/golden_app.dart',
      ]);
    });

    test('none of them omits `retry:`', () {
      final List<String> offenders = <String>[
        for (final _ScopeSite s in _providerScopeSites())
          if (!s.namesRetry) '${s.path}:${s.line}',
      ]..sort();

      expect(
        offenders,
        isEmpty,
        reason:
            'A ProviderScope without `retry:` runs on riverpod 3.3.2\'s '
            'defaultRetry, which rebuilds a build that threw a Failure ten '
            'times over ~38 s while publishing AsyncLoading(retrying: true) — '
            'so every screen under it shows a spinner where its designed '
            'error body belongs. Pass `retry: lumenRetry` '
            '(core/error/retry_policy.dart).',
      );
    });
  });
}
