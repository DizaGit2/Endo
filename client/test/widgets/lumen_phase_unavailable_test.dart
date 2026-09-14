// Tests for LumenPhaseUnavailable (P4b-T5, brief §4).
//
// TDD (RED first): this widget did not exist. Screens 8, 10, 11 and 14 all draw
// a phase band in the mockups ("Luteal · Day 22"), and P4a answers
// `phase: { available: false, unavailableReason: "phase_engine_not_implemented" }`
// with no day row carrying a phase, cycleDay or confidence. `ARCHITECTURE.md`
// §C.0.3 is exact: *render the unavailable state; do not infer one*.
//
// The copy is asserted verbatim because it is the whole product decision here.
// Goldens cannot do it — `flutter_test_config.dart` turns on `obscureText`, so
// a golden sees blocks, never words.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';

import '../support/harness.dart';

const _heading = "Cycle phases aren't available yet";
const _body =
    'Lumen needs more of your cycle history before it can show phases.';

/// Everything the phase envelope can carry, now and in P6.
const _allReasons = <String?>[
  kPhaseEngineNotImplemented,
  'tracking_paused',
  'insufficient_data',
  'no_period_logged',
  null,
  'something_the_backend_has_not_invented_yet',
];

Future<void> _pumpBand(
  WidgetTester tester, {
  String? reason = kPhaseEngineNotImplemented,
  Brightness brightness = Brightness.light,
}) {
  return pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LumenPhaseUnavailable(reason: reason),
      ),
    ),
  );
}

void main() {
  // -------------------------------------------------------------------------
  // The copy
  // -------------------------------------------------------------------------

  testWidgets('renders the approved copy, verbatim', (tester) async {
    await _pumpBand(tester);

    expect(find.text(_heading), findsOneWidget);
    expect(find.text(_body), findsOneWidget);
  });

  testWidgets('promises nothing: no date, no countdown, no "soon"', (
    tester,
  ) async {
    await _pumpBand(tester);

    expect(find.textContaining('soon'), findsNothing);
    expect(find.textContaining('2026'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('never shows the user the raw wire reason', (tester) async {
    for (final reason in _allReasons) {
      await _pumpBand(tester, reason: reason);

      if (reason == null) continue;
      expect(
        find.textContaining(reason),
        findsNothing,
        reason: '"$reason" is a wire code, not something to read.',
      );
      // And nothing snake_cased leaked in by another route.
      expect(find.textContaining('_'), findsNothing);
    }
  });

  // -------------------------------------------------------------------------
  // Reasons — P6 adds a case; nothing here may blank out or crash first
  // -------------------------------------------------------------------------

  group('reason handling', () {
    testWidgets('every reason the envelope can carry still renders the copy', (
      tester,
    ) async {
      for (final reason in _allReasons) {
        await _pumpBand(tester, reason: reason);

        expect(
          find.text(_heading),
          findsOneWidget,
          reason: 'reason: $reason rendered no heading',
        );
        expect(find.text(_body), findsOneWidget, reason: 'reason: $reason');
      }
    });

    test('the copy resolver answers for every reason, known or not', () {
      for (final reason in _allReasons) {
        final copy = phaseUnavailableCopy(reason);
        expect(copy.heading, _heading, reason: 'reason: $reason');
        expect(copy.body, _body, reason: 'reason: $reason');
      }
    });

    test('P6 copy is deliberately unwritten, not accidentally missing', () {
      // The three P6 reasons deserve their own sentences and that wording
      // needs clinical review this phase does not have. Until then they must
      // resolve to the neutral copy — NOT to an empty string, and NOT to
      // invented wording. This test is what would fail if someone filled in
      // `tracking_paused` without that review.
      for (final reason in const [
        'tracking_paused',
        'insufficient_data',
        'no_period_logged',
      ]) {
        expect(phaseUnavailableCopy(reason), phaseUnavailableCopy(null));
      }
    });
  });

  // -------------------------------------------------------------------------
  // The gate (T23 fix round 1, I-1)
  // -------------------------------------------------------------------------
  //
  // `phaseUnavailableCopy` decides WHAT the block says. `phasesAreUnavailable`
  // decides WHETHER it says anything, and it exists because the copy half
  // structurally cannot: it returns a non-nullable record, so every reason —
  // `null` included — resolves to "cycle phases aren't available yet". Until
  // this function nothing in `lib/features/` or `lib/shared/` read `available`
  // at all, and all three call sites rendered the block unconditionally.

  group('phasesAreUnavailable — the gate P6 flips', () {
    test('only an explicit `available: true` hides the block', () {
      expect(phasesAreUnavailable(true), isFalse);
    });

    test("`available: false` — P4a's stated answer — shows it", () {
      expect(phasesAreUnavailable(false), isTrue);
    });

    test(
      '`null` shows it: no envelope at all, or an envelope with the flag '
      'omitted, is the ABSENCE of an answer and not a claim that phases work',
      () {
        expect(phasesAreUnavailable(null), isTrue);
      },
    );

    test(
      'the reason plays no part — this gate is about availability alone, and '
      'no edit to the copy could have replaced it',
      () {
        // The defect was exactly this confusion: three screens decided what to
        // SAY from the reason and never asked whether there was anything to
        // say. `phasesAreUnavailable` takes no reason at all — and the loop
        // below is why it must not: for every reason the envelope can carry,
        // including `null`, the copy is the same true-but-wrong sentence, so
        // "render nothing" is not expressible on that side of the split.
        for (final reason in _allReasons) {
          expect(
            phaseUnavailableCopy(reason),
            phaseUnavailableCopy(null),
            reason:
                'copy cannot express "render nothing" for $reason, which is '
                'why the gate reads `available` instead',
          );
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // Presentation
  // -------------------------------------------------------------------------

  group('presentation', () {
    testWidgets('sits on the input surface inside a border, radius 14', (
      tester,
    ) async {
      await _pumpBand(tester);
      final decoration =
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byType(LumenPhaseUnavailable),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      expect(decoration.color, lumenLight.input);
      expect(decoration.border, Border.all(color: lumenLight.border));
      expect(decoration.borderRadius, BorderRadius.circular(14));
    });

    testWidgets('heading is ink/w500, body is muted/w400', (tester) async {
      await _pumpBand(tester);

      final heading = tester.widget<Text>(find.text(_heading)).style!;
      final body = tester.widget<Text>(find.text(_body)).style!;

      expect(heading.color, lumenLight.ink);
      expect(heading.fontWeight, FontWeight.w500);
      expect(body.color, lumenLight.muted);
      expect(body.fontWeight, FontWeight.w400);
    });

    testWidgets('takes its colours from the dark palette in dark mode', (
      tester,
    ) async {
      await _pumpBand(tester, brightness: Brightness.dark);

      expect(
        tester.widget<Text>(find.text(_heading)).style!.color,
        lumenDark.ink,
      );
      expect(
        tester.widget<Text>(find.text(_body)).style!.color,
        lumenDark.muted,
      );
    });
  });
}
