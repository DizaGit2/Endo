// ---------------------------------------------------------------------------
// DayLogEditorController — screen 11's day-log editor (P4b-T16b)
// ---------------------------------------------------------------------------
//
// The write behind screen 11: pain, mood and the day's note, through
// `POST /cycle/day/{date}`, which is a **MERGE** — an omitted field is left
// UNCHANGED, and there is no way to clear one at all.
//
// Read `CycleRepository.logDay`'s dartdoc before this file; it carries the
// verified contract. What lives HERE is the state machine, and it is built
// against exactly two rules:
//
//  1. **Only a field the user actually TOUCHED is sent.** [DayLogEditorForm]
//     carries `touchedPain`/`touchedMood`/`touchedNotes` as their OWN
//     explicit state. They are never re-derived from whether the value is
//     null, and the two differ on precisely the input every prefilled field
//     starts at: "holding a value the user has not edited".
//
//  2. **The 200 body is adopted into the READ VIEW, never into the FORM.**
//     Both halves are deliberate and the house rule points the other way —
//     `quick_checkin_controller.dart`'s rule 7 and screen 12's success arm
//     both refuse the response outright. See [DayLogEditorController.submit]
//     and [DayLogEditorController.applyToDayView] for why this surface
//     differs and why it still does not touch the form.
//
// **This screen offers no "clear" affordance, because the endpoint has none.**
// The pain scale is passed `allowClear: false` and the mood chips ignore a
// re-tap of the selected chip. A logged pain or mood CANNOT be removed in v1
// by any route; closing that needs a contract change P4b does not make.
// Suppressing a gesture the server cannot honour is honest — offering one
// that silently no-ops is a data lie.
//
// **No date control, and no clock.** The day is the route's own `:date`,
// already round-trip-verified by `Routes.parseCycleDayDate` before screen 11
// was built. There is no move operation on this endpoint and none is invented
// here; nothing in this file reads `DateTime.now()`.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';

// ---------------------------------------------------------------------------
// Authored copy
// ---------------------------------------------------------------------------

/// Why Save is disabled on a freshly-opened editor.
///
/// **Authored** — no mockup draws this editor at all, so nothing about it is
/// extracted. Queued for the T25 PO copy pass with screen 12's four strings.
///
/// It is a different sentence from [kDayLogEmptyMessage] because it is a
/// different situation: this one says "you have not changed anything yet",
/// which is the ordinary state of an editor that was opened and not yet used.
const String kDayLogNothingChangedMessage =
    'Change pain, mood or the note to save.';

/// Why Save is disabled once the user has cleared everything they changed.
///
/// **SERVER-VERBATIM** — `CycleValidationMessages.DayLogEmpty`, the exact
/// string `POST /cycle/day/{date}` answers with under the cross-field
/// `request` key when pain, mood and a trimmed note are all absent. Mirrored
/// rather than reworded, the same move `kSymptomNothingSelectedMessage`
/// makes: the condition is fully knowable on the device, so the user should
/// meet it as a disabled button with a reason instead of a round trip, and
/// two different sentences for one rule is how a user learns to distrust
/// both.
///
/// Reachable only on a PREFILLED form — screen 9 cannot reach its own
/// equivalent, because it never prefills and its CTA needs a touch. Here the
/// user reaches it by emptying the note they arrived with.
const String kDayLogEmptyMessage =
    'at least one of pain, mood or notes is required';

// ---------------------------------------------------------------------------
// DayLogEditorForm
// ---------------------------------------------------------------------------

/// Everything the day-log editor renders and everything it can send.
@immutable
class DayLogEditorForm {
  const DayLogEditorForm({
    this.pain,
    this.mood,
    this.notes = '',
    this.touchedPain = false,
    this.touchedMood = false,
    this.touchedNotes = false,
    this.submitting = false,
    this.failure,
  });

  /// The form as it opens over [log] — the day view's own already-loaded row,
  /// or `null` on a day nobody has logged anything on.
  ///
  /// **Seeding marks nothing as touched**, which is the whole point: a seeded
  /// value is the server's, not the user's, and asserting it back would be
  /// the lost update (S-2) this design exists to make unreachable.
  factory DayLogEditorForm.seededFrom(CycleDayLogResponse? log) {
    return DayLogEditorForm(
      // `log?.pain` straight through — never `?? 0`. A stored 0 is a real
      // logged "none today" (D-08) and must seed the scale's first stop;
      // `null` must seed no stop at all.
      pain: log?.pain,
      mood: log?.mood,
      // The notes box is a `String`, never `String?`: a text field's empty
      // state IS the empty string, and carrying a second "no note" value
      // would give the same fact two representations.
      notes: log?.notes ?? '',
    );
  }

  /// The pain scale's current value — `0..10`, or `null` for "not recorded".
  /// **Never inspected to decide whether to send it** — see [touchedPain].
  final int? pain;

  /// The mood chips' current value — the WIRE ordinal `1..4`, or `null`.
  final int? mood;

  /// The notes box's current text, exactly as typed (untrimmed).
  final String notes;

  /// Whether the user has interacted with the pain scale since the editor
  /// opened — its own explicit state, **not** `pain != null`.
  ///
  /// The two shapes differ on exactly one input, and it is the one every
  /// prefilled field starts at: a seeded value with no edit behind it.
  /// `if (pain != null)` would send that value back, which under MERGE means
  /// re-asserting a possibly-stale read over whatever the server now holds.
  ///
  /// **A touched field whose value is `null` keeps `touchedPain: true`.**
  /// Screen 9 collapses "touched, then cleared" back to `false`; that is
  /// correct there and would be wrong here. Screen 9 never prefills, so its
  /// collapse only ever describes a value the user invented and withdrew in
  /// the same session — while on a prefilled editor the same collapse would
  /// silently re-merge the two variables this form keeps apart. Whether the
  /// form has anything worth sending is [blockReason]'s question, answered
  /// from the flag AND the value together, at the one place that asks it.
  final bool touchedPain;

  /// Whether the user has picked a mood chip since the editor opened.
  final bool touchedMood;

  /// Whether the user has edited the notes box since the editor opened.
  ///
  /// Set by any edit, including one that restores the seeded text. "Touched"
  /// means the gesture happened; re-sending an unchanged note is a harmless
  /// no-op on this endpoint, while inferring touched-ness by comparing text
  /// would be exactly the value-derived guard rule 1 forbids.
  final bool touchedNotes;

  /// Whether `POST /cycle/day/{date}` is in flight. Every control refuses
  /// input while this is true.
  final bool submitting;

  /// Why the last attempt failed. Cleared the moment the user changes
  /// anything again, or starts a new attempt.
  final Failure? failure;

  /// Whether [pain] would actually reach the wire.
  ///
  /// Both halves are load-bearing: the flag, because an untouched seed must
  /// not travel; the null check, because `LogCycleDayRequest`'s generated
  /// serializer omits a null member, so a "touched" field holding `null`
  /// contributes nothing to the request.
  bool get _sendsPain => touchedPain && pain != null;

  bool get _sendsMood => touchedMood && mood != null;

  /// `notes.trim().isNotEmpty` mirrors the server's own rule — it trims
  /// before deciding, and treats blank text as absent rather than as an
  /// erase instruction. A structural mirror of the contract, not a bound.
  bool get _sendsNotes => touchedNotes && notes.trim().isNotEmpty;

  /// Why Save is disabled, in priority order, or `null` when it is enabled.
  ///
  /// Screen 12's `blockReason` shape: one `String?` getter returning named
  /// module-level constants, rendered straight beside the CTA, with
  /// [canSubmit] defined from it so the two can never disagree.
  String? get blockReason {
    if (_sendsPain || _sendsMood || _sendsNotes) return null;
    if (!touchedPain && !touchedMood && !touchedNotes) {
      return kDayLogNothingChangedMessage;
    }
    // Something was touched, and none of it survives to the wire — the exact
    // condition the endpoint answers with its cross-field 400.
    return kDayLogEmptyMessage;
  }

  bool get canSubmit => blockReason == null;

  DayLogEditorForm copyWith({
    int? pain,
    bool clearPain = false,
    int? mood,
    bool clearMood = false,
    String? notes,
    bool? touchedPain,
    bool? touchedMood,
    bool? touchedNotes,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return DayLogEditorForm(
      // Paired `clearX` flags rather than a bare `pain ?? this.pain`: without
      // them "set pain to null" and "do not pass pain" would be the same
      // call, which is the 0-vs-null hazard in another costume.
      pain: clearPain ? null : (pain ?? this.pain),
      mood: clearMood ? null : (mood ?? this.mood),
      notes: notes ?? this.notes,
      touchedPain: touchedPain ?? this.touchedPain,
      touchedMood: touchedMood ?? this.touchedMood,
      touchedNotes: touchedNotes ?? this.touchedNotes,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

// ---------------------------------------------------------------------------
// DayLogEditorController
// ---------------------------------------------------------------------------

/// Drives the day-log editor for one [date].
///
/// **Shape: a plain `Notifier<DayLogEditorForm>` with a SYNCHRONOUS
/// `build()`** — the empty-build branch of the phase's controller-shape rule,
/// the same one screens 9, 12 and 13 use. It reads no repository: the seed
/// comes from the day view screen 11 has already settled, so there is no
/// build future for a tapped stop to race.
///
/// **A family, keyed by [date]**, matching `DayDetailController` — the editor
/// belongs to one day and cannot be pointed at another.
///
/// `autoDispose`: the form holds the user's own unsent pain/mood/note
/// answers, which is health data. Closing the sheet tears it down, the same
/// house rule `QuickCheckinController` and `SymptomFormController` follow.
class DayLogEditorController extends Notifier<DayLogEditorForm> {
  DayLogEditorController(this.date);

  /// The day this editor writes. Set once, at construction, from the route.
  final DateTime date;

  /// Seeds the form from the day view that is already on screen.
  ///
  /// **`ref.exists` before `ref.read`, and it is load-bearing here.**
  /// `dayDetailControllerProvider` is `autoDispose`; a bare `ref.read` would
  /// CREATE it for a day nobody is looking at, firing `GET /cycle/day` and
  /// `GET /symptoms` from behind a modal. In production the guard is always
  /// true (screen 11 is watching that provider — the sheet opens over it),
  /// so the branch below is the honest answer to "opened some other way":
  /// an empty form, which is safe precisely because nothing in it is marked
  /// touched.
  ///
  /// **The seed may be STALE and that is fine.** `DayDetailController.build`
  /// collapses `Fresh` and `Stale` into the same value, so this cannot tell
  /// them apart even in principle — and does not need to. Under MERGE an
  /// untouched field is omitted, so a stale seed can never be written back.
  /// The alternative the plan proposed — "rehydrate only from Fresh, or
  /// re-GET immediately before writing" — is not available in this codebase:
  /// `Fresh` also means a cache hit inside the 5-minute TTL, and `cachedRead`
  /// has no `forceRefresh`.
  @override
  DayLogEditorForm build() {
    final provider = dayDetailControllerProvider(date);
    final log = ref.exists(provider)
        ? ref.read(provider).value?.log
        : null;
    return DayLogEditorForm.seededFrom(log);
  }

  // ── Answering ─────────────────────────────────────────────────────────

  /// Records a pain-scale tap. [value] is `LumenIntensityScale`'s own report.
  ///
  /// `null` is **unreachable from this surface** — the scale is built with
  /// `allowClear: false`, so tapping the selected stop is a no-op and the
  /// increase/decrease actions never step below the lowest stop. It is
  /// handled rather than asserted because the parameter type is the widget's,
  /// and because the honest answer to a `null` is the same one this method
  /// gives every other value: record it, mark the control touched, and let
  /// [DayLogEditorForm.blockReason] decide whether there is anything to send.
  void setPain(int? value) {
    if (state.submitting) return;
    state = state.copyWith(
      pain: value,
      clearPain: value == null,
      // Never `value != null` — see [DayLogEditorForm.touchedPain].
      touchedPain: true,
      clearFailure: true,
    );
  }

  /// Records a mood-chip tap. [value] MUST be the WIRE ordinal (`1..4`),
  /// never a zero-based list index — the screen owns the `index + 1`
  /// translation and this method does not re-derive it, because doing so
  /// here would hide the off-by-one fabrication path (a grid built on a bare
  /// list index writes `low` when the user tapped `tired`).
  void setMood(int? value) {
    if (state.submitting) return;
    state = state.copyWith(
      mood: value,
      clearMood: value == null,
      touchedMood: true,
      clearFailure: true,
    );
  }

  /// Records an edit to the notes box.
  void setNotes(String value) {
    if (state.submitting) return;
    state = state.copyWith(
      notes: value,
      touchedNotes: true,
      clearFailure: true,
    );
  }

  // ── Submitting ────────────────────────────────────────────────────────

  /// Saves whatever was touched. Returns `true` on success, `false` on a
  /// blocked, rejected or already-in-flight attempt — the screen closes the
  /// sheet only on `true`.
  ///
  /// **The 200 body is adopted into the READ VIEW, never into the FORM.**
  /// Say it in those words, because the house rule points the other way:
  /// `quick_checkin_controller.dart`'s rule 7 and screen 12's success arm
  /// both refuse the response outright, and a reader will assume that pattern
  /// wins here unless the difference is stated.
  ///
  ///  * **Never into the form.** The 200 echoes the STORED row, so it carries
  ///    fields this call never sent — a notes-only save comes back with the
  ///    day's existing pain and mood. Patching those into [state] would make
  ///    an echoed value indistinguishable from user input on the NEXT save,
  ///    which is the fabrication T18 refused. Rule 1 forbids it directly:
  ///    adopting a value would have to invent a `touched` flag for it.
  ///  * **Into the read view, yes.** That same property is what makes the
  ///    body the freshest possible truth for the screen UNDERNEATH — it is
  ///    the stored row, built from the entity after the merge, not an echo of
  ///    the request. See [applyToDayView].
  Future<bool> submit() async {
    final form = state;
    if (form.submitting) return false;
    if (form.blockReason != null) return false;

    state = form.copyWith(submitting: true, clearFailure: true);

    Failure? rejected;
    CycleDayLogResponse? saved;
    try {
      saved = await ref
          .read(cycleRepositoryProvider)
          .logDay(
            date: date,
            pain: form.pain,
            mood: form.mood,
            notes: form.notes,
            touchedPain: form.touchedPain,
            touchedMood: form.touchedMood,
            touchedNotes: form.touchedNotes,
          );
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render —
      // the `goals_controller.dart`/`quick_checkin_controller.dart`
      // precedent (a concurrent cache purge during invalidation, e.g.).
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return rejected == null;

    if (rejected != null) {
      // R9 — state preserved intact. Rebuilt from the PRE-submit snapshot, so
      // every answer and every touched flag survives a failure exactly as the
      // user left them and the retry sends the same request.
      state = form.copyWith(submitting: false, failure: rejected);
      return false;
    }

    _refreshDependents(saved!);

    state = state.copyWith(submitting: false, clearFailure: true);
    return true;
  }

  /// Tells the screens showing this day that it changed.
  ///
  /// **The dashboard: invalidated unconditionally.** It renders today's own
  /// pain and mood, and this write may be to today. [Ref.invalidate] never
  /// CREATES an element, so it costs nothing when the dashboard is not
  /// mounted — and wrapping it in `ref.exists` would be INERT, which P4b-T20b
  /// established by tracing riverpod 3.3.2: `invalidate` is
  /// `readPointer(provider)?.element?.invalidateSelf(...)` and `exists` is the
  /// same lookup returning a bool.
  ///
  /// **This day's detail view: ADOPTED, not invalidated — [applyToDayView].**
  /// This is the one place this editor departs from both shipped
  /// `_refreshDependents`, and the reason is that neither of them had this
  /// shape: screen 9 and screen 12 invalidate a day view on a DIFFERENT
  /// screen, while this sheet sits directly ON TOP of the provider it would
  /// be invalidating. Invalidating it would drop screen 11 to a spinner
  /// behind the scrim, re-issue `GET /cycle/day` and `GET /symptoms`, and
  /// answer with data the 200 in hand already contains — a visible loading
  /// flash the moment the sheet pops, bought for nothing. The repository has
  /// already invalidated the CACHE keys, so this is not a stale cache being
  /// papered over: any later rebuild still re-reads from the network.
  ///
  /// `ref.exists` before the `ref.read` IS load-bearing here — unlike around
  /// an `invalidate` — because `ref.read(provider.notifier)` genuinely does
  /// create the element.
  ///
  /// **The cycle calendar: refreshed only if it already exists AND already
  /// has a value** — screen 9's and screen 12's guard verbatim, for their
  /// reason. `ref.exists` stops a `ref.read` from creating an unopened
  /// calendar (in production: `sessionTodayProvider` plus three month GETs),
  /// and `hasValue` avoids `refresh()`'s own `invalidateSelf()` branch, which
  /// snaps the visible month back to today. A day log changes what that day
  /// contains, so an open calendar is genuinely out of date after this write.
  /// Fire-and-forget: the calendar shows its own refresh treatment and
  /// [submit] does not await it.
  void _refreshDependents(CycleDayLogResponse saved) {
    ref.invalidate(dashboardControllerProvider);

    applyToDayView(saved);

    if (ref.exists(cycleCalendarControllerProvider)) {
      final calendarState = ref.read(cycleCalendarControllerProvider);
      if (calendarState.hasValue) {
        unawaited(ref.read(cycleCalendarControllerProvider.notifier).refresh());
      }
    }
  }

  /// Puts [saved] — the STORED row the 200 carried — onto this day's detail
  /// view, or invalidates that view when there is nothing to put it onto.
  ///
  /// The two branches are not interchangeable:
  ///
  ///  * **Settled ⇒ adopt.** `DayDetailController.applySavedLog` swaps the
  ///    `log` member and leaves `symptoms`/`symptomsTotal` alone, which is
  ///    exactly right: a day-log write cannot change the symptom rows.
  ///  * **Still loading ⇒ invalidate.** There is no value to patch, and the
  ///    in-flight read was issued BEFORE this write committed, so it would
  ///    land as pre-write data with nothing left to correct it. Invalidating
  ///    a still-loading day view is strictly more correct than skipping it —
  ///    P4b-T20b's own finding, restated here because this method's other
  ///    branch is what makes it non-obvious.
  @visibleForTesting
  void applyToDayView(CycleDayLogResponse saved) {
    final provider = dayDetailControllerProvider(date);
    if (ref.exists(provider) && ref.read(provider).hasValue) {
      ref.read(provider.notifier).applySavedLog(saved);
    } else {
      ref.invalidate(provider);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// The day-log editor's controller, one per day navigated to.
final dayLogEditorControllerProvider =
    NotifierProvider.autoDispose
        .family<DayLogEditorController, DayLogEditorForm, DateTime>(
          DayLogEditorController.new,
        );
