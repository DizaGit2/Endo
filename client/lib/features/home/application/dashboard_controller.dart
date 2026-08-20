// DashboardController — screen 8's state (P4b-T17, READ SURFACE ONLY).
//
// Screen 8 is the Home tab's landing screen — the authenticated default as of
// R-19 (`app_router.dart`). What P4a genuinely supplies for it is narrower
// than the mockup draws: `MeResponse.displayName` for the greeting, and
// today's/yesterday's `CycleCalendarDay.pain`/`.mood` off the same sparse
// per-day rows screen 10 already reads. No phase, no cycle day, no
// confidence, no insight snapshot, no Energy column — see the screen file's
// own header for the full cut list and citations.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/settings/data/me_repository.dart';

// ---------------------------------------------------------------------------
// DashboardView
// ---------------------------------------------------------------------------

/// Everything screen 8 renders.
@immutable
class DashboardView {
  const DashboardView({
    required this.today,
    required this.displayName,
    required this.todayPain,
    required this.todayMood,
    required this.yesterdayPain,
  });

  /// The user's current day, **as the server computes it** (D-12) — read
  /// once via [sessionTodayProvider], never the device clock.
  final DateTime today;

  /// `MeResponse.displayName` — nullable. A user with no name set greets
  /// without one rather than printing an empty slot or the literal `null`
  /// (screen file's `_GreetingLine`).
  final String? displayName;

  /// Today's `CycleCalendarDay.pain`. `null` means nothing was logged today —
  /// **never** conflated with a real, logged `0` (D-08).
  final int? todayPain;

  /// Today's `CycleCalendarDay.mood` (the `cycle_day_logs.mood` 1-4 ordinal
  /// scale, same source `day_detail_screen.dart`'s `_MoodRow` reads).
  final int? todayMood;

  /// Yesterday's `CycleCalendarDay.pain`, resolved from whichever of the two
  /// requested months actually contains yesterday — the previous month
  /// whenever today is the 1st. `null` means nothing was logged yesterday.
  final int? yesterdayPain;
}

// ---------------------------------------------------------------------------
// One resolved read
// ---------------------------------------------------------------------------

/// One [CacheResult] resolved to its value, plus whether it was [Stale].
///
/// Unlike `DayDetailController`/`CycleCalendarController` (which turn a
/// [NetworkRequired] into a `throw` and collapse every degraded state onto
/// [LumenErrorRetry]), this controller preserves the [CacheResult] union —
/// screen 8 follows screen 31's four-state pattern instead (the brief's own
/// instruction), so [NetworkRequired] must survive as a real, renderable
/// "connect to load" state, not become an exception.
class _Resolved<T> {
  const _Resolved({required this.value, required this.stale});
  final T value;
  final bool stale;
}

/// Resolves one [CacheResult]: [Fresh]/[Stale] unwrap to `_Resolved`;
/// [NetworkRequired] appends its [Failure] to [unreachable] and returns
/// `null`. Three calls (one per read) that all append to the SAME list is
/// what lets [DashboardController.build] answer "was ANY read unreachable"
/// with one check, after all three reads have already run — no partial
/// dashboard from a read that happened to fail first.
_Resolved<T>? _resolve<T>(CacheResult<T> result, List<Failure> unreachable) {
  switch (result) {
    case Fresh(:final value):
      return _Resolved(value: value, stale: false);
    case Stale(:final value):
      return _Resolved(value: value, stale: true);
    case NetworkRequired(:final failure):
      unreachable.add(failure);
      return null;
  }
}

// ---------------------------------------------------------------------------
// DashboardController
// ---------------------------------------------------------------------------

/// Drives screen 8.
///
/// **Shape: `AsyncNotifier<CacheResult<DashboardView>>`** — screen 31's own
/// shape (`ProfileController`), not the shape T15/T16 use. This screen writes
/// nothing (T17 is read-only) and draws no control that could invoke a
/// mutation before [build]'s own `await`s settle, so there is no synchronous
/// action racing [build] — the controller-shape rule's "real await" branch
/// applies either way; what differs here is what the OUTER `AsyncValue`
/// wraps. [AsyncError] is reserved for a genuine [Failure] (validation, auth,
/// unexpected) that one of the three reads below throws; a [NetworkRequired]
/// answer is not that — it is [ProfileController]'s "no network AND no
/// cache" state, and the four states the brief asks for (loading / empty /
/// error / stale) are loading → [AsyncLoading], error → [AsyncError],
/// empty → `data: NetworkRequired`, stale → `data: Stale`.
///
/// **Three reads, combined.**
/// - `GET /me` (name) — started immediately; it does not depend on `today`.
/// - `sessionTodayProvider` — the one shared "what day is it" read every
///   dated screen goes through (never the device clock, D-12). Needed BEFORE
///   the two calendar reads below, because "the current month" is a question
///   about today.
/// - `CycleRepository.getCalendarMonth` for the current month AND the
///   previous month, **unconditionally**, both started before either is
///   awaited (the same "capture both futures, then await each" idiom
///   `DayDetailController`/`CycleCalendarController` use for real
///   concurrency). Unconditional on purpose: yesterday falls in the previous
///   month whenever today is the 1st, and a conditional second read for that
///   one day is an off-by-one waiting to ship (the brief's own reasoning) —
///   two always-issued, always-cached reads are simpler to reason about than
///   one plus an edge case, and the previous month is usually already warm
///   from the calendar tab.
///
/// **Combining rule (this controller's own — brief: "you are defining it, so
/// document the rule you chose").** All three reads happen regardless of any
/// one of them degrading, and only THEN is the outcome decided:
/// - any [NetworkRequired] among the three → the WHOLE view is
///   [NetworkRequired] (screen 8 shows ProfileScreen's "connect to load"
///   surface, never a dashboard with one card silently missing);
/// - otherwise, any [Stale] among the three → the WHOLE view is [Stale] (the
///   stale notice, same as screen 31);
/// - otherwise → [Fresh].
///
/// A genuine [Failure] thrown by any of the three reads is not caught here —
/// it propagates through the `await`s exactly as `DayDetailController`'s two
/// reads do, and `AsyncNotifier` turns it into [AsyncError].
class DashboardController extends AsyncNotifier<CacheResult<DashboardView>> {
  @override
  Future<CacheResult<DashboardView>> build() async {
    final meRepo = ref.read(meRepositoryProvider);
    final cycleRepo = ref.read(cycleRepositoryProvider);

    // Started here, before `today` is known — the profile read has no
    // dependency on which month is "current". `.ignore()` is attached
    // immediately: a genuine rejection here would otherwise race Dart's
    // zone-level "unhandled Future error" report against the `await` below,
    // because nothing subscribes to this future until AFTER `today` (a
    // second, unrelated `await`) resolves — `.ignore()` gives it a listener
    // synchronously, which silences that report without consuming the
    // future; the SAME rejection still reaches `await meFuture` below
    // untouched, exactly as a second independent listener on one Future
    // always does in Dart.
    final meFuture = meRepo.getMe()..ignore();

    final today = await ref.read(sessionTodayProvider.future);
    final todayDate = today.toDateTime();
    final currentMonth = DateTime(todayDate.year, todayDate.month);
    final previousMonth = DateTime(todayDate.year, todayDate.month - 1);

    // Both started before either is awaited — genuine concurrency, same
    // idiom as DayDetailController's two reads. Same `.ignore()` reasoning
    // as `meFuture`: `currentFuture` gets no listener until AFTER
    // `previousFuture` is created AND `meFuture` is awaited, a real gap a
    // fast rejection can lose the race against.
    final currentFuture = cycleRepo.getCalendarMonth(currentMonth)..ignore();
    final previousFuture = cycleRepo.getCalendarMonth(previousMonth)..ignore();

    final meResult = await meFuture;
    final currentResult = await currentFuture;
    final previousResult = await previousFuture;

    final unreachable = <Failure>[];
    final meRead = _resolve(meResult, unreachable);
    final currentRead = _resolve(currentResult, unreachable);
    final previousRead = _resolve(previousResult, unreachable);

    if (unreachable.isNotEmpty) {
      return NetworkRequired<DashboardView>(unreachable.first);
    }

    final dayByDate = <Date, CycleCalendarDay>{};
    for (final day in <CycleCalendarDay>[
      ...?currentRead!.value.days,
      ...?previousRead!.value.days,
    ]) {
      final date = day.date;
      if (date != null) dayByDate[date] = day;
    }

    final yesterday = todayDate.subtract(const Duration(days: 1)).toDate();
    final todayRow = dayByDate[today];
    final yesterdayRow = dayByDate[yesterday];

    final view = DashboardView(
      today: todayDate,
      displayName: meRead!.value.displayName,
      todayPain: todayRow?.pain,
      todayMood: todayRow?.mood,
      yesterdayPain: yesterdayRow?.pain,
    );

    final stale = meRead.stale || currentRead.stale || previousRead.stale;
    return stale ? Stale(view) : Fresh(view);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 8's controller.
///
/// `autoDispose`: today's/yesterday's pain-and-mood PRESENCE still describes
/// health behaviour, matching every other P4b screen controller's reasoning
/// (`ProfileController`, `CycleCalendarController`, `DayDetailController`) —
/// this state must not outlive the screen showing it, most concretely on
/// sign-out on a shared device.
///
/// `retry: (_, __) => null` — the same measured finding documented in full on
/// `sessionTodayProvider` and `CycleCalendarController`: Riverpod's own
/// default retry (exponential backoff, up to 10 attempts) would intercept a
/// thrown [build] before it ever reaches [AsyncError], leaving the screen on
/// an indeterminate spinner instead of promptly reaching the retry surface.
final dashboardControllerProvider =
    AsyncNotifierProvider.autoDispose<
      DashboardController,
      CacheResult<DashboardView>
    >(DashboardController.new, retry: (_, _) => null);
