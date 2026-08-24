// ---------------------------------------------------------------------------
// THE GOLDEN COMPARISON GATE — the 78 goldens cannot go quiet
// (P4b-T25a, fix-round-1; assertion 1 repaired in fix-round-2)
// ---------------------------------------------------------------------------
//
// `screen_registry_test.dart` asserts that every screen's two PNGs EXIST. Until
// this file, nothing asserted that they are still COMPARED. That gap is not
// hypothetical on this branch: T25a's first fix made `goldenTestLightAndDark`
// register a *skipped* test off Linux, which turned 78 goldens into `~78` in a
// green run on the primary dev machine — a state a reader of the summary line
// would not distinguish from "everything passed". P4b-T21b lost a golden pair
// to a silent non-failure the same way.
//
// **What this file catches, precisely.** Three ways the suite can report green
// while comparing nothing:
//   1. `ciGoldensConfig.enabled: false` in `flutter_test_config.dart` — the
//      one switch that makes Alchemist skip every CI golden.
//   2. `--update-goldens` over the whole suite — every golden then "passes" by
//      being rewritten from whatever the tree currently renders, which is how
//      a regression gets blessed. Deliberate regeneration is still available
//      and still works: scope it, `flutter test --tags golden
//      --update-goldens`, which does not run this file.
//   3. A host gate reintroduced into `goldenTestLightAndDark` — `skip:`, or a
//      `Platform.is*` branch around the `goldenTest` calls.
//
// **All three are negative-tested: each assertion has been watched to FAIL,
// not merely to pass.** That is not a formality here. Assertion 1 shipped in
// fix-round-1 unable to fail — it read `AlchemistConfig.current()` inside the
// test body, where the ambient config is not visible and Alchemist's library
// default (`enabled: true`) answers instead, so it passed with
// `ciGoldensConfig(enabled: false)` in `flutter_test_config.dart`. A guard
// that cannot fail is worse than no guard, because it reads as deliberate
// cover. Fix-round-2 moved the read to declaration time and broke the config
// once to see the test go red; 2 and 3 were broken and seen red in
// fix-round-1 and again in review.
//
// **What it does NOT catch, stated plainly:** it does not prove that 78 golden
// tests executed in this run. Nothing inside one test file can observe
// another's result. It closes the three known routes to silence; it is not a
// count.

@Tags(<String>['gate'])
library;

import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/screen_registry.dart';

void main() {
  // Read HERE, at declaration time, and not inside the test body — the
  // difference is the whole assertion. `testExecutable` establishes the
  // AlchemistConfig in a zone around `main()`, so this line sees the real
  // ambient value. A test BODY runs in a zone the runner spawns, where
  // `AlchemistConfig.current()` finds no ambient config and falls back to
  // Alchemist's library defaults — whose `ciGoldensConfig.enabled` is `true`.
  // Fix-round-1 read it there, which made this test watch a hard-coded
  // constant: it passed with `enabled: false` in `flutter_test_config.dart`,
  // measured. Alchemist's own `goldenTest` captures the config at declaration
  // time too, so reading it here is reading it where the goldens read it.
  // Negative-tested in fix-round-2: with `enabled: false` this test fails, and
  // with it restored it passes.
  final bool ciGoldensEnabled =
      AlchemistConfig.current().ciGoldensConfig.enabled;

  test('CI goldens are enabled in the ambient Alchemist config', () {
    expect(
      ciGoldensEnabled,
      isTrue,
      reason:
          'flutter_test_config.dart has ciGoldensConfig(enabled: false), so '
          'every one of the 78 committed goldens is being skipped and the '
          'suite is green for a reason that has nothing to do with the app.',
    );
  });

  test('the suite is not silently rewriting every golden', () {
    expect(
      autoUpdateGoldenFiles,
      isFalse,
      reason:
          'This run passed --update-goldens over the WHOLE suite, so all 78 '
          'masters are being overwritten with whatever the tree renders now '
          'and no comparison is happening. If you meant to regenerate, scope '
          'it: flutter test --tags golden --update-goldens (this file is '
          'tagged "gate", so that command skips it).',
    );
  });

  test('goldenTestLightAndDark has no host gate around the comparison', () {
    final String source = File(
      '${resolvePackageRoot().path}/test/support/golden_app.dart',
    ).readAsStringSync();

    // Everything from the declaration onward — the file's header comment
    // discusses both words at length and must stay quotable.
    final int decl = source.indexOf('void goldenTestLightAndDark(');
    expect(decl, isNot(-1), reason: 'goldenTestLightAndDark was renamed.');
    final String body = source.substring(decl);

    expect(
      body,
      isNot(contains('skip:')),
      reason:
          'goldenTestLightAndDark skips a golden pair on some condition. A '
          'skipped golden reports as "~" in a green run, which is how 78 '
          'goldens go quiet without anyone noticing (P4b-T25a). Fix the '
          'divergence at its source instead — rule 9 in golden_app.dart is '
          'the worked example.',
    );
    expect(
      body,
      isNot(contains('Platform.')),
      reason:
          'goldenTestLightAndDark branches on the host platform. The masters '
          'are host-independent by construction since P4b-T25a fix-round-1; '
          'if that stops being true, fix the cause, do not gate the '
          'comparison to one operating system (rule 9).',
    );
  });
}
