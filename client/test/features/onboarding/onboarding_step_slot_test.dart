// Layout for the box the onboarding shell gives a step body (P4b-T9b).
//
// The mockups (`Screens/screen_0{3..7}_*.html`) draw the Continue button with
// `margin-top:auto`: it sits on the bottom edge of the step, however short the
// step's content is. That is a fact about the BOX, not about the button — a
// `Spacer` can only push against a bounded height, and the shell's first
// version handed the body an unbounded one, so screen 3 shipped with its CTA
// floating mid-screen above ~300 px of nothing.
//
// Two cases, because the fix has to answer both and they pull in opposite
// directions:
//
//   * a body SHORTER than the slot fills it, and its CTA lands on the bottom
//     edge — while the content itself stays at the top, which is what makes
//     this "push the CTA away" rather than "bottom-align the step";
//   * a body TALLER than the slot keeps its own height, gains nothing from the
//     `Spacer`, is not clipped, and scrolls all the way to its CTA.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// A step body of the shape screens 3-7 have
// ---------------------------------------------------------------------------

const Key _kHeading = ValueKey<String>('heading');
const Key _kContent = ValueKey<String>('content');
const Key _kCta = ValueKey<String>('cta');

/// Heading, [contentHeight] px of content, a `Spacer`, a CTA — the skeleton
/// every onboarding step shares, with the one dimension that matters as a
/// parameter.
Widget _stepBody({required double contentHeight}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const SizedBox(key: _kHeading, height: 30, width: double.infinity),
      SizedBox(key: _kContent, height: contentHeight, width: double.infinity),
      const Spacer(),
      const SizedBox(key: _kCta, height: 48, width: double.infinity),
    ],
  );
}

// ---------------------------------------------------------------------------
// The real thing
// ---------------------------------------------------------------------------

/// The flow pinned to step 3, so the shell mounts the one step that is built.
class _SettledFlow extends OnboardingFlowController {
  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(
      step: OnboardingStep.cycle,
      state: onboardingStateFixture(cycleProvided: true),
    ),
  );
}

/// Screen 3 pinned to a settled form: its two reads would otherwise leave an
/// indeterminate spinner on screen and `pumpAndSettle` would never return.
class _SettledCycleSetup extends CycleSetupController {
  @override
  AsyncValue<CycleSetupForm> build() => AsyncValue<CycleSetupForm>.data(
    CycleSetupForm(
      answers: const CycleAnswers(),
      saved: const CycleAnswers(),
      visibleMonth: DateTime(2026, 4),
    ),
  );
}

void main() {
  // -------------------------------------------------------------------------
  // The slot
  // -------------------------------------------------------------------------

  testWidgets('a body shorter than the slot puts its CTA on the bottom edge, '
      'and leaves its content at the top', (tester) async {
    await pumpApp(
      tester,
      home: onboardingStepHost(_stepBody(contentHeight: 80)),
    );

    final Rect slot = tester.getRect(find.byType(OnboardingStepSlot));
    final Rect heading = tester.getRect(find.byKey(_kHeading));
    final Rect content = tester.getRect(find.byKey(_kContent));
    final Rect cta = tester.getRect(find.byKey(_kCta));

    // Premise: this body really is shorter than its box. Without it, "the CTA
    // is at the bottom" would be a fact about a body that fills the slot
    // whatever the slot does.
    expect(
      heading.height + content.height + cta.height,
      lessThan(slot.height),
      reason: 'the short case has to actually be short',
    );

    expect(
      cta.bottom,
      moreOrLessEquals(slot.bottom, epsilon: 0.5),
      reason: "the mockup's `margin-top:auto` puts the CTA on the bottom edge",
    );

    // The control for the line above, in the same test: the body did not slide
    // down as a block. `Align(bottomCenter)` or `MainAxisAlignment.end` would
    // satisfy that assertion and fail this one, and both are the wrong screen.
    expect(
      heading.top,
      moreOrLessEquals(slot.top, epsilon: 0.5),
      reason: 'the content stays at the top; only the CTA is pushed away',
    );

    // …and the CTA is BELOW the content, not pinned over it.
    expect(cta.top, greaterThanOrEqualTo(content.bottom));
  });

  testWidgets('a body taller than the slot keeps its own height, is not '
      'clipped, and scrolls to its CTA', (tester) async {
    await pumpApp(
      tester,
      home: onboardingStepHost(_stepBody(contentHeight: 2000)),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'a body taller than its box must scroll, not overflow it',
    );

    final Rect slot = tester.getRect(find.byType(OnboardingStepSlot));
    final Rect content = tester.getRect(find.byKey(_kContent));
    final Rect cta = tester.getRect(find.byKey(_kCta));

    // Premise: this body really is taller than its box, and its CTA really is
    // off the bottom of it — the case this test is about.
    expect(content.height, greaterThan(slot.height));
    expect(cta.top, greaterThan(slot.bottom));

    // The `Spacer` had nothing to give: a body with no room left keeps its own
    // height rather than growing by a viewport.
    expect(
      cta.top,
      moreOrLessEquals(content.bottom, epsilon: 0.5),
      reason: 'the Spacer must contribute zero when the body overflows',
    );

    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.drag(
      find.byType(Scrollable),
      Offset(0, -scrollable.position.maxScrollExtent),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(_kCta)).bottom,
      moreOrLessEquals(slot.bottom, epsilon: 0.5),
      reason: 'the whole body is reachable — nothing is cut off the end',
    );
    expect(tester.takeException(), isNull);
  });

  // -------------------------------------------------------------------------
  // …and the one step that is built
  // -------------------------------------------------------------------------

  testWidgets("screen 3's Continue sits on the bottom edge of the shell's "
      'step slot', (tester) async {
    // The surface the goldens use. The default 800x600 is wider and much
    // shorter than a phone, and this assertion is about a step body that fits
    // inside its slot with room to spare.
    tester.view.physicalSize = const Size(kGoldenWidth, kGoldenHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      home: const OnboardingShellScreen(),
      overrides: <Override>[
        authStatusProvider.overrideWith(
          () => FakeAuthController(AuthStatus.unauthenticated),
        ),
        onboardingFlowControllerProvider.overrideWith(_SettledFlow.new),
        cycleSetupControllerProvider.overrideWith(_SettledCycleSetup.new),
      ],
    );

    final Rect slot = tester.getRect(find.byType(OnboardingStepSlot));
    final Rect heading = tester.getRect(
      find.text('When did your last period start?'),
    );
    final Rect regularity = tester.getRect(find.text('REGULARITY'));
    final Rect cta = tester.getRect(find.byType(FilledButton));

    // Premise: screen 3 fits inside its slot on this surface — nothing is
    // scrolled off — so where its CTA lands is a question the layout has to
    // answer rather than one the content settles by running out of room.
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      0,
    );

    // The slot alone is not enough: the shell can hand down a bounded height
    // and the step body still has to have a `Spacer` to spend it. This is the
    // assertion that fails if only one of the two halves ships.
    expect(
      cta.bottom,
      moreOrLessEquals(slot.bottom, epsilon: 0.5),
      reason: "screen 3's CTA is pinned to the bottom of the step",
    );

    // Controls, same test: the fields did not move down with it, and the CTA
    // is under the last of them rather than over it.
    expect(heading.top, moreOrLessEquals(slot.top, epsilon: 0.5));
    expect(cta.top, greaterThanOrEqualTo(regularity.bottom));
  });
}
