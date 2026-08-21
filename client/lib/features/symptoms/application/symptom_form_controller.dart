import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/symptoms/application/symptom_batch_assembler.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';

// ---------------------------------------------------------------------------
// SymptomFormController — screen 12's I/O-doing half (P4b-T20a)
// ---------------------------------------------------------------------------
//
// `SymptomForm` (`symptom_form.dart`) is the pure data + guard logic;
// `assembleSymptomBatch` (`symptom_batch_assembler.dart`) is the pure
// mapping to the wire boundary. This file is the one place both meet I/O:
// reading [sessionTodayProvider] (R12) and calling
// [SymptomsRepository.createBatch] — the `QuickCheckinController` shape
// (P4b-T18): a plain `Notifier`, `autoDispose`, no prefill.
class SymptomFormController extends Notifier<SymptomForm> {
  @override
  SymptomForm build() => const SymptomForm(); // R11 — no prefill, no read.

  // ── Setters ──────────────────────────────────────────────────────────

  /// Records the single LOCATION chip. `null` clears it.
  void setRegion(String? value) {
    if (state.submitting) return;
    state = state.copyWith(
      region: value,
      clearRegion: value == null,
      clearSubmission: true,
    );
  }

  /// Toggles one TYPE chip.
  void togglePainType(String code) {
    if (state.submitting) return;
    final next = Set<String>.of(state.painTypes);
    if (!next.remove(code)) next.add(code);
    state = state.copyWith(painTypes: next, clearSubmission: true);
  }

  /// Toggles one TRIGGERS chip.
  void toggleTrigger(String code) {
    if (state.submitting) return;
    final next = Set<String>.of(state.triggers);
    if (!next.remove(code)) next.add(code);
    state = state.copyWith(triggers: next, clearSubmission: true);
  }

  /// Records a pain-scale tap — [value] is [LumenIntensityScale]'s own
  /// report, `int?`, where `null` means the clear gesture fired. `0` is
  /// preserved exactly (D-08); this method never tests it for truthiness.
  void setPainIntensity(int? value) {
    if (state.submitting) return;
    state = state.copyWith(
      painIntensity: value,
      clearPainIntensity: value == null,
      clearSubmission: true,
    );
  }

  /// Toggles one RELATED chip. Selecting adds the code with a `null`
  /// intensity (not set yet); **deselecting DISCARDS whatever intensity it
  /// held (R5)** — re-selecting later starts over at `null`, never restoring
  /// a value from an earlier interaction.
  void toggleRelated(String code) {
    if (state.submitting) return;
    final next = Map<String, int?>.of(state.relatedIntensities);
    if (next.containsKey(code)) {
      next.remove(code);
    } else {
      next[code] = null;
    }
    state = state.copyWith(relatedIntensities: next, clearSubmission: true);
  }

  /// Records a RELATED chip's own intensity. A no-op if [code] is not
  /// currently selected — the intensity scale for a code only appears once
  /// its chip is toggled on (progressive disclosure is T20b's screen-level
  /// concern; this method just refuses to invent a selection).
  void setRelatedIntensity(String code, int? value) {
    if (state.submitting) return;
    if (!state.relatedIntensities.containsKey(code)) return;
    final next = Map<String, int?>.of(state.relatedIntensities)..[code] = value;
    state = state.copyWith(relatedIntensities: next, clearSubmission: true);
  }

  /// Records the notes box. `null` clears it.
  void setNotes(String? value) {
    if (state.submitting) return;
    state = state.copyWith(
      notes: value,
      clearNotes: value == null,
      clearSubmission: true,
    );
  }

  /// The T21 seam: screen 13 hands back its own already-built
  /// [SymptomEntryDraft]s here. Replaces the field wholesale — there is no
  /// per-point toggle at this layer, since R-15's own toggle semantics (two
  /// taps on the same region+side) belong to screen 13, not this form.
  void setBodyMapPoints(List<SymptomEntryDraft> points) {
    if (state.submitting) return;
    state = state.copyWith(bodyMapPoints: points, clearSubmission: true);
  }

  // ── Submitting ───────────────────────────────────────────────────────

  /// Saves the assembled batch. Returns `true` on success, `false` on a
  /// blocked, rejected or already-in-flight attempt.
  ///
  /// **R7** — a no-op when [SymptomForm.blockReason] is non-null: the screen
  /// must gate its CTA on [SymptomForm.canSubmit], and this is the
  /// controller-level guard behind it, the same belt-and-suspenders shape
  /// `QuickCheckinController.submit`'s `!form.canSubmit` check uses.
  Future<bool> submit() async {
    final form = state;
    if (form.submitting) return false;
    if (form.blockReason != null) return false;

    // Captured from THIS snapshot, before `state` changes to `submitting:
    // true` below — [assembleSymptomBatch] is pure and reads nothing else,
    // so the batch cannot depend on anything that happens later in this
    // method. `painIndex` mirrors the assembler's own "pain row is always
    // index 0 when present" invariant, captured once here rather than
    // re-derived by searching the batch's content later (see
    // [SymptomForm.submittedPainIndex]'s own dartdoc for why content-search
    // would be ambiguous for the pain row specifically).
    final drafts = assembleSymptomBatch(form);
    final painIndex = form.painIntensity != null ? 0 : null;

    state = form.copyWith(submitting: true, clearSubmission: true);

    Failure? rejected;
    // The day the batch landed on, captured inside the `try` below and read
    // again by [_refreshDependents] (P4b-T20b). Screen 12 draws no date
    // affordance, so every entry's `occurredAt` is null and the server dates
    // the whole batch by its own `now` — which is the same civil day
    // `sessionTodayProvider` just confirmed. Held as a local rather than
    // re-read after the await: a second read could, in principle, answer a
    // different day across midnight, and the screens to refresh are the ones
    // for the day this write actually reached.
    DateTime? savedDay;
    try {
      // R12 — the server-confirmed "today", exactly as
      // `quick_checkin_controller.dart:204,212` reads it. `Date.toDateTime()`
      // gives LOCAL midnight carrying the server's civil fields — never
      // `.toUtc()` it (a same-value no-op in every test here, a real
      // off-by-one-day bug on a positive-offset device in production; see
      // `symptoms_repository.dart`'s own documented M-2 regression, and the
      // dedicated R12 test in `symptom_form_controller_test.dart`).
      final today = await ref.read(sessionTodayProvider.future);
      savedDay = today.toDateTime();
      await ref
          .read(symptomsRepositoryProvider)
          .createBatch(entries: drafts, fallbackDay: savedDay);
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render —
      // the `goals_controller.dart`/`quick_checkin_controller.dart`
      // precedent (a concurrent cache-purge during invalidation, e.g.).
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return rejected == null;

    if (rejected != null) {
      // R10 — state preserved intact: every field below EXCEPT
      // submitting/failure/submittedDrafts/submittedPainIndex is copied
      // straight off the PRE-submit `form` snapshot, unchanged. Built as a
      // fresh SymptomForm directly, not via `copyWith` — see
      // [SymptomForm.copyWith]'s own dartdoc for why a generic `x ?? this.x`
      // three-parameter version of this write would have the exact "0 vs
      // null" hazard R2 exists to prevent (a RELATED-only retry's `null`
      // painIndex could never be told apart from "not passed, keep the old
      // value").
      state = SymptomForm(
        region: form.region,
        painTypes: form.painTypes,
        triggers: form.triggers,
        painIntensity: form.painIntensity,
        relatedIntensities: form.relatedIntensities,
        notes: form.notes,
        bodyMapPoints: form.bodyMapPoints,
        submitting: false,
        failure: rejected,
        submittedDrafts: drafts,
        submittedPainIndex: painIndex,
      );
      return false;
    }

    // Success — never adopts the response (the created rows are not this
    // form's business; T20b's screen pops on `true`). Selections are left
    // exactly as they were, the `QuickCheckinController` precedent: the
    // controller is `autoDispose`, so the screen closing tears the whole
    // form down rather than this method resetting it.
    if (savedDay != null) _refreshDependents(savedDay);

    state = state.copyWith(submitting: false, clearSubmission: true);
    return true;
  }

  /// Tells the screens that already show [day] to re-fetch (S12, P4b-T20b).
  ///
  /// **Why this is here at all.** `SymptomsRepository.createBatch` invalidates
  /// the CACHE keys for every day it wrote, but an already-mounted
  /// `ref.watch`-based controller does not re-read its repository because a
  /// cache entry changed — it has to be invalidated itself. Without this the
  /// save succeeds and the user pops back to a dashboard, a day view or a
  /// calendar still rendering the pre-write day, with nothing on screen
  /// saying so. **This is invisible to any test that only asserts the POST**,
  /// which is why T20a's report flagged it as an open gap rather than
  /// closing it: the decision needs to know which SCREENS exist, and a
  /// headless unit has no business knowing that.
  ///
  /// It lives on the controller rather than on the screen for the same reason
  /// `QuickCheckinController._refreshDependents` does: the refresh belongs to
  /// the successful write, not to whatever widget happened to trigger it, and
  /// [day] is only knowable here — it is the value [submit] just read from
  /// [sessionTodayProvider] and handed to the repository.
  ///
  /// **What is refreshed, and under what guard:**
  ///
  ///  * **The dashboard, unconditionally.** It renders today's own pain/mood
  ///    and is where both routes to screen 12 start. [Ref.invalidate] never
  ///    CREATES a provider element, so this costs nothing when it is not
  ///    mounted.
  ///  * **The day-detail controller for [day], only if it already exists.**
  ///    `dayDetailControllerProvider` is an `autoDispose` FAMILY, and the
  ///    check is what stops this from building a controller — and firing its
  ///    two GETs — for a Cycle-tab screen nobody has opened. [Ref.exists] is
  ///    the one way to ask that WITHOUT creating one. Only that day's
  ///    controller is touched: the batch reached exactly one day, and
  ///    invalidating others would re-fetch days this write cannot have
  ///    changed.
  ///
  ///    **No `hasValue` half here, unlike the calendar below — deliberately.**
  ///    That half exists on screen 9 because `CycleCalendarController
  ///    .refresh()` falls back to `invalidateSelf()` when it has no value,
  ///    which snaps the visible month back to today. `DayDetailController`
  ///    has no `refresh()` and no such branch — it is one `build()` for one
  ///    fixed date — so the only tool is `invalidate`, and invalidating a
  ///    STILL-LOADING day view is strictly more correct than skipping it:
  ///    that in-flight read was issued before this write committed and would
  ///    otherwise land as pre-write data with nothing to correct it.
  ///  * **The cycle calendar, only if it already exists AND already has a
  ///    value** — screen 9's guard verbatim, for screen 9's reason: the same
  ///    `refresh()`, the same snap-back. A symptom changes that day's
  ///    `symptomCount` and therefore whether the cell draws a dot at all, so
  ///    an open calendar is genuinely out of date after this write.
  ///
  /// Fire-and-forget, like screen 9's: the calendar screen (if mounted) shows
  /// its own refresh treatment, and [submit] does not await it.
  void _refreshDependents(DateTime day) {
    ref.invalidate(dashboardControllerProvider);

    final dayDetail = dayDetailControllerProvider(day);
    if (ref.exists(dayDetail)) {
      ref.invalidate(dayDetail);
    }

    if (ref.exists(cycleCalendarControllerProvider)) {
      final calendarState = ref.read(cycleCalendarControllerProvider);
      if (calendarState.hasValue) {
        unawaited(ref.read(cycleCalendarControllerProvider.notifier).refresh());
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 12's controller. `autoDispose` — the form holds the user's own
/// unsent symptom answers (health data), the same house rule
/// `QuickCheckinController`/`GoalsController`/`ProfileController` already
/// follow: such state must not outlive the screen showing it.
final symptomFormControllerProvider =
    NotifierProvider.autoDispose<SymptomFormController, SymptomForm>(
      SymptomFormController.new,
    );
