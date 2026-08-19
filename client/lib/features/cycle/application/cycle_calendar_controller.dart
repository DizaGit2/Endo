// CycleCalendarController — screen 10's state (P4b-T15).
//
// Screen 10 is the Cycle tab's landing screen and the first consumer of T14's
// cycle data layer. What it can honestly draw is narrow: P4a supplies the
// server's `today` and a sparse per-day row good for one "something was
// logged" dot — no phase, no cycle day, no confidence (`ARCHITECTURE.md`
// §C.0.3). This controller's whole job is combining three month-bucketed
// reads (previous/current/next) into one view the screen can render honestly,
// and re-reading that same window — never resetting it — when asked to.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';

// ---------------------------------------------------------------------------
// CycleCalendarView
// ---------------------------------------------------------------------------

/// Everything screen 10 renders for one visible month.
@immutable
class CycleCalendarView {
  const CycleCalendarView({
    required this.visibleMonth,
    required this.today,
    required this.phase,
    required this.dayByDate,
  });

  /// The first day of the month currently on screen.
  final DateTime visibleMonth;

  /// The user's current day, **as the server computes it** (D-12) — never the
  /// device clock. Read once via [sessionTodayProvider] and carried forward
  /// across paging rather than re-read, so the ring never disagrees with
  /// itself mid-session.
  final Date today;

  /// P4a's phase-availability envelope, taken from the VISIBLE month's own
  /// response (index 1 of the three windows [CycleCalendarController] reads).
  /// `ARCHITECTURE.md` §C.0.3 says every P4a account answers `{available:
  /// false, unavailableReason: "phase_engine_not_implemented"}` today, but
  /// this class forwards whatever the server actually sent rather than
  /// hard-coding that string here too.
  final CyclePhaseAvailabilityResponse? phase;

  /// Every sparse day row the previous, current and next month's reads
  /// carried, merged and keyed by its own [Date].
  ///
  /// A date ABSENT from this map has nothing logged on it — the brief's §5:
  /// *"`days` is SPARSE and ASCENDING: a day with nothing on it is absent from
  /// the array, not a zero row."* This map preserves that: it is never
  /// populated with a zero-valued placeholder for a day the server omitted.
  final Map<Date, CycleCalendarDay> dayByDate;
}

// ---------------------------------------------------------------------------
// The dot predicate
// ---------------------------------------------------------------------------

/// Exactly the predicate the brief specifies, and nothing else:
///
/// ```
/// pain != null || mood != null || hasNotes || eventCount > 0 || symptomCount > 0
/// ```
///
/// **`pain: 0` is a real logged datum (D-08)** — checking `pain != null`
/// (never `pain != 0`, never a bare `if (day.pain)`-shaped falsiness test) is
/// what keeps a pain-free day's dot showing; a falsiness test would silently
/// drop the exact users who logged one. Every [CycleCalendarDay] property is
/// nullable (§C.0.2), so [CycleCalendarDay.hasNotes] is compared with
/// `== true` here — never force-unwrapped with `!`.
///
/// Public (not `@visibleForTesting`) on purpose: [_DayCell] in
/// `cycle_calendar_screen.dart` calls this from production code, not only
/// from a test.
bool cycleCalendarDayHasMark(CycleCalendarDay day) {
  if (day.pain != null) return true;
  if (day.mood != null) return true;
  if (day.hasNotes == true) return true;
  if ((day.eventCount ?? 0) > 0) return true;
  if ((day.symptomCount ?? 0) > 0) return true;
  return false;
}

// ---------------------------------------------------------------------------
// CycleCalendarController
// ---------------------------------------------------------------------------

/// Drives screen 10.
///
/// **Shape: `AsyncNotifier<CycleCalendarView>`, a REAL await in [build] — the
/// controller-shape rule's other branch.** Unlike screen 3's controller
/// (`CycleSetupController`, `Notifier` + a microtask-deferred load), nothing
/// here is a synchronous mutation racing [build]'s own future: the chevrons
/// that page the month do not exist in the tree until [build] has already
/// settled into `AsyncData` (the screen's `loading` arm draws no chevrons), so
/// there is no call site that could invoke [showPreviousMonth] /
/// [showNextMonth] / [refresh] while the initial read is still in flight.
/// [AsyncValue.guard] is what every write-path method below settles its state
/// through, per that same rule.
///
/// **Three month reads, not one grid-shaped read** (brief §5 — supersedes an
/// earlier, wrong ruling of the orchestrator's own that a single read spanning
/// the visible grid's first cell to its last would do). `CycleRepository.
/// getCalendarMonth` is MONTH-BUCKETED (T14, `CacheKeys.cycleCalendarMonth`) —
/// a 42-day read spanning three months has no single month to file itself
/// under, so a write on a neighbouring day could not invalidate it correctly.
/// Reading previous/current/next separately keeps every cached entry
/// invalidatable by [CacheKeys.keysForDate] AND pre-warms the two months
/// paging is likeliest to need next.
class CycleCalendarController extends AsyncNotifier<CycleCalendarView> {
  /// Guards a paging/refresh action's result against a LATER action's result
  /// landing first — e.g. two rapid taps on the month chevron, or a refresh
  /// racing a page.
  ///
  /// **Reachability, precisely (fix-round-1, M-5 — measured, not asserted
  /// from the shape of the code):**
  /// - Two overlapping [_page] calls can never race each other: [_page]
  ///   writes `state = const AsyncValue.loading()` SYNCHRONOUSLY before its
  ///   only `await`, so a second call arriving before the first resolves
  ///   always finds `state.value == null` and bails at the top — the guard
  ///   never even reaches an increment on that path.
  /// - Two overlapping [refresh] calls CAN race, and the guard is what
  ///   stops it. Unlike [_page], [refresh] does not null out `state.value`
  ///   before awaiting — so a second call issued before the first resolves
  ///   sees the SAME non-null data, proceeds, and starts its own
  ///   `_loadMonth`. Measured directly (counting `getCalendarMonth` calls
  ///   at the REPOSITORY interface, not the HTTP mock — `cachedRead`'s own
  ///   in-flight de-dup would otherwise hide it): two overlapping
  ///   `refresh()` calls issue two independent three-window reads. Without
  ///   this guard, whichever of the two happens to RESOLVE last would win
  ///   even if it was the first one ISSUED — silently reverting a newer
  ///   result to a stale one. `cycle_calendar_controller_test.dart`'s
  ///   "`_generation` IS reachable for refresh() vs refresh()" test forces
  ///   exactly that ordering and pins the correct outcome.
  ///
  /// Not needed for [build] itself: nothing can call an action before the
  /// screen exposes the controls that trigger one, and those controls do not
  /// exist before [build] settles.
  int _generation = 0;

  @override
  Future<CycleCalendarView> build() async {
    final today = await ref.read(sessionTodayProvider.future);
    return _loadMonth(month: DateTime(today.year, today.month), today: today);
  }

  // ── Paging ───────────────────────────────────────────────────────────────

  /// Shows the month before the one on screen.
  ///
  /// Unbounded in EITHER direction (brief §5: *"Do not impose an artificial
  /// paging bound"*) — P4a places no floor on how far back a user may page,
  /// and unlike screen 3's anchor picker there is no future-date rule to honour
  /// here at all: a future `to` is legal on this endpoint precisely so paging
  /// forward works.
  Future<void> showPreviousMonth() =>
      _page((month) => DateTime(month.year, month.month - 1));

  /// Shows the month after the one on screen. Unbounded, for the same reason.
  Future<void> showNextMonth() =>
      _page((month) => DateTime(month.year, month.month + 1));

  Future<void> _page(DateTime Function(DateTime current) next) async {
    final current = state.value;
    // Not settled yet — the chevrons that call this do not exist in that
    // state, so this is a defensive no-op rather than a reachable UI path.
    if (current == null) return;

    final generation = ++_generation;
    final target = next(current.visibleMonth);

    // The one correctness rule on the transition (brief §7): paging must
    // never show a stale month's dots under a new month's title. Going
    // through `loading` makes that true by construction — the title and the
    // grid are drawn from the SAME AsyncValue, so there is no frame in which
    // one has moved to the new month and the other has not.
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _loadMonth(month: target, today: current.today),
    );
    if (!ref.mounted || generation != _generation) return;
    state = result;
  }

  // ── Refresh (T16's call site) ───────────────────────────────────────────

  /// Re-reads whatever month is currently on screen, without resetting to
  /// today's month.
  ///
  /// **This is what T16 (screen 11's day writes) must call after a
  /// successful write** —
  /// `ref.read(cycleCalendarControllerProvider.notifier).refresh()` — and
  /// specifically NOT `ref.invalidate(cycleCalendarControllerProvider)`.
  /// Invalidating throws this notifier away and reruns [build], which always
  /// re-derives the visible month from `today`; a write made while the user
  /// had paged away from the current month would silently snap them back to
  /// it. [refresh] instead re-issues the exact three-window read
  /// [showPreviousMonth]/[showNextMonth] use, for the month already on
  /// screen — it needs no cache-key bookkeeping of its own, because
  /// `CycleRepository.logEvent`/`deleteEvent` already invalidate the written
  /// day's `CacheKeys.cycleCalendarMonth` bucket (T14,
  /// `CacheKeys.keysForDate`). The re-read this method issues is therefore a
  /// real network fetch for the ONE month that actually changed and an
  /// instant cache hit for the other two — the same property
  /// [showPreviousMonth]/[showNextMonth] have when paging into an
  /// already-warm month.
  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      // Nothing loaded yet (still loading, or errored) — rerunning build is
      // already the honest "start from today's month" behaviour; there is no
      // "month on screen" to preserve.
      ref.invalidateSelf();
      return;
    }

    final generation = ++_generation;
    final result = await AsyncValue.guard(
      () => _loadMonth(month: current.visibleMonth, today: current.today),
    );
    if (!ref.mounted || generation != _generation) return;
    state = result;
  }

  // ── The three-window read ───────────────────────────────────────────────

  /// Reads the previous, current and next month for [month] concurrently and
  /// merges their sparse day rows into one [CycleCalendarView].
  ///
  /// **Any failure among the three fails the whole read.** A [CacheResult] can
  /// answer [NetworkRequired] as a plain VALUE rather than a thrown exception
  /// (`cachedRead`'s own contract for a connectivity/transient-server
  /// failure with nothing cached) — that is turned into a `throw` here so it
  /// still reaches the caller as a rejected [Future], exactly like a real
  /// exception would. Brief §5: *"If any of the three fails, the screen shows
  /// the error and retry — not a partial grid. A calendar rendered with
  /// five-sixths of its dots correct and the remainder silently absent is
  /// worse than a retry, because nothing on screen distinguishes the missing
  /// sixth from a month with nothing logged."*
  Future<CycleCalendarView> _loadMonth({
    required DateTime month,
    required Date today,
  }) async {
    final repo = ref.read(cycleRepositoryProvider);
    final windows = <DateTime>[
      DateTime(month.year, month.month - 1),
      month,
      DateTime(month.year, month.month + 1),
    ];

    final results = await Future.wait(
      windows.map(repo.getCalendarMonth).toList(),
    );

    final responses = <CycleCalendarResponse>[
      for (final result in results)
        switch (result) {
          Fresh(:final value) => value,
          Stale(:final value) => value,
          NetworkRequired(:final failure) => throw failure,
        },
    ];

    final dayByDate = <Date, CycleCalendarDay>{};
    for (final response in responses) {
      for (final day in response.days ?? const <CycleCalendarDay>[]) {
        final date = day.date;
        if (date != null) dayByDate[date] = day;
      }
    }

    return CycleCalendarView(
      visibleMonth: month,
      today: today,
      // The CURRENT (visible) month's own envelope — index 1 of [windows].
      // Every P4a response answers the same `phase` regardless of window, so
      // this is a choice of which response to trust rather than a guess.
      phase: responses[1].phase,
      dayByDate: dayByDate,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 10's controller.
///
/// `autoDispose`: a day's pain/mood PRESENCE (never the value) still describes
/// health behaviour, and the house rule elsewhere in this phase
/// (`ProfileController`, `CycleSetupController`) is that such state does not
/// outlive the screen showing it — most concretely, a sign-out on a shared
/// device must not leave one account's calendar dots resident for the next.
///
/// **`retry: (_, __) => null` — measured, not assumed, the same finding T14's
/// `sessionTodayProvider` already made and documented in full.** Riverpod's
/// OWN default retry (`ProviderContainer.defaultRetry`, exponential backoff up
/// to 10 attempts) intercepts a thrown [build] before it ever becomes
/// [AsyncError]: the state sits at `AsyncLoading(error: ..., retrying: true)`
/// through the whole backoff window instead. That directly contradicts brief
/// §5/§7 — *"a failure in any of the three surfaces the error state"* — which
/// means PROMPTLY, not after up to ten silent retries: the screen's own
/// [LumenErrorRetry] is the retry gesture, user-initiated via
/// `ref.invalidate(...)`, and it must not be racing an automatic one hidden
/// underneath it.
final cycleCalendarControllerProvider =
    AsyncNotifierProvider.autoDispose<
      CycleCalendarController,
      CycleCalendarView
    >(CycleCalendarController.new, retry: (_, _) => null);
