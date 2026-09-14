import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';

// ---------------------------------------------------------------------------
// assembleSymptomBatch — screen 12's pure batch assembler (P4b-T20a)
// ---------------------------------------------------------------------------
//
// `List<SymptomEntryDraft>` out, [SymptomForm] in. **No `ref`, no I/O, no
// clock** — this is the unit the T20/T20a split exists to make reviewable in
// isolation, so it stays a plain top-level function with no side channel a
// future edit could quietly introduce.
//
// Callers must check `form.blockReason` first — this function does not
// re-derive R7/R8's guards, and a caller that skips that check gets whatever
// this function's OWN rules produce for an otherwise-blocked state (see the
// "R1 — no carrier" branch below, which is exactly that case handled
// defensively rather than left to fabricate something).
List<SymptomEntryDraft> assembleSymptomBatch(SymptomForm form) {
  final drafts = <SymptomEntryDraft>[];

  // R1 — the pain row is emitted IFF a pain intensity was set. LOCATION/
  // TYPE/TRIGGERS are read ONLY inside this branch: with no pain row they
  // describe nothing on the wire (R1's "no carrier" ruling) and are silently
  // absent from the batch — `SymptomForm.blockReason` is what actually stops
  // the user from reaching this state via the CTA; this function's job is
  // only to never invent a row for data that has nowhere to go.
  final painIntensity = form.painIntensity;
  if (painIntensity != null) {
    drafts.add(
      SymptomEntryDraft(
        symptomCode: null, // server default "pain" (SymptomService.cs:413)
        intensity: painIntensity, // never `?? 0` — R2, and non-nullable here
        region: form.region,
        // Screen 12 draws no front/back control at all — `side` has no
        // selection to read, so this is always an explicit null asking for
        // the server's "not classified" default, never a guess.
        side: null,
        painTypes: _inFrozenOrder(form.painTypes, kPainTypeLabels.keys),
        triggers: _inFrozenOrder(form.triggers, kTriggerLabels.keys),
        // R12 — screen 12 draws no date affordance either, so every entry's
        // `occurredAt` is null; `SymptomFormController.submit` supplies
        // `fallbackDay` for CACHE INVALIDATION only, never onto the wire.
        occurredAt: null,
      ),
    );
  }

  // R4 — RELATED rows in FROZEN vocabulary order (kSymptomCodeLabels'
  // declaration order), never the order the chips were tapped. Iterating the
  // VOCABULARY (not `form.relatedIntensities.keys`, which is
  // insertion/selection order) is what makes this true; do not swap the
  // iteration source.
  for (final code in kSymptomCodeLabels.keys) {
    if (!form.relatedIntensities.containsKey(code)) continue;
    final intensity = form.relatedIntensities[code];
    // R2 — a selected chip with no intensity yet is SKIPPED here, never
    // defaulted. `SymptomEntryDraft.intensity` is non-nullable `int`, so
    // there is no wire representation for "selected, unset" at all; the
    // only two honest choices are "block the save" (SymptomForm.blockReason,
    // R2's actual enforcement point) and "omit the row" (here). `?? 0` would
    // silently promote "not recorded" into a logged zero.
    if (intensity == null) continue;
    drafts.add(
      SymptomEntryDraft(
        symptomCode: code,
        intensity: intensity,
        // R1 — RELATED rows carry ONLY symptomCode + intensity; they never
        // inherit the pain row's own region/painTypes/triggers.
        region: null,
        side: null,
        occurredAt: null,
      ),
    );
  }

  // The T21 seam: already-built SymptomEntryDrafts, appended after the
  // RELATED rows and otherwise untouched (they carry their own region/side/
  // intensity from screen 13's own, still-undesigned, assembly). Empty until
  // T21 ships.
  drafts.addAll(form.bodyMapPoints);

  // R3 — one notes box per episode, attached to the batch's FIRST entry
  // (whichever row that turns out to be: the pain row when one exists, else
  // the first RELATED row, else the first body-map point). A single
  // reconstruction step here — rather than deciding per-row at construction
  // time above — means this rule has exactly one place to read, and exactly
  // one place a future edit could move it to the wrong entry (the mutation
  // round's own target).
  return _withFirstEntryNotes(drafts, form.notes);
}

/// [selected], in the order [vocabularyOrder] declares them — never
/// insertion order. Used for a row's OWN `painTypes`/`triggers` arrays, the
/// same "do not let tap sequence leak into the wire" principle R4 states for
/// whole ROWS, extended here to the elements within one row's arrays (a
/// judgment call beyond R4's literal text — see the task report).
List<String> _inFrozenOrder(
  Set<String> selected,
  Iterable<String> vocabularyOrder,
) => [
  for (final code in vocabularyOrder)
    if (selected.contains(code)) code,
];

/// Attaches [notes] to `drafts[0]` — see R3 above. Returns an unmodifiable
/// copy either way, so a caller can never come to depend on the input list
/// being reused.
List<SymptomEntryDraft> _withFirstEntryNotes(
  List<SymptomEntryDraft> drafts,
  String? notes,
) {
  final hasNotes = notes != null && notes.isNotEmpty;
  if (!hasNotes || drafts.isEmpty) {
    return List.unmodifiable(drafts);
  }
  final result = List<SymptomEntryDraft>.of(drafts);
  result[0] = _copyWithNotes(result[0], notes);
  return List.unmodifiable(result);
}

/// [SymptomEntryDraft] has no `copyWith` of its own (T19 left it a plain
/// `const`-constructible value with no reason to grow one for a single
/// internal caller) — this rebuilds all eight fields explicitly rather than
/// add one to the shared T19 type for this file's sole use.
SymptomEntryDraft _copyWithNotes(SymptomEntryDraft draft, String notes) {
  return SymptomEntryDraft(
    symptomCode: draft.symptomCode,
    intensity: draft.intensity,
    region: draft.region,
    side: draft.side,
    painTypes: draft.painTypes,
    triggers: draft.triggers,
    occurredAt: draft.occurredAt,
    notes: notes,
  );
}
