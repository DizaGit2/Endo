import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/presentation/day_detail_screen.dart';

import '../../support/harness.dart';

/// A controller pinned to one settled day — no reads, so nothing animates.
/// Rule 5 of `golden_app.dart`: never golden a loading state.
class _SettledDayDetail extends DayDetailController {
  _SettledDayDetail(this.view) : super(view.date);

  final DayDetailView view;

  @override
  Future<DayDetailView> build() async => view;
}

void main() {
  // April 7, 2026 — a Tuesday, matching the mockup's own header
  // (`Screens/screen_11_day_detail.html:34-35`) — with one symptom row, a
  // pain+mood pair, a note, and truncation visible (3 of 4 symptoms), so one
  // golden pair exercises every section this screen draws.
  final date = DateTime(2026, 4, 7);
  final view = DayDetailView(
    date: date,
    log: cycleDayLogFixture(
      pain: 3,
      mood: 3,
      notes: 'Pain eased after stretching. Tea and a heating pad helped.',
    ),
    symptoms: [
      symptomResponseFixture(
        id: 's1',
        symptomCode: 'bloating',
        intensity: 5,
        region: 'lower_back',
        painTypes: const ['cramping'],
        triggers: const ['food'],
      ),
      symptomResponseFixture(
        id: 's2',
        symptomCode: 'fatigue',
        intensity: 0,
        region: 'unspecified',
      ),
      symptomResponseFixture(id: 's3', symptomCode: 'headache', intensity: 2),
    ],
    symptomsTotal: 4,
  );

  goldenTestLightAndDark(
    subject: 'DayDetailScreen',
    fileName: 'day_detail_screen',
    build: (brightness) => goldenApp(
      home: DayDetailScreen(date: date),
      brightness: brightness,
      overrides: [
        dayDetailControllerProvider(
          date,
        ).overrideWith(() => _SettledDayDetail(view)),
      ],
    ),
  );
}
