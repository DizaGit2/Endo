// DayDetailController — screen 11's state (P4b-T16, READ SURFACE ONLY).
//
// TDD (RED first). The controller's whole job is combining TWO independent
// reads — `GET /cycle/day/{date}` and `GET /symptoms?from&to` — into one
// honest `AsyncValue`. What is worth pinning: both reads are actually
// issued (for the RIGHT date), a failure in EITHER one fails the WHOLE
// screen (never a partial render), and `total` falling back to the page
// length never manufactures a false truncation notice.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
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
      when(() => symptomsRepo.getDay(any())).thenAnswer(
        (_) async => Fresh(
          symptomListResponseFixture(
            items: [symptomResponseFixture()],
            total: null,
          ),
        ),
      );

      container = buildContainer();
      await settle();

      final view = container.read(dayDetailControllerProvider(date)).value!;
      expect(view.symptomsTotal, 1);
    });
  });
}
