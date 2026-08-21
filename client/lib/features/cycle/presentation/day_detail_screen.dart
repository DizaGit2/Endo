// Screen 11 — the day detail (P4b-T16 read surface; P4b-T16b day-log editor;
// P4b-T16c period section + period editor).
//
// The drill-in from screen 10: "what did I log on April 7?" It reads two
// endpoints (`GET /cycle/day/{date}`, `GET /symptoms?from&to`) and renders
// what it finds.
//
// **This file still issues no request itself.** It carries TWO affordances,
// each opening its own `LumenBottomSheet` over this screen, each owning ONE
// endpoint:
//
//  * [kDayDetailEditLogLabel] -> `day_log_editor_screen.dart` ->
//    `POST /cycle/day/{date}`, a MERGE (P4b-T16b).
//  * [kDayDetailEditPeriodLabel] -> `period_editor_screen.dart` ->
//    `POST /cycle/events`, a FULL UPSERT (P4b-T16c).
//
// **They are two sheets on purpose and must never become one.** The endpoints
// have OPPOSITE write rules — an emptied field is a no-op on the first and an
// ERASE on the second — and one Save writing both would be two requests, two
// failure modes and one message for one user action, on an online-only client
// with no write queue (S-9; the same reasoning R-11 used for screen 13).
//
// **The Period section is new, and its absence was the finding.** A re-survey
// of all 38 mockups found Lumen had NO period-logging surface anywhere: a user
// set `lastPeriodStart` once at onboarding and could never log a period again.
// `DayDetailView` carried no `events` at all until P4b-T16c, although
// `CycleDayResponse` always did.
//
// **The T16 header's own precondition for that split is void, and is
// corrected here rather than left to mislead.** It read *"T20 has given the
// mockup's 'Edit' affordance a real destination"*. RULING T20-B: T19 cut
// `PUT /symptoms/{id}`, so screen 12 is create-only and the symptom-row
// `Edit` ships NOWHERE — it is booked for P6. T16b edits the DAY LOG (pain,
// mood, note), which is a different row on a different endpoint. The T18 half
// of that sentence was true and has happened.
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
//  * `Edit`, in the Symptoms section header — STAYS CUT after T16b/T16c, and
//    the reason changed: it is not "no destination yet" any more, it is
//    RULING T20-B. `PUT /symptoms/{id}` does not exist, so there is nothing
//    an edit could send. Booked for P6.
//  * `+ Add to this day` — STAYS CUT, and its reason got STRONGER. Screen 12
//    hard-codes `occurredAt: null`, i.e. the SERVER's now, so pointing a past
//    day's affordance at it would silently log to today: a data-fabrication
//    path, not merely inert navigation (RULING T16-K). The two editor buttons
//    below are different buttons with different copy, in a different place,
//    and neither is this one revived — note in particular that the period
//    editor's `occurredOn` is THIS day, from the route, never the server's
//    now, which is exactly the property the cut affordance lacks.
//
// Section header colour, restated because T16b makes it live again: the
// mockup's `.sl span:last-child` rule exists to colour a right-hand ACTION,
// and only `Edit` was ever meant to be accent. T16b adds no action to any
// section header — its affordance is a full-width control BELOW the
// sections — so no header renders accent here and the rule stays dormant.
//
// Section header colour: the mockup's CSS (`.sl span:last-child`) happens to
// colour "Mood & energy", "Activity" and "Note" accent too, because each is
// its OWN last child once "Edit" is the only header with two spans. That
// rule exists to colour the right-hand ACTION. Only `Edit` was ever meant to
// be accent, and `Edit` is cut — so no section header renders accent here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/presentation/day_log_editor_screen.dart';
import 'package:lumen/features/cycle/presentation/period_editor_screen.dart';
import 'package:lumen/features/cycle/presentation/period_vocabulary.dart';
import 'package:lumen/shared/mood_labels.dart';
import 'package:lumen/shared/symptom_vocabulary.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';

/// Chips for one symptom row, from `region` + `painTypes` + `triggers`
/// ONLY — never a symptom's own `notes` (a distinct field the mockup does
/// not draw a chip for) and never `side` (anatomical view, not a chip the
/// mockup draws either). A value outside the ratified vocabulary — the
/// mockup's own "After lunch" is the named example, in no ratified set —
/// does not silently render: it has no entry in the ratified label maps this
/// file imports from `symptom_vocabulary.dart`, so it is dropped rather than
/// shown as a raw code.
///
/// (Those maps used to be declared directly above this function; P4b-T19b
/// promoted them to `symptom_vocabulary.dart` and left the word "above"
/// behind. Corrected at P4b-T16b, the task that owns this file next.)
List<String> _chipsFor(SymptomResponse symptom) {
  final chips = <String>[];
  final region = symptom.region;
  if (region != null && region != 'unspecified') {
    final label = kRegionLabels[region];
    if (label != null) chips.add(label);
  }
  for (final type in symptom.painTypes ?? const <String>[]) {
    final label = kPainTypeLabels[type];
    if (label != null) chips.add(label);
  }
  for (final trigger in symptom.triggers ?? const <String>[]) {
    final label = kTriggerLabels[trigger];
    if (label != null) chips.add(label);
  }
  return chips;
}

// ---------------------------------------------------------------------------
// The day-log editor's affordance
// ---------------------------------------------------------------------------

/// The control that opens the day-log editor (P4b-T16b).
///
/// **AUTHORED.** Screen 11's mockup draws exactly two edit affordances — the
/// Symptoms header's `Edit` and the dashed `+ Add to this day` — and BOTH
/// stay cut (see this file's header). Nothing drawn is reusable, so this
/// string, its geometry and its placement are all new. Queued for the T25 PO
/// copy pass.
///
/// It names the three fields it writes rather than the row it writes them to:
/// `pain`, `mood` and `notes` are exactly `LogCycleDayRequest`'s members, so
/// the label cannot over-promise. In particular it does NOT say "symptoms" —
/// those are a different table this button cannot touch — and it does not say
/// "add to this day", which is the cut affordance's own words and a different
/// (fabricating) destination.
///
/// The word "Edit" is honest on an empty day too: the sheet opens on whatever
/// the day already holds, which may be nothing.
const String kDayDetailEditLogLabel = 'Edit pain, mood and note';

/// The control that opens the period-event editor (P4b-T16c).
///
/// **AUTHORED**, like everything else about this surface: no mockup in the
/// design system draws a period, flow or spotting control anywhere.
///
/// *"Log or edit"*, not *"Edit"*: unlike the day log — where the row is the day
/// and always exists — a day may have no period event at all, and on a surface
/// that has never existed before that is the COMMON case. A button reading
/// "Edit" over a day with nothing to edit would be describing a row that is not
/// there. It names the thing rather than the fields, because the sheet's three
/// fields (type, flow, note) are one row's whole state and naming them would be
/// longer without being more precise.
const String kDayDetailEditPeriodLabel = 'Log or edit a period event';

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The back chevron — SHIPS here, unlike screen 10: this is a
            // pushed route inside the Cycle branch's own Navigator, so there
            // is something to pop back to.
            //
            // **In the LAYOUT, not a `Positioned` over the scroll view.** It
            // was an overlay through T16, which cost nothing while this was a
            // read surface: nothing that scrolled under its 48x48 corner was
            // tappable. P4b-T16b adds a tappable control to the scroll view,
            // and P4b-T20b hit a real tap-miss with this exact overlay shape
            // on screen 12 — so it converges onto screen 12's arrangement
            // now, before there is anything to lose. The rendered result is
            // the mockup's either way: the chevron at the top left with the
            // content beginning below it.
            //
            // `semanticLabel` on the Icon (screen 10's `_MonthStep`
            // precedent) — NOT `tooltip:`, which Material surfaces as a
            // SEPARATE semantics `tooltip` field rather than the button's own
            // `label`, and would leave this control announcing nothing. The
            // WORD is `MaterialLocalizations`' own translated name for this
            // control, not copy this screen invented (screen 12's precedent).
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
                  onPressed: () => _leaveDayDetail(context),
                ),
              ),
            ),
            Expanded(
              child: view.when(
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Leaves screen 11: pops when there is something to pop, and otherwise goes
/// to the Cycle tab.
///
/// **`canPop`-guarded rather than a bare `context.pop()`, and this is a
/// CONSISTENCY change, not a bug fix.** P4b-T21b's probe C MEASURED the bare
/// pop this replaces: a cold link to `/cycle/day/2026-04-20` through the real
/// route table renders this chevron with `context.canPop() == true`, and
/// tapping it threw nothing. The reason is structural — `/cycle/day/:date` is
/// registered as a CHILD `GoRoute` under `/cycle` inside the Cycle
/// `StatefulShellBranch`, so go_router materialises the calendar page beneath
/// it even on a cold deep link. Screen 12 and screen 13 each needed their
/// guard for real (both are top-level routes and can genuinely be the stack
/// root); this one is the third member of a house idiom, adopted so that the
/// three logging screens answer "where does back go" the same way and a
/// future route-table change cannot quietly make this the exception.
///
/// [Routes.cycle] rather than [Routes.home] — screen 12's fallback — because
/// this screen's own branch root IS the cycle calendar it drills in from, so
/// a user with no back stack lands where the ordinary pop would have taken
/// them rather than in another tab.
void _leaveDayDetail(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.cycle);
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
    // P4b-T16c: a day with ONLY a period event is not an empty day. Before
    // `events` reached this view there was no way for it to say so.
    final hasEvents = view.events.isNotEmpty;
    final hasAnything =
        hasPain || hasMood || hasNote || hasSymptomData || hasEvents;
    final truncated = view.symptomsTotal > view.symptoms.length;

    return SingleChildScrollView(
      // Top padding drops from 48 to 6: the chevron is in the layout now
      // rather than an overlay this had to clear.
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DayHeader(date: date),
          const SizedBox(height: 18),

          // The common case the mockup draws no state for at all (T16
          // brief §5): a 200 with `log: null` and empty collections.
          if (!hasAnything) const _EmptyDay(),

          // **Period first** (P4b-T16c), ahead of the mockup's own three
          // sections. This screen lives in the Cycle branch and a day's period
          // status is the cycle's own headline datum; the mockup drew no
          // section for it to be placed relative to, so there is no drawn
          // order being departed from.
          //
          // Rendered in the SERVER's order — `CycleDayService` sorts by `Kind`,
          // so it reads period_end, period_start, spotting. Not re-sorted here:
          // re-deriving an ordering rule this client does not own is how the
          // two drift.
          if (hasEvents) ...[
            const _SectionLabel('Period'),
            const SizedBox(height: 5),
            for (final event in view.events) ...[
              _PeriodRow(event: event),
              const SizedBox(height: 5),
            ],
            const SizedBox(height: 12),
          ],

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

          // No Activity section (module is P5); no `Edit`, no `+ Add to this
          // day` — see this file's header for why each stays cut.
          const SizedBox(height: 16),
          // The day-log button keeps the position it shipped in at T16b; the
          // period button is added BELOW it rather than above, so no control
          // already on this screen moves under the user. The two are visually
          // identical because they are the same kind of thing — the difference
          // that matters (MERGE vs FULL UPSERT) belongs on the sheet that
          // behaves that way, where the user is about to act on it, not on a
          // button label.
          _EditLogButton(date: date),
          const SizedBox(height: 8),
          _EditPeriodButton(date: date),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The day-log editor's affordance
// ---------------------------------------------------------------------------

/// Opens the day-log editor for this day (P4b-T16b).
///
/// **Only rendered in the DATA state**, inside `_Body`, and deliberately so:
/// the editor seeds itself from the day view this screen has already settled,
/// so offering it while that read is loading or failed would open a form that
/// silently claims the day is empty. A user who could not read the day cannot
/// edit it; they retry the read first.
///
/// **Always rendered in the data state, including on an empty day** — the
/// endpoint upserts, so a day with nothing on it is exactly as writable as
/// one with a full log, and hiding the button there would leave the
/// empty-state screen with no way forward at all.
///
/// Geometry is the mockup's `.add` button — full width, 11 px, muted, radius
/// 11 — with one deliberate departure: a SOLID border where `.add` is dashed.
/// That button is `+ Add to this day`, which stays cut and must not be
/// mistaken for this one.
class _EditLogButton extends StatelessWidget {
  const _EditLogButton({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return OutlinedButton(
      onPressed: () => showDayLogEditor(context, date),
      style: OutlinedButton.styleFrom(
        foregroundColor: c.muted,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        minimumSize: const Size.fromHeight(0),
      ),
      child: const Text(kDayDetailEditLogLabel),
    );
  }
}

/// Opens the period-event editor for this day (P4b-T16c).
///
/// Same gate and same geometry as [_EditLogButton], for the same two reasons:
/// only in the DATA state, because the editor seeds itself from the settled day
/// view and a form opened over a failed read would silently claim the day has
/// no period event; and ALWAYS within it, including on a day with no event at
/// all, because that is precisely the day a first period event gets logged on.
class _EditPeriodButton extends StatelessWidget {
  const _EditPeriodButton({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return OutlinedButton(
      onPressed: () => showPeriodEditor(context, date),
      style: OutlinedButton.styleFrom(
        foregroundColor: c.muted,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        minimumSize: const Size.fromHeight(0),
      ),
      child: const Text(kDayDetailEditPeriodLabel),
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
    final label = symptomCodeLabel(symptom.symptomCode);
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
// Period row
// ---------------------------------------------------------------------------

/// One `cycle_events` row as screen 11 reads it (P4b-T16c): its kind, its flow
/// level if it has one, and its note if it has one.
///
/// **No clinical treatment of any level (RULING T16-C).** `Heavy` renders as a
/// chip exactly like `Light` does — same colours, same size, no icon, no note,
/// no warning. The C-15 red-flag note that level 4 would trigger needs
/// clinician AND legal sign-off and ships nowhere in P4b.
///
/// A flow of `null` draws NO chip rather than a "none" chip: the column stores
/// "no level recorded", which is a different fact from a recorded lowest level,
/// and the two must not look alike.
class _PeriodRow extends StatelessWidget {
  const _PeriodRow({required this.event});

  final CycleEventResponse event;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    final flow = event.flowIntensity;
    final notes = (event.notes ?? '').trim();

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
                    periodKindLabel(event.kind),
                    style: TextStyle(fontSize: 11, color: c.ink),
                  ),
                ),
                if (flow != null) ...[
                  const SizedBox(width: 6),
                  _Chip(flowLabel(flow)),
                ],
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                notes,
                style: TextStyle(
                  fontSize: 10,
                  color: c.muted,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
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
    // P4b-T18: the shared `moodLabel` fallback is `'$mood'`, not the word
    // `'Mood'` (fix round 1, M7) — this row carried the superseded shape
    // until this promotion; see mood_labels.dart's own dartdoc.
    final label = moodLabel(mood);
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
