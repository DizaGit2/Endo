// Screen 10 — the cycle calendar (P4b-T15).
//
// The Cycle tab's landing screen, and the screen most damaged by the missing
// phase engine: the mockup draws four phase-coloured day fills, a four-swatch
// legend, and a `Day 22 of 28 · 62% confidence` line, and none of those has a
// data source in P4a. What P4a genuinely supplies is the server's `today` and
// a sparse per-day row good for one "something was logged" dot. So this
// screen ships only what the data supports:
//
//  * the `.cf` confidence line is CUT entirely (no column backs it);
//  * the `.p1`-`.p4` phase fills are CUT (`ARCHITECTURE.md` §C.0.3: render
//    the unavailable state, do not infer one) — [LumenPhaseUnavailable]
//    stands in for them and for the four-swatch legend;
//  * the mockup's back chevron is CUT — this is a bottom-nav branch root,
//    there is nothing to go back to;
//  * a day tap is CUT — it would land on screen 11, which T16 has not built
//    yet, and ruling R-10 says inert navigation is hidden, not disabled.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_phase_unavailable.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';

// ---------------------------------------------------------------------------
// CycleCalendarScreen
// ---------------------------------------------------------------------------

/// Screen 10 — the Cycle tab's landing screen.
///
/// Mounted as the branch root at `Routes.cycle` (`app_router.dart`); the
/// bottom nav, the surrounding [Scaffold] chrome and the "Cycle" tab selection
/// all come from the shell, not from this widget.
class CycleCalendarScreen extends ConsumerWidget {
  const CycleCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final view = ref.watch(cycleCalendarControllerProvider);

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: view.when(
          loading: () => Center(
            child: CircularProgressIndicator(
              color: c.accent,
              semanticsLabel: 'Loading',
            ),
          ),
          // Brief §7/§5: a failure in any of the three month reads surfaces
          // the error state, never a partial grid.
          error: (error, _) => LumenErrorRetry(
            message: error is Failure
                ? error.message
                : 'Something went wrong. Please try again.',
            onRetry: () => ref.invalidate(cycleCalendarControllerProvider),
          ),
          data: (calendar) => _Body(view: calendar),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _Body extends ConsumerWidget {
  const _Body({required this.view});

  final CycleCalendarView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final locale = ref.watch(localeProvider);
    final materialLocalizations = MaterialLocalizations.of(context);
    final controller = ref.read(cycleCalendarControllerProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: LumenSectionLabel('Cycle')),
          const SizedBox(height: 6),

          // The mockup's `h1` ("April 2026") and `.mh` stepper ("‹ April ›")
          // collapse into ONE control — the brief's requirement 4. Two labels
          // for the same month at two sizes is a mockup artifact (the
          // standalone-screen h1 colliding with a real control), not a design
          // intent to reproduce twice.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MonthStep(
                icon: Icons.chevron_left,
                label: materialLocalizations.previousMonthTooltip,
                onPressed: controller.showPreviousMonth,
              ),
              const SizedBox(width: 6),
              Text(
                // English month name, no locale param — see
                // LumenFormats.monthName's own dartdoc for why.
                LumenFormats.monthName(view.visibleMonth),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 6),
              _MonthStep(
                icon: Icons.chevron_right,
                label: materialLocalizations.nextMonthTooltip,
                onPressed: controller.showNextMonth,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Replaces the mockup's `.cf` confidence line AND its four-swatch
          // phase legend — `ARCHITECTURE.md` §C.0.3.
          LumenPhaseUnavailable(reason: view.phase?.unavailableReason),

          const SizedBox(height: 16),

          _MonthGrid(key: cycleCalendarGridKey, view: view, locale: locale),
        ],
      ),
    );
  }
}

class _MonthStep extends StatelessWidget {
  const _MonthStep({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return IconButton(
      icon: Icon(icon, size: 20, semanticLabel: label),
      color: c.muted,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
    );
  }
}

// ---------------------------------------------------------------------------
// The month grid
// ---------------------------------------------------------------------------

/// The seven weekday **labels** — English initials, indexed by [DateTime]
/// weekday constant. The mockup's fixed `S M T W T F S` header is an English,
/// Sunday-first artifact; the ORDER these are drawn in comes from
/// [LumenFormats.orderedWeekdays], which is Monday-first under es-ES (D-05).
/// Owned by this screen rather than shared, per [LumenFormats.orderedWeekdays]'s
/// own dartdoc: the locale decides the order, the app owns the words (R-04),
/// so the grid rotates for es-ES without a single string being translated.
const Map<int, String> _weekdayInitials = <int, String>{
  DateTime.monday: 'M',
  DateTime.tuesday: 'T',
  DateTime.wednesday: 'W',
  DateTime.thursday: 'T',
  DateTime.friday: 'F',
  DateTime.saturday: 'S',
  DateTime.sunday: 'S',
};

/// One cell of the month grid: [date], and whether it belongs to the
/// previous/next month rather than the one on screen ([dimmed]).
@immutable
class CycleCalendarGridCell {
  const CycleCalendarGridCell({required this.date, required this.dimmed});

  final DateTime date;
  final bool dimmed;
}

/// Builds the exact cells [_MonthGrid] draws for [month] under [locale] —
/// leading days from the previous month, every day of [month] itself, and
/// trailing days from the next month that complete the final row.
///
/// **Sized to the month, never to a fixed row count** (brief §3). The row
/// count is derived from [LumenFormats.leadingBlankDays] and the month's own
/// length: a month starting late in the week spans SIX rows, not the five the
/// mockup happens to show for April 2026 — a hard-coded 5x7 grid is a defect
/// the mockup cannot reveal.
///
/// Leading/trailing cells are drawn with a real adjacent-month day number
/// (dimmed), never a blank box — the adjacent month is one of the three the
/// controller already reads, so every cell drawn, including these, can carry
/// an accurate dot.
///
/// Pure and widget-free on purpose: which row count a given month produces,
/// and which column the 1st lands in under each locale, is then testable
/// without a pump.
@visibleForTesting
List<CycleCalendarGridCell> buildCycleCalendarGrid({
  required DateTime month,
  required String locale,
}) {
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final leading = LumenFormats.leadingBlankDays(month, locale);
  final beforeTrailing = leading + daysInMonth;
  final rows = (beforeTrailing / 7).ceil();
  final trailing = rows * 7 - beforeTrailing;

  final previousMonth = DateTime(month.year, month.month - 1);
  // Day 0 of the current month is the last day of the previous one — correct
  // for 30/31-day months and for both kinds of February.
  final previousMonthLength = DateTime(month.year, month.month, 0).day;
  final nextMonth = DateTime(month.year, month.month + 1);

  return <CycleCalendarGridCell>[
    for (var i = 0; i < leading; i++)
      CycleCalendarGridCell(
        date: DateTime(
          previousMonth.year,
          previousMonth.month,
          previousMonthLength - leading + 1 + i,
        ),
        dimmed: true,
      ),
    for (var day = 1; day <= daysInMonth; day++)
      CycleCalendarGridCell(
        date: DateTime(month.year, month.month, day),
        dimmed: false,
      ),
    for (var i = 0; i < trailing; i++)
      CycleCalendarGridCell(
        date: DateTime(nextMonth.year, nextMonth.month, 1 + i),
        dimmed: true,
      ),
  ];
}

/// Identifies the rendered month grid (weekday header + day rows) so a test
/// can scope an assertion to it specifically — e.g. "no `InkWell` in the
/// GRID", as distinct from the two legitimate ones Material 3's `IconButton`
/// implementation gives the month chevrons (fix-round-1, I-1: a blanket,
/// unscoped `find.byType(InkWell)` check would always find those two and
/// could never usefully assert "none").
const Key cycleCalendarGridKey = Key('cycle-calendar-grid');

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.view, required this.locale, super.key});

  final CycleCalendarView view;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final cells = buildCycleCalendarGrid(
      month: view.visibleMonth,
      locale: locale,
    );
    final rows = cells.length ~/ 7;

    return Column(
      children: [
        // Excluded from semantics: every day cell announces its own content,
        // so seven single letters ahead of them in reading order is noise —
        // the same call screen 3's calendar makes.
        ExcludeSemantics(
          child: Row(
            children: [
              for (final weekday in LumenFormats.orderedWeekdays(locale))
                Expanded(
                  child: Text(
                    _weekdayInitials[weekday]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: c.muted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 3),
          Row(
            children: [
              for (var col = 0; col < 7; col++) ...[
                if (col > 0) const SizedBox(width: 3),
                Expanded(
                  child: _DayCell(
                    // Keyed by date (not by index) so a test can address one
                    // exact cell — including an adjacent-month one — without
                    // ambiguity against same-numbered days elsewhere in the
                    // grid.
                    key: ValueKey<DateTime>(cells[row * 7 + col].date),
                    cell: cells[row * 7 + col],
                    view: view,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Day cell
// ---------------------------------------------------------------------------

/// One day of the grid: a number, an optional today ring, an optional
/// "something was logged" dot. **Never a control** — requirement 2: no
/// `onTap`, no `InkWell` ripple, no button semantics. There is nothing behind
/// a tap here yet (T16 adds the route and the tap together, in one commit),
/// and hit areas are not expanded in anticipation of one either — the
/// phase's tap-target ruling stands, and there is no tap to protect.
class _DayCell extends StatelessWidget {
  const _DayCell({required this.cell, required this.view, super.key});

  final CycleCalendarGridCell cell;
  final CycleCalendarView view;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final date = cell.date;
    final today = view.today.toDateTime();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final day = view.dayByDate[date.toDate()];
    final marked = day != null && cycleCalendarDayHasMark(day);

    final content = AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: isToday ? Border.all(color: c.accent, width: 2) : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w500 : FontWeight.w400,
                color: c.ink,
              ),
            ),
            if (marked)
              Positioned(
                bottom: 2,
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // `.d.dim{opacity:.3}` dims the WHOLE cell (number, ring and dot alike) —
    // reproduced the same way, rather than fading just the text colour, so an
    // adjacent-month day that also happens to carry the today ring or a dot
    // dims correctly too.
    return cell.dimmed ? Opacity(opacity: 0.3, child: content) : content;
  }
}
