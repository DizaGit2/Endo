// Accessibility tests for LumenPhaseUnavailable (P4b-T5, brief §4).
//
// This band replaces something the mockups draw as a live data readout, so the
// a11y question is what it announces INSTEAD. Two house rules apply:
//
//   * It is informational and nothing is wired behind it, so it must be a
//     `MergeSemantics` unit and never `Semantics(button: true)` — announcing
//     "button" for a tap that does nothing is worse than announcing nothing
//     (`a11y_guard.dart`'s `expectNotAButton`).
//   * It is a steady state, not an async failure, so it is deliberately NOT a
//     live region: it is on screen when the screen is, and interrupting a
//     screen reader to say so every rebuild would be noise.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';

import '../support/harness.dart';

const _heading = "Cycle phases aren't available yet";
const _body =
    'Lumen needs more of your cycle history before it can show phases.';

Future<void> _pumpBand(WidgetTester tester) => pumpApp(
  tester,
  home: const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(16),
      child: LumenPhaseUnavailable(reason: kPhaseEngineNotImplemented),
    ),
  ),
);

void main() {
  testWidgetsWithSemantics('reads as one informational unit, not a button', (
    tester,
  ) async {
    await _pumpBand(tester);

    expectNotAButton(
      tester,
      find.byType(LumenPhaseUnavailable),
      merged: const [_heading, _body],
    );
  });

  testWidgetsWithSemantics('is not a live region — it is a steady state', (
    tester,
  ) async {
    await _pumpBand(tester);

    expect(
      tester
          .getSemantics(find.byType(LumenPhaseUnavailable))
          .flagsCollection
          .isLiveRegion,
      isNot(Tristate.isTrue),
      reason:
          'The band is on screen for as long as the screen is; announcing it '
          'as a live region would interrupt the user on every rebuild.',
    );
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpBand(tester);

    expectNoDingbats(tester, screen: 'LumenPhaseUnavailable');
  });
}
