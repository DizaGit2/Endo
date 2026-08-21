import 'package:flutter/foundation.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';

// ---------------------------------------------------------------------------
// BodyMapSelection — screen 13's selection model (P4b-T21a)
// ---------------------------------------------------------------------------
//
// Screen 13 marks WHERE it hurts, and every mark becomes a row in the same
// all-or-nothing `POST /symptoms` batch screen 12 owns (R-11). The T21a/T21b
// split puts every data-integrity decision here — a pure function of a
// `Map<String, int?>` — rather than inside a ~1,200-line screen diff, exactly
// as the T20a/T20 split did for screen 12. **No `ref`, no I/O, no clock, no
// widget**: this file imports `foundation` for `@immutable` and nothing from
// `material`, so "headless" is checkable by reading three import lines.
//
// SHAPE. `Map<String, int?>` keyed by region code, mirroring
// `SymptomForm.relatedIntensities` (`symptom_form.dart:109-115`) FIELD FOR
// FIELD: key presence IS placement, `null` is "placed, not rated yet", and
// deselecting DISCARDS the intensity rather than remembering it. The same
// problem in the same feature gets the same idiom — a second one would leave
// a reader to work out whether the difference meant something.
//
// **Deliberately NOT a `BodyMapPoint` value class.** A class with
// `operator==` over a subset of its fields makes two "equal" points carrying
// different intensities possible, and then every set operation has a silent
// winner. The map makes the identity question disappear: one key per region,
// and the region IS the identity, because with `side` cut by R-21 a point's
// entire wire contribution is `region` + `intensity`.

/// The reason screen 13 blocks its own CTA: a placed region nobody has rated.
///
/// Screen 13 owns this reason ALONE. `SymptomForm.blockReason`'s guard 2
/// (`symptom_form.dart:190-193`) inspects only `relatedIntensities`, so it can
/// never see an unrated body-map point — by the time a point reaches
/// `SymptomForm.bodyMapPoints` it is already a `SymptomEntryDraft`, whose
/// `intensity` is a non-nullable `int` with no representation for "unrated" at
/// all. This is the fifth message in the set that begins at
/// `symptom_form.dart:53`, written in that set's register: smallest possible
/// claim, sentence case, no clinical vocabulary.
///
/// **Authored, not ratified** — flagged for PO confirmation at phase exit,
/// like the four it joins.
const String kBodyMapMissingIntensityMessage =
    'set an intensity for every placed point';

/// Screen 13's placed points: which regions are marked, and how each one is
/// rated.
@immutable
class BodyMapSelection {
  const BodyMapSelection({this.intensities = const <String, int?>{}});

  /// Placed regions keyed by ratified region code. **Key presence IS
  /// placement (R1)**; the mapped value is that region's own 0-10 intensity
  /// (D-08), `null` for "placed, not rated yet" — the state [blockReason]
  /// objects to and [toDrafts] omits.
  ///
  /// Every map this class hands out is unmodifiable; a caller that mutates one
  /// it built itself and passed to the constructor gets what it deserves, the
  /// same contract `SymptomForm` carries.
  final Map<String, int?> intensities;

  /// Whether [region] is placed — named, so a caller never has to decide what
  /// a `null` from `intensities[region]` meant. `intensities[region] == null`
  /// is TRUE for both "not placed" and "placed, not rated", which is precisely
  /// the conflation this getter exists to keep out of the widget tree.
  bool isPlaced(String region) => intensities.containsKey(region);

  /// Placed regions in `kRegionLabels` DECLARATION order (R7) — never tap
  /// order. [toDrafts] emits through this getter and screen 13's stacked
  /// intensity blocks render through it, so the order exists exactly once and
  /// cannot drift between what the user sees and what the wire receives.
  ///
  /// Derived from `kRegionLabels.keys`, never from a second hard-coded list:
  /// the frozen vocabulary is append-only, and a copy of its order is a drift
  /// waiting to happen.
  List<String> get placedRegions => <String>[
    for (final region in kRegionLabels.keys)
      if (intensities.containsKey(region)) region,
  ];

  /// Distinct placed regions, rated or not — the mockup's own "N points
  /// placed" counter.
  ///
  /// Derived from [placedRegions], never from `intensities.length`. For every
  /// ratified code the two are identical, so this changes no reachable
  /// behaviour — it removes a divergence. [toggle] refuses an unratified
  /// code, but the constructor is public, and a key outside `kRegionLabels`
  /// counted raw would be a phantom point: shown in the counter, never
  /// emitted by [toDrafts] (which iterates [placedRegions]), and not
  /// removable by [toggle], whose vocabulary guard returns `this`. Counting
  /// through the vocabulary makes the counter and the payload agree
  /// structurally instead of by the caller's good behaviour.
  ///
  /// [blockReason] iterates [placedRegions] for the same reason, so the
  /// counter, the block and the payload share ONE definition of "placed" —
  /// the vocabulary's. A key outside it is counted nowhere, blocks nothing and
  /// reaches the wire nowhere, without any caller having to behave.
  int get pointCount => placedRegions.length;

  /// Why screen 13 may not hand its points back, or `null` when it may.
  ///
  /// An EMPTY body map is not an error: a user who placed nothing and left has
  /// simply logged nothing, and screen 12 owns the empty-batch guard
  /// (`kSymptomNothingSelectedMessage`) for the batch as a whole. The only
  /// thing this model can object to is a placed region with no intensity —
  /// see R8 and [toDrafts].
  ///
  /// Reads through [placedRegions], never `intensities.values`. For every
  /// ratified code the two are identical; what the vocabulary walk removes is
  /// a key OUTSIDE `kRegionLabels` mapped to `null`, reachable through the
  /// public constructor, which read raw would be a permanent [canApply]
  /// `false` — nothing on screen to rate ([placedRegions] and [toDrafts] omit
  /// it) and no way to take it back ([toggle] refuses the code). Blocking only
  /// on points the user can actually see is the same hardening [pointCount]
  /// makes, on the same map.
  String? get blockReason {
    for (final region in placedRegions) {
      // `== null`, never a falsiness test: `0` is a real logged intensity
      // (D-08), permanently indistinguishable from a real "none today", and
      // v1 ships no edit and no delete.
      if (intensities[region] == null) return kBodyMapMissingIntensityMessage;
    }
    return null;
  }

  /// Whether the points may be handed back to screen 12 — [blockReason]
  /// collapsed to one boolean, the `SymptomForm.canSubmit` shape.
  bool get canApply => blockReason == null;

  /// Places [region] if it is absent, or REMOVES it — discarding its intensity
  /// — if it is present (R1).
  ///
  /// Re-placing a removed region starts over at `null`: a remembered intensity
  /// would silently re-log a number the user had already taken back.
  ///
  /// A [region] outside `kRegionLabels` is never placed. The frozen vocabulary
  /// is the only source of placeable regions and BOTH of screen 13's input
  /// paths draw from it (the hit-geometry table and the all-8 chip list), so
  /// an unratified code can only arrive from a typo. Refusing it at the door
  /// is the first of two guards, not the only one: [pointCount],
  /// [placedRegions], [blockReason] and [toDrafts] all read `kRegionLabels`,
  /// so a code that got past this door through the public constructor is
  /// counted nowhere, blocks nothing and is emitted nowhere either — see
  /// [pointCount]. The refusal is visible immediately in the UI (the chip
  /// simply does not select), so it is not a silent failure.
  BodyMapSelection toggle(String region) {
    if (!kRegionLabels.containsKey(region)) return this;
    final next = Map<String, int?>.of(intensities);
    // `containsKey`, never the value `remove` returns: that value is `null`
    // both for an absent key AND for a placed-but-unrated one, so branching on
    // it would toggle an unrated point in the wrong direction.
    if (next.containsKey(region)) {
      next.remove(region);
    } else {
      next[region] = null;
    }
    return BodyMapSelection(intensities: Map<String, int?>.unmodifiable(next));
  }

  /// Rates an already-placed [region], or — with a `null` [intensity] — takes
  /// its rating back, leaving the point placed and unrated.
  ///
  /// **A region that is not placed is a no-op** — the intensity affordance
  /// only exists underneath a placed point, so a call for an absent region is
  /// a caller bug, and inventing a placement here would log a location the
  /// user never marked. No bound is enforced on [intensity]: the ratified
  /// 0-10 scale is the server's to validate — `NormalizeIntensity`'s range
  /// check against `Symptom.IntensityScale`, `SymptomService.cs:466-472` —
  /// and this file states no clinical bound of its own.
  ///
  /// **[intensity] is `int?`, and the nullable half is not decoration**
  /// (widened at T21b, where it acquired its caller). `LumenIntensityScale`
  /// reports `ValueChanged<int?>` and hands back `null` when the user taps the
  /// stop that is already selected — the tap-to-clear gesture P4b-T18 added
  /// precisely because a mis-tap was otherwise permanent and this endpoint has
  /// no clear affordance. A non-nullable parameter here could not express that
  /// gesture at all, so screen 13 would have had to reach around this class to
  /// its public constructor to reproduce a state the class already models.
  /// `SymptomFormController.setRelatedIntensity` — the shipped sibling this
  /// whole class mirrors — already takes `int?` for the same reason.
  ///
  /// `null` here means "placed, not rated", exactly as it does in
  /// [intensities]: it is [blockReason]'s objection and [toDrafts]' omission,
  /// never a logged `0` (D-08).
  BodyMapSelection setIntensity(String region, int? intensity) {
    if (!intensities.containsKey(region)) return this;
    final next = Map<String, int?>.of(intensities);
    next[region] = intensity;
    return BodyMapSelection(intensities: Map<String, int?>.unmodifiable(next));
  }

  /// The placed points as request-boundary drafts, ready to be appended to
  /// `SymptomForm.bodyMapPoints` and passed through `assembleSymptomBatch`
  /// untouched.
  ///
  /// ONLY rated regions are emitted, in `kRegionLabels` declaration order.
  /// Every field a body-map row does not carry is set explicitly below, each
  /// against the ruling that decided it — the `SymptomEntryDraft` boundary
  /// makes forgetting one a compile error, and these comments make CHANGING
  /// one a decision.
  List<SymptomEntryDraft> toDrafts() {
    final drafts = <SymptomEntryDraft>[];
    for (final region in placedRegions) {
      final intensity = intensities[region];
      // R8 — an unrated placement is SKIPPED, never defaulted. `?? 0` here
      // would promote "marked, never rated" into a logged zero: D-08 makes 0
      // a real datum, permanently indistinguishable from a deliberate "none
      // today", and v1 has no edit and no delete to take it back with.
      // `blockReason` is what stops the user reaching this state; this line is
      // what makes fabricating a row impossible if they somehow do.
      if (intensity == null) continue;
      drafts.add(
        SymptomEntryDraft(
          // R4 — asks the server for its ratified `pain` default
          // (`SymptomService.cs:413-415`), matching the shipped pain row
          // (`symptom_batch_assembler.dart:32`). A RELATED code here would
          // make `SymptomForm.relatedRowError`'s content search
          // (`symptom_form.dart:235`) resolve a rejection to the wrong row.
          symptomCode: null,
          intensity: intensity,
          region: region,
          // R2 (plan R-21) — `side` is NEVER set, and this model has no
          // front/back concept at all: no field, no parameter, no enum. No
          // source anywhere assigns a region to a view, `side` is documented
          // as ANATOMICAL in three shipped sources, the app never renders it
          // back, v1 has neither edit nor delete, and a P6/P7 heatmap will
          // act on it — so drawing `lower_back` on an anterior figure would
          // be a clinical claim made in pixels. `null` is a ratified value
          // the server already defaults to (C-16 escalates the membership
          // question to the clinician).
          side: null,
          // R6 — `painTypes`/`triggers` describe THE PAIN ROW's qualities
          // (T20a's R1); a body-map row carries region and intensity only.
          // Left at their `const []` defaults, exactly as the assembler's own
          // RELATED rows are.
          // R3 — every entry's `occurredAt` is null, asking the server for
          // the batch's single `now`. `symptoms_repository.dart:281-291`
          // branches ambiguous-failure cache invalidation on precisely this
          // field and states that on the traffic this screen sends, EVERY
          // entry's `occurredAt` is null; a device clock here would also trip
          // `formatting_guard`'s device-clock rule and break the
          // single-instant property `ARCHITECTURE.md:166` relies on for
          // stable offset paging.
          occurredAt: null,
          // `notes` is deliberately NOT passed (R5). The assembler attaches
          // the episode's single note to `drafts[0]`
          // (`symptom_batch_assembler.dart:118`), which on a body-map-only
          // save IS one of these points — overwriting a `null` loses nothing,
          // which is why the assembler needs zero change. **Adding a
          // per-point note field here would make that overwrite silent data
          // loss**; the mockup draws no per-point notes affordance, so there
          // is nothing to add it for.
        ),
      );
    }
    return List<SymptomEntryDraft>.unmodifiable(drafts);
  }
}
