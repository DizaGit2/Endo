// Screen 11's period-event editor (P4b-T16c) — the app's FIRST period-logging
// surface of any kind.
//
// A bottom sheet over screen 11, opened by `DayDetailScreen`'s
// [kDayDetailEditPeriodLabel] affordance and hosted by `showLumenBottomSheet`
// (screen 9's shipped modal idiom). Not a route: the day-detail route already
// carries the date, so the sheet needs no URL of its own and screen 11 stays
// mounted underneath — which is what keeps the Period section the form was
// seeded from on screen.
//
// **NOTHING HERE IS DRAWN BY A MOCKUP, AND THAT IS THE FINDING, NOT A
// FOOTNOTE.** A four-agent re-survey checked all 38 mockups: Lumen has no
// period-logging surface anywhere in the design system — "period" appears only
// in onboarding, two reminder toggles, insights and settings, and no screen
// draws a flow, spotting or bleeding control at all. So a user set
// `lastPeriodStart` once at onboarding and could never log a period again, in a
// menstrual-cycle tracker. Every string, control and metric below is either
// borrowed from a shipped sibling or authored; the authored ones are listed in
// the T16c report for the T25 PO copy pass.
//
// **THIS IS NOT THE DAY-LOG EDITOR, AND THE DIFFERENCE IS DESTRUCTIVE.**
// `day_log_editor_screen.dart` writes `POST /cycle/day/{date}`, a MERGE: an
// emptied field there is a NO-OP and its sheet says so. This one writes
// `POST /cycle/events`, a FULL UPSERT: an emptied field here is an ERASE, and
// [kPeriodEditorUpsertNote] says THAT. The two sheets must never share a
// widget and must never share copy — `kDayLogEditorMergeNote` states the
// opposite rule in the same slot, and pasting it here would be a data lie.
//
// The controls, and why each is shaped the way it is:
//
//  * **kind — three chips, single-select, NO deselect.** `kind` is part of the
//    upsert key, so the chip row is the ROW SELECTOR: it decides which of the
//    day's up-to-three events this sheet describes. A re-tap of the selected
//    chip is a no-op, so it is given a null `onTap` and the node drops its tap
//    action rather than announcing one that does nothing (T16b's rule, applied
//    here). See `PeriodEditorController.setKind` for why this row does not
//    deselect while the flow row does.
//  * **flow — four chips, single-select, WITH deselect-to-clear.** Here `null`
//    is a real wire value: it is the ONLY way a user can take a flow level back
//    off an event, since the generated serializer omits a null member and this
//    endpoint reads absence as CLEAR. A re-tap therefore does something, and
//    keeps its action.
//  * **note — multiline, seeded once**, `baseline_screen.dart`'s shape.
//    Emptying it and saving ERASES the stored note. That is deliberate and it
//    is the only way to remove one.
//  * **delete — behind a confirmation**, because it is irreversible from the
//    user's side: no endpoint reads a tombstoned row, so the note goes with it.
//  * **no date control.** The day is the route's; this endpoint has no move
//    operation, and building one out of DELETE + POST is what RULING T16-G
//    forbids.
//
// **C-15 does NOT ship here (RULING T16-C).** `Heavy` is a chip label and
// nothing more: no warning, no alarm chrome, no advisory copy, nothing that
// characterises heaviness as a concern. That note needs clinician AND legal
// sign-off, and neither exists.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/cycle/application/period_editor_controller.dart';
import 'package:lumen/features/cycle/presentation/period_vocabulary.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';

// ---------------------------------------------------------------------------
// Authored copy
// ---------------------------------------------------------------------------

/// The sheet's eyebrow. **AUTHORED** — screen 9's shape (eyebrow, title,
/// sub-line), this endpoint's subject.
const String kPeriodEditorEyebrow = 'Period event';

/// The sheet's sub-line, and the highest-value string in this task.
///
/// **AUTHORED.** It states the FULL-UPSERT rule in the user's own terms, at the
/// one moment it matters. Without it the endpoint's most surprising property —
/// clearing a field and saving removes it, permanently, with a 200 — is only
/// discoverable by losing something.
///
/// **It says the OPPOSITE of `kDayLogEditorMergeNote`, deliberately**, and the
/// two sheets sit on the same screen. That is not a copy inconsistency to be
/// smoothed over at the T25 pass: the endpoints behave oppositely, and the one
/// thing worse than two different sentences would be one sentence that is false
/// on one of them.
const String kPeriodEditorUpsertNote =
    'This save replaces the whole entry. Anything you leave empty is removed.';

/// The kind row's caption. **AUTHORED** — nothing draws this control.
///
/// `Type`, not `Kind`: `kind` is the wire's word for it and not one the user
/// has ever seen.
const String kPeriodEditorKindLabel = 'Type';

/// The flow row's caption. **AUTHORED** — `Flow`, the smallest claim of the
/// three candidates (`Flow` / `Flow level` / `Flow intensity`), none of which
/// is drawn or ratified anywhere.
const String kPeriodEditorFlowLabel = 'Flow';

/// The note field's caption and accessible name.
///
/// **EXTRACTED, singular** — `screen_11_day_detail.html` draws `Note` and
/// screen 11 already ships that section label, as does the day-log editor over
/// it. Screen 12's plural `Notes` is its own authored string on a screen whose
/// mockup draws no notes box at all.
const String kPeriodEditorNoteLabel = 'Note';

/// The Save CTA. **AUTHORED** — screen 9 ships `Save check-in`, screen 12
/// `Save symptom`, the day-log editor `Save day log`; each names its own
/// subject and none of them is this endpoint.
const String kPeriodEditorSaveLabel = 'Save period event';

/// The CTA's label while a previous attempt is showing a failure.
///
/// `expectRetryReissuesOneRequest` (`test/support/retry_trap.dart`) locates a
/// write screen's retry control by exactly this text or `'Retry'` — a P4b exit
/// criterion for every write screen, and screen 11 is named in it.
const String kPeriodEditorRetryLabel = 'Try again';

/// The delete affordance. **AUTHORED** — no mockup draws a delete anywhere in
/// the cycle module.
const String kPeriodEditorDeleteLabel = 'Delete this event';

/// The confirmation's question. **AUTHORED.**
const String kPeriodEditorDeleteConfirmTitle = 'Delete this event?';

/// The confirmation's body. **AUTHORED**, and it names what goes with the row
/// rather than saying "are you sure".
///
/// *"It cannot be undone"* is literally true from the user's side even though
/// the delete is a SOFT delete: no endpoint reads a tombstoned row, so once
/// this device drops its copy the note is unreachable. (Re-logging the same
/// kind on the same day revives that very row — same id, same `createdAt` —
/// but with whatever the new request carried, so it does not bring the note
/// back.)
const String kPeriodEditorDeleteConfirmBody =
    'This removes the event, its flow level and its note. It cannot be undone.';

/// The confirmation's destructive action. **AUTHORED.**
const String kPeriodEditorDeleteConfirmLabel = 'Delete';

/// The confirmation's dismissal. **SHIPPED-PRECEDENT** — `profile_screen.dart`'s
/// dialog, the app's only other one, labels its dismissal `Cancel`.
const String kPeriodEditorDeleteCancelLabel = 'Cancel';

// ---------------------------------------------------------------------------
// Opening it
// ---------------------------------------------------------------------------

/// Opens the period-event editor for [date] over whatever is on screen.
///
/// `enableDrag: false`, permanently: this sheet's Save and Delete are both
/// genuine in-flight writes, and drag-dismiss CANNOT be gated per-attempt —
/// `BottomSheet.onClosing` calls `Navigator.pop` directly and bypasses
/// `PopScope` (measured against the SDK; `showLumenBottomSheet`'s own dartdoc
/// carries the finding). The scrim tap and the system back gesture DO route
/// through `Navigator.maybePop`, so those stay gated live by the [PopScope]
/// inside [PeriodEditorScreen].
Future<void> showPeriodEditor(BuildContext context, DateTime date) {
  return showLumenBottomSheet<void>(
    context: context,
    enableDrag: false,
    builder: (_) => PeriodEditorScreen(date: date),
  );
}

// ---------------------------------------------------------------------------
// The sheet's content
// ---------------------------------------------------------------------------

/// The period editor's content, hosted inside a `LumenBottomSheet` by
/// [showPeriodEditor]. Not a route — it is a modal over screen 11.
///
/// `ConsumerStatefulWidget` for the [TextEditingController] alone; the form's
/// own state lives in [PeriodEditorController].
class PeriodEditorScreen extends ConsumerStatefulWidget {
  const PeriodEditorScreen({required this.date, super.key});

  /// The day being written — the route's own `:date`, already round-trip
  /// verified by `Routes.parseCycleDayDate`.
  ///
  /// **There is no date control on this sheet and there must not be one.**
  /// `occurredOn` IS a body field here, unlike the day log's path parameter, so
  /// one would be buildable — and it would be a lie. There is no move
  /// operation on `cycle_events`: changing the date writes a SECOND row at the
  /// new key and leaves the original live, and faking a move out of DELETE plus
  /// POST has no safe ordering (RULING T16-G). The date renders as the sheet's
  /// title so the user can see which day they are writing, and that is all.
  final DateTime date;

  @override
  ConsumerState<PeriodEditorScreen> createState() => _PeriodEditorScreenState();
}

class _PeriodEditorScreenState extends ConsumerState<PeriodEditorScreen> {
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    // Seeded ONCE from the form's own seed — `baseline_screen.dart`'s
    // precedent. Screen 12's `_NotesField` is the opposite shape (created
    // empty, never seeded) and is correct there because that form CREATES
    // rows; here an empty box is an ERASE INSTRUCTION, so opening blank over a
    // stored note would arm the wipe before the user had done anything.
    _notes = TextEditingController(
      text: ref.read(periodEditorControllerProvider(widget.date)).notes,
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Asks first, then deletes, then leaves.
  ///
  /// **The confirmation is not decoration.** This is the only irreversible
  /// action either sheet on screen 11 offers, and the house shape for one is
  /// `showDialog` + [AlertDialog] (`profile_screen.dart`, the app's only other
  /// dialog) — not a new pattern invented here.
  ///
  /// `confirmed != true` covers both the explicit Cancel and a barrier tap,
  /// which pops with `null`. Nothing is written on either.
  Future<void> _confirmAndDelete(PeriodEditorController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteConfirmationDialog(),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final deleted = await controller.delete();
    // Only a real deletion closes. On failure the sheet stays exactly as it is,
    // with the banner above the same button.
    if (deleted && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final provider = periodEditorControllerProvider(widget.date);
    final form = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final enabled = !form.busy;
    final bannerMessage = periodEditorBannerMessage(form.failure);
    final blockReason = form.blockReason;

    // **Re-seeds the note box when — and ONLY when — the selected KIND
    // changes.** The kind chip picks which row this sheet describes, so a new
    // kind means a new row and the box must show that row's own note. This is
    // the one place `baseline_screen.dart`'s "never re-seed, it moves the
    // cursor" rule is deliberately departed from, and the reason is that the
    // alternative is worse: carrying the old row's text over would post it onto
    // the new row and wipe the new row's own note, under FULL UPSERT. Keyed on
    // `kind` rather than on `notes`, so ordinary typing never rewrites the
    // field the user is typing into.
    ref.listen<PeriodEditorForm>(provider, (previous, next) {
      if (previous?.kind == next.kind) return;
      if (_notes.text == next.notes) return;
      _notes.text = next.notes;
    });

    return PopScope(
      // Blocks the scrim tap AND the system/predictive back gesture while
      // either write is in flight; both route through `Navigator.maybePop`,
      // which consults this freshly on every attempt.
      canPop: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const LumenSectionLabel(kPeriodEditorEyebrow),
          const SizedBox(height: 4),
          Text(
            // The day, from the route. `LumenFormats`, never a raw
            // `DateTime.toString()` and never a clock read.
            LumenFormats.monthDay(widget.date),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            kPeriodEditorUpsertNote,
            style: TextStyle(fontSize: 11, color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 18),

          const LumenFieldLabel(kPeriodEditorKindLabel),
          const SizedBox(height: 8),
          _KindChips(
            selected: form.kind,
            enabled: enabled,
            onSelect: controller.setKind,
          ),
          const SizedBox(height: 18),

          const LumenFieldLabel(kPeriodEditorFlowLabel),
          const SizedBox(height: 8),
          _FlowChips(
            selected: form.flowIntensity,
            enabled: enabled,
            onSelect: controller.setFlow,
          ),
          const SizedBox(height: 18),

          const LumenFieldLabel(kPeriodEditorNoteLabel, announce: false),
          const SizedBox(height: 8),
          LumenInputField(
            controller: _notes,
            label: kPeriodEditorNoteLabel,
            // Empty on purpose: no mockup draws a placeholder here, the caption
            // already names the field, and a hint would be another authored
            // string bought for nothing.
            hint: '',
            minLines: 3,
            maxLines: 5,
            // Mirrors `FieldLimits.MaxNotesLength = 2000`, which the server
            // applies AFTER trimming — so a raw cap at the same number can
            // never produce a value the server rejects for length. A structural
            // field limit, not a clinical bound (R-17).
            maxLength: 2000,
            enabled: enabled,
            onChanged: controller.setNotes,
          ),
          const SizedBox(height: 18),

          // The banner and the block reason sit DIRECTLY above the CTA, and the
          // whole sheet scrolls as one inside `LumenBottomSheet` — so the
          // message that explains a failure can never scroll away from the
          // control that produced it, and a screen reader's next swipe after
          // the announcement reaches "Try again".
          if (bannerMessage != null) ...<Widget>[
            LumenErrorBanner(message: bannerMessage),
            const SizedBox(height: 10),
          ],
          if (blockReason != null) ...<Widget>[
            // Rendered STRAIGHT from `PeriodEditorForm.blockReason`, never
            // composed here. Deliberately NOT a live region: it sits directly
            // above the control it disables.
            LumenFieldMessage(blockReason),
            const SizedBox(height: 8),
          ],
          FilledButton(
            // Gated on `canSubmit`, which is `blockReason == null && !busy` —
            // never a condition recomputed here. `submit()` carries the same
            // guard itself; this is the screen-level half of that pair.
            onPressed: !form.canSubmit
                ? null
                : () async {
                    final saved = await controller.submit();
                    if (saved && context.mounted) Navigator.of(context).pop();
                  },
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
                        ? kPeriodEditorRetryLabel
                        : kPeriodEditorSaveLabel,
                  ),
          ),

          // **Rendered only when there IS a row to delete.** A delete offered
          // for a kind this day has no event on could do nothing, and R-10's
          // rule for an affordance with no destination applies to an action
          // with no target: remove it, do not disable it.
          if (form.selectedEvent != null) ...<Widget>[
            const SizedBox(height: 6),
            TextButton(
              onPressed: form.canDelete
                  ? () => _confirmAndDelete(controller)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: c.muted,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              child: const Text(kPeriodEditorDeleteLabel),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The kind chips — the ROW SELECTOR
// ---------------------------------------------------------------------------

/// The three ratified cycle-event kinds as a single-select chip row.
///
/// **No deselect, and the selected chip is INERT — by having no callback, not
/// by ignoring one.** `LumenSelectableChip` only reports taps; whether a row is
/// a toggle or a radio is the caller's decision. A `null` `onTap` makes the
/// node drop its tap action and announce itself unavailable, which is the SAME
/// MECHANISM `LumenIntensityScale`'s `allowClear: false` stop uses — two
/// controls on one sheet expressing "this gesture is not offered" two different
/// ways is how one of them ends up lying.
///
/// See `PeriodEditorController.setKind` for why this row does not deselect
/// while [_FlowChips] does. Short version: `null` flow is a real wire value
/// and `null` kind is only a blocked save, and deselecting here would discard
/// a note the user had just typed.
class _KindChips extends StatelessWidget {
  const _KindChips({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  /// The selected `cycle_events.kind` code, or null.
  final String? selected;

  final bool enabled;

  /// Called with the WIRE CODE of the tapped chip — never a display label and
  /// never a list index. The codes are the vocabulary
  /// `CycleEvent.Kinds` declares; the labels only exist to be read.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final String code in kPeriodKindCodes)
          LumenSelectableChip(
            label: periodKindLabel(code),
            selected: selected == code,
            enabled: enabled,
            onTap: selected == code ? null : () => onSelect(code),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The flow chips — deselect-to-clear
// ---------------------------------------------------------------------------

/// The four PO-interim flow levels as a single-select chip row, with
/// deselect-to-clear.
///
/// **A re-tap of the selected chip CLEARS the level, and that is the only way
/// to remove one.** `LogCycleEventRequest`'s generated serializer omits a null
/// member, and this endpoint reads an absent `flowIntensity` as CLEAR — so a
/// null here is not "unspecified", it is a real, otherwise-unreachable
/// instruction. That is exactly why this row deselects where the kind row does
/// not, and why the selected chip keeps its tap action where the kind row's
/// loses it.
///
/// **`index + 1`, never a bare index.** `flowIntensity` is 1-based on the wire
/// (like `mood`, unlike `pain`); a row built on the list index writes
/// `spotting` when the user tapped `light`, which is a fabricated value that
/// looks completely real. The translation lives here and is deliberately not
/// re-derived in the controller.
///
/// **No clinical treatment of any level (RULING T16-C).** `Heavy` is the
/// fourth label and renders exactly like the other three: no icon, no colour
/// change beyond the shared chip's own selection tokens, no note, no warning.
class _FlowChips extends StatelessWidget {
  const _FlowChips({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  /// The WIRE ordinal (`1..4`) currently chosen, or null for "no level".
  final int? selected;

  final bool enabled;

  /// Called with the WIRE ordinal, or `null` to clear.
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final (int index, String label) in kFlowLabels.indexed)
          LumenSelectableChip(
            label: label,
            selected: selected == index + 1,
            enabled: enabled,
            onTap: () => onSelect(selected == index + 1 ? null : index + 1),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The delete confirmation
// ---------------------------------------------------------------------------

/// The house confirmation shape: `showDialog` + [AlertDialog], as
/// `profile_screen.dart` uses for the app's only other dialog.
///
/// Pops `true` for the destructive action and `false` for the dismissal; a
/// barrier tap pops `null`, and the caller treats anything that is not `true`
/// as "do nothing".
class _DeleteConfirmationDialog extends StatelessWidget {
  const _DeleteConfirmationDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(kPeriodEditorDeleteConfirmTitle),
      content: const Text(kPeriodEditorDeleteConfirmBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(kPeriodEditorDeleteCancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(kPeriodEditorDeleteConfirmLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Failure -> message
// ---------------------------------------------------------------------------

/// What the banner above the CTA says, or `null` when nothing is wrong.
///
/// The WRITE precedent (`goals_screen.dart` / `quick_checkin_screen.dart` /
/// screen 12's footer), not the read-failure generic-copy rule.
///
/// **Every one of this endpoint's field keys is promoted into the banner, and
/// that is a property of the sheet rather than laziness.** `occurredOn` has no
/// control here at all — it is the route's day, by RULING T16-G — and `kind`
/// and `flowIntensity` are closed selectors that can only emit legal values, so
/// their 400s are unreachable through the UI. The one key with a control the
/// user can genuinely put out of range is `notes`, and its length cap is
/// mirrored structurally on the field. So there is no per-field slot worth
/// building, and dropping a message that has no slot is how a user meets a
/// rejection with no explanation.
///
/// **`occurredOn` carries the backdate floor, and it can ONLY arrive as a
/// 400.** The floor is the user's account-creation day minus two years, and no
/// endpoint in the document exposes `users.created_at` — so nothing on the
/// device can pre-check it, and a client-side "earliest allowed day" would be a
/// fabrication. The future-day half is deliberately not pre-checked either:
/// `sessionTodayProvider` pins one `today` for the whole app session while the
/// server recomputes it per request, so an app left open across local midnight
/// would block a LEGAL write to the user's actual today.
@visibleForTesting
String? periodEditorBannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    if (crossField.isNotEmpty) return crossField.first;
    for (final key in const <String>[
      'occurredOn',
      'kind',
      'flowIntensity',
      'notes',
    ]) {
      final message = failure.messageFor(key);
      if (message != null) return message;
    }
    return failure.message;
  }
  return failure.message;
}
