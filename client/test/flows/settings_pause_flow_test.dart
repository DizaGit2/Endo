// ---------------------------------------------------------------------------
// FLOW · settings pause / resume — screen 8 → More → screen 31 → screen 32,
// both directions, all five reasons (P4b-T24, R-06 (i), ruling R1.4)
// ---------------------------------------------------------------------------
//
// **What this file uniquely proves.** Screen 32's controller, repository,
// rendering and route all have tests. What none of them can have is the state
// this flow walks THROUGH: a user who has already paused and resumed, whose
// stored row therefore carries `trackingPaused: false` together with a non-null
// `pauseReason` — the server keeps the reason on purpose, *"there is
// deliberately no CHECK tying it to `TrackingPaused`"* — and who then pauses
// again for a DIFFERENT reason. Two of this phase's defects live exactly there:
//
//  * **T22a** — a never-paused user's echo silently re-asserting six stale
//    values. Every body below is asserted as an EXACT map, so a seventh key is
//    a failure rather than something nobody looked at.
//  * **T22b** — a pause reason travelling without its flag. Resuming a user who
//    still carries a remembered reason is precisely the request that would 400
//    if the reason came along, and the pause/resume/pause/resume walk below is
//    the only place that state is reachable at all.
//
// The five reasons are walked in ONE mounted app rather than five, because the
// interesting input to reason N+1 is the row reason N left behind.
//
// **Fix round 1 adds the SAVE leg**, at the bottom of this file. The pause
// sub-flow crosses `pauseTracking`/`resumeTracking`; it never presses **Save
// cycle settings**, which is where T22a's six `touched*` guards actually live
// — so the literal T22a site survived this file 21/21 green. It does not any
// more.
//
// R3 — nothing settles; frame counts and the one route duration are stated.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/update_cycle_settings_request.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/settings/application/cycle_settings_controller.dart';
import 'package:lumen/features/settings/presentation/cycle_settings_screen.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../support/harness.dart';
import 'flow_harness.dart';

// ---------------------------------------------------------------------------
// Finders
// ---------------------------------------------------------------------------

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

/// The pause/resume control. An `OutlinedButton`, where screen 32's settings
/// save is a `FilledButton` — the two are told apart by ROLE, so a copy change
/// on either cannot silently point this flow at the wrong control.
final Finder _pauseCta = find.descendant(
  of: find.byType(CycleSettingsScreen),
  matching: find.byType(OutlinedButton),
);

/// Screen 32's SETTINGS save. A `FilledButton`, where the pause/resume
/// control is an `OutlinedButton` — same footer, told apart by ROLE.
final Finder _saveCta = find.descendant(
  of: find.byType(CycleSettingsScreen),
  matching: find.byType(FilledButton),
);

Finder _reasonChip(String label) => find.descendant(
  of: find.byType(CycleSettingsScreen),
  matching: find.text(label),
);

/// Navigates screen 8 → More → screen 31 → screen 32.
Future<void> _openCycleSettings(WidgetTester tester) async {
  await tester.tap(_tab('More'));
  // Four frames: the branch switch, screen 31's `/me` read (served from the
  // cache the gate already filled) and its rebuild.
  await pumpFlowFrames(tester, 4);
  expect(find.byType(ProfileScreen), findsOneWidget);

  await tester.ensureVisible(find.text(kCycleSettingsRowLabel));
  await tester.pump();
  await tester.tap(find.text(kCycleSettingsRowLabel));
  await pumpRouteTransition(tester);
  await pumpFlowFrames(tester, 3);
  expect(find.byType(CycleSettingsScreen), findsOneWidget);
}

/// Selects [reason]'s chip and presses the CTA.
Future<void> _pauseFor(WidgetTester tester, CyclePauseReason reason) async {
  await tester.ensureVisible(_reasonChip(reason.label));
  await tester.pump();
  await tester.tap(_reasonChip(reason.label));
  await tester.pump();
  await tester.ensureVisible(_pauseCta);
  await tester.pump();
  await tester.tap(_pauseCta);
  // Two frames: the PATCH resolves and the card rebuilds from the 200.
  await pumpFlowFrames(tester, 2);
}

Future<void> _resume(WidgetTester tester) async {
  await tester.ensureVisible(_pauseCta);
  await tester.pump();
  await tester.tap(_pauseCta);
  await pumpFlowFrames(tester, 2);
}

/// Screen 32's back affordance — the icon carries the name, so this finder is
/// the same one a screen reader would resolve.
final Finder _backChevron = find.byWidgetPredicate(
  (Widget widget) =>
      widget is Icon &&
      widget.icon == Icons.chevron_left &&
      widget.semanticLabel == 'Back',
  description: "screen 32's back affordance",
);

Map<String, dynamic> _body(UpdateCycleSettingsRequest request) =>
    wireBody(UpdateCycleSettingsRequest.serializer, request);

void main() {
  // -------------------------------------------------------------------------
  // Both directions, all five reasons, on one row that keeps its history
  // -------------------------------------------------------------------------

  testWidgets(
    'pause and resume travel as the two-key and one-key bodies and NOTHING '
    'else — for every one of the five reasons, including on a row that '
    'already remembers a different one',
    (WidgetTester tester) async {
      final world = FlowWorld();
      await world.mount(tester);
      expect(find.byType(DashboardScreen), findsOneWidget);

      await _openCycleSettings(tester);

      // The premise: an unpaused user with no remembered reason. The CTA is
      // held until a reason is chosen — an unpaused user is never paused for a
      // reason they did not name in this request.
      expect(find.text(kCycleSettingsTrackingActiveValue), findsOneWidget);
      expect(find.text(kCycleSettingsChooseReasonMessage), findsOneWidget);
      expect(tester.widget<OutlinedButton>(_pauseCta).onPressed, isNull);

      world.clearWire();

      for (final CyclePauseReason reason in CyclePauseReason.values) {
        await _pauseFor(tester, reason);

        expect(
          _body(world.settingsPatches.last),
          <String, dynamic>{
            'trackingPaused': true,
            'pauseReason': reason.wireName,
          },
          reason:
              'exactly two keys. The six settings values the screen is holding '
              'must NOT ride along: this row is a MERGE, so every key present '
              'is a value re-asserted, and re-asserting a stale one is the '
              'T22a defect. `pauseTracking` sends `trackingPaused: true` as a '
              'literal, which is what couples the reason to the act.',
        );

        // The card flipped: no chips (changing a live pause is a second
        // gesture with its own failure mode), a read-only reason row, and a
        // CTA that resumes.
        expect(find.text(kCycleSettingsTrackingPausedValue), findsOneWidget);
        expect(find.text(reason.label), findsOneWidget);
        expect(find.text(kCycleSettingsResumeLabel), findsOneWidget);
        expect(
          find.text(kCycleSettingsChooseReasonMessage),
          findsNothing,
          reason: 'nothing may block a resume — C-12, for every reason',
        );

        await _resume(tester);

        expect(
          _body(world.settingsPatches.last),
          <String, dynamic>{'trackingPaused': false},
          reason:
              'ONE key. The server keeps `pauseReason` across a resume on '
              'purpose, so the 200 this screen just adopted still carries '
              '"${reason.wireName}" — echoing it back beside '
              '`trackingPaused: false` is a 400, and `resumeTracking` takes no '
              'arguments precisely so there is nothing to echo it from.',
        );

        expect(find.text(kCycleSettingsTrackingActiveValue), findsOneWidget);
        expect(find.text(kCycleSettingsPauseLabel), findsOneWidget);
      }

      // Ten writes, ten requests — no write fired twice, and nothing else
      // reached the wire. In particular the pause did NOT refresh the
      // dashboard or the calendar: `phasesUnavailable` still has no reader
      // outside this feature in P4b, so refreshing them would be re-fetching
      // for a change nothing renders.
      expect(world.wire, List<String>.filled(10, 'PATCH /settings/cycle'));
      expect(
        world.cache.invalidations.toSet(),
        <String>{CacheKeys.cycleSettings},
        reason:
            'the settings key is the whole of what has gone stale; a pause '
            'writes nothing else',
      );

      // The row the walk left behind is the state the next pause starts from,
      // and it is the dangerous one: unpaused, with a remembered reason.
      expect(world.cycleSettings.trackingPaused, isFalse);
      expect(world.cycleSettings.pauseReason, CyclePauseReason.other.wireName);
    },
  );

  // -------------------------------------------------------------------------
  // The failure path
  // -------------------------------------------------------------------------

  testWidgets(
    'a REJECTED pause leaves the user unpaused with the reason still chosen, '
    'and the retry sends the IDENTICAL two-key body — exactly once',
    (WidgetTester tester) async {
      final world = FlowWorld();
      var attempts = 0;
      world.onSettingsPatch = (UpdateCycleSettingsRequest request) async {
        attempts++;
        if (attempts == 1) {
          throw const NetworkFailure('No network connection.');
        }
        world.cycleSettings = applyCycleSettingsPatch(
          world.cycleSettings,
          request,
        );
        return world.cycleSettings;
      };

      await world.mount(tester);
      await _openCycleSettings(tester);
      world.clearWire();

      await _pauseFor(tester, CyclePauseReason.pregnancy);

      expect(world.settingsPatches, hasLength(1));
      expect(find.byType(LumenErrorBanner), findsOneWidget);
      expect(
        find.text(kCycleSettingsTrackingActiveValue),
        findsOneWidget,
        reason:
            'the write failed, so the user is NOT paused — a card that flipped '
            'optimistically would tell them tracking had stopped when it had '
            'not',
      );
      expect(find.text(kCycleSettingsRetryLabel), findsOneWidget);

      // S-6: a NetworkFailure is AMBIGUOUS — the server may have committed
      // before the connection dropped — so the settings key is invalidated
      // even though the client saw an error. Without it the next read would
      // serve pre-write data for the rest of the TTL AND show an error.
      expect(world.cache.invalidations, contains(CacheKeys.cycleSettings));

      await expectRetryReissuesOneRequest(
        tester,
        requestCount: () => world.settingsPatches.length,
        label: kCycleSettingsRetryLabel,
        settle: false,
      );
      await pumpFlowFrames(tester, 2);

      expect(world.settingsPatches, hasLength(2));
      expect(
        _body(world.settingsPatches.last),
        _body(world.settingsPatches.first),
        reason:
            'the retry rebuilds from the PRE-write snapshot, so the reason the '
            'user chose is still the reason that travels',
      );
      expect(find.text(kCycleSettingsTrackingPausedValue), findsOneWidget);
      expect(find.text(CyclePauseReason.pregnancy.label), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // The READ that gets there — the surface T26 fixed, crossed as a flow
  // -------------------------------------------------------------------------

  testWidgets(
    'screen 32 opened from screen 31 with a failing read reaches its error '
    'body on the FRAME AFTER the failure, not after ten silent retries',
    (WidgetTester tester) async {
      final world = FlowWorld();
      var attempts = 0;
      world.onCycleSettingsGet = () async {
        if (attempts++ == 0) throw flowOffline(path: '/settings/cycle');
        return world.cycleSettings;
      };

      await world.mount(tester);

      await tester.tap(_tab('More'));
      await pumpFlowFrames(tester, 4);
      await tester.ensureVisible(find.text(kCycleSettingsRowLabel));
      await tester.pump();
      await tester.tap(find.text(kCycleSettingsRowLabel));
      await pumpRouteTransition(tester);
      // ONE frame after the transition — no more. This is the whole assertion:
      // under riverpod's own `defaultRetry` the thrown `Failure` is rebuilt ten
      // times over ~38 s while the screen publishes
      // `AsyncLoading(retrying: true)`, so at this frame there would be a
      // SPINNER and no error body. `lumenRetry` is what makes the designed
      // state arrive immediately (P4b-T26), and a flow that settled here would
      // be structurally blind to the difference.
      await tester.pump();

      expect(find.byType(LumenErrorRetry), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'a spinner here is the T26 defect: the read has already failed and '
            'the screen is hiding that behind a loading state',
      );
      expect(world.countOf('GET /settings/cycle'), 1);

      await expectRetryReissuesOneRequest(
        tester,
        requestCount: () => world.countOf('GET /settings/cycle'),
        settle: false,
      );
      await pumpFlowFrames(tester, 3);

      expect(world.countOf('GET /settings/cycle'), 2);
      expect(find.byType(LumenErrorRetry), findsNothing);
      expect(find.text(kCycleSettingsTrackingActiveValue), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // The seam back out — screen 32 is a CHILD of the More branch
  // -------------------------------------------------------------------------

  testWidgets(
    'leaving screen 32 returns to screen 31 inside the More branch, with the '
    'pause already applied and the nav bar never gone',
    (WidgetTester tester) async {
      final world = FlowWorld();
      await world.mount(tester);
      await _openCycleSettings(tester);

      // The bottom nav is on screen the whole time: screen 32 is a child of
      // the More branch, not a top-level route rendered over the whole app.
      expect(find.byType(LumenBottomNav), findsOneWidget);

      await _pauseFor(tester, CyclePauseReason.surgical);
      expect(find.text(kCycleSettingsTrackingPausedValue), findsOneWidget);

      // Screen 32's own chevron, not `tester.pageBack()`: this screen draws no
      // `AppBar`, so there is no Material `BackButton` for `pageBack` to find —
      // it is an `IconButton` whose icon carries
      // `MaterialLocalizations.backButtonTooltip` as its semantic label, which
      // is also what a screen reader announces.
      await tester.tap(_backChevron);
      await pumpRouteTransition(tester);
      await pumpFlowFrames(tester, 2);

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(CycleSettingsScreen), findsNothing);
      expect(find.byType(LumenBottomNav), findsOneWidget);

      // What the server holds is what the user asked for — asserted on the
      // stored row rather than on the screen, because the screen is gone.
      final CycleSettingsResponse stored = world.cycleSettings;
      expect(stored.trackingPaused, isTrue);
      expect(stored.pauseReason, CyclePauseReason.surgical.wireName);
      // The six settings values are untouched — no key the pause did not name
      // reached the row.
      expect(stored.avgCycleLengthDays, 28);
      expect(stored.regularity, 'somewhat');
      expect(stored.autoDetectPeriodStartEnabled, isTrue);
      expect(stored.showFertilityWindowEnabled, isFalse);
    },
  );

  // -------------------------------------------------------------------------
  // The SAVE path — the literal T22a site, which the pause sub-flow never
  // touches (fix round 1)
  // -------------------------------------------------------------------------
  //
  // The four flows R-06 named cover screen 32's PAUSE card. Nothing in them
  // ever presses **Save cycle settings**, so the exact site T22a's six
  // `if (touchedX)` guards live on was unreachable: replacing all six with
  // `if (x != null)` left this file 21/21 green while a seeded, untouched form
  // re-asserted six stale values on every save. The mutation is caught here.
  //
  // It is still a SEAM test, not a re-run of `cycle_settings_screen_semantics
  // _test.dart`. What it uniquely proves is the one thing neither existing
  // test can reach: the screen-32 semantics test stubs the repository, so it
  // never sees a wire body at all, and `cycle_settings_repository_test.dart`
  // builds its `touched*` matrix by hand, so it can never show that a form
  // SEEDED BY A REAL READ arrives with those flags false. Only a flow can put
  // a real `GET /settings/cycle` in front of a real save.

  testWidgets(
    'a screen 32 seeded from the server and saved after ONE toggle sends '
    'exactly that one key — and the value another writer changed while the '
    'form sat open survives',
    (WidgetTester tester) async {
      final world = FlowWorld();
      await world.mount(tester);

      await _openCycleSettings(tester);

      // The premise, and it is the whole discrimination: the form is FULL —
      // it is showing five real values it read from the server — and yet
      // nothing is touched, so there is nothing to send. A guard derived from
      // the value instead of the flag cannot tell this state from an edited
      // one.
      expect(find.text('28 days'), findsOneWidget);
      expect(find.text(kCycleSettingsNotSetValue), findsOneWidget);
      expect(find.text(kCycleSettingsNothingChangedMessage), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_saveCta).onPressed,
        isNull,
        reason:
            'seeding marks nothing touched — `CycleSettingsForm.seededFrom` — '
            'so a freshly-read form has nothing that would reach the wire',
      );

      // A SECOND writer moves the row while the form sits open. This is not a
      // contrived race: `user_cycle_settings` is written by
      // `POST /onboarding/cycle` and by the pause card as well as by this
      // save, and the form was seeded from a read with a 5-minute TTL. Under
      // MERGE the stale seed is harmless *only* while it stays off the wire.
      world.cycleSettings = cycleSettingsFixture(
        avgCycleLengthDays: 31,
        regularity: 'irregular',
      );

      world.clearWire();

      // ONE field. `Show fertility window` is seeded false, so this tap is
      // the only touched control on the form.
      await tester.ensureVisible(find.text(kCycleSettingsFertilityLabel));
      await tester.pump();
      await tester.tap(find.text(kCycleSettingsFertilityLabel));
      await tester.pump();
      expect(find.text(kCycleSettingsNothingChangedMessage), findsNothing);

      await tester.ensureVisible(_saveCta);
      await tester.pump();
      await tester.tap(_saveCta);
      // Two frames: the PATCH resolves and the form re-seeds from the 200.
      await pumpFlowFrames(tester, 2);

      expect(
        _body(world.settingsPatches.single),
        <String, dynamic>{'showFertilityWindowEnabled': true},
        reason:
            'ONE key. The other five values are on this screen, in this form, '
            'in memory — and every one of them is a key the server would '
            'MERGE. `if (touchedShowFertilityWindowEnabled)` is what keeps '
            'them off the wire; `if (showFertilityWindowEnabled != null)` '
            'would send all five and nothing on screen would look different.',
      );

      // The lost update, asserted where a user would eventually find it: on
      // the STORED row. The 31 and the `irregular` this form never saw are
      // still there.
      expect(world.cycleSettings.showFertilityWindowEnabled, isTrue);
      expect(
        world.cycleSettings.avgCycleLengthDays,
        31,
        reason:
            "the other writer's value. An echoed `avgCycleLengthDays: 28` "
            'would have silently put it back to what this form read minutes '
            'ago — a lost update with no error, no banner and no way for the '
            'user to know',
      );
      expect(world.cycleSettings.regularity, 'irregular');

      // One request, and the settings key is the whole of what went stale.
      expect(world.wire, <String>['PATCH /settings/cycle']);
      expect(world.cache.invalidations, <String>[CacheKeys.cycleSettings]);

      // The save re-seeded the form from its own 200, so Save is inert again
      // — a second tap cannot re-send anything, which is the same duplicate
      // door screen 12 closes by leaving.
      expect(find.text(kCycleSettingsNothingChangedMessage), findsOneWidget);
      expect(tester.widget<FilledButton>(_saveCta).onPressed, isNull);

      // …and the user-visible half of the merge: the row the screen is now
      // showing is the STORED one, so the other writer's 31 is on screen. A
      // form that had echoed its stale seed would be sitting here showing a
      // confident, wrong 28.
      expect(find.text('31 days'), findsOneWidget);
    },
  );
}
