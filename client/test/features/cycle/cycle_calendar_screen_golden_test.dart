import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/presentation/cycle_calendar_screen.dart';

import '../../support/harness.dart';

/// A controller pinned to one settled month — no reads, so nothing animates.
/// Rule 5 of `golden_app.dart`: never golden a loading state.
class _SettledCalendar extends CycleCalendarController {
  _SettledCalendar(this.view);

  final CycleCalendarView view;

  // `async` because CycleCalendarController's OWN build() is declared
  // `Future<CycleCalendarView> Function()`, not the bare `FutureOr<T>` its
  // AsyncNotifier base allows — an override matches the signature actually
  // declared on its immediate superclass. It never really awaits anything.
  @override
  Future<CycleCalendarView> build() async => view;
}

void main() {
  // April 2026 — five rows, same month the mockup itself draws (`Screens/
  // screen_10_cycle_calendar.html`) — with today on the 22nd and three
  // logged days (16, 19, 20), the same dates the mockup marks with `.mk`.
  final view = CycleCalendarView(
    visibleMonth: DateTime(2026, 4),
    today: Date(2026, 4, 22),
    phase: null,
    dayByDate: <Date, CycleCalendarDay>{
      for (final day in <int>[16, 19, 20])
        Date(2026, 4, day): cycleCalendarDayFixture(
          date: Date(2026, 4, day),
          eventCount: 1,
        ),
      // D-08 control, drawn in the same golden: a pain-FREE day (pain: 0)
      // still carries a dot — a falsiness-tested predicate would silently
      // drop it from this very image.
      Date(2026, 4, 3): cycleCalendarDayFixture(
        date: Date(2026, 4, 3),
        pain: 0,
      ),
    },
  );

  goldenTestLightAndDark(
    subject: 'CycleCalendarScreen',
    fileName: 'cycle_calendar_screen',
    build: (brightness) => goldenApp(
      home: const CycleCalendarScreen(),
      brightness: brightness,
      overrides: [
        // Pinned: without it the month header's weekday order (and any real
        // device locale reachable in CI) would follow whichever machine ran
        // the suite, same reasoning as screen 3's golden.
        deviceLocaleProvider.overrideWithValue('es-ES'),
        cycleCalendarControllerProvider.overrideWith(
          () => _SettledCalendar(view),
        ),
      ],
    ),
  );
}
