import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/goals_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';

// ---------------------------------------------------------------------------
// Constants the tests and the screen share
// ---------------------------------------------------------------------------

/// The wire field name `POST /onboarding/goals` keys its rejections under.
///
/// The whole-array errors arrive as `goals`; a rejected member arrives as
/// `goals[i]` (`OnboardingStepsService.cs:1127-1149`,
/// `ValidationFailure.path('goals', i)`).
const String kGoalsField = 'goals';

/// The server's own sentence for an empty selection, verbatim.
///
/// `OnboardingValidationMessages.GoalsEmpty`
/// (`backend/src/Lumen.Api/Onboarding/OnboardingStepResult.cs:371`). D-14 makes
/// the step multi-select **min 1, no max**, and an empty array is a 400 —
/// deliberately with THIS message rather than the generic `value is required`,
/// because the field *was* supplied and "value is required" would send the user
/// looking for a field they missed instead of at the chips.
///
/// Mirrored here rather than waited for: the condition is fully knowable on the
/// device, so the round trip is not spent to be told. It is the server's string
/// and not this task's, which is also why it is lower-case — it is what the
/// same condition says when it comes back off the wire.
const String kGoalsEmptyMessage = 'select at least one goal';

/// The stable handle for one goal row.
///
/// A key rather than a semantics label, because a test that taps a control by
/// what it ANNOUNCES fails inside `tester.tap` when the announcement changes —
/// which is indistinguishable from a passing assertion having been broken
/// (P4b-T5c). Tests locate a row with this; `find.bySemanticsLabel` appears
/// only inside assertions about what is announced.
Key goalTileKey(String code) => ValueKey<String>('goal:$code');

// ---------------------------------------------------------------------------
// GoalsScreen
// ---------------------------------------------------------------------------

/// Screen 5 — "What brings you here?" (onboarding step 5 of 7).
///
/// It is a step BODY, not a route: the eyebrow, the back affordance, the dot
/// row and the padding all belong to `OnboardingShellScreen`, which mounts this
/// in place of the `goals` arm of its exhaustive switch.
///
/// ## The list it draws is the server's
///
/// `GET /onboarding/state` and `POST /onboarding/goals` both answer the
/// **complete** vocabulary in frozen order with a boolean per code, and this
/// screen renders that list ([GoalsForm.goals]). It does not iterate
/// [GoalOption] to decide what exists — that enum is copy plus the seed for the
/// one case the wire cannot answer (§C.0.1, and [GoalsForm.fromWire]). The
/// vocabulary is append-only on the server, so a client that re-derived it
/// would silently disagree with storage the day a sixth code lands.
///
/// A code this build has no copy for is therefore **not drawn** — there is no
/// title, sub-description or icon for it and inventing one from the wire code
/// would be authoring copy — but it is still carried into the write. See
/// [GoalsForm.drawable].
///
/// ## What Continue does
///
/// **FULL REPLACE** (§C.0.1): the array is the whole desired state of
/// `user_goals`, so a code left out is stored as **deselected**. This screen
/// therefore always posts the complete selection, never a diff against what it
/// read — the opposite of screen 4, whose endpoint merges. See
/// [GoalsController.submit].
///
/// The one rule it mirrors client-side is D-14's **min 1**: with nothing
/// selected the CTA is inert and [kGoalsEmptyMessage] says why, in the server's
/// own words. Nothing else is mirrored — there is no maximum, duplicates are
/// collapsed server-side and codes are matched case-sensitively, and a client
/// that rejected any of those would be refusing what the server stores.
///
/// ## D-14: the goals are stored and unconsumed
///
/// The subhead says "Shapes your dashboard" and **nothing in P4b consumes a
/// goal.** That is D-14's ratified escape hatch rather than an oversight: every
/// element a goal could gate — the insight card, the confidence ring, the
/// missing-data card — is a P6 surface that does not exist yet
/// (`survey/decisions-and-vocabularies.md` §1.2). The copy is the mockup's and
/// stays as drawn; softening it would be authoring a promise the product has
/// not made.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(goalsControllerProvider);
    final controller = ref.read(goalsControllerProvider.notifier);
    final c = Theme.of(context).extension<LumenColors>()!;

    final failure = form.failure;
    final rejected = failure is ValidationFailure ? failure : null;
    final bannerMessage = _bannerMessage(failure);

    // There is no loading arm and no error arm, and neither is missing: this
    // body makes no read of its own. The goal list came with the shell's resume
    // read, which has already settled by the time the shell mounts a step, and
    // the shell owns both of that read's failure surfaces. See
    // [GoalsController].
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            'What brings you here?',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w500,
              color: c.ink,
              letterSpacing: -0.3,
            ),
          ),
        ),

        const SizedBox(height: 6),

        Text(
          'Pick all that fit. Shapes your dashboard.',
          style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
        ),

        const SizedBox(height: 18),

        // The mockup's `.gl` column, at its 8 px gap. Built from the SERVER's
        // list, in the SERVER's order.
        for (final (int index, GoalChoice choice)
            in form.drawable.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: 8),
          _GoalTile(
            key: goalTileKey(choice.code),
            option: choice.option!,
            selected: choice.selected,
            enabled: !form.submitting,
            onTap: () => controller.toggle(choice.code),
          ),
        ],

        if (!form.canSubmit) ...<Widget>[
          const SizedBox(height: 8),
          // A live region: it appears because the user just emptied the list,
          // and the control it disabled is at the other end of the screen. This
          // is the one `LumenFieldMessage` in the app that announces itself —
          // the widget is deliberately silent where a `LumenErrorBanner` sits
          // above it, and here there is none.
          Semantics(
            liveRegion: true,
            child: const LumenFieldMessage(kGoalsEmptyMessage),
          ),
        ],

        if (rejected?.messageFor(kGoalsField) != null) ...<Widget>[
          const SizedBox(height: 8),
          LumenFieldMessage(rejected!.messageFor(kGoalsField)!),
        ],

        // The mockup's `.btn { margin-top:auto }`. What it pushes against is
        // `OnboardingStepSlot`, which is why this is a `Spacer` and not a
        // `SizedBox` of some measured height.
        const Spacer(),

        if (bannerMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          LumenErrorBanner(message: bannerMessage),
        ],

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            // Inert without an answer. That is the endpoint's own rule — D-14's
            // min 1, `select at least one goal` — and not a bound this screen
            // invented; [kGoalsEmptyMessage] is drawn above so the reason is
            // never left to be guessed.
            onPressed: !form.canSubmit || form.submitting
                ? null
                : controller.submit,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              elevation: 0,
            ),
            child: form.submitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.surface,
                      // The shell's own spinner label, reused rather than
                      // invented: no copy for this state exists in the mockup
                      // or in `definitions.md`.
                      semanticsLabel: 'Loading',
                    ),
                  )
                : const Text('Continue'),
          ),
        ),
      ],
    );
  }
}

/// What the banner above the CTA says, or null when there is nothing wrong.
///
/// Same shape as screens 2, 3 and 4: the banner is this body's live region for
/// a failed WRITE, so it is never suppressed in favour of the per-field message
/// below the list. For a [ValidationFailure] it prefers the server's reserved
/// cross-field messages, which name no input.
String? _bannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    return crossField.isEmpty ? failure.message : crossField.first;
  }
  return failure.message;
}

// ---------------------------------------------------------------------------
// One goal
// ---------------------------------------------------------------------------

/// The mockup's `.g` row: a glyph in a circle, a title and a sub-description.
///
/// Announced as ONE node carrying both strings and its selected state. The two
/// are joined with a newline and nothing else — that is the separator
/// `MergeSemantics` itself uses when it folds sibling labels together
/// (`SemanticsNode` joins sibling labels with a line break), so the reading
/// order is the framework's own and no punctuation is invented between two
/// pieces of mockup copy.
///
/// An explicit label rather than a [MergeSemantics] wrapper because
/// `SemanticsNode.label` — what `expectLabeledButton` reads — is a node's OWN
/// label, and a merging node's own label is empty: the shipped matcher would
/// see an unnamed button. Same shape as screen 4's `_StatusOption`.
class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final GoalOption option;
  final bool selected;

  /// False only while a save is in flight — a toggle accepted then would be
  /// discarded by the response a moment later, so the row stops offering one.
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: '${option.title}\n${option.description}',
      excludeSemantics: true,
      // excludeSemantics drops the child GestureDetector's tap action from the
      // tree, so this Semantics needs its own onTap wired to the SAME callback:
      // a screen reader's "activate" gesture invokes the node's action, not the
      // pointer handler.
      onTap: enabled ? onTap : null,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.input,
            border: Border.all(color: selected ? c.accent : c.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.accent : c.surface,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _glyph(option),
                  size: 16,
                  // No `semanticLabel`: the mockup's `✦ ◐ ♡ ↗ ✿` are
                  // decoration, and an Icon without one contributes no node
                  // at all — so the row announces its title and
                  // sub-description rather than a shape.
                  color: selected ? c.surface : c.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      option.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: selected ? c.accent : c.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      option.description,
                      style: TextStyle(fontSize: 11, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The `Icon` standing in for one goal's decorative glyph.
///
/// The mockup draws `✦ ◐ ♡ ↗ ✿` as text inside a `.ic` circle. P3c's rule is
/// that a decorative dingbat becomes an `Icon` — a screen reader announces "✦"
/// as punctuation noise — so each is matched to the nearest Material shape:
/// sparkle, half-filled circle, heart, north-east arrow, flower.
///
/// An exhaustive switch, so adding a member to [GoalOption] fails to compile
/// rather than silently drawing nothing.
IconData _glyph(GoalOption option) => switch (option) {
  GoalOption.manageSymptoms => Icons.auto_awesome, // ✦
  GoalOption.understandHormones => Icons.contrast, // ◐
  GoalOption.planFertility => Icons.favorite_border, // ♡
  GoalOption.prepareAppointments => Icons.north_east, // ↗
  GoalOption.justCurious => Icons.local_florist, // ✿
};
