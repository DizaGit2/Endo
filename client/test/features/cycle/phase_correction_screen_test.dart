// Screen 14 — the documented phase-unavailable state (P4b-T23).
//
// TDD (RED first). What this file proves, and what it deliberately leaves to
// `phase_correction_source_test.dart` (the source-level half) and
// `test/core/router/phase_correction_route_test.dart` (the routing half):
//
//  * **R2 — the reason is READ, never embedded.** The screen forwards
//    `CyclePhaseAvailabilityResponse.unavailableReason` verbatim, so when P6
//    lands the phase engine this screen stops claiming it is missing without
//    anyone remembering to come back. P4a's own review caught the identical
//    shape one layer down: a `[DefaultValue]` on that nullable property would
//    have left the generated client unable to observe `null`, so the app
//    *"would keep reporting `phase_engine_not_implemented` after P6 shipped"*.
//    **The reason is VARIED across these tests on purpose.**
//    `phaseUnavailableCopy` resolves every reason to the SAME neutral copy
//    today, so a test that renders one reason and asserts the heading is
//    present passes whether the value was read or hard-coded — the assertion
//    is evaluated where both outcomes look identical. Reading the mounted
//    [LumenPhaseUnavailable]'s own `reason` field, with three different values
//    and with `null`, is what tells them apart. Both shipped call sites' tests
//    do exactly this (`dashboard_screen_semantics_test.dart`,
//    `cycle_calendar_screen_semantics_test.dart`).
//  * **R6 — the mockup's correction UI is CUT, not reworded.**
//    `Screens/screen_14_phase_correction.html` draws a draggable phase
//    timeline, a day stepper, a retrain footnote, a Save and a Reset. R-08
//    defers all of it to P6 and R-16 removes copy describing machinery this
//    phase does not ship. Asserted absent here so a later edit cannot restore
//    them silently — the shape T22c used for screen 36's cut App-lock strings.
//  * **R-08 — nothing on this screen can write.** The behavioural half: the
//    screen offers exactly ONE control, and it is the one that leaves.
//  * **I-1 (fix round 1) — the block is GATED on `available`.** Reading the
//    reason correctly, which is all R2 asked for, turns out to be necessary
//    and not sufficient: `phaseUnavailableCopy` maps every reason INCLUDING
//    `null` to the same neutral sentence, so an ungated block goes on denying
//    the phase engine after P6 ships it. The gate is inert across the whole
//    P4a surface — §C.0.3 fixes `available: false` for every account — which
//    is exactly why the `available: true` rows below had to be written by
//    hand: nothing the server can currently answer would have exercised them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/presentation/phase_correction_screen.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// The Cycle tab's controller pinned to one settled month — screen 14 reads
/// exactly one field off it, [CycleCalendarView.phase].
class _SettledCalendar extends CycleCalendarController {
  _SettledCalendar(this.view);

  final CycleCalendarView view;

  @override
  Future<CycleCalendarView> build() async => view;
}

CycleCalendarView _view({required CyclePhaseAvailabilityResponse? phase}) {
  return CycleCalendarView(
    visibleMonth: DateTime(2026, 4),
    today: Date(2026, 4, 22),
    phase: phase,
    dayByDate: const <Date, CycleCalendarDay>{},
  );
}

/// [available] defaults to P4a's own answer (`false`, §C.0.3). The tests that
/// pass `true` are simulating P6 and are the only ones in this file that no
/// server response could produce today.
CyclePhaseAvailabilityResponse _envelope(
  String? reason, {
  bool? available = false,
}) {
  return CyclePhaseAvailabilityResponse(
    (b) => b
      ..available = available
      ..unavailableReason = reason,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required CyclePhaseAvailabilityResponse? phase,
}) async {
  await pumpApp(
    tester,
    home: const PhaseCorrectionScreen(),
    overrides: [
      cycleCalendarControllerProvider.overrideWith(
        () => _SettledCalendar(_view(phase: phase)),
      ),
    ],
  );
}

/// The `reason` the mounted [LumenPhaseUnavailable] is actually carrying.
String? _mountedReason(WidgetTester tester) => tester
    .widget<LumenPhaseUnavailable>(find.byType(LumenPhaseUnavailable))
    .reason;

// ---------------------------------------------------------------------------
// The mockup's cut controls (R6)
// ---------------------------------------------------------------------------

/// Every string `Screens/screen_14_phase_correction.html` draws that this
/// screen does NOT render, listed so restoring one silently is impossible.
///
/// **Delete an entry only together with the ruling that cut it.** P6 owns the
/// override write (R-08) and reinstates the controls with it; until then a
/// screen that draws a Save button over a phase nobody predicted is a form
/// that invents the thing it claims to correct.
const List<String> kCutMockupStrings = <String>[
  'Correct phase',
  'Adjust your timeline',
  'Drag the markers to match what you felt',
  'EDITING',
  'OVULATION START',
  'Day 14',
  'retrain the prediction model',
  'Save correction',
  'Reset to predicted',
  // The timeline's four phase-band labels — drawn over a predicted timeline
  // that does not exist (`ARCHITECTURE.md` §C.0.3: no day row carries a
  // phase, so there is nothing to band).
  'Mens',
  'Foll',
  'Ovul',
  'Luteal',
];

void main() {
  // -------------------------------------------------------------------------
  // R2 — the reason is read, and the value provably varies
  // -------------------------------------------------------------------------

  group('the unavailable reason is READ, never embedded', () {
    for (final reason in <String>[
      kPhaseEngineNotImplemented,
      // Two of the reasons `phaseUnavailableCopy`'s own TODO says P6 will be
      // able to answer. Neither is a string this screen recognises: they are
      // here to make the value VARY, so no hard-coded literal can satisfy all
      // three rows at once.
      'tracking_paused',
      'insufficient_data',
    ]) {
      testWidgets(
        'the supplied reason "$reason" is the one the block carries',
        (tester) async {
          await _pump(tester, phase: _envelope(reason));

          expect(find.byType(LumenPhaseUnavailable), findsOneWidget);
          expect(_mountedReason(tester), reason);
        },
      );
    }

    testWidgets('a null reason stays null — the screen never substitutes '
        'phase_engine_not_implemented, so P6 removing the reason removes the '
        'claim with it', (tester) async {
      await _pump(tester, phase: _envelope(null));

      expect(find.byType(LumenPhaseUnavailable), findsOneWidget);
      expect(_mountedReason(tester), isNull);
    });

    testWidgets(
      'an ABSENT phase envelope also stays null — every generated DTO field '
      'is nullable, and a missing envelope is not a reason',
      (tester) async {
        await _pump(tester, phase: null);

        expect(find.byType(LumenPhaseUnavailable), findsOneWidget);
        expect(_mountedReason(tester), isNull);
      },
    );

    testWidgets('no raw wire code is ever rendered as text', (tester) async {
      await _pump(tester, phase: _envelope(kPhaseEngineNotImplemented));

      // The block explains the state in words; the wire code is data, not
      // copy. `phaseUnavailableCopy` resolves every reason to the neutral
      // sentence — this pins that the code itself never leaks into the UI.
      expect(find.textContaining(kPhaseEngineNotImplemented), findsNothing);
      expect(find.text("Cycle phases aren't available yet"), findsOneWidget);
    });

    testWidgets('the screen reuses the SHARED block rather than a second '
        'unavailable-state widget (R1 — its third production call site)', (
      tester,
    ) async {
      await _pump(tester, phase: _envelope(kPhaseEngineNotImplemented));

      expect(find.byType(LumenPhaseUnavailable), findsOneWidget);
      expect(
        find.text(
          'Lumen needs more of your cycle history before it can '
          'show phases.',
        ),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // I-1 (fix round 1) — the block is gated on AVAILABILITY
  // -------------------------------------------------------------------------

  group('the block is gated on availability, not on the reason', () {
    testWidgets(
      'with phases AVAILABLE the block is gone — screen 14 says nothing '
      'rather than denying an engine that works',
      (tester) async {
        await _pump(tester, phase: _envelope(null, available: true));

        expect(find.byType(LumenPhaseUnavailable), findsNothing);
        expect(find.text("Cycle phases aren't available yet"), findsNothing);
        // The screen still mounts and Back still works: what is gated is the
        // BLOCK, not the route. A screen holding only its chevron is the
        // honest rendering of "this surface exists in P4b *because* phases
        // are unavailable" — and it is unreachable regardless (R3), because
        // the P6 task that flips this flag is the same task that ships the
        // editor and the affordance.
        expect(find.byIcon(Icons.chevron_left), findsOneWidget);
        expect(find.byType(IconButton), findsOneWidget);
      },
    );

    testWidgets(
      'a stale reason does not resurrect it — availability decides, and the '
      'reason only decides what the block would have said',
      (tester) async {
        await _pump(
          tester,
          phase: _envelope(kPhaseEngineNotImplemented, available: true),
        );

        expect(find.byType(LumenPhaseUnavailable), findsNothing);
      },
    );

    testWidgets(
      'and `available: false` renders it exactly as before — the P4a answer, '
      'which is every answer P4a has',
      (tester) async {
        await _pump(tester, phase: _envelope(kPhaseEngineNotImplemented));

        expect(find.byType(LumenPhaseUnavailable), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // R6 — the mockup's correction UI is cut
  // -------------------------------------------------------------------------

  group('the mockup controls R-08 defers are ABSENT', () {
    for (final cut in kCutMockupStrings) {
      testWidgets('"$cut" does not render', (tester) async {
        await _pump(tester, phase: _envelope(kPhaseEngineNotImplemented));

        expect(find.textContaining(cut), findsNothing);
      });
    }

    testWidgets(
      'and no draggable or steppable control of any kind ships — the timeline '
      'markers and the day stepper are cut as CONTROLS, not merely as words',
      (tester) async {
        await _pump(tester, phase: _envelope(kPhaseEngineNotImplemented));

        expect(find.byType(Slider), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.byIcon(Icons.add), findsNothing);
        expect(find.byIcon(Icons.remove), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // R-08 — nothing here can write (the behavioural half)
  // -------------------------------------------------------------------------

  group('no control on this screen can write', () {
    testWidgets(
      'the screen offers exactly ONE control — Back — so no tap on it can '
      'reach POST /cycle/phase-override',
      (tester) async {
        await _pump(tester, phase: _envelope(kPhaseEngineNotImplemented));

        expect(find.byType(IconButton), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      },
    );
  });
}
