// ---------------------------------------------------------------------------
// FLOW · onboarding resume — cold start → the gate → the step that is owed,
// and back out again (P4b-T24, R-06 (i), ruling R1.1)
// ---------------------------------------------------------------------------
//
// **What this file uniquely proves.** `resumeStepFrom` has a unit test, the
// redirect has a truth-table test, the shell has widget tests, and
// `onboarding_back_navigation_test.dart` pins the step-write refresh at the
// REPOSITORY boundary. What none of them can do is start the app cold and let
// the real thing decide where the session lands:
//
//  1. **The gate is two facts, not one.** `MeResponse.onboardingCompleted`
//     decides whether the user is inside the flow at all (`lumenRedirect`), and
//     `GET /onboarding/state` decides which step they land on
//     (`resumeStepFrom`). Every test below crosses both — including the control
//     that a COMPLETED user never sees the flow, without which "always shows
//     onboarding" would pass all five resume tests.
//  2. **One resume read for the whole flow.** The shell reads
//     `GET /onboarding/state` once and every step prefills from that value,
//     kept current by `OnboardingFlowController.recordGoalsSaved` and its
//     siblings. T8b's review found a live DATA-LOSS path in exactly this seam:
//     `POST /onboarding/goals` is a FULL REPLACE, so a step that came back
//     seeded from the PRE-save read does not merely show stale data — it makes
//     the next request's body destroy the answer the user gave. That is
//     asserted here on the WIRE, twice, which is where the destruction would be
//     visible.
//  3. **Finishing opens the gate without another round trip.**
//     `POST /onboarding/complete` calls `markCompleted()` so the router lets the
//     user out immediately; a second `GET /me` would be a re-read of a profile
//     the server has just changed, and the cached copy is still stale.
//
// R3 — nothing settles; frame counts are stated.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/save_goals_request.dart';
import 'package:lumen/api/model/save_onboarding_cycle_request.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/presentation/baseline_screen.dart';
import 'package:lumen/features/onboarding/presentation/cycle_setup_screen.dart';
import 'package:lumen/features/onboarding/presentation/goals_screen.dart';
import 'package:lumen/features/onboarding/presentation/hormones_screen.dart';
import 'package:lumen/features/onboarding/presentation/notifications_screen.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';

import '../support/harness.dart';
import 'flow_harness.dart';

// ---------------------------------------------------------------------------
// Finders
// ---------------------------------------------------------------------------

/// The SHELL's back affordance, not a step's own control: screen 3 draws its
/// own `Icons.chevron_left` for the previous month, so the icon alone does not
/// identify this one. `Back` is `MaterialLocalizations.backButtonTooltip`.
final Finder _shellBack = find.byWidgetPredicate(
  (Widget widget) =>
      widget is Icon &&
      widget.icon == Icons.chevron_left &&
      widget.semanticLabel == 'Back',
  description: "the onboarding shell's back affordance",
);

/// The step's own CTA — every step body has exactly one `FilledButton` except
/// screen 7, which has two and is addressed by key instead.
final Finder _stepCta = find.descendant(
  of: find.byType(OnboardingShellScreen),
  matching: find.byType(FilledButton),
);

Future<void> _tapAndSettleStep(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  // Three frames: the POST resolves, the flow records what the server stored,
  // and the next step's own build runs.
  await pumpFlowFrames(tester, 3);
}

/// The step the real flow controller is on — the value the shell renders from,
/// read rather than inferred from a rendered string.
OnboardingStep _step(FlowWorld world) =>
    world.container.read(onboardingFlowControllerProvider).value!.step;

// ---------------------------------------------------------------------------
// The five resume points
// ---------------------------------------------------------------------------

/// One row per step: what `GET /onboarding/state` reports as already answered,
/// and the screen that must therefore be showing.
typedef _ResumeCase = ({
  OnboardingStep step,
  Type screen,
  _ProvidedFlags flags,
});

/// The four `*Provided` booleans a case has to vary — `notificationsProvided`
/// is false in every one of them, because a state with all five answered is
/// `completed`, which is a different test.
typedef _ProvidedFlags = ({
  bool cycle,
  bool baseline,
  bool goals,
  bool hormones,
});

const List<_ResumeCase> _resumeCases = <_ResumeCase>[
  (
    step: OnboardingStep.cycle,
    screen: CycleSetupScreen,
    flags: (cycle: false, baseline: false, goals: false, hormones: false),
  ),
  (
    step: OnboardingStep.baseline,
    screen: BaselineScreen,
    flags: (cycle: true, baseline: false, goals: false, hormones: false),
  ),
  (
    step: OnboardingStep.goals,
    screen: GoalsScreen,
    flags: (cycle: true, baseline: true, goals: false, hormones: false),
  ),
  (
    step: OnboardingStep.hormones,
    screen: HormonesScreen,
    flags: (cycle: true, baseline: true, goals: true, hormones: false),
  ),
  (
    step: OnboardingStep.notifications,
    screen: NotificationsScreen,
    flags: (cycle: true, baseline: true, goals: true, hormones: true),
  ),
];

void main() {
  // -------------------------------------------------------------------------
  // R1.1 — every step, not just one
  // -------------------------------------------------------------------------

  for (final _ResumeCase testCase in _resumeCases) {
    testWidgets('a cold start resumes on step ${testCase.step.number} '
        '(${testCase.step.title}) when that is the first step the server has no '
        'answer for', (WidgetTester tester) async {
      final world = FlowWorld()
        // The gate's own fact: this account has not finished onboarding.
        ..me = meResponseFixture(onboardingCompleted: false)
        ..onboardingState = onboardingStateFixture(
          cycleProvided: testCase.flags.cycle,
          baselineProvided: testCase.flags.baseline,
          goalsProvided: testCase.flags.goals,
          hormonesProvided: testCase.flags.hormones,
          notificationsProvided: false,
        );

      await world.mount(tester);

      expect(find.byType(OnboardingShellScreen), findsOneWidget);
      expect(
        find.byType(DashboardScreen),
        findsNothing,
        reason:
            'the gate is closed — an un-onboarded user must not reach the '
            'authed default, whatever location they asked for',
      );
      expect(_step(world), testCase.step);
      expect(find.byType(testCase.screen), findsOneWidget);

      // The two reads the gate is made of, in order, and each exactly once.
      expect(world.wire.take(2).toList(), <String>[
        'GET /me',
        'GET /onboarding/state',
      ]);
      expect(world.countOf('GET /onboarding/state'), 1);
      expect(world.countOf('GET /me'), 1);

      // The dashboard never built: a month-windowed calendar read is its
      // signature, and an un-onboarded user must not be paying for one.
      expect(world.wire.where((String op) => op.contains('from=')), isEmpty);
    });
  }

  // -------------------------------------------------------------------------
  // The control that makes those five discriminating
  // -------------------------------------------------------------------------

  testWidgets(
    'a COMPLETED account never enters the flow — and never pays for the '
    'resume read at all',
    (WidgetTester tester) async {
      final world = FlowWorld()
        ..me = meResponseFixture(onboardingCompleted: true)
        // The server would still answer this read; nothing may ask for it.
        ..onboardingState = onboardingStateFixture(completed: true);

      await world.mount(tester);

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(OnboardingShellScreen), findsNothing);
      expect(
        world.countOf('GET /onboarding/state'),
        0,
        reason:
            'the flow controller is autoDispose and never mounts, so its read '
            'must never be issued — the gate is decided by /me alone',
      );
    },
  );

  // -------------------------------------------------------------------------
  // The T8b seam, at the wire — step 3
  // -------------------------------------------------------------------------

  testWidgets(
    'the anchor saved on step 3 is what step 3 shows when the user walks back '
    'to it — with the resume read issued exactly ONCE for the whole flow',
    (WidgetTester tester) async {
      final world = FlowWorld()
        ..me = meResponseFixture(onboardingCompleted: false)
        // Nothing answered yet, and — deliberately — the state response is
        // NEVER updated below. The only way step 3 can come back holding the
        // saved anchor is the flow's own record of what the write stored.
        ..onboardingState = onboardingStateFixture();

      await world.mount(tester);
      expect(_step(world), OnboardingStep.cycle);
      expect(find.byType(CycleSetupScreen), findsOneWidget);

      // April 2026 is the month the calendar opens on (the server's today is
      // 2026-04-20), so the cell labelled 15 is the 15th of it. Asserted to be
      // unique first: screen 3 also draws cycle-length numbers, and a finder
      // that silently matched one of those would tap the wrong control.
      final Finder day15 = find.descendant(
        of: find.byType(CycleSetupScreen),
        matching: find.text('15'),
      );
      expect(day15, findsOneWidget);
      await tester.ensureVisible(day15);
      await tester.pump();
      await tester.tap(day15);
      await tester.pump();

      await _tapAndSettleStep(tester, _stepCta);

      // --- what reached the wire ------------------------------------------
      expect(world.onboardingCyclePosts, hasLength(1));
      expect(
        wireBody(
          SaveOnboardingCycleRequest.serializer,
          world.onboardingCyclePosts.single,
        ),
        <String, dynamic>{'lastPeriodStart': '2026-04-15'},
        reason:
            'ONE key. The user touched the calendar and nothing else, and this '
            'endpoint MERGES — so the two self-reports the screen READ from '
            '`GET /settings/cycle` (28 days, `somewhat`) must NOT ride along. '
            'A body that re-asserted them would be writing values the user '
            'never entered on this screen, which is the same shape as the '
            'never-paused echo T22a found on screen 32.',
      );

      expect(_step(world), OnboardingStep.baseline);
      expect(find.byType(BaselineScreen), findsOneWidget);

      // --- walk back ------------------------------------------------------
      final CycleSetupController left = world.container.read(
        cycleSetupControllerProvider.notifier,
      );

      await tester.tap(_shellBack);
      await pumpFlowFrames(tester, 4);

      expect(_step(world), OnboardingStep.cycle);
      expect(
        identical(
          world.container.read(cycleSetupControllerProvider.notifier),
          left,
        ),
        isFalse,
        reason:
            'every step controller is autoDispose, so leaving DISPOSED this '
            'one — the assertion below is about what the REBUILT one seeded '
            'from, and without this premise it could pass on a controller '
            'that was never rebuilt',
      );

      expect(
        world.container
            .read(cycleSetupControllerProvider)
            .value!
            .answers
            .lastPeriodStart,
        Date(2026, 4, 15),
        reason:
            '`lastPeriodStart` is REQUIRED on every post, so a stale anchor is '
            'not a stale view — it travels on the next save and drags a '
            'corrected date back',
      );

      expect(
        world.countOf('GET /onboarding/state'),
        1,
        reason:
            'the shell reads the resume state ONCE; a second read here would '
            'mean the prefill came from the network rather than from the flow, '
            'and the flow is what a step write updates',
      );
    },
  );

  // -------------------------------------------------------------------------
  // The T8b seam, at the wire — step 5, where the loss is destructive
  // -------------------------------------------------------------------------

  testWidgets(
    'coming back to step 5 and pressing Continue again re-posts the set the '
    'user CHOSE — the FULL REPLACE never carries the pre-save selection back',
    (WidgetTester tester) async {
      final world = FlowWorld()
        ..me = meResponseFixture(onboardingCompleted: false)
        ..onboardingState = onboardingStateFixture(
          cycleProvided: true,
          baselineProvided: true,
          // The D-14 seed the server holds for a user who has never answered:
          // the first two ON. Every assertion below is the opposite of it.
          goals: kSeededGoals,
        );

      await world.mount(tester);
      expect(_step(world), OnboardingStep.goals);

      // The user's real answer: neither default, `just_curious` only.
      for (final String code in <String>[
        'manage_symptoms',
        'understand_hormones',
        'just_curious',
      ]) {
        final Finder tile = find.byKey(goalTileKey(code));
        await tester.ensureVisible(tile);
        await tester.pump();
        await tester.tap(tile);
        await tester.pump();
      }

      await _tapAndSettleStep(tester, _stepCta);

      expect(_step(world), OnboardingStep.hormones);
      expect(
        wireBody(
          SaveGoalsRequest.serializer,
          world.onboardingGoalsPosts.single,
        ),
        <String, dynamic>{
          'goals': <String>['just_curious'],
        },
      );

      await tester.tap(_shellBack);
      await pumpFlowFrames(tester, 4);
      expect(_step(world), OnboardingStep.goals);

      await _tapAndSettleStep(tester, _stepCta);

      expect(world.onboardingGoalsPosts, hasLength(2));
      expect(
        wireBody(SaveGoalsRequest.serializer, world.onboardingGoalsPosts.last),
        <String, dynamic>{
          'goals': <String>['just_curious'],
        },
        reason:
            'this is the request a stale prefill would destroy the answer '
            'with: the array IS the complete desired state, so a second post '
            'carrying the pre-save pair would store `just_curious: false` and '
            'silently undo what the user asked for',
      );
    },
  );

  // -------------------------------------------------------------------------
  // The failure path
  // -------------------------------------------------------------------------

  testWidgets(
    'a resume read that fails shows the whole-surface retry rather than a '
    'guessed step, and retrying re-issues exactly ONE read',
    (WidgetTester tester) async {
      final world = FlowWorld()
        ..me = meResponseFixture(onboardingCompleted: false);
      var attempts = 0;
      world.onboardingState = onboardingStateFixture(cycleProvided: true);
      // The read fails once. `cachedRead` turns a NetworkFailure with no
      // cached value into `NetworkRequired`, which the flow controller reports
      // as an error — the resume read is what decides which step to show, so
      // there is no honest partial screen to render without it.
      world.onOnboardingState = () async {
        if (attempts++ == 0) throw flowOffline(path: '/onboarding/state');
        return world.onboardingState;
      };

      await world.mount(tester);

      expect(find.byType(OnboardingShellScreen), findsOneWidget);
      expect(find.byType(LumenErrorRetry), findsOneWidget);
      expect(
        find.byType(CycleSetupScreen),
        findsNothing,
        reason:
            'no step may be guessed: the answer to "which step" is the read '
            'that just failed',
      );
      expect(world.countOf('GET /onboarding/state'), 1);

      await expectRetryReissuesOneRequest(
        tester,
        requestCount: () => world.countOf('GET /onboarding/state'),
        settle: false,
      );
      await pumpFlowFrames(tester, 3);

      expect(world.countOf('GET /onboarding/state'), 2);
      expect(find.byType(LumenErrorRetry), findsNothing);
      expect(_step(world), OnboardingStep.baseline);
      expect(find.byType(BaselineScreen), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // Out the other side
  // -------------------------------------------------------------------------

  testWidgets(
    'finishing on step 7 opens the gate from the WRITE, not from a read — the '
    'user lands on the dashboard while /me still says they have not finished',
    (WidgetTester tester) async {
      final world = FlowWorld()
        ..me = meResponseFixture(onboardingCompleted: false)
        ..onboardingState = onboardingStateFixture(
          cycleProvided: true,
          baselineProvided: true,
          goalsProvided: true,
          hormonesProvided: true,
        );

      await world.mount(tester);
      expect(_step(world), OnboardingStep.notifications);
      expect(find.byType(NotificationsScreen), findsOneWidget);

      // "Not now" — D-02's skip: it completes and writes NO preference rows,
      // so the server's own backfill still gives this user the seeded
      // categories. An empty POST here would suppress that backfill and leave
      // them muted.
      final Finder skip = find.byKey(kNotificationsSkipKey);
      await tester.ensureVisible(skip);
      await tester.pump();
      await tester.tap(skip);
      await pumpFlowFrames(tester, 3);
      await pumpRouteTransition(tester);
      await pumpFlowFrames(tester, 3);

      expect(world.countOf('POST /onboarding/complete'), 1);
      expect(
        world.onboardingNotificationsPosts,
        isEmpty,
        reason:
            'skip means NOT CALLING the step\'s endpoint (D-02) — an empty '
            'POST would store four rows with every flag false and suppress '
            "the server's seed",
      );

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(OnboardingShellScreen), findsNothing);

      // **The gate was opened by `markCompleted()`, and this is what proves
      // it:** `GET /me` still answers `onboardingCompleted: false` — the
      // harness never flips it — and the user is on the dashboard anyway. A
      // client that waited to be told by a read would still be inside the flow
      // it just finished.
      expect(world.me.onboardingCompleted, isFalse);

      // The second `/me` is the DASHBOARD's, not the gate's, and it happens
      // because the completion write invalidated the profile key on purpose —
      // the stored profile has just changed, so the cached copy is wrong.
      // Stated here so the count is not mistaken for a re-read of the gate.
      expect(
        world.cache.invalidations,
        containsAll(<String>[CacheKeys.profile, CacheKeys.onboardingState]),
      );
      expect(
        world.wire.indexOf('POST /onboarding/complete'),
        lessThan(world.wire.lastIndexOf('GET /me')),
      );
    },
  );
}
