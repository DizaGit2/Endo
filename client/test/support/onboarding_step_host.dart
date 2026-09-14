// ---------------------------------------------------------------------------
// onboarding_step_host.dart — the shell frame, for a test about ONE step
// (P4b-T9b)
// ---------------------------------------------------------------------------
//
// Screens 3-7 are step BODIES, not routes: `OnboardingShellScreen` owns the
// eyebrow, the back affordance, the dot row, the page insets and the box the
// body is laid out in. A test that wants to photograph or drive one step on its
// own therefore has to put that frame back, or it measures a widget under
// constraints the app never gives it.
//
// Screen 3's golden and semantics tests each hand-copied that frame, and the
// copies did what copies do: when T9b changed the shell's constraint chain,
// both would have gone on laying screen 3 out the old way and the golden would
// have photographed a layout the app no longer draws — while still passing.
//
// So this is the ONE reproduction, and the load-bearing half of it is not
// reproduced at all: the constraint chain is [OnboardingStepSlot] and the
// insets are [kOnboardingStepPadding], both imported from the shell itself.
// What is left here is only the frame the shell has no widget for — a
// `Scaffold` and a `SafeArea`.
//
// WHAT THIS DELIBERATELY DOES NOT REPRODUCE: the eyebrow, the back row, the
// failure banner and the dots. They are the shell's own, T8 has goldens for
// them, and dragging them into a step's test would photograph them twice. The
// slot is consequently TALLER here than in the app by the height of that
// chrome — this frame proves how a step behaves in its box, not how tall the
// box is on a device.

import 'package:flutter/material.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';

/// [step] inside the shell's page insets and its step slot.
Widget onboardingStepHost(Widget step) {
  return Scaffold(
    body: SafeArea(
      child: Padding(
        padding: kOnboardingStepPadding,
        child: OnboardingStepSlot(child: step),
      ),
    ),
  );
}
