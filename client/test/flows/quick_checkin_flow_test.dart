// ---------------------------------------------------------------------------
// FLOW · quick check-in — screen 8 → screen 9 → (screen 8 | screen 12)
// (P4b-T24, R-06 (i), ruling R1.3)
// ---------------------------------------------------------------------------
//
// **What this file uniquely proves.** Screen 9 has unit, widget, semantics,
// golden and retry-trap coverage already, and `symptom_form_route_test.dart`
// pins the route "+ Add details" reaches. None of them can see the two seams
// this flow is about, because each end is pinned in the others:
//
//  1. **the check-in refreshes the screen it was opened from.** Screen 9 is a
//     sheet OVER screen 8, and `QuickCheckinController._refreshDependents`
//     invalidates `dashboardControllerProvider` so the dashboard re-reads the
//     day the write just changed. Every screen-9 test pins the dashboard away;
//     every dashboard test pins the controller. **The cost of the seam being
//     broken is a user who logs a 7 and watches the card behind the sheet keep
//     saying "Not logged today" for the rest of the session** — a wrong number
//     on screen with nothing to correct it.
//  2. **R-13's save-first, and T20-P's failure half.** "+ Add details" saves the
//     check-in and only then opens screen 12 — and a FAILED save does not
//     navigate at all, because screen 12 opens EMPTY and `POST /checkin/quick`
//     has no clear affordance, so leaving would discard the answer silently
//     with nothing on the next screen saying so.
//
// R2 — every assertion below names what reached the wire, in order, with the
// serialized body. The touched-only omission is asserted here as well as at the
// repository, deliberately: this is the only place it is asserted about a body
// produced by real taps on a real screen inside the real app.
//
// R3 — nothing settles. Frames are driven by hand and the counts are stated.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/quick_checkin_request.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/checkin/application/quick_checkin_controller.dart';
import 'package:lumen/features/checkin/presentation/quick_checkin_screen.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/application/symptom_form_controller.dart';
import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

import '../support/harness.dart';
import 'flow_harness.dart';

// ---------------------------------------------------------------------------
// Finders — by ROLE, never by a string the design pass could reword
// ---------------------------------------------------------------------------

/// The dashboard's Mood quick-log tile.
///
/// By its icon, not by its text: the word "Mood" appears TWICE on screen 8 —
/// once on the Mood card (a read-only readout) and once on this tile — so a
/// text finder would be ambiguous, and which of the two it resolved to would
/// depend on layout order.
final Finder _moodTile = find.widgetWithIcon(LumenSelectableRow, Icons.mood);

/// The dashboard's Symptom quick-log tile, by the same rule.
final Finder _symptomTile = find.widgetWithIcon(
  LumenSelectableRow,
  Icons.healing,
);

/// A pain stop INSIDE the sheet. The dashboard behind it draws numbers of its
/// own, so the finder is scoped to screen 9's own subtree.
Finder _painStop(int stop) => find.descendant(
  of: find.byType(QuickCheckinScreen),
  matching: find.text('$stop'),
);

/// A mood tile inside the sheet, by its ratified label (`kMoodLabels`).
Finder _moodChoice(String label) => find.descendant(
  of: find.byType(QuickCheckinScreen),
  matching: find.text(label),
);

/// The sheet's CTA, whatever it currently says.
final Finder _sheetCta = find.descendant(
  of: find.byType(QuickCheckinScreen),
  matching: find.byType(FilledButton),
);

/// Opens the sheet from the dashboard and leaves it fully laid out.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.ensureVisible(_moodTile);
  await tester.pump();
  await tester.tap(_moodTile);
  // The modal's own entrance animation, driven by hand rather than settled:
  // 250 ms is `showModalBottomSheet`'s duration
  // (`_kBottomSheetEnterDuration`, measured in the SDK — `showLumenBottomSheet`
  // overrides neither it nor the animation controller), and
  // `pumpRouteTransition` advances a stated `kFlowTransition` of 800 ms — past
  // that entrance and still an order of magnitude short of the nearest thing
  // this app schedules on a timer (the onboarding gate's 8 s bounded wait).
  await pumpRouteTransition(tester);
  expect(find.byType(LumenBottomSheet), findsOneWidget);
}

void main() {
  // -------------------------------------------------------------------------
  // Seam 1 — the write refreshes the screen underneath it
  // -------------------------------------------------------------------------

  testWidgets(
    'a saved check-in reaches the wire touched-only, invalidates the day it '
    'wrote, and the dashboard it was opened from re-reads that day',
    (WidgetTester tester) async {
      final world = FlowWorld();
      // The premise the closing assertion depends on: the server holds nothing
      // for today, so the dashboard opens saying so. Without this the "Not
      // logged today" below could be a stale render rather than the truth.
      world.months[flowMonth(DateTime(2026, 4))] = cycleCalendarFixture(
        today: Date(2026, 4, 20),
        from: Date(2026, 4, 1),
        to: Date(2026, 4, 30),
        days: const <CycleCalendarDay>[],
      );

      // The server STORES: after the check-in, the month read answers with the
      // row the write created. A harness that echoed the request instead could
      // not tell a dashboard that re-read from one that re-rendered its own
      // pre-write state.
      world.onCheckinPost = (QuickCheckinRequest request) async {
        world.months[flowMonth(DateTime(2026, 4))] = cycleCalendarFixture(
          today: Date(2026, 4, 20),
          from: Date(2026, 4, 1),
          to: Date(2026, 4, 30),
          days: <CycleCalendarDay>[
            cycleCalendarDayFixture(
              date: Date(2026, 4, 20),
              pain: request.pain,
              mood: request.mood,
            ),
          ],
        );
        return quickCheckinResponseFixture(
          day: Date(2026, 4, 20),
          pain: request.pain,
          mood: request.mood,
        );
      };

      await world.mount(tester);

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('Not logged today'), findsWidgets);

      // The cold-start traffic, in order. Stated in full once, here, because
      // everything after it is asserted as a DELTA and a delta is only
      // meaningful against a known start.
      expect(world.wire, <String>[
        'GET /me', // the onboarding gate
        kTodayOp, // sessionTodayProvider
        'GET /cycle/calendar?from=2026-04-01&to=2026-04-30',
        'GET /cycle/calendar?from=2026-03-01&to=2026-03-31',
      ]);
      // R-09's cadence sends NOTHING in P4b: `PushTokenSource` answers null, so
      // the app-start registration must not reach the wire at all.
      expect(world.countOf(kDeviceRegisterOp), 0);
      // The gate's `/me` and the dashboard's `/me` are ONE round trip — the
      // cache/in-flight layer is real here, so this is a fact rather than a
      // fixture.
      expect(world.countOf('GET /me'), 1);

      await _openSheet(tester);
      world.clearWire();

      // `0`, not `7`: D-08 makes 0 a supplied datum, and it is the value a
      // falsiness test anywhere on this path would silently drop.
      await tester.tap(_painStop(0));
      await tester.pump();
      await tester.tap(_moodChoice('Tired'));
      await tester.pump();

      await tester.tap(_sheetCta);
      // Three frames: the POST resolves, the three cache invalidations run,
      // the dashboard is invalidated. Then the sheet's own exit animation.
      await pumpFlowFrames(tester, 3);
      await pumpRouteTransition(tester);
      // Three more: the rebuilt dashboard's own read chain —
      // `sessionTodayProvider` (already pinned, so one turn), the two month
      // reads, the combining step. Stated rather than settled: if this chain
      // ever grows a round trip, this number is what reddens.
      await pumpFlowFrames(tester, 3);

      // --- what reached the wire -------------------------------------------
      expect(world.checkinPosts, hasLength(1));
      expect(
        wireBody(QuickCheckinRequest.serializer, world.checkinPosts.single),
        <String, dynamic>{'pain': 0, 'mood': 2},
        reason:
            'mood is 1-based on the wire, so the SECOND tile is 2 — a grid '
            'built on the bare list index would send `low` for `tired`, a '
            'fabricated value that looks completely real and is permanent',
      );

      // --- what the write invalidated ---------------------------------------
      expect(
        world.cache.invalidations,
        containsAll(CacheKeys.keysForDate(DateTime(2026, 4, 20))),
        reason:
            'the three keys for the day the server said it stored — not for '
            "the device's own day, and not for a day the write did not touch",
      );

      // --- the seam: the dashboard re-read that day -------------------------
      expect(
        world.wire,
        contains('GET /cycle/calendar?from=2026-04-01&to=2026-04-30'),
        reason:
            'the invalidated month must be re-fetched. If the dashboard is '
            'not invalidated the cache entry is gone but nothing asks for it '
            'again, so the screen keeps rendering the value it already held.',
      );
      expect(find.byType(QuickCheckinScreen), findsNothing);
      expect(find.byType(DashboardScreen), findsOneWidget);
      // The numbers the user just entered, on the screen they came back to.
      // `0 / 10`, not "Not logged today": `pain: 0` is a real logged value and
      // the card renders it exactly like a 3 (D-08).
      expect(find.text('0 / 10'), findsOneWidget);
      expect(find.text('Tired'), findsOneWidget);
      expect(find.text('Not logged today'), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // Seam 1, failure half
  // -------------------------------------------------------------------------

  testWidgets(
    'a REJECTED check-in leaves the sheet up over an unchanged dashboard, and '
    'the same button retries with the identical body — exactly one request',
    (WidgetTester tester) async {
      final world = FlowWorld();
      var attempts = 0;
      world.onCheckinPost = (QuickCheckinRequest request) async {
        attempts++;
        if (attempts == 1) {
          throw const ValidationFailure(
            message: 'at least one of pain or mood is required',
            detail: 'at least one of pain or mood is required',
            fields: <String, List<String>>{
              'request': <String>['at least one of pain or mood is required'],
            },
          );
        }
        return quickCheckinResponseFixture(
          day: Date(2026, 4, 20),
          pain: request.pain,
        );
      };

      await world.mount(tester);
      await _openSheet(tester);
      world.clearWire();

      await tester.tap(_painStop(4));
      await tester.pump();
      await tester.tap(_sheetCta);
      await pumpFlowFrames(tester, 3);

      // The sheet is still up, the answer is still on it, and the reason is
      // visible. A rejected write that closed the sheet would discard a value
      // this endpoint has no way to re-enter later.
      expect(find.byType(QuickCheckinScreen), findsOneWidget);
      expect(find.byType(LumenErrorBanner), findsOneWidget);
      expect(
        find.text('at least one of pain or mood is required'),
        findsOneWidget,
      );
      expect(find.text(kQuickCheckinRetryLabel), findsOneWidget);
      expect(world.checkinPosts, hasLength(1));

      // Nothing behind the sheet moved. Note exactly what is and is not being
      // claimed here: `CheckinRepository.quickCheckin` invalidates the day's
      // cache keys on EVERY failure, a 400 included, and deliberately — "even
      // a genuine rejection costs nothing extra to invalidate", where an
      // under-invalidation would leave a committed write stale for the whole
      // TTL. So the assertion is about REQUESTS, not about the cache.
      expect(
        world.cache.invalidations,
        containsAll(CacheKeys.keysForDate(DateTime(2026, 4, 20))),
        reason:
            'the rejection path invalidates by hand before rethrowing — a '
            'timed-out or malformed-200 write may already have committed',
      );
      expect(
        world.wire,
        <String>['POST /checkin/quick'],
        reason:
            'no refresh: `_refreshDependents` runs only on success, so a '
            'failed attempt costs exactly one request and no re-reads',
      );

      // The retry is the SAME control, so there is exactly one place a
      // duplicate tap could come from.
      await expectRetryReissuesOneRequest(
        tester,
        requestCount: () => world.checkinPosts.length,
        label: kQuickCheckinRetryLabel,
        settle: false,
      );
      await pumpFlowFrames(tester, 3);

      expect(world.checkinPosts, hasLength(2));
      expect(
        wireBody(QuickCheckinRequest.serializer, world.checkinPosts.last),
        wireBody(QuickCheckinRequest.serializer, world.checkinPosts.first),
        reason:
            'the retry must send what the first attempt sent — a retry that '
            'rebuilt its body from a form the failure had reset would write '
            'something the user never entered',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Seam 2 — R-13's save-first hand-off into screen 12
  // -------------------------------------------------------------------------

  testWidgets(
    '"+ Add details" SAVES the check-in first and then opens screen 12 — the '
    'save is on the wire before the route changes, and screen 12 opens EMPTY',
    (WidgetTester tester) async {
      final world = FlowWorld();
      await world.mount(tester);
      await _openSheet(tester);
      world.clearWire();

      await tester.tap(_painStop(6));
      await tester.pump();

      await tester.tap(find.text(kQuickCheckinAddDetailsLabel));
      await pumpFlowFrames(tester, 3);
      await pumpRouteTransition(tester);

      // Order is the ruling: the check-in reached the wire, and only then did
      // the route change. Asserted as the wire log rather than as two
      // independent facts, because "both happened" is true of the broken order
      // too.
      expect(world.wire.first, 'POST /checkin/quick');
      expect(world.checkinPosts, hasLength(1));
      expect(
        wireBody(QuickCheckinRequest.serializer, world.checkinPosts.single),
        <String, dynamic>{'pain': 6},
        reason:
            'mood was never touched, so it must be ABSENT — not null, not 0',
      );

      expect(find.byType(SymptomFormScreen), findsOneWidget);
      expect(find.byType(QuickCheckinScreen), findsNothing);
      expect(
        find.byType(LumenBottomSheet),
        findsNothing,
        reason:
            'the sheet is dismissed BEFORE the push — a live modal left over '
            'a full-screen route keeps its scrim swallowing taps',
      );

      // R-13's other half: screen 12 opens EMPTY. Nothing carries across,
      // because a whole-day pain score and a per-symptom intensity are
      // different tables with different meanings (D-11). The pain the user
      // just entered on screen 9 must NOT be pre-selected here.
      final SymptomForm form = world.container.read(
        symptomFormControllerProvider,
      );
      expect(form.painIntensity, isNull);
      expect(form.region, isNull);
      expect(form.relatedIntensities, isEmpty);
      expect(form.notes, isNull);
    },
  );

  testWidgets(
    'a FAILED "+ Add details" does NOT open screen 12 — the sheet stays up '
    'holding the answer, because leaving would discard it silently',
    (WidgetTester tester) async {
      final world = FlowWorld();
      world.onCheckinPost = (QuickCheckinRequest request) async {
        throw const NetworkFailure('No network connection.');
      };

      await world.mount(tester);
      await _openSheet(tester);
      world.clearWire();

      await tester.tap(_painStop(6));
      await tester.pump();
      await tester.tap(find.text(kQuickCheckinAddDetailsLabel));
      await pumpFlowFrames(tester, 3);
      await pumpRouteTransition(tester);

      expect(world.checkinPosts, hasLength(1));
      expect(
        find.byType(SymptomFormScreen),
        findsNothing,
        reason:
            'T20-P: navigating on a failed save discards the check-in the '
            'user just entered, and this endpoint has no clear affordance — '
            'nothing on screen 12 would say the answer was lost',
      );
      expect(find.byType(QuickCheckinScreen), findsOneWidget);
      expect(find.byType(LumenErrorBanner), findsOneWidget);
      // The answer is still there to retry with.
      expect(world.container.read(quickCheckinControllerProvider).pain, 6);
    },
  );

  // -------------------------------------------------------------------------
  // The other route into screen 12, for contrast — it writes NOTHING first
  // -------------------------------------------------------------------------

  testWidgets(
    "the dashboard's own Symptom tile opens screen 12 with no check-in at "
    'all — save-first belongs to the sheet, not to the destination',
    (WidgetTester tester) async {
      final world = FlowWorld();
      await world.mount(tester);
      world.clearWire();

      await tester.ensureVisible(_symptomTile);
      await tester.pump();
      await tester.tap(_symptomTile);
      await pumpRouteTransition(tester);

      expect(find.byType(SymptomFormScreen), findsOneWidget);
      expect(
        world.wire,
        isEmpty,
        reason:
            'this tile is the route for a user with no check-in to make; a '
            'write here would be one they never asked for',
      );
    },
  );
}
