// Screen 9 — the quick check-in (P4b-T18, the first client WRITE of the
// logging half).
//
// TDD (RED first). One test per fabrication path the brief names, plus the
// a11y/retry-trap obligations every P4b write screen owes. `CheckinRepository`
// and `ServerTodayRepository` are exercised FOR REAL here (only
// `LumenApiApi`/`CacheStore` are mocked) — this file therefore proves the
// SCREEN's own wiring (in particular the mood grid's `index + 1` translation)
// funnels correctly all the way to the wire, not merely that the controller
// asks the repository correctly (that half is `quick_checkin_controller_test
// .dart`'s job, and the wire-omission proof at the repository boundary is
// `checkin_repository_test.dart`'s).

import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/quick_checkin_request.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/features/checkin/presentation/quick_checkin_screen.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<MockCacheStore> _pumpScreen(
  WidgetTester tester, {
  required MockLumenApiApi api,
  bool settle = true,
}) async {
  when(
    () => api.cycleCalendarGet(from: null, to: null),
  ).thenAnswer(apiSuccess(cycleCalendarFixture()));
  final store = emptyCacheStore();

  await pumpApp(
    tester,
    settle: settle,
    home: const Scaffold(
      body: SingleChildScrollView(child: QuickCheckinScreen()),
    ),
    overrides: lumenOverrides(api: api, cacheStore: store),
  );
  return store;
}

QuickCheckinRequest _capturedRequest(MockLumenApiApi api) {
  return verify(
        () => api.checkinQuickPost(
          quickCheckinRequest: captureAny(named: 'quickCheckinRequest'),
        ),
      ).captured.last
      as QuickCheckinRequest;
}

Map<String, dynamic> _wireMap(QuickCheckinRequest request) {
  final encoded = standardSerializers.serializeWith(
    QuickCheckinRequest.serializer,
    request,
  );
  return json.decode(json.encode(encoded)) as Map<String, dynamic>;
}

void main() {
  late MockLumenApiApi api;

  setUpAll(() {
    registerFallbackValue(QuickCheckinRequest((b) => b..pain = 0));
  });

  setUp(() {
    api = MockLumenApiApi();
  });

  // -------------------------------------------------------------------------
  // Opening state — the anti-fabrication mechanical control
  // -------------------------------------------------------------------------

  group('the opening state', () {
    testWidgets('both controls are null/unselected and the CTA is disabled', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      // No pain stop is filled — probed the same way
      // lumen_intensity_scale_test.dart does, by comparing each stop's own
      // decoration to every other's rather than hard-coding the accent
      // token here.
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
      expect(
        fills.length,
        1,
        reason:
            'every stop must share the SAME (unselected) fill colour — '
            'a `?? 0` default would make stop 0 the odd one out',
      );

      expect(find.text('Save check-in'), findsOneWidget);
      final saveButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Save check-in'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(
        saveButton.onPressed,
        isNull,
        reason: 'the CTA must be disabled until something is touched',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Rule 1 — never send an untouched field (payload proof, screen level)
  // -------------------------------------------------------------------------

  group('touching only one field', () {
    testWidgets('tapping only a mood tile sends NO pain key, and the mood '
        'sent is the WIRE ORDINAL, not the tapped tile\'s list index', (
      tester,
    ) async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(quickCheckinResponseFixture(mood: 3)));

      await _pumpScreen(tester, api: api);

      // "Steady" is the THIRD tile (list index 2), wire ordinal 3 — the
      // off-by-one this test exists to catch would send 2.
      await tester.tap(find.text('Steady'));
      await tester.pump();
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      final wire = _wireMap(_capturedRequest(api));
      expect(wire.containsKey('pain'), isFalse);
      expect(
        wire['mood'],
        3,
        reason:
            'tapping the THIRD tile (list index 2) must send the WIRE '
            'ordinal 3, never the bare index 2 — that is the exact '
            'fabricated-value shape the brief names: "writes low when the '
            'user tapped tired"',
      );
    });

    testWidgets('tapping only pain sends NO mood key', (tester) async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(quickCheckinResponseFixture(pain: 6)));

      await _pumpScreen(tester, api: api);

      await tester.tap(find.text('6'));
      await tester.pump();
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      final wire = _wireMap(_capturedRequest(api));
      expect(wire['pain'], 6);
      expect(wire.containsKey('mood'), isFalse);
    });

    testWidgets('tapping pain stop 0 DOES send pain: 0 — 0 is a real datum, '
        'not "not touched"', (tester) async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(quickCheckinResponseFixture(pain: 0)));

      await _pumpScreen(tester, api: api);

      await tester.tap(find.text('0'));
      await tester.pump();
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      final wire = _wireMap(_capturedRequest(api));
      expect(wire['pain'], 0);
    });
  });

  // -------------------------------------------------------------------------
  // Rules 5/6 — CTA gating and the clear gesture
  // -------------------------------------------------------------------------

  group('the CTA', () {
    testWidgets(
      'is disabled until something is touched, and touching-then-clearing '
      'disables it again',
      (tester) async {
        await _pumpScreen(tester, api: api);

        FilledButton save() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Save check-in'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(save().onPressed, isNull);

        await tester.tap(find.text('5'));
        await tester.pump();
        expect(save().onPressed, isNotNull);

        // Tap the now-selected stop 5 again — the clear gesture.
        await tester.tap(find.text('5'));
        await tester.pump();
        expect(
          save().onPressed,
          isNull,
          reason:
              'clearing the only touched field must disable the CTA '
              'again',
        );
      },
    );

    testWidgets('tapping the selected stop clears it, and the payload then '
        'omits pain entirely', (tester) async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(quickCheckinResponseFixture(mood: 1)));

      await _pumpScreen(tester, api: api);

      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('5'));
      await tester.pump();
      // Touch mood too, so the CTA stays enabled and a save is possible —
      // otherwise this test could not tell "correctly omitted" apart from
      // "the save never happened".
      await tester.tap(find.text('Low'));
      await tester.pump();

      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      final wire = _wireMap(_capturedRequest(api));
      expect(wire.containsKey('pain'), isFalse);
      expect(wire['mood'], 1);
    });
  });

  // -------------------------------------------------------------------------
  // Refuses taps while submitting
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'every control refuses taps while a save is in flight',
    (tester) async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiPending());

      await _pumpScreen(tester, api: api);

      await tester.tap(find.text('4'));
      await tester.pump();
      await tester.tap(find.text('Save check-in'));
      await tester.pump();

      // Still "submitting" — the spinner is up, and the pending future
      // above never resolves in this test, so nothing settles further.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // A tap on a DIFFERENT stop must not change the selection while
      // submitting — proven at the semantics level: the scale's own
      // `enabled: false` makes every stop's onTap null, so the node
      // reports disabled and offers no tap action.
      await tester.tap(find.text('7'));
      await tester.pump();
      final sevenSemantics = tester
          .getSemantics(find.text('7'))
          .getSemanticsData();
      expect(sevenSemantics.flagsCollection.isEnabled, Tristate.isFalse);
      expect(sevenSemantics.hasAction(SemanticsAction.tap), isFalse);

      // The mood grid is disabled too.
      final lowSemantics = tester
          .getSemantics(find.text('Low'))
          .getSemanticsData();
      expect(lowSemantics.flagsCollection.isEnabled, Tristate.isFalse);
    },
  );

  // -------------------------------------------------------------------------
  // Failure surface
  // -------------------------------------------------------------------------

  group('a write failure', () {
    testWidgetsWithSemantics(
      'shows the server\'s cross-field message and a retry labelled '
      '"Try again" that re-issues exactly one request',
      (tester) async {
        final log = ApiCallLog();
        when(
          () => api.checkinQuickPost(
            quickCheckinRequest: any(named: 'quickCheckinRequest'),
          ),
        ).thenAnswer(
          apiScript([
            apiValidationProblem(
              fields: {
                'request': ['at least one of pain or mood is required'],
              },
            ),
            apiSuccess(quickCheckinResponseFixture(pain: 4)),
          ], log: log),
        );

        await _pumpScreen(tester, api: api);

        await tester.tap(find.text('4'));
        await tester.pump();
        await tester.tap(find.text('Save check-in'));
        await tester.pumpAndSettle();

        expectLiveRegion(tester, 'at least one of pain or mood is required');
        expect(find.byType(LumenErrorBanner), findsOneWidget);

        await expectRetryReissuesOneRequest(
          tester,
          requestCount: () => log.calls,
          label: kQuickCheckinRetryLabel,
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Success pops the sheet
  // -------------------------------------------------------------------------

  testWidgets('a successful save pops the sheet', (tester) async {
    when(
      () => api.cycleCalendarGet(from: null, to: null),
    ).thenAnswer(apiSuccess(cycleCalendarFixture()));
    when(
      () => api.checkinQuickPost(
        quickCheckinRequest: any(named: 'quickCheckinRequest'),
      ),
    ).thenAnswer(apiSuccess(quickCheckinResponseFixture(pain: 4)));

    await pumpApp(
      tester,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showLumenBottomSheet<void>(
                context: context,
                builder: (_) => const QuickCheckinScreen(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      overrides: lumenOverrides(api: api, cacheStore: emptyCacheStore()),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(LumenBottomSheet), findsOneWidget);

    await tester.tap(find.text('4'));
    await tester.pump();
    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();

    expect(find.byType(LumenBottomSheet), findsNothing);
  });

  // -------------------------------------------------------------------------
  // House rule
  // -------------------------------------------------------------------------

  testWidgets('no dingbat glyphs anywhere on the screen', (tester) async {
    await _pumpScreen(tester, api: api);

    expectNoDingbats(tester, screen: 'QuickCheckinScreen');
  });
}
