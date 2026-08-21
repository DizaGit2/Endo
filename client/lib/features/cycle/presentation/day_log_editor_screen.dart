// Screen 11's day-log editor (P4b-T16b) — the first WRITE on the cycle
// module.
//
// A bottom sheet over screen 11, opened by `DayDetailScreen`'s
// [kDayDetailEditLogLabel] affordance and hosted by `showLumenBottomSheet`
// (screen 9's shipped modal idiom). Not a route: the day-detail route already
// carries the date, so the sheet needs no URL of its own and screen 11 stays
// mounted underneath — which is what keeps the view the form was seeded from
// on screen.
//
// **NOTHING HERE IS DRAWN BY A MOCKUP.** Screen 11's mockup has no text field,
// no scale, no CTA and no save state; its only interactive elements are the
// theme toggle (mockup chrome, never shipped) and two navigation stubs. Every
// string, control and metric below is either borrowed from a shipped sibling
// (screen 9's sheet, screen 12's footer) or authored — the authored ones are
// listed in the T16b report for the T25 PO copy pass.
//
// **The MERGE semantics are the design constraint, not a footnote.**
// `POST /cycle/day/{date}` leaves an omitted field unchanged and cannot clear
// one at all. So:
//
//  * the pain scale is built `allowClear: false` and the mood chips ignore a
//    re-tap of the selected chip — the endpoint cannot honour a clear, and a
//    control that looks like one would be a data lie;
//  * emptying the note box is a NO-OP on the server, and
//    [kDayLogEditorMergeNote] says so above the fields rather than leaving the
//    user to discover it from a 200 that changed nothing;
//  * Save is DISABLED, with the reason inline, when nothing the user touched
//    would survive to the wire — never a round trip that can only 400.
//
// **This is NOT the period-event editor.** `POST /cycle/events` is a FULL
// UPSERT where an omitted field is CLEARED, and an empty notes box there
// destroys the stored ciphertext. It is T16c, and it must not share a widget
// with this one: the two sheets have to look different because they behave
// oppositely.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/cycle/application/day_log_editor_controller.dart';
import 'package:lumen/shared/mood_labels.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';

// ---------------------------------------------------------------------------
// Authored copy
// ---------------------------------------------------------------------------

/// The sheet's eyebrow. **Authored** — screen 9's shape (eyebrow + title +
/// sub-line), screen 11's subject.
const String kDayLogEditorEyebrow = 'Day log';

/// The sheet's sub-line, and the highest-value string in this task.
///
/// **Authored.** It states the MERGE rule in the user's own terms, at the one
/// moment it matters. Without it the endpoint's most surprising property — an
/// emptied field is left alone, not removed — is only discoverable by trying
/// it and getting a 200 that changed nothing.
///
/// Both sentences are load-bearing and they are not the same claim: the first
/// explains why a field the user did not touch is safe (nothing is
/// overwritten by opening this sheet), the second explains why a field they
/// DID empty is not gone.
const String kDayLogEditorMergeNote =
    'Saved values stay unless you replace them. '
    'Emptying a field does not remove it.';

/// The Save CTA. **Authored** — screen 9 ships `Save check-in` and screen 12
/// `Save symptom`, both naming their own subject; nothing existing fits this
/// one, and neither of those endpoints is this one.
const String kDayLogEditorSaveLabel = 'Save day log';

/// The CTA's label while a previous attempt is showing a failure.
///
/// `expectRetryReissuesOneRequest` (`test/support/retry_trap.dart`) locates a
/// write screen's retry control by exactly this text or `'Retry'` — a P4b exit
/// criterion for every write screen, and screen 11 is named in it. The same
/// control that failed is what tries again, so there is exactly one place a
/// duplicate tap could come from.
const String kDayLogEditorRetryLabel = 'Try again';

/// The pain control's caption. **EXTRACTED** — `screen_09_quick_checkin.html`
/// draws `Pain level`, screen 9 ships it and screen 12 adopted it by ruling.
/// Reused rather than varied.
const String kDayLogEditorPainLabel = 'Pain level';

/// The mood control's caption. **EXTRACTED** — `screen_09_quick_checkin.html`
/// (`definitions.md`'s `s9.label_mood`).
const String kDayLogEditorMoodLabel = 'Mood';

/// The note field's caption and accessible name.
///
/// **EXTRACTED, singular** — `screen_11_day_detail.html` draws `Note` and
/// screen 11 already ships that section label. Screen 12 ships the plural
/// `Notes`, which is its own authored string on a screen whose mockup draws no
/// notes box at all. With this sheet sitting directly over screen 11's `NOTE`
/// card, matching the card is the smaller claim.
const String kDayLogEditorNoteLabel = 'Note';

// ---------------------------------------------------------------------------
// Opening it
// ---------------------------------------------------------------------------

/// Opens the day-log editor for [date] over whatever is on screen.
///
/// `enableDrag: false`, permanently: this sheet's Save can be a genuine
/// in-flight write, and drag-dismiss CANNOT be gated per-attempt —
/// `BottomSheet.onClosing` calls `Navigator.pop` directly and bypasses
/// `PopScope` (measured against the SDK; `showLumenBottomSheet`'s own dartdoc
/// carries the finding). The scrim tap and the system back gesture DO route
/// through `Navigator.maybePop`, so those stay gated live by the [PopScope]
/// inside [DayLogEditorScreen].
Future<void> showDayLogEditor(BuildContext context, DateTime date) {
  return showLumenBottomSheet<void>(
    context: context,
    enableDrag: false,
    builder: (_) => DayLogEditorScreen(date: date),
  );
}

// ---------------------------------------------------------------------------
// The sheet's content
// ---------------------------------------------------------------------------

/// The day-log editor's content, hosted inside a `LumenBottomSheet` by
/// [showDayLogEditor]. Not a route — it is a modal over screen 11.
///
/// `ConsumerStatefulWidget` for the [TextEditingController] alone: the form's
/// own state lives in [DayLogEditorController].
class DayLogEditorScreen extends ConsumerStatefulWidget {
  const DayLogEditorScreen({required this.date, super.key});

  /// The day being written — the route's own `:date`, already round-trip
  /// verified by `Routes.parseCycleDayDate`.
  ///
  /// **There is no date control on this sheet and there must not be one.**
  /// The day is the endpoint's path parameter, not a body field, so there is
  /// nothing a date picker could change without navigating somewhere else
  /// first; and `POST /cycle/day/{date}` has no move operation to build one
  /// out of. The date is rendered as the sheet's title so the user can see
  /// which day they are writing, and that is all.
  final DateTime date;

  @override
  ConsumerState<DayLogEditorScreen> createState() => _DayLogEditorScreenState();
}

class _DayLogEditorScreenState extends ConsumerState<DayLogEditorScreen> {
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    // Seeded ONCE, here, and never re-seeded — `baseline_screen.dart`'s
    // precedent, for its reason: rewriting a field's text while somebody is
    // typing in it moves their cursor. Screen 12's `_NotesField` is the
    // opposite shape (created empty, never seeded) and is correct there
    // because that form CREATES rows; this one edits a day that may already
    // have a note, and opening it blank would invite the user to retype what
    // is already stored.
    //
    // Seeding does NOT mark the field touched: the controller's own seed is
    // untouched by construction, so a note that is merely displayed here is
    // never sent back.
    _notes = TextEditingController(
      text: ref.read(dayLogEditorControllerProvider(widget.date)).notes,
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final form = ref.watch(dayLogEditorControllerProvider(widget.date));
    final controller = ref.read(
      dayLogEditorControllerProvider(widget.date).notifier,
    );
    final enabled = !form.submitting;
    final bannerMessage = dayLogEditorBannerMessage(form.failure);
    final blockReason = form.blockReason;

    // `canPop: !form.submitting` blocks the scrim tap AND the system/
    // predictive back gesture while a write is in flight; both route through
    // `Navigator.maybePop`, which consults this freshly on every attempt.
    // Without it, dismissing mid-submit lets the write commit while
    // `submit()`'s own `!ref.mounted` guard (correctly) skips the dependent
    // refresh — leaving screen 11 rendering pre-write data with nothing on
    // screen saying so.
    return PopScope(
      canPop: enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const LumenSectionLabel(kDayLogEditorEyebrow),
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
            kDayLogEditorMergeNote,
            style: TextStyle(fontSize: 11, color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 18),

          // announce: false — the scale carries its own semanticsLabel, so an
          // announced caption here would be a duplicate "Pain level" in the
          // reading order (screen 9's precedent).
          const LumenFieldLabel(kDayLogEditorPainLabel, announce: false),
          const SizedBox(height: 8),
          LumenIntensityScale(
            value: form.pain,
            enabled: enabled,
            // R3 — the endpoint cannot express a clear, so this surface does
            // not offer the gesture. See the widget's own `allowClear` doc.
            allowClear: false,
            semanticsLabel: kDayLogEditorPainLabel,
            onChanged: controller.setPain,
          ),
          const SizedBox(height: 18),

          // announce: true (the default) — no single chip below carries
          // "Mood" as its own name; each announces its own mood word.
          const LumenFieldLabel(kDayLogEditorMoodLabel),
          const SizedBox(height: 8),
          _MoodChips(
            selected: form.mood,
            enabled: enabled,
            onSelect: controller.setMood,
          ),
          const SizedBox(height: 18),

          const LumenFieldLabel(kDayLogEditorNoteLabel, announce: false),
          const SizedBox(height: 8),
          LumenInputField(
            controller: _notes,
            label: kDayLogEditorNoteLabel,
            // Empty on purpose: screen 11's mockup draws no placeholder for
            // the note, the caption above already names the field, and a hint
            // would be another authored string bought for nothing.
            hint: '',
            minLines: 3,
            maxLines: 5,
            // Mirrors `FieldLimits.MaxNotesLength = 2000`, which the server
            // applies AFTER trimming — so a raw cap at the same number can
            // never produce a value the server rejects for length. A
            // structural field limit, not a clinical bound (R-17).
            maxLength: 2000,
            enabled: enabled,
            onChanged: controller.setNotes,
          ),
          const SizedBox(height: 18),

          // The banner and the block reason sit DIRECTLY above the CTA, and
          // the whole sheet scrolls as one inside `LumenBottomSheet` — so the
          // message that explains a failure can never scroll away from the
          // control that caused it, and a screen reader's next swipe after
          // the announcement reaches "Try again". Screen 12's footer ruling,
          // applied to a sheet.
          if (bannerMessage != null) ...<Widget>[
            LumenErrorBanner(message: bannerMessage),
            const SizedBox(height: 10),
          ],
          if (blockReason != null) ...<Widget>[
            // Rendered STRAIGHT from `DayLogEditorForm.blockReason`, never
            // composed here — the two messages are named constants and their
            // priority order lives in one getter.
            //
            // Deliberately NOT a live region: it sits directly above the
            // control it disables, and a live region would re-announce on
            // every keystroke in the note box.
            LumenFieldMessage(blockReason),
            const SizedBox(height: 8),
          ],
          FilledButton(
            // Gated on `canSubmit`, which is `blockReason == null` — never on
            // a condition recomputed here. `submit()` carries the same guard
            // itself; this is the screen-level half of that pair.
            onPressed: (!form.canSubmit || form.submitting)
                ? null
                : () async {
                    final saved = await controller.submit();
                    // Only `true` closes. On failure the sheet stays exactly
                    // as it is, with every answer intact and the banner above
                    // the same button — leaving would discard the edit
                    // silently.
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
                        ? kDayLogEditorRetryLabel
                        : kDayLogEditorSaveLabel,
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The mood chips
// ---------------------------------------------------------------------------

/// The four ratified moods as a single-select chip row.
///
/// **`LumenSelectableChip`, not screen 9's `_MoodGrid`.** The grid is private
/// to `quick_checkin_screen.dart` and carries its own `sentiment_*` glyph
/// mapping with a ruling attached (`sentiment_satisfied` is skipped, because
/// "Steady" names a plateau and not a positive judgement). Copying it here
/// would put that mapping in two places, where a drift shows the user a
/// different face for the same logged mood; promoting it would add a shared
/// widget for a second caller, below the promotion threshold this codebase
/// states (two private copies plus a third caller). The chip is the shipped
/// primitive for choosing one value out of a ratified vocabulary, which is
/// exactly what this is, and it costs no new mapping at all.
///
/// **Single-select, and re-tapping the selected chip does NOTHING.** The chip
/// widget only reports taps; whether a row is a toggle or a radio is the
/// caller's decision. This caller makes it a radio with no deselect, for the
/// same reason the pain scale is built `allowClear: false`: mood cannot be
/// un-logged on this endpoint, so a deselect gesture would clear the form and
/// change nothing on the server.
class _MoodChips extends StatelessWidget {
  const _MoodChips({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  /// The WIRE ordinal (`1..4`) currently chosen, or null.
  final int? selected;

  final bool enabled;

  /// Called with the WIRE ordinal of the tapped chip — `index + 1`, never a
  /// bare list index. Mood is 1-based on the wire (pain is 0-based); a row
  /// built on the list index alone writes `low` when the user tapped
  /// `tired`, which is a fabricated value that looks completely real and, on
  /// an endpoint with no delete, is permanent. The `+ 1` below is the whole
  /// fix for that hazard and is deliberately not re-derived in the
  /// controller.
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final (int index, String label) in kMoodLabels.indexed)
          LumenSelectableChip(
            label: label,
            selected: selected == index + 1,
            enabled: enabled,
            onTap: () {
              if (selected == index + 1) return;
              onSelect(index + 1);
            },
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
/// screen 12's footer), not the read-failure generic-copy rule: this
/// endpoint's `request`-keyed cross-field sentence is the one thing a user
/// could act on, and suppressing it in favour of generic copy would hide it.
///
/// The `date` key is checked after `request` and is the reason this function
/// is not simply `failure.message`. `POST /cycle/day/{date}` rejects a future
/// day under the key **`date`** — a ROUTE parameter, so there is no field on
/// this sheet for that message to bind to. It is promoted into the banner
/// rather than dropped. Deliberately NOT pre-checked on the device: the
/// server's `today` is the user's own timezone day recomputed per request,
/// while `sessionTodayProvider` pins one value for the whole app session, so
/// an app left open across midnight would block a legal write to the user's
/// actual today.
@visibleForTesting
String? dayLogEditorBannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    if (crossField.isNotEmpty) return crossField.first;
    final dateMessage = failure.messageFor('date');
    if (dateMessage != null) return dateMessage;
    return failure.message;
  }
  return failure.message;
}
