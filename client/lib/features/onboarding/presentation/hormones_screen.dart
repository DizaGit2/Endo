import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/hormone_palette.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/hormones_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

// ---------------------------------------------------------------------------
// Constants the tests and the screen share
// ---------------------------------------------------------------------------

/// The stable handle for one hormone row.
///
/// A key rather than a semantics label, because a test that taps a control by
/// what it ANNOUNCES fails inside `tester.tap` when the announcement changes —
/// which is indistinguishable from a passing assertion having been broken
/// (P4b-T5c). Tests locate a row with this; `find.bySemanticsLabel` appears
/// only inside assertions about what is announced.
Key hormoneRowKey(String code) => ValueKey<String>('hormone:$code');

/// The stable handle for one hormone's colour swatch.
///
/// The swatch has no accessible name of its own — it is decoration — so a test
/// asserting the hard-coded colour has nothing to find it by. Hence a key.
Key hormoneSwatchKey(String code) => ValueKey<String>('hormone-swatch:$code');

/// The stable handle for one hormone's pill toggle.
///
/// Same reason as the swatch, and a sharper one. The pill announces nothing —
/// the row carries the state as `SemanticsFlag.isSelected` — so its appearance
/// is reachable only by reading its `BoxDecoration` and its knob's `Align`.
/// Without this key its **OFF** appearance is covered by nothing at all: the
/// goldens pin the mockup's all-ON form, so both of [_PillToggle]'s conditional
/// lines could be hard-coded to their ON value and every test would stay green,
/// shipping a row whose fill says OFF beside a pill that says ON.
Key hormoneTogglePillKey(String code) =>
    ValueKey<String>('hormone-toggle:$code');

// ---------------------------------------------------------------------------
// HormonesScreen
// ---------------------------------------------------------------------------

/// Screen 6 — "Which to chart?" (onboarding step 6 of 7).
///
/// It is a step BODY, not a route: the eyebrow, the back affordance, the dot
/// row and the padding all belong to `OnboardingShellScreen`, which mounts this
/// in place of the `hormones` arm of its exhaustive switch.
///
/// ## The list it draws is the server's
///
/// `GET /onboarding/state` and `POST /onboarding/hormones` both answer the
/// **complete** vocabulary in frozen order with a boolean per code, and this
/// screen renders that list ([HormonesForm.hormones]). It does not iterate
/// [HormoneOption] to decide what exists — that enum is copy plus the seed for
/// the one case the wire cannot answer (§C.0.1, and [HormonesForm.fromWire]).
/// The vocabulary is append-only on the server, so a client that re-derived it
/// would silently disagree with storage the day an eighth code lands.
///
/// A code this build has no copy for is therefore **not drawn** — there is no
/// label, category or swatch for it and inventing one from the wire code would
/// be authoring copy — but it is still carried into the write. See
/// [HormonesForm.drawable].
///
/// ## Codes travel; labels do not
///
/// Each row draws [HormoneOption.label] and is keyed on
/// [HormoneOption.wireName], and the two differ for two members: `estradiol`
/// reads "Estrogen" and `glp1` reads "GLP-1" (B16, `HormoneCatalog.cs:7-12`).
/// The labels are i18n **source** strings — never stored, never sent. What goes
/// on the wire is [HormonesForm.chartedCodes].
///
/// ## What Continue does
///
/// **FULL REPLACE** (§C.0.1): the array is the whole desired state of
/// `user_hormone_prefs`, so a code left out is stored as **deselected**. This
/// screen therefore always posts the complete selection, never a diff against
/// what it read. See [HormonesController.submit].
///
/// **It mirrors no client-side rule at all, and that is the difference from
/// screen 5.** `POST /onboarding/hormones` has no minimum: `chartedHormones:
/// []` is a real answer — "chart nothing" — and the server rejects only a null
/// (`OnboardingStepsService.cs:435-436`). So Continue stays live with every row
/// off, there is no sentence explaining a bound that does not exist, and the
/// empty array is posted rather than refused.
///
/// ## Charted is not extracted
///
/// The toggle decides whether a hormone's series is **drawn**. P7b extracts all
/// seven from every lab regardless of what is stored here (D-14,
/// `OnboardingContracts.cs:210-214`), so turning one off hides a line and
/// destroys nothing. Nothing in this screen's copy says or implies otherwise —
/// the mockup's "Defaults shown. Tweak now or in settings." is the whole of it.
///
/// ## No units
///
/// Name, category and toggle only. Display units are screen 33's, and they rest
/// on the clinician-UNSIGNED C-07 whitelist (`HormoneCatalog.cs:14-19`), so
/// there is nothing to draw here that would not be an unsigned clinical value.
class HormonesScreen extends ConsumerWidget {
  const HormonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(hormonesControllerProvider);
    final controller = ref.read(hormonesControllerProvider.notifier);
    final c = Theme.of(context).extension<LumenColors>()!;

    final bannerMessage = _bannerMessage(form.failure);

    // There is no loading arm and no error arm, and neither is missing: this
    // body makes no read of its own. The hormone list came with the shell's
    // resume read, which has already settled by the time the shell mounts a
    // step, and the shell owns both of that read's failure surfaces. See
    // [HormonesController].
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            'Which to chart?',
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
          'Defaults shown. Tweak now or in settings.',
          style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
        ),

        const SizedBox(height: 16),

        // The mockup's `.hl` column, at its 6 px gap. Built from the SERVER's
        // list, in the SERVER's order.
        for (final (int index, HormoneChoice choice)
            in form.drawable.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: 6),
          _HormoneRow(
            key: hormoneRowKey(choice.code),
            code: choice.code,
            option: choice.option!,
            charted: choice.charted,
            enabled: !form.submitting,
            onTap: () => controller.toggle(choice.code),
          ),
        ],

        // No min-1 message and no inert CTA: see the class docs. An empty
        // selection is an answer this endpoint stores.

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
            // Live with nothing charted, deliberately. The only thing that
            // takes it away is a request already in flight.
            onPressed: form.submitting ? null : controller.submit,
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
/// Same shape as screens 2, 3, 4 and 5: the banner is this body's live region
/// for a failed WRITE. For a [ValidationFailure] it prefers the server's
/// reserved cross-field messages, which name no input.
///
/// There is no per-field slot below the list, and that is not an omission: the
/// only fields this endpoint can reject are `chartedHormones` and
/// `chartedHormones[i]`, and both are statements about the list of rows as a
/// whole — there is no single control to hang either one under.
String? _bannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    return crossField.isEmpty ? failure.message : crossField.first;
  }
  return failure.message;
}

// ---------------------------------------------------------------------------
// One hormone
// ---------------------------------------------------------------------------

/// The mockup's `.r` row: a colour swatch, the hormone's name, its category and
/// a pill toggle.
///
/// Announced as ONE node carrying the name and the category. The two are joined
/// with a newline and nothing else — that is the separator `MergeSemantics`
/// uses when it folds sibling labels together, so the reading order is the
/// framework's own and no punctuation is invented between two pieces of mockup
/// copy.
///
/// The box, the selected styling and the button semantics are
/// [LumenSelectableRow]'s (P4b-T5d); this class is the hormone-specific content
/// inside it, at screen 6's own padding and radius.
///
/// **The pill toggle is drawn, not built from a `Switch`.** A `Switch` would
/// add a second focusable control inside a control that is already a button,
/// so a screen reader would offer two ways to change one answer and announce
/// the state twice. The row is the affordance — which is also what the mockup
/// draws, where `.tgl` has no handler of its own — and the state it carries is
/// announced once, as `SemanticsFlag.isSelected`.
class _HormoneRow extends StatelessWidget {
  const _HormoneRow({
    required this.code,
    required this.option,
    required this.charted,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  /// The wire code, used for the swatch handle and the palette lookup.
  final String code;

  /// The copy this build holds for [code].
  final HormoneOption option;

  final bool charted;

  /// False only while a save is in flight — a toggle accepted then would be
  /// discarded by the response a moment later, so the row stops offering one.
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return LumenSelectableRow(
      selected: charted,
      enabled: enabled,
      onTap: onTap,
      // Screen 6's own `.r`: `padding:10px 12px; border-radius:10px`. The
      // shared row defaults to screen 5's numbers and takes these as
      // parameters, because the mockups' absolute sizes are this phase's
      // fidelity bar.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: 10,
      child: Row(
        children: <Widget>[
          // The mockup's `.sw`, at the hormone's hard-coded swatch. These
          // colours do NOT theme-switch: a hormone keeps its identity colour in
          // both themes (`CLAUDE.md`, `HormoneCatalog.cs:63-66`). Drawn with no
          // `semanticLabel` and no `Semantics` of its own — a colour chip has
          // nothing to say that the name beside it does not already say.
          Container(
            key: hormoneSwatchKey(code),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: HormonePalette.forCode(code),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              option.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(option.category, style: TextStyle(fontSize: 10, color: c.muted)),
          const SizedBox(width: 10),
          _PillToggle(code: code, on: charted),
        ],
      ),
    );
  }
}

/// The mockup's `.tgl`: a 28x16 pill with a 12px knob at one end.
///
/// Pure decoration. It draws the same fact the row already announces as
/// `SemanticsFlag.isSelected`, and it contributes no semantics node of its own
/// — a `Container` without a `Semantics` ancestor of its own adds nothing to
/// the tree, so the row keeps announcing its name and category rather than
/// "switch, on".
///
/// **Being silent is exactly why it carries [hormoneTogglePillKey].** Announcing
/// nothing means no accessibility assertion can see it, and the goldens pin only
/// the mockup's all-ON form — so the two lines below were, until P4b-T12's
/// review, the one part of this row whose OFF appearance no test and no image
/// could contradict. `hormones_screen_semantics_test.dart` now reads both states
/// off one mixed-state mount.
class _PillToggle extends StatelessWidget {
  const _PillToggle({required this.code, required this.on});

  /// The wire code, for the handle only — the pill draws nothing from it.
  final String code;

  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Container(
      key: hormoneTogglePillKey(code),
      width: 28,
      height: 16,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: on ? c.accent : c.border,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Align(
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            // The mockup's `background: var(--f)` — the surface token, so the
            // knob reads against the accent fill in both themes.
            color: c.surface,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
