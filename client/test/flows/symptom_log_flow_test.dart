// ---------------------------------------------------------------------------
// FLOW · log a symptom end to end — screen 11 open in one tab, screen 8 →
// screen 12 → save → back, and screen 11 correct afterwards
// (P4b-T24, R-06 (i), ruling R1.2)
// ---------------------------------------------------------------------------
//
// **What this file uniquely proves.** The batch assembler, the repository's
// wire mapping, screen 12's own rendering and the `/symptoms/new` route each
// have their own tests. Three things are true only ACROSS them, and each has
// already been a live defect or a stated open gap in this phase:
//
//  1. **One tap, one batch.** `POST /symptoms` is all-or-nothing and has no
//     idempotency key. T21b shipped a screen 12 whose post-save exit threw on
//     the very route state the task created: the screen stayed mounted, the CTA
//     came back live, and a second tap posted the batch AGAIN — call count 2, a
//     duplicate clinical write. The `GoError` escaped as an uncaught ZONE error,
//     so `expect(tester.takeException(), isNull)` never fired: **the call count
//     was the only assertion that could see it.** It is asserted here, on the
//     real route stack, with the real navigation.
//  2. **The dependent screen refreshes.** `SymptomFormController
//     ._refreshDependents` invalidates the day-detail controller for the day
//     the write landed on. T20a's own report flagged this as an open gap
//     precisely because *"this is invisible to any test that only asserts the
//     POST"*. Screen 11 is opened in the Cycle branch BEFORE the write here,
//     left there while the write happens in the Home branch, and read again
//     after — which is the only shape in which the invalidation is observable.
//  3. **The body a real screen produces.** The batch's frozen order, the pain
//     row's omitted `symptomCode`, the notes-on-the-first-entry rule and the
//     absence of `side`/`occurredAt` are asserted against a request built by
//     taps, not by a hand-constructed `SymptomForm`.
//
// **Fix round 1 adds a fourth thing, on the other write screen 11 owns**: the
// DAY-LOG EDITOR (`POST /cycle/day/{date}`, T16b). It lives here rather than in
// a file of its own because this is the file that already walks the Cycle
// branch into screen 11 — the sheet opens over that screen and seeds itself
// from the view it is sitting on, so the navigation this file already does is
// the whole premise of the leg. What it closes is the same gap the settings
// SAVE leg closes one file over: T16b's defect is a `touched*` guard re-derived
// from the VALUE, and no flow pressed that screen's Save either.
//
// R3 — nothing settles; frame counts are stated at each call site.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/create_symptoms_request.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/log_cycle_day_request.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/day_log_editor_controller.dart';
import 'package:lumen/features/cycle/presentation/cycle_calendar_screen.dart';
import 'package:lumen/features/cycle/presentation/day_detail_screen.dart';
import 'package:lumen/features/cycle/presentation/day_log_editor_screen.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/application/symptom_form_controller.dart';
import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_intensity_scale.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';
import 'package:lumen/shared/widgets/lumen_selectable_row.dart';

import '../support/harness.dart';
import 'flow_harness.dart';

// ---------------------------------------------------------------------------
// The day this flow is about
// ---------------------------------------------------------------------------

final Date _today = Date(2026, 4, 20);
final DateTime _todayLocal = DateTime(2026, 4, 20);

// ---------------------------------------------------------------------------
// Finders
// ---------------------------------------------------------------------------

final Finder _symptomTile = find.widgetWithIcon(
  LumenSelectableRow,
  Icons.healing,
);

/// A bottom-nav destination, scoped to the nav bar: "Home" and "Cycle" are
/// words that also appear inside screens.
Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

/// A chip on screen 12, by its ratified label.
Finder _chip(String label) => find.descendant(
  of: find.byType(SymptomFormScreen),
  matching: find.text(label),
);

/// One stop inside the intensity block [blockKey] — screen 12 can draw up to
/// 21 blocks, every one of them labelled `0`..`10`, so nothing in the rendered
/// text can tell two apart. The keys are why an addressable one exists.
Finder _stop(Key blockKey, int stop) =>
    find.descendant(of: find.byKey(blockKey), matching: find.text('$stop'));

final Finder _saveCta = find.descendant(
  of: find.byType(SymptomFormScreen),
  matching: find.byType(FilledButton),
);

// ── the day-log editor (fix round 1) ───────────────────────────────────────

/// The day the day-log leg writes. **Not today**, deliberately: `POST
/// /cycle/day/{date}` is *"capped by today and NOTHING ELSE"*
/// (`CycleDayService`), so a past day is an ordinary legal write, and using one
/// keeps the leg's assertions clear of the dashboard's own today-shaped state.
final DateTime _pastDayLocal = DateTime(2026, 4, 8);
final Date _pastDay = Date(2026, 4, 8);

/// Everything inside the day-log sheet is scoped to it: screen 11 stays mounted
/// underneath, and it draws a note and a pain figure of its own.
Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byType(DayLogEditorScreen), matching: matching);

/// One stop on the sheet's pain scale. Screen 11 underneath draws no
/// [LumenIntensityScale] at all (its own bar is a private `_IntensityBar`), so
/// this cannot collide with anything behind the scrim.
Finder _sheetPainStop(int stop) => _inSheet(
  find.descendant(
    of: find.byType(LumenIntensityScale),
    matching: find.text('$stop'),
  ),
);

final Finder _sheetNoteBox = _inSheet(find.byType(TextField));

final Finder _sheetCta = _inSheet(find.byType(FilledButton));

/// What the sheet's note box currently holds — read from the controller rather
/// than by finding text, because screen 11's own note card behind the scrim
/// renders the identical string.
String _noteBoxText(WidgetTester tester) =>
    tester.widget<TextField>(_sheetNoteBox).controller!.text;

/// Scrolls [finder] into view and taps it.
///
/// Screen 12 scrolls (its CTA is pinned; the chip rows are not), so a tap
/// without this misses a control that is merely below the fold — a failure
/// INSIDE the tap, which is the shape that cannot be told apart from a broken
/// assertion.
Future<void> _tapScrolled(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  // -------------------------------------------------------------------------
  // The flow R-06 names
  // -------------------------------------------------------------------------

  testWidgets(
    'a symptom logged on screen 12 reaches the wire as ONE batch in frozen '
    'order, pops back into the Home branch, and the day view left open in the '
    'Cycle branch shows it afterwards',
    (WidgetTester tester) async {
      final world = FlowWorld();
      world.months[flowMonth(_todayLocal)] = cycleCalendarFixture(
        today: _today,
        from: Date(2026, 4, 1),
        to: Date(2026, 4, 30),
        days: <CycleCalendarDay>[
          cycleCalendarDayFixture(date: _today, symptomCount: 0),
        ],
      );

      // The server STORES the batch: the day's symptom list answers with the
      // rows the write created. An echoing mock could not tell a screen that
      // re-read from one that re-rendered its own pre-write state.
      world.onSymptomsPost = (CreateSymptomsRequest request) async {
        world.symptomDays['2026-04-20'] = symptomListResponseFixture(
          items: <SymptomResponse>[
            symptomResponseFixture(
              id: 'symptom-pain',
              symptomCode: 'pain',
              intensity: 7,
              region: 'pelvis',
              occurredOn: _today,
            ),
            symptomResponseFixture(
              id: 'symptom-bloating',
              symptomCode: 'bloating',
              intensity: 4,
              region: null,
              occurredOn: _today,
            ),
          ],
        );
        return createSymptomsResponseFixture(
          items: <SymptomResponse>[
            symptomResponseFixture(id: 'symptom-pain', occurredOn: _today),
            symptomResponseFixture(id: 'symptom-bloating', occurredOn: _today),
          ],
        );
      };

      await world.mount(tester);
      expect(find.byType(DashboardScreen), findsOneWidget);

      // --- open screen 11 in the Cycle branch, and leave it there -----------
      await tester.tap(_tab('Cycle'));
      await pumpFlowFrames(tester, 4);
      expect(find.byType(CycleCalendarScreen), findsOneWidget);

      await tester.tap(find.byKey(ValueKey<DateTime>(_todayLocal)));
      await pumpRouteTransition(tester);
      await pumpFlowFrames(tester, 3);
      expect(find.byType(DayDetailScreen), findsOneWidget);
      // The premise: the day holds nothing yet. Every assertion at the end is
      // the opposite of this, which is what makes them discriminating.
      expect(find.text('Bloating'), findsNothing);

      // --- go and log one, from the OTHER branch ---------------------------
      await tester.tap(_tab('Home'));
      await pumpFlowFrames(tester, 3);
      expect(find.byType(DashboardScreen), findsOneWidget);

      await tester.ensureVisible(_symptomTile);
      await tester.pump();
      await tester.tap(_symptomTile);
      await pumpRouteTransition(tester);
      expect(find.byType(SymptomFormScreen), findsOneWidget);

      world.clearWire();

      await _tapScrolled(tester, _chip('Pelvis'));
      await _tapScrolled(tester, _stop(kSymptomPainIntensityKey, 7));
      await _tapScrolled(tester, _chip('Sharp'));
      await _tapScrolled(tester, _chip('Bloating'));
      await _tapScrolled(tester, _stop(symptomIntensityKey('bloating'), 4));

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Worse after standing.');
      await tester.pump();

      await _tapScrolled(tester, _saveCta);
      // Two frames for the POST and its invalidations, then the pop's own
      // transition, then two for the Home branch to settle back in.
      await pumpFlowFrames(tester, 2);
      await pumpRouteTransition(tester);
      await pumpFlowFrames(tester, 2);

      // --- ONE batch, and this exact body ----------------------------------
      expect(
        world.countOf('POST /symptoms'),
        1,
        reason:
            'all-or-nothing, no idempotency key: a second post is a duplicate '
            'clinical write, and T21b shipped exactly that behind a green '
            '"no exception" assertion',
      );
      expect(
        wireBody(CreateSymptomsRequest.serializer, world.symptomPosts.single),
        <String, dynamic>{
          'entries': <dynamic>[
            <String, dynamic>{
              // No `symptomCode`: the server defaults the row to `pain`, and
              // sending one would be the client naming a code the vocabulary
              // has no label for.
              'intensity': 7,
              'region': 'pelvis',
              'painTypes': <String>['sharp'],
              // PRESENT and EMPTY, not omitted: `SymptomService.cs` keeps
              // these arrays "empty, never NULL — keeping 'the user
              // classified nothing' a single state", and `_toWire` mirrors
              // that rather than dropping an empty list.
              'triggers': <String>[],
              // R3 — one notes box per episode, attached to the FIRST entry.
              'notes': 'Worse after standing.',
            },
            <String, dynamic>{
              'symptomCode': 'bloating',
              'intensity': 4,
              // A RELATED row's arrays are its OWN, and empty — it never
              // inherits the pain row's `sharp`.
              'painTypes': <String>[],
              'triggers': <String>[],
            },
          ],
        },
        reason:
            'absence is half the assertion: no `side` (R-21 cut Front/Back, '
            'and null is what the server defaults to) and no `occurredAt` '
            '(screen 12 draws no date affordance, so the server dates the '
            'batch by its own now)',
      );

      // --- the screen that could duplicate the write is GONE ----------------
      expect(find.byType(SymptomFormScreen), findsNothing);
      expect(find.text(kSymptomFormSaveLabel), findsNothing);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(
        find.byType(LumenBottomNav),
        findsOneWidget,
        reason:
            'popped back INTO the Home branch, not over it — screen 12 is a '
            'top-level non-shell route, so a `go` instead of a `push` would '
            'have replaced the branch and left nothing to pop to',
      );

      // --- the write invalidated the day it landed on -----------------------
      expect(
        world.cache.invalidations,
        containsAll(CacheKeys.keysForDate(_todayLocal)),
        reason:
            'derived from the RESPONSE rows\' own `occurredOn`, so a server '
            'that dated the batch differently invalidates what it actually '
            'wrote',
      );

      // --- the day view left open in the other branch is correct -----------
      await tester.tap(_tab('Cycle'));
      await pumpFlowFrames(tester, 4);

      expect(
        find.byType(DayDetailScreen),
        findsOneWidget,
        reason:
            'the branch kept its own stack across the tab switch — this is '
            'the same screen 11, not a fresh one',
      );
      expect(
        world.wire,
        contains('GET /symptoms?from=2026-04-20'),
        reason:
            'the day view re-read. Without the invalidation the entry is gone '
            'from the cache but nothing asks for it again, so a screen the '
            'user never left keeps rendering a day that no longer exists.',
      );
      expect(find.text('Bloating'), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // The failure path
  // -------------------------------------------------------------------------

  testWidgets(
    'a REJECTED batch keeps screen 12 mounted with every selection intact, '
    'binds the rejection to the row the server named, and the retry sends the '
    'IDENTICAL batch — exactly once',
    (WidgetTester tester) async {
      final world = FlowWorld();
      var attempts = 0;
      world.onSymptomsPost = (CreateSymptomsRequest request) async {
        attempts++;
        if (attempts == 1) {
          // Keyed `entries[1].intensity` — the RELATED row, not the pain row.
          // Which row a message lands under is resolved through the RETAINED
          // submitted drafts, so a screen that re-derived the index from live
          // state would put the server's complaint under the wrong symptom.
          throw const ValidationFailure(
            message: 'One or more validation errors occurred.',
            detail: 'One or more validation errors occurred.',
            fields: <String, List<String>>{
              'entries[1].intensity': <String>['must be between 0 and 10'],
            },
          );
        }
        return createSymptomsResponseFixture(
          items: <SymptomResponse>[
            symptomResponseFixture(id: 'symptom-pain', occurredOn: _today),
            symptomResponseFixture(id: 'symptom-bloating', occurredOn: _today),
          ],
        );
      };

      await world.mount(tester);
      await tester.ensureVisible(_symptomTile);
      await tester.pump();
      await tester.tap(_symptomTile);
      await pumpRouteTransition(tester);
      world.clearWire();

      await _tapScrolled(tester, _chip('Pelvis'));
      await _tapScrolled(tester, _stop(kSymptomPainIntensityKey, 7));
      await _tapScrolled(tester, _chip('Bloating'));
      await _tapScrolled(tester, _stop(symptomIntensityKey('bloating'), 4));

      // Type a note and then take it back — an ordinary gesture, and the ONE
      // input on which `notes != null && notes.isNotEmpty` and `notes != null`
      // disagree. `SymptomForm.notes` starts null and only ever becomes `''`
      // this way, so a batch assembled after a cleared box is the only place
      // the empty-string half of `_withFirstEntryNotes`'s guard is reachable
      // at all.
      await tester.ensureVisible(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Never mind.');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await _tapScrolled(tester, _saveCta);
      await pumpFlowFrames(tester, 3);

      expect(world.symptomPosts, hasLength(1));
      // The EMPTIED notes box is ABSENT from the batch, not present and empty
      // (fix round 1). `notes` is the one member whose empty state is a real
      // string rather than a null, and the two conventions sit two keys apart
      // in this very body — `painTypes`/`triggers` ARE sent present-and-empty
      // on purpose, `notes` must not be. Nothing on screen distinguishes them,
      // so only an exact body can.
      expect(
        wireBody(CreateSymptomsRequest.serializer, world.symptomPosts.single),
        <String, dynamic>{
          'entries': <dynamic>[
            <String, dynamic>{
              'intensity': 7,
              'region': 'pelvis',
              'painTypes': <String>[],
              'triggers': <String>[],
            },
            <String, dynamic>{
              'symptomCode': 'bloating',
              'intensity': 4,
              'painTypes': <String>[],
              'triggers': <String>[],
            },
          ],
        },
      );
      expect(
        find.byType(SymptomFormScreen),
        findsOneWidget,
        reason:
            'the batch is all-or-nothing: leaving on a rejection would throw '
            'away every selection the user made',
      );
      expect(find.byType(LumenErrorBanner), findsOneWidget);
      expect(find.text('must be between 0 and 10'), findsOneWidget);

      // The rejection landed under the RELATED row the server named, not
      // under the pain row that happens to be index 0 of the current batch.
      final SymptomForm rejected = world.container.read(
        symptomFormControllerProvider,
      );
      expect(
        rejected.relatedRowError('bloating', 'intensity'),
        'must be between 0 and 10',
      );
      expect(rejected.painRowError('intensity'), isNull);

      // Every selection survived, so the retry can send the same batch.
      expect(rejected.region, 'pelvis');
      expect(rejected.painIntensity, 7);
      expect(rejected.relatedIntensities, <String, int?>{'bloating': 4});

      // Nothing was invalidated: a 400 means the server collected every field
      // error before writing anything, so no cached day has gone stale.
      expect(world.cache.invalidations, isEmpty);

      await expectRetryReissuesOneRequest(
        tester,
        requestCount: () => world.symptomPosts.length,
        label: kSymptomFormRetryLabel,
        settle: false,
      );
      await pumpFlowFrames(tester, 2);
      await pumpRouteTransition(tester);

      expect(world.symptomPosts, hasLength(2));
      expect(
        wireBody(CreateSymptomsRequest.serializer, world.symptomPosts.last),
        wireBody(CreateSymptomsRequest.serializer, world.symptomPosts.first),
        reason:
            'a retry that rebuilt its batch from a form the failure had reset '
            'would write something the user never entered — and this endpoint '
            'has no update and no delete to correct it with',
      );
      // …and the accepted retry leaves, so the duplicate door closes here too.
      expect(find.byType(SymptomFormScreen), findsNothing);
      expect(
        world.cache.invalidations,
        containsAll(CacheKeys.keysForDate(_todayLocal)),
      );
    },
  );

  // -------------------------------------------------------------------------
  // Screen 11's OTHER write — the day-log editor (fix round 1)
  // -------------------------------------------------------------------------
  //
  // T16b's defect shape is `DayLogEditorForm._sendsNotes` re-derived from the
  // VALUE instead of from the flag. Its consequence is NOT a wiped note —
  // `CycleDayService` trims first and treats blank text as absent — it is that
  // an emptied note box becomes a submittable form whose request carries
  // nothing the server will accept, so the user's only feedback is a 400 for a
  // gesture the client could have refused on the device. The leg below walks
  // both halves: the save that DOES send something sends only what changed,
  // and the one that would send nothing cannot be started.
  //
  // Still a SEAM test. `day_log_editor_screen_semantics_test.dart` stubs
  // `CycleRepository` outright, so it sees `touchedNotes: false` as an
  // ARGUMENT and never a body; `cycle_repository_test.dart` builds its matrix
  // by hand. Neither can seed a form from a real `GET /cycle/day` and then look
  // at what a real Save put on the wire.

  testWidgets(
    'a day-log editor seeded from the stored day and saved after ONE pain tap '
    'sends exactly that one key — and emptying the note it arrived with is a '
    'gesture the sheet refuses rather than a request the server rejects',
    (WidgetTester tester) async {
      final world = FlowWorld();
      world.days['2026-04-08'] = cycleDayFixture(
        date: _pastDay,
        log: cycleDayLogFixture(
          day: _pastDay,
          pain: 3,
          mood: 3,
          notes: 'Cramps all morning.',
        ),
      );

      await world.mount(tester);

      // --- open screen 11 on that day --------------------------------------
      await tester.tap(_tab('Cycle'));
      await pumpFlowFrames(tester, 4);
      expect(find.byType(CycleCalendarScreen), findsOneWidget);

      await tester.tap(find.byKey(ValueKey<DateTime>(_pastDayLocal)));
      await pumpRouteTransition(tester);
      await pumpFlowFrames(tester, 3);
      expect(find.byType(DayDetailScreen), findsOneWidget);

      // The premise, as the user sees it: three stored values on the day.
      expect(find.text('3/10'), findsOneWidget);
      expect(find.text('Steady'), findsOneWidget);
      expect(find.text('Cramps all morning.'), findsOneWidget);

      // --- open the editor over it -----------------------------------------
      await tester.ensureVisible(find.text(kDayDetailEditLogLabel));
      await tester.pump();
      await tester.tap(find.text(kDayDetailEditLogLabel));
      // The sheet's own entrance (250 ms), driven by hand.
      await pumpRouteTransition(tester);
      expect(find.byType(DayLogEditorScreen), findsOneWidget);

      // Seeded — and seeding marks nothing touched, which is the state a
      // value-derived guard cannot tell apart from an edited one.
      expect(_noteBoxText(tester), 'Cramps all morning.');
      expect(find.text(kDayLogNothingChangedMessage), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_sheetCta).onPressed,
        isNull,
        reason:
            'the form is FULL — a pain, a mood and a note, all read from the '
            'server — and none of it is touched, so none of it may travel',
      );

      world.clearWire();

      // --- change ONE field, and save --------------------------------------
      await _tapScrolled(tester, _sheetPainStop(7));
      await _tapScrolled(tester, _sheetCta);
      // Two frames for the POST and its dependent refresh, then the sheet's
      // exit transition.
      await pumpFlowFrames(tester, 2);
      await pumpRouteTransition(tester);

      expect(world.countOf('POST /cycle/day/2026-04-08'), 1);
      expect(
        wireBody(LogCycleDayRequest.serializer, world.dayLogPosts.single),
        <String, dynamic>{'pain': 7},
        reason:
            'ONE key. The mood and the note are in this form, in memory, and '
            'both are keys this endpoint MERGES — `if (touchedMood)` and '
            '`if (touchedNotes)` are the only reason they are not on the wire, '
            'and re-asserting a seed read minutes ago over a row a second '
            'writer may have moved is the lost update the flags exist to '
            'prevent',
      );

      // The stored row: the tap landed, and nothing rode along with it.
      final CycleDayLogResponse stored = world.days['2026-04-08']!.log!;
      expect(stored.pain, 7);
      expect(stored.mood, 3);
      expect(stored.notes, 'Cramps all morning.');

      // The sheet closed, and screen 11 ADOPTED the 200 rather than re-reading
      // it — `DayLogEditorController.applyToDayView`, which is why no second
      // `GET /cycle/day/2026-04-08` appears in the log.
      expect(find.byType(DayLogEditorScreen), findsNothing);
      expect(find.text('7/10'), findsOneWidget);
      expect(find.text('Cramps all morning.'), findsOneWidget);
      expect(world.countOf('GET /cycle/day/2026-04-08'), 0);

      // --- and now the gesture the sheet must refuse ------------------------
      await tester.ensureVisible(find.text(kDayDetailEditLogLabel));
      await tester.pump();
      await tester.tap(find.text(kDayDetailEditLogLabel));
      await pumpRouteTransition(tester);
      expect(
        _noteBoxText(tester),
        'Cramps all morning.',
        reason:
            're-seeded from the view the save adopted, so the note the user '
            'never touched is still the note they are looking at',
      );

      await tester.ensureVisible(_sheetNoteBox);
      await tester.pump();
      await tester.enterText(_sheetNoteBox, '');
      await tester.pump();

      expect(
        find.text(kDayLogEmptyChangeMessage),
        findsOneWidget,
        reason:
            'something was touched and none of it survives to the wire — a '
            'different sentence from "nothing changed yet", because it is a '
            'different situation',
      );
      expect(tester.widget<FilledButton>(_sheetCta).onPressed, isNull);

      // Press it anyway. Nothing may reach the wire: `notes: ""` trims to
      // absent server-side, which makes the whole body all-absent and the
      // answer a 400 keyed `request` — a round trip that can only fail, for a
      // condition the device already knew.
      await tester.tap(_sheetCta);
      await pumpFlowFrames(tester, 2);

      expect(
        world.dayLogPosts,
        hasLength(1),
        reason:
            'still just the pain save. A second entry here is the T16b defect '
            'live: the sheet let an emptied note box submit, and the user gets '
            'the server rejection instead of a disabled button',
      );
      expect(find.byType(LumenErrorBanner), findsNothing);
      expect(find.byType(DayLogEditorScreen), findsOneWidget);
      expect(world.days['2026-04-08']!.log!.notes, 'Cramps all morning.');
    },
  );
}
