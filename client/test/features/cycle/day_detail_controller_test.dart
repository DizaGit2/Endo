// DayDetailController — screen 11's state (P4b-T16, READ SURFACE ONLY).
//
// TDD (RED first). The controller's whole job is combining TWO independent
// reads — `GET /cycle/day/{date}` and `GET /symptoms?from&to` — into one
// honest `AsyncValue`. What is worth pinning: both reads are actually
// issued (for the RIGHT date), a failure in EITHER one fails the WHOLE
// screen (never a partial render), and `total` falling back to the page
// length never manufactures a false truncation notice.

import 'package:built_collection/built_collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/symptom_list_response.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/day_detail_controller.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _MockCycleRepository extends Mock implements CycleRepository {}

class _MockSymptomsRepository extends Mock implements SymptomsRepository {}

void main() {
  late _MockCycleRepository cycleRepo;
  late _MockSymptomsRepository symptomsRepo;
  late ProviderContainer container;

  final date = DateTime(2026, 4, 20);

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  setUp(() {
    cycleRepo = _MockCycleRepository();
    symptomsRepo = _MockSymptomsRepository();
  });

  ProviderContainer buildContainer() {
    final c = ProviderContainer(
      overrides: <Override>[
        cycleRepositoryProvider.overrideWithValue(cycleRepo),
        symptomsRepositoryProvider.overrideWithValue(symptomsRepo),
      ],
    );
    addTearDown(c.dispose);
    // autoDispose.family — a bare read disposes as it returns, so a
    // subscription is required, matching how a screen's ref.watch behaves.
    c.listen(dayDetailControllerProvider(date), (_, _) {});
    return c;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('the two reads', () {
    test('both getDay methods are called with the SAME date the screen was '
        'opened for', () async {
      when(() => cycleRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(cycleDayFixture(date: Date(2026, 4, 20))),
      );
      when(
        () => symptomsRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(symptomListResponseFixture()));

      container = buildContainer();
      await settle();

      verify(() => cycleRepo.getDay(date)).called(1);
      verify(() => symptomsRepo.getDay(date)).called(1);
    });

    test('combines log:null with an empty symptoms list into one settled view '
        '— the common case', () async {
      when(
        () => cycleRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(cycleDayFixture()));
      when(() => symptomsRepo.getDay(any())).thenAnswer(
        (_) async =>
            Fresh(symptomListResponseFixture(items: const [], total: 0)),
      );

      container = buildContainer();
      await settle();

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.log, isNull);
      expect(view.symptoms, isEmpty);
      expect(view.symptomsTotal, 0);
    });

    test(
      'carries the day log and the symptom rows through unmodified',
      () async {
        when(() => cycleRepo.getDay(any())).thenAnswer(
          (_) async =>
              Fresh(cycleDayFixture(log: cycleDayLogFixture(pain: 4, mood: 2))),
        );
        when(() => symptomsRepo.getDay(any())).thenAnswer(
          (_) async => Fresh(
            symptomListResponseFixture(
              items: [
                symptomResponseFixture(symptomCode: 'bloating', intensity: 5),
              ],
            ),
          ),
        );

        container = buildContainer();
        await settle();

        final view = container.read(dayDetailControllerProvider(date)).value!;
        expect(view.log?.pain, 4);
        expect(view.log?.mood, 2);
        expect(view.symptoms, hasLength(1));
        expect(view.symptoms.single.symptomCode, 'bloating');
        expect(view.symptoms.single.intensity, 5);
      },
    );

    test('a Stale day read and a Fresh symptoms read both still combine — '
        'Stale unwraps to its value like Fresh does', () async {
      when(
        () => cycleRepo.getDay(any()),
      ).thenAnswer((_) async => Stale(cycleDayFixture()));
      when(
        () => symptomsRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(symptomListResponseFixture()));

      container = buildContainer();
      await settle();

      expect(
        container.read(dayDetailControllerProvider(date)),
        isA<AsyncData<DayDetailView>>(),
      );
    });
  });

  group('either read failing fails the whole screen', () {
    test('NetworkRequired from the DAY read surfaces AsyncError, not a '
        'partial view', () async {
      when(() => cycleRepo.getDay(any())).thenAnswer(
        (_) async => const NetworkRequired(NetworkFailure('offline')),
      );
      when(
        () => symptomsRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(symptomListResponseFixture()));

      container = buildContainer();
      await settle();

      expect(
        container.read(dayDetailControllerProvider(date)),
        isA<AsyncError<DayDetailView>>(),
      );
    });

    test('NetworkRequired from the SYMPTOMS read surfaces AsyncError too — '
        'the day half succeeding does not paper over it', () async {
      when(
        () => cycleRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(cycleDayFixture()));
      when(() => symptomsRepo.getDay(any())).thenAnswer(
        (_) async => const NetworkRequired(NetworkFailure('offline')),
      );

      container = buildContainer();
      await settle();

      expect(
        container.read(dayDetailControllerProvider(date)),
        isA<AsyncError<DayDetailView>>(),
      );
    });
  });

  group('symptomsTotal', () {
    test('total greater than the returned page is carried through, visibly '
        '— never silently clamped to the page length', () async {
      when(
        () => cycleRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(cycleDayFixture()));
      when(() => symptomsRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          symptomListResponseFixture(
            items: List.generate(3, (i) => symptomResponseFixture(id: 'r$i')),
            total: 7,
          ),
        ),
      );

      container = buildContainer();
      await settle();

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.symptoms, hasLength(3));
      expect(view.symptomsTotal, 7);
    });

    test('a null total falls back to the page length, never to 0', () async {
      when(
        () => cycleRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(cycleDayFixture()));
      // fix round 1, I-3: NOT `symptomListResponseFixture(total: null)` —
      // the fixture (`fixtures.dart`: `..total = total ?? rows.length`)
      // fills a null argument with the page length itself, so that call
      // never produces a genuinely-null `total` and this test could not
      // have failed no matter what `?? items.length` was mutated to.
      // Built directly here, leaving `.total` genuinely unset, to reach
      // the branch the fixture's own default-filling makes unreachable.
      when(() => symptomsRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          SymptomListResponse(
            (b) => b
              ..items = ListBuilder<SymptomResponse>([symptomResponseFixture()])
              ..limit = 100
              ..offset = 0,
          ),
        ),
      );

      container = buildContainer();
      await settle();

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.symptomsTotal, 1);
    });
  });

  // -------------------------------------------------------------------------
  // events (P4b-T16c) — the read the period editor has no data without
  // -------------------------------------------------------------------------

  group('events', () {
    test('carries the day\'s cycle events through unmodified, in the order '
        'the server sent them', () async {
      when(() => cycleRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          cycleDayFixture(
            events: <CycleEventResponse>[
              cycleEventFixture(
                id: 'evt-end',
                kind: 'period_end',
                flowIntensity: 2,
              ),
              cycleEventFixture(
                id: 'evt-start',
                kind: 'period_start',
                flowIntensity: 4,
                notes: 'heavy first day',
              ),
            ],
          ),
        ),
      );
      when(
        () => symptomsRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(symptomListResponseFixture()));

      container = buildContainer();
      await settle();

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.events.map((e) => e.id), <String>['evt-end', 'evt-start']);
      expect(view.events.first.flowIntensity, 2);
      expect(view.events.last.notes, 'heavy first day');
    });

    test('a day with no events becomes an EMPTY list, never null — the '
        'section\'s empty state is a list length, not a null check', () async {
      when(
        () => cycleRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(cycleDayFixture()));
      when(
        () => symptomsRepo.getDay(any()),
      ).thenAnswer((_) async => Fresh(symptomListResponseFixture()));

      container = buildContainer();
      await settle();

      expect(
        container.read(dayDetailControllerProvider(date)).value!.events,
        isEmpty,
      );
    });
  });

  // -------------------------------------------------------------------------
  // applySavedEvent / applyDeletedEvent (P4b-T16c)
  //
  // Every fixture below seeds a NON-EMPTY symptom list and a non-null log on
  // purpose: T16b's mutation round found that "the adoption left the other
  // members alone" and "the adoption wiped them" are the SAME assertion when
  // those members are empty, and a mutant replacing them with `const []`
  // survived the whole suite.
  // -------------------------------------------------------------------------

  group('applySavedEvent', () {
    Future<DayDetailController> seeded(
      List<CycleEventResponse> events,
    ) async {
      when(() => cycleRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          cycleDayFixture(
            log: cycleDayLogFixture(pain: 4, mood: 2, notes: 'day note'),
            events: events,
          ),
        ),
      );
      when(() => symptomsRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          symptomListResponseFixture(
            items: [symptomResponseFixture(symptomCode: 'bloating')],
          ),
        ),
      );
      container = buildContainer();
      await settle();
      return container.read(dayDetailControllerProvider(date).notifier);
    }

    test('REPLACES the event with the same id, in place, leaving the rest of '
        'the view alone', () async {
      final notifier = await seeded(<CycleEventResponse>[
        cycleEventFixture(id: 'evt-1', kind: 'period_start', flowIntensity: 1),
        cycleEventFixture(id: 'evt-2', kind: 'spotting'),
      ]);

      notifier.applySavedEvent(
        cycleEventFixture(
          id: 'evt-1',
          kind: 'period_start',
          flowIntensity: 4,
          notes: 'saved note',
        ),
      );

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.events.map((e) => e.id), <String>['evt-1', 'evt-2']);
      expect(view.events.first.flowIntensity, 4);
      expect(view.events.first.notes, 'saved note');
      expect(view.log?.pain, 4, reason: 'the day log is a different row');
      expect(view.symptoms, hasLength(1));
      expect(view.symptoms.single.symptomCode, 'bloating');
      expect(view.symptomsTotal, 1);
      expect(view.date, date);
    });

    test('APPENDS an event whose id is not on the day yet — a first period '
        'event on a day that had none', () async {
      final notifier = await seeded(const <CycleEventResponse>[]);

      notifier.applySavedEvent(
        cycleEventFixture(id: 'evt-new', kind: 'period_start'),
      );

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.events.map((e) => e.id), <String>['evt-new']);
      expect(view.symptoms, hasLength(1));
    });

    test('does NOT re-derive the view\'s date from the saved event', () async {
      final notifier = await seeded(const <CycleEventResponse>[]);

      notifier.applySavedEvent(
        cycleEventFixture(id: 'evt-new', occurredOn: Date(2020, 1, 1)),
      );

      expect(
        container.read(dayDetailControllerProvider(date)).value!.date,
        date,
        reason:
            'the route\'s own :date, never re-derived from a response body',
      );
    });
  });

  group('applyDeletedEvent', () {
    test('removes exactly the deleted id and leaves every other member of '
        'the view intact', () async {
      when(() => cycleRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          cycleDayFixture(
            log: cycleDayLogFixture(pain: 4, mood: 2),
            events: <CycleEventResponse>[
              cycleEventFixture(id: 'evt-1', kind: 'period_start'),
              cycleEventFixture(id: 'evt-2', kind: 'spotting'),
            ],
          ),
        ),
      );
      when(() => symptomsRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          symptomListResponseFixture(
            items: [symptomResponseFixture(symptomCode: 'bloating')],
          ),
        ),
      );
      container = buildContainer();
      await settle();

      container
          .read(dayDetailControllerProvider(date).notifier)
          .applyDeletedEvent('evt-1');

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.events.map((e) => e.id), <String>['evt-2']);
      expect(view.log?.pain, 4);
      expect(view.symptoms, hasLength(1));
      expect(view.symptomsTotal, 1);
    });
  });

  group('applySavedLog (P4b-T16b) keeps the events P4b-T16c added', () {
    test('a day-log save leaves the day\'s cycle events exactly where they '
        'were — different table, different endpoint', () async {
      when(() => cycleRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          cycleDayFixture(
            events: <CycleEventResponse>[
              cycleEventFixture(id: 'evt-1', kind: 'period_start'),
            ],
          ),
        ),
      );
      when(() => symptomsRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(symptomListResponseFixture()),
      );
      container = buildContainer();
      await settle();

      container
          .read(dayDetailControllerProvider(date).notifier)
          .applySavedLog(cycleDayLogFixture(pain: 9, mood: 1));

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.log?.pain, 9);
      expect(
        view.events.map((e) => e.id),
        <String>['evt-1'],
        reason:
            'a `POST /cycle/day/{date}` cannot create, change or remove a '
            'cycle_events row',
      );
    });
  });
}
