import 'package:flutter/foundation.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';

// ---------------------------------------------------------------------------
// SymptomForm — screen 12's form state (P4b-T20a)
// ---------------------------------------------------------------------------
//
// Two six-agent surveys of screen 12 (`.superpowers/sdd/lumen-build/
// survey-symptoms/`) found that every data-fabrication hazard on this screen
// lives in the ASSEMBLY logic, not the widget tree: a null intensity silently
// becoming `0`, a pain row the user never entered, a note attached to the
// wrong row, and the first index-to-chip error binding in this codebase.
// This class holds the twelve rulings (R1-R12) that close those hazards; the
// pure batch assembler that reads it lives in `symptom_batch_assembler.dart`,
// and the I/O-doing `Notifier` that drives it lives in
// `symptom_form_controller.dart` — three files, so "no ref, no I/O, no
// clock" is checkable by inspecting one small file's imports rather than
// auditing a ~1000-line screen diff (the T19b/T19c precedent, applied once
// more).
//
// Shape mirrors `QuickCheckinController`'s `QuickCheckinForm` (P4b-T18): a
// plain immutable value class, no prefill (R11), `submitting`/`failure` as
// their own fields. **No `touched` flags are added here.** Every field below
// was checked against T18's own defect class — "a flag that duplicates what
// nullability already says is noise, and a missing one is the T18 defect" —
// and none needed one:
//   - `region`/`painTypes`/`triggers`: a chip toggle's "cleared back to
//     nothing" and "never touched" are the SAME wire effect (no
//     classification), so nullability/emptiness alone is the whole signal.
//   - `painIntensity`: R1 already emits the pain row iff this is non-null;
//     there is no separate "touched, then cleared" state that needs to
//     behave differently from "never touched" the way `QuickCheckinForm`
//     needed for its two-field `canSubmit` OR. (`0` is still preserved
//     exactly — see [SymptomForm.hasPainRow]'s `!= null`, never a truthiness
//     check.)
//   - `relatedIntensities`: a `Map<String, int?>` where KEY PRESENCE is the
//     "touched"/"selected" signal (R5) and the VALUE is that chip's own
//     intensity, `null` until set. The map already carries the three states
//     a bare `Set<String>` + `Map<String, int>` pair could not: unselected
//     (no key), selected-unset (key, `null` value — R2 blocks the save on
//     this), selected-set (key, value, including `0`). A separate boolean
//     would duplicate what the key's presence already says.
//   - `notes`: free text has no false/absent conflation (unlike an `int`,
//     an empty string and "never typed" mean the identical nothing).

/// The server's own sentence for an empty selection, verbatim — mirrored
/// rather than round-tripped for the identical reason `goals_screen.dart`'s
/// `kGoalsEmptyMessage` is: the condition is fully knowable on the device.
///
/// **Authored, not ratified** (brief's own words) — flagged for PO
/// confirmation at phase exit, same as the three messages below.
const String kSymptomNothingSelectedMessage =
    'select a symptom or set a pain level';

/// R2's guard, surfaced as the reason a save is blocked: a selected RELATED
/// chip with no intensity yet.
const String kSymptomMissingIntensityMessage =
    'set an intensity for every selected symptom';

/// R1's coupling guard: LOCATION/TYPE/TRIGGERS chips describe the pain, and
/// have no carrier without a pain row.
const String kSymptomMissingPainLevelMessage =
    'set a pain level to save these pain details';

/// R-18's cap, in the server's own words
/// (`SymptomValidationMessages.MaxEntries`, `SymptomContracts.cs:161`) —
/// interpolating [SymptomsRepository.maxBatchEntries] (a compile-time
/// constant) rather than a second hard-coded `50`, so the two numbers cannot
/// drift apart.
const String kSymptomBatchOverCapMessage =
    'a request may contain at most '
    '${SymptomsRepository.maxBatchEntries} entries';

/// Screen 12's form state, headless: everything it renders and everything it
/// can send, with no widget attached.
@immutable
class SymptomForm {
  const SymptomForm({
    this.region,
    this.painTypes = const <String>{},
    this.triggers = const <String>{},
    this.painIntensity,
    this.relatedIntensities = const <String, int?>{},
    this.notes,
    this.bodyMapPoints = const <SymptomEntryDraft>[],
    this.submitting = false,
    this.failure,
    this.submittedDrafts,
    this.submittedPainIndex,
  });

  /// The single selected LOCATION chip, or `null`. Screen 12 draws no `side`
  /// (front/back) affordance, so there is no matching field here — the
  /// assembler always sends `side: null` for rows this file produces.
  final String? region;

  /// The selected TYPE chips.
  final Set<String> painTypes;

  /// The selected TRIGGERS chips.
  final Set<String> triggers;

  /// The pain row's own 0-10 intensity, or `null` for "not set". **`0` is a
  /// real datum (D-08)** — every read of this field below tests `!= null`,
  /// never truthiness. R1: the pain row is emitted iff this is non-null.
  final int? painIntensity;

  /// Selected RELATED symptom codes, keyed by code. **Key presence IS
  /// selection (R5)** — a code absent here was either never selected or was
  /// just deselected, which DISCARDS whatever intensity it held; re-selecting
  /// it starts over at `null`, never restoring a stale number. The mapped
  /// value is that code's own intensity: `null` for "selected, not set yet"
  /// (R2 blocks the save on this), otherwise the logged value including `0`.
  final Map<String, int?> relatedIntensities;

  /// One notes box per episode (R3) — attached to the batch's first entry by
  /// the assembler, never sent on every row.
  final String? notes;

  /// The T21 seam (R-15's body map, not yet built): already-assembled
  /// [SymptomEntryDraft]s in the SAME shape every other row in this file
  /// produces, so the assembler needs no conversion logic for them and this
  /// file needs no knowledge of screen 13's still-undesigned geometry. Empty
  /// until T21 exists; counted toward the R-18 cap like any other row.
  final List<SymptomEntryDraft> bodyMapPoints;

  /// Whether `POST /symptoms` is in flight. Every setter below refuses to
  /// mutate while this is true — the `QuickCheckinController`/
  /// `GoalsController` precedent (`goals_controller.dart:298`).
  final bool submitting;

  /// Why the last attempt failed. **Never cleared on failure itself** (R10)
  /// — only a fresh selection change or a new submit attempt clears it (see
  /// [SymptomFormController]'s `clearSubmission`).
  final Failure? failure;

  /// The EXACT drafts POSTed on the last failed attempt, retained beside
  /// [failure] so [relatedRowError] resolves a row by searching THIS list —
  /// never by recomputing where a code would rank in CURRENT
  /// [relatedIntensities] (R9). A live recomputation would silently point a
  /// message at the wrong chip if the selection changed between submit and
  /// the response; searching the retained list cannot do that, because the
  /// list itself does not change.
  final List<SymptomEntryDraft>? submittedDrafts;

  /// The zero-based index the pain row occupied in [submittedDrafts], or
  /// `null` if that batch had no pain row. **Stored explicitly, never
  /// searched for by content** — unlike RELATED rows, the pain row's own
  /// `symptomCode` is `null` (it asks the server for its `pain` default),
  /// and an opaque T21 body-map point could, in principle, ALSO carry a
  /// `null` `symptomCode`. Searching [submittedDrafts] for "the first
  /// `null`-coded row" would be ambiguous between the two; the assembler's
  /// own "pain row is always index 0 when present" invariant is instead
  /// captured once, by [SymptomFormController.submit], at the moment the
  /// batch is built.
  final int? submittedPainIndex;

  /// Whether a pain row would be emitted — R1's own condition, named once so
  /// [blockReason] and a caller both read it the same way.
  bool get hasPainRow => painIntensity != null;

  /// Whether any LOCATION/TYPE/TRIGGERS chip is selected — the classification
  /// data that, per R1, has no carrier without a pain row.
  bool get hasClassification =>
      region != null || painTypes.isNotEmpty || triggers.isNotEmpty;

  /// `1 pain + N related + M body-map points` — R-18's own count, computed
  /// without needing to run the assembler. A selected RELATED chip counts
  /// here even before its intensity is set (guard 2 already blocks that
  /// case, ahead of the cap check in [blockReason]'s priority order, so this
  /// count never needs to distinguish the two for correctness — but it
  /// SHOULD count the chip as "there", matching guard 1's own "is anything
  /// selected at all" question).
  int get totalEntryCount =>
      (hasPainRow ? 1 : 0) + relatedIntensities.length + bodyMapPoints.length;

  /// R8's single save-block reason, or `null` when the save may proceed —
  /// checked in the brief's own priority order. Each `if` below is one
  /// ruling; do not reorder them.
  String? get blockReason {
    // Guard 1 (R7) — truly nothing selected: no pain, no related chip, no
    // body-map point, AND no classification chip either (a lone
    // classification chip is "something", handled by guard 3 below, not
    // this one).
    if (totalEntryCount == 0 && !hasClassification) {
      return kSymptomNothingSelectedMessage;
    }
    // Guard 2 (R2) — a selected RELATED chip with no intensity yet. Checked
    // ahead of guard 3 per R8's stated order, even if both would apply.
    if (relatedIntensities.values.any((intensity) => intensity == null)) {
      return kSymptomMissingIntensityMessage;
    }
    // Guard 3 (R1's coupling) — LOCATION/TYPE/TRIGGERS describe THE PAIN;
    // with no pain row they have no carrier.
    if (hasClassification && !hasPainRow) {
      return kSymptomMissingPainLevelMessage;
    }
    // Guard 4 (R-18) — the assembly-time cap, inclusive: 50 is allowed, 51
    // is not ("a request may contain at most 50 entries" — the SERVER's own
    // wording is "at most", not "fewer than").
    if (totalEntryCount > SymptomsRepository.maxBatchEntries) {
      return kSymptomBatchOverCapMessage;
    }
    return null;
  }

  /// Whether the CTA may fire — R7's empty-batch guard and every other
  /// guard above, collapsed to one boolean. Never satisfied by defaulting
  /// any field; only by [blockReason] finding nothing to object to.
  bool get canSubmit => blockReason == null;

  /// The message the server rejected the pain row's [field] with, resolved
  /// via [submittedPainIndex] — never by assuming the pain row is still at
  /// index 0 of the CURRENT (possibly rebuilt) batch. `null` when there was
  /// no [ValidationFailure], no submitted pain row, or no rejection for
  /// [field].
  String? painRowError(String field) {
    final rejected = failure;
    final index = submittedPainIndex;
    if (rejected is! ValidationFailure || index == null) return null;
    return rejected.messageFor(ValidationFailure.path('entries', index, field));
  }

  /// The message the server rejected the RELATED row for [code]'s [field]
  /// with, resolved by searching [submittedDrafts] for the row whose
  /// `symptomCode` is [code] — the retained list, not live
  /// [relatedIntensities] (R9). `null` under the same three conditions as
  /// [painRowError], plus a fourth: [code] was not in the submitted batch at
  /// all.
  String? relatedRowError(String code, String field) {
    final rejected = failure;
    final drafts = submittedDrafts;
    if (rejected is! ValidationFailure || drafts == null) return null;
    final index = drafts.indexWhere((draft) => draft.symptomCode == code);
    if (index < 0) return null;
    return rejected.messageFor(ValidationFailure.path('entries', index, field));
  }

  /// **Deliberately does not accept [failure]/[submittedDrafts]/
  /// [submittedPainIndex] as parameters.** Those three are only ever set
  /// TOGETHER, as one atomic "this is what got rejected" snapshot
  /// (`SymptomFormController.submit`'s failure branch constructs a fresh
  /// [SymptomForm] directly for that reason) — a generic `x ?? this.x`
  /// three-parameter version of this method would have the exact "0 vs
  /// null" hazard this whole file exists to avoid: passing
  /// `submittedPainIndex: null` for a RELATED-only retry could never be
  /// told apart from "not passed, keep the old (possibly stale, non-null)
  /// value". [clearSubmission] is the only way this method touches any of
  /// the three, and it always sets all three to `null` together.
  SymptomForm copyWith({
    String? region,
    bool clearRegion = false,
    Set<String>? painTypes,
    Set<String>? triggers,
    int? painIntensity,
    bool clearPainIntensity = false,
    Map<String, int?>? relatedIntensities,
    String? notes,
    bool clearNotes = false,
    List<SymptomEntryDraft>? bodyMapPoints,
    bool? submitting,
    bool clearSubmission = false,
  }) {
    return SymptomForm(
      region: clearRegion ? null : (region ?? this.region),
      painTypes: painTypes ?? this.painTypes,
      triggers: triggers ?? this.triggers,
      painIntensity: clearPainIntensity
          ? null
          : (painIntensity ?? this.painIntensity),
      relatedIntensities: relatedIntensities ?? this.relatedIntensities,
      notes: clearNotes ? null : (notes ?? this.notes),
      bodyMapPoints: bodyMapPoints ?? this.bodyMapPoints,
      submitting: submitting ?? this.submitting,
      failure: clearSubmission ? null : failure,
      submittedDrafts: clearSubmission ? null : submittedDrafts,
      submittedPainIndex: clearSubmission ? null : submittedPainIndex,
    );
  }
}
