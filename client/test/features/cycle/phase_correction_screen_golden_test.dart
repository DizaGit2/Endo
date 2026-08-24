import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/presentation/phase_correction_screen.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';

import '../../support/harness.dart';

/// The Cycle tab's controller pinned to one settled month — rule 5 of
/// `golden_app.dart`: never golden a loading state. Screen 14 reads exactly
/// one field off this view ([CycleCalendarView.phase]).
class _SettledCalendar extends CycleCalendarController {
  _SettledCalendar(this.view);

  final CycleCalendarView view;

  @override
  Future<CycleCalendarView> build() async => view;
}

void main() {
  // April 2026, today the 22nd — the same anchor every other cycle golden
  // uses. The date is invisible on this screen; it is here because
  // [CycleCalendarView] requires one, not because screen 14 draws it.
  final view = CycleCalendarView(
    visibleMonth: DateTime(2026, 4),
    today: Date(2026, 4, 22),
    phase: CyclePhaseAvailabilityResponse(
      (b) => b
        ..available = false
        ..unavailableReason = kPhaseEngineNotImplemented,
    ),
    dayByDate: const <Date, CycleCalendarDay>{},
  );

  goldenTestLightAndDark(
    subject: 'PhaseCorrectionScreen',
    fileName: 'phase_correction_screen',
    build: (brightness) => goldenApp(
      home: const PhaseCorrectionScreen(),
      brightness: brightness,
      overrides: [
        cycleCalendarControllerProvider.overrideWith(
          () => _SettledCalendar(view),
        ),
      ],
    ),
  );
}
