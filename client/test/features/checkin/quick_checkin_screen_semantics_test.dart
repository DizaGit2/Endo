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

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/quick_checkin_request.dart';
import 'package:lumen/api/model/quick_checkin_response.dart';
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

    // Fix round 1, M-2: mood gets the same clear gesture as pain.
    testWidgets(
      'tapping the selected MOOD tile clears it, and the payload then '
      'omits mood entirely — the mood mirror of the pain clear test above',
      (tester) async {
        when(
          () => api.checkinQuickPost(
            quickCheckinRequest: any(named: 'quickCheckinRequest'),
          ),
        ).thenAnswer(apiSuccess(quickCheckinResponseFixture(pain: 6)));

        await _pumpScreen(tester, api: api);

        await tester.tap(find.text('Low'));
        await tester.pump();
        await tester.tap(find.text('Low'));
        await tester.pump();
        // Touch pain too, so the CTA stays enabled and a save is possible.
        await tester.tap(find.text('6'));
        await tester.pump();

        await tester.tap(find.text('Save check-in'));
        await tester.pumpAndSettle();

        final wire = _wireMap(_capturedRequest(api));
        expect(wire['pain'], 6);
        expect(wire.containsKey('mood'), isFalse);
      },
    );

    testWidgets(
      'the CTA disables again after touching then clearing ONLY mood',
      (tester) async {
        await _pumpScreen(tester, api: api);

        FilledButton save() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Save check-in'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(save().onPressed, isNull);

        await tester.tap(find.text('Bright'));
        await tester.pump();
        expect(save().onPressed, isNotNull);

        await tester.tap(find.text('Bright'));
        await tester.pump();
        expect(save().onPressed, isNull);
      },
    );
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

      // …and so is "+ Add details" (P4b-T20b). It performs the SAME write
      // the CTA does, so leaving it live mid-flight would be a second route
      // to a duplicate check-in.
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text(kQuickCheckinAddDetailsLabel),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );

  // -------------------------------------------------------------------------
  // "+ Add details" — R-13's save-first route into screen 12 (P4b-T20b)
  // -------------------------------------------------------------------------
  //
  // The NAVIGATION half (save-first, and no navigation on a failed save) is
  // proven against the real route table in
  // `test/core/router/symptom_form_route_test.dart` — this sheet has no
  // GoRouter above it here. What belongs in this file is the control itself.

  group('"+ Add details"', () {
    testWidgetsWithSemantics('ships as a labelled button, gated exactly like '
        'the Save CTA', (tester) async {
      await _pumpScreen(tester, api: api);

      // Nothing touched yet: announced, but disabled and with no tap action
      // — never a live button that silently does nothing.
      expectLabeledButton(
        tester,
        find.text(kQuickCheckinAddDetailsLabel),
        kQuickCheckinAddDetailsLabel,
        requireTapAction: false,
      );
      expect(
        tester
            .getSemantics(find.text(kQuickCheckinAddDetailsLabel))
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );

      // The CTA is disabled in this state too — the two move together,
      // because "+ Add details" ALWAYS saves first (R-13) and so has
      // nothing to do until there is a check-in to save.
      await tester.tap(find.text('5'));
      await tester.pump();

      expectLabeledButton(
        tester,
        find.text(kQuickCheckinAddDetailsLabel),
        kQuickCheckinAddDetailsLabel,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Failure surface
  // -------------------------------------------------------------------------

  group('a write failure', () {
    // Fix round 1, I-1: `kQuickCheckinRetryLabel` MUST actually be a member
    // of `kRetryLabels` — the P4b exit criterion `expectRetryReissuesOneRequest`
    // exists to enforce is precisely that the retry control announces one of
    // those two specific strings, not whatever string a production constant
    // happens to hold today. Passing `label: kQuickCheckinRetryLabel` into
    // the helper (below) makes it find whatever the constant says
    // REGARDLESS of the constant's value — a self-certifying assertion that
    // stays green even if the constant drifted to something
    // `expectRetryReissuesOneRequest`'s own real callers (`find.text(label)`
    // with NO membership check against `kRetryLabels`,
    // `test/support/retry_trap.dart:33` for the constant, `:41` for
    // `find.text(label)` itself — fix round 2, item 4: `:39-40` was the
    // dartdoc/signature lines, not the call) would never find. This
    // membership check is the independent guard that actually fails if the
    // constant drifts.
    test('kQuickCheckinRetryLabel is a member of kRetryLabels', () {
      expect(kRetryLabels, contains(kQuickCheckinRetryLabel));
    });

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

        // No `label:` argument — fix round 1, I-1: passing the production
        // constant itself here would make this assertion self-certifying
        // (it would find whatever the constant says, even a wrong string).
        // Omitting it makes `findRetryAffordance` match against the REAL
        // `kRetryLabels` predicate instead, which is the one that can
        // actually fail. The membership test above is what proves the
        // constant belongs to that set in the first place.
        await expectRetryReissuesOneRequest(
          tester,
          requestCount: () => log.calls,
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
  // Fix round 1, I-3 — the sheet cannot be dismissed mid-write
  // -------------------------------------------------------------------------
  //
  // Measured against the Flutter SDK source, not assumed: the scrim tap
  // calls `Navigator.maybePop` from `modal_barrier.dart:230`
  // (`ModalBarrier`'s own `handleDismiss`); the system/predictive back
  // gesture calls the SAME method from `app.dart:1619`
  // (`_WidgetsAppState.didPopRoute`). Both reach `route.popDisposition`,
  // which consults `PopScope.canPop` freshly on every attempt — that path
  // is what `QuickCheckinScreen`'s own `PopScope` gates.
  // `widgets/routes.dart:988` is ALSO a `Navigator.maybePop` call, but a
  // THIRD, different one — `_DismissModalAction.invoke`, the
  // `DismissIntent`/Escape-key path, not the scrim or system back (fix
  // round 2, item 4: the earlier citation pointed at this line by mistake).
  // Drag-to-dismiss calls
  // `Navigator.pop` DIRECTLY from `BottomSheet`'s `onClosing`
  // (`material/bottom_sheet.dart`'s `_ModalBottomSheet.build`), bypassing
  // `PopScope` entirely and unreachable by any reactive gate — closed a
  // DIFFERENT way instead, permanently, via `enableDrag: false` at the
  // dashboard's call site (see `dashboard_screen_semantics_test.dart`).

  group('cannot be dismissed while a save is in flight', () {
    testWidgets(
      'positive control: the scrim DOES dismiss the sheet when idle',
      (tester) async {
        when(
          () => api.cycleCalendarGet(from: null, to: null),
        ).thenAnswer(apiSuccess(cycleCalendarFixture()));

        await pumpApp(
          tester,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showLumenBottomSheet<void>(
                    context: context,
                    enableDrag: false,
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

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(
          find.byType(LumenBottomSheet),
          findsNothing,
          reason:
              'premise: the scrim is a working escape hatch when '
              'nothing is in flight — this is what the test below proves '
              'gets BLOCKED, not "always blocked"',
        );
      },
    );

    testWidgets(
      'the scrim does NOT dismiss the sheet while a save is in flight',
      (tester) async {
        final release = Completer<Response<QuickCheckinResponse>>();
        when(
          () => api.cycleCalendarGet(from: null, to: null),
        ).thenAnswer(apiSuccess(cycleCalendarFixture()));
        when(
          () => api.checkinQuickPost(
            quickCheckinRequest: any(named: 'quickCheckinRequest'),
          ),
        ).thenAnswer(apiPending(release: release));

        await pumpApp(
          tester,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showLumenBottomSheet<void>(
                    context: context,
                    enableDrag: false,
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

        await tester.tap(find.text('4'));
        await tester.pump();
        await tester.tap(find.text('Save check-in'));
        await tester.pump();

        // Submitting — the pending future above never resolves here, so a
        // `pumpAndSettle()` on the indeterminate spinner would hang; a
        // fixed pump is used for everything from here on.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tapAt(const Offset(10, 10));
        // A BOUNDED sequence, not a single bare pump: if the pop were NOT
        // blocked, the route's exit transition (~250ms) needs several
        // frames to finish removing the sheet from the tree — a single
        // pump cannot tell "blocked" apart from "popping, mid-animation",
        // which is exactly the false-negative shape this probe caught on
        // its first attempt (a `canPop: true` mutation left this assertion
        // green because ONE pump never let the animation finish). Not
        // `pumpAndSettle()`: the indeterminate spinner inside the
        // STILL-open sheet animates forever whenever the block genuinely
        // holds, so settle would hang on the correct outcome.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          find.byType(LumenBottomSheet),
          findsOneWidget,
          reason:
              'PopScope(canPop: !form.submitting) must refuse the pop '
              'attempt the scrim tap makes via Navigator.maybePop while a '
              'write is in flight — dismissing here would commit the '
              'write and leave the dashboard rendering stale pain for the '
              'rest of the session',
        );

        // Let the write resolve and settle, so the test's own binding does
        // not carry a pending timer/animation into the next test.
        release.complete(
          Response<QuickCheckinResponse>(
            requestOptions: RequestOptions(path: '/checkin/quick'),
            statusCode: 200,
            data: quickCheckinResponseFixture(pain: 4),
          ),
        );
        await tester.pumpAndSettle();
      },
    );
  });

  // -------------------------------------------------------------------------
  // Fix round 1, M-4 — "Steady" is neutral, not satisfied
  // -------------------------------------------------------------------------

  group('the mood icon family does not judge the middle value', () {
    testWidgets('"Steady" uses sentiment_neutral, never sentiment_satisfied', (
      tester,
    ) async {
      await _pumpScreen(tester, api: api);

      expect(find.byIcon(Icons.sentiment_neutral), findsOneWidget);
      expect(
        find.byIcon(Icons.sentiment_satisfied),
        findsNothing,
        reason:
            'the ratified vocabulary {low, tired, steady, bright} makes '
            'no affect judgement about its middle value — rendering '
            '"Steady" as positively-valenced ("satisfied") is exactly the '
            'clinical-inference-in-the-middle-of-a-scale shape this '
            'codebase forbids elsewhere',
      );
    });

    testWidgets('the full four-tile family is the five-point scale minus '
        'sentiment_satisfied, monotone low to high', (tester) async {
      await _pumpScreen(tester, api: api);

      expect(find.byIcon(Icons.sentiment_very_dissatisfied), findsOneWidget);
      expect(find.byIcon(Icons.sentiment_dissatisfied), findsOneWidget);
      expect(find.byIcon(Icons.sentiment_neutral), findsOneWidget);
      expect(find.byIcon(Icons.sentiment_very_satisfied), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // House rule
  // -------------------------------------------------------------------------

  testWidgets('no dingbat glyphs anywhere on the screen', (tester) async {
    await _pumpScreen(tester, api: api);

    expectNoDingbats(tester, screen: 'QuickCheckinScreen');
  });
}
