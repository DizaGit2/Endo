// Screen 11 — the day detail (P4b-T16, READ SURFACE ONLY).
//
// The drill-in from screen 10: "what did I log on April 7?" It reads two
// endpoints (`GET /cycle/day/{date}`, `GET /symptoms?from&to`), renders what
// it finds, and navigates nowhere. This is a SPLIT task — see the T16 brief
// for the full reasoning — and this file writes nothing to the API. No
// `POST`, no `DELETE`. The period-event editor and the day-log editor land
// in T16b, after T18 has given `LumenBottomSheet`/`LumenIntensityScale`
// their debut production caller and T20 has given the mockup's "Edit"
// affordance a real destination.
//
// Cuts from the mockup, and why (T16 brief §4 has the full citations):
//  * the `.dp` phase badge ("Luteal · Day 20") — CycleDayResponse carries no
//    phase member at all. Screen 11 renders NO phase treatment — not the
//    badge, not the unavailable envelope. **Not because a second network
//    read would be needed** — `sessionTodayProvider` already issues that
//    exact `GET /cycle/calendar` and pins it for the session
//    (`server_today.dart`), and `phaseUnavailableCopy` resolves EVERY
//    reason, including `null`, to the same neutral copy with no read at
//    all (`lumen_phase_unavailable.dart`) — both checked; neither is the
//    reason. The real reason: screen 10 is one tap away and already
//    carries the phase-unavailable block, so repeating a constant string
//    on every day view is noise, not information. (T23, this is
//    deliberate, not an oversight — the ruling stands even though this
//    file's earlier justification for it did not.)
//  * the energy half of "Mood & energy" — D-10 defers energy entirely (no
//    writer, no DTO, no scale in P4a). The section is renamed "Pain & mood"
//    and renders the day-log's own `pain` (which the mockup draws no
//    section for at all) alongside `mood`.
//  * the Activity section — module is P5.
//  * `Edit` and `+ Add to this day` — both point at screens that do not
//    exist yet (screen 12/T20, the period-event editor/T16b). R-10 removes
//    inert navigation rather than disabling it.
//
// Section header colour: the mockup's CSS (`.sl span:last-child`) happens to
// colour "Mood & energy", "Activity" and "Note" accent too, because each is
// its OWN last child once "Edit" is the only header with two spans. That
// rule exists to colour the right-hand ACTION. Only `Edit` was ever meant to
// be accent, and `Edit` is cut — so no section header renders accent here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';

// ---------------------------------------------------------------------------
// Ratified vocabulary labels this screen renders
// ---------------------------------------------------------------------------
//
// Sourced from `survey/decisions-and-vocabularies.md` §2.2-2.6, which is
// itself sourced from `definitions.md`'s frozen 2026-07-08 ratification
// block plus the backend's own frozen enum declarations. These sets are
// APPEND-ONLY on the wire; a code absent from a map below has no ratified
// label and is a vocabulary gap to REPORT, not to invent a rendering for.

/// Display label for each of the 20 non-pain `symptomCode` values.
/// `pain` is deliberately absent — see [_symptomCodeLabel]'s dartdoc.
const Map<String, String> _kSymptomCodeLabels = <String, String>{
  'bloating': 'Bloating',
  'nausea': 'Nausea',
  'fatigue': 'Fatigue',
  'diarrhea': 'Diarrhea',
  'constipation': 'Constipation',
  'headache': 'Headache',
  'dizziness': 'Dizziness',
  'inflammation': 'General inflammation',
  'water_retention': 'Fluid retention',
  'joint_pain': 'Cramping / joint pain',
  'frequent_urination': 'Frequent urination',
  'frequent_bowel_movements': 'Frequent bowel movements',
  'indigestion': 'Indigestion',
  // The RATIFIED label — definitions.md's frozen ratification block. C-14 /
  // R-16 (`lumen-build.md:870`) recommend "Low mood" instead, but that
  // recommendation still needs a one-line PO confirmation (it post-dates
  // the frozen block), and "Low mood" collides with the mood scale's OWN
  // ordinal-1 label "Low" (`_kMoodLabels[0]` below) — screen 11 is the one
  // surface that would render both at once. Rendered as-is; the collision
  // is reported, not resolved, in this task's report.
  'depressed_mood': 'Depressed mood',
  'painful_intercourse': 'Painful intercourse',
  'heavy_menstrual_flow': 'Excessive menstrual flow',
  'brain_fog': 'Mental fog',
  'poor_concentration': 'Trouble concentrating',
  'food_sensitivity': 'Food sensitivity',
  'acne': 'Acne',
};

/// Display label for each of the 8 anatomical `region` values.
/// `unspecified` is deliberately absent — it is the "no location" default
/// and must never render as a chip.
const Map<String, String> _kRegionLabels = <String, String>{
  'lower_abdomen': 'Lower abdomen',
  'pelvis': 'Pelvis',
  'lower_back': 'Lower back',
  'legs': 'Legs',
  'bowel_rectal': 'Bowel / rectal',
  'bladder': 'Bladder',
  'vaginal': 'Vaginal',
  'chest_shoulder': 'Chest / shoulder',
};

/// Display label for each of the 6 `painTypes` values.
const Map<String, String> _kPainTypeLabels = <String, String>{
  'cramping': 'Cramping',
  'sharp': 'Sharp',
  'burning': 'Burning',
  'dull': 'Dull',
  'stabbing': 'Stabbing',
  'throbbing': 'Throbbing',
};

/// Display label for each of the 7 `triggers` values.
const Map<String, String> _kTriggerLabels = <String, String>{
  'stress': 'Stress',
  'intercourse': 'Intercourse',
  'food': 'Food',
  'exercise': 'Exercise',
  'physical_strain': 'Physical strain / sedentarism',
  'poor_sleep': 'Poor sleep',
  'weather': 'Weather',
};

/// `cycle_day_logs.mood`'s 4-member scale, `Codes[value - 1]` — the wire
/// carries the integer 1-4, never the code string.
const List<String> _kMoodLabels = <String>['Low', 'Tired', 'Steady', 'Bright'];

/// The symptom row's own label: the code's ratified display label, or a
/// sentence-cased fallback of the raw code.
///
/// **Never a composite of code + region.** The mockup's own "Pelvic pain" is
/// neither a code label nor any ratified code+region rendering — `pain` has
/// no display label anywhere (`definitions.md:31`; screen 12's heading is
/// "Pain details" instead). Region/painTypes/triggers render separately, as
/// chips (see [_chipsFor]) — never fused into this string. A wrong row label
/// is a clinical claim against a frozen, append-only set, so the fallback
/// here is a plain sentence-cased rendering of the code itself, not a
/// fabricated phrase: `pain` falls through to "Pain", not "Pelvic pain".
String _symptomCodeLabel(String? code) {
  if (code == null) return 'Symptom';
  return _kSymptomCodeLabels[code] ?? _sentenceCase(code);
}

String _sentenceCase(String code) {
  final words = code.replaceAll('_', ' ');
  if (words.isEmpty) return words;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

/// Chips for one symptom row, from `region` + `painTypes` + `triggers`
/// ONLY — never a symptom's own `notes` (a distinct field the mockup does
/// not draw a chip for) and never `side` (anatomical view, not a chip the
/// mockup draws either). A value outside the ratified vocabulary — the
/// mockup's own "After lunch" is the named example, in no ratified set —
/// does not silently render: it is simply not in the label maps above, so
/// it is dropped rather than shown as a raw code.
List<String> _chipsFor(SymptomResponse symptom) {
  final chips = <String>[];
  final region = symptom.region;
  if (region != null && region != 'unspecified') {
    final label = _kRegionLabels[region];
    if (label != null) chips.add(label);
  }
  for (final type in symptom.painTypes ?? const <String>[]) {
    final label = _kPainTypeLabels[type];
    if (label != null) chips.add(label);
  }
  for (final trigger in symptom.triggers ?? const <String>[]) {
    final label = _kTriggerLabels[trigger];
    if (label != null) chips.add(label);
  }
  return chips;
}

// ---------------------------------------------------------------------------
// DayDetailScreen
// ---------------------------------------------------------------------------

/// Screen 11 — the drill-in from screen 10.
///
/// Mounted as a CHILD route of the Cycle branch (`/cycle/day/:date`,
/// `app_router.dart`) — a PUSHED route, unlike screen 10's branch root, so
/// there is a calendar underneath it to pop back to.
class DayDetailScreen extends ConsumerWidget {
  const DayDetailScreen({required this.date, super.key});

  /// The day this screen shows — already round-trip-verified by
  /// `Routes.parseCycleDayDate` before this widget is ever built
  /// (`app_router.dart`); a malformed `:date` never reaches here.
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final view = ref.watch(dayDetailControllerProvider(date));

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Stack(
          children: [
            view.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: c.accent,
                  semanticsLabel: 'Loading',
                ),
              ),
              // Brief §3: a failure in EITHER read surfaces the error state,
              // never a partial screen — see DayDetailController's dartdoc
              // for the combining rule this implements.
              error: (error, _) => LumenErrorRetry(
                message: error is Failure
                    ? error.message
                    : 'Something went wrong. Please try again.',
                onRetry: () =>
                    ref.invalidate(dayDetailControllerProvider(date)),
              ),
              data: (dayView) => _Body(date: date, view: dayView),
            ),
            // The back chevron — SHIPS here, unlike screen 10: this is a
            // pushed route inside the Cycle branch's own Navigator, so
            // there is something to pop back to.
            Positioned(
              top: 0,
              left: 0,
              child: IconButton(
                // `semanticLabel` on the Icon (screen 10's `_MonthStep`
                // precedent) — NOT `tooltip:`, which Material surfaces as a
                // SEPARATE semantics `tooltip` field, not the button's own
                // `label`, and would leave this control announcing nothing.
                icon: const Icon(Icons.chevron_left, semanticLabel: 'Back'),
                color: c.muted,
                onPressed: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.date, required this.view});

  final DateTime date;
  final DayDetailView view;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final log = view.log;
    final hasPain = log?.pain != null; // never a falsiness test — D-08.
    final hasMood = log?.mood != null;
    final hasNote = (log?.notes ?? '').trim().isNotEmpty;
    // `symptomsTotal > 0 || symptoms.isNotEmpty` (fix round 1 tried
    // `symptomsTotal > 0` alone, fix round 2 corrected it): each half
    // guards the OTHER's silent-loss shape, and a server inconsistency can
    // make either half zero while the other is not.
    //  - `symptomsTotal > 0` alone: gating the whole section — including
    //    the truncation notice — on the RETURNED page would let
    //    `symptomsTotal > 0` with an empty page (unreachable today because
    //    `limit` is always >= 1, but a silent-truncation shape all the
    //    same) fall through to the empty-day state and say "nothing
    //    logged" on a day that is not empty.
    //  - `symptoms.isNotEmpty` alone (fix round 1's actual defect, found
    //    at re-review): `total == 0` with a NON-empty page would fall
    //    through the same way and DROP every returned row — the mirror
    //    image of the first shape, on the same screen, introduced by the
    //    fix for the first one.
    // `total` is the ground truth for whether the SECTION exists; the page
    // is the ground truth for what to render inside it. Neither one alone
    // is sufficient to decide the section is empty.
    final hasSymptomData = view.symptomsTotal > 0 || view.symptoms.isNotEmpty;
    final hasAnything = hasPain || hasMood || hasNote || hasSymptomData;
    final truncated = view.symptomsTotal > view.symptoms.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DayHeader(date: date),
          const SizedBox(height: 18),

          // The common case the mockup draws no state for at all (T16
          // brief §5): a 200 with `log: null` and empty collections.
          if (!hasAnything) const _EmptyDay(),

          if (hasSymptomData) ...[
            const _SectionLabel('Symptoms'),
            const SizedBox(height: 5),
            for (final symptom in view.symptoms) ...[
              _SymptomRow(symptom: symptom),
              const SizedBox(height: 5),
            ],
            // A visible limit, never a silent one (R-18 / SymptomContracts
            // §222-228): `total` exceeding the page renders a count line
            // rather than quietly truncating. Deliberately NOT nested
            // inside a "the page has rows" condition — gated on
            // `hasSymptomData` (`total > 0 || symptoms.isNotEmpty`) above
            // so this notice still renders even in the (currently
            // unreachable) shape where the page came back empty but
            // `total` says otherwise.
            if (truncated)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  'Showing ${view.symptoms.length} of '
                  '${view.symptomsTotal} symptoms logged today.',
                  style: TextStyle(fontSize: 10, color: c.muted),
                ),
              ),
            const SizedBox(height: 12),
          ],

          // "Pain & mood" — renamed from the mockup's "Mood & energy"
          // (energy is cut, D-10) and given the day-log's own `pain`, which
          // the mockup draws no section for at all (a genuine gap in it).
          if (hasPain || hasMood) ...[
            const _SectionLabel('Pain & mood'),
            const SizedBox(height: 5),
            if (hasPain) _PainRow(pain: log!.pain!),
            if (hasPain && hasMood) const SizedBox(height: 5),
            if (hasMood) _MoodRow(mood: log!.mood!),
            const SizedBox(height: 12),
          ],

          if (hasNote) ...[
            const _SectionLabel('Note'),
            const SizedBox(height: 5),
            _NoteCard(notes: log!.notes!),
          ],

          // No Activity section (module is P5); no `Edit` or `+ Add to this
          // day` (both point at screens that do not exist yet — R-10).
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Column(
      children: [
        Text(
          LumenFormats.weekdayName(date).toUpperCase(),
          style: TextStyle(fontSize: 10, color: c.muted, letterSpacing: 1),
        ),
        const SizedBox(height: 2),
        Text(
          LumenFormats.monthDay(date),
          style: TextStyle(
            fontSize: 22,
            color: c.ink,
            fontWeight: FontWeight.w500,
          ),
        ),
        // No phase badge here — see this file's header comment for the
        // full reasoning. Cut, not an oversight: CycleDayResponse carries
        // no phase member, and — contrary to what this comment used to
        // say — rendering the unavailable envelope would cost no extra
        // network read. It is still cut because it would be a constant
        // string repeated on every day view: noise, not information, when
        // screen 10 already shows it one tap away.
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          'Nothing logged for this day.',
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

/// The muted, uppercase 9px section eyebrow this screen uses for every
/// section — deliberately never accent (see this file's header comment).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        color: c.muted,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Symptom row
// ---------------------------------------------------------------------------

class _SymptomRow extends StatelessWidget {
  const _SymptomRow({required this.symptom});

  final SymptomResponse symptom;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final label = _symptomCodeLabel(symptom.symptomCode);
    final intensity = symptom.intensity; // never `?? 0` — D-08 / R-12.
    final chips = _chipsFor(symptom);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Dot(color: c.accent),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 11, color: c.ink),
                  ),
                ),
                // A 0 is a REAL datum (D-08) — `intensity != null` renders
                // the row, `intensity == 0` still draws (a zero-width fill
                // and) the "0/10" text, never falsiness-tested away.
                if (intensity != null) ...[
                  const SizedBox(width: 6),
                  Expanded(child: _IntensityBar(intensity: intensity)),
                  const SizedBox(width: 6),
                  Text(
                    '$intensity/10',
                    style: TextStyle(fontSize: 9, color: c.muted),
                  ),
                ],
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 5),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [for (final chip in chips) _Chip(chip)],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pain & mood rows
// ---------------------------------------------------------------------------

class _PainRow extends StatelessWidget {
  const _PainRow({required this.pain});

  final int pain;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            _Dot(color: c.sage),
            const SizedBox(width: 9),
            Text('Pain', style: TextStyle(fontSize: 11, color: c.ink)),
            const SizedBox(width: 6),
            Expanded(child: _IntensityBar(intensity: pain)),
            const SizedBox(width: 6),
            Text('$pain/10', style: TextStyle(fontSize: 9, color: c.muted)),
          ],
        ),
      ),
    );
  }
}

class _MoodRow extends StatelessWidget {
  const _MoodRow({required this.mood});

  final int mood;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final label = (mood >= 1 && mood <= 4) ? _kMoodLabels[mood - 1] : 'Mood';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            _Dot(color: c.sage),
            const SizedBox(width: 9),
            Text(label, style: TextStyle(fontSize: 11, color: c.ink)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Note card
// ---------------------------------------------------------------------------

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.sageSoft,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          notes,
          style: TextStyle(
            fontSize: 10,
            color: c.ink,
            fontStyle: FontStyle.italic,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.input,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(label, style: TextStyle(fontSize: 9, color: c.ink)),
      ),
    );
  }
}

/// The 4px intensity bar: `--bd` track, `--ac` fill, fill fraction =
/// `intensity / 10` (verified against the mockup's own two sample widths —
/// 30% at 3/10, 50% at 5/10, `screen_11_day_detail.html:19-20,:40-41`).
class _IntensityBar extends StatelessWidget {
  const _IntensityBar({required this.intensity});

  final int intensity;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final fraction = intensity.clamp(0, 10) / 10;
    return Stack(
      children: [
        Container(
          height: 4,
          width: double.infinity,
          decoration: BoxDecoration(
            color: c.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FractionallySizedBox(
          widthFactor: fraction,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}
