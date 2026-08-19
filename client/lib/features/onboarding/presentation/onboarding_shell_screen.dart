import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/presentation/baseline_screen.dart';
import 'package:lumen/features/onboarding/presentation/cycle_setup_screen.dart';
import 'package:lumen/features/onboarding/presentation/goals_screen.dart';
import 'package:lumen/features/onboarding/presentation/hormones_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_step_chrome.dart';
import 'package:lumen/shared/widgets/lumen_step_dots.dart';

/// The shell screens 3-7 mount inside — the whole of `/onboarding`.
///
/// **One route, five steps.** The router's gate funnels every
/// authenticated-but-not-onboarded location to `/onboarding` and nowhere else
/// (P4b-T1), so the flow cannot be a set of sub-routes without changing the
/// gate: `/onboarding/cycle` would be redirected straight back here. The step
/// therefore lives in [OnboardingFlowController], not in the URL, and this
/// screen renders whichever one the controller is on.
///
/// What the shell owns, and what it does not:
///
/// | owns | leaves to the step screen |
/// |---|---|
/// | the eyebrow ([LumenStepChrome]) | the step's own heading, fields and CTA |
/// | the step dots | what "Continue" does with the answer |
/// | the back affordance | each step's endpoint |
/// | the resume read and its loading / retry surfaces | |
/// | `POST /onboarding/complete` and its 409 | |
///
/// The step body is [onboardingStepContent] — an exhaustive switch. Screens 3,
/// 4, 5 and 6 are built ([CycleSetupScreen], [BaselineScreen], [GoalsScreen],
/// [HormonesScreen]); the last arm answers the placeholder, and T13 replaces
/// it.
class OnboardingShellScreen extends ConsumerWidget {
  const OnboardingShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final flow = ref.watch(onboardingFlowControllerProvider);

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: flow.when(
          loading: () => Center(
            child: CircularProgressIndicator(
              color: c.accent,
              semanticsLabel: 'Loading',
            ),
          ),
          // The resume read is what decides which step to show, so there is no
          // honest partial screen to render without it — this is the
          // whole-surface failure shape, not the in-page banner one.
          error: (error, _) => LumenErrorRetry(
            message: error is Failure
                ? error.message
                : 'Something went wrong. Please try again.',
            onRetry: () => ref.invalidate(onboardingFlowControllerProvider),
          ),
          data: (value) => _FlowBody(flow: value),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The chrome
// ---------------------------------------------------------------------------

/// Back affordance, eyebrow, the step's body, the failure banner and the dots.
///
/// The vertical order is the mockups' own (`Screens/screen_0{3..7}_*.html`):
/// the back control is absolutely positioned at the top left, the `.tag`
/// eyebrow follows, the step's content fills the middle, and the `.dt` dot row
/// sits at the very bottom under the CTA.
class _FlowBody extends ConsumerWidget {
  const _FlowBody({required this.flow});

  final OnboardingFlow flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Padding(
      padding: kOnboardingStepPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A fixed-height row whether or not it holds a control, so the
          // eyebrow does not jump 40 px between step 3 and step 4.
          SizedBox(
            height: 40,
            child: flow.step.previous == null
                ? null
                : Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      // The name lives on the ICON, not on `tooltip:`. A
                      // tooltip builds its own semantics node OUTSIDE the
                      // button's, so the control announces as an unnamed
                      // button with the label floating beside it; an icon's
                      // `semanticLabel` merges into the button node, which is
                      // the one a screen reader activates.
                      //
                      // The word itself is `MaterialLocalizations`' — the
                      // platform's own name for this control, translated
                      // wherever Flutter is, and not copy this task invented.
                      icon: Icon(
                        Icons.chevron_left,
                        semanticLabel: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                      ),
                      color: c.muted,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      onPressed: () => ref
                          .read(onboardingFlowControllerProvider.notifier)
                          .back(),
                    ),
                  ),
          ),

          LumenStepChrome(
            step: flow.step.number,
            totalSteps: OnboardingStep.totalSteps,
            title: flow.step.title,
          ),

          const SizedBox(height: 14),

          Expanded(
            child: OnboardingStepSlot(child: onboardingStepContent(flow.step)),
          ),

          // A failed `POST /onboarding/complete` is a failure of a page that is
          // still usable — the user is still on their step and can act — so it
          // is the banner, not the whole-surface retry.
          if (flow.failure != null) ...[
            const SizedBox(height: 16),
            LumenErrorBanner(message: flow.failure!.message),
          ],

          const SizedBox(height: 16),
          LumenStepDots(
            count: OnboardingStep.totalSteps,
            activeIndex: flow.step.number - 1,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The step's box
// ---------------------------------------------------------------------------

/// The page insets every onboarding step is laid out inside.
///
/// Public because a test that photographs one step body on its own has to
/// reproduce the shell's frame to lay it out as it ships, and a second copy of
/// these four numbers is a second thing to keep in step. See
/// `test/support/onboarding_step_host.dart`.
const EdgeInsets kOnboardingStepPadding = EdgeInsets.fromLTRB(28, 8, 28, 24);

/// The box a step body is given, and the thing its `Spacer()` pushes against.
///
/// A plain `Expanded(SingleChildScrollView(...))` hands the body an
/// **unbounded** height: the scroll view sizes its child to that child's own
/// height, so a `Spacer` inside it has nothing to expand into and the mockups'
/// `margin-top:auto` CTA lands wherever the content happens to end. This is the
/// chain screens 1 and 2 already ship for the same reason
/// (`welcome_screen.dart`, `account_screen.dart`): [ConstrainedBox] makes the
/// body at least as tall as the viewport, [IntrinsicHeight] lets it be taller
/// when its own content needs it, and the scroll view carries whatever spills.
///
/// So a short body fills the slot and its CTA sits on the bottom edge; a body
/// taller than the slot keeps its natural height, the `Spacer` contributes
/// nothing, and the whole thing scrolls.
class OnboardingStepSlot extends StatelessWidget {
  const OnboardingStepSlot({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// The step slot
// ---------------------------------------------------------------------------

/// The body for [step].
///
/// **One arm per screen, and that is the handoff.** The five screens are one
/// task each — T9 (screen 3, cycle, built), T10 (4, baseline, built), T11 (5,
/// goals, built), T12 (6, hormones, built), T13 (7, notifications) — and each
/// of them replaces exactly one arm here, the same one-line shape P4b-T1 left
/// this task. The
/// switch is exhaustive over [OnboardingStep] on purpose: adding a sixth step
/// would fail to compile rather than silently render nothing.
Widget onboardingStepContent(OnboardingStep step) {
  switch (step) {
    case OnboardingStep.cycle: // screen 3 — the one mandatory step (D-02)
      return const CycleSetupScreen();
    case OnboardingStep.baseline: // screen 4 — the first skippable step (D-02)
      return const BaselineScreen();
    case OnboardingStep.goals: // screen 5 — the first FULL REPLACE (§C.0.1)
      return const GoalsScreen();
    case OnboardingStep.hormones: // screen 6 — full replace with NO minimum
      return const HormonesScreen();
    case OnboardingStep.notifications: // P4b-T13 — screen 7
      return const _StepNotBuiltYet();
  }
}

/// What a step shows before its own screen exists.
///
/// **The copy is inherited, not authored.** These two strings are exactly what
/// `_OnboardingPlaceholderScreen` shipped on this route from P4b-T1 until this
/// task replaced it; the mockups and `definitions.md` carry no copy for "this
/// step is not built yet", and the phase's rule is to use the nearest sourced
/// string rather than invent one. So the route says the same thing it said
/// yesterday, inside the real chrome instead of in place of it.
class _StepNotBuiltYet extends StatelessWidget {
  const _StepNotBuiltYet();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header: true — with no fields or CTA on the step yet, this heading is
        // the only thing on the body worth jumping to.
        Semantics(
          header: true,
          child: Text(
            'Set up Lumen',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'A few questions about your cycle come next, so Lumen can '
          'make sense of what you log.',
          style: TextStyle(fontSize: 14, height: 1.5, color: c.muted),
        ),
      ],
    );
  }
}
