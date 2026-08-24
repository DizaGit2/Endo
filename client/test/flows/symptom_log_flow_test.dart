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
// R3 — nothing settles; frame counts are stated at each call site.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/create_symptoms_request.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/presentation/cycle_calendar_screen.dart';
import 'package:lumen/features/cycle/presentation/day_detail_screen.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/application/symptom_form_controller.dart';
import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
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

      await _tapScrolled(tester, _saveCta);
      await pumpFlowFrames(tester, 3);

      expect(world.symptomPosts, hasLength(1));
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
}
