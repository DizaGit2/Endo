import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
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
    try {
      // R12 — the server-confirmed "today", exactly as
      // `quick_checkin_controller.dart:204,212` reads it. `Date.toDateTime()`
      // gives LOCAL midnight carrying the server's civil fields — never
      // `.toUtc()` it (a same-value no-op in every test here, a real
      // off-by-one-day bug on a positive-offset device in production; see
      // `symptoms_repository.dart`'s own documented M-2 regression, and the
      // dedicated R12 test in `symptom_form_controller_test.dart`).
      final today = await ref.read(sessionTodayProvider.future);
      await ref
          .read(symptomsRepositoryProvider)
          .createBatch(entries: drafts, fallbackDay: today.toDateTime());
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
    state = state.copyWith(submitting: false, clearSubmission: true);
    return true;
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
