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
// this screen renders as an advisory note **after** the save (R-17).

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
    show CycleRegularity, cycleWarningMessage;
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
/// Sections: YOUR PATTERN (the three self-reports, all editable) and
/// PREDICTIONS (the three stored preferences R-10 keeps). The pause card the
/// C-12 contract also puts on this screen is **T22b's** and is deliberately
/// absent — nothing here reads or writes `trackingPaused`, `pauseReason` or
/// `pausedSince`.
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
                  onRetry: () => ref.invalidate(cycleSettingsControllerProvider),
                ),
                data: (form) => _Body(form: form),
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
    final bannerMessage = cycleSettingsBannerMessage(form.failure);
    final blockReason = form.blockReason;
    final enabled = !form.submitting;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
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

            // NOTE: the DISPLAY section and its `First day of week` row are
            // REMOVED, not disabled and not reworded — R-10, and the reasoning
            // is at the top of this file. The retrain footer is likewise gone
            // under R-16. `cycle_settings_screen_semantics_test.dart` pins both
            // absences so neither can drift back in without the column and the
            // machinery behind them.
            const SizedBox(height: 18),

            // After a SUCCESSFUL save, never before one: the band does not
            // block a write, so a hint about a value only exists once the
            // server has stored it and said so (R-17).
            for (final code in form.warnings)
              if (cycleWarningMessage(code) case final message?) ...<Widget>[
                _Advisory(message),
                const SizedBox(height: 10),
              ],

            // The banner, the block reason and the CTA are adjacent and inside
            // the SAME scroll view, so the message explaining a failure can
            // never scroll away from the control that caused it, and a screen
            // reader's next swipe after the announcement reaches `Try again`
            // (T20b's amended S9).
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
              onPressed: (!form.canSubmit || form.submitting)
                  ? null
                  : controller.submit,
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
          ],
        ),
      ),
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
        hint: '',
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
/// footer card, reused here because it is the same kind of statement: the save
/// succeeded, and this is a remark about it. `liveRegion` because it appears
/// without the user moving focus to it.
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
