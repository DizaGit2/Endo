// The period-event editor as a WIDGET (P4b-T16c) — semantics, the two chip
// rows that behave differently on purpose, and the one irreversible action
// either sheet on screen 11 offers.
//
// The controller's state machine is pinned in
// `application/period_editor_controller_test.dart`. What this file pins is the
// half a controller test structurally cannot see:
//
//  * the sheet says the FULL-UPSERT rule out loud, and does NOT say the
//    day-log editor's opposite one;
//  * the kind row's selected chip announces NO tap action (a re-tap is a
//    no-op) while the flow row's selected chip does (a re-tap CLEARS);
//  * the note box is SEEDED from the stored note — opening blank over a stored
//    note would arm the erase before the user did anything;
//  * the delete sits behind a real confirmation, and declining it writes
//    nothing;
//  * `Heavy` renders as a plain chip with no warning of any kind (T16-C).

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/application/period_editor_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/cycle/presentation/period_editor_screen.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_field_message.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _MockCycleRepository extends Mock implements CycleRepository {}

typedef _EventCall = ({
  String kind,
  Date occurredOn,
  int? flowIntensity,
  String? notes,
});

typedef _DeleteCall = ({String id, Date occurredOn});

/// Shows the sheet only once the day view has settled — screen 11's own gate
/// (the affordance lives in the `data` arm of `view.when`).
class _SettledDayHost extends ConsumerWidget {
  const _SettledDayHost({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(dayDetailControllerProvider(date));
    if (!view.hasValue) return const SizedBox.shrink();
    return LumenBottomSheet(child: PeriodEditorScreen(date: date));
  }
}

class _SettledDayDetail extends DayDetailController {
  _SettledDayDetail(this.view) : super(view.date);

  final DayDetailView view;

  @override
  Future<DayDetailView> build() async => view;
}

void main() {
  final date = DateTime(2026, 4, 7);
  late _MockCycleRepository repo;
  late List<_EventCall> saves;
  late List<_DeleteCall> deletes;

  setUpAll(() {
    registerFallbackValue(Date(2026, 1, 1));
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  setUp(() {
    repo = _MockCycleRepository();
    saves = <_EventCall>[];
    deletes = <_DeleteCall>[];
  });

  void stubLogEvent({Object? throws, CycleEventResponse? body}) {
    when(
      () => repo.logEvent(
        kind: any(named: 'kind'),
        occurredOn: any(named: 'occurredOn'),
        flowIntensity: any(named: 'flowIntensity'),
        notes: any(named: 'notes'),
      ),
    ).thenAnswer((invocation) async {
      saves.add((
        kind: invocation.namedArguments[#kind] as String,
        occurredOn: invocation.namedArguments[#occurredOn] as Date,
        flowIntensity: invocation.namedArguments[#flowIntensity] as int?,
        notes: invocation.namedArguments[#notes] as String?,
      ));
      if (throws != null) throw throws;
      return body ?? cycleEventFixture(occurredOn: Date(2026, 4, 7));
    });
  }

  void stubDeleteEvent({Object? throws}) {
    when(
      () => repo.deleteEvent(
        id: any(named: 'id'),
        occurredOn: any(named: 'occurredOn'),
      ),
    ).thenAnswer((invocation) async {
      deletes.add((
        id: invocation.namedArguments[#id] as String,
        occurredOn: invocation.namedArguments[#occurredOn] as Date,
      ));
      if (throws != null) throw throws;
    });
  }

  /// Mounts the sheet the way screen 11 does: over a day view that has ALREADY
  /// SETTLED. The gate is production shape, not scaffolding.
  Future<void> pumpSheet(
    WidgetTester tester, {
    List<CycleEventResponse> events = const <CycleEventResponse>[],
  }) async {
    await pumpApp(
      tester,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: _SettledDayHost(date: date),
        ),
      ),
      overrides: [
        cycleRepositoryProvider.overrideWithValue(repo),
        dayDetailControllerProvider(date).overrideWith(
          () => _SettledDayDetail(
            DayDetailView(
              date: date,
              log: null,
              events: events,
              symptoms: const [],
              symptomsTotal: 0,
            ),
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  List<CycleEventResponse> oneStart({int? flow, String? notes}) =>
      <CycleEventResponse>[
        cycleEventFixture(
          id: 'evt-1',
          kind: 'period_start',
          occurredOn: Date(2026, 4, 7),
          flowIntensity: flow,
          notes: notes,
        ),
      ];

  // `Spotting` is BOTH an event kind and flow level 1 — one word, two fields,
  // one sheet. That collision is real and shipped: it renders as ratified,
  // disambiguated by its field label, which is the ruling the phase already
  // made for screen 12's `Cramping` / `Cramping / joint pain` pair. A bare
  // `find.text('Spotting')` therefore matches TWO widgets, so every chip
  // assertion below names its row.
  //
  // The two rows are the sheet's only `Wrap`s, in tree order: kind, then flow.
  // `expectTwoChipRows` is called first wherever these are used, so a third
  // `Wrap` appearing later fails loudly here instead of silently re-pointing
  // one of the finders.
  void expectTwoChipRows(WidgetTester tester) {
    expect(
      find.byType(Wrap),
      findsNWidgets(2),
      reason: 'the kind row and the flow row, in that order',
    );
  }

  Finder kindChip(String label) =>
      find.descendant(of: find.byType(Wrap).at(0), matching: find.text(label));

  Finder flowChip(String label) =>
      find.descendant(of: find.byType(Wrap).at(1), matching: find.text(label));

  // -------------------------------------------------------------------------
  // Chrome and copy
  // -------------------------------------------------------------------------

  group('the sheet', () {
    testWidgetsWithSemantics('renders no dingbats', (tester) async {
      await pumpSheet(tester, events: oneStart(flow: 3, notes: 'A note.'));

      expectNoDingbats(tester, screen: 'PeriodEditorScreen');
    });

    testWidgetsWithSemantics(
      'names the DAY it writes, and offers no control that could change it',
      (tester) async {
        await pumpSheet(tester);

        expect(find.text('April 7'), findsOneWidget);
        // `occurredOn` IS a body field on this endpoint, so a date control
        // would be buildable here — and it would be a lie: there is no move
        // operation, so changing the date writes a SECOND row and leaves the
        // original live (T16-G).
        expect(find.byIcon(Icons.calendar_today), findsNothing);
        expect(find.byIcon(Icons.edit_calendar), findsNothing);
        expect(find.byType(CalendarDatePicker), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).maxLines,
          5,
          reason: 'the multiline note box, not a date input',
        );
      },
    );

    testWidgetsWithSemantics(
      'states the FULL-UPSERT rule where the user can read it before typing, '
      'and does NOT carry the day-log editor\'s opposite sentence',
      (tester) async {
        await pumpSheet(tester, events: oneStart(notes: 'stored'));

        expect(find.text(kPeriodEditorUpsertNote), findsOneWidget);
        // The sibling sheet says "Emptying a field does not remove it." That
        // is true there and false here, and the two sheets sit on one screen.
        expect(find.textContaining('does not remove'), findsNothing);
        expect(find.textContaining('Saved values stay'), findsNothing);
      },
    );

    testWidgetsWithSemantics(
      'T16-C — `Heavy` ships as a bare chip label: no warning, no alarm '
      'chrome, no advisory copy anywhere on the sheet',
      (tester) async {
        await pumpSheet(tester, events: oneStart(flow: 4));

        expect(find.text('Heavy'), findsOneWidget);
        for (final word in const <String>[
          'heavy bleeding',
          'Heavy bleeding',
          'doctor',
          'clinician',
          'concern',
          'warning',
          'Warning',
          'unusual',
          'see a',
          'talk to',
        ]) {
          expect(
            find.textContaining(word),
            findsNothing,
            reason:
                'C-15\'s red-flag note needs clinician AND legal sign-off and '
                'ships nowhere in P4b — only the C-04 label ships',
          );
        }
        expect(find.byIcon(Icons.warning), findsNothing);
        expect(find.byIcon(Icons.warning_amber), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Seeding
  // -------------------------------------------------------------------------

  group('the form opens on what is already stored', () {
    testWidgetsWithSemantics(
      'every control reflects the stored event — the kind chip, the flow chip '
      'and the note box',
      (tester) async {
        await pumpSheet(
          tester,
          events: oneStart(flow: 3, notes: 'stored note'),
        );

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'stored note',
        );
        expect(
          tester
              .getSemantics(kindChip('Period start'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        expectTwoChipRows(tester);
        expect(
          tester
              .getSemantics(flowChip('Medium'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
      },
    );

    testWidgetsWithSemantics(
      'a day with no period event opens with an empty note box and nothing '
      'selected, and the save is BLOCKED with the reason beside it',
      (tester) async {
        await pumpSheet(tester);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '',
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(find.text(kPeriodEditorNoKindMessage), findsOneWidget);
        expect(find.byType(LumenFieldMessage), findsOneWidget);
      },
    );

    testWidgetsWithSemantics(
      'changing the kind RE-SEEDS the note box from the newly-addressed row — '
      'carrying the old row\'s text across would post it onto, and wipe, the '
      'new row',
      (tester) async {
        await pumpSheet(
          tester,
          events: <CycleEventResponse>[
            cycleEventFixture(
              id: 'evt-start',
              kind: 'period_start',
              occurredOn: Date(2026, 4, 7),
              notes: 'first day',
            ),
            cycleEventFixture(
              id: 'evt-spot',
              kind: 'spotting',
              occurredOn: Date(2026, 4, 7),
              notes: 'light spotting',
            ),
          ],
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'first day',
        );

        expectTwoChipRows(tester);
        await tester.tap(kindChip('Spotting'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'light spotting',
        );
      },
    );

    testWidgetsWithSemantics(
      'typing does NOT rewrite the box under the user — the re-seed is keyed '
      'on the kind, not on the form state',
      (tester) async {
        await pumpSheet(tester, events: oneStart(notes: 'stored note'));

        await tester.enterText(find.byType(TextField), 'half typ');
        await tester.pump();

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'half typ',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // The two chip rows, which behave differently ON PURPOSE
  // -------------------------------------------------------------------------

  group('the chip rows', () {
    testWidgetsWithSemantics(
      'the SELECTED kind chip offers NO tap action and reports itself '
      'unavailable — a re-tap there would do nothing, and a control that '
      'cannot act must not announce itself as one that can',
      (tester) async {
        await pumpSheet(tester, events: oneStart());

        expectTwoChipRows(tester);
        final SemanticsData chosen = tester
            .getSemantics(kindChip('Period start'))
            .getSemanticsData();
        expect(chosen.hasAction(SemanticsAction.tap), isFalse);
        expect(chosen.flagsCollection.isEnabled, Tristate.isFalse);
        expect(chosen.flagsCollection.isSelected, Tristate.isTrue);

        final SemanticsData other = tester
            .getSemantics(kindChip('Spotting'))
            .getSemanticsData();
        expect(other.hasAction(SemanticsAction.tap), isTrue);
        expect(other.flagsCollection.isEnabled, Tristate.isTrue);
      },
    );

    testWidgetsWithSemantics(
      'the SELECTED flow chip KEEPS its tap action, because a re-tap there '
      'CLEARS the level — the only way to take one back off an event',
      (tester) async {
        stubLogEvent();
        await pumpSheet(tester, events: oneStart(flow: 4));

        final SemanticsData chosen = tester
            .getSemantics(find.text('Heavy'))
            .getSemanticsData();
        expect(
          chosen.hasAction(SemanticsAction.tap),
          isTrue,
          reason:
              'unlike the kind row beside it, this tap does something — the '
              'two rows differ because the endpoint treats their nulls '
              'differently',
        );
        expect(chosen.flagsCollection.isEnabled, Tristate.isTrue);

        await tester.tap(find.text('Heavy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kPeriodEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(saves.single.flowIntensity, isNull);
      },
    );

    testWidgetsWithSemantics(
      'picking a flow chip sends the WIRE ordinal, never the list index',
      (tester) async {
        stubLogEvent();
        await pumpSheet(tester, events: oneStart());

        // 'Heavy' is the fourth label — wire ordinal 4, list index 3.
        await tester.tap(find.text('Heavy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kPeriodEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(saves.single.flowIntensity, 4);
      },
    );

    testWidgetsWithSemantics('picking a different kind sends THAT kind\'s code',
        (tester) async {
      stubLogEvent();
      await pumpSheet(tester, events: oneStart());

      await tester.tap(find.text('Period end'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kPeriodEditorSaveLabel));
      await tester.pumpAndSettle();

      expect(saves.single.kind, 'period_end');
    });
  });

  // -------------------------------------------------------------------------
  // The save
  // -------------------------------------------------------------------------

  group('the save', () {
    testWidgetsWithSemantics(
      'sends all four fields from an untouched, prefilled sheet',
      (tester) async {
        stubLogEvent();
        await pumpSheet(
          tester,
          events: oneStart(flow: 2, notes: 'stored note'),
        );

        await tester.tap(find.text(kPeriodEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(saves, hasLength(1));
        expect(saves.single.kind, 'period_start');
        expect(saves.single.occurredOn, Date(2026, 4, 7));
        expect(saves.single.flowIntensity, 2);
        expect(saves.single.notes, 'stored note');
      },
    );

    testWidgetsWithSemantics(
      'S-1 — DELIBERATE: clearing the note box and saving sends an EMPTY note '
      'and ERASES the stored one. This is the ONLY way to remove a note, and '
      'it must not be "fixed" into the day-log editor\'s no-op.',
      (tester) async {
        stubLogEvent();
        await pumpSheet(tester, events: oneStart(flow: 2, notes: 'stored note'));

        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        await tester.tap(find.text(kPeriodEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(saves.single.notes, '');
        expect(
          saves.single.flowIntensity,
          2,
          reason: 'the flow was untouched and is re-asserted, not dropped',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Delete, behind its confirmation — R6
  // -------------------------------------------------------------------------

  group('delete', () {
    testWidgetsWithSemantics(
      'is not offered at all when the selected kind has no stored row — an '
      'action with no target is removed, not disabled (R-10)',
      (tester) async {
        await pumpSheet(tester);

        expect(find.text(kPeriodEditorDeleteLabel), findsNothing);
      },
    );

    testWidgetsWithSemantics(
      'asks first — the affordance alone writes NOTHING',
      (tester) async {
        stubDeleteEvent();
        await pumpSheet(tester, events: oneStart(notes: 'stored note'));

        await tester.tap(find.text(kPeriodEditorDeleteLabel));
        await tester.pumpAndSettle();

        expect(find.text(kPeriodEditorDeleteConfirmTitle), findsOneWidget);
        expect(find.text(kPeriodEditorDeleteConfirmBody), findsOneWidget);
        expect(
          deletes,
          isEmpty,
          reason: 'the confirmation has not been answered yet',
        );
      },
    );

    testWidgetsWithSemantics(
      'DECLINING the confirmation writes nothing, leaves the sheet open and '
      'leaves every answer alone',
      (tester) async {
        stubDeleteEvent();
        await pumpSheet(tester, events: oneStart(notes: 'stored note'));

        await tester.tap(find.text(kPeriodEditorDeleteLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kPeriodEditorDeleteCancelLabel));
        await tester.pumpAndSettle();

        expect(deletes, isEmpty);
        expect(find.byType(PeriodEditorScreen), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'stored note',
        );
      },
    );

    testWidgetsWithSemantics(
      'CONFIRMING it deletes the row by its own id and its own day, then '
      'closes the sheet',
      (tester) async {
        stubDeleteEvent();
        await pumpSheet(tester, events: oneStart(notes: 'stored note'));

        await tester.tap(find.text(kPeriodEditorDeleteLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kPeriodEditorDeleteConfirmLabel));
        await tester.pumpAndSettle();

        expect(deletes, hasLength(1));
        expect(deletes.single.id, 'evt-1');
        expect(deletes.single.occurredOn, Date(2026, 4, 7));
        expect(saves, isEmpty, reason: 'a delete is not a save');
      },
    );
  });

  // -------------------------------------------------------------------------
  // Failure and retry
  // -------------------------------------------------------------------------

  group('a failed save', () {
    testWidgetsWithSemantics(
      'keeps every answer on screen, relabels the CTA and puts the message '
      'directly above it',
      (tester) async {
        stubLogEvent(throws: const NetworkFailure());
        await pumpSheet(tester, events: oneStart(flow: 2));

        await tester.tap(find.text('Heavy'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'typed this');
        await tester.pump();
        await tester.tap(find.text(kPeriodEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(find.byType(LumenErrorBanner), findsOneWidget);
        expect(find.text(const NetworkFailure().message), findsOneWidget);
        expect(find.text(kPeriodEditorRetryLabel), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'typed this',
        );
        expect(
          tester
              .getSemantics(find.text('Heavy'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );

        final bannerY = tester.getBottomLeft(find.byType(LumenErrorBanner)).dy;
        final ctaY = tester.getTopLeft(find.byType(FilledButton)).dy;
        expect(
          ctaY - bannerY,
          lessThan(40),
          reason:
              'the failure message must stay next to the button that failed',
        );
      },
    );

    testWidgetsWithSemantics(
      'the retry is a real button and re-issues exactly one request',
      (tester) async {
        stubLogEvent(throws: const NetworkFailure());
        await pumpSheet(tester, events: oneStart());

        await tester.tap(find.text(kPeriodEditorSaveLabel));
        await tester.pumpAndSettle();

        await expectRetryReissuesOneRequest(
          tester,
          requestCount: () => saves.length,
          label: kPeriodEditorRetryLabel,
        );
      },
    );

    testWidgetsWithSemantics(
      'a 400 keyed `occurredOn` — the backdate floor, which nothing on the '
      'device can pre-check and which has no control on this sheet — is '
      'promoted into the banner rather than dropped',
      (tester) async {
        stubLogEvent(
          throws: const ValidationFailure(
            fields: {
              'occurredOn': ['date is before the earliest allowed date'],
            },
          ),
        );
        await pumpSheet(tester, events: oneStart());

        await tester.tap(find.text(kPeriodEditorSaveLabel));
        await tester.pumpAndSettle();

        expect(
          find.text('date is before the earliest allowed date'),
          findsOneWidget,
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // In flight
  // -------------------------------------------------------------------------

  group('while the write is in flight', () {
    testWidgetsWithSemantics(
      'every control is frozen and the sheet refuses to be dismissed',
      (tester) async {
        when(
          () => repo.logEvent(
            kind: any(named: 'kind'),
            occurredOn: any(named: 'occurredOn'),
            flowIntensity: any(named: 'flowIntensity'),
            notes: any(named: 'notes'),
          ),
        ).thenAnswer(
          (_) => Future<CycleEventResponse>.delayed(
            const Duration(seconds: 1),
            cycleEventFixture,
          ),
        );

        await pumpSheet(tester, events: oneStart());
        await tester.tap(find.text(kPeriodEditorSaveLabel));
        await tester.pump();

        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        expectTwoChipRows(tester);
        expect(
          tester
              .getSemantics(kindChip('Spotting'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
          reason: 'no chip may change the answer mid-write',
        );
        expect(
          tester
              .getSemantics(flowChip('Spotting'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
        );
        final popScope = tester
            .widgetList<PopScope<dynamic>>(find.byType(PopScope<dynamic>))
            .single;
        expect(
          popScope.canPop,
          isFalse,
          reason:
              'abandoning a committed FULL UPSERT leaves every open screen '
              'showing pre-write data',
        );

        await tester.pumpAndSettle(const Duration(seconds: 2));
      },
    );
  });
}
