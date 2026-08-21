// PeriodEditorController — screen 11's period-event editor (P4b-T16c).
//
// `POST /cycle/events` is a FULL UPSERT: the body describes the row's whole
// desired final state, and anything it does not carry is CLEARED. That is the
// OPPOSITE of the day-log editor beside it on this same screen, and every test
// below exists because of that one difference.
//
// Three claims worth stating up front, because a reader who knows
// `day_log_editor_controller_test.dart` will expect the other answer:
//
//  1. **There are no `touched` flags and there must not be.** Every save sends
//     all four fields. A field the user never looked at is re-asserted anyway,
//     because omitting it would delete it.
//  2. **A blank note is a REAL ERASE**, deliberately — `CycleService` assigns
//     `row.NotesEnc` unconditionally. The test that pins it says so in its own
//     name, so nobody "fixes" it into the sibling endpoint's no-op.
//  3. **The kind chip selects WHICH ROW is being edited**, because the upsert
//     key is `(user, kind, occurredOn)`. Changing it re-seeds flow and note
//     from that other row; carrying them across would post one row's note onto
//     another row and wipe that row's own.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/application/period_editor_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/harness.dart';

class _MockCycleRepository extends Mock implements CycleRepository {}

/// What one `logEvent` call actually carried.
typedef _EventCall = ({
  String kind,
  Date occurredOn,
  int? flowIntensity,
  String? notes,
});

typedef _DeleteCall = ({String id, Date occurredOn});

class _Counter {
  int value = 0;
}

class _CountingDashboard extends DashboardController {
  _CountingDashboard(this.counter);
  final _Counter counter;

  @override
  Future<CacheResult<DashboardView>> build() async {
    counter.value++;
    return Fresh(
      DashboardView(
        today: DateTime(2026, 4, 20),
        displayName: 'Maya',
        todayPain: null,
        todayMood: null,
        yesterdayPain: null,
        phaseUnavailableReason: null,
      ),
    );
  }
}

class _CountingCalendar extends CycleCalendarController {
  _CountingCalendar(this.refreshes, this.builds, {this.settles = true});

  final _Counter refreshes;

  /// Counted SEPARATELY from [refreshes]: a bare `ref.read` of this
  /// `autoDispose` provider CREATES the element, fires this `build()` and
  /// disposes it again, so a guard test written only against `exists` passes
  /// against the very defect it exists to catch.
  final _Counter builds;

  /// When false, `build()` never completes — `ref.exists` is true and
  /// `hasValue` is false, the state T16b's mutation round found untested.
  final bool settles;

  @override
  Future<CycleCalendarView> build() {
    builds.value++;
    if (!settles) return Completer<CycleCalendarView>().future;
    return Future<CycleCalendarView>.value(
      CycleCalendarView(
        visibleMonth: DateTime(2026, 4),
        today: Date(2026, 4, 20),
        phase: null,
        dayByDate: const {},
      ),
    );
  }

  @override
  Future<void> refresh() async {
    refreshes.value++;
  }
}

/// A day-detail controller settled on [view], counting its own rebuilds.
class _SeededDayDetail extends DayDetailController {
  _SeededDayDetail(this.view, this.builds) : super(view.date);

  final DayDetailView view;
  final _Counter builds;

  @override
  Future<DayDetailView> build() async {
    builds.value++;
    return view;
  }
}

void main() {
  final date = DateTime(2026, 4, 20);
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

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// The day view the editor seeds itself from.
  ///
  /// **[symptoms] defaults to a NON-EMPTY list and [log] to a real row**, for
  /// the reason T16b's mutation round measured: with both empty, "the adoption
  /// left them alone" and "the adoption wiped them" are the SAME assertion, and
  /// a mutant that dropped either survived the whole suite.
  DayDetailView viewWith(List<CycleEventResponse> events) => DayDetailView(
    date: date,
    log: cycleDayLogFixture(pain: 4, mood: 2, notes: 'a day note'),
    events: events,
    symptoms: [symptomResponseFixture(symptomCode: 'bloating')],
    symptomsTotal: 1,
  );

  void stubLogEvent({CycleEventResponse? body, Object? throws}) {
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
      return body ?? cycleEventFixture();
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

  late _Counter dayDetailBuilds;

  ProviderContainer buildContainer({
    List<CycleEventResponse> events = const <CycleEventResponse>[],
    bool seedDayDetail = true,
    List<Override> extra = const <Override>[],
  }) {
    dayDetailBuilds = _Counter();
    final container = ProviderContainer(
      overrides: <Override>[
        cycleRepositoryProvider.overrideWithValue(repo),
        if (seedDayDetail)
          dayDetailControllerProvider(date).overrideWith(
            () => _SeededDayDetail(viewWith(events), dayDetailBuilds),
          ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Reads the editor after the day view it seeds from has settled — screen
  /// 11's own gate (the affordance lives in the `data` arm of `view.when`).
  Future<PeriodEditorController> editor(
    ProviderContainer container, {
    bool seedDayDetail = true,
  }) async {
    if (seedDayDetail) {
      container.listen(dayDetailControllerProvider(date), (_, _) {});
      await container.read(dayDetailControllerProvider(date).future);
    }
    container.listen(periodEditorControllerProvider(date), (_, _) {});
    return container.read(periodEditorControllerProvider(date).notifier);
  }

  PeriodEditorForm formOf(ProviderContainer c) =>
      c.read(periodEditorControllerProvider(date));

  DayDetailView viewOf(ProviderContainer c) =>
      c.read(dayDetailControllerProvider(date)).value!;

  // -------------------------------------------------------------------------
  // Seeding — R2: seed EVERY control from the existing event
  // -------------------------------------------------------------------------

  group('seeding', () {
    test(
      'a day with no events opens with nothing selected and an empty note',
      () async {
        final container = buildContainer();
        await editor(container);

        final form = formOf(container);
        expect(form.kind, isNull);
        expect(form.flowIntensity, isNull);
        expect(form.notes, '');
        expect(form.selectedEvent, isNull);
      },
    );

    test('every control reflects the stored event — nothing is blank that has '
        'a stored value', () async {
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-1',
            kind: 'period_start',
            flowIntensity: 3,
            notes: 'stored note',
          ),
        ],
      );
      await editor(container);

      final form = formOf(container);
      expect(form.kind, 'period_start');
      expect(form.flowIntensity, 3);
      expect(form.notes, 'stored note');
      expect(form.selectedEvent?.id, 'evt-1');
    });

    test('a stored event with NO flow and NO note seeds those empty, never to '
        'some default', () async {
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'spotting'),
        ],
      );
      await editor(container);

      expect(formOf(container).kind, 'spotting');
      expect(formOf(container).flowIntensity, isNull);
      expect(formOf(container).notes, '');
    });

    test('with several events on the day it opens on the FIRST one the server '
        'returned, and holds the others ready', () async {
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-end', kind: 'period_end'),
          cycleEventFixture(
            id: 'evt-start',
            kind: 'period_start',
            flowIntensity: 4,
          ),
        ],
      );
      await editor(container);

      expect(formOf(container).kind, 'period_end');
      expect(formOf(container).storedFor('period_start')?.id, 'evt-start');
    });

    test('an event whose kind is outside the ratified three is NOT selectable '
        '— the sheet can only ever send one of the three', () async {
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-x', kind: 'ovulation', flowIntensity: 2),
          cycleEventFixture(id: 'evt-spot', kind: 'spotting'),
        ],
      );
      await editor(container);

      expect(formOf(container).kind, 'spotting');
      expect(formOf(container).flowIntensity, isNull);
    });

    test('a day view that never settled seeds an EMPTY form rather than '
        'inventing one', () async {
      final container = buildContainer(seedDayDetail: false);
      await editor(container, seedDayDetail: false);

      expect(formOf(container).kind, isNull);
      expect(formOf(container).notes, '');
    });
  });

  // -------------------------------------------------------------------------
  // The kind chip selects the ROW
  // -------------------------------------------------------------------------

  group('changing the kind re-targets the row it describes', () {
    test('switching to a kind that HAS a stored event re-seeds flow and note '
        'from THAT event — it never carries the previous row\'s values across',
        () async {
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-start',
            kind: 'period_start',
            flowIntensity: 4,
            notes: 'first day',
          ),
          cycleEventFixture(
            id: 'evt-spot',
            kind: 'spotting',
            flowIntensity: 1,
            notes: 'light spotting',
          ),
        ],
      );
      final controller = await editor(container);
      expect(formOf(container).kind, 'period_start');

      controller.setKind('spotting');

      expect(formOf(container).flowIntensity, 1);
      expect(
        formOf(container).notes,
        'light spotting',
        reason:
            'posting "first day" onto the spotting row would wipe that row\'s '
            'own note under FULL UPSERT',
      );
    });

    test('switching to a kind with NO stored event blanks flow and note', () async {
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-start',
            kind: 'period_start',
            flowIntensity: 4,
            notes: 'first day',
          ),
        ],
      );
      final controller = await editor(container);

      controller.setKind('period_end');

      expect(formOf(container).kind, 'period_end');
      expect(formOf(container).flowIntensity, isNull);
      expect(formOf(container).notes, '');
    });

    test('deselecting the kind clears the form and BLOCKS the save — the '
        'server rejects a body with no kind', () async {
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-start',
            kind: 'period_start',
            flowIntensity: 4,
            notes: 'first day',
          ),
        ],
      );
      final controller = await editor(container);

      controller.setKind(null);

      expect(formOf(container).kind, isNull);
      expect(formOf(container).flowIntensity, isNull);
      expect(formOf(container).notes, '');
      expect(formOf(container).blockReason, kPeriodEditorNoKindMessage);
      expect(formOf(container).canSubmit, isFalse);
    });

    test('re-selecting a deselected kind seeds it back from the stored row — '
        'a mis-tap is never permanent (T20-G)', () async {
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-start',
            kind: 'period_start',
            flowIntensity: 4,
            notes: 'first day',
          ),
        ],
      );
      final controller = await editor(container);

      controller.setKind(null);
      controller.setKind('period_start');

      expect(formOf(container).flowIntensity, 4);
      expect(formOf(container).notes, 'first day');
    });
  });

  // -------------------------------------------------------------------------
  // Every save sends all four fields — R2
  // -------------------------------------------------------------------------

  group('the save', () {
    test('sends ALL FOUR fields, including the ones the user never touched — '
        'an omitted field is CLEARED on this endpoint', () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-1',
            kind: 'period_start',
            flowIntensity: 3,
            notes: 'stored note',
          ),
        ],
      );
      final controller = await editor(container);

      expect(await controller.submit(), isTrue);

      expect(saves, hasLength(1));
      expect(saves.single.kind, 'period_start');
      expect(saves.single.occurredOn, Date(2026, 4, 20));
      expect(
        saves.single.flowIntensity,
        3,
        reason: 'untouched, and re-asserted anyway — omitting it clears it',
      );
      expect(saves.single.notes, 'stored note');
    });

    test('occurredOn is the ROUTE date, never re-derived from the stored event',
        () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-1',
            kind: 'period_start',
            occurredOn: Date(2019, 7, 1),
          ),
        ],
      );
      final controller = await editor(container);

      await controller.submit();

      expect(saves.single.occurredOn, Date(2026, 4, 20));
    });

    test('S-1 — DELIBERATE: emptying the note sends an EMPTY note, which '
        'ERASES the stored ciphertext. That is the user asking for the note to '
        'go, and it is the ONLY way to remove one. Do NOT "fix" this into a '
        'no-op — that is POST /cycle/day/{date}\'s rule, not this one\'s.',
        () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-1',
            kind: 'period_start',
            flowIntensity: 2,
            notes: 'stored note',
          ),
        ],
      );
      final controller = await editor(container);
      expect(formOf(container).notes, 'stored note');

      controller.setNotes('');
      await controller.submit();

      expect(
        saves.single.notes,
        '',
        reason:
            'CycleService trims it, finds it empty, and assigns '
            'row.NotesEnc = null UNCONDITIONALLY — the ciphertext is destroyed',
      );
      expect(saves.single.flowIntensity, 2, reason: 'the flow is untouched');
    });

    test('clearing the flow chips sends a null flow, which the wire OMITS and '
        'the server reads as CLEAR — the only way to take a level back off',
        () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-1',
            kind: 'period_start',
            flowIntensity: 4,
            notes: 'stored note',
          ),
        ],
      );
      final controller = await editor(container);

      controller.setFlow(null);
      await controller.submit();

      expect(saves.single.flowIntensity, isNull);
      expect(saves.single.notes, 'stored note');
    });

    test('a save with no kind selected is refused and issues NO request',
        () async {
      stubLogEvent();
      final container = buildContainer();
      final controller = await editor(container);

      expect(await controller.submit(), isFalse);
      expect(saves, isEmpty);
    });

    test('an OPENED-AND-UNTOUCHED form is submittable, unlike the day-log '
        'editor beside it: re-posting the same four values is a legal, '
        'harmless upsert here', () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
      );
      final controller = await editor(container);

      expect(formOf(container).blockReason, isNull);
      expect(formOf(container).canSubmit, isTrue);
      expect(await controller.submit(), isTrue);
    });

    test('a second submit while one is in flight is refused', () async {
      final gate = Completer<CycleEventResponse>();
      when(
        () => repo.logEvent(
          kind: any(named: 'kind'),
          occurredOn: any(named: 'occurredOn'),
          flowIntensity: any(named: 'flowIntensity'),
          notes: any(named: 'notes'),
        ),
      ).thenAnswer((invocation) {
        saves.add((
          kind: invocation.namedArguments[#kind] as String,
          occurredOn: invocation.namedArguments[#occurredOn] as Date,
          flowIntensity: invocation.namedArguments[#flowIntensity] as int?,
          notes: invocation.namedArguments[#notes] as String?,
        ));
        return gate.future;
      });
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
      );
      final controller = await editor(container);

      final first = controller.submit();
      expect(await controller.submit(), isFalse);
      gate.complete(cycleEventFixture());
      await first;

      expect(saves, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  // Failure — R9's shape
  // -------------------------------------------------------------------------

  group('a failed save', () {
    test('keeps every answer exactly as the user left it and records the '
        'failure', () async {
      stubLogEvent(throws: const NetworkFailure());
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-1',
            kind: 'period_start',
            flowIntensity: 2,
            notes: 'stored',
          ),
        ],
      );
      final controller = await editor(container);
      controller.setFlow(4);
      controller.setNotes('typed this');

      expect(await controller.submit(), isFalse);

      final form = formOf(container);
      expect(form.failure, isA<NetworkFailure>());
      expect(form.submitting, isFalse);
      expect(form.kind, 'period_start');
      expect(form.flowIntensity, 4);
      expect(form.notes, 'typed this');
    });

    test('a rejected save does NOT touch the day view', () async {
      stubLogEvent(
        throws: const ValidationFailure(
          fields: {
            'occurredOn': ['date is before the earliest allowed date'],
          },
        ),
      );
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-1',
            kind: 'period_start',
            flowIntensity: 1,
          ),
        ],
      );
      final controller = await editor(container);
      controller.setFlow(4);

      await controller.submit();

      expect(viewOf(container).events.single.flowIntensity, 1);
    });

    test('any change clears the failure', () async {
      stubLogEvent(throws: const NetworkFailure());
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
      );
      final controller = await editor(container);
      await controller.submit();
      expect(formOf(container).failure, isNotNull);

      controller.setFlow(2);
      expect(formOf(container).failure, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // R10 — the 200 goes into the READ VIEW, never into the FORM
  // -------------------------------------------------------------------------

  group('the 200 body', () {
    test('is adopted into the READ VIEW, replacing that row and leaving every '
        'other member of the view alone', () async {
      stubLogEvent(
        body: cycleEventFixture(
          id: 'evt-1',
          kind: 'period_start',
          flowIntensity: 3,
          notes: 'saved note',
        ),
      );
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
      );
      final controller = await editor(container);
      controller.setFlow(3);
      controller.setNotes('saved note');

      await controller.submit();
      await settle();

      final view = viewOf(container);
      expect(view.events, hasLength(1));
      expect(view.events.single.flowIntensity, 3);
      expect(view.events.single.notes, 'saved note');
      expect(view.symptoms, hasLength(1), reason: 'a different table');
      expect(view.log?.pain, 4, reason: 'a different row');
      expect(
        dayDetailBuilds.value,
        1,
        reason:
            'ADOPTED, not invalidated — the sheet sits on top of this very '
            'provider, so invalidating would drop screen 11 to a spinner '
            'behind the scrim',
      );
    });

    test('is NEVER adopted into the FORM — the echoed kind/flow/note are not '
        'answers the user gave', () async {
      stubLogEvent(
        body: cycleEventFixture(
          id: 'evt-1',
          kind: 'spotting',
          flowIntensity: 1,
          notes: 'the server\'s echo',
        ),
      );
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
      );
      final controller = await editor(container);
      controller.setFlow(4);
      controller.setNotes('what I typed');

      await controller.submit();

      final form = formOf(container);
      expect(form.kind, 'period_start');
      expect(form.flowIntensity, 4);
      expect(form.notes, 'what I typed');
    });

    test('S-7 — a 200 dated somewhere OTHER than this screen\'s day is not '
        'patched onto this day\'s view; that view is invalidated instead',
        () async {
      stubLogEvent(
        body: cycleEventFixture(
          id: 'evt-other',
          kind: 'period_start',
          occurredOn: Date(2026, 5, 9),
        ),
      );
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
      );
      final controller = await editor(container);

      await controller.submit();
      await settle();

      expect(
        viewOf(container).events.map((e) => e.id),
        <String>['evt-1'],
        reason:
            'a re-read is what corrects this day; an event dated elsewhere '
            'must never be drawn onto it',
      );
      expect(
        dayDetailBuilds.value,
        2,
        reason: 'invalidated rather than adopted, so it re-read',
      );
    });

    test('a save on a day view that never settled INVALIDATES it rather than '
        'skipping it — the in-flight read predates the write', () async {
      stubLogEvent();
      final container = buildContainer(seedDayDetail: false);
      final controller = await editor(container, seedDayDetail: false);
      controller.setKind('period_start');

      expect(await controller.submit(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Dependents — R9
  // -------------------------------------------------------------------------

  group('refreshing the dependents', () {
    late _Counter dashboardBuilds;
    late _Counter calendarRefreshes;
    late _Counter calendarBuilds;

    setUp(() {
      dashboardBuilds = _Counter();
      calendarRefreshes = _Counter();
      calendarBuilds = _Counter();
    });

    List<Override> dependents({bool calendarSettles = true}) => <Override>[
      dashboardControllerProvider.overrideWith(
        () => _CountingDashboard(dashboardBuilds),
      ),
      cycleCalendarControllerProvider.overrideWith(
        () => _CountingCalendar(
          calendarRefreshes,
          calendarBuilds,
          settles: calendarSettles,
        ),
      ),
    ];

    test('the dashboard is invalidated', () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
        extra: dependents(),
      );
      container.listen(dashboardControllerProvider, (_, _) {});
      await settle();
      expect(dashboardBuilds.value, 1);

      final controller = await editor(container);
      await controller.submit();
      await settle();

      expect(dashboardBuilds.value, 2);
    });

    test('a calendar that exists AND has a value is refreshed', () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
        extra: dependents(),
      );
      container.listen(cycleCalendarControllerProvider, (_, _) {});
      await container.read(cycleCalendarControllerProvider.future);

      final controller = await editor(container);
      await controller.submit();
      await settle();

      expect(calendarRefreshes.value, 1);
    });

    test('a calendar that exists but has NOT settled is left alone — '
        'refresh() falls back to invalidateSelf(), which snaps the visible '
        'month back to today under a user who paged away', () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
        extra: dependents(calendarSettles: false),
      );
      container.listen(cycleCalendarControllerProvider, (_, _) {});
      await settle();

      final controller = await editor(container);
      await controller.submit();
      await settle();

      expect(calendarRefreshes.value, 0);
    });

    test('a calendar nobody opened is never CREATED', () async {
      stubLogEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
        extra: dependents(),
      );

      final controller = await editor(container);
      await controller.submit();
      await settle();

      expect(calendarBuilds.value, 0);
      expect(calendarRefreshes.value, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Delete — R6
  // -------------------------------------------------------------------------

  group('delete', () {
    test('deletes the SELECTED row by its own id and its own occurredOn — '
        'never the screen\'s route date (S-7)', () async {
      stubDeleteEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(
            id: 'evt-1',
            kind: 'period_start',
            occurredOn: Date(2026, 5, 9),
          ),
        ],
      );
      final controller = await editor(container);

      expect(formOf(container).canDelete, isTrue);
      expect(await controller.delete(), isTrue);

      expect(deletes, hasLength(1));
      expect(deletes.single.id, 'evt-1');
      expect(
        deletes.single.occurredOn,
        Date(2026, 5, 9),
        reason:
            'the row\'s own day is what its cache keys are filed under; the '
            'route date is a third value nobody checked',
      );
    });

    test('removes the row from the day view and leaves the rest alone',
        () async {
      stubDeleteEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
          cycleEventFixture(id: 'evt-2', kind: 'spotting'),
        ],
      );
      final controller = await editor(container);

      await controller.delete();
      await settle();

      final view = viewOf(container);
      expect(view.events.map((e) => e.id), <String>['evt-2']);
      expect(view.log?.pain, 4);
      expect(view.symptoms, hasLength(1));
    });

    test('FALSE-GREEN CLOSED (mutation m27) — a row that cannot supply its own '
        'occurredOn is NOT deletable, because the alternative is substituting '
        'the screen\'s route date, which is exactly what S-7 forbids',
        () async {
      stubDeleteEvent();
      final container = buildContainer(
        events: <CycleEventResponse>[
          // Built directly, not through `cycleEventFixture`, because that
          // fixture fills an unset `occurredOn` with a default — so it can
          // never produce the genuinely-null property this branch is about,
          // and every delete test written against it left the guard
          // unexercised. The mutation round caught that: dropping the
          // `occurredOn != null` half of `canDelete` reddened nothing.
          CycleEventResponse(
            (b) => b
              ..id = 'evt-1'
              ..kind = 'period_start',
          ),
        ],
      );
      final controller = await editor(container);

      expect(formOf(container).selectedEvent?.id, 'evt-1');
      expect(formOf(container).selectedEvent?.occurredOn, isNull);
      expect(
        formOf(container).canDelete,
        isFalse,
        reason:
            'the 204 carries no body, so occurredOn is the ONLY way the '
            'repository can name the keys this deletion invalidates',
      );
      expect(await controller.delete(), isFalse);
      expect(deletes, isEmpty);
    });

    test('is refused when the selected kind has no stored row — there is '
        'nothing to delete', () async {
      stubDeleteEvent();
      final container = buildContainer();
      final controller = await editor(container);
      controller.setKind('period_start');

      expect(formOf(container).canDelete, isFalse);
      expect(await controller.delete(), isFalse);
      expect(deletes, isEmpty);
    });

    test('a failed delete keeps the row on the day view and records the '
        'failure', () async {
      stubDeleteEvent(throws: const NetworkFailure());
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
      );
      final controller = await editor(container);

      expect(await controller.delete(), isFalse);

      expect(formOf(container).failure, isA<NetworkFailure>());
      expect(formOf(container).deleting, isFalse);
      expect(viewOf(container).events.single.id, 'evt-1');
    });
  });

  // -------------------------------------------------------------------------
  // S-9 — two editors, two endpoints, two failure modes
  // -------------------------------------------------------------------------

  group('S-9 — the two editors on this screen are independent', () {
    test('a failed period save issues NO day-log request and leaves the '
        'day view\'s own log exactly as it was', () async {
      stubLogEvent(throws: const NetworkFailure());
      final container = buildContainer(
        events: <CycleEventResponse>[
          cycleEventFixture(id: 'evt-1', kind: 'period_start'),
        ],
      );
      final controller = await editor(container);

      await controller.submit();

      verifyNever(
        () => repo.logDay(
          date: any(named: 'date'),
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          notes: any(named: 'notes'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          touchedNotes: any(named: 'touchedNotes'),
        ),
      );
      expect(formOf(container).failure, isA<NetworkFailure>());
      expect(viewOf(container).log?.pain, 4);
    });
  });
}
