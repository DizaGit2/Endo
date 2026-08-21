// DayLogEditorController — screen 11's day-log editor (P4b-T16b).
//
// TDD (RED first). This is the state machine behind the ONE write screen 11
// makes: `POST /cycle/day/{date}`, a MERGE.
//
// The whole file exists to pin one property: **only a field the user actually
// TOUCHED is sent**, and "touched" is its own explicit state that is never
// re-derived from whether the value happens to be null. Two named data-loss
// paths collapse into that single rule:
//
//  * S-1 — a notes box that opens holding the stored note, is never edited,
//    and is submitted anyway would send that text back. Untouched, so it is
//    omitted, so it cannot.
//  * S-2 — the form is SEEDED from a day read that may have come out of a
//    5-minute-TTL cache. Under MERGE an untouched field is omitted, so a
//    stale seed cannot become a lost update. Staleness stops mattering
//    rather than having to be established — which matters, because
//    `CacheResult.Fresh` ALSO means "a cache hit inside the TTL" and
//    `cachedRead` has no `forceRefresh`, so "re-read until fresh" was never
//    an option in this codebase.
//
// Every assertion about touched-ness below varies the flag and the value
// INDEPENDENTLY. A suite that only ever supplies "untouched AND null"
// together cannot tell a `touched` guard from `built_value`'s own
// omit-nulls serializer, and deleting either would leave it green.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/application/day_log_editor_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/harness.dart';

class _MockCycleRepository extends Mock implements CycleRepository {}

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// The arguments one `logDay` call actually carried.
typedef _DayCall = ({
  DateTime date,
  int? pain,
  int? mood,
  String? notes,
  bool touchedPain,
  bool touchedMood,
  bool touchedNotes,
});

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
  _CountingCalendar(this.refreshes, this.builds);

  final _Counter refreshes;

  /// Counted SEPARATELY from [refreshes] for the reason
  /// `symptom_form_controller_test.dart` documents: a bare `ref.read` of this
  /// `autoDispose` provider CREATES the element, fires this `build()` and
  /// then disposes it again, so a guard test written only against `exists`
  /// passes against the very defect it exists to catch.
  final _Counter builds;

  @override
  Future<CycleCalendarView> build() async {
    builds.value++;
    return CycleCalendarView(
      visibleMonth: DateTime(2026, 4),
      today: Date(2026, 4, 20),
      phase: null,
      dayByDate: const {},
    );
  }

  @override
  Future<void> refresh() async {
    refreshes.value++;
  }
}

/// A day-detail controller settled on [view], counting its own rebuilds and
/// recording every state it is pushed into from outside.
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
  late List<_DayCall> calls;

  /// The day-detail view the editor seeds itself from.
  ///
  /// **[symptoms] defaults to a NON-EMPTY list, and that is load-bearing.**
  /// The mutation round caught this: with an empty list, "the adoption left
  /// the symptoms alone" and "the adoption wiped the symptoms" render the
  /// identical assertion, so a mutant that replaced `current.symptoms` with
  /// `const []` inside `DayDetailController.applySavedLog` survived the whole
  /// suite. A seeded row is what makes the two outcomes distinguishable.
  DayDetailView viewWith(
    CycleDayLogResponse? log, {
    List<SymptomResponse>? symptoms,
    int? symptomsTotal,
  }) {
    final rows = symptoms ?? <SymptomResponse>[symptomResponseFixture()];
    return DayDetailView(
      date: date,
      log: log,
      symptoms: rows,
      symptomsTotal: symptomsTotal ?? rows.length,
    );
  }

  void stubLogDay({CycleDayLogResponse? body, Object? throws}) {
    when(
      () => repo.logDay(
        date: any(named: 'date'),
        pain: any(named: 'pain'),
        mood: any(named: 'mood'),
        notes: any(named: 'notes'),
        touchedPain: any(named: 'touchedPain'),
        touchedMood: any(named: 'touchedMood'),
        touchedNotes: any(named: 'touchedNotes'),
      ),
    ).thenAnswer((invocation) async {
      calls.add((
        date: invocation.namedArguments[#date] as DateTime,
        pain: invocation.namedArguments[#pain] as int?,
        mood: invocation.namedArguments[#mood] as int?,
        notes: invocation.namedArguments[#notes] as String?,
        touchedPain: invocation.namedArguments[#touchedPain] as bool,
        touchedMood: invocation.namedArguments[#touchedMood] as bool,
        touchedNotes: invocation.namedArguments[#touchedNotes] as bool,
      ));
      if (throws != null) throw throws;
      return body ?? cycleDayLogFixture();
    });
  }

  /// A container with the editor wired to [repo] and the day view seeded
  /// from [log]. Nothing else is created unless a test asks for it.
  ProviderContainer buildContainer({
    CycleDayLogResponse? log,
    bool seedDayDetail = true,
    List<Override> extra = const <Override>[],
  }) {
    final container = ProviderContainer(
      overrides: <Override>[
        cycleRepositoryProvider.overrideWithValue(repo),
        if (seedDayDetail)
          dayDetailControllerProvider(date).overrideWith(
            () => _SeededDayDetail(viewWith(log), _Counter()),
          ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Opens the day view (so `ref.exists` is true, exactly as screen 11 does
  /// by watching it) and then the editor on top of it.
  Future<DayLogEditorForm> openEditor(ProviderContainer container) async {
    container.listen(dayDetailControllerProvider(date), (_, _) {});
    await settle();
    container.listen(dayLogEditorControllerProvider(date), (_, _) {});
    return container.read(dayLogEditorControllerProvider(date));
  }

  DayLogEditorController notifier(ProviderContainer c) =>
      c.read(dayLogEditorControllerProvider(date).notifier);

  DayLogEditorForm state(ProviderContainer c) =>
      c.read(dayLogEditorControllerProvider(date));

  setUp(() {
    repo = _MockCycleRepository();
    calls = <_DayCall>[];
  });

  // ---------------------------------------------------------------------------
  // Seeding
  // ---------------------------------------------------------------------------

  group('the form is SEEDED from the day already on screen', () {
    test('a logged day prefills pain, mood and the note — and nothing is '
        'marked touched by the seeding', () async {
      final c = buildContainer(
        log: cycleDayLogFixture(pain: 8, mood: 2, notes: 'stored note'),
      );
      final form = await openEditor(c);

      expect(form.pain, 8);
      expect(form.mood, 2);
      expect(form.notes, 'stored note');
      expect(form.touchedPain, isFalse);
      expect(form.touchedMood, isFalse);
      expect(form.touchedNotes, isFalse);
    });

    test('pain: 0 seeds as 0, not as "not recorded" (D-08)', () async {
      final c = buildContainer(
        log: cycleDayLogFixture(pain: 0, mood: null, notes: null),
      );
      final form = await openEditor(c);

      expect(form.pain, 0);
      expect(form.mood, isNull);
      expect(form.notes, '');
    });

    test('an unlogged day (log: null) opens empty', () async {
      final c = buildContainer(log: null);
      final form = await openEditor(c);

      expect(form.pain, isNull);
      expect(form.mood, isNull);
      expect(form.notes, '');
    });

    test('the day view NOT being open at all is not an error — the form '
        'opens empty rather than creating the day controller and firing two '
        'GETs behind a modal', () async {
      final c = buildContainer(seedDayDetail: false);
      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      final form = c.read(dayLogEditorControllerProvider(date));

      expect(form.pain, isNull);
      expect(form.notes, '');
      expect(
        c.exists(dayDetailControllerProvider(date)),
        isFalse,
        reason: 'seeding must not CREATE the day-detail controller',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // canSubmit / blockReason
  // ---------------------------------------------------------------------------

  group('blockReason', () {
    test('a freshly-seeded form is blocked — a prefilled editor with nothing '
        'changed has nothing to assert', () async {
      final c = buildContainer(
        log: cycleDayLogFixture(pain: 8, mood: 2, notes: 'stored note'),
      );
      final form = await openEditor(c);

      expect(form.blockReason, kDayLogNothingChangedMessage);
      expect(form.canSubmit, isFalse);
    });

    test('touching one control unblocks it', () async {
      final c = buildContainer();
      await openEditor(c);

      notifier(c).setPain(4);

      expect(state(c).blockReason, isNull);
      expect(state(c).canSubmit, isTrue);
    });

    test('pain 0 unblocks it — never a falsiness test (D-08)', () async {
      final c = buildContainer();
      await openEditor(c);

      notifier(c).setPain(0);

      expect(state(c).blockReason, isNull);
    });

    test('M-7 — a user who CLEARS a prefilled note and changes nothing else '
        'is blocked on the device, never 400ed by the endpoint', () async {
      final c = buildContainer(
        log: cycleDayLogFixture(pain: null, mood: null, notes: 'a note'),
      );
      await openEditor(c);

      notifier(c).setNotes('   ');

      expect(state(c).touchedNotes, isTrue);
      expect(state(c).blockReason, kDayLogEmptyChangeMessage);
    });

    test('I-2 — the block reason describes the SAVE, not the DAY: it never '
        'says the day holds nothing while its stored pain is shown', () async {
      // The reviewer's measured state: a day that STORES pain 4, whose
      // prefilled note the user empties. Nothing about the day changed.
      final c = buildContainer(
        log: cycleDayLogFixture(pain: 4, mood: null, notes: 'a note'),
      );
      await openEditor(c);

      notifier(c).setNotes('');

      expect(state(c).pain, 4, reason: 'the stored pain is untouched');
      expect(state(c).blockReason, kDayLogEmptyChangeMessage);
      expect(
        kDayLogEmptyChangeMessage,
        isNot(contains('required')),
        reason:
            'the server sentence "at least one of pain, mood or notes is '
            'required" is true of the REQUEST and false as the user reads '
            'it: this day requires nothing, it already stores pain 4. That '
            'sentence reaches the user only off the wire, through '
            'dayLogEditorBannerMessage, never from this constant.',
      );
    });

    test('a blocked submit() is a no-op, not a request', () async {
      stubLogDay();
      final c = buildContainer();
      await openEditor(c);

      final ok = await notifier(c).submit();

      expect(ok, isFalse);
      expect(calls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // What reaches the repository — the touched matrix
  // ---------------------------------------------------------------------------

  group('only TOUCHED fields are asserted', () {
    test('S-2 — a stale seed the user never edited is NOT written back: '
        'editing pain alone sends touchedPain only, even though mood and '
        'notes hold seeded values', () async {
      stubLogDay();
      final c = buildContainer(
        log: cycleDayLogFixture(pain: 8, mood: 2, notes: 'stored note'),
      );
      await openEditor(c);

      notifier(c).setPain(3);
      final ok = await notifier(c).submit();

      expect(ok, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.touchedPain, isTrue);
      expect(calls.single.touchedMood, isFalse);
      expect(calls.single.touchedNotes, isFalse);
      expect(calls.single.pain, 3);
      expect(
        calls.single.mood,
        2,
        reason:
            'the VALUE still travels to the repository — it is the FLAG '
            'that stops it reaching the wire. Asserting null here would '
            'test the wrong layer and would hide a flag that stopped '
            'working.',
      );
      expect(calls.single.notes, 'stored note');
    });

    test('S-1 — a note the user never touched is never asserted, even when '
        'the seeded note is empty (the empty-controller wipe shape)', () async {
      stubLogDay();
      final c = buildContainer(
        log: cycleDayLogFixture(pain: 5, mood: null, notes: null),
      );
      await openEditor(c);

      notifier(c).setMood(3);
      await notifier(c).submit();

      expect(calls.single.touchedNotes, isFalse);
      expect(calls.single.notes, '');
    });

    test('TOUCHED + null — the flag stays TRUE and the value stays null; the '
        'controller never substitutes 0 (S-4)', () async {
      stubLogDay();
      final c = buildContainer(log: cycleDayLogFixture(pain: 8, mood: 2));
      await openEditor(c);

      // Unreachable from this screen's own scale (`allowClear: false`), but
      // reachable here — and the ONE case a controller-level `?? 0` would
      // change. `setNotes` is what keeps the form submittable.
      notifier(c).setPain(null);
      notifier(c).setNotes('still saving something');
      await notifier(c).submit();

      expect(calls.single.touchedPain, isTrue);
      expect(
        calls.single.pain,
        isNull,
        reason:
            'never `pain ?? 0` — 0 is a real logged "none today" (D-08) and '
            'there is no delete on this endpoint to take it back',
      );
    });

    test('TOUCHED + SET, all three — every flag travels true', () async {
      stubLogDay();
      final c = buildContainer();
      await openEditor(c);

      notifier(c).setPain(0);
      notifier(c).setMood(4);
      notifier(c).setNotes('felt fine');
      await notifier(c).submit();

      expect(calls.single.touchedPain, isTrue);
      expect(calls.single.touchedMood, isTrue);
      expect(calls.single.touchedNotes, isTrue);
      expect(calls.single.pain, 0);
      expect(calls.single.mood, 4);
      expect(calls.single.notes, 'felt fine');
    });

    test('R5 — the write goes to the ROUTE date, and there is no way to '
        'change it: the form carries no date at all', () async {
      stubLogDay();
      final c = buildContainer();
      await openEditor(c);

      notifier(c).setPain(2);
      await notifier(c).submit();

      expect(calls.single.date, date);
    });
  });

  // ---------------------------------------------------------------------------
  // Failure handling (R9)
  // ---------------------------------------------------------------------------

  group('a failed save', () {
    test('preserves every answer intact and keeps the form editable', () async {
      stubLogDay(throws: const NetworkFailure());
      final c = buildContainer(log: cycleDayLogFixture(pain: 8, mood: 2));
      await openEditor(c);

      notifier(c).setPain(3);
      notifier(c).setNotes('typed this');
      final ok = await notifier(c).submit();

      expect(ok, isFalse);
      final form = state(c);
      expect(form.failure, isA<NetworkFailure>());
      expect(form.submitting, isFalse);
      expect(form.pain, 3);
      expect(form.mood, 2);
      expect(form.notes, 'typed this');
      expect(form.touchedPain, isTrue);
      expect(form.touchedNotes, isTrue);
      expect(form.canSubmit, isTrue, reason: 'the retry must be possible');
    });

    test('a non-Failure throw becomes UnknownFailure rather than escaping', () async {
      stubLogDay(throws: StateError('boom'));
      final c = buildContainer();
      await openEditor(c);

      notifier(c).setPain(3);
      final ok = await notifier(c).submit();

      expect(ok, isFalse);
      expect(state(c).failure, isA<UnknownFailure>());
    });

    test('touching a control after a failure clears the banner', () async {
      stubLogDay(throws: const NetworkFailure());
      final c = buildContainer();
      await openEditor(c);

      notifier(c).setPain(3);
      await notifier(c).submit();
      expect(state(c).failure, isNotNull);

      notifier(c).setMood(2);
      expect(state(c).failure, isNull);
    });

    test('a retry re-issues exactly one request', () async {
      stubLogDay(throws: const NetworkFailure());
      final c = buildContainer();
      await openEditor(c);

      notifier(c).setPain(3);
      await notifier(c).submit();
      expect(calls, hasLength(1));

      await notifier(c).submit();
      expect(calls, hasLength(2));
    });

    test('setters are inert while a save is in flight', () async {
      final gate = Completer<CycleDayLogResponse>();
      when(
        () => repo.logDay(
          date: any(named: 'date'),
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          notes: any(named: 'notes'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          touchedNotes: any(named: 'touchedNotes'),
        ),
      ).thenAnswer((_) => gate.future);

      final c = buildContainer();
      await openEditor(c);
      notifier(c).setPain(3);
      final pending = notifier(c).submit();
      await settle();

      expect(state(c).submitting, isTrue);
      notifier(c).setPain(9);
      notifier(c).setMood(1);
      notifier(c).setNotes('typed during the write');
      expect(state(c).pain, 3);
      expect(state(c).mood, isNull);
      expect(state(c).notes, '');

      gate.complete(cycleDayLogFixture());
      await pending;
    });

    test('a second submit() while one is in flight does not double-write', () async {
      final gate = Completer<CycleDayLogResponse>();
      when(
        () => repo.logDay(
          date: any(named: 'date'),
          pain: any(named: 'pain'),
          mood: any(named: 'mood'),
          notes: any(named: 'notes'),
          touchedPain: any(named: 'touchedPain'),
          touchedMood: any(named: 'touchedMood'),
          touchedNotes: any(named: 'touchedNotes'),
        ),
      ).thenAnswer((_) {
        calls.add((
          date: date,
          pain: null,
          mood: null,
          notes: null,
          touchedPain: false,
          touchedMood: false,
          touchedNotes: false,
        ));
        return gate.future;
      });

      final c = buildContainer();
      await openEditor(c);
      notifier(c).setPain(3);
      final first = notifier(c).submit();
      await settle();
      final second = await notifier(c).submit();

      expect(second, isFalse);
      expect(calls, hasLength(1));

      gate.complete(cycleDayLogFixture());
      await first;
    });
  });

  // ---------------------------------------------------------------------------
  // R6 / R7 / R8 — what a SUCCESSFUL save does to the screens around it
  // ---------------------------------------------------------------------------

  group('a successful save', () {
    late _Counter dashboardBuilds;
    late _Counter calendarRefreshes;
    late _Counter calendarBuilds;
    late _Counter dayDetailBuilds;

    setUp(() {
      dashboardBuilds = _Counter();
      calendarRefreshes = _Counter();
      calendarBuilds = _Counter();
      dayDetailBuilds = _Counter();
    });

    ProviderContainer dependents({
      required Set<ProviderListenable<Object?>> watch,
      CycleDayLogResponse? log,
      bool seedDayDetail = true,
    }) {
      final c = ProviderContainer(
        overrides: <Override>[
          cycleRepositoryProvider.overrideWithValue(repo),
          dashboardControllerProvider.overrideWith(
            () => _CountingDashboard(dashboardBuilds),
          ),
          cycleCalendarControllerProvider.overrideWith(
            () => _CountingCalendar(calendarRefreshes, calendarBuilds),
          ),
          if (seedDayDetail)
            dayDetailControllerProvider(date).overrideWith(
              () => _SeededDayDetail(viewWith(log), dayDetailBuilds),
            ),
        ],
      );
      addTearDown(c.dispose);
      for (final provider in watch) {
        c.listen(provider, (_, _) {});
      }
      return c;
    }

    test('the dashboard is invalidated — it renders today\'s own pain and '
        'mood', () async {
      stubLogDay();
      final c = dependents(
        watch: {dashboardControllerProvider, dayDetailControllerProvider(date)},
      );
      await settle();
      expect(dashboardBuilds.value, 1);

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setPain(3);
      expect(await notifier(c).submit(), isTrue);
      await settle();

      expect(dashboardBuilds.value, 2);
    });

    test('R6/R8 — the day view UNDER the sheet ADOPTS the 200 body rather '
        'than being invalidated: the screen the modal sits over must not '
        'drop to a spinner behind the scrim and re-issue two GETs whose '
        'answer the 200 already carries', () async {
      stubLogDay(
        // `day` deliberately DISAGREES with the route date. The client must
        // keep the route's own day: `DayDetailView.date` is documented as
        // "never re-derived from either response", and with a matching
        // fixture the two behaviours would be the same assertion.
        body: cycleDayLogFixture(
          day: Date(2020, 1, 1),
          pain: 3,
          mood: 2,
          notes: 'stored note',
        ),
      );
      final c = dependents(
        watch: {dayDetailControllerProvider(date)},
        log: cycleDayLogFixture(pain: 8, mood: 2, notes: 'stored note'),
      );
      await settle();
      expect(dayDetailBuilds.value, 1);

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setPain(3);
      expect(await notifier(c).submit(), isTrue);
      await settle();

      expect(
        dayDetailBuilds.value,
        1,
        reason: 'adopted, not rebuilt — no second read was issued',
      );
      final view = c.read(dayDetailControllerProvider(date)).value!;
      expect(view.log!.pain, 3, reason: 'the screen behind now shows the '
          'value that was just saved');
      // The rest of the day view survives the swap. Asserted against a
      // NON-EMPTY seeded list on purpose: against an empty one, "left alone"
      // and "wiped" are the same assertion, and a mutant that replaced
      // `current.symptoms` with `const []` inside
      // `DayDetailController.applySavedLog` survived the entire suite until
      // this line was written.
      expect(view.symptoms, hasLength(1));
      expect(view.symptoms.single.symptomCode, 'bloating');
      expect(view.symptomsTotal, 1);
      expect(
        view.date,
        date,
        reason:
            'the ROUTE date, never the echoed `day` on the 200 body (which this '
            'stub sets to 2020-01-01 precisely so the two can be told apart)',
      );
    });

    test('the adopted body is the SERVER\'s stored row, not the form — a '
        'notes-only write repaints the pain the caller never sent', () async {
      stubLogDay(
        body: cycleDayLogFixture(pain: 8, mood: 2, notes: 'edited note'),
      );
      final c = dependents(
        watch: {dayDetailControllerProvider(date)},
        log: cycleDayLogFixture(pain: 8, mood: 2, notes: 'old note'),
      );
      await settle();

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setNotes('edited note');
      await notifier(c).submit();
      await settle();

      final view = c.read(dayDetailControllerProvider(date)).value!;
      expect(view.log!.notes, 'edited note');
      expect(view.log!.pain, 8);
    });

    test('R6 — the FORM is never patched from the 200: a field the user did '
        'not touch stays untouched afterwards, so a second save cannot '
        'assert an echoed value', () async {
      stubLogDay(
        body: cycleDayLogFixture(pain: 8, mood: 4, notes: 'server note'),
      );
      final c = dependents(watch: {dayDetailControllerProvider(date)});
      await settle();

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setNotes('mine');
      await notifier(c).submit();
      await settle();

      final form = state(c);
      expect(form.touchedPain, isFalse);
      expect(form.touchedMood, isFalse);
      expect(
        form.mood,
        isNull,
        reason:
            'the 200 carried mood 4; adopting it here would make an echoed '
            'field indistinguishable from user input on the NEXT save',
      );
    });

    test('a day view that is still LOADING is invalidated instead of '
        'adopted — the in-flight read was issued before this write '
        'committed', () async {
      stubLogDay(body: cycleDayLogFixture(pain: 3));
      final gate = Completer<DayDetailView>();
      final builds = _Counter();
      final c = ProviderContainer(
        overrides: <Override>[
          cycleRepositoryProvider.overrideWithValue(repo),
          dayDetailControllerProvider(
            date,
          ).overrideWith(() => _PendingDayDetail(gate, builds, date)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(dayDetailControllerProvider(date), (_, _) {});
      await settle();
      expect(builds.value, 1);
      expect(c.read(dayDetailControllerProvider(date)).hasValue, isFalse);

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setPain(3);
      await notifier(c).submit();
      await settle();

      expect(
        builds.value,
        2,
        reason: 'no value to adopt into, so the read is re-issued',
      );
      gate.complete(
        DayDetailView(
          date: date,
          log: null,
          symptoms: const [],
          symptomsTotal: 0,
        ),
      );
      await settle();
    });

    test('the calendar is refreshed only when it already exists AND already '
        'has a value — and is never CREATED', () async {
      stubLogDay();
      final c = dependents(
        watch: {dayDetailControllerProvider(date)},
      );
      await settle();

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setPain(3);
      await notifier(c).submit();
      await settle();

      expect(calendarRefreshes.value, 0);
      expect(
        calendarBuilds.value,
        0,
        reason:
            'a bare ref.read would have CREATED it — in production that is '
            'sessionTodayProvider plus three month GETs for a tab nobody '
            'opened',
      );
    });

    test('a calendar that EXISTS but has NOT SETTLED is left alone — the '
        'hasValue half of the guard, which the mutation round caught with no '
        'test behind it. CycleCalendarController.refresh() falls back to '
        'invalidateSelf() when it holds no value, and that snaps the visible '
        'month back to today under a user who had paged away.', () async {
      stubLogDay();
      final gate = Completer<CycleCalendarView>();
      final c = ProviderContainer(
        overrides: <Override>[
          cycleRepositoryProvider.overrideWithValue(repo),
          dashboardControllerProvider.overrideWith(
            () => _CountingDashboard(dashboardBuilds),
          ),
          cycleCalendarControllerProvider.overrideWith(
            () => _PendingCalendar(gate, calendarRefreshes, calendarBuilds),
          ),
          dayDetailControllerProvider(date).overrideWith(
            () => _SeededDayDetail(viewWith(null), dayDetailBuilds),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(dayDetailControllerProvider(date), (_, _) {});
      c.listen(cycleCalendarControllerProvider, (_, _) {});
      await settle();

      expect(c.exists(cycleCalendarControllerProvider), isTrue);
      expect(c.read(cycleCalendarControllerProvider).hasValue, isFalse);
      expect(calendarBuilds.value, 1);

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setPain(3);
      await notifier(c).submit();
      await settle();

      expect(
        calendarRefreshes.value,
        0,
        reason:
            'exists is true here, so only hasValue can stop the refresh — '
            'and it must',
      );

      gate.complete(
        CycleCalendarView(
          visibleMonth: DateTime(2026, 4),
          today: Date(2026, 4, 20),
          phase: null,
          dayByDate: const {},
        ),
      );
      await settle();
    });

    test('an OPEN calendar IS refreshed — a day-log write changes what that '
        'day contains', () async {
      stubLogDay();
      final c = dependents(
        watch: {
          dayDetailControllerProvider(date),
          cycleCalendarControllerProvider,
        },
      );
      await settle();
      expect(calendarBuilds.value, 1);

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setPain(3);
      await notifier(c).submit();
      await settle();

      expect(calendarRefreshes.value, 1);
    });

    test('a day view that was never opened is not created by the refresh', () async {
      stubLogDay();
      final c = dependents(watch: const {}, seedDayDetail: false);

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setPain(3);
      await notifier(c).submit();
      await settle();

      expect(c.exists(dayDetailControllerProvider(date)), isFalse);
    });

    test('leaves the form settled: not submitting, no failure', () async {
      stubLogDay();
      final c = dependents(watch: {dayDetailControllerProvider(date)});
      await settle();

      c.listen(dayLogEditorControllerProvider(date), (_, _) {});
      notifier(c).setPain(3);
      expect(await notifier(c).submit(), isTrue);

      expect(state(c).submitting, isFalse);
      expect(state(c).failure, isNull);
    });
  });
}

/// A calendar controller whose `build()` never settles until [gate] does.
class _PendingCalendar extends CycleCalendarController {
  _PendingCalendar(this.gate, this.refreshes, this.builds);

  final Completer<CycleCalendarView> gate;
  final _Counter refreshes;
  final _Counter builds;

  @override
  Future<CycleCalendarView> build() {
    builds.value++;
    return gate.future;
  }

  @override
  Future<void> refresh() async {
    refreshes.value++;
  }
}

/// A day-detail controller whose `build()` never settles until [gate] does.
class _PendingDayDetail extends DayDetailController {
  _PendingDayDetail(this.gate, this.builds, super.date);

  final Completer<DayDetailView> gate;
  final _Counter builds;

  @override
  Future<DayDetailView> build() {
    builds.value++;
    return gate.future;
  }
}
