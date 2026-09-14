// Accessibility for screen 14 (P4b-T23).
//
// The registry artifact required by R-07/R5. The screen is deliberately the
// narrowest surface in the app — one control (Back) and one informational
// block — so what this file pins is mostly what is NOT there: no second
// button, nothing announcing itself as a control that cannot do anything, and
// no dingbat where an [Icon] belongs (the mockup's `✦` on the retrain footnote
// is cut with the footnote, and would not have shipped as text regardless —
// U+2726 is outside `kAllowedNonAsciiGlyphs`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/presentation/phase_correction_screen.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';

import '../../support/harness.dart';

class _SettledCalendar extends CycleCalendarController {
  _SettledCalendar(this.view);

  final CycleCalendarView view;

  @override
  Future<CycleCalendarView> build() async => view;
}

Future<void> _pump(WidgetTester tester) async {
  await pumpApp(
    tester,
    home: const PhaseCorrectionScreen(),
    overrides: [
      cycleCalendarControllerProvider.overrideWith(
        () => _SettledCalendar(
          CycleCalendarView(
            visibleMonth: DateTime(2026, 4),
            today: Date(2026, 4, 22),
            phase: CyclePhaseAvailabilityResponse(
              (b) => b
                ..available = false
                ..unavailableReason = kPhaseEngineNotImplemented,
            ),
            dayByDate: const <Date, CycleCalendarDay>{},
          ),
        ),
      ),
    ],
  );
}

void main() {
  testWidgetsWithSemantics('no decorative glyph is rendered as text', (
    tester,
  ) async {
    await _pump(tester);

    expectNoDingbats(tester, screen: 'PhaseCorrectionScreen');
  });

  testWidgetsWithSemantics(
    'the back chevron announces itself with the platform\'s own name for the '
    'control — screen 14 is a pushed route inside the Cycle branch, so there '
    'is something to go back TO',
    (tester) async {
      await _pump(tester);

      final back = MaterialLocalizations.of(
        tester.element(find.byType(PhaseCorrectionScreen)),
      ).backButtonTooltip;
      expectLabeledButton(tester, find.bySemanticsLabel(back), back);
    },
  );

  testWidgetsWithSemantics(
    'Back is the ONLY button on the screen — R-08 leaves nothing else to do '
    'here, and an affordance pointing at nothing is what R-10 removes',
    (tester) async {
      await _pump(tester);

      expect(
        kAnyButtonSemantics,
        findsNWidgets(1),
        reason:
            'the back chevron, and nothing else. If this went to 2, name the '
            'second one here rather than raising the number — the only '
            'control R-08 permits on screen 14 is the one that leaves it.',
      );
    },
  );

  testWidgetsWithSemantics(
    'the unavailable block is one merged informational unit, never a button '
    '— nothing is wired behind it, and announcing "button" for a tap that '
    'does nothing is worse than announcing nothing',
    (tester) async {
      await _pump(tester);

      expectNotAButton(
        tester,
        find.byType(LumenPhaseUnavailable),
        merged: <String>[
          "Cycle phases aren't available yet",
          'Lumen needs more of your cycle history',
        ],
      );
    },
  );
}
