// Screen 32 — cycle settings (P4b-T22a), the More branch's second leaf.
//
// The one write on `/settings/cycle` this phase ships. `PATCH /settings/cycle`
// is a MERGE, so only what the user TOUCHED travels; everything about that
// lives in `CycleSettingsController`, and its dartdoc is the one to read first.
//
// **What the mockup draws and this screen does NOT.**
//
//  * The DISPLAY section and its `First day of week` row are **REMOVED** —
//    R-10. The row points at a column that does not exist: there is no
//    first-day-of-week field on `user_cycle_settings`, on `MeResponse`, or
//    anywhere on the P4a surface, and R-04 already derives the week's first day
//    from the locale. A row with no column can never be anything but a promise
//    with a date attached.
//  * The footer *"Predictions retrain after every 3 logged cycles"* is
//    **REMOVED** — R-16: copy describing machinery this phase does not ship is
//    removed, not reworded into a promise. `ARCHITECTURE.md` locks the phase
//    engine as deterministic C# rules — there is no model and nothing retrains
//    — and the "3 cycles" figure also contradicts the 6-cycle window. P6
//    authors the real line if there is one.
//
// Both absences are asserted by `cycle_settings_screen_semantics_test.dart`,
// the way T22c pinned screen 36's cut App-lock strings: a later edit cannot
// restore either one silently.
//
// **What the mockup draws as read-only and this screen makes EDITABLE.** The
// three YOUR PATTERN rows are values in the mockup. R2: this is the only
// surface in the whole app that can ever set `avgPeriodLengthDays` —
// onboarding screen 3 does not collect it — so if this screen cannot set it,
// nothing can.
//
// **No bound, anywhere.** The C-03 clinical figures appear nowhere in
// `client/lib`, and the server's own sanity band is not restated here either.
// A value outside it is SAVED and answered with a non-blocking code, which
// this screen renders as an advisory note that NEVER blocks anything (R-17) —
// on LOAD as well as after a save (fix round 1; see
// [cycleSettingsWarningMessage] for the copy that had to change with it).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/locale/locale_provider.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/onboarding/application/cycle_setup_controller.dart'
    show CycleRegularity;
import 'package:lumen/features/settings/application/cycle_settings_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

/// Screen 32's own title. **EXTRACTED** — `Screens/screen_32_cycle_settings.
/// html` draws `Cycle` under the `SETTINGS` eyebrow.
const String kCycleSettingsScreenTitle = 'Cycle';

/// The NAME of the row on screen 31 that reaches this screen.
///
/// **AUTHORED**, and deliberately NOT [kCycleSettingsScreenTitle] — which is
/// the rule T22c set (one constant for the affordance and its destination, so
/// the two cannot come to be called different things) and this is the one case
/// it cannot serve. The bottom nav already ships a tab whose destination label
/// is the bare word `Cycle` (`LumenBottomNav`), so a row with that exact name
/// inside the More tab would be indistinguishable from it in a screen reader's
/// flat list, and `find.text('Cycle')` would match both. On the T25 PO list.
const String kCycleSettingsRowLabel = 'Cycle settings';

/// The first section. **EXTRACTED** — the mockup's `YOUR PATTERN`, sentence
/// case here because [LumenSectionLabel] applies the mockup's own
/// `text-transform: uppercase` itself (CLAUDE.md's rule).
const String kCycleSettingsPatternLabel = 'Your pattern';

/// The second section. **EXTRACTED** — the mockup's `PREDICTIONS`.
const String kCycleSettingsPredictionsLabel = 'Predictions';

/// **EXTRACTED** — the mockup's row label.
const String kCycleSettingsAvgCycleLabel = 'Avg cycle length';

/// **EXTRACTED** — the mockup's row label.
const String kCycleSettingsAvgPeriodLabel = 'Avg period length';

/// **EXTRACTED** — the mockup's row label, and screen 3's field label.
const String kCycleSettingsRegularityLabel = 'Regularity';

/// **EXTRACTED** — the mockup's toggle label.
const String kCycleSettingsPhasePredictionLabel = 'Phase prediction';

/// **EXTRACTED** — the mockup's toggle label.
const String kCycleSettingsAutoDetectLabel = 'Auto-detect period start';

/// **EXTRACTED** — the mockup's toggle label.
const String kCycleSettingsFertilityLabel = 'Show fertility window';

/// What an unset self-report reads as.
///
/// **AUTHORED.** Screen 31 draws a lone em dash for its unset values, and this
/// row is not that row: it is a BUTTON, so its accessible name would end in a
/// dash a screen reader has to interpret. `Not set` says the same thing in the
/// register a control's own name needs. Flagged for T25 as a register
/// difference with screen 31's `—`.
const String kCycleSettingsNotSetValue = 'Not set';

/// The unit both length rows draw. **EXTRACTED** — the mockup's `29 days`,
/// and the unit screen 3's chips already announce.
///
/// Singular exists because `1 days` is wrong and `avgPeriodLengthDays` can be
/// 1. It is an English pluralisation branch, which R-04 permits (strings stay
/// English this phase) and the localisation phase will replace with a plural
/// rule rather than a ternary.
const String kCycleSettingsDayUnit = 'day';

/// See [kCycleSettingsDayUnit].
const String kCycleSettingsDaysUnit = 'days';

/// The Save CTA. **AUTHORED** — screen 32's mockup draws no CTA at all.
/// Screen 9 ships `Save check-in`, screen 11 `Save day log`, screen 12
/// `Save symptom`; this one names its own subject the same way.
const String kCycleSettingsSaveLabel = 'Save cycle settings';

/// The CTA's label once an attempt has failed.
///
/// `expectRetryReissuesOneRequest` (`test/support/retry_trap.dart`) locates a
/// write screen's retry control by exactly this text or `Retry` — a P4b exit
/// criterion for every write screen. The same control that failed is what
/// tries again, so there is exactly one place a duplicate tap could come from.
const String kCycleSettingsRetryLabel = 'Try again';

/// The number editor's dismissal. **SHIPPED-PRECEDENT** — every dialog in this
/// app labels its dismissal `Cancel`.
const String kCycleSettingsEditCancelLabel = 'Cancel';

/// The number editor's confirmation. **SHIPPED-PRECEDENT** — screen 31's
/// display-name dialog.
const String kCycleSettingsEditSaveLabel = 'Save';

// ---------------------------------------------------------------------------
// The C-12 pause sub-flow's copy and vocabulary (P4b-T22b)
// ---------------------------------------------------------------------------
//
// **Every string below is AUTHORED**: `Screens/screen_32_cycle_settings.html`
// draws no pause card, and the word "pause" appears in no mockup in the repo.
// All of them are on the T25 PO copy list.
//
// **R4 governs the whole block.** C-12 is PO-interim and clinician-UNSIGNED,
// so the five reasons are a VOCABULARY and not a diagnosis: each label is its
// wire code humanised and nothing more, and no sentence anywhere on this
// screen says what a reason means, medically or otherwise — least of all about
// `pregnancy`, whose C-12 rider (hormone-range interpretation disabled
// entirely) is a P6/P7b rule with no surface here at all.
// `cycle_settings_screen_semantics_test.dart` asserts that property directly:
// every drawn string mentioning one of these words IS that reason's bare
// label.

/// The pause card's section. **AUTHORED.**
const String kCycleSettingsTrackingLabel = 'Cycle tracking';

/// The status row's label. **AUTHORED.**
const String kCycleSettingsStatusLabel = 'Status';

/// The status of a user who is NOT paused. **AUTHORED.**
const String kCycleSettingsTrackingActiveValue = 'Active';

/// The status of a paused user. **AUTHORED.**
const String kCycleSettingsTrackingPausedValue = 'Paused';

/// Labels the reason chips while unpaused, and the reason row while paused.
/// **AUTHORED.**
const String kCycleSettingsPauseReasonLabel = 'Reason';

/// The pause CTA. **AUTHORED.**
const String kCycleSettingsPauseLabel = 'Pause tracking';

/// The resume CTA. **AUTHORED.**
///
/// **It is never anything else, and nothing stands in front of it.** R1 /
/// C-12: resume is user-controlled and always available for every pause
/// reason, `pregnancy` included — no confirmation dialog, no second question,
/// and no variant of this string that asks one.
const String kCycleSettingsResumeLabel = 'Resume tracking';

/// The hint for `avg_cycle_length_out_of_sanity_band`.
///
/// **AUTHORED, and it is screen 3's sentence minus its first word.** Screen 3
/// (`cycle_setup_controller.dart`'s `cycleWarningMessage`) opens both of its
/// answers with *"Saved."*, which is true there — that screen only ever shows
/// the hint immediately after a `POST /onboarding/cycle`. Screen 32 shows it
/// on LOAD as well, where a save acknowledgement would be a statement about
/// something the user did not just do, so the acknowledgement is dropped and
/// the remaining sentence is true in both states.
///
/// **The duplication is deliberate and self-checking.** The alternative —
/// splitting the prefix out of the shared function — edits screen 3's copy,
/// its tests and its feature for a screen-32 problem. Instead
/// `cycle_settings_screen_semantics_test.dart` asserts these two strings ARE
/// screen 3's two, without the leading `Saved. `, so a PO reword of one names
/// the other rather than letting the two surfaces drift into describing the
/// same server behaviour differently. Booked for T25 with the placement
/// question that was already open on `cycleWarningMessage`.
const String kCycleSettingsCycleLengthWarning =
    "That cycle length is unusual — double-check the number if it wasn't "
    'intended.';

/// The hint for `avg_period_length_out_of_sanity_band`. See
/// [kCycleSettingsCycleLengthWarning].
const String kCycleSettingsPeriodLengthWarning =
    "That period length is unusual — double-check the number if it wasn't "
    'intended.';

/// What screen 32 says about one frozen `CycleSettingsWarnings` code, or
/// `null` when it has nothing to say about it.
///
/// **An unknown code answers null**, the same load-bearing choice
/// `cycleWarningMessage` makes: the vocabulary is append-only on the server, so
/// a third code WILL arrive at a build that has never seen it, and inventing a
/// sentence for it would be authoring copy about behaviour nobody has
/// described. (That a new code then renders as nothing at all, with no signal,
/// is booked as a T25 item across both surfaces.)
String? cycleSettingsWarningMessage(String code) => switch (code) {
  'avg_cycle_length_out_of_sanity_band' => kCycleSettingsCycleLengthWarning,
  'avg_period_length_out_of_sanity_band' => kCycleSettingsPeriodLengthWarning,
  _ => null,
};

/// The failure text for the banner above the CTA.
///
/// A cross-field `request` message first (the endpoint's all-fields-absent
/// 400, which this screen's own block reason should have prevented — if it
/// ever arrives, the pre-check has a hole and the user must still be told),
/// then the generic message. Field-keyed messages are NOT consumed here: they
/// belong under their own row, and [_LengthRow] renders them there.
String? cycleSettingsBannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    if (crossField.isNotEmpty) return crossField.first;
    return failure.message;
  }
  return failure.message;
}

/// `29 days`, or `1 day`. The number goes through [LumenFormats] (R-04);
/// nothing here formats a number by itself.
String cycleSettingsDaysText(int days, String locale) {
  final unit = days == 1 ? kCycleSettingsDayUnit : kCycleSettingsDaysUnit;
  return '${LumenFormats.decimal(days, locale, decimalDigits: 0)} $unit';
}

// ---------------------------------------------------------------------------
// Leaving
// ---------------------------------------------------------------------------

/// Leaves screen 32.
///
/// `canPop()` first, `go` second — screen 36's `_leavePrivacy` shape and
/// screen 11's `_leaveDayDetail` before it.
///
/// **The guard is a CONSISTENCY choice, not a live fix, and this task measured
/// that rather than assuming it either way.** A mutation replacing the whole
/// body with a bare `context.pop()` left the entire suite GREEN, including the
/// cold-deep-link test — because `/more/cycle` is registered as a CHILD of the
/// More branch, so even a cold link builds the branch root beneath it and
/// `context.canPop()` answers true. That is P4b-T21b's probe C, one route over.
/// The `else` arm is therefore **unreachable from today's route table**, and
/// the test below it pins where leaving LANDS rather than pretending the guard
/// is load-bearing. It stays because it is the shape all three settings leaves
/// use and because the arrangement that makes it dead is the route table's,
/// not this function's.
void _leaveCycleSettings(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.more);
  }
}

// ---------------------------------------------------------------------------
// CycleSettingsScreen
// ---------------------------------------------------------------------------

/// Screen 32 — Cycle (Settings), at [Routes.cycleSettings].
///
/// Sections: YOUR PATTERN (the three self-reports, all editable), PREDICTIONS
/// (the three stored preferences R-10 keeps) and CYCLE TRACKING (the C-12
/// pause sub-flow, P4b-T22b).
///
/// **The screen writes the same row through two separate requests**, and the
/// split is the safety property, not a layering accident: a `pauseReason` sent
/// while the effective state is not paused is a 400, and a resumed user's own
/// 200 is exactly that body. `CycleSettingsRepository`'s three methods have
/// disjoint parameter sets so the combination cannot be built; read its class
/// dartdoc. `pausedSince` is written by nothing here — the server defaults it
/// to the user's own today.
class CycleSettingsScreen extends ConsumerWidget {
  const CycleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final state = ref.watch(cycleSettingsControllerProvider);

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 44, 22, 0),
              child: Row(
                children: <Widget>[
                  // `semanticLabel` on the Icon (screens 11, 12 and 36's
                  // precedent), never `tooltip:` — Material surfaces a tooltip
                  // as a SEPARATE semantics field rather than the button's own
                  // name, which would leave this control announcing nothing.
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left,
                      semanticLabel: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                    ),
                    iconSize: 22,
                    color: c.muted,
                    padding: EdgeInsets.zero,
                    onPressed: () => _leaveCycleSettings(context),
                  ),
                  const SizedBox(width: 2),
                  const LumenSectionLabel(
                    'Settings',
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.when(
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: c.accent,
                    semanticsLabel: 'Loading',
                  ),
                ),
                error: (error, _) => LumenErrorRetry(
                  message: error is Failure
                      ? error.message
                      : 'Something went wrong. Please try again.',
                  onRetry: () =>
                      ref.invalidate(cycleSettingsControllerProvider),
                ),
                // S7's shape, converged with screen 12 (T20b fix round 1):
                // the FORM scrolls and the message zone does NOT. See
                // [_Footer] for why the failure banner is down there rather
                // than inside the scroll view with the fields it belongs to.
                data: (form) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: _Body(form: form)),
                    _Footer(form: form),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The form
// ---------------------------------------------------------------------------

/// Everything above the pinned footer: the two sections and their controls.
///
/// No advisory, no banner, no block reason and no CTA — all four live in
/// [_Footer], outside this scroll view.
class _Body extends ConsumerWidget {
  const _Body({required this.form});

  final CycleSettingsForm form;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final locale = ref.watch(localeProvider);
    final controller = ref.read(cycleSettingsControllerProvider.notifier);
    final rejected = form.failure is ValidationFailure
        ? form.failure! as ValidationFailure
        : null;
    // Either write on this row locks the whole form: they hit the same
    // `user_cycle_settings` row, and `CycleSettingsController` refuses to
    // start one while the other is in flight, so a live control here would be
    // a gesture the controller would silently drop.
    final enabled = !form.submitting && !form.pausing;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              kCycleSettingsScreenTitle,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 14),

            // --- YOUR PATTERN ---
            const LumenSectionLabel(kCycleSettingsPatternLabel),
            const SizedBox(height: 6),
            _LengthRow(
              label: kCycleSettingsAvgCycleLabel,
              days: form.avgCycleLengthDays,
              locale: locale,
              enabled: enabled,
              errorText: rejected?.messageFor('avgCycleLengthDays'),
              onChanged: controller.setAvgCycleLengthDays,
            ),
            const SizedBox(height: 5),
            _LengthRow(
              label: kCycleSettingsAvgPeriodLabel,
              days: form.avgPeriodLengthDays,
              locale: locale,
              enabled: enabled,
              errorText: rejected?.messageFor('avgPeriodLengthDays'),
              onChanged: controller.setAvgPeriodLengthDays,
            ),
            const SizedBox(height: 10),

            // Regularity is a CHIP ROW rather than a fourth tappable row: the
            // vocabulary is three ratified codes, the chip is the shipped
            // control for picking one of those (screen 3 draws the same three),
            // and unlike a number it has no empty state to design around.
            const LumenFieldLabel(kCycleSettingsRegularityLabel),
            const SizedBox(height: 6),
            _RegularityChips(
              selected: form.regularity,
              enabled: enabled,
              onSelect: controller.setRegularity,
            ),
            if (rejected?.messageFor('regularity') != null) ...<Widget>[
              const SizedBox(height: 6),
              LumenFieldMessage(rejected!.messageFor('regularity')!),
            ],
            const SizedBox(height: 14),

            // --- PREDICTIONS ---
            // R-10: these three persist real preferences that P6/P9a consume,
            // so they ship. A stored preference is honest even before the
            // feature reading it exists; what R-10 removes is inert
            // NAVIGATION, which is why the DISPLAY row below them is gone.
            const LumenSectionLabel(kCycleSettingsPredictionsLabel),
            const SizedBox(height: 6),
            _ToggleRow(
              label: kCycleSettingsPhasePredictionLabel,
              on: form.phasePredictionEnabled ?? false,
              enabled: enabled,
              onTap: () => controller.setPhasePredictionEnabled(
                !(form.phasePredictionEnabled ?? false),
              ),
            ),
            const SizedBox(height: 5),
            _ToggleRow(
              label: kCycleSettingsAutoDetectLabel,
              on: form.autoDetectPeriodStartEnabled ?? false,
              enabled: enabled,
              onTap: () => controller.setAutoDetectPeriodStartEnabled(
                !(form.autoDetectPeriodStartEnabled ?? false),
              ),
            ),
            const SizedBox(height: 5),
            _ToggleRow(
              label: kCycleSettingsFertilityLabel,
              on: form.showFertilityWindowEnabled ?? false,
              enabled: enabled,
              onTap: () => controller.setShowFertilityWindowEnabled(
                !(form.showFertilityWindowEnabled ?? false),
              ),
            ),

            const SizedBox(height: 14),

            // --- CYCLE TRACKING (the C-12 pause sub-flow, P4b-T22b) ---
            // The CARD is here, in the scroll view; its CTA, its block reason
            // and its failure banner are in `_Footer` with the save trio. That
            // split is R5, and this card is the content T22a moved the footer
            // out for.
            const LumenSectionLabel(kCycleSettingsTrackingLabel),
            const SizedBox(height: 6),
            _PauseCard(
              form: form,
              enabled: enabled,
              onSelect: controller.selectPauseReason,
            ),

            // NOTE: the DISPLAY section and its `First day of week` row are
            // REMOVED, not disabled and not reworded — R-10, and the reasoning
            // is at the top of this file. The retrain footer is likewise gone
            // under R-16. `cycle_settings_screen_semantics_test.dart` pins both
            // absences so neither can drift back in without the column and the
            // machinery behind them.
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The pinned footer
// ---------------------------------------------------------------------------

/// The advisory, both failure banners, both block reasons and both CTAs —
/// outside the scroll view, always on screen.
///
/// **Converged with screen 12's `_Footer` (T22a fix round 1), one task before
/// T22b made it matter — and it now does.** T20b's fix round 1 moved screen
/// 12's banner out of its scroll view and amended S9 to say so; this screen
/// shipped the banner inside. Measured at the time that was not a live defect
/// — at 390x844 screen 32's `maxScrollExtent` was 0.0 before and after a
/// failure, so nothing could scroll away — but the property held by accident
/// of content height rather than by construction. **T22b's pause card is the
/// content that broke the accident**: the form now scrolls, and a banner left
/// inside it would be a message the user never sees.
///
/// T20b's three reasons, all of which apply here unchanged:
///  * a failure banner and a block reason are the same class of message —
///    "here is why the button did not do what you asked" — and pinning one
///    while the other scrolls splits a rule in half;
///  * the user is by construction AT the CTA when a failure arrives, because
///    that is the control they just pressed;
///  * it keeps the live region adjacent to the retry control, so a screen
///    reader user's next swipe after the announcement reaches `Try again`.
///
/// **The advisory is pinned too**, which screen 12 has no equivalent of. It is
/// the same class again — a remark about the values, rendered without the user
/// asking for it — and it now appears on LOAD as well as after a save, so
/// neither anchor (the top of the page, the bottom of the page) keeps it on
/// screen in both cases. Pinning it is the only placement that does.
///
/// Footer height is the real cost of pinning, and it is bounded: the advisory
/// and the banner are mutually exclusive in practice. Warnings can only be
/// non-empty on a seed, a seed has every `touched*` flag false, and a form
/// with nothing touched cannot submit — so a form holding warnings has never
/// had a failure, and a failure rebuild carries the warning-free pre-submit
/// snapshot. Field-keyed 400s stay at their rows, where [_LengthRow] renders
/// them.
class _Footer extends ConsumerWidget {
  const _Footer({required this.form});

  final CycleSettingsForm form;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final controller = ref.read(cycleSettingsControllerProvider.notifier);
    final bannerMessage = cycleSettingsBannerMessage(form.failure);
    final blockReason = form.blockReason;
    final busy = form.submitting || form.pausing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // On LOAD as well as after a save (fix round 1). The band never
          // blocks a write — R-17 — so this is a remark about values the
          // server already holds, and the codes reach the form only through
          // `CycleSettingsForm.seededFrom`.
          for (final code in form.warnings)
            if (cycleSettingsWarningMessage(code)
                case final message?) ...<Widget>[
              _Advisory(message),
              const SizedBox(height: 10),
            ],

          if (bannerMessage != null) ...<Widget>[
            LumenErrorBanner(message: bannerMessage),
            const SizedBox(height: 10),
          ],
          if (blockReason != null) ...<Widget>[
            // Rendered STRAIGHT from `CycleSettingsForm.blockReason`, never
            // composed here.
            //
            // Deliberately NOT a live region: it sits directly above the
            // control it disables.
            LumenFieldMessage(blockReason),
            const SizedBox(height: 8),
          ],
          FilledButton(
            // Gated on `canSubmit`, which is `blockReason == null` — never on
            // a condition recomputed here. `submit()` carries the same guard
            // itself; this is the screen-level half of that pair, and it is
            // what stops the endpoint's all-fields-absent 400 from ever being
            // sent for.
            onPressed: (!form.canSubmit || busy) ? null : controller.submit,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              textStyle: const TextStyle(
                fontSize: 14,
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
                      semanticsLabel: 'Loading',
                    ),
                  )
                : Text(
                    form.failure != null
                        ? kCycleSettingsRetryLabel
                        : kCycleSettingsSaveLabel,
                  ),
          ),

          // --- the pause sub-flow's own three (P4b-T22b) ---
          // Same order as the save trio above — banner, block reason, CTA —
          // and in the same pinned footer, because R5 asks for exactly what
          // T22a converged on. It sits BELOW the save CTA so it stays adjacent
          // to the card it acts on, which is the last thing in the scroll
          // view.
          //
          // Footer height is bounded by two invariants rather than by hope:
          // the two banners are mutually exclusive (starting either attempt
          // clears both — `CycleSettingsForm.pauseFailure`), and so are the
          // pause banner and the pause block reason (a pause attempt requires
          // a selected reason, and the card offers no deselect, so a form that
          // can show `Choose a reason to pause.` has never attempted one).
          _PauseFooter(form: form, busy: busy, controller: controller),
        ],
      ),
    );
  }
}

/// The pause sub-flow's failure banner, block reason and CTA — the second half
/// of [_Footer], outside the scroll view for [_Footer]'s reasons.
class _PauseFooter extends StatelessWidget {
  const _PauseFooter({
    required this.form,
    required this.busy,
    required this.controller,
  });

  final CycleSettingsForm form;
  final bool busy;
  final CycleSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final bannerMessage = cycleSettingsBannerMessage(form.pauseFailure);
    final blockReason = form.pauseBlockReason;

    // ONE branch decides the label and the action together, so the control can
    // never announce one and do the other. **Nothing else gates the resume
    // arm** — R1 / C-12: there is no reason a user cannot resume from, and no
    // confirmation singles out `pregnancy`.
    final (String label, Future<bool> Function() action) = form.trackingPaused
        ? (kCycleSettingsResumeLabel, controller.resume)
        : (kCycleSettingsPauseLabel, controller.pause);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (bannerMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          LumenErrorBanner(message: bannerMessage),
        ],
        if (blockReason != null) ...<Widget>[
          const SizedBox(height: 10),
          // Straight from `CycleSettingsForm.pauseBlockReason`, never composed
          // here, and never rendered while paused — that getter has no arm
          // that can block a resume.
          LumenFieldMessage(blockReason),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          // Gated on `canTogglePause`, which is `pauseBlockReason == null`.
          // `pause()` and `resume()` carry the same guards themselves; this is
          // the screen-level half of that pair.
          onPressed: (!form.canTogglePause || busy) ? null : action,
          style: OutlinedButton.styleFrom(
            foregroundColor: c.ink,
            side: BorderSide(color: c.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 11),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: form.pausing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.ink,
                    semanticsLabel: 'Loading',
                  ),
                )
              : Text(
                  form.pauseFailure != null ? kCycleSettingsRetryLabel : label,
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One self-reported length
// ---------------------------------------------------------------------------

/// The mockup's value row, made editable: a label, the stored value, and a
/// chevron, opening a small number editor.
///
/// **A dialog rather than an inline field, and that is a design decision with
/// a consequence.** An inline number field can be EMPTIED, and this endpoint
/// cannot express a clear — `UpdateCycleSettingsRequest`'s own doc says so, and
/// says screen 32 offers no clear affordance. An empty box would therefore be a
/// gesture the server cannot honour: it would silently do nothing, and after a
/// save of some other field it would sit there showing nothing while the server
/// still held the old number. The dialog removes the state instead of
/// apologising for it — its own Save is inert while the box is empty, so the
/// form can only ever receive a real integer.
class _LengthRow extends StatelessWidget {
  const _LengthRow({
    required this.label,
    required this.days,
    required this.locale,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
  });

  final String label;
  final int? days;
  final String locale;
  final bool enabled;

  /// The server's own message for this field, or null. The only 400 these two
  /// fields can produce is structural (a positive integer that fits
  /// `smallint`); the sanity band produces a 200 and a warning instead.
  final String? errorText;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final value = days == null
        ? kCycleSettingsNotSetValue
        : cycleSettingsDaysText(days!, locale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LumenSelectableRow(
          // No selection concept — this is a LAUNCHER, so the flag is omitted
          // rather than passed `false`, which a screen reader would announce as
          // "not selected" for a control that was never selectable (T18's fix
          // round 1).
          selected: null,
          enabled: enabled,
          onTap: () => _edit(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          borderRadius: 10,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
              Text(value, style: TextStyle(fontSize: 12, color: c.ink)),
              const SizedBox(width: 4),
              // Decorative: the row merges its descendants' labels, and an
              // `Icon` with no `semanticLabel` contributes nothing.
              Icon(Icons.chevron_right, size: 16, color: c.muted),
            ],
          ),
        ),
        if (errorText != null) ...<Widget>[
          const SizedBox(height: 6),
          LumenFieldMessage(errorText!),
        ],
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    final entered = await showDialog<int>(
      context: context,
      builder: (_) => _EditLengthDialog(label: label, initialValue: days),
    );
    if (entered == null) return;
    onChanged(entered);
  }
}

/// The number editor. A [StatefulWidget] so the [TextEditingController] belongs
/// to the dialog's own subtree — screen 31's `_EditDisplayNameDialog` carries
/// the full reasoning (a controller disposed in a `finally` is torn down
/// mid-transition and makes the dialog undrivable from a widget test).
///
/// It pops the entered integer, or `null` on Cancel and on a barrier tap. Save
/// is inert while nothing parses, so `null` never means "clear it" — this
/// endpoint has no clear, and offering a gesture it cannot honour would be a
/// data lie.
///
/// **No bound is applied here** (R-17). `digitsOnly` refuses a minus sign and a
/// decimal point, which is the column's own domain (a positive integer) and not
/// a judgement about the number's size. Anything the field accepts is submitted
/// and answered by the server.
class _EditLengthDialog extends StatefulWidget {
  const _EditLengthDialog({required this.label, required this.initialValue});

  final String label;
  final int? initialValue;

  @override
  State<_EditLengthDialog> createState() => _EditLengthDialogState();
}

class _EditLengthDialogState extends State<_EditLengthDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _parsed => int.tryParse(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final value = _parsed;
    return AlertDialog(
      title: Text(widget.label),
      content: LumenInputField(
        controller: _controller,
        label: widget.label,
        // No placeholder: the dialog title already names the value. `null`,
        // not `''` — the widget asserts against the empty string (P4b-T25a).
        hint: null,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        suffixText: kCycleSettingsDaysUnit,
        onChanged: (_) => setState(() {}),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(kCycleSettingsEditCancelLabel),
        ),
        TextButton(
          // Inert while the box holds nothing that parses. `null` here is not
          // "clear the value" — the endpoint cannot express one.
          onPressed: value == null ? null : () => Navigator.pop(context, value),
          child: const Text(kCycleSettingsEditSaveLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Regularity
// ---------------------------------------------------------------------------

/// The three ratified regularity codes as a single-select chip row.
///
/// The SELECTED chip is given a null `onTap` — screen 11's mood row's rule, for
/// its reason: this endpoint has no way to un-set a regularity (the column is
/// non-nullable and MERGE cannot clear), so a deselect gesture is one the
/// server could not honour. The chip then reports itself as offering no action
/// rather than staying a button whose activation silently does nothing.
class _RegularityChips extends StatelessWidget {
  const _RegularityChips({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  /// The stored WIRE code, or null when the read carried none.
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final regularity in CycleRegularity.values) ...<Widget>[
          if (regularity != CycleRegularity.values.first)
            const SizedBox(width: 8),
          Expanded(
            child: LumenSelectableChip(
              label: regularity.label,
              selected: selected == regularity.wireName,
              enabled: enabled,
              onTap: selected == regularity.wireName
                  ? null
                  : () => onSelect(regularity.wireName),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The C-12 pause card (P4b-T22b)
// ---------------------------------------------------------------------------

/// The state of cycle tracking, and — while it is on — the reason a pause
/// would be taken for.
///
/// **The two states are decided by `trackingPaused` alone** (R2). The
/// remembered `pauseReason` a resumed user's response still carries is used
/// for exactly what the server keeps it for: pre-selecting the chip. It is
/// never read as "is this user paused", which would leave every resumed user
/// looking paused with a Resume control they had already used.
///
/// **While PAUSED the chips are gone and the reason is a read-only row.**
/// Re-tapping a chip in that state would re-pause with a new reason, which the
/// server does accept — it updates the open span in place — but it is a second
/// gesture with its own failure mode that C-12 asks for nowhere, and it would
/// need its own confirmation story to be safe. Resume and pause again is the
/// path; R1 guarantees the first half is always available. Booked for T25 as a
/// product question, not shipped as a guess.
class _PauseCard extends StatelessWidget {
  const _PauseCard({
    required this.form,
    required this.enabled,
    required this.onSelect,
  });

  final CycleSettingsForm form;
  final bool enabled;
  final ValueChanged<CyclePauseReason> onSelect;

  @override
  Widget build(BuildContext context) {
    final reason = CyclePauseReason.fromWireName(form.pauseReason);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StatusRow(
          label: kCycleSettingsStatusLabel,
          value: form.trackingPaused
              ? kCycleSettingsTrackingPausedValue
              : kCycleSettingsTrackingActiveValue,
        ),
        if (form.trackingPaused) ...<Widget>[
          // An unresolvable code draws NO row rather than the raw wire string
          // — the vocabulary is append-only, so a future member will reach
          // this build. **The `Reason` label is inside the `if` with it**: a
          // label with nothing beside it claims a value the row is not
          // showing. The status above still says Paused, and the CTA below
          // still resumes.
          if (reason != null) ...<Widget>[
            const SizedBox(height: 5),
            _StatusRow(
              label: kCycleSettingsPauseReasonLabel,
              value: reason.label,
            ),
          ],
        ] else ...<Widget>[
          const SizedBox(height: 10),
          const LumenFieldLabel(kCycleSettingsPauseReasonLabel),
          const SizedBox(height: 6),
          _PauseReasonChips(
            selected: form.selectedPauseReason,
            enabled: enabled,
            onSelect: onSelect,
          ),
        ],
      ],
    );
  }
}

/// A label and a value in the row treatment [LumenSelectableRow] draws, with
/// no gesture and no selection.
///
/// It is not a [LumenSelectableRow] with a no-op `onTap`: that widget's
/// `onTap` is required and non-nullable, and it announces itself as a button —
/// which this is not. `MergeSemantics` so a screen reader hears
/// "Status Paused" as one node rather than two loose strings.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.input,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
            Text(value, style: TextStyle(fontSize: 12, color: c.ink)),
          ],
        ),
      ),
    );
  }
}

/// The five C-12 reasons as a single-select wrap.
///
/// A [Wrap] rather than the `Expanded`-in-a-[Row] the regularity chips use:
/// five labels, one of them `Hormonal suppression`, do not fit a 300-px row
/// and squeezing them would truncate the vocabulary's own words.
///
/// The SELECTED chip keeps a null `onTap` — the regularity row's rule, for its
/// reason: there is no way to un-set a pause reason (the request has no clear,
/// and a null `pauseReason` means "leave alone" on the wire), so a deselect
/// would be a gesture the server could not honour. The chip then reports
/// itself as offering no action rather than staying a button that silently
/// does nothing.
class _PauseReasonChips extends StatelessWidget {
  const _PauseReasonChips({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  /// The picked reason, or null when none is.
  ///
  /// A [CyclePauseReason] rather than the wire string it used to be, so
  /// "selected" here and "sendable" in [CycleSettingsForm.selectedPauseReason]
  /// are the same set by construction: there is no value this row can be
  /// handed that it cannot draw as a selected chip (fix round 1 / I-1).
  final CyclePauseReason? selected;
  final bool enabled;
  final ValueChanged<CyclePauseReason> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final reason in CyclePauseReason.values)
          LumenSelectableChip(
            label: reason.label,
            selected: selected == reason,
            enabled: enabled,
            onTap: selected == reason ? null : () => onSelect(reason),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One prediction preference
// ---------------------------------------------------------------------------

/// The mockup's toggle row: a label and a pill, announced as one button
/// carrying `SemanticsFlag.isSelected`.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.on,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return LumenSelectableRow(
      selected: on,
      enabled: enabled,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: 10,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: c.ink)),
          ),
          const SizedBox(width: 12),
          _TogglePill(on: on),
        ],
      ),
    );
  }
}

/// The mockup's `26x16` pill with a `12 px` knob.
///
/// Pure decoration. It draws the same fact the row already announces as
/// `SemanticsFlag.isSelected`, and contributes no semantics node of its own.
///
/// **Kept private rather than promoted**, and the count is now three: screen
/// 6's pill is `28x16` with a `12 px` knob, screen 7's is `30x18` with a `14 px`
/// knob (`notifications_screen.dart`'s `_PillToggle` names the promotion
/// threshold), and this one is a third geometry again. The mockups' absolute
/// sizes are this phase's fidelity bar, so a shared widget would have to take
/// all three as parameters — and a widget under `lib/shared/widgets/` owes the
/// registry its own golden pair and semantics test. A parameterised box with
/// three call sites and four new test artifacts is not a smaller thing than
/// three eight-line private classes. Recorded for T25 as a real candidate once
/// someone rules the three geometries into one.
class _TogglePill extends StatelessWidget {
  const _TogglePill({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Container(
      width: 26,
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
            // The mockup's `background: #FFFCF7` — the surface token, so the
            // knob reads against the accent fill in both themes.
            color: c.surface,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The advisory
// ---------------------------------------------------------------------------

/// A non-blocking hint about a value the server has ALREADY stored.
///
/// Screen 3's `_Advisory` in the sage-soft treatment the mockup gives its
/// footer card, reused here because it is the same kind of statement — a
/// remark about a value that WAS accepted, never a rejection of one.
///
/// It renders on LOAD as well as after a save (fix round 1), so its copy is
/// screen 32's own rather than screen 3's: see [cycleSettingsWarningMessage].
///
/// `liveRegion` because it appears without the user moving focus to it — after
/// a save, and on arrival for the user whose stored value has been out of band
/// since some earlier session, who is the one this hint exists for.
class _Advisory extends StatelessWidget {
  const _Advisory(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.sageSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message,
          style: TextStyle(fontSize: 11, color: c.sage, height: 1.4),
        ),
      ),
    );
  }
}
