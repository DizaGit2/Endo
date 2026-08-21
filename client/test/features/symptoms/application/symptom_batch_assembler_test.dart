// assembleSymptomBatch — screen 12's pure batch assembler (P4b-T20a).
//
// TDD (RED first). This is the unit the T20/T20a split exists to make
// reviewable: `List<SymptomEntryDraft>` out, `SymptomForm` in, no `ref`, no
// I/O, no clock. Every group below is named after the ruling it pins.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/symptoms/application/symptom_batch_assembler.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';

/// A minimal, fully-explicit body-map-point stand-in — T21 has not shipped,
/// so this is only ever an OPAQUE, already-built [SymptomEntryDraft] passed
/// straight through, never inspected or reconstructed by the assembler
/// except when it happens to land at index 0 for the notes attachment (R3).
SymptomEntryDraft _bodyMapPoint({
  String? region = 'legs',
  String? side = 'front',
  int intensity = 6,
}) {
  return SymptomEntryDraft(
    symptomCode: null,
    intensity: intensity,
    region: region,
    side: side,
    occurredAt: null,
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // R1 — the pain row is optional, and classification has no other carrier
  // ---------------------------------------------------------------------------

  group('R1 — the pain row is optional', () {
    test('emits a pain row when a pain intensity is set', () {
      const form = SymptomForm(painIntensity: 6);
      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(1));
      expect(batch.single.symptomCode, isNull);
      expect(batch.single.intensity, 6);
    });

    test('emits NO pain row when the pain intensity is null', () {
      const form = SymptomForm(relatedIntensities: {'bloating': 4});
      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(1));
      expect(
        batch.every((e) => e.symptomCode != null),
        isTrue,
        reason:
            'the only row must be the RELATED one, not a fabricated '
            'pain row',
      );
    });

    test('LOCATION/TYPE/TRIGGERS selected with no pain intensity contribute '
        'NOTHING to the batch — they have no carrier without a pain row', () {
      const form = SymptomForm(
        region: 'pelvis',
        painTypes: {'cramping'},
        triggers: {'stress'},
      );
      final batch = assembleSymptomBatch(form);

      expect(
        batch,
        isEmpty,
        reason:
            'this state is blocked by SymptomForm.blockReason before a '
            'screen would ever call the assembler on it; the assembler '
            'itself must still never invent a carrier for it',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // R2 — never fabricate an intensity
  // ---------------------------------------------------------------------------

  group('R2 — never default a null intensity to 0', () {
    test('pain intensity 0 is emitted as a real datum, never skipped', () {
      const form = SymptomForm(painIntensity: 0);
      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(1));
      expect(batch.single.intensity, 0);
    });

    test('a selected RELATED chip with a null intensity is SKIPPED — no '
        'row, never `?? 0`', () {
      const form = SymptomForm(
        relatedIntensities: {'bloating': null, 'nausea': 4},
      );
      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(1));
      expect(batch.single.symptomCode, 'nausea');
      expect(batch.single.intensity, 4);
    });

    test('RELATED intensity 0 is emitted as a real datum too', () {
      const form = SymptomForm(relatedIntensities: {'bloating': 0});
      final batch = assembleSymptomBatch(form);

      expect(batch.single.intensity, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // R4 — RELATED rows in frozen vocabulary order
  // ---------------------------------------------------------------------------

  group('R4 — RELATED rows in frozen vocabulary order', () {
    test('emitted in kSymptomCodeLabels order, NOT the order the chips were '
        'tapped', () {
      // 'brain_fog' is declared far AFTER 'bloating' in kSymptomCodeLabels,
      // but is inserted into the map first here.
      const form = SymptomForm(
        relatedIntensities: {'brain_fog': 3, 'bloating': 5},
      );
      final batch = assembleSymptomBatch(form);

      expect(batch.map((e) => e.symptomCode).toList(), <String>[
        'bloating',
        'brain_fog',
      ]);
    });

    test('three codes, selected in reverse-frozen order, still emit '
        'forward', () {
      const form = SymptomForm(
        relatedIntensities: {'acne': 1, 'fatigue': 2, 'bloating': 3},
      );
      final batch = assembleSymptomBatch(form);

      expect(batch.map((e) => e.symptomCode).toList(), <String>[
        'bloating',
        'fatigue',
        'acne',
      ]);
    });
  });

  // ---------------------------------------------------------------------------
  // R3 — one notes box, attached to the batch's FIRST entry
  // ---------------------------------------------------------------------------

  group('R3 — notes attach to the batch\'s first entry', () {
    test('pain-first batch: notes land on the pain row, not the RELATED '
        'row', () {
      const form = SymptomForm(
        painIntensity: 5,
        relatedIntensities: {'bloating': 3},
        notes: 'worse after lunch',
      );
      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(2));
      expect(batch[0].symptomCode, isNull); // the pain row
      expect(batch[0].notes, 'worse after lunch');
      expect(batch[1].symptomCode, 'bloating');
      expect(
        batch[1].notes,
        isNull,
        reason:
            'attaching the note to every row would multiply it into N '
            'encrypted copies',
      );
    });

    test('RELATED-only batch: notes land on the first RELATED row (frozen '
        'order), since there is no pain row to carry it', () {
      const form = SymptomForm(
        relatedIntensities: {'nausea': 2, 'bloating': 3},
        notes: 'no pain today, just nausea',
      );
      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(2));
      expect(
        batch[0].symptomCode,
        'bloating',
        reason: 'frozen order puts bloating before nausea',
      );
      expect(batch[0].notes, 'no pain today, just nausea');
      expect(batch[1].notes, isNull);
    });

    test('empty notes attach nothing (not an empty string on the wire)', () {
      const form = SymptomForm(painIntensity: 5, notes: '');
      final batch = assembleSymptomBatch(form);
      expect(batch.single.notes, isNull);
    });

    test('null notes attach nothing', () {
      const form = SymptomForm(painIntensity: 5);
      final batch = assembleSymptomBatch(form);
      expect(batch.single.notes, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Row shape — every one of the eight SymptomEntryDraft fields, per row
  // ---------------------------------------------------------------------------

  group('row shape — every field asserted', () {
    test('the pain row: symptomCode null (server default "pain"), region/'
        'painTypes/triggers from the form, side ALWAYS null (no affordance '
        'on this screen), occurredAt ALWAYS null (R12 — no date affordance '
        'either)', () {
      const form = SymptomForm(
        painIntensity: 7,
        region: 'pelvis',
        painTypes: {'sharp', 'cramping'}, // inserted out of frozen order
        triggers: {'stress'},
      );
      final row = assembleSymptomBatch(form).single;

      expect(row.symptomCode, isNull);
      expect(row.intensity, 7);
      expect(row.region, 'pelvis');
      expect(row.side, isNull);
      expect(row.painTypes, <String>[
        'cramping',
        'sharp',
      ], reason: 'frozen kPainTypeLabels order, not insertion order');
      expect(row.triggers, <String>['stress']);
      expect(row.occurredAt, isNull);
      expect(row.notes, isNull);
    });

    test('a RELATED row carries ONLY symptomCode + intensity — region, '
        'side, painTypes, triggers, occurredAt, notes are all null/empty, '
        'never inherited from the pain row\'s own classification', () {
      const form = SymptomForm(
        region: 'pelvis', // must NOT leak onto the related row
        painTypes: {'cramping'}, // must NOT leak
        triggers: {'stress'}, // must NOT leak
        painIntensity: 5,
        relatedIntensities: {'bloating': 4},
      );
      final batch = assembleSymptomBatch(form);
      final relatedRow = batch.firstWhere((e) => e.symptomCode == 'bloating');

      expect(relatedRow.intensity, 4);
      expect(relatedRow.region, isNull);
      expect(relatedRow.side, isNull);
      expect(relatedRow.painTypes, isEmpty);
      expect(relatedRow.triggers, isEmpty);
      expect(relatedRow.occurredAt, isNull);
      expect(relatedRow.notes, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Body-map seam (T21 has not shipped — empty until then)
  // ---------------------------------------------------------------------------

  group('body-map seam', () {
    test('body-map points are appended after the RELATED rows, passed '
        'through UNCHANGED (the exact same instance) when not first', () {
      final point = _bodyMapPoint();
      final form = SymptomForm(
        relatedIntensities: const {'bloating': 3},
        bodyMapPoints: [point],
      );
      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(2));
      expect(batch[0].symptomCode, 'bloating');
      expect(
        batch[1],
        same(point),
        reason:
            'the assembler has no conversion logic for an opaque T21 '
            'point; it must not rebuild it unless notes attach to it',
      );
    });

    test('body-map points count toward the assembled length', () {
      final form = SymptomForm(
        painIntensity: 5,
        bodyMapPoints: [_bodyMapPoint(), _bodyMapPoint()],
      );
      expect(assembleSymptomBatch(form), hasLength(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Valid combinations
  // ---------------------------------------------------------------------------

  group('valid combinations', () {
    test('a RELATED-only batch assembles and is valid', () {
      const form = SymptomForm(
        relatedIntensities: {'bloating': 5, 'fatigue': 2},
      );
      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(2));
      expect(
        batch.length,
        greaterThanOrEqualTo(SymptomsRepository.minBatchEntries),
      );
    });

    test('a pain-only batch assembles and is valid', () {
      const form = SymptomForm(painIntensity: 8);
      expect(assembleSymptomBatch(form), hasLength(1));
    });
  });
}
