// SymptomForm — screen 12's form state (P4b-T20a).
//
// TDD (RED first). This file covers the PURE half of `SymptomForm`: its
// defaults (R11), the save-block priority order (R7/R8), and the R9 error
// lookups — all of it constructible directly, with no `ProviderContainer`
// and no repository. The Notifier that DOES I/O (`SymptomFormController`,
// R12's `sessionTodayProvider` read, R9's retained-draft capture at submit
// time) has its own file, `symptom_form_controller_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A minimal, fully-explicit `SymptomEntryDraft` — every field named, the
/// same discipline `symptoms_repository_test.dart`'s own `_draft()` helper
/// uses, so a test that overrides one field cannot accidentally lean on
/// another's default.
SymptomEntryDraft _draft({
  String? symptomCode,
  int intensity = 5,
  String? region,
  String? side,
  List<String> painTypes = const <String>[],
  List<String> triggers = const <String>[],
  DateTime? occurredAt,
  String? notes,
}) {
  return SymptomEntryDraft(
    symptomCode: symptomCode,
    intensity: intensity,
    region: region,
    side: side,
    painTypes: painTypes,
    triggers: triggers,
    occurredAt: occurredAt,
    notes: notes,
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // R11 — the form starts empty
  // ---------------------------------------------------------------------------

  group('R11 — the default form is empty', () {
    test('nothing is selected, nothing is in flight, and the save is '
        'blocked with the empty-selection reason — the mockup\'s four '
        'pre-selected chips (including "intercourse") are a design '
        'fixture, never an initial state', () {
      const form = SymptomForm();

      expect(form.region, isNull);
      expect(form.painTypes, isEmpty);
      expect(form.triggers, isEmpty);
      expect(form.painIntensity, isNull);
      expect(form.relatedIntensities, isEmpty);
      expect(form.notes, isNull);
      expect(form.bodyMapPoints, isEmpty);
      expect(form.submitting, isFalse);
      expect(form.failure, isNull);
      expect(form.submittedDrafts, isNull);
      expect(form.submittedPainIndex, isNull);
      expect(form.canSubmit, isFalse);
      expect(form.blockReason, kSymptomNothingSelectedMessage);
    });
  });

  // ---------------------------------------------------------------------------
  // R7/R8 — the save-block reason, in priority order
  // ---------------------------------------------------------------------------

  group('R7/R8 — blockReason priority order', () {
    test('guard 1: nothing selected at all', () {
      const form = SymptomForm();
      expect(form.blockReason, kSymptomNothingSelectedMessage);
    });

    test('a selected body-map point alone is "something" — guard 1 does '
        'not fire', () {
      final form = SymptomForm(bodyMapPoints: [_draft(intensity: 4)]);
      expect(form.blockReason, isNot(kSymptomNothingSelectedMessage));
    });

    test('guard 2: a selected RELATED chip with no intensity blocks, even '
        'alone', () {
      const form = SymptomForm(relatedIntensities: {'bloating': null});
      expect(form.blockReason, kSymptomMissingIntensityMessage);
    });

    test('guard 2: ONE unset chip among several SET ones still blocks — '
        'this must be an ANY check, not an EVERY one', () {
      const form = SymptomForm(
        relatedIntensities: {'bloating': 5, 'nausea': null, 'fatigue': 2},
      );
      expect(form.blockReason, kSymptomMissingIntensityMessage);
    });

    test('guard 2 beats guard 3 when both apply — an unset RELATED chip '
        'AND a classification chip with no pain level', () {
      const form = SymptomForm(
        region: 'lower_abdomen',
        relatedIntensities: {'bloating': null},
      );
      expect(form.blockReason, kSymptomMissingIntensityMessage);
    });

    test('guard 3: a LOCATION chip with no pain level blocks', () {
      const form = SymptomForm(region: 'pelvis');
      expect(form.blockReason, kSymptomMissingPainLevelMessage);
    });

    test('guard 3: a TYPE chip with no pain level blocks', () {
      const form = SymptomForm(painTypes: {'cramping'});
      expect(form.blockReason, kSymptomMissingPainLevelMessage);
    });

    test('guard 3: a TRIGGERS chip with no pain level blocks', () {
      const form = SymptomForm(triggers: {'stress'});
      expect(form.blockReason, kSymptomMissingPainLevelMessage);
    });

    test('guard 3 does not fire once a pain level IS set', () {
      const form = SymptomForm(region: 'pelvis', painIntensity: 3);
      expect(form.blockReason, isNull);
    });

    test('guard 4: over the cap blocks, with the server\'s own string '
        '(reached here via body-map points, since screen 12 alone cannot '
        'reach 51)', () {
      final form = SymptomForm(
        painIntensity: 5,
        bodyMapPoints: List.generate(50, (_) => _draft(intensity: 1)),
      );
      expect(form.blockReason, kSymptomBatchOverCapMessage);
      expect(
        form.blockReason,
        'a request may contain at most '
        '${SymptomsRepository.maxBatchEntries} entries',
      );
    });

    test('exactly the cap (50) is allowed — the boundary is inclusive '
        '("at most 50", not "fewer than 50")', () {
      final form = SymptomForm(
        painIntensity: 5,
        bodyMapPoints: List.generate(49, (_) => _draft(intensity: 1)),
      );
      expect(form.blockReason, isNull);
      expect(form.canSubmit, isTrue);
    });

    test('51 is blocked, one past the inclusive boundary', () {
      final form = SymptomForm(
        painIntensity: 5,
        bodyMapPoints: List.generate(50, (_) => _draft(intensity: 1)),
      );
      expect(form.blockReason, kSymptomBatchOverCapMessage);
    });
  });

  // ---------------------------------------------------------------------------
  // Valid combinations — canSubmit true, no reason
  // ---------------------------------------------------------------------------

  group('valid combinations', () {
    test('a RELATED-only selection is valid (MinEntries = 1)', () {
      const form = SymptomForm(
        relatedIntensities: {'bloating': 5, 'nausea': 0},
      );
      expect(form.canSubmit, isTrue);
      expect(form.blockReason, isNull);
    });

    test('a pain-only selection is valid, with no classification at all', () {
      const form = SymptomForm(painIntensity: 7);
      expect(form.canSubmit, isTrue);
      expect(form.blockReason, isNull);
    });

    test('pain intensity 0 counts as SET, not as "nothing" (D-08)', () {
      const form = SymptomForm(painIntensity: 0);
      expect(form.canSubmit, isTrue);
      expect(form.blockReason, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // R9 — error binding against the retained submitted draft list
  // ---------------------------------------------------------------------------

  group('R9 — error binding', () {
    test('painRowError resolves via the retained pain index', () {
      final form = SymptomForm(
        painIntensity: 5,
        failure: const ValidationFailure(
          fields: {
            'entries[0].intensity': ['must be between 0 and 10'],
          },
        ),
        submittedDrafts: [_draft(intensity: 5)],
        submittedPainIndex: 0,
      );

      expect(form.painRowError('intensity'), 'must be between 0 and 10');
      expect(form.painRowError('region'), isNull);
    });

    test('painRowError is null when the submitted batch had no pain row', () {
      final form = SymptomForm(
        failure: const ValidationFailure(
          fields: {
            'entries[0].intensity': ['x'],
          },
        ),
        submittedDrafts: [_draft(symptomCode: 'bloating', intensity: 3)],
        // submittedPainIndex deliberately omitted (null) — no pain row.
      );

      expect(form.painRowError('intensity'), isNull);
    });

    test('relatedRowError resolves via the retained draft list, by code', () {
      final form = SymptomForm(
        relatedIntensities: {'bloating': 3, 'nausea': 11},
        failure: const ValidationFailure(
          fields: {
            'entries[1].intensity': ['must be between 0 and 10'],
          },
        ),
        submittedDrafts: [
          _draft(symptomCode: 'bloating', intensity: 3),
          _draft(symptomCode: 'nausea', intensity: 11),
        ],
      );

      expect(
        form.relatedRowError('nausea', 'intensity'),
        'must be between 0 and 10',
      );
      expect(form.relatedRowError('bloating', 'intensity'), isNull);
    });

    test('the retained draft list is used even when the LIVE selection has '
        'since changed — a shifted index must not attach a message to the '
        'wrong chip', () {
      // At submit time the batch was [bloating@0, nausea@1] and the server
      // rejected index 1 (nausea). Since then, the user deselected
      // 'bloating' — if this were recomputed from CURRENT
      // `relatedIntensities` (now just {'nausea': 11}), 'nausea' would rank
      // at index 0, not 1, and a naive re-derivation would either miss the
      // message or (worse) attach entries[1]'s message to whatever code
      // happens to occupy live index 1. The retained list must be searched
      // instead.
      final form = SymptomForm(
        relatedIntensities: {'nausea': 11}, // 'bloating' deselected since
        failure: const ValidationFailure(
          fields: {
            'entries[1].intensity': ['must be between 0 and 10'],
          },
        ),
        submittedDrafts: [
          _draft(symptomCode: 'bloating', intensity: 3),
          _draft(symptomCode: 'nausea', intensity: 11),
        ],
      );

      expect(
        form.relatedRowError('nausea', 'intensity'),
        'must be between 0 and 10',
      );
      expect(
        form.relatedRowError('bloating', 'intensity'),
        isNull,
        reason:
            "bloating's row (index 0) was never rejected — only "
            "nausea's (index 1) was",
      );
    });

    test('lookups are null without a ValidationFailure', () {
      final form = SymptomForm(
        submittedDrafts: [_draft(symptomCode: 'bloating', intensity: 3)],
        submittedPainIndex: null,
      );
      expect(form.relatedRowError('bloating', 'intensity'), isNull);
      expect(form.painRowError('intensity'), isNull);
    });

    test('lookups are null before any submit attempt', () {
      const form = SymptomForm();
      expect(form.relatedRowError('bloating', 'intensity'), isNull);
      expect(form.painRowError('intensity'), isNull);
    });

    test('relatedRowError is null for a code that was never in the '
        'submitted batch at all', () {
      final form = SymptomForm(
        failure: const ValidationFailure(
          fields: {
            'entries[0].intensity': ['x'],
          },
        ),
        submittedDrafts: [_draft(symptomCode: 'bloating', intensity: 3)],
      );
      expect(form.relatedRowError('nausea', 'intensity'), isNull);
    });
  });
}
