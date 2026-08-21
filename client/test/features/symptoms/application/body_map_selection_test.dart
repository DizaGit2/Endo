// BodyMapSelection — screen 13's headless selection model (P4b-T21a).
//
// TDD (RED first). Same split, and the same reason, as T20a: every
// data-integrity decision screen 13 makes lives here, as a pure function of a
// `Map<String, int?>`, so it can be reviewed and mutated without opening a
// ~1,200-line screen diff. No widgets, no painter, no route, no clock.
//
// Every group below is named after the ruling it pins.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/symptoms/application/body_map_selection.dart';
import 'package:lumen/features/symptoms/application/symptom_batch_assembler.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';

/// A tap order deliberately DIFFERENT from `kRegionLabels`' declaration order
/// (`lower_abdomen`, `pelvis`, `lower_back`, `legs`, …, `chest_shoulder`), so
/// every ordering assertion below can actually tell the two apart. A fixture
/// whose two candidate orders coincide is the assertion-that-cannot-fail this
/// phase keeps re-finding.
const List<String> kTapOrder = <String>[
  'chest_shoulder',
  'legs',
  'lower_abdomen',
];

/// [kTapOrder]'s regions, all rated, placed in that order.
BodyMapSelection _threeRated() {
  var selection = const BodyMapSelection();
  for (final region in kTapOrder) {
    selection = selection.toggle(region).setIntensity(region, 4);
  }
  return selection;
}

void main() {
  // -------------------------------------------------------------------------
  // R1 — key presence IS placement, and deselecting DISCARDS
  // -------------------------------------------------------------------------

  group('R1 — key presence is placement', () {
    test('toggle places a region with a null intensity', () {
      const empty = BodyMapSelection();
      final placed = empty.toggle('pelvis');

      expect(placed.intensities.containsKey('pelvis'), isTrue);
      expect(placed.intensities['pelvis'], isNull);
      expect(placed.isPlaced('pelvis'), isTrue);
      expect(placed.pointCount, 1);
      expect(empty.pointCount, 0, reason: 'the receiver is immutable');
    });

    test('re-toggling removes the region and DISCARDS its intensity', () {
      final rated = const BodyMapSelection()
          .toggle('pelvis')
          .setIntensity('pelvis', 7);
      expect(rated.intensities['pelvis'], 7);

      final removed = rated.toggle('pelvis');
      expect(removed.intensities.containsKey('pelvis'), isFalse);
      expect(removed.isPlaced('pelvis'), isFalse);
      expect(removed.pointCount, 0);

      final rePlaced = removed.toggle('pelvis');
      expect(rePlaced.intensities.containsKey('pelvis'), isTrue);
      expect(
        rePlaced.intensities['pelvis'],
        isNull,
        reason: 're-placing starts at null, never restoring the stale 7',
      );
    });

    test('toggling off an UNRATED region removes it too', () {
      // The mutation round's M7: an implementation that branches on what
      // `Map.remove` RETURNS cannot tell "absent" from "placed, unrated" —
      // both are `null` — and so re-places an unrated point instead of
      // removing it. The rated case above passes for that bug, because
      // `remove` hands back the real intensity; only an unrated round trip
      // separates the two outcomes.
      final placed = const BodyMapSelection().toggle('legs');
      expect(placed.intensities['legs'], isNull, reason: 'unrated by design');

      final removed = placed.toggle('legs');

      expect(removed.isPlaced('legs'), isFalse);
      expect(removed.intensities, isEmpty);
      expect(removed.pointCount, 0);
    });

    test('setIntensity on an absent region is a no-op', () {
      final result = const BodyMapSelection().setIntensity('pelvis', 4);

      expect(result.intensities, isEmpty);
      expect(result.pointCount, 0);
      expect(result.isPlaced('pelvis'), isFalse);
    });

    test('a code outside the frozen region vocabulary is never placed', () {
      // `unspecified` is deliberately absent from kRegionLabels and must never
      // be produced; a typo'd code must not become a phantom point at all.
      final result = const BodyMapSelection().toggle('unspecified');

      expect(result.intensities, isEmpty);
      expect(result.pointCount, 0);
      expect(result.toDrafts(), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // D-08 — 0 is a real logged datum, never an absence
  // -------------------------------------------------------------------------

  group('D-08 — 0 is a real intensity', () {
    test('0 survives setIntensity, blockReason and toDrafts', () {
      final selection = const BodyMapSelection()
          .toggle('pelvis')
          .setIntensity('pelvis', 0);

      expect(selection.intensities['pelvis'], 0);
      expect(selection.pointCount, 1);
      expect(selection.blockReason, isNull, reason: '0 is rated, not unrated');
      expect(selection.canApply, isTrue);

      final drafts = selection.toDrafts();
      expect(drafts, hasLength(1));
      expect(drafts.single.intensity, 0);
      expect(drafts.single.region, 'pelvis');
    });

    test('toggling a 0-rated region off discards the 0 like any value', () {
      final selection = const BodyMapSelection()
          .toggle('pelvis')
          .setIntensity('pelvis', 0)
          .toggle('pelvis')
          .toggle('pelvis');

      expect(selection.isPlaced('pelvis'), isTrue);
      expect(selection.intensities['pelvis'], isNull);
      expect(selection.toDrafts(), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // pointCount
  // -------------------------------------------------------------------------

  group('pointCount', () {
    test('counts distinct placed regions, rated or not', () {
      final selection = const BodyMapSelection()
          .toggle('pelvis')
          .toggle('legs')
          .setIntensity('legs', 3);

      expect(selection.pointCount, 2);
      expect(selection.toDrafts(), hasLength(1), reason: 'only legs is rated');
    });

    test('placing the same region twice is one point, then none', () {
      final once = const BodyMapSelection().toggle('legs');
      expect(once.pointCount, 1);
      expect(once.toggle('legs').pointCount, 0);
    });

    test('a key outside the frozen vocabulary is never counted', () {
      // `toggle` refuses an unratified code, but the constructor is public,
      // so the count reads `kRegionLabels` rather than trusting the caller.
      // Counting raw keys would make such a key a phantom point: visible in
      // the counter, absent from `placedRegions` and never on the wire.
      const phantomOnly = BodyMapSelection(
        intensities: <String, int?>{'unspecified': 3},
      );

      expect(phantomOnly.pointCount, 0);
      expect(phantomOnly.placedRegions, isEmpty);
      expect(phantomOnly.toDrafts(), isEmpty);

      const phantomBesideReal = BodyMapSelection(
        intensities: <String, int?>{'unspecified': 3, 'pelvis': 5},
      );

      expect(phantomBesideReal.pointCount, 1, reason: 'only pelvis counts');
      expect(phantomBesideReal.placedRegions, <String>['pelvis']);
      expect(
        phantomBesideReal.toDrafts().map((draft) => draft.region),
        <String>['pelvis'],
      );
    });
  });

  // -------------------------------------------------------------------------
  // R8/R9 — an unrated placement blocks, and is never a 0
  // -------------------------------------------------------------------------

  group('R8 — an unrated placement blocks the save', () {
    test('an empty body map is not an error', () {
      const empty = BodyMapSelection();

      expect(empty.blockReason, isNull);
      expect(empty.canApply, isTrue);
      expect(empty.toDrafts(), isEmpty);
    });

    test('blockReason is non-null while any placed region is unrated', () {
      final selection = const BodyMapSelection()
          .toggle('pelvis')
          .toggle('legs')
          .setIntensity('legs', 3);

      expect(selection.blockReason, kBodyMapMissingIntensityMessage);
      expect(selection.canApply, isFalse);
    });

    test('blockReason clears once every placed region is rated', () {
      final selection = const BodyMapSelection()
          .toggle('pelvis')
          .toggle('legs')
          .setIntensity('legs', 3)
          .setIntensity('pelvis', 0);

      expect(selection.blockReason, isNull);
      expect(selection.canApply, isTrue);
    });

    test('a key outside the frozen vocabulary never blocks the CTA', () {
      // The constructor is public, so a non-vocabulary key can arrive mapped
      // to `null`. Read from `intensities.values` raw, that is a PERMANENT
      // `canApply == false`: `placedRegions` and `toDrafts` omit the key so
      // there is nothing on screen to rate, and `toggle` refuses the code so
      // there is no way to take it back. The block walks the vocabulary for
      // the same reason the counter does.
      const phantomUnrated = BodyMapSelection(
        intensities: <String, int?>{'unspecified': null},
      );

      expect(phantomUnrated.blockReason, isNull);
      expect(phantomUnrated.canApply, isTrue);
      expect(phantomUnrated.pointCount, 0);
      expect(phantomUnrated.toDrafts(), isEmpty);

      // Guard against the opposite mutation — a block that never fires. A
      // REAL unrated placement beside the phantom must still block.
      const phantomBesideUnratedReal = BodyMapSelection(
        intensities: <String, int?>{'unspecified': null, 'pelvis': null},
      );

      expect(
        phantomBesideUnratedReal.blockReason,
        kBodyMapMissingIntensityMessage,
      );
      expect(phantomBesideUnratedReal.canApply, isFalse);
    });

    test('an unrated region is absent from toDrafts entirely, never a 0', () {
      final selection = const BodyMapSelection()
          .toggle('pelvis')
          .toggle('legs')
          .setIntensity('legs', 3);

      final drafts = selection.toDrafts();

      expect(drafts, hasLength(1));
      expect(drafts.single.region, 'legs');
      expect(drafts.single.intensity, 3);
      expect(drafts.map((draft) => draft.region), isNot(contains('pelvis')));
    });
  });

  // -------------------------------------------------------------------------
  // R7 — frozen declaration order, never tap order
  // -------------------------------------------------------------------------

  group('R7 — toDrafts emits in kRegionLabels declaration order', () {
    test('emitted order is the vocabulary order, not the tap order', () {
      final emitted = _threeRated()
          .toDrafts()
          .map((draft) => draft.region)
          .toList();
      final declared = kRegionLabels.keys
          .where(kTapOrder.contains)
          .toList(growable: false);

      expect(
        declared,
        isNot(equals(kTapOrder)),
        reason:
            'the fixture must distinguish the two orders, or the assertion '
            'below passes for a tap-ordered implementation too',
      );
      expect(emitted, hasLength(kTapOrder.length));
      expect(emitted, declared);
    });

    test('placedRegions is the same derivation, unrated ones included', () {
      final selection = _threeRated().toggle('pelvis');
      final declared = kRegionLabels.keys
          .where((region) => kTapOrder.contains(region) || region == 'pelvis')
          .toList(growable: false);

      expect(declared, isNot(equals(<String>[...kTapOrder, 'pelvis'])));
      expect(selection.placedRegions, declared);
      expect(selection.placedRegions, hasLength(4));
    });
  });

  // -------------------------------------------------------------------------
  // R2/R3/R4/R5/R6 — the fields a body-map draft never sets
  // -------------------------------------------------------------------------

  group('the fields a body-map draft never sets', () {
    test('R2 — every draft carries side: null', () {
      final drafts = _threeRated().toDrafts();

      expect(drafts, hasLength(3), reason: 'a loop over [] proves nothing');
      for (final draft in drafts) {
        expect(draft.side, isNull);
      }
    });

    test('R3 — every draft carries occurredAt: null', () {
      final drafts = _threeRated().toDrafts();

      expect(drafts, hasLength(3), reason: 'a loop over [] proves nothing');
      for (final draft in drafts) {
        expect(draft.occurredAt, isNull);
      }
    });

    test('R4 — every draft carries symptomCode: null', () {
      final drafts = _threeRated().toDrafts();

      expect(drafts, hasLength(3), reason: 'a loop over [] proves nothing');
      for (final draft in drafts) {
        expect(draft.symptomCode, isNull);
      }
    });

    test('R5 — every draft carries notes: null', () {
      final drafts = _threeRated().toDrafts();

      expect(drafts, hasLength(3), reason: 'a loop over [] proves nothing');
      for (final draft in drafts) {
        expect(draft.notes, isNull);
      }
    });

    test('R6 — painTypes and triggers are empty on every draft', () {
      final drafts = _threeRated().toDrafts();

      expect(drafts, hasLength(3), reason: 'a loop over [] proves nothing');
      for (final draft in drafts) {
        expect(draft.painTypes, isEmpty);
        expect(draft.triggers, isEmpty);
      }
    });

    test('a draft carries the region and the intensity it was given', () {
      final drafts = const BodyMapSelection()
          .toggle('legs')
          .setIntensity('legs', 9)
          .toDrafts();

      expect(drafts, hasLength(1));
      expect(drafts.single.region, 'legs');
      expect(drafts.single.intensity, 9);
    });
  });

  // -------------------------------------------------------------------------
  // R5 — proved through the REAL assembler, not restated
  // -------------------------------------------------------------------------

  group('R5 — the assembler needs zero change', () {
    test('the episode note lands on drafts[0] and clobbers nothing', () {
      final points = _threeRated().toDrafts();
      final form = SymptomForm(
        bodyMapPoints: points,
        notes: 'worse after sitting',
      );

      final batch = assembleSymptomBatch(form);

      expect(batch, hasLength(3), reason: 'no pain row, no related rows');
      expect(
        batch.map((draft) => draft.region),
        points.map((draft) => draft.region),
        reason: 'the assembler passes body-map points through untouched',
      );
      expect(
        points.first.notes,
        isNull,
        reason: 'the model itself never authors a note (R5)',
      );
      expect(batch.first.notes, 'worse after sitting');
      expect(batch.first.region, points.first.region);
      expect(batch.first.intensity, points.first.intensity);
      expect(batch.first.symptomCode, isNull);
      expect(batch.first.side, isNull);
      expect(batch.first.occurredAt, isNull);
      expect(batch.first.painTypes, isEmpty);
      expect(batch.first.triggers, isEmpty);
      expect(
        batch.skip(1).map((draft) => draft.notes),
        everyElement(isNull),
        reason: 'one note per episode, never one per row',
      );
    });

    test('the drafts count toward the batch cap like any other row', () {
      final form = SymptomForm(
        painIntensity: 5,
        bodyMapPoints: _threeRated().toDrafts(),
      );

      expect(form.totalEntryCount, 4);
      expect(assembleSymptomBatch(form), hasLength(4));
    });
  });

  // -------------------------------------------------------------------------
  // R9 — the block message
  // -------------------------------------------------------------------------

  group('R9 — the block message', () {
    test('is authored once, in the register of the existing four', () {
      expect(kBodyMapMissingIntensityMessage, isNotEmpty);
      expect(
        kBodyMapMissingIntensityMessage,
        isNot(equals(kSymptomMissingIntensityMessage)),
        reason: 'screen 13 owns a FIFTH reason, distinct from guard 2',
      );
      expect(
        kBodyMapMissingIntensityMessage.codeUnits,
        everyElement(lessThan(128)),
        reason: 'ASCII only, like every other message in this feature',
      );
      expect(
        kBodyMapMissingIntensityMessage.trim(),
        kBodyMapMissingIntensityMessage,
      );
    });
  });

  // -------------------------------------------------------------------------
  // The request boundary
  // -------------------------------------------------------------------------

  group('the request boundary', () {
    test('toDrafts produces the shared SymptomEntryDraft type', () {
      expect(_threeRated().toDrafts(), everyElement(isA<SymptomEntryDraft>()));
    });
  });
}
