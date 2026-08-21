// DayDetailController — screen 11's state (P4b-T16; P4b-T16b).
//
// Screen 11 is a drill-in from screen 10: "what did I log on April 7?" It
// combines two independent reads into one honest view. It still issues no
// write of its own: P4b-T16b's day-log editor owns
// `POST /cycle/day/{date}` and lives in `day_log_editor_controller.dart`.
// The one thing that editor needs from here is [DayDetailController.applySavedLog]
// — see its dartdoc. The period-event editor (`POST /cycle/events`, the
// opposite write rule) is T16c and does not exist yet.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';

// ---------------------------------------------------------------------------
// DayDetailView
// ---------------------------------------------------------------------------

/// Everything screen 11 renders for one day.
@immutable
class DayDetailView {
  const DayDetailView({
    required this.date,
    required this.log,
    required this.symptoms,
    required this.symptomsTotal,
  });

  /// The day this view is for — the route's own `:date`, never re-derived
  /// from either response (both echo it, but the route parameter is the one
  /// value neither read can get wrong independently of the other).
  final DateTime date;

  /// `GET /cycle/day/{date}`'s `log` — `null` on a day nobody has logged a
  /// pain/mood/note entry on. **Not the same thing as "nothing at all
  /// happened"** — [symptoms] is a separate, independently-empty list.
  final CycleDayLogResponse? log;

  /// The page `GET /symptoms?from={date}&to={date}&limit=100` returned,
  /// newest first (the server's own order). May be fewer rows than
  /// [symptomsTotal] — see that field.
  final List<SymptomResponse> symptoms;

  /// `SymptomListResponse.total` — the TRUE count of rows on this day,
  /// regardless of how many [symptoms] actually returned. R-18 allows up to
  /// 37 rows in a single save, so two saves in one day can exceed even the
  /// 100-row page [SymptomsRepository.getDay] requests; the screen renders
  /// this alongside `symptoms.length` so a truncated day is VISIBLE, never
  /// silent.
  final int symptomsTotal;
}

// ---------------------------------------------------------------------------
// DayDetailController
// ---------------------------------------------------------------------------

/// Drives screen 11 for one [date].
///
/// **Shape: `AsyncNotifier<DayDetailView>`** — the controller-shape rule's
/// "loading build" branch (`lumen-build.md:993-997`), the same one
/// `CycleCalendarController` uses: [build] performs a real `await` before
/// there is anything to render, and screen 11 draws no control that could
/// invoke a mutation before that `await` settles. **P4b-T16b keeps that
/// true**: screen 11's editor affordance opens a sheet whose own
/// `DayLogEditorController` owns the write, and this class gained only
/// [applySavedLog], which cannot be reached before [build] settles (its
/// caller checks `hasValue` first).
///
/// **A family, keyed by [date].** Riverpod 3's hand-written family shape
/// (`AsyncNotifierProvider.family`, `misc.dart`'s `AsyncNotifierProviderFamily`)
/// hands the argument to the NOTIFIER's constructor, not to [build] — so
/// [date] is a field, read by [build] rather than a parameter of it. Each
/// distinct date gets its own controller instance and its own
/// `autoDispose` lifetime, matching `CycleCalendarController`'s reasoning
/// for why day-shaped health state should not outlive the screen showing
/// it.
///
/// **Combining rule for the two reads (undocumented anywhere in this
/// codebase before this task — brief §3: "you are defining it, so document
/// the rule you chose").** Both reads are issued before either is awaited
/// (`getDay`/`getDay` are ordinary — not `async` — methods that start their
/// own work eagerly; capturing both futures first, then awaiting each in
/// turn, still fires both requests concurrently). Each resulting
/// [CacheResult] is then resolved exactly the way
/// `CycleCalendarController._loadMonth` resolves its three month windows:
/// [Fresh] and [Stale] both unwrap to their value, [NetworkRequired] is
/// turned into a `throw` of its own [Failure]. `AsyncNotifier` wraps that
/// throw into [AsyncError] the same way a real exception would. **Either
/// read failing fails the whole screen** — there is no state that shows one
/// section fresh and the other as a partial-failure banner, matching this
/// brief's "any failure surfaces the error and retry, never a partial
/// screen" and T15's identical rule for its three-window read.
class DayDetailController extends AsyncNotifier<DayDetailView> {
  DayDetailController(this.date);

  /// The day this controller reads. Set once, at construction — a new
  /// [date] gets a new controller instance via the family provider below,
  /// never a mutation of this field.
  final DateTime date;

  @override
  Future<DayDetailView> build() async {
    final cycleRepo = ref.read(cycleRepositoryProvider);
    final symptomsRepo = ref.read(symptomsRepositoryProvider);

    // Both requests start executing here — an ordinary (non-`async`) method
    // call runs synchronously up to its own first `await`, so capturing the
    // futures before awaiting either one fires both concurrently.
    final dayFuture = cycleRepo.getDay(date);
    final symptomsFuture = symptomsRepo.getDay(date);

    final dayResult = await dayFuture;
    final symptomsResult = await symptomsFuture;

    final dayResponse = switch (dayResult) {
      Fresh(:final value) => value,
      Stale(:final value) => value,
      NetworkRequired(:final failure) => throw failure,
    };
    final symptomsResponse = switch (symptomsResult) {
      Fresh(:final value) => value,
      Stale(:final value) => value,
      NetworkRequired(:final failure) => throw failure,
    };

    final items = symptomsResponse.items?.toList() ?? const <SymptomResponse>[];

    return DayDetailView(
      date: date,
      log: dayResponse.log,
      symptoms: items,
      // `total` is nullable on the generated model (every property is,
      // §C.0.2) even though the server always sends it; falling back to the
      // page length rather than to 0 means a malformed/absent `total` never
      // manufactures a FALSE truncation notice.
      symptomsTotal: symptomsResponse.total ?? items.length,
    );
  }

  /// Replaces this day's [DayDetailView.log] with [log], leaving everything
  /// else in the view alone (P4b-T16b).
  ///
  /// **The one write-adjacent method on this read controller, and it takes
  /// the STORED row rather than a form's answers.** `POST /cycle/day/{date}`
  /// answers with the row as the server holds it after merging — built from
  /// the entity, not echoed from the request — so it is the freshest possible
  /// value for this view, fresher than the re-read invalidating would cost.
  /// `DayLogEditorController._refreshDependents` has the full reasoning for
  /// why the day-log editor adopts here instead of invalidating: the editor
  /// is a sheet sitting directly on top of the screen watching this
  /// provider, so invalidating would drop that screen to a spinner behind the
  /// scrim and re-issue two reads whose answer is already in hand.
  ///
  /// **[DayDetailView.symptoms] and [DayDetailView.symptomsTotal] are carried
  /// over untouched** — a day-log write cannot create, change or remove a
  /// `symptoms` row (different table, different endpoint, D-11) — and so is
  /// [DayDetailView.date], which stays the route's own day and is never
  /// re-derived from [log]'s echoed `day`.
  ///
  /// A no-op while this controller has no value: there is nothing to patch,
  /// and the caller invalidates instead in that case rather than assembling a
  /// half-built view here.
  void applySavedLog(CycleDayLogResponse log) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData<DayDetailView>(
      DayDetailView(
        date: current.date,
        log: log,
        symptoms: current.symptoms,
        symptomsTotal: current.symptomsTotal,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 11's controller, one per [DateTime] navigated to.
///
/// `autoDispose` for the same reason `cycleCalendarControllerProvider` is:
/// a day's pain/mood/symptom PRESENCE still describes health behaviour, and
/// this state must not outlive the screen showing it.
///
/// `retry: (_, _) => null` — the same measured finding `sessionTodayProvider`
/// and `CycleCalendarController` both document: Riverpod's own default retry
/// (exponential backoff up to 10 attempts) would intercept a thrown [build]
/// before it ever reaches [AsyncError], leaving the screen on an
/// indeterminate spinner instead of promptly showing [LumenErrorRetry].
final dayDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<DayDetailController, DayDetailView, DateTime>(
      DayDetailController.new,
      retry: (_, _) => null,
    );
