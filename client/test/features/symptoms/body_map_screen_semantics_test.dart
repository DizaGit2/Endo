// Screen 13 — the body map (P4b-T21b, the screen half of T21).
//
// TDD (RED first). T21a shipped the whole headless half — `BodyMapSelection`'s
// placement/toggle/block rules and `body_map_geometry.dart`'s zone table and
// `regionAt` — each with its own unit tests. **Nothing here re-tests those
// rules**; this file tests what only the SCREEN can get wrong:
//
//   * a tap on the drawn figure reaching the RIGHT region (a transposed or
//     flipped coordinate would pass every T21a geometry test ever written,
//     because `regionAt` itself would still be correct);
//   * the two input paths — chip and silhouette — producing IDENTICAL state;
//   * the four regions with NO hit zone being fully usable and drawing no
//     marker (R3), which is the one place the picture and the truth differ;
//   * the LIVE write into `SymptomForm.bodyMapPoints` (R7), before any `Done`;
//   * the block reason rendering BESIDE the blocked affordance (R8), never a
//     bare disabled control;
//   * rehydration across a real push/pop/push (R7);
//   * and the four elements the rulings CUT — Front/Back, the selected-point
//     control, zoom, and its hint card.
//
// The marker geometry is asserted through `flutter_test`'s `paints` matcher
// rather than through a golden: `golden_app.dart`'s copy-insensitivity rules
// 6-8 all concern `RenderParagraph`, so hand-drawn vector art has no
// cross-platform protection in an image, and the one golden pair this screen
// ships is of the EMPTY figure. Every claim about a marker is made here, where
// it can be stated in numbers.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/symptoms/application/body_map_geometry.dart';
import 'package:lumen/features/symptoms/application/body_map_selection.dart';
import 'package:lumen/features/symptoms/application/symptom_form_controller.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:lumen/features/symptoms/presentation/body_map_screen.dart';
import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Mounts screen 13 on its own.
///
/// Nothing on this screen does I/O — R-11 leaves it no repository at all — so
/// there is no API to stub. The returned container is how a test reads the
/// form back: this screen's whole contract is what it writes into it.
Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  ProviderContainer? container,
}) {
  return pumpApp(
    tester,
    home: const BodyMapScreen(),
    container: container,
    overrides: container != null
        ? const <Override>[]
        : <Override>[...lumenOverrides()],
  );
}

/// Mounts screen 13 the way production does: PUSHED over screen 12, which
/// stays mounted underneath.
///
/// That is not decoration — `symptomFormControllerProvider` is `autoDispose`,
/// so with no screen 12 underneath, popping screen 13 would drop the last
/// listener and tear the form down. The production stack is what keeps it
/// alive, and a rehydration test against anything else would be testing a
/// shape the app does not have.
Future<GoRouter> _pumpPushed(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: Routes.symptomsNew,
    routes: <RouteBase>[
      GoRoute(
        path: Routes.symptomsNew,
        builder: (_, _) => const SymptomFormScreen(),
      ),
      GoRoute(
        path: Routes.symptomsBodyMap,
        builder: (_, _) => const BodyMapScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await pumpRouterApp(
    tester,
    routerConfig: router,
    overrides: <Override>[...lumenOverrides()],
  );
  router.push(Routes.symptomsBodyMap);
  await tester.pumpAndSettle();
  return router;
}

// ---------------------------------------------------------------------------
// Reaching the screen's parts
// ---------------------------------------------------------------------------

/// A point inside the drawn figure, in the mockup's own user-space units.
///
/// The figure is painted at exactly [kBodyMapUserSpace], so a user-space
/// coordinate is a logical-pixel offset from the box's top left with no
/// conversion — which is the property that makes these numbers readable
/// against `body_map_geometry.dart`'s table.
Offset _figurePoint(WidgetTester tester, double userX, double userY) =>
    tester.getTopLeft(find.byKey(kBodyMapFigureKey)) + Offset(userX, userY);

Future<void> _tapFigure(
  WidgetTester tester,
  double userX,
  double userY,
) async {
  await tester.tapAt(_figurePoint(tester, userX, userY));
  await tester.pump();
}

/// Scrolls [finder] to the middle of the viewport, then taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

/// Taps stop [stop] on the intensity block for [region].
Future<void> _tapStop(WidgetTester tester, String region, int stop) {
  return _tap(
    tester,
    find.descendant(
      of: find.byKey(bodyMapIntensityKey(region)),
      matching: find.text('$stop'),
    ),
  );
}

List<SymptomEntryDraft> _points(ProviderContainer container) =>
    container.read(symptomFormControllerProvider).bodyMapPoints;

/// One draft's whole wire contribution, in a form `expect` can compare.
///
/// [SymptomEntryDraft] has no `operator==`, and writing one for it would be
/// exactly the "equal on a subset of fields" hazard T21a rejected. Comparing
/// the described maps instead states every field the comparison covers.
Map<String, Object?> _describe(SymptomEntryDraft draft) => <String, Object?>{
  'symptomCode': draft.symptomCode,
  'intensity': draft.intensity,
  'region': draft.region,
  'side': draft.side,
  'painTypes': draft.painTypes,
  'triggers': draft.triggers,
  'occurredAt': draft.occurredAt,
  'notes': draft.notes,
};

/// Every intensity scale on screen, in tree order, by the label it announces.
List<String> _scaleLabels(WidgetTester tester) => tester
    .widgetList<LumenIntensityScale>(find.byType(LumenIntensityScale))
    .map((scale) => scale.semanticsLabel)
    .toList();

List<LumenSelectableChip> _chips(WidgetTester tester) => tester
    .widgetList<LumenSelectableChip>(find.byType(LumenSelectableChip))
    .toList();

bool _chipSelected(WidgetTester tester, String label) =>
    _chips(tester).firstWhere((chip) => chip.label == label).selected;

TextButton _done(WidgetTester tester) => tester.widget<TextButton>(
  find.widgetWithText(TextButton, kBodyMapDoneLabel),
);

void main() {
  // -------------------------------------------------------------------------
  // The opening state
  // -------------------------------------------------------------------------

  group('the opening state', () {
    testWidgets('opens with nothing placed — no chip selected, no intensity '
        'block, no marker', (tester) async {
      await _pumpScreen(tester);

      expect(_chips(tester).where((chip) => chip.selected), isEmpty);
      expect(find.byType(LumenIntensityScale), findsNothing);
      expect(find.text('0 points placed'), findsOneWidget);
      expect(
        find.byKey(kBodyMapFigureKey),
        isNot(paints..circle()),
        reason:
            'a marker on an empty map would be the mockup\'s three design '
            'fixtures shipped as data',
      );
    });

    testWidgets('renders ALL EIGHT ratified regions as chips, in frozen '
        'declaration order — the chip list is the COMPLETE input path (R3), '
        'not a subset of what the figure can be tapped for', (tester) async {
      await _pumpScreen(tester);

      expect(
        _chips(tester).map((chip) => chip.label).toList(),
        <String>[
          'Lower abdomen',
          'Pelvis',
          'Lower back',
          'Legs',
          'Bowel / rectal',
          'Bladder',
          'Vaginal',
          'Chest / shoulder',
        ],
      );
    });

    testWidgets('Done is offered from the start — an EMPTY body map is not an '
        'error, and screen 12 owns the empty-batch guard', (tester) async {
      await _pumpScreen(tester);

      expect(_done(tester).onPressed, isNotNull);
      expect(find.byType(LumenFieldMessage), findsNothing);
    });

    testWidgets('the figure is painted at its natural size and never shrinks '
        '— the layout SCROLLS instead', (tester) async {
      await _pumpScreen(tester);

      final Size painted = tester.getSize(find.byKey(kBodyMapFigureKey));

      expect(
        painted,
        kBodyMapUserSpace,
        reason:
            'painted at exactly 1:1 with the mockup\'s own viewBox, which is '
            'what removes every scale factor from the tap path',
      );
      expect(
        painted.height,
        greaterThanOrEqualTo(kBodyMapMinPaintedHeight),
        reason:
            'below this the pelvis zone — 26 of 220 user units, the '
            'shallowest — falls under the 24 logical-px tap-target floor. '
            'The natural size clears it by 16 px and no more, which is why a '
            'layout short of vertical room must scroll rather than shrink '
            'the silhouette',
      );
    });
  });

  // -------------------------------------------------------------------------
  // The silhouette as an input (R3's convenience half)
  // -------------------------------------------------------------------------

  group('tapping the figure', () {
    // Each pair is the CENTRE of that zone in `kBodyMapRegionZones`, read off
    // the table rather than computed here, so a probe cannot silently drift
    // with the zone it aims at.
    // Keyed by the CHIP LABEL the tap must select, because an unrated
    // placement is deliberately not in the form yet (`toDrafts` emits only
    // rated regions) — the chip list is the authoritative display of what is
    // placed, so it is what a placement assertion reads.
    const Map<String, Offset> centres = <String, Offset>{
      'Chest / shoulder': Offset(60, 59),
      'Lower abdomen': Offset(60, 102),
      'Pelvis': Offset(60, 137),
      'Legs': Offset(60, 177),
    };

    for (final MapEntry<String, Offset> zone in centres.entries) {
      testWidgets('a tap inside the ${zone.key} zone places ${zone.key}', (
        tester,
      ) async {
        await _pumpScreen(tester);

        await _tapFigure(tester, zone.value.dx, zone.value.dy);

        expect(
          _chips(tester).where((chip) => chip.selected).map((c) => c.label),
          <String>[zone.key],
          reason:
              'the tap landed in the ${zone.key} zone; a flipped or '
              'transposed coordinate would place a DIFFERENT region while '
              'every regionAt unit test stayed green — which is why this '
              'names the region rather than counting placements',
        );
        expect(find.text('1 point placed'), findsOneWidget);
      });
    }

    testWidgets('a tap that hits NO zone places nothing — the head, an arm '
        'and the background are not "nearest region" hints', (tester) async {
      await _pumpScreen(tester);

      await _tapFigure(tester, 60, 20); // the head
      await _tapFigure(tester, 26, 110); // the left arm
      await _tapFigure(tester, 4, 4); // the top-left background

      expect(_chips(tester).where((chip) => chip.selected), isEmpty);
      expect(find.text('0 points placed'), findsOneWidget);
    });

    testWidgets('a SECOND tap on the same region removes it AND discards its '
        'intensity — re-placing starts over at unrated', (tester) async {
      final container = await _pumpScreen(tester);

      await _tapFigure(tester, 60, 137); // pelvis
      await _tapStop(tester, 'pelvis', 7);
      expect(_points(container).single.intensity, 7);

      await _tapFigure(tester, 60, 137);
      expect(_points(container), isEmpty);
      expect(find.byType(LumenIntensityScale), findsNothing);

      await _tapFigure(tester, 60, 137);
      expect(
        _points(container),
        isEmpty,
        reason:
            'the point is placed again but UNRATED, so toDrafts emits '
            'nothing — a remembered 7 would silently re-log a number the '
            'user had already taken back',
      );
      expect(
        tester
            .widget<LumenIntensityScale>(
              find.descendant(
                of: find.byKey(bodyMapIntensityKey('pelvis')),
                matching: find.byType(LumenIntensityScale),
              ),
            )
            .value,
        isNull,
      );
    });

    testWidgets('a chip tap and a figure tap on the same region produce '
        'IDENTICAL form state', (tester) async {
      final byFigure = await _pumpScreen(tester);
      await _tapFigure(tester, 60, 102); // lower_abdomen
      await _tapStop(tester, 'lower_abdomen', 4);
      final List<Map<String, Object?>> fromFigure = _points(
        byFigure,
      ).map(_describe).toList();

      await tester.pumpWidget(const SizedBox.shrink());

      final byChip = await _pumpScreen(tester);
      await _tap(tester, find.text('Lower abdomen'));
      await _tapStop(tester, 'lower_abdomen', 4);
      final List<Map<String, Object?>> fromChip = _points(
        byChip,
      ).map(_describe).toList();

      expect(fromChip, fromFigure);
      expect(
        fromFigure.single['side'],
        isNull,
        reason:
            'R-21 — every body-map point carries side: null, and no code path '
            'on this screen can set it',
      );
    });
  });

  // -------------------------------------------------------------------------
  // R3 — the four regions with no honest anterior projection
  // -------------------------------------------------------------------------

  group('a region with no hit zone (R3)', () {
    testWidgets('lower_back is placed by chip, counted, and emitted — but NO '
        'marker is painted for it, because a zone on an anterior figure '
        'would be an invented anatomical projection', (tester) async {
      final container = await _pumpScreen(tester);

      await _tap(tester, find.text('Lower back'));
      await _tapStop(tester, 'lower_back', 6);

      expect(_chipSelected(tester, 'Lower back'), isTrue);
      expect(find.text('1 point placed'), findsOneWidget);
      expect(_points(container).single.region, 'lower_back');
      expect(
        find.byKey(kBodyMapFigureKey),
        isNot(paints..circle()),
        reason:
            'the chip list is the authoritative display of what is placed; '
            'the silhouette shows only what it can honestly show — no '
            'invented position, no legend pin, no "elsewhere" bucket',
      );
    });

    testWidgets('all four zoneless regions are reachable and none draws a '
        'marker', (tester) async {
      final container = await _pumpScreen(tester);

      for (final String label in const <String>[
        'Lower back',
        'Bowel / rectal',
        'Bladder',
        'Vaginal',
      ]) {
        await _tap(tester, find.text(label));
      }

      expect(
        container.read(symptomFormControllerProvider).bodyMapPoints,
        isEmpty,
        reason: 'none of the four is rated yet',
      );
      expect(find.text('4 points placed'), findsOneWidget);
      expect(find.byKey(kBodyMapFigureKey), isNot(paints..circle()));
    });
  });

  // -------------------------------------------------------------------------
  // R4 — markers are flat
  // -------------------------------------------------------------------------

  group('markers (R4)', () {
    testWidgets('every marker is drawn at the SAME radius regardless of '
        'intensity — a size ramp would draw a logged 0 at zero radius and '
        'erase the user\'s own datum from the only picture of it', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await _tapFigure(tester, 60, 137); // pelvis
      await _tapStop(tester, 'pelvis', 0);
      await _tapFigure(tester, 60, 59); // chest_shoulder
      await _tapStop(tester, 'chest_shoulder', 10);

      // Drawn in `kRegionLabels` order, so pelvis precedes chest_shoulder.
      // The radius is stated as a LITERAL, not as kBodyMapMarkerRadius: an
      // assertion written against the constant it is checking cannot fail.
      expect(
        find.byKey(kBodyMapFigureKey),
        paints
          ..circle(x: 60, y: 137, radius: 5.0)
          ..circle(x: 60, y: 59, radius: 5.0),
      );
    });

    testWidgets('a marker sits at its zone\'s centre, and only placed regions '
        'draw one', (tester) async {
      await _pumpScreen(tester);

      await _tapFigure(tester, 60, 102); // lower_abdomen
      await _tapStop(tester, 'lower_abdomen', 3);

      expect(
        find.byKey(kBodyMapFigureKey),
        paints..circle(x: 60, y: 102, radius: 5.0),
      );
      expect(
        find.byKey(kBodyMapFigureKey),
        isNot(paints..circle()..circle()),
        reason: 'one placed region, one marker',
      );
    });
  });

  // -------------------------------------------------------------------------
  // R2 — one stacked intensity block per placed region
  // -------------------------------------------------------------------------

  group('intensity blocks (R2)', () {
    testWidgets('blocks render in FROZEN VOCABULARY order, never tap order — '
        'the list must not reorder under the user', (tester) async {
      await _pumpScreen(tester);

      // Tapped LAST-in-vocabulary first.
      await _tap(tester, find.text('Chest / shoulder'));
      await _tap(tester, find.text('Lower abdomen'));

      expect(_scaleLabels(tester), <String>[
        'Lower abdomen intensity',
        'Chest / shoulder intensity',
      ]);
    });

    testWidgets('there is no "selected point" control — the mockup\'s single '
        'shared scale does not ship', (tester) async {
      await _pumpScreen(tester);

      expect(find.textContaining('selected point'), findsNothing);

      await _tap(tester, find.text('Pelvis'));
      await _tap(tester, find.text('Legs'));
      expect(
        find.byType(LumenIntensityScale),
        findsNWidgets(2),
        reason:
            'one scale per placed region: a single shared control could not '
            'be reached at all by a chip-list user, since LumenSelectableChip '
            'is a plain two-state toggle with no "select" state to hang it on',
      );
    });

    testWidgets('a rating survives placing another region, and each block '
        'holds its OWN value', (tester) async {
      await _pumpScreen(tester);

      await _tap(tester, find.text('Pelvis'));
      await _tapStop(tester, 'pelvis', 2);
      await _tap(tester, find.text('Legs'));
      await _tapStop(tester, 'legs', 9);

      expect(
        tester
            .widgetList<LumenIntensityScale>(find.byType(LumenIntensityScale))
            .map((scale) => scale.value)
            .toList(),
        <int>[2, 9],
      );
    });

    testWidgets('tapping the selected stop clears that point back to unrated '
        '— a mis-tap is reachable, not permanent', (tester) async {
      final container = await _pumpScreen(tester);

      await _tap(tester, find.text('Pelvis'));
      await _tapStop(tester, 'pelvis', 5);
      expect(_points(container).single.intensity, 5);

      await _tapStop(tester, 'pelvis', 5);

      expect(
        _points(container),
        isEmpty,
        reason:
            'the point is still PLACED but no longer rated, and toDrafts '
            'never invents an intensity for it',
      );
      expect(_chipSelected(tester, 'Pelvis'), isTrue);
      expect(find.text('1 point placed'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // R7 — the write is LIVE
  // -------------------------------------------------------------------------

  group('the live write (R7)', () {
    testWidgets('a rated placement reaches SymptomForm.bodyMapPoints BEFORE '
        'any Done — the screen hands nothing back on exit', (tester) async {
      final container = await _pumpScreen(tester);

      await _tapFigure(tester, 60, 137);
      await _tapStop(tester, 'pelvis', 8);

      expect(_describe(_points(container).single), <String, Object?>{
        'symptomCode': null,
        'intensity': 8,
        'region': 'pelvis',
        'side': null,
        'painTypes': <String>[],
        'triggers': <String>[],
        'occurredAt': null,
        'notes': null,
      });
    });

    testWidgets('removing a point removes it from the form immediately — the '
        'toggle IS the undo, so there is nothing to cancel', (tester) async {
      final container = await _pumpScreen(tester);

      await _tap(tester, find.text('Pelvis'));
      await _tapStop(tester, 'pelvis', 8);
      await _tap(tester, find.text('Legs'));
      await _tapStop(tester, 'legs', 1);
      expect(_points(container), hasLength(2));

      await _tap(tester, find.text('Pelvis'));

      expect(_points(container).map((point) => point.region).toList(), <String>[
        'legs',
      ]);
    });

    testWidgets('re-entering the screen rehydrates from the form', (
      tester,
    ) async {
      final GoRouter router = await _pumpPushed(tester);

      await _tap(tester, find.text('Pelvis'));
      await _tapStop(tester, 'pelvis', 3);
      await _tap(tester, find.text('Lower back'));
      await _tapStop(tester, 'lower_back', 6);

      await _tap(tester, find.text(kBodyMapDoneLabel));
      await tester.pumpAndSettle(); // the pop's exit transition
      expect(find.byType(BodyMapScreen), findsNothing);
      expect(find.byType(SymptomFormScreen), findsOneWidget);

      router.push(Routes.symptomsBodyMap);
      await tester.pumpAndSettle();

      expect(_chipSelected(tester, 'Pelvis'), isTrue);
      expect(_chipSelected(tester, 'Lower back'), isTrue);
      expect(find.text('2 points placed'), findsOneWidget);
      expect(
        tester
            .widgetList<LumenIntensityScale>(find.byType(LumenIntensityScale))
            .map((scale) => scale.value)
            .toList(),
        <int>[3, 6],
        reason:
            'in kRegionLabels order: pelvis then lower_back, each with the '
            'intensity it was given before the screen closed',
      );
    });
  });

  // -------------------------------------------------------------------------
  // R8 — blocked, with the reason beside it
  // -------------------------------------------------------------------------

  group('the block reason (R8)', () {
    testWidgets('Done is blocked and the reason is DRAWN while a placement is '
        'unrated — never a bare disabled control', (tester) async {
      await _pumpScreen(tester);

      await _tap(tester, find.text('Pelvis'));

      expect(_done(tester).onPressed, isNull);
      expect(
        find.text(kBodyMapMissingIntensityMessage),
        findsOneWidget,
        reason:
            'the goals-screen rule: "the reason is never left to be guessed"',
      );
    });

    testWidgets('rating every placement unblocks it and removes the reason', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await _tap(tester, find.text('Pelvis'));
      await _tap(tester, find.text('Legs'));
      expect(_done(tester).onPressed, isNull);

      await _tapStop(tester, 'pelvis', 0);
      expect(
        _done(tester).onPressed,
        isNull,
        reason: 'legs is still unrated — and 0 is a real rating for pelvis',
      );

      await _tapStop(tester, 'legs', 4);
      expect(_done(tester).onPressed, isNotNull);
      expect(find.text(kBodyMapMissingIntensityMessage), findsNothing);
    });

    testWidgets('the reason is NOT a live region — it sits directly above the '
        'control it disables and would otherwise re-announce on every one of '
        'eight chip taps', (tester) async {
      await _pumpScreen(tester);
      await _tap(tester, find.text('Pelvis'));

      final SemanticsNode node = tester.getSemantics(
        find.text(kBodyMapMissingIntensityMessage),
      );
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // R9 / R10 — what a screen reader gets
  // -------------------------------------------------------------------------

  group('semantics', () {
    testWidgetsWithSemantics('the silhouette carries ONE summary node whose '
        'VALUE is the counter, and it is not a live region', (tester) async {
      await _pumpScreen(tester);

      SemanticsNode summary() =>
          find.semantics.byLabel(kBodyMapFigureLabel).evaluate().single;

      expect(summary().value, '0 points placed');
      expect(
        summary().getSemanticsData().flagsCollection.isLiveRegion,
        isFalse,
        reason:
            'all seven existing liveRegion sites in client/lib are '
            'appear-once messages; a permanently-mounted changing counter '
            'would re-announce on every tap',
      );

      await _tap(tester, find.text('Pelvis'));
      expect(summary().value, '1 point placed');

      await _tap(tester, find.text('Legs'));
      expect(summary().value, '2 points placed');
    });

    testWidgetsWithSemantics('individual zones get NO semantics nodes — a '
        'screen reader cannot aim a tap at a pixel region, and the all-8 chip '
        'list is the path that exists for exactly that reason', (tester) async {
      await _pumpScreen(tester);

      final SemanticsNode summary = find.semantics
          .byLabel(kBodyMapFigureLabel)
          .evaluate()
          .single;

      expect(summary.childrenCount, 0);
      expect(summary.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgetsWithSemantics('each intensity block announces "<Region> '
        'intensity"', (tester) async {
      await _pumpScreen(tester);

      await _tap(tester, find.text('Bladder'));
      await _tap(tester, find.text('Chest / shoulder'));

      expect(_scaleLabels(tester), <String>[
        'Bladder intensity',
        'Chest / shoulder intensity',
      ]);

      // And it reaches the NODE, not merely the widget property. `startsWith`
      // rather than equality: `LumenIntensityScale` is a merging container, so
      // its two fixed anchors join the announced name as
      // `'<label>\nNone\nWorst'` — shipped behaviour, identical on screen 12,
      // and not this screen's to restate.
      for (final MapEntry<String, String> block
          in const <String, String>{
            'bladder': 'Bladder intensity',
            'chest_shoulder': 'Chest / shoulder intensity',
          }.entries) {
        final Finder scale = find.descendant(
          of: find.byKey(bodyMapIntensityKey(block.key)),
          matching: find.byType(LumenIntensityScale),
        );
        // Scrolled into view first: a scrollable drops the semantics of
        // children outside its viewport, so an off-screen block would look
        // like an unlabelled one.
        await Scrollable.ensureVisible(tester.element(scale), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(scale).label, startsWith(block.value));
      }
    });

    testWidgetsWithSemantics('the back affordance has an accessible name', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expectLabeledButton(tester, find.byType(IconButton), 'Back');
    });

    testWidgets('no dingbat glyphs anywhere on the screen', (tester) async {
      await _pumpScreen(tester);

      expectNoDingbats(tester, screen: 'BodyMapScreen');
    });
  });

  // -------------------------------------------------------------------------
  // What the rulings CUT
  // -------------------------------------------------------------------------

  group('the cuts', () {
    testWidgets('R1 — there is no Front/Back control anywhere', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('Front'), findsNothing);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('R5 — no zoom: no +/- controls, no zoom label, no hint card, '
        'and no InteractiveViewer', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('100%'), findsNothing);
      expect(find.textContaining('zoom'), findsNothing);
      expect(find.textContaining('Pinch'), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('R6 — the affordance is Done, and it is not a FilledButton', (
      tester,
    ) async {
      await _pumpScreen(tester);

      // Literals on both sides. An assertion written against
      // kBodyMapDoneLabel would move with the constant it is checking and
      // could not tell "the ruling held" from "somebody renamed it".
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Save body map'), findsNothing);
      expect(
        find.byType(FilledButton),
        findsNothing,
        reason:
            'the mockup\'s markup is byte-identical to screen 12\'s real save '
            'button, so its visual weight promises a write R-11 forbids',
      );
    });
  });
}
