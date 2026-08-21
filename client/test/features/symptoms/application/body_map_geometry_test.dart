// Body-map region geometry — screen 13's hit table (P4b-T21a).
//
// TDD (RED first). The table is declared in the mockup's OWN 120x220 user
// space (`Screens/screen_13_body_map.html`, `viewBox="0 0 120 220"`), so every
// number below can be read against the SVG path it came from without
// arithmetic. `regionAt` is a pure top-level function: no painter, no widget,
// no zoom.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/symptoms/application/body_map_geometry.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';

/// A painted figure at exactly 1:1 with the mockup's user space, deliberately
/// placed at a NON-ZERO origin: a `regionAt` that forgot to subtract
/// `paintedFigure.topLeft` would still land inside the table (20,40 shifts a
/// chest probe into the abdomen zone), so this offset is what makes the
/// translation assertable instead of assumed.
const Rect kUnitFigure = Rect.fromLTWH(20, 40, 120, 220);

/// The same figure painted at 2x and at the origin — the scale half of the
/// mapping, which the 1:1 fixture above cannot see.
const Rect kDoubleFigure = Rect.fromLTWH(0, 0, 240, 440);

/// [userX], [userY] in mockup units, expressed as a tap inside [kUnitFigure].
Offset _unit(double userX, double userY) =>
    Offset(kUnitFigure.left + userX, kUnitFigure.top + userY);

/// The same point inside [kDoubleFigure].
Offset _double(double userX, double userY) => Offset(userX * 2, userY * 2);

void main() {
  // -------------------------------------------------------------------------
  // R10 — four zones, and four deliberate absences
  // -------------------------------------------------------------------------

  group('R10 — the table covers exactly four regions', () {
    test('the four ratified zones are present', () {
      expect(
        kBodyMapRegionZones.keys,
        unorderedEquals(<String>[
          'chest_shoulder',
          'lower_abdomen',
          'pelvis',
          'legs',
        ]),
      );
    });

    test('the four regions with no honest anterior projection are absent', () {
      for (final region in const <String>[
        'lower_back',
        'bladder',
        'vaginal',
        'bowel_rectal',
      ]) {
        expect(
          kBodyMapRegionZones.containsKey(region),
          isFalse,
          reason: '$region has no hit zone — R10',
        );
        expect(
          kRegionLabels.containsKey(region),
          isTrue,
          reason: 'it is still a ratified region, reachable by chip in T21b',
        );
      }
    });

    test('every key is a ratified region code', () {
      for (final region in kBodyMapRegionZones.keys) {
        expect(kRegionLabels.containsKey(region), isTrue, reason: region);
      }
      expect(
        kRegionLabels,
        hasLength(8),
        reason: 'all eight are accounted for',
      );
    });

    test('the table is declared in the mockup own 120x220 user space', () {
      expect(kBodyMapUserSpace, const Size(120, 220));
      for (final entry in kBodyMapRegionZones.entries) {
        expect(entry.value.left, greaterThanOrEqualTo(0.0), reason: entry.key);
        expect(entry.value.top, greaterThanOrEqualTo(0.0), reason: entry.key);
        expect(
          entry.value.right,
          lessThanOrEqualTo(kBodyMapUserSpace.width),
          reason: entry.key,
        );
        expect(
          entry.value.bottom,
          lessThanOrEqualTo(kBodyMapUserSpace.height),
          reason: entry.key,
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // R11 — no overlap, ever
  // -------------------------------------------------------------------------

  group('R11 — the zones do not overlap', () {
    test('every pair of zones is disjoint', () {
      final entries = kBodyMapRegionZones.entries.toList(growable: false);

      expect(
        entries.length,
        greaterThanOrEqualTo(2),
        reason: 'a pairwise walk over fewer than two entries asserts nothing',
      );
      var pairs = 0;
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          pairs++;
          expect(
            entries[i].value.overlaps(entries[j].value),
            isFalse,
            reason:
                '${entries[i].key} ${entries[i].value} overlaps '
                '${entries[j].key} ${entries[j].value} — a tie is a defect, '
                'not a priority question',
          );
        }
      }
      expect(pairs, 6, reason: 'four zones, six pairs — the walk really ran');
    });

    test('a point on a shared edge resolves to exactly one zone', () {
      // pelvis ends and legs begin at user y=150 (the mockup's leg split).
      // `Rect.contains` is half-open, so the boundary belongs to `legs` and to
      // nothing else — deterministic, not a coin toss.
      final matches = kBodyMapRegionZones.entries
          .where((entry) => entry.value.contains(const Offset(60, 150)))
          .map((entry) => entry.key)
          .toList(growable: false);

      expect(matches, <String>['legs']);
      expect(regionAt(_unit(60, 150), kUnitFigure), 'legs');
      expect(regionAt(_unit(60, 149), kUnitFigure), 'pelvis');
    });
  });

  // -------------------------------------------------------------------------
  // regionAt — the hit test itself
  // -------------------------------------------------------------------------

  group('regionAt maps a tap to its region', () {
    test('a tap inside each of the four zones returns that zone', () {
      expect(regionAt(_unit(60, 55), kUnitFigure), 'chest_shoulder');
      // (60,100) is the mockup's own largest accent circle.
      expect(regionAt(_unit(60, 100), kUnitFigure), 'lower_abdomen');
      expect(regionAt(_unit(60, 137), kUnitFigure), 'pelvis');
      expect(regionAt(_unit(52, 175), kUnitFigure), 'legs');
    });

    test('every zone centre resolves to its own key', () {
      for (final entry in kBodyMapRegionZones.entries) {
        final centre = entry.value.center;
        expect(
          regionAt(_unit(centre.dx, centre.dy), kUnitFigure),
          entry.key,
          reason: '${entry.key} centre $centre',
        );
      }
    });

    test('the painted rect scale is applied, not assumed to be 1:1', () {
      expect(regionAt(_double(60, 55), kDoubleFigure), 'chest_shoulder');
      expect(regionAt(_double(60, 100), kDoubleFigure), 'lower_abdomen');
      expect(regionAt(_double(60, 137), kDoubleFigure), 'pelvis');
      expect(regionAt(_double(52, 175), kDoubleFigure), 'legs');
      expect(
        regionAt(_double(60, 20), kDoubleFigure),
        isNull,
        reason: 'the head is still not a region at 2x',
      );
    });

    test('a tap above the figure (the head) is null', () {
      expect(regionAt(_unit(60, 20), kUnitFigure), isNull);
      expect(regionAt(_unit(60, 2), kUnitFigure), isNull);
      expect(regionAt(_unit(60, -10), kUnitFigure), isNull);
    });

    test('a tap below the figure (past the feet) is null', () {
      expect(regionAt(_unit(60, 210), kUnitFigure), isNull);
      expect(regionAt(_unit(60, 219), kUnitFigure), isNull);
      expect(regionAt(_unit(60, 400), kUnitFigure), isNull);
    });

    test('a tap on an arm, or off the figure sideways, is null', () {
      // The mockup's arm stroke runs (40,60)->(24,110)->(28,140) and its
      // mirror; neither arm is a region.
      expect(regionAt(_unit(26, 110), kUnitFigure), isNull);
      expect(regionAt(_unit(94, 110), kUnitFigure), isNull);
      expect(regionAt(_unit(2, 100), kUnitFigure), isNull);
      expect(regionAt(_unit(118, 100), kUnitFigure), isNull);
      expect(regionAt(_unit(-20, 100), kUnitFigure), isNull);
    });

    test('regionAt never returns a region the table does not declare', () {
      var hits = 0;
      for (var x = -10.0; x <= 130.0; x += 2.0) {
        for (var y = -10.0; y <= 230.0; y += 2.0) {
          final region = regionAt(_unit(x, y), kUnitFigure);
          if (region == null) continue;
          hits++;
          expect(
            kBodyMapRegionZones.containsKey(region),
            isTrue,
            reason: 'regionAt returned $region at ($x,$y)',
          );
        }
      }
      expect(hits, greaterThan(0), reason: 'the sweep must actually hit');
    });

    test('a degenerate painted rect is null, never a NaN hit', () {
      expect(regionAt(const Offset(60, 100), Rect.zero), isNull);
      expect(
        regionAt(const Offset(60, 100), const Rect.fromLTWH(0, 0, 0, 220)),
        isNull,
      );
      expect(
        regionAt(const Offset(60, 100), const Rect.fromLTWH(0, 0, 120, 0)),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // R13 — the tap-target arithmetic, in logical pixels
  // -------------------------------------------------------------------------

  group('R13 — tap targets clear the 24 logical-px floor', () {
    test('every zone clears it at the minimum painted height', () {
      final scale = kBodyMapMinPaintedHeight / kBodyMapUserSpace.height;

      expect(kBodyMapRegionZones, isNotEmpty);
      for (final entry in kBodyMapRegionZones.entries) {
        expect(
          entry.value.width * scale,
          greaterThanOrEqualTo(kBodyMapMinTapTarget),
          reason: '${entry.key} width',
        );
        expect(
          entry.value.height * scale,
          greaterThanOrEqualTo(kBodyMapMinTapTarget),
          reason: '${entry.key} height',
        );
      }
    });

    test('the minimum painted height is tight, not an arbitrary number', () {
      // Two logical px shorter and the shallowest zone (pelvis, 26 user units)
      // drops below the floor — so the constant is derived, and a later edit
      // that shrinks a zone cannot hide behind a generously large number.
      final scale = (kBodyMapMinPaintedHeight - 2) / kBodyMapUserSpace.height;

      expect(
        kBodyMapRegionZones.values.any(
          (zone) =>
              zone.width * scale < kBodyMapMinTapTarget ||
              zone.height * scale < kBodyMapMinTapTarget,
        ),
        isTrue,
      );
    });

    test('the floor is WCAG 2.2 SC 2.5.8, the value the plan ruled', () {
      expect(kBodyMapMinTapTarget, 24.0);
    });

    test('the mockup natural 1:1 size leaves 16 logical px of slack', () {
      // This project maps 1 mockup CSS px to 1 Flutter logical px, with no
      // frame scaling, and the mockup's svg is
      // `viewBox="0 0 120 220" width="150" height="220"` — the default
      // `xMidYMid meet` fits 120x220 into 150x220 at scale 1 — so the
      // figure's natural painted height IS the user space's own height.
      expect(kBodyMapUserSpace.height, 220.0);
      expect(
        kBodyMapUserSpace.height - kBodyMapMinPaintedHeight,
        16.0,
        reason: 'the whole vertical margin T21b has to spend',
      );

      // At that natural size the zones measure 48x42, 48x44, 48x26 and 40x54
      // logical px, so the tightest is `pelvis` at 26 — 1.08x the floor, not
      // a comfortable multiple of it.
      final tightest = kBodyMapRegionZones.values
          .map((zone) => zone.shortestSide)
          .reduce((a, b) => a < b ? a : b);

      expect(tightest, 26.0, reason: 'pelvis height, at 1:1');
      expect(tightest / kBodyMapMinTapTarget, closeTo(1.083, 0.001));
    });
  });
}
