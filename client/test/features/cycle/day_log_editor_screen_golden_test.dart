// Goldens for the day-log editor (P4b-T16b).
//
// Photographed the way the user meets it: the sheet's chrome over screen 11's
// scrim, with the form PREFILLED — which is the state the whole task is about
// and the one screen 9's own sheet golden cannot show, because screen 9 never
// prefills.
//
// The sheet is composed here rather than opened through `showDayLogEditor`
// because a golden's `builder:` has no `WidgetTester` and cannot drive a
// route; what is photographed is the same `LumenBottomSheet` the modal route
// wraps this content in (`lumen_bottom_sheet_golden_test.dart`'s precedent).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/presentation/day_log_editor_screen.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';

import '../../support/harness.dart';

/// Shows the sheet only once the day view has settled.
///
/// **Not golden scaffolding — it is screen 11's own gate.** The affordance
/// that opens this sheet lives in the `data` arm of `view.when`, so the
/// editor can only ever be built over a settled day. Building it directly
/// would photograph an EMPTY form for a day that has a log, because the
/// controller seeds itself once, in `build()`, from whatever the day view
/// holds at that moment.
class _SettledDayHost extends ConsumerWidget {
  const _SettledDayHost({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(dayDetailControllerProvider(date));
    if (!view.hasValue) return const SizedBox.shrink();
    return LumenBottomSheet(child: DayLogEditorScreen(date: date));
  }
}

/// A day-detail controller pinned to one settled day — the editor seeds
/// itself from this, exactly as it does in production.
class _SettledDayDetail extends DayDetailController {
  _SettledDayDetail(this.view) : super(view.date);

  final DayDetailView view;

  @override
  Future<DayDetailView> build() async => view;
}

void main() {
  final date = DateTime(2026, 4, 7);
  final view = DayDetailView(
    events: const [],
    date: date,
    log: cycleDayLogFixture(
      pain: 3,
      mood: 3,
      notes: 'Pain eased after stretching. Tea and a heating pad helped.',
    ),
    symptoms: const [],
    symptomsTotal: 0,
  );

  goldenTestLightAndDark(
    subject: 'DayLogEditorScreen',
    fileName: 'day_log_editor_screen',
    build: (brightness) {
      final c = brightness == Brightness.light ? lumenLight : lumenDark;

      return goldenApp(
        brightness: brightness,
        overrides: [
          dayDetailControllerProvider(
            date,
          ).overrideWith(() => _SettledDayDetail(view)),
        ],
        home: Stack(
          fit: StackFit.expand,
          children: [
            // Screen 11 behind the scrim, reduced to its header so the
            // golden's subject is the sheet.
            ColoredBox(
              color: c.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 44, 20, 0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    'April 7',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ),
            ColoredBox(color: scrimFor(brightness)),
            Align(
              alignment: Alignment.bottomCenter,
              child: _SettledDayHost(date: date),
            ),
          ],
        ),
      );
    },
  );
}
