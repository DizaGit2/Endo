// Screen 12 — the symptom form (P4b-T20b, the screen half of T20).
//
// The whole headless half already shipped at T20a and is NOT re-implemented
// here: `SymptomForm` owns every guard, block reason and error lookup,
// `assembleSymptomBatch` owns the wire mapping, and `SymptomFormController`
// owns the state machine and `submit()`. **Read
// `application/symptom_form.dart` before changing anything in this file** —
// if a rule looks missing here it is because it lives there, and a second
// copy of it would be a defect rather than thoroughness.
//
// What this file owns, and nothing else does:
//  * rendering the four ratified vocabularies COMPLETE and in FROZEN
//    declaration order (R-14) — `symptom_vocabulary.dart` is the order;
//  * the SELECTION DISCIPLINE `LumenSelectableChip` deliberately refuses
//    (its own dartdoc: "whether a row is single-select or multi-select … is
//    decided by the caller") — LOCATION single-select with
//    deselect-to-clear, the other three multi-select;
//  * the chip -> per-chip-intensity disclosure, as a stacked list BELOW the
//    whole RELATED row (S5);
//  * freezing every control while a save is in flight (S8), which is what
//    makes T20a's retained-draft error binding sound: the selection cannot
//    change between the submit and the response;
//  * binding each rejection to its row through `painRowError` /
//    `relatedRowError` — never by parsing a key here (S9).
//
// Cut from `Screens/screen_12_symptom_form.html`, and why:
//  * the four PRE-SELECTED chips (including the sensitive trigger
//    `intercourse`) — a design fixture, not seed data. The form opens empty
//    (S2/R11) and nothing is carried forward from screen 9 (R-13: a
//    whole-day pain score is a different table and a different semantic from
//    a per-symptom intensity).
//  * the `✦ Tap body map for precise location` card — its destination is
//    screen 13, which does not exist until T21, and R-10 removes inert
//    navigation rather than disabling it. T21 ships the card and the route
//    together (R-20).
//  * the mockup's 3-4 chips per row — a design sample, not the vocabulary.
//    Every row renders in full; there is no "show more" affordance, because
//    R-14's "progressive disclosure" is the chip->intensity one below, and
//    the mockup draws no collapse, no expand and no "+N more" (S4).
//  * the inert `‹` — replaced with a real back affordance (this is a pushed
//    route, so there is something to pop back to), disabled mid-write.
//
// Added, with no mockup element behind it: the notes box (R3 — one per
// episode) and the block-reason line above the CTA (the `goals_screen.dart`
// precedent: "the reason is never left to be guessed").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/application/symptom_form_controller.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_label.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_section_label.dart';
import 'package:lumen/shared/widgets/lumen_selectable_chip.dart';

/// The save affordance's label while a previous attempt failed.
///
/// The SAME control relabels rather than a second one appearing beside
/// "Save symptom" — screen 9's `kQuickCheckinRetryLabel` precedent, and what
/// makes `expectRetryReissuesOneRequest`'s "exactly one request" assertion
/// meaningful: there is exactly one place a duplicate tap could come from.
/// It must stay a member of `test/support/retry_trap.dart`'s `kRetryLabels`;
/// a dedicated test pins that.
const String kSymptomFormRetryLabel = 'Try again';

/// The save affordance's label at rest — the mockup's own button copy.
const String kSymptomFormSaveLabel = 'Save symptom';

/// The key on the pain row's intensity block.
///
/// This screen can render up to 21 intensity scales at once and every one of
/// them draws stops labelled `0`..`10`, so nothing in the rendered text can
/// tell two blocks apart. The keys exist so a test (and a screen reader's
/// user, via [LumenIntensityScale.semanticsLabel]) can address one
/// specific block — the `goalTileKey` precedent in `goals_screen.dart`.
const Key kSymptomPainIntensityKey = ValueKey<String>('symptom-intensity-pain');

/// The key on the intensity block disclosed for RELATED symptom [code].
Key symptomIntensityKey(String code) =>
    ValueKey<String>('symptom-intensity-$code');

/// The per-entry field names a rejection of ONE row can carry, in the order
/// this screen looks them up — first non-null wins.
///
/// **This is not a key parser (S9).** Each name below is handed whole to
/// `SymptomForm.painRowError` / `relatedRowError`, which resolve the row
/// index against the RETAINED submitted drafts; this list only decides which
/// of a row's own fields to ask about, and every name is one the server
/// keys unindexed (`SymptomService.cs`'s `Normalize`: `$"{path}.intensity"`,
/// `$"{path}.region"`, …).
///
/// `painTypes` and `triggers` are deliberately ABSENT: the server keys those
/// per MEMBER (`entries[0].painTypes[1]`, `SymptomService.cs:576`), so
/// resolving one would mean re-deriving the assembler's own frozen ordering
/// here to learn which member index a chip became — a second copy of
/// `_inFrozenOrder`, which is exactly the duplication T20a's split exists to
/// prevent. Such a rejection surfaces in the banner instead, which every
/// failure raises anyway.
///
/// `notes` is absent for a different reason: the note has a CONTROL of its
/// own on this screen, so its rejection belongs under that box rather than
/// under whichever row the assembler happened to attach it to — see
/// [_notesError].
const List<String> _kRowErrorFields = <String>[
  'intensity',
  'symptomCode',
  'region',
  'side',
  'occurredAt',
];

// ---------------------------------------------------------------------------
// SymptomFormScreen
// ---------------------------------------------------------------------------

/// Screen 12 — the symptom form.
///
/// Mounted as a TOP-LEVEL route OUTSIDE the tab shell (`Routes.symptomsNew`,
/// `/symptoms/new`, `app_router.dart`), the same shape `/onboarding` and
/// `/account` already have: the mockup draws no bottom nav, and this is a
/// task flow you enter and leave. Exactly one URL (R-19), pushed from
/// whichever branch the user was in, so popping returns them to it with that
/// branch's back stack intact.
class SymptomFormScreen extends ConsumerWidget {
  const SymptomFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final form = ref.watch(symptomFormControllerProvider);
    final controller = ref.read(symptomFormControllerProvider.notifier);

    // `canPop: !form.submitting` — screen 9's I-3 fix, applied to a pushed
    // route instead of a sheet. Both the system/predictive back gesture and
    // `Navigator.maybePop` consult this freshly on every attempt, so a write
    // in flight cannot be abandoned half-way: the batch is all-or-nothing,
    // and leaving mid-write would let the rows commit while `submit()`'s own
    // `!ref.mounted` guard (correctly) skips the dependent-screen refresh,
    // leaving every open screen rendering a day that no longer exists.
    return PopScope(
      canPop: !form.submitting,
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The back chevron — a pushed route has something to pop back
              // to, unlike the branch roots.
              //
              // **In the LAYOUT, not a `Positioned` over the scroll view** —
              // where screen 11 (`day_detail_screen.dart`) puts its own, and
              // where this screen's mockup draws it. Screen 11 is a READ
              // surface: nothing that scrolls under its chevron was ever
              // tappable, so the overlap costs nothing there. This screen has
              // 41 chips plus up to 21 scales, and anything that comes to rest
              // in the chevron's own 48x48 corner would silently stop
              // accepting taps. The rendered result is the mockup's anyway —
              // the chevron sits at the top left and the content begins below
              // it, exactly as the mockup's `padding:44px` arranges.
              //
              // `semanticLabel` on the Icon, never `tooltip:`, which Material
              // surfaces as a SEPARATE semantics field rather than the
              // button's own name (screen 11's finding). The word itself is
              // `MaterialLocalizations`' — the platform's own, translated,
              // name for this control, not copy this screen invented (the
              // onboarding shell's precedent).
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(
                      Icons.chevron_left,
                      semanticLabel: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                    ),
                    color: c.muted,
                    // S8 — frozen mid-write like every other control, so this
                    // is not a second way around the PopScope above.
                    onPressed: form.submitting ? null : () => context.pop(),
                  ),
                ),
              ),
              // S7 — the form scrolls, the CTA does not. Content runs to
              // several viewports (up to ~21 full-width scales alone), and a
              // CTA that scrolls away carries the block reason explaining why
              // it is disabled away with it. `T9b` pinned the onboarding CTA
              // against its shell for the same reason.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                  child: _FormBody(form: form, controller: controller),
                ),
              ),
              _Footer(form: form, controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The scrolling body
// ---------------------------------------------------------------------------

/// Everything above the pinned footer, top to bottom.
class _FormBody extends StatelessWidget {
  const _FormBody({required this.form, required this.controller});

  final SymptomForm form;
  final SymptomFormController controller;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final enabled = !form.submitting;
    final bannerMessage = _bannerMessage(form.failure);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (bannerMessage != null) ...<Widget>[
          LumenErrorBanner(message: bannerMessage),
          const SizedBox(height: 16),
        ],

        // The mockup's `.tag` — 11 px, sage, uppercase, 1.5 px tracking.
        const LumenSectionLabel(
          'Log symptom',
          fontSize: 11,
          letterSpacing: 1.5,
        ),
        const SizedBox(height: 4),
        Semantics(
          header: true,
          child: Text(
            'Pain details',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // The pain row comes FIRST, before LOCATION — the mockup draws no
        // pain row at all, so this placement is a ruling rather than a copy.
        // LOCATION/TYPE/TRIGGERS are attributes OF the pain row (which is why
        // selecting one with no pain level blocks the save at all — R1's
        // "no carrier"), so the thing they attach to has to precede them or
        // the coupling is invisible. The screen is titled "Pain details".
        _IntensityBlock(
          key: kSymptomPainIntensityKey,
          label: 'Pain level',
          // The pain row's own scale keeps screen 9's shipped string rather
          // than inventing a twelfth one — the smallest claim available.
          semanticsLabel: 'Pain level',
          value: form.painIntensity,
          enabled: enabled,
          onChanged: controller.setPainIntensity,
          errorMessage: _painRowError(form),
        ),
        const SizedBox(height: 14),

        _ChipRow(
          label: 'Location',
          labels: kRegionLabels,
          enabled: enabled,
          isSelected: (code) => form.region == code,
          // Single-select WITH deselect-to-clear: tapping the chip that is
          // already selected clears the region entirely. Without it a
          // mistaken region tap is permanent for the life of the form — the
          // screen draws no other route back to "no location", and
          // `unspecified` is deliberately not a chip.
          onTap: (code) =>
              controller.setRegion(form.region == code ? null : code),
        ),
        const SizedBox(height: 14),

        _ChipRow(
          label: 'Type',
          labels: kPainTypeLabels,
          enabled: enabled,
          isSelected: form.painTypes.contains,
          onTap: controller.togglePainType,
        ),
        const SizedBox(height: 14),

        _ChipRow(
          label: 'Triggers',
          labels: kTriggerLabels,
          enabled: enabled,
          isSelected: form.triggers.contains,
          onTap: controller.toggleTrigger,
        ),
        const SizedBox(height: 14),

        _ChipRow(
          label: 'Related',
          labels: kSymptomCodeLabels,
          enabled: enabled,
          isSelected: form.relatedIntensities.containsKey,
          onTap: controller.toggleRelated,
        ),

        // S5 — one intensity block per SELECTED related chip, stacked below
        // the WHOLE row and iterated over the VOCABULARY rather than over
        // `relatedIntensities.keys` (which is selection order). Frozen order
        // is what stops the list reordering under the user on every tap; a
        // ~55 px full-width scale inserted into the chip `Wrap` instead would
        // reflow the row itself, destabilising the very ordering R-14 exists
        // to protect.
        for (final MapEntry<String, String> entry in kSymptomCodeLabels.entries)
          if (form.relatedIntensities.containsKey(entry.key)) ...<Widget>[
            const SizedBox(height: 14),
            _IntensityBlock(
              key: symptomIntensityKey(entry.key),
              label: entry.value,
              // S6 — '<Chip label> intensity'. `LumenIntensityScale` requires
              // a label, has no default and no auto-numbering, and this
              // screen may render 21 of them; without this convention every
              // one of them announces the same thing.
              semanticsLabel: '${entry.value} intensity',
              value: form.relatedIntensities[entry.key],
              enabled: enabled,
              onChanged: (value) =>
                  controller.setRelatedIntensity(entry.key, value),
              errorMessage: _relatedRowError(form, entry.key),
            ),
          ],

        const SizedBox(height: 18),
        const LumenFieldLabel('Notes', announce: false),
        const SizedBox(height: 6),
        _NotesField(
          enabled: enabled,
          // A note is attached to the batch's FIRST entry (R3), so the server
          // keys any rejection of it on that row — which is the pain row when
          // one exists. Read back through the same row lookup rather than a
          // key of its own.
          errorMessage: _notesError(form),
          onChanged: controller.setNotes,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One chip row
// ---------------------------------------------------------------------------

/// A `LumenFieldLabel` over a wrap of [LumenSelectableChip]s, one per entry of
/// [labels] in that map's own declaration order.
///
/// [label] is passed in SENTENCE case (S1). `LumenFieldLabel` uppercases it
/// for the eye and announces the string it was GIVEN — pass `LOCATION` and a
/// screen reader spells it out letter by letter, the exact defect that widget
/// exists to prevent and that this phase has shipped once already.
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.labels,
    required this.enabled,
    required this.isSelected,
    required this.onTap,
  });

  final String label;

  /// Wire code -> ratified display label, in frozen declaration order.
  final Map<String, String> labels;

  final bool enabled;

  /// Whether the chip for this wire code is currently chosen.
  final bool Function(String code) isSelected;

  /// Invoked with the WIRE CODE of the tapped chip — never its label, and
  /// never a list index.
  final void Function(String code) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // announce: true (the default) — the chips below carry only their own
        // words, so without this the row itself has no name at all.
        LumenFieldLabel(label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final MapEntry<String, String> entry in labels.entries)
              LumenSelectableChip(
                label: entry.value,
                selected: isSelected(entry.key),
                enabled: enabled,
                onTap: () => onTap(entry.key),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One intensity block
// ---------------------------------------------------------------------------

/// A label, a [LumenIntensityScale] and that row's rejection slot.
///
/// Used for the pain row and for every disclosed RELATED chip, so the two
/// cannot drift apart in spacing, in disabled behaviour or in where their
/// error lands.
class _IntensityBlock extends StatelessWidget {
  const _IntensityBlock({
    required this.label,
    required this.semanticsLabel,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.errorMessage,
    super.key,
  });

  /// Drawn above the scale, in sentence case (S1).
  final String label;

  /// What the scale announces — `Pain level`, or `<Chip label> intensity`.
  final String semanticsLabel;

  /// The logged intensity, or `null` for "not recorded". **`0` is a real
  /// datum** and is passed straight through; nothing here tests it for
  /// truthiness.
  final int? value;

  final bool enabled;
  final ValueChanged<int?> onChanged;

  /// The server's own sentence for this row, or `null`.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // announce: false — the scale below carries [semanticsLabel] as its
        // OWN name, so announcing this caption too would put a second,
        // unassociated copy of it in the reading order (screen 9's precedent
        // for the identical pairing).
        LumenFieldLabel(label, announce: false),
        const SizedBox(height: 6),
        LumenIntensityScale(
          value: value,
          enabled: enabled,
          semanticsLabel: semanticsLabel,
          onChanged: onChanged,
        ),
        if (message != null) ...<Widget>[
          const SizedBox(height: 6),
          LumenFieldMessage(message),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The notes box
// ---------------------------------------------------------------------------

/// R3's one notes box per episode.
///
/// Stateful for the [TextEditingController] alone. It is created EMPTY and
/// never re-seeded from [SymptomForm.notes]: the form opens empty (S2) and
/// nothing else writes that field, so re-seeding could only ever move
/// somebody's cursor while they type. The `baseline_screen.dart` precedent,
/// minus its resume-read seeding, which this screen has no equivalent of.
class _NotesField extends StatefulWidget {
  const _NotesField({
    required this.enabled,
    required this.errorMessage,
    required this.onChanged,
  });

  final bool enabled;
  final String? errorMessage;
  final ValueChanged<String> onChanged;

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LumenInputField(
      controller: _notes,
      // The same string the caption above the box draws — Flutter has no
      // `aria-labelledby`, so a field with only hint text announces its
      // PLACEHOLDER (`LumenInputField`'s own dartdoc).
      label: 'Notes',
      // **Empty on purpose** — `baseline_screen.dart`'s precedent for a field
      // its mockup draws no placeholder for. Screen 12's mockup draws no
      // notes box AT ALL, so any placeholder here would be a fifth authored
      // string on a screen whose copy is already queued for a PO/clinician
      // pass (§T25), bought for nothing: the "NOTES" caption above the box
      // and this field's own accessible name already say what it is.
      hint: '',
      // `minLines` is what makes this read as a notes box on first paint
      // rather than a one-line field that grows; `maxLength` mirrors the
      // contract's own `FieldLimits.MaxNotesLength = 2000`, which the server
      // applies AFTER trimming — so a raw cap at the same number can never
      // produce a value the server rejects for length. A structural field
      // limit, not a clinical bound (R-17).
      minLines: 3,
      maxLines: 5,
      maxLength: 2000,
      enabled: widget.enabled,
      errorText: widget.errorMessage,
      onChanged: widget.onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// The pinned footer
// ---------------------------------------------------------------------------

/// The block reason and the CTA — outside the scroll view, always on screen.
class _Footer extends StatelessWidget {
  const _Footer({required this.form, required this.controller});

  final SymptomForm form;
  final SymptomFormController controller;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final blockReason = form.blockReason;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (blockReason != null) ...<Widget>[
            // Rendered STRAIGHT from `SymptomForm.blockReason`, never composed
            // here — the four messages are named constants in
            // `symptom_form.dart` and their priority order is one of T20a's
            // rulings (R8).
            //
            // Deliberately NOT a live region, where `goals_screen.dart`'s
            // equivalent is one: that screen's reason sits at the opposite end
            // of the page from the control it disables, and this one is
            // directly above it. A live region here would also re-announce on
            // every one of 41 chip taps.
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
                    // S11 — only `true` pops. On failure the screen stays
                    // exactly as it was, with every selection intact: the
                    // batch is all-or-nothing and will later carry the work
                    // the user did on screen 13.
                    if (saved && context.mounted) context.pop();
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
                        ? kSymptomFormRetryLabel
                        : kSymptomFormSaveLabel,
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Failure -> message
// ---------------------------------------------------------------------------

/// What the banner at the top says, or `null` when nothing is wrong.
///
/// The WRITE precedent (`goals_screen.dart`/`quick_checkin_screen.dart`), not
/// the read-failure generic-copy rule: the server's own `request`-keyed
/// cross-field sentence is the one thing the user could act on, and
/// suppressing it in favour of generic copy would hide it.
///
/// The `entries` key is checked second because it is BOTH a server-side
/// batch-level rejection AND the key `SymptomsRepository.createBatch` uses
/// for its own client-side R-18 size refusal — one string either way, in the
/// server's own words. A per-ROW rejection (`entries[3].intensity`) matches
/// neither and falls through to the generic message, which is correct: that
/// message renders beside the row it names, and the banner's job here is only
/// to announce (it is a live region) that the save failed at all.
String? _bannerMessage(Failure? failure) {
  if (failure == null) return null;
  if (failure is ValidationFailure) {
    final crossField = failure.requestMessages;
    if (crossField.isNotEmpty) return crossField.first;
    final batch = failure.messagesFor('entries');
    if (batch.isNotEmpty) return batch.first;
    return failure.message;
  }
  return failure.message;
}

/// The pain row's own rejection, or `null` — resolved through
/// [SymptomForm.painRowError], which uses the index the pain row occupied in
/// the RETAINED submitted batch, never wherever it would land today.
String? _painRowError(SymptomForm form) {
  for (final String field in _kRowErrorFields) {
    final String? message = form.painRowError(field);
    if (message != null) return message;
  }
  return null;
}

/// RELATED row [code]'s own rejection, or `null` — resolved by searching the
/// retained submitted drafts for that code (R9), so a selection change made
/// after the submit cannot move the message onto a different chip.
String? _relatedRowError(SymptomForm form, String code) {
  for (final String field in _kRowErrorFields) {
    final String? message = form.relatedRowError(code, field);
    if (message != null) return message;
  }
  return null;
}

/// The rejection of the note itself, which the assembler attached to the
/// batch's FIRST entry (R3): the pain row when one exists, else the first
/// RELATED row in frozen order.
///
/// Asked of the same two getters rather than of a key of its own — there is
/// no `notes` key at the top level of this endpoint's error map, only
/// `entries[N].notes`.
String? _notesError(SymptomForm form) {
  final String? onPainRow = form.painRowError('notes');
  if (onPainRow != null) return onPainRow;
  for (final String code in kSymptomCodeLabels.keys) {
    if (!form.relatedIntensities.containsKey(code)) continue;
    final String? message = form.relatedRowError(code, 'notes');
    if (message != null) return message;
  }
  return null;
}
