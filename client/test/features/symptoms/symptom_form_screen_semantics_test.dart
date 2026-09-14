// Screen 12 — the symptom form (P4b-T20b, the screen half of T20).
//
// TDD (RED first). T20a shipped the whole headless half — `SymptomForm`'s
// guards and error lookups, `assembleSymptomBatch`, and
// `SymptomFormController` — all with their own unit tests. **Nothing here
// re-tests those rules**; this file tests what only the SCREEN can get
// wrong:
//
//   * the four vocabularies rendering COMPLETE and in FROZEN order (R-14);
//   * each control being wired to the setter it claims (a Location tap that
//     called `togglePainType` would pass every T20a test ever written);
//   * LOCATION's single-select + deselect-to-clear discipline, which
//     `LumenSelectableChip` deliberately does NOT own;
//   * the per-chip intensity list's own ordering and disclosure (S5);
//   * the freeze-while-submitting that makes T20a's error binding sound
//     (S8) — including the controls far down the scroll;
//   * and the error binding actually reaching the right row on screen.
//
// `SymptomsRepository` and `ServerTodayRepository` are exercised FOR REAL
// (only `LumenApiApi`/`CacheStore` are mocked), so a wire assertion here
// proves the screen's own funnel end to end, not merely that the controller
// asked the repository correctly.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/create_symptoms_request.dart';
import 'package:lumen/api/model/create_symptoms_response.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/application/symptom_form_controller.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:lumen/features/symptoms/presentation/body_map_screen.dart';
import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

/// A [SymptomFormController] pinned to one [SymptomForm].
///
/// For the two states the UI cannot reach on its own: the R-18 over-cap
/// block (the chips can produce at most 21 entries, and the cap is 50) and a
/// retained-drafts failure whose SELECTION HAS SINCE CHANGED — every setter
/// clears the failure, so no tap sequence can produce that combination.
class _FixedSymptomFormController extends SymptomFormController {
  _FixedSymptomFormController(this._form);
  final SymptomForm _form;

  @override
  SymptomForm build() => _form;
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Mounts screen 12 on its own, with the REAL repository and the REAL
/// `sessionTodayProvider` behind it.
///
/// `cycleCalendarGet` is stubbed because `SymptomFormController.submit`
/// reads the server-confirmed "today" (R12) before it POSTs.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required MockLumenApiApi api,
  bool settle = true,
  SymptomForm? pinnedForm,
}) async {
  when(
    () => api.cycleCalendarGet(from: null, to: null),
  ).thenAnswer(apiSuccess(cycleCalendarFixture()));

  await pumpApp(
    tester,
    settle: settle,
    home: const SymptomFormScreen(),
    overrides: <Override>[
      ...lumenOverrides(api: api, cacheStore: emptyCacheStore()),
      if (pinnedForm != null)
        symptomFormControllerProvider.overrideWith(
          () => _FixedSymptomFormController(pinnedForm),
        ),
    ],
  );
}

/// Mounts screen 12 as a PUSHED route over a host page, so `context.pop()`
/// has somewhere to go — the shape the production route has
/// (`/symptoms/new` is top-level, pushed from whichever branch the user was
/// in). The production table itself is exercised in
/// `test/core/router/symptom_form_route_test.dart`.
Future<GoRouter> _pumpPushed(
  WidgetTester tester, {
  required MockLumenApiApi api,
}) async {
  when(
    () => api.cycleCalendarGet(from: null, to: null),
  ).thenAnswer(apiSuccess(cycleCalendarFixture()));

  final router = GoRouter(
    initialLocation: '/host',
    routes: <RouteBase>[
      GoRoute(
        path: '/host',
        builder: (_, _) => const Scaffold(body: Center(child: Text('host'))),
      ),
      GoRoute(path: '/pushed', builder: (_, _) => const SymptomFormScreen()),
      // Screen 13's REAL path constant, so the body-map affordance's push
      // target is checked against the same string production registers
      // (P4b-T21b). The production TABLE is exercised in
      // `test/core/router/body_map_route_test.dart`.
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
    overrides: lumenOverrides(api: api, cacheStore: emptyCacheStore()),
  );
  router.push('/pushed');
  await tester.pumpAndSettle();
  return router;
}

/// Scrolls [finder] to the MIDDLE of the viewport, then taps it.
///
/// This screen is several viewports tall — every chip below TYPE is laid out
/// but off-screen at the 390x844 test surface, and `tester.tap` on an
/// off-screen target hits nothing.
///
/// `alignment: 0.5` rather than `tester.ensureVisible`'s edge alignment: an
/// edge-aligned target lands flush against the viewport boundary, where a
/// rounding pixel or a neighbouring widget's ink splash can take the tap. It
/// is a no-op when there is no `Scrollable` ancestor at all, so the same
/// helper works for the pinned footer's CTA.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

List<String> _chipLabels(WidgetTester tester) => tester
    .widgetList<LumenSelectableChip>(find.byType(LumenSelectableChip))
    .map((chip) => chip.label)
    .toList();

List<LumenSelectableChip> _chips(WidgetTester tester) => tester
    .widgetList<LumenSelectableChip>(find.byType(LumenSelectableChip))
    .toList();

/// Every intensity scale on screen, in tree order, by the label it announces.
List<String> _scaleLabels(WidgetTester tester) => tester
    .widgetList<LumenIntensityScale>(find.byType(LumenIntensityScale))
    .map((scale) => scale.semanticsLabel)
    .toList();

FilledButton _cta(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  late MockLumenApiApi api;

  setUpAll(() {
    registerFallbackValue(
      CreateSymptomsRequest((b) => b.entries.replace(const [])),
    );
  });

  setUp(() {
    api = MockLumenApiApi();
  });

  // -------------------------------------------------------------------------
  // The opening state (S2) — the anti-fabrication mechanical control
  // -------------------------------------------------------------------------

  group('the opening state', () {
    testWidgets('opens EMPTY — no chip selected, no stop filled', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      expect(
        _chips(tester).where((chip) => chip.selected),
        isEmpty,
        reason:
            'the mockup pre-selects four chips including the sensitive '
            'trigger `intercourse`; that is a design fixture (S2/F-13), '
            'not seed data',
      );

      // No pain stop is filled — probed the way screen 9 probes its own, by
      // comparing each stop's decoration against every other's rather than
      // hard-coding the accent token here. A `?? 0` default anywhere on the
      // pain path would make stop 0 the odd one out.
      final fills = <Color?>{};
      for (var stop = 0; stop <= 10; stop++) {
        final container = tester.widget<Container>(
          find.ancestor(
            of: find.text('$stop'),
            matching: find.byType(Container),
          ),
        );
        fills.add((container.decoration! as BoxDecoration).color);
      }
      expect(fills.length, 1);
    });

    testWidgets('the CTA is disabled and says why', (tester) async {
      await _pumpScreen(tester, api: api);

      expect(_cta(tester).onPressed, isNull);
      expect(find.text(kSymptomNothingSelectedMessage), findsOneWidget);
      expect(find.text('Save symptom'), findsOneWidget);
    });

    testWidgets('exactly ONE intensity scale — the pain row; no RELATED chip '
        'is selected, so no per-chip scale is disclosed', (tester) async {
      await _pumpScreen(tester, api: api);

      expect(_scaleLabels(tester), <String>['Pain level']);
    });
  });

  // -------------------------------------------------------------------------
  // The vocabularies (R-14 / S4) — complete, in frozen declaration order
  // -------------------------------------------------------------------------

  group('the chip rows', () {
    testWidgets(
      'render all 8 / 6 / 7 / 20 chips, in frozen declaration order, with no '
      '"show more" affordance hiding any of them',
      (tester) async {
        await _pumpScreen(tester, api: api);

        expect(
          _chipLabels(tester),
          <String>[
            ...kRegionLabels.values,
            ...kPainTypeLabels.values,
            ...kTriggerLabels.values,
            ...kSymptomCodeLabels.values,
          ],
          reason:
              'one assertion pins four things at once: every vocabulary is '
              'COMPLETE (41 chips), each row is in its own frozen '
              'declaration order, the ROWS are in the ruled order, and '
              'nothing is hidden behind a disclosure control (S4)',
        );
      },
    );

    testWidgets('the two ratified label collisions both render, unaltered — '
        'their section labels are what disambiguates them', (tester) async {
      await _pumpScreen(tester, api: api);

      expect(find.text('Cramping'), findsOneWidget); // Type
      expect(find.text('Cramping / joint pain'), findsOneWidget); // Related
      expect(find.text('Intercourse'), findsOneWidget); // Triggers
      expect(find.text('Painful intercourse'), findsOneWidget); // Related
    });
  });

  // -------------------------------------------------------------------------
  // S1 — field labels are PASSED in sentence case, DRAWN uppercase
  // -------------------------------------------------------------------------

  group('field labels', () {
    testWidgetsWithSemantics('are drawn uppercase but ANNOUNCED in sentence '
        'case — passing "LOCATION" would draw identically and be spelled out '
        'letter by letter', (tester) async {
      await _pumpScreen(tester, api: api);

      for (final (drawn, announced) in const <(String, String)>[
        ('LOCATION', 'Location'),
        ('TYPE', 'Type'),
        ('TRIGGERS', 'Triggers'),
        ('RELATED', 'Related'),
      ]) {
        expect(find.text(drawn), findsOneWidget);
        expect(
          find.bySemanticsLabel(announced),
          findsOneWidget,
          reason:
              'LumenFieldLabel announces the string it was GIVEN; the only '
              'thing that can distinguish "$announced" from "$drawn" at the '
              'call site is this announced label',
        );
        expect(find.bySemanticsLabel(drawn), findsNothing);
      }
    });

    testWidgets(
      'the pain row is labelled "Pain level" — screen 9\'s shipped string',
      (tester) async {
        await _pumpScreen(tester, api: api);

        expect(find.text('PAIN LEVEL'), findsOneWidget);
        expect(_scaleLabels(tester), contains('Pain level'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // LOCATION — single-select with deselect-to-clear
  // -------------------------------------------------------------------------

  group('LOCATION', () {
    testWidgets('is single-select: a second tap moves the selection', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Pelvis'));
      expect(
        _chips(tester).where((chip) => chip.selected).map((c) => c.label),
        <String>['Pelvis'],
      );

      await _tap(tester, find.text('Legs'));
      expect(
        _chips(tester).where((chip) => chip.selected).map((c) => c.label),
        <String>['Legs'],
        reason:
            'LOCATION is one region per episode — selecting a second must '
            'REPLACE the first, never accumulate',
      );
    });

    testWidgets('deselects to clear: tapping the selected chip returns to '
        'nothing selected', (tester) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Bladder'));
      expect(_chips(tester).where((chip) => chip.selected), hasLength(1));

      await _tap(tester, find.text('Bladder'));
      expect(
        _chips(tester).where((chip) => chip.selected),
        isEmpty,
        reason:
            'without deselect-to-clear a mistaken region tap is permanent '
            'for the life of the form — the screen draws no other way back '
            'to "no location"',
      );
    });
  });

  // -------------------------------------------------------------------------
  // TYPE / TRIGGERS / RELATED — multi-select
  // -------------------------------------------------------------------------

  group('the multi-select rows', () {
    testWidgets('TYPE and TRIGGERS accumulate rather than replace', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Sharp'));
      await _tap(tester, find.text('Dull'));
      await _tap(tester, find.text('Stress'));

      expect(
        _chips(tester).where((chip) => chip.selected).map((c) => c.label),
        <String>['Sharp', 'Dull', 'Stress'],
      );
    });
  });

  // -------------------------------------------------------------------------
  // S5 — the per-chip intensity list
  // -------------------------------------------------------------------------

  group('the per-chip intensity list', () {
    testWidgets('selecting a RELATED chip discloses exactly one block', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Nausea'));

      expect(_scaleLabels(tester), <String>['Pain level', 'Nausea intensity']);
    });

    testWidgets('blocks are ordered by FROZEN vocabulary order, never by '
        'selection order', (tester) async {
      await _pumpScreen(tester, api: api);

      // Tapped last-to-first in vocabulary terms: Fatigue (index 2) before
      // Bloating (index 0). Selection order would render them reversed.
      await _tap(tester, find.text('Fatigue'));
      await _tap(tester, find.text('Bloating'));

      expect(
        _scaleLabels(tester),
        <String>['Pain level', 'Bloating intensity', 'Fatigue intensity'],
        reason:
            'a list that reorders under the user on every tap destabilises '
            'the very ordering R-14 protects (S5)',
      );
    });

    testWidgets('deselecting removes the block, and re-selecting shows it '
        'EMPTY — never restored', (tester) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Headache'));
      await _tapStop(tester, symptomIntensityKey('headache'), 7);
      expect(_scaleValueFor(tester, 'Headache intensity'), 7);

      await _tap(tester, find.text('Headache'));
      expect(_scaleLabels(tester), <String>['Pain level']);

      await _tap(tester, find.text('Headache'));
      expect(
        _scaleValueFor(tester, 'Headache intensity'),
        isNull,
        reason:
            'R5 — deselecting DISCARDS the intensity; restoring a stale '
            'number would log a value the user did not choose this time',
      );
    });

    testWidgets('every per-chip scale announces "<Chip label> intensity" '
        '(S6) — 21 unnumbered scales would otherwise be indistinguishable', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Cramping / joint pain'));
      await _tap(tester, find.text('Mental fog'));

      expect(_scaleLabels(tester), <String>[
        'Pain level',
        'Cramping / joint pain intensity',
        'Mental fog intensity',
      ]);
    });
  });

  // -------------------------------------------------------------------------
  // The four block states (R8) — a disabled CTA PLUS an inline reason
  // -------------------------------------------------------------------------
  //
  // The MESSAGES and their priority order belong to `SymptomForm.blockReason`
  // and are pinned in `symptom_form_test.dart`. What is tested here is only
  // that this screen renders that one string, verbatim, above a CTA it has
  // actually disabled — the four constants are referenced, never retyped, so
  // a reworded message cannot make this file disagree with that one.

  group('the save block', () {
    testWidgets('guard 1 — nothing selected at all', (tester) async {
      await _pumpScreen(tester, api: api);

      expect(find.text(kSymptomNothingSelectedMessage), findsOneWidget);
      expect(_cta(tester).onPressed, isNull);
    });

    testWidgets('guard 2 — a RELATED chip selected with no intensity yet', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Bloating'));

      expect(find.text(kSymptomMissingIntensityMessage), findsOneWidget);
      expect(_cta(tester).onPressed, isNull);
    });

    testWidgets('guard 3 — a classification chip with no pain level', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Lower back'));

      expect(find.text(kSymptomMissingPainLevelMessage), findsOneWidget);
      expect(_cta(tester).onPressed, isNull);
    });

    testWidgets('guard 4 — the batch would exceed the R-18 cap', (
      tester,
    ) async {
      // 51 body-map points: the four chip rows can produce at most 21 entries
      // between them, so this state is only reachable once T21's seam is
      // filled. The screen renders whatever reason the form gives it.
      await _pumpScreen(
        tester,
        api: api,
        pinnedForm: SymptomForm(
          bodyMapPoints: List<SymptomEntryDraft>.generate(
            SymptomsRepository.maxBatchEntries + 1,
            (_) => const SymptomEntryDraft(
              symptomCode: 'bloating',
              intensity: 3,
              region: null,
              side: null,
              occurredAt: null,
            ),
          ),
        ),
      );

      expect(find.text(kSymptomBatchOverCapMessage), findsOneWidget);
      expect(_cta(tester).onPressed, isNull);
    });

    testWidgets('lifts once the block is satisfied', (tester) async {
      await _pumpScreen(tester, api: api);

      await _tap(tester, find.text('Lower back'));
      expect(_cta(tester).onPressed, isNull);

      await _tapStop(tester, kSymptomPainIntensityKey, 4);

      expect(_cta(tester).onPressed, isNotNull);
      expect(find.text(kSymptomMissingPainLevelMessage), findsNothing);
      expect(find.text(kSymptomNothingSelectedMessage), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // The wire funnel — every control wired to the setter it claims
  // -------------------------------------------------------------------------
  //
  // T20a proves the assembler maps a FORM correctly. Only a screen-level test
  // can prove the LOCATION chips reach `setRegion` rather than
  // `togglePainType`, that a chip reports its WIRE CODE rather than its
  // label, and that the notes box lands on the batch's first entry.

  testWidgets('the saved batch carries exactly what the user selected — pain '
      'row first with its own classification, then the RELATED row, with the '
      'note on the first entry', (tester) async {
    when(
      () => api.symptomsPost(
        createSymptomsRequest: any(named: 'createSymptomsRequest'),
      ),
    ).thenAnswer(apiSuccess(createSymptomsResponseFixture(), statusCode: 201));

    // Pushed, not standalone: a successful save pops, and `context.pop()`
    // needs a router above it — the shape production has.
    await _pumpPushed(tester, api: api);

    await _tapStop(tester, kSymptomPainIntensityKey, 5);
    await _tap(tester, find.text('Pelvis'));
    await _tap(tester, find.text('Sharp'));
    await _tap(tester, find.text('Food'));
    await _tap(tester, find.text('Nausea'));
    await _tapStop(tester, symptomIntensityKey('nausea'), 2);
    await _enterNotes(tester, 'worse after lunch');

    await _tap(tester, find.text(kSymptomFormSaveLabel));
    await tester.pumpAndSettle();

    final entries = _wireEntries(_capturedRequest(api));
    expect(entries, hasLength(2));

    // The pain row. `symptomCode` is OMITTED, not sent as null — that is what
    // asks the server for its `pain` default (R1).
    expect(entries[0].containsKey('symptomCode'), isFalse);
    expect(entries[0]['intensity'], 5);
    expect(entries[0]['region'], 'pelvis');
    expect(entries[0]['painTypes'], <String>['sharp']);
    expect(entries[0]['triggers'], <String>['food']);
    expect(entries[0]['notes'], 'worse after lunch');

    // The RELATED row carries ONLY its code and its own intensity — it never
    // inherits the pain row's region/painTypes/triggers, and the note is not
    // duplicated onto it (R3).
    expect(entries[1]['symptomCode'], 'nausea');
    expect(entries[1]['intensity'], 2);
    expect(entries[1].containsKey('region'), isFalse);
    expect(entries[1].containsKey('notes'), isFalse);
  });

  testWidgets('intensity 0 is a real logged value, not "not recorded"', (
    tester,
  ) async {
    when(
      () => api.symptomsPost(
        createSymptomsRequest: any(named: 'createSymptomsRequest'),
      ),
    ).thenAnswer(apiSuccess(createSymptomsResponseFixture(), statusCode: 201));

    await _pumpPushed(tester, api: api);

    await _tapStop(tester, kSymptomPainIntensityKey, 0);
    await _tap(tester, find.text(kSymptomFormSaveLabel));
    await tester.pumpAndSettle();

    final entries = _wireEntries(_capturedRequest(api));
    expect(entries, hasLength(1));
    expect(entries[0]['intensity'], 0);
  });

  // -------------------------------------------------------------------------
  // S8 — every control freezes while a save is in flight
  // -------------------------------------------------------------------------

  group('while a save is in flight', () {
    testWidgetsWithSemantics(
      'EVERY control is frozen — all 41 chips, all scales, the notes box, '
      'the CTA and the back affordance',
      (tester) async {
        when(
          () => api.symptomsPost(
            createSymptomsRequest: any(named: 'createSymptomsRequest'),
          ),
        ).thenAnswer(apiPending());

        await _pumpScreen(tester, api: api);

        await _tapStop(tester, kSymptomPainIntensityKey, 4);
        await _tap(tester, find.text('Nausea'));
        await _tapStop(tester, symptomIntensityKey('nausea'), 2);
        await _enterNotes(tester, 'note');

        await _tap(tester, find.text(kSymptomFormSaveLabel));
        // The pending answer never resolves, so nothing settles from here on.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        expect(
          _chips(tester).where((chip) => chip.enabled),
          isEmpty,
          reason:
              'a chip toggled between the POST and its response would move '
              'the very rows T20a binds the server\'s per-row messages '
              'against — the freeze is what makes that binding sound, not a '
              'courtesy',
        );
        expect(
          tester
              .widgetList<LumenIntensityScale>(find.byType(LumenIntensityScale))
              .where((scale) => scale.enabled),
          isEmpty,
        );
        expect(
          tester.widget<LumenInputField>(find.byType(LumenInputField)).enabled,
          isFalse,
        );
        expect(_cta(tester).onPressed, isNull);
        expect(
          tester.widget<IconButton>(find.byType(IconButton)).onPressed,
          isNull,
        );

        // The far end of the scroll, proven at the semantics level rather
        // than only by the widget flag: "Acne" is the LAST of the 20 RELATED
        // chips and is several viewports down.
        await tester.ensureVisible(find.text('Acne'));
        await tester.pump();
        final acne = tester.getSemantics(find.text('Acne')).getSemanticsData();
        expect(acne.flagsCollection.isEnabled, Tristate.isFalse);
        expect(acne.hasAction(SemanticsAction.tap), isFalse);
      },
    );

    testWidgets('the screen cannot be popped', (tester) async {
      final release = Completer<Response<CreateSymptomsResponse>>();
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiPending(release: release));

      await _pumpPushed(tester, api: api);

      await _tapStop(tester, kSymptomPainIntensityKey, 4);
      await _tap(tester, find.text(kSymptomFormSaveLabel));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // The system/predictive back gesture — `WidgetsBinding.handlePopRoute`
      // is the same entry point the platform uses, and it reaches
      // `Navigator.maybePop`, which consults `PopScope.canPop` freshly.
      await tester.binding.handlePopRoute();
      // A BOUNDED sequence, not one bare pump: an UNBLOCKED pop needs several
      // frames to finish its exit transition, so a single pump could not tell
      // "blocked" from "popping, mid-animation". Not `pumpAndSettle`, which
      // would hang on the spinner whenever the block genuinely holds.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byType(SymptomFormScreen),
        findsOneWidget,
        reason:
            'abandoning the route mid-write lets the batch commit while '
            'submit()\'s own `!ref.mounted` guard skips the dependent-screen '
            'refresh — every open screen then renders a day that no longer '
            'exists',
      );

      // Positive control for the assertion above, on the SAME gesture: once
      // the write resolves, `handlePopRoute()` DOES pop this route. Without
      // it the assertion could pass on a route that is simply un-poppable,
      // or in a harness where `handlePopRoute` reaches nothing at all.
      //
      // The write is released as a REJECTION, not a success (fix round 1):
      // a successful save pops the screen from the CTA's own success handler
      // via `context.pop()`, which would leave the gesture untested while
      // LOOKING like proof — the previous version of this comment claimed
      // exactly that and was false.
      release.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/symptoms'),
          type: DioExceptionType.badResponse,
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/symptoms'),
            statusCode: 400,
            data: const <String, dynamic>{
              'title': 'One or more validation errors occurred.',
              'status': 400,
              'detail': 'The request contained invalid data.',
              'errors': <String, List<String>>{
                'request': <String>['something was wrong'],
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(SymptomFormScreen),
        findsOneWidget,
        reason:
            'premise for the control below: the write has resolved and the '
            'screen is idle again, still on the route',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byType(SymptomFormScreen),
        findsNothing,
        reason:
            'the identical gesture, with nothing in flight, pops — so the '
            'assertion above is about PopScope refusing it, not about a '
            'route that could never be popped',
      );
    });
  });

  // -------------------------------------------------------------------------
  // S9 — errors bind per row, through the getters
  // -------------------------------------------------------------------------

  group('a rejected save', () {
    testWidgetsWithSemantics(
      'renders the server\'s per-row message on the RIGHT row, and nowhere '
      'else',
      (tester) async {
        when(
          () => api.symptomsPost(
            createSymptomsRequest: any(named: 'createSymptomsRequest'),
          ),
        ).thenAnswer(
          apiValidationProblem(
            fields: <String, List<String>>{
              'entries[1].intensity': <String>['must be between 0 and 10'],
            },
          ),
        );

        await _pumpScreen(tester, api: api);

        // entries[0] is the pain row, entries[1] is the RELATED row.
        await _tapStop(tester, kSymptomPainIntensityKey, 4);
        await _tap(tester, find.text('Nausea'));
        await _tapStop(tester, symptomIntensityKey('nausea'), 2);
        await _tap(tester, find.text(kSymptomFormSaveLabel));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(symptomIntensityKey('nausea')),
            matching: find.text('must be between 0 and 10'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(kSymptomPainIntensityKey),
            matching: find.text('must be between 0 and 10'),
          ),
          findsNothing,
          reason:
              'entries[1] is the RELATED row; a message that also appeared '
              'on the pain row would be the index-to-chip binding failing '
              'open',
        );
      },
    );

    testWidgets('binds to the SUBMITTED row even after the selection moved '
        'that code to a different index (R9)', (tester) async {
      // Unreachable by tapping — every setter clears the failure — so the
      // state is pinned directly: a batch of [pain, nausea] was rejected on
      // entries[1], and `bloating` has since been selected, which would put
      // NAUSEA at index 2 and BLOATING at index 1 in a batch rebuilt today.
      // A live recomputation would move the message onto Bloating.
      await _pumpScreen(
        tester,
        api: api,
        pinnedForm: const SymptomForm(
          painIntensity: 4,
          relatedIntensities: <String, int?>{'nausea': 2, 'bloating': 1},
          failure: ValidationFailure(
            fields: <String, List<String>>{
              'entries[1].intensity': <String>['must be between 0 and 10'],
            },
          ),
          submittedDrafts: <SymptomEntryDraft>[
            SymptomEntryDraft(
              symptomCode: null,
              intensity: 4,
              region: null,
              side: null,
              occurredAt: null,
            ),
            SymptomEntryDraft(
              symptomCode: 'nausea',
              intensity: 2,
              region: null,
              side: null,
              occurredAt: null,
            ),
          ],
          submittedPainIndex: 0,
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(symptomIntensityKey('nausea')),
          matching: find.text('must be between 0 and 10'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(symptomIntensityKey('bloating')),
          matching: find.text('must be between 0 and 10'),
        ),
        findsNothing,
        reason:
            'Bloating is what index 1 would hold in a batch assembled from '
            'the CURRENT selection — pointing the message there is exactly '
            'the defect R9 exists to prevent',
      );
    });

    testWidgetsWithSemantics(
      'a request-keyed cross-field message announces itself in the banner',
      (tester) async {
        when(
          () => api.symptomsPost(
            createSymptomsRequest: any(named: 'createSymptomsRequest'),
          ),
        ).thenAnswer(
          apiValidationProblem(
            fields: <String, List<String>>{
              'request': <String>['a request may contain at most 50 entries'],
            },
          ),
        );

        await _pumpScreen(tester, api: api);

        await _tapStop(tester, kSymptomPainIntensityKey, 4);
        await _tap(tester, find.text(kSymptomFormSaveLabel));
        await tester.pumpAndSettle();

        expect(find.byType(LumenErrorBanner), findsOneWidget);
        expectLiveRegion(tester, 'a request may contain at most 50 entries');
      },
    );

    testWidgets('the banner is PINNED in the footer, not carried away by the '
        'scroll view (fix round 1, amending S9)', (tester) async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: <String, List<String>>{
            'request': <String>['something was wrong'],
          },
        ),
      );

      await _pumpScreen(tester, api: api);

      await _tapStop(tester, kSymptomPainIntensityKey, 4);
      await _tap(tester, find.text(kSymptomFormSaveLabel));
      await tester.pumpAndSettle();

      expect(find.byType(LumenErrorBanner), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(LumenErrorBanner),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
        reason:
            'the user is AT the CTA when a failure arrives — that is the '
            'control they just pressed — and this screen is several '
            'viewports tall, so a banner inside the scroll view is close to '
            'no message at all. It is the same class of message as the '
            'block reason, which S7 already pins.',
      );

      // Positive control: the finder pair above CAN see a scroll ancestor,
      // so "findsNothing" is about the banner's placement rather than about
      // a probe that never matches anything.
      expect(
        find.ancestor(
          of: find.text('Pelvis'),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
      );
    });

    testWidgets('a batch-level `entries` rejection renders in the banner too', (
      tester,
    ) async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: <String, List<String>>{
            'entries': <String>['a request must contain at least one entry'],
          },
        ),
      );

      await _pumpScreen(tester, api: api);

      await _tapStop(tester, kSymptomPainIntensityKey, 4);
      await _tap(tester, find.text(kSymptomFormSaveLabel));
      await tester.pumpAndSettle();

      expect(
        find.text('a request must contain at least one entry'),
        findsOneWidget,
      );
    });

    test('kSymptomFormRetryLabel is a member of kRetryLabels', () {
      // Self-certification guard: `expectRetryReissuesOneRequest` locates the
      // control by one of `kRetryLabels`, so passing the production constant
      // into it would find whatever that constant says. This is the
      // independent check that the constant belongs to that set at all.
      expect(kRetryLabels, contains(kSymptomFormRetryLabel));
    });

    testWidgetsWithSemantics(
      'the SAME button relabels to "Try again" and re-issues exactly one '
      'request',
      (tester) async {
        final log = ApiCallLog();
        when(
          () => api.symptomsPost(
            createSymptomsRequest: any(named: 'createSymptomsRequest'),
          ),
        ).thenAnswer(
          apiScript(<ApiAnswer<CreateSymptomsResponse>>[
            apiValidationProblem<CreateSymptomsResponse>(
              fields: <String, List<String>>{
                'request': <String>['something was wrong'],
              },
            ),
            apiSuccess(createSymptomsResponseFixture(), statusCode: 201),
          ], log: log),
        );

        // Pushed: the retry's second answer succeeds, which pops.
        await _pumpPushed(tester, api: api);

        await _tapStop(tester, kSymptomPainIntensityKey, 4);
        await _tap(tester, find.text(kSymptomFormSaveLabel));
        await tester.pumpAndSettle();

        expect(find.text(kSymptomFormSaveLabel), findsNothing);
        expect(
          find.byType(FilledButton),
          findsOneWidget,
          reason:
              'the retry must BE the save button, not a second control '
              'beside it — otherwise "exactly one request" is not a '
              'meaningful thing to assert',
        );

        // No `label:` — that would make the assertion self-certifying.
        await expectRetryReissuesOneRequest(
          tester,
          requestCount: () => log.calls,
        );
      },
    );

    testWidgets('keeps every selection intact (S11)', (tester) async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: <String, List<String>>{
            'request': <String>['something was wrong'],
          },
        ),
      );

      await _pumpScreen(tester, api: api);

      await _tapStop(tester, kSymptomPainIntensityKey, 5);
      await _tap(tester, find.text('Pelvis'));
      await _tap(tester, find.text('Sharp'));
      await _tap(tester, find.text('Nausea'));
      await _tapStop(tester, symptomIntensityKey('nausea'), 2);

      await _tap(tester, find.text(kSymptomFormSaveLabel));
      await tester.pumpAndSettle();

      expect(
        _chips(tester).where((chip) => chip.selected).map((c) => c.label),
        <String>['Pelvis', 'Sharp', 'Nausea'],
      );
      expect(_scaleValueFor(tester, 'Pain level'), 5);
      expect(_scaleValueFor(tester, 'Nausea intensity'), 2);
    });
  });

  // -------------------------------------------------------------------------
  // S11 — success pops
  // -------------------------------------------------------------------------

  testWidgets('a successful save pops the screen', (tester) async {
    when(
      () => api.symptomsPost(
        createSymptomsRequest: any(named: 'createSymptomsRequest'),
      ),
    ).thenAnswer(apiSuccess(createSymptomsResponseFixture(), statusCode: 201));

    await _pumpPushed(tester, api: api);
    expect(find.byType(SymptomFormScreen), findsOneWidget);

    await _tapStop(tester, kSymptomPainIntensityKey, 4);
    await _tap(tester, find.text(kSymptomFormSaveLabel));
    await tester.pumpAndSettle();

    expect(find.byType(SymptomFormScreen), findsNothing);
    // The POSITIVE CONTROL for the `canPop` guard T21b's fix round 2 put on
    // this exit: with something to pop, a successful save still POPS, landing
    // back on the host it was pushed from. This router registers no
    // `Routes.home` at all, so a guard that had flattened every exit into
    // `go(Routes.home)` would land on go_router's unknown-route page and this
    // would fail. The rootless half — where `pop` throws and the screen
    // staying up would duplicate the batch — is
    // `test/core/router/body_map_route_test.dart`'s post-save group.
    expect(find.text('host'), findsOneWidget);
  });

  testWidgets('a FAILED save does NOT pop', (tester) async {
    when(
      () => api.symptomsPost(
        createSymptomsRequest: any(named: 'createSymptomsRequest'),
      ),
    ).thenAnswer(
      apiValidationProblem(
        fields: <String, List<String>>{
          'request': <String>['something was wrong'],
        },
      ),
    );

    await _pumpPushed(tester, api: api);

    await _tapStop(tester, kSymptomPainIntensityKey, 4);
    await _tap(tester, find.text(kSymptomFormSaveLabel));
    await tester.pumpAndSettle();

    expect(find.byType(SymptomFormScreen), findsOneWidget);
    expect(find.text(kSymptomFormRetryLabel), findsOneWidget);
  });

  testWidgets('the back affordance pops without saving', (tester) async {
    await _pumpPushed(tester, api: api);

    await _tap(tester, find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.byType(SymptomFormScreen), findsNothing);
    // The POSITIVE CONTROL for the `canPop` guard added in T21b's fix round 1:
    // with something to pop the chevron still POPS, landing back on the host
    // it was pushed from. This router registers no `Routes.home` at all, so a
    // guard that had flattened every exit into `go(Routes.home)` would land on
    // go_router's unknown-route page instead and this would fail.
    expect(find.text('host'), findsOneWidget);
    verifyNever(
      () => api.symptomsPost(
        createSymptomsRequest: any(named: 'createSymptomsRequest'),
      ),
    );
  });

  // -------------------------------------------------------------------------
  // The notes box
  // -------------------------------------------------------------------------

  testWidgets('the notes box is a multi-line field capped at the contract\'s '
      'own 2000 characters', (tester) async {
    await _pumpScreen(tester, api: api);

    final field = tester.widget<LumenInputField>(find.byType(LumenInputField));
    expect(field.maxLength, 2000);
    expect(field.minLines, greaterThan(1));
    expect(field.maxLines, greaterThan(1));
  });

  // -------------------------------------------------------------------------
  // House rule
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'the back affordance and the notes box both have accessible names',
    (tester) async {
      await _pumpScreen(tester, api: api);

      // The chevron carries its name on the ICON, never on `tooltip:` —
      // Material surfaces a tooltip as a SEPARATE semantics field, which
      // would leave this control announcing nothing. The word is
      // `MaterialLocalizations.backButtonTooltip`, the platform's own; 'Back'
      // is what that resolves to under the test locale.
      expectLabeledButton(tester, find.byType(IconButton), 'Back');

      // The notes box passes `hint: null` (P4b-T25a/fix-round-1; `hint: ''`
      // before it, and neither is announced) and its caption is
      // `announce: false`, so `LumenInputField.label` is the ONLY thing that
      // names it — nothing else in the tree would announce for it if that
      // were dropped.
      expectLabeledField(tester, find.byType(TextField), 'Notes');
    },
  );

  testWidgets('no dingbat glyphs anywhere on the screen', (tester) async {
    await _pumpScreen(tester, api: api);

    expectNoDingbats(tester, screen: 'SymptomFormScreen');
  });

  // -------------------------------------------------------------------------
  // The body-map affordance (P4b-T21b, R-20)
  // -------------------------------------------------------------------------
  //
  // **This group REPLACES T20b's tripwire, which asserted
  // `find.textContaining('body map')` is `findsNothing`.** That assertion
  // guarded a ruling — "the hint card is cut until its destination exists" —
  // which R-20 has now discharged by shipping both halves in one commit. The
  // tripwire is INVERTED rather than deleted, because deleting it would leave
  // nothing at all watching this position.
  //
  // Every claim below is stated as a LITERAL. An assertion written against
  // `kSymptomBodyMapLabel` would move with the constant it is checking and
  // could not fail — and copy that merely avoided the old tripwire's `body
  // map` substring would have left `findsNothing` green while the ruling
  // underneath it had changed. That is this phase's signature defect and it
  // is T21b's named mutation target.

  group('the body-map affordance', () {
    Future<Finder> visibleAffordance(WidgetTester tester) async {
      final Finder affordance = find.byKey(kSymptomBodyMapKey);
      await Scrollable.ensureVisible(
        tester.element(affordance),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      return affordance;
    }

    testWidgetsWithSemantics('renders, and announces the mockup\'s own copy', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      expectLabeledButton(
        tester,
        await visibleAffordance(tester),
        'Tap body map for precise location',
        exactLabel: true,
      );
    });

    testWidgetsWithSemantics('is a LAUNCHER, not a toggle — it omits '
        'SemanticsFlag.isSelected rather than announcing "not selected"', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      final SemanticsData data = tester
          .getSemantics(await visibleAffordance(tester))
          .getSemanticsData();
      expect(
        data.flagsCollection.isSelected,
        Tristate.none,
        reason:
            'passing selected: false is the exact bug T18 shipped — a screen '
            'reader then announces "not selected" for a control that was '
            'never selectable',
      );
    });

    testWidgets('navigates to screen 13', (tester) async {
      await _pumpPushed(tester, api: api);

      await tester.tap(await visibleAffordance(tester));
      await tester.pumpAndSettle();

      expect(find.byType(BodyMapScreen), findsOneWidget);
      // `skipOffstage: false` is the assertion, not a workaround: an opaque
      // pushed route takes screen 12 OFFSTAGE, and offstage-but-still-MOUNTED
      // is exactly the property that matters here — a `go` would have
      // unmounted it, dropping the last listener on the autoDispose form and
      // taking every unsent selection with it.
      expect(
        find.byType(SymptomFormScreen, skipOffstage: false),
        findsOneWidget,
        reason:
            'PUSHED, not `go`: screen 12 stays mounted underneath, which is '
            'what keeps its autoDispose form — and every unsent selection on '
            'it — alive while screen 13 writes into it',
      );
    });

    testWidgets('is the LAST element of the form body — below the notes box, '
        'and never between RELATED and Notes where it would split the input '
        'flow with a navigation control', (tester) async {
      await _pumpScreen(tester, api: api);

      // Stated STRUCTURALLY, against the form body's own child list, rather
      // than as a pixel comparison: "last" is the claim the position judgement
      // actually made, and a `dy` ordering would also be satisfied by an
      // affordance sitting anywhere below the notes box.
      final Column body = tester.widget<Column>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Column),
            )
            .first,
      );
      expect(
        find.descendant(
          of: find.byWidget(body.children.last),
          matching: find.byKey(kSymptomBodyMapKey),
        ),
        findsOneWidget,
        reason:
            'the mockup draws this card last before the CTA; the notes box '
            'has no mockup position at all, so "last" is the only reading of '
            'the mockup that survives the notes box being added',
      );

      // And the notes box really is above it — the half of the ordering that
      // the mockup does not state and this screen decided.
      expect(
        tester.getTopLeft(find.byKey(kSymptomBodyMapKey)).dy,
        greaterThan(tester.getTopLeft(find.byType(LumenInputField)).dy),
      );
    });

    testWidgets('is NOT a second IconButton — the freeze test above resolves '
        'find.byType(IconButton) to a single widget, and a second one would '
        'throw there rather than here', (tester) async {
      await _pumpScreen(tester, api: api);

      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('is frozen mid-write like every other control (S8)', (
      tester,
    ) async {
      // Never completed — the in-flight state is the whole subject, exactly
      // as in the freeze test above.
      final release = Completer<Response<CreateSymptomsResponse>>();
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiPending(release: release));

      await _pumpScreen(tester, api: api);
      await _tapStop(tester, kSymptomPainIntensityKey, 4);
      await _tap(tester, find.text(kSymptomFormSaveLabel));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      expect(
        tester
            .widget<LumenSelectableRow>(find.byKey(kSymptomBodyMapKey))
            .enabled,
        isFalse,
        reason:
            'navigating away mid-write would strand the batch: this screen '
            'cannot be popped while submitting, and the affordance must not '
            'be a second way around that',
      );
    });
  });
}

/// Types [text] into the notes box.
Future<void> _enterNotes(WidgetTester tester, String text) async {
  final field = find.byType(TextField);
  await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pump();
}

/// The request the screen actually put on the wire.
CreateSymptomsRequest _capturedRequest(MockLumenApiApi api) {
  return verify(
        () => api.symptomsPost(
          createSymptomsRequest: captureAny(named: 'createSymptomsRequest'),
        ),
      ).captured.last
      as CreateSymptomsRequest;
}

/// [request]'s entries, serialized exactly as they go on the wire — the level
/// at which "omitted" and "explicit null" actually differ. `built_value`
/// drops a null member from its serialized form, so a key missing from one of
/// these maps is proof the field was OMITTED.
List<Map<String, dynamic>> _wireEntries(CreateSymptomsRequest request) {
  final encoded = standardSerializers.serializeWith(
    CreateSymptomsRequest.serializer,
    request,
  );
  final map = json.decode(json.encode(encoded)) as Map<String, dynamic>;
  return (map['entries'] as List<dynamic>)
      .map((entry) => (entry as Map<String, dynamic>))
      .toList();
}

/// Taps stop [stop] on the intensity block keyed [key].
///
/// The screen can render up to 21 scales at once and every one of them draws
/// stops labelled `0`..`10`, so a bare `find.text('7')` is ambiguous the
/// moment a single RELATED chip is selected. Each block carries its own key
/// for exactly this reason.
Future<void> _tapStop(WidgetTester tester, Key key, int stop) {
  return _tap(
    tester,
    find.descendant(of: find.byKey(key), matching: find.text('$stop')),
  );
}

/// The value currently held by the scale announcing [semanticsLabel].
int? _scaleValueFor(WidgetTester tester, String semanticsLabel) {
  return tester
      .widgetList<LumenIntensityScale>(find.byType(LumenIntensityScale))
      .firstWhere((scale) => scale.semanticsLabel == semanticsLabel)
      .value;
}
