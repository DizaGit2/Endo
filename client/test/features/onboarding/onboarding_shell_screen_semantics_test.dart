// Semantics + behaviour for the onboarding shell (P4b-T8).
//
// The shell is chrome: it says where the user is, lets them step back, shows
// what finishing did, and hosts the step's own screen (T9-T13). Everything a
// screen reader gets from it is therefore chrome too — and chrome is exactly
// what tends to ship unlabelled.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_step_chrome.dart';
import 'package:lumen/shared/widgets/lumen_step_dots.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// A controller pinned to [flow] with no load at all — `build()` returns a
/// settled value, so the screen paints the step under test on frame one.
class _SettledFlow extends OnboardingFlowController {
  _SettledFlow(this.flow);

  final OnboardingFlow flow;

  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(flow);
}

OnboardingFlow _flow(OnboardingStep step, {Failure? failure}) => OnboardingFlow(
  step: step,
  state: onboardingStateFixture(cycleProvided: true),
  failure: failure,
);

List<Override> _overrides(List<Override> extra) => <Override>[
  authStatusProvider.overrideWith(
    () => FakeAuthController(AuthStatus.unauthenticated),
  ),
  ...extra,
];

Future<void> _pumpFlow(
  WidgetTester tester, {
  required OnboardingStep step,
  Failure? failure,
}) => pumpApp(
  tester,
  home: const OnboardingShellScreen(),
  overrides: _overrides([
    onboardingFlowControllerProvider.overrideWith(
      () => _SettledFlow(_flow(step, failure: failure)),
    ),
  ]),
);

void main() {
  // -------------------------------------------------------------------------
  // What the shell says about where you are
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics('it announces the step the flow is on', (
    tester,
  ) async {
    await _pumpFlow(tester, step: OnboardingStep.baseline);

    // Positive control: the eyebrow is drawn, so the announcement below is
    // about the SEMANTICS of a rendered screen rather than about a screen that
    // failed to build.
    expect(find.text('STEP 4 OF 7 · ABOUT YOU'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 4 of 7, About you'), findsOneWidget);
  });

  testWidgets('it follows the flow to whatever step it moves to', (
    tester,
  ) async {
    // One mount, two steps: the eyebrow AND the active dot must both move. A
    // shell that hard-coded either would pass the first pair and fail the
    // second, which is what makes the first pair a positive control rather
    // than a second copy of the same assertion.
    final container = await _pumpFlowContainer(
      tester,
      step: OnboardingStep.goals,
    );

    expect(find.text('STEP 5 OF 7 · GOALS'), findsOneWidget);
    expect(
      tester.widget<LumenStepDots>(find.byType(LumenStepDots)).activeIndex,
      4,
    );

    container
        .read(onboardingFlowControllerProvider.notifier)
        .goTo(OnboardingStep.notifications);
    await tester.pumpAndSettle();

    expect(find.text('STEP 7 OF 7 · REMINDERS'), findsOneWidget);
    expect(find.text('STEP 5 OF 7 · GOALS'), findsNothing);
    expect(
      tester.widget<LumenStepDots>(find.byType(LumenStepDots)).activeIndex,
      6,
    );
  });

  // -------------------------------------------------------------------------
  // Back
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'the back affordance is a named, activatable button',
    (tester) async {
      await _pumpFlow(tester, step: OnboardingStep.goals);

      // 'Back' is `MaterialLocalizations.backButtonTooltip` — the platform's own
      // word for this control, not a string this task invented.
      expectLabeledButton(tester, find.byIcon(Icons.chevron_left), 'Back');
    },
  );

  testWidgets('back walks one step, and disappears on the first one', (
    tester,
  ) async {
    // One mount, three states. The affordance is SHOWN first and then walked
    // out of existence, so the final `findsNothing` is a fact about the first
    // step rather than about a button this screen never renders.
    final container = await _pumpFlowContainer(
      tester,
      step: OnboardingStep.goals,
    );
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(
      container.read(onboardingFlowControllerProvider).value!.step,
      OnboardingStep.baseline,
    );
    expect(find.text('STEP 4 OF 7 · ABOUT YOU'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(find.text('STEP 3 OF 7 · CYCLE'), findsOneWidget);
    expect(
      find.byIcon(Icons.chevron_left),
      findsNothing,
      reason:
          'Screen 2 created an account that now exists, so "back" off the first '
          'step would offer to create it again.',
    );
  });

  // -------------------------------------------------------------------------
  // States
  // -------------------------------------------------------------------------

  testWidgetsWithSemantics(
    'the resume read reports itself while it is loading',
    (tester) async {
      final repo = _MockOnboardingRepository();
      when(repo.getState).thenAnswer(
        (_) => Completer<CacheResult<OnboardingStateResponse>>().future,
      );

      await pumpApp(
        tester,
        home: const OnboardingShellScreen(),
        settle: false,
        overrides: _overrides([
          onboardingRepositoryProvider.overrideWithValue(repo),
        ]),
      );

      expectLabeledSpinner(tester, 'Loading');
    },
  );

  testWidgetsWithSemantics(
    'a resume that cannot be read offers a retry, and the retry re-reads',
    (tester) async {
      final repo = _MockOnboardingRepository();
      final log = ApiCallLog();
      when(repo.getState).thenAnswer((_) async {
        log.record();
        return const NetworkRequired<OnboardingStateResponse>(NetworkFailure());
      });

      await pumpApp(
        tester,
        home: const OnboardingShellScreen(),
        overrides: _overrides([
          onboardingRepositoryProvider.overrideWithValue(repo),
        ]),
      );

      expect(log.calls, 1, reason: 'premise: the first read happened');
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(
        log.calls,
        2,
        reason:
            'The retry affordance must re-issue the read. A retry that only '
            'rebuilds the widget leaves the user tapping a button that does '
            'nothing.',
      );
    },
  );

  testWidgetsWithSemantics('a failed completion announces itself', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      step: OnboardingStep.notifications,
      failure: const ConflictFailure(
        message:
            'Onboarding cannot be completed until every mandatory step is '
            'answered.',
        code: 'onboarding_incomplete',
        missingSteps: ['cycle'],
      ),
    );

    expectLiveRegion(
      tester,
      'Onboarding cannot be completed until every mandatory step is answered.',
    );
  });

  testWidgets('a flow with nothing wrong shows no banner', (tester) async {
    // The positive control for the test above: the same screen, same step, no
    // failure — so "the banner is there" is a fact about the failure rather
    // than about a banner that is always on screen.
    await _pumpFlow(tester, step: OnboardingStep.notifications);

    expect(find.byType(LumenErrorBanner), findsNothing);
    expect(find.byType(LumenStepChrome), findsOneWidget);
  });

  testWidgets('renders no dingbat glyphs', (tester) async {
    await _pumpFlow(tester, step: OnboardingStep.baseline);

    expectNoDingbats(tester, screen: 'OnboardingShellScreen');
  });
}

/// [_pumpFlow], returning the container so a test can read the flow back.
Future<ProviderContainer> _pumpFlowContainer(
  WidgetTester tester, {
  required OnboardingStep step,
}) {
  return pumpApp(
    tester,
    home: const OnboardingShellScreen(),
    overrides: _overrides([
      onboardingFlowControllerProvider.overrideWith(
        () => _SettledFlow(_flow(step)),
      ),
    ]),
  );
}
