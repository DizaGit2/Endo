// The five onboarding steps and the resume rule (P4b-T8).
//
// Screens 3-7 are one linear, resumable, partly-skippable flow. Two facts about
// it are load-bearing enough to be pinned here rather than left to the shell:
//
//   * WHICH step a returning user lands on. `GET /onboarding/state` reports one
//     boolean per step and nothing else, so "where was I" is a pure function of
//     those five booleans — and it is the only thing in this task a user can
//     notice going wrong.
//   * WHAT is mandatory. D-02: account + last-period date. The other four steps
//     are skippable and "skip" means not calling their endpoint, so a client
//     that treats an unanswered goals step as an obstacle contradicts the
//     decision outright.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';

import '../../support/harness.dart';

void main() {
  // -------------------------------------------------------------------------
  // The step table
  // -------------------------------------------------------------------------

  group('the step table matches the mockups', () {
    test('each step carries the number and title screens 3-7 print', () {
      // A table with five DIFFERENT expected pairs: no constant answer and no
      // off-by-one can satisfy all five rows at once.
      expect(
        <OnboardingStep, (int, String)>{
          for (final step in OnboardingStep.values)
            step: (step.number, step.title),
        },
        <OnboardingStep, (int, String)>{
          OnboardingStep.cycle: (3, 'Cycle'),
          OnboardingStep.baseline: (4, 'About you'),
          OnboardingStep.goals: (5, 'Goals'),
          OnboardingStep.hormones: (6, 'Hormones'),
          OnboardingStep.notifications: (7, 'Reminders'),
        },
      );
    });

    test('the flow is 7 steps long — screens 1 and 2 are the first two', () {
      // The eyebrow reads "of 7" on every screen from 1 to 7, but only 3-7 are
      // in this enum: welcome and account are pre-auth and live outside the
      // shell. Both halves are asserted so a future "just count the enum"
      // simplification fails here rather than in the copy.
      expect(OnboardingStep.totalSteps, 7);
      expect(OnboardingStep.values, hasLength(5));
      expect(OnboardingStep.values.first.number, 3);
      expect(OnboardingStep.values.last.number, OnboardingStep.totalSteps);
    });

    test('only the cycle step is mandatory (D-02)', () {
      // Asserted as a map so the four falses are stated, not implied: a
      // `isMandatory => true` bug and a `=> false` bug both fail this.
      expect(
        <OnboardingStep, bool>{
          for (final step in OnboardingStep.values) step: step.isMandatory,
        },
        <OnboardingStep, bool>{
          OnboardingStep.cycle: true,
          OnboardingStep.baseline: false,
          OnboardingStep.goals: false,
          OnboardingStep.hormones: false,
          OnboardingStep.notifications: false,
        },
      );
    });
  });

  // -------------------------------------------------------------------------
  // The wire vocabulary
  // -------------------------------------------------------------------------

  group('wire step codes', () {
    test('"cycle" is the only code the server can ever send', () {
      // `OnboardingSteps` (backend) names the MANDATORY set only, and it has
      // exactly one member: naming the skippable four would imply the client
      // could be told it still owes one, which D-02 denies.
      expect(OnboardingStep.fromWireName('cycle'), OnboardingStep.cycle);

      for (final absent in const [
        'baseline',
        'goals',
        'hormones',
        'notifications',
        'account',
        '',
        'Cycle',
      ]) {
        expect(
          OnboardingStep.fromWireName(absent),
          isNull,
          reason:
              '"$absent" is not a step code the server emits. Matching it would '
              'route the user somewhere on the strength of a string nobody '
              'sends.',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // Resume
  // -------------------------------------------------------------------------

  group('resume', () {
    test('resume walks to the first step the server has no answer for', () {
      // Five rows, five DIFFERENT answers. That is the point of the table: any
      // constant, and any rule that reads the wrong boolean, fails at least one
      // row. A single-row test would pass with `resumeStepFrom => cycle`.
      final table = <OnboardingStep, OnboardingStateResponse>{
        OnboardingStep.cycle: onboardingStateFixture(),
        OnboardingStep.baseline: onboardingStateFixture(cycleProvided: true),
        OnboardingStep.goals: onboardingStateFixture(
          cycleProvided: true,
          baselineProvided: true,
        ),
        OnboardingStep.hormones: onboardingStateFixture(
          cycleProvided: true,
          baselineProvided: true,
          goalsProvided: true,
        ),
        OnboardingStep.notifications: onboardingStateFixture(
          cycleProvided: true,
          baselineProvided: true,
          goalsProvided: true,
          hormonesProvided: true,
        ),
      };

      expect(
        {
          for (final entry in table.entries)
            resumeStepFrom(entry.value): entry.key,
        }.length,
        5,
        reason: 'The five inputs must produce five distinct landing steps.',
      );
      for (final entry in table.entries) {
        expect(resumeStepFrom(entry.value), entry.key);
      }
    });

    test(
      'a flow with every step answered lands on the last one, where finishing '
      'lives',
      () {
        // The positive control for the row above it: the same walk that returns
        // `notifications` for "nothing answered after hormones" must ALSO
        // return it when there is nothing left to answer at all — otherwise a
        // fully-answered user falls off the end of the flow with no way to
        // press finish.
        final everything = onboardingStateFixture(
          cycleProvided: true,
          baselineProvided: true,
          goalsProvided: true,
          hormonesProvided: true,
          notificationsProvided: true,
        );

        expect(resumeStepFrom(everything), OnboardingStep.notifications);
      },
    );

    test('a null boolean is "not answered", never "answered"', () {
      // Every generated property is `T?` (§C.0.2). A `?? true` anywhere in the
      // walk would skip the one mandatory step and strand the user on a finish
      // button that 409s.
      final nulls = OnboardingStateResponse((b) => b..completed = false);

      expect(nulls.cycleProvided, isNull, reason: 'premise of this test');
      expect(resumeStepFrom(nulls), OnboardingStep.cycle);
    });

    test(
      'a skipped step is indistinguishable from an unanswered one, so resume '
      'offers it again',
      () {
        // D-02: skipping means not calling the endpoint, so the wire carries no
        // trace of the skip. Landing the user back on baseline is the only
        // behaviour the contract supports — pinned so it reads as a decision
        // rather than as a bug someone later "fixes" by inventing local state.
        final skippedBaselineThenAnsweredGoals = onboardingStateFixture(
          cycleProvided: true,
          goalsProvided: true,
        );

        expect(
          resumeStepFrom(skippedBaselineThenAnsweredGoals),
          OnboardingStep.baseline,
        );
      },
    );

    test('resume ignores answers that are not step booleans', () {
      // `lastPeriodStart` is data the cycle step OWNS, not a second signal that
      // it was answered: the server derives `cycleProvided` from exactly that
      // row, and a client that read the date instead would disagree with it the
      // moment the anchor is retracted.
      final dateButNotProvided = onboardingStateFixture(
        lastPeriodStart: Date(2026, 4, 6),
      );

      expect(dateButNotProvided.lastPeriodStart, isNotNull);
      expect(dateButNotProvided.cycleProvided, isFalse);
      expect(resumeStepFrom(dateButNotProvided), OnboardingStep.cycle);
    });
  });

  // -------------------------------------------------------------------------
  // Walking the flow
  // -------------------------------------------------------------------------

  group('next / previous', () {
    test('the steps chain in flow order and stop at both ends', () {
      expect(OnboardingStep.cycle.previous, isNull);
      expect(OnboardingStep.cycle.next, OnboardingStep.baseline);
      expect(OnboardingStep.baseline.previous, OnboardingStep.cycle);
      expect(OnboardingStep.hormones.next, OnboardingStep.notifications);
      expect(OnboardingStep.notifications.next, isNull);
      expect(OnboardingStep.notifications.previous, OnboardingStep.hormones);
    });
  });
}
