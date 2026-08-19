import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/goal_selection.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/data/onboarding_repository.dart';

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

/// The five ratified goal codes and the copy screen 5 draws for each.
///
/// Wire codes from `UserGoal.Codes`
/// (`backend/src/Lumen.Domain/Entities/UserGoal.cs:44-54`); titles and
/// sub-descriptions verbatim from `Screens/screen_05_goals.html`'s five `.g`
/// rows and `definitions.md:52-60`. Declaration order is the mockup's display
/// order, which is also the server's frozen order.
///
/// **This is copy, not a source of truth about what exists.** The response to
/// `POST /onboarding/goals` and `GET /onboarding/state` both list the COMPLETE
/// vocabulary in frozen order with a boolean per code, and the screen renders
/// *that* list ([GoalsForm.goals]). This enum answers two narrower questions:
/// what to draw beside a code, and what a code's flag is when the wire carried
/// no list at all. The vocabulary is append-only on the server, so a build will
/// eventually meet a code that is not here — [fromWireName] answers null for it
/// and [GoalsForm] carries it through untouched rather than dropping it.
///
/// [defaultSelected] is D-14's seed (`UserGoal.DefaultSelected`,
/// `UserGoal.cs:37-38`): the first two ON, the rest OFF.
enum GoalOption {
  manageSymptoms(
    'manage_symptoms',
    'Manage symptoms',
    'Find pain & flare patterns',
    defaultSelected: true,
  ),
  understandHormones(
    'understand_hormones',
    'Understand my hormones',
    'Compare labs to baseline',
    defaultSelected: true,
  ),
  planFertility(
    'plan_fertility',
    'Plan for fertility',
    'Track ovulation windows',
  ),
  prepareAppointments(
    'prepare_appointments',
    'Prepare for appointments',
    'Doctor-ready reports',
  ),
  justCurious('just_curious', 'Just curious', 'Learn my own rhythm');

  const GoalOption(
    this.wireName,
    this.title,
    this.description, {
    this.defaultSelected = false,
  });

  /// The code on the wire and in `user_goals.GoalCode`.
  final String wireName;

  /// The goal's title, verbatim from the mockup.
  final String title;

  /// The goal's sub-description, verbatim from the mockup.
  final String description;

  /// Whether D-14 seeds this goal ON for a user who has never answered.
  final bool defaultSelected;

  /// The member [code] names, or null — including for a code this build has
  /// never seen.
  ///
  /// Matched exactly and never case-folded: the server compares with
  /// `StringComparer.Ordinal` (`OnboardingStepsService.cs:1127-1149`), so a
  /// client that folded case would treat `Manage_Symptoms` as a goal it knows
  /// and then send a code the server answers 400 for.
  static GoalOption? fromWireName(String? code) {
    for (final GoalOption value in values) {
      if (value.wireName == code) return value;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// GoalChoice
// ---------------------------------------------------------------------------

/// One row of the server's goal list: a code, and whether the user has it
/// selected.
@immutable
class GoalChoice {
  const GoalChoice({required this.code, required this.selected});

  /// The wire code, exactly as the server sent it.
  final String code;

  /// Whether the user currently has this goal selected. `false` is a real
  /// answer — the row exists and records that the question was asked and
  /// declined (`UserGoal.cs:26-27`).
  final bool selected;

  /// The ratified copy for [code], or null when this build has none.
  GoalOption? get option => GoalOption.fromWireName(code);

  GoalChoice get toggled => GoalChoice(code: code, selected: !selected);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalChoice && other.code == code && other.selected == selected;

  @override
  int get hashCode => Object.hash(code, selected);
}

// ---------------------------------------------------------------------------
// GoalsForm
// ---------------------------------------------------------------------------

/// Everything screen 5 renders.
@immutable
class GoalsForm {
  const GoalsForm({required this.goals, this.submitting = false, this.failure});

  /// The **complete** vocabulary the server sent, in the order it sent it.
  ///
  /// Not "the selected ones", and not a client-side list filtered by what this
  /// build can draw. It is the array the next write is built from, so anything
  /// missing from here is a code the write will store as deselected.
  final List<GoalChoice> goals;

  /// Whether `POST /onboarding/goals` is in flight.
  final bool submitting;

  /// Why the last attempt failed. Cleared when the user answers again.
  final Failure? failure;

  /// The rows this build has copy for, in the server's order.
  ///
  /// A code with no [GoalOption] is **not drawn** — there is no title, no
  /// sub-description and no icon for it, and inventing one from the wire code
  /// would be authoring copy. It is still carried in [goals] and still travels
  /// in [selectedCodes]: on a FULL REPLACE endpoint, dropping an unknown code
  /// from the array is not "ignoring it", it is storing the user's answer as a
  /// deselection.
  List<GoalChoice> get drawable => <GoalChoice>[
    for (final GoalChoice choice in goals)
      if (choice.option != null) choice,
  ];

  /// Every selected code, in the server's order — the **whole body** of the
  /// write.
  ///
  /// `POST /onboarding/goals` is a FULL REPLACE (§C.0.1): the array is the
  /// complete desired state, so a still-selected goal that is left out of it is
  /// stored as deselected. This is therefore never a diff against what was read.
  List<String> get selectedCodes => <String>[
    for (final GoalChoice choice in goals)
      if (choice.selected) choice.code,
  ];

  /// Whether there is an answer to send.
  ///
  /// D-14 is multi-select **min 1, no max**, and an empty array is a 400
  /// (`select at least one goal`, `OnboardingStepResult.cs:371`). There is no
  /// maximum to mirror.
  bool get canSubmit => selectedCodes.isNotEmpty;

  /// [code] flipped; every other row left exactly as it was.
  GoalsForm toggle(String code) {
    return copyWith(
      goals: <GoalChoice>[
        for (final GoalChoice choice in goals)
          choice.code == code ? choice.toggled : choice,
      ],
    );
  }

  GoalsForm copyWith({
    List<GoalChoice>? goals,
    bool? submitting,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return GoalsForm(
      goals: goals ?? this.goals,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  /// The form for [selections] as the server sent them.
  ///
  /// **Null means the wire carried no list**, which is the one case the
  /// ratified table is a source of truth for: every generated property is
  /// nullable (§C.0.2) and a P3b-era cached `GET /onboarding/state` predates
  /// this member entirely. The fallback is `UserGoal.DefaultSelected` — the
  /// same per-code seed `OnboardingStepsService.ReadGoalsAsync` applies
  /// (`:600-614`) for a user who has never answered — so the two cannot
  /// disagree about what an unanswered step looks like.
  ///
  /// A row with a null `code` is dropped: it names nothing, so it can be
  /// neither drawn nor sent. A row with a null `selected` falls back to the
  /// same per-code seed, for the same reason: the server declares that member
  /// non-nullable and always sends it, so a null is a truncated body rather
  /// than an answer, and the seed is what the server itself would have read.
  factory GoalsForm.fromWire(Iterable<GoalSelection>? selections) {
    if (selections == null) {
      return GoalsForm(
        goals: <GoalChoice>[
          for (final GoalOption option in GoalOption.values)
            GoalChoice(code: option.wireName, selected: option.defaultSelected),
        ],
      );
    }

    return GoalsForm(
      goals: <GoalChoice>[
        for (final GoalSelection selection in selections)
          if (selection.code case final String code)
            GoalChoice(
              code: code,
              selected:
                  selection.selected ??
                  (GoalOption.fromWireName(code)?.defaultSelected ?? false),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// GoalsController
// ---------------------------------------------------------------------------

/// Screen 5's state: the goal list, the toggles, and the save.
///
/// **Shape: a plain `Notifier<GoalsForm>` with a synchronous `build()`.**
/// Classified before it was written, per the phase's controller-shape rule.
/// `build()` has no `await` at all — the resume read this screen prefills from
/// was already made by [OnboardingFlowController], and the response carries the
/// goal list whole, so there is nothing left for this controller to fetch. That
/// is the **empty-build** case, and the rule's remedy for it — a synchronous
/// build, so no build future can land on top of a synchronous `state =` — is
/// taken here to its root: there is no `AsyncValue` and therefore no build
/// future at all. Every action on this screen is a synchronous mutation (a
/// tapped chip), so that race is the one thing that would break it.
///
/// It follows that there is **no loading arm and no error arm**, and neither is
/// a missing state: the shell mounts this body only behind a settled flow, and
/// the flow's own failure surfaces are already `LumenErrorRetry` (the resume
/// read) and `LumenErrorBanner` (the completion). What can still fail here is
/// the save, and that is held on [GoalsForm.failure].
///
/// The list is read **once**, with `ref.read` rather than `ref.watch`, and that
/// is deliberate: re-seeding from a later flow change would discard whatever
/// the user had toggled — the same rule screen 4 applies to its text
/// controllers. The flow's `state` member never changes after the resume read
/// (`OnboardingFlow.copyWith` carries it through), but its step and failure do,
/// and a watch would rebuild this form on both.
///
/// `autoDispose`, because the form holds the user's own answers and the house
/// rule is that such state must not outlive the screen showing it.
class GoalsController extends Notifier<GoalsForm> {
  @override
  GoalsForm build() {
    final BuiltList<GoalSelection>? goals = ref
        .read(onboardingFlowControllerProvider)
        .value
        ?.state
        .goals;
    return GoalsForm.fromWire(goals);
  }

  // ── Answering ─────────────────────────────────────────────────────────────

  /// Flips [code], and drops whatever the last attempt said about the answers
  /// it replaced.
  ///
  /// **Every code can be turned off, including the last one.** The min-1 rule
  /// belongs to the submit, not to the tap: a chip that refused to deselect
  /// would be a control that does nothing, and the honest way to state the rule
  /// is an inert Continue beside the server's own sentence.
  ///
  /// A no-op while a save is in flight — that request already carries its
  /// codes, and the 200 replaces the form with the server's re-read, so a
  /// toggle accepted here would be silently discarded a moment later.
  void toggle(String code) {
    if (state.submitting) return;
    state = state.toggle(code).copyWith(clearFailure: true);
  }

  // ── Submitting ────────────────────────────────────────────────────────────

  /// Saves the complete selection and walks on.
  ///
  /// **It always posts, and it always posts the whole set.** Unlike screen 4 —
  /// which sends a diff and posts nothing when nothing changed, because its
  /// endpoint MERGES and D-02's skip means not calling it — this endpoint is a
  /// FULL REPLACE and the set on screen *is* the answer. Re-posting an
  /// unchanged set is idempotent, and it is what makes `goalsProvided` true for
  /// a user who accepted the defaults without touching a chip.
  ///
  /// **With nothing selected it posts nothing.** An empty array is a 400
  /// (`select at least one goal`, `OnboardingStepResult.cs:371`) and the
  /// condition is fully knowable here, so the round trip is not spent to be
  /// told. The step does not advance either: emptying the list is not a way
  /// past it.
  Future<void> submit() async {
    final GoalsForm form = state;
    // In-flight guard: a second press must not issue a second request.
    if (form.submitting) return;

    final List<String> codes = form.selectedCodes;
    if (codes.isEmpty) return;

    // The previous rejection goes NOW, not when the new attempt lands: without
    // this the old banner sits beside the new spinner, telling the user the
    // attempt they are watching has already failed.
    state = form.copyWith(submitting: true, clearFailure: true);

    List<GoalChoice>? saved;
    Failure? rejected;
    try {
      final response = await ref
          .read(onboardingRepositoryProvider)
          .saveGoals(codes: codes);
      // The 200 is the server's RE-READ of the stored rows rather than an echo
      // of the request, so it is the best answer to "what does the server hold
      // now" — including for a code this build cannot draw.
      saved = GoalsForm.fromWire(response.goals).goals;
    } on Failure catch (failure) {
      rejected = failure;
    } catch (_) {
      // Not a typed failure, so nothing about it is user-safe to render.
      // `cachedWrite` invalidates its keys unguarded after a successful write,
      // so a concurrent logout purge closing the Hive box lands here — after
      // the answer was stored. Leaving it unhandled would be a spinner that
      // never stops and a banner that never appears.
      rejected = const UnknownFailure();
    }

    if (!ref.mounted) return;

    if (rejected != null) {
      state = state.copyWith(submitting: false, failure: rejected);
      return;
    }

    state = state.copyWith(goals: saved, submitting: false, clearFailure: true);

    ref.read(onboardingFlowControllerProvider.notifier).next();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Screen 5's controller.
final goalsControllerProvider =
    NotifierProvider.autoDispose<GoalsController, GoalsForm>(
      GoalsController.new,
    );
