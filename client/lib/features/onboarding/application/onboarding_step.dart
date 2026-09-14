import 'package:lumen/api/model/onboarding_state_response.dart';

// ---------------------------------------------------------------------------
// OnboardingStep — screens 3-7, in flow order
// ---------------------------------------------------------------------------

/// One step of the post-account onboarding flow.
///
/// The flow the user sees is **seven** screens long (`Step N of 7` on every
/// eyebrow from screen 1), but only five of them are steps in this sense:
/// screens 1 (welcome) and 2 (account) are pre-auth surfaces outside the
/// onboarding shell, and by the time any of these five can render, the account
/// they collect already exists. So [values] holds five members whose [number]
/// starts at 3, and [totalSteps] stays 7 — the eyebrow's denominator is the
/// flow's length, not this enum's.
///
/// **D-02 in one line:** account + last-period date are mandatory; baseline,
/// goals, hormones and notifications are skippable, and "skip" means *not
/// calling that step's endpoint at all*. So [isMandatory] is true for exactly
/// one member, and nothing here may treat an unanswered skippable step as an
/// obstacle.
///
/// Titles are the mockups' own, verbatim (`Screens/screen_0{3..7}_*.html`, the
/// `.tag` line): "Step 3 of 7 · Cycle", "… · About you", "… · Goals",
/// "… · Hormones", "… · Reminders".
enum OnboardingStep {
  /// Screen 3 — the last-period anchor. `POST /onboarding/cycle`.
  cycle(number: 3, title: 'Cycle', wireName: 'cycle'),

  /// Screen 4 — age / height / weight / endometriosis status.
  baseline(number: 4, title: 'About you'),

  /// Screen 5 — what the user came here for.
  goals(number: 5, title: 'Goals'),

  /// Screen 6 — which hormones to chart.
  hormones(number: 6, title: 'Hormones'),

  /// Screen 7 — reminders, and the screen that finishes the flow.
  notifications(number: 7, title: 'Reminders');

  const OnboardingStep({
    required this.number,
    required this.title,
    this.wireName,
  });

  /// How many screens the flow has, including the two before this enum starts.
  /// This is the "of 7" every onboarding eyebrow prints.
  static const int totalSteps = 7;

  /// The step's 1-based position in the seven-screen flow (3-7).
  final int number;

  /// The eyebrow's trailing word(s), verbatim from the mockup.
  final String title;

  /// The code this step travels under in `missingSteps` (the completion 409)
  /// and `missingMandatorySteps` (the state read), or null when the server has
  /// no code for it.
  ///
  /// **Only the mandatory step has one.** `OnboardingSteps` on the server names
  /// the mandatory set and nothing else, deliberately: a code for a skippable
  /// step would imply the client could be told it still "owes" that step, which
  /// is precisely what D-02's skippability denies. Mirroring that here means
  /// [fromWireName] cannot invent a destination out of a string nobody sends.
  final String? wireName;

  /// Whether onboarding can be completed without this step (D-02).
  bool get isMandatory => wireName != null;

  /// The step [name] identifies, or null when it is not a code the server
  /// emits.
  ///
  /// Matched exactly — the wire codes are lowercase snake_case and are compared
  /// ordinally on the server too; a case-insensitive match here would accept a
  /// string the server would never send and route the user on the strength of
  /// it.
  static OnboardingStep? fromWireName(String name) {
    for (final step in values) {
      if (step.wireName == name) return step;
    }
    return null;
  }

  /// The next step in flow order, or null on the last one.
  OnboardingStep? get next =>
      index + 1 < values.length ? values[index + 1] : null;

  /// The previous step in flow order, or null on the first one.
  ///
  /// Null on [cycle] on purpose: "back" from the first step would be screen 2,
  /// and that account has already been created — there is nothing to go back
  /// to inside the shell.
  OnboardingStep? get previous => index > 0 ? values[index - 1] : null;

  /// Whether [state] reports this step as answered.
  ///
  /// Reads the step's own boolean and nothing else. Every generated property is
  /// nullable (§C.0.2), and a null is read as **not** answered: the safe
  /// direction is to offer a step again, never to skip past the one mandatory
  /// answer and land the user on a finish button that 409s.
  bool isAnsweredIn(OnboardingStateResponse state) => switch (this) {
    OnboardingStep.cycle => state.cycleProvided == true,
    OnboardingStep.baseline => state.baselineProvided == true,
    OnboardingStep.goals => state.goalsProvided == true,
    OnboardingStep.hormones => state.hormonesProvided == true,
    OnboardingStep.notifications => state.notificationsProvided == true,
  };
}

// ---------------------------------------------------------------------------
// Resume
// ---------------------------------------------------------------------------

/// The step a returning user should land on, given `GET /onboarding/state`.
///
/// The first step [state] has no answer for, or the last step when every one of
/// them is answered — the last step is where finishing lives, so a user who has
/// answered everything but never pressed finish must land there rather than
/// falling off the end of the flow.
///
/// **A skipped step is indistinguishable from an unanswered one**, and that is
/// a property of the contract rather than a gap here: skipping writes no rows,
/// so the wire carries no trace of it. A user who skipped baseline and then
/// closed the app during goals is therefore offered baseline again. That is the
/// only behaviour `GET /onboarding/state` can support, it costs one tap, and
/// the alternative — remembering skips client-side — would invent a second,
/// device-local answer to a question the server already answers.
OnboardingStep resumeStepFrom(OnboardingStateResponse state) {
  for (final step in OnboardingStep.values) {
    if (!step.isAnsweredIn(state)) return step;
  }
  return OnboardingStep.values.last;
}
