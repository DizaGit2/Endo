// SymptomFormController — screen 12's I/O-doing half (P4b-T20a).
//
// TDD (RED first). `SymptomForm`'s pure logic (blockReason, error lookups)
// is covered in `symptom_form_test.dart`; `assembleSymptomBatch`'s pure
// assembly rules are covered in `symptom_batch_assembler_test.dart`. This
// file is the STATE MACHINE: what a setter does, when `submit()` may fire,
// R12's `sessionTodayProvider` read, and R9/R10's failure handling — the
// `QuickCheckinController` precedent (`quick_checkin_controller_test.dart`),
// applied to this screen's shape.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/time/server_today.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/application/symptom_form_controller.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockSymptomsRepository extends Mock implements SymptomsRepository {}

class _MockServerTodayRepository extends Mock
    implements ServerTodayRepository {}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _MockSymptomsRepository repo;
  late _MockServerTodayRepository todayRepo;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(<SymptomEntryDraft>[]);
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  setUp(() {
    repo = _MockSymptomsRepository();
    todayRepo = _MockServerTodayRepository();
    when(todayRepo.today).thenAnswer((_) async => Date(2026, 4, 20));
  });

  ProviderContainer buildContainer() {
    final c = ProviderContainer(
      overrides: <Override>[
        symptomsRepositoryProvider.overrideWithValue(repo),
        serverTodayRepositoryProvider.overrideWithValue(todayRepo),
      ],
    );
    addTearDown(c.dispose);
    // autoDispose — a bare read disposes as soon as the awaited gap lets the
    // scheduled teardown run; keep it alive the way a screen's `ref.watch`
    // would (`quick_checkin_controller_test.dart`'s own precedent).
    c.listen(symptomFormControllerProvider, (_, _) {});
    return c;
  }

  SymptomFormController notifier(ProviderContainer c) =>
      c.read(symptomFormControllerProvider.notifier);

  SymptomForm state(ProviderContainer c) =>
      c.read(symptomFormControllerProvider);

  void stubCreateBatchSuccess() {
    when(
      () => repo.createBatch(
        entries: any(named: 'entries'),
        fallbackDay: any(named: 'fallbackDay'),
      ),
    ).thenAnswer((_) async => const <SymptomResponse>[]);
  }

  // ---------------------------------------------------------------------------
  // R11 — no prefill
  // ---------------------------------------------------------------------------

  test('build() reads nothing — the form opens empty, never seeded from any '
      'read', () {
    container = buildContainer();
    final form = state(container);

    expect(form.region, isNull);
    expect(form.painIntensity, isNull);
    expect(form.relatedIntensities, isEmpty);
    expect(form.canSubmit, isFalse);
    verifyZeroInteractions(repo);
    verifyNever(todayRepo.today);
  });

  // ---------------------------------------------------------------------------
  // Setters
  // ---------------------------------------------------------------------------

  group('setters', () {
    test('setRegion sets the LOCATION chip', () {
      container = buildContainer();
      notifier(container).setRegion('lower_abdomen');
      expect(state(container).region, 'lower_abdomen');
    });

    test('togglePainType adds then removes a TYPE chip', () {
      container = buildContainer();
      notifier(container).togglePainType('cramping');
      expect(state(container).painTypes, {'cramping'});

      notifier(container).togglePainType('cramping');
      expect(state(container).painTypes, isEmpty);
    });

    test('toggleTrigger adds then removes a TRIGGERS chip', () {
      container = buildContainer();
      notifier(container).toggleTrigger('stress');
      expect(state(container).triggers, {'stress'});

      notifier(container).toggleTrigger('stress');
      expect(state(container).triggers, isEmpty);
    });

    test('setPainIntensity(0) is preserved as a real datum, not falsy', () {
      container = buildContainer();
      notifier(container).setPainIntensity(0);
      expect(state(container).painIntensity, 0);
      expect(state(container).canSubmit, isTrue);
    });

    test('setPainIntensity(null) — the clear gesture — returns to "not '
        'set"', () {
      container = buildContainer();
      notifier(container).setPainIntensity(6);
      notifier(container).setPainIntensity(null);
      expect(state(container).painIntensity, isNull);
    });

    test('setNotes sets free text', () {
      container = buildContainer();
      notifier(container).setNotes('worse today');
      expect(state(container).notes, 'worse today');
    });

    test('setBodyMapPoints replaces the T21 seam field wholesale', () {
      container = buildContainer();
      const point = SymptomEntryDraft(
        symptomCode: null,
        intensity: 4,
        region: 'legs',
        side: 'front',
        occurredAt: null,
      );
      notifier(container).setBodyMapPoints([point]);
      expect(state(container).bodyMapPoints, [point]);
    });

    test('a setter is a no-op while submitting', () async {
      container = buildContainer();
      final release = Completer<List<SymptomResponse>>();
      when(
        () => repo.createBatch(
          entries: any(named: 'entries'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer((_) => release.future);

      notifier(container).setPainIntensity(5);
      final submitFuture = notifier(container).submit();
      await settle();
      expect(state(container).submitting, isTrue);

      notifier(container).setPainIntensity(9);
      expect(
        state(container).painIntensity,
        5,
        reason:
            'a control mutating mid-flight would race the request that '
            'is already on the wire',
      );

      release.complete(const <SymptomResponse>[]);
      await submitFuture;
    });
  });

  // ---------------------------------------------------------------------------
  // R5 — deselecting a RELATED chip discards its intensity
  // ---------------------------------------------------------------------------

  group('R5 — deselect discards intensity', () {
    test('toggle on, set an intensity, toggle off, toggle on again — the '
        'intensity comes back null, not the previous value', () {
      container = buildContainer();
      final n = notifier(container);

      n.toggleRelated('bloating');
      n.setRelatedIntensity('bloating', 7);
      expect(state(container).relatedIntensities['bloating'], 7);

      n.toggleRelated('bloating'); // deselect
      expect(
        state(container).relatedIntensities.containsKey('bloating'),
        isFalse,
      );

      n.toggleRelated('bloating'); // reselect
      expect(
        state(container).relatedIntensities.containsKey('bloating'),
        isTrue,
      );
      expect(
        state(container).relatedIntensities['bloating'],
        isNull,
        reason:
            're-selecting must never silently restore a number from an '
            'earlier interaction',
      );
    });

    test('setRelatedIntensity on a code that is not selected is a no-op', () {
      container = buildContainer();
      notifier(container).setRelatedIntensity('bloating', 5);
      expect(
        state(container).relatedIntensities.containsKey('bloating'),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // R9 — setters clear a prior failure and its retained draft list
  // ---------------------------------------------------------------------------

  group('R9 — a new selection change clears the bound row errors', () {
    test(
      'a setter after a rejected submit clears failure/submittedDrafts',
      () async {
        container = buildContainer();
        when(
          () => repo.createBatch(
            entries: any(named: 'entries'),
            fallbackDay: any(named: 'fallbackDay'),
          ),
        ).thenAnswer(
          (_) async => throw const ValidationFailure(
            fields: {
              'entries[0].intensity': ['too high'],
            },
          ),
        );

        notifier(container).setPainIntensity(11);
        await notifier(container).submit();
        expect(state(container).failure, isNotNull);
        expect(state(container).submittedDrafts, isNotNull);

        notifier(container).setPainIntensity(5);

        final form = state(container);
        expect(form.failure, isNull);
        expect(form.submittedDrafts, isNull);
        expect(form.submittedPainIndex, isNull);
        expect(form.painRowError('intensity'), isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // submit() — guards
  // ---------------------------------------------------------------------------

  group('submit() guards', () {
    test('a no-op when blockReason is non-null (nothing selected)', () async {
      container = buildContainer();
      final ok = await notifier(container).submit();

      expect(ok, isFalse);
      verifyZeroInteractions(repo);
      verifyNever(todayRepo.today);
    });

    test('a no-op while already submitting', () async {
      container = buildContainer();
      final release = Completer<List<SymptomResponse>>();
      when(
        () => repo.createBatch(
          entries: any(named: 'entries'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer((_) => release.future);

      notifier(container).setPainIntensity(4);
      final first = notifier(container).submit();
      await settle();
      expect(state(container).submitting, isTrue);

      final second = await notifier(container).submit();
      expect(second, isFalse);

      release.complete(const <SymptomResponse>[]);
      await first;
      verify(
        () => repo.createBatch(
          entries: any(named: 'entries'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // R12 — fallbackDay from sessionTodayProvider, never the device clock,
  // never .toUtc()
  // ---------------------------------------------------------------------------

  group('R12 — fallbackDay', () {
    test('submit() reads sessionTodayProvider and passes '
        'today.toDateTime() as fallbackDay, unmodified', () async {
      container = buildContainer();
      stubCreateBatchSuccess();

      notifier(container).setPainIntensity(5);
      await notifier(container).submit();

      final captured = verify(
        () => repo.createBatch(
          entries: any(named: 'entries'),
          fallbackDay: captureAny(named: 'fallbackDay'),
        ),
      ).captured;
      final fallbackDay = captured.single as DateTime;

      expect(fallbackDay, DateTime(2026, 4, 20));
      expect(
        fallbackDay.isUtc,
        isFalse,
        reason:
            '.toUtc() on Date.toDateTime() is a same-value no-op in '
            'every test but a real off-by-one-day bug for a positive-offset '
            'device in production (symptoms_repository.dart\'s own '
            'documented M-2 regression) — this must never be added here',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // submit() sends the assembled batch
  // ---------------------------------------------------------------------------

  test('submit() sends exactly assembleSymptomBatch\'s own output for the '
      'current form', () async {
    container = buildContainer();
    stubCreateBatchSuccess();

    notifier(container).setPainIntensity(5);
    notifier(container).setRegion('pelvis');
    notifier(container).toggleRelated('bloating');
    notifier(container).setRelatedIntensity('bloating', 3);
    await notifier(container).submit();

    final captured = verify(
      () => repo.createBatch(
        entries: captureAny(named: 'entries'),
        fallbackDay: any(named: 'fallbackDay'),
      ),
    ).captured;
    final entries = captured.single as List<SymptomEntryDraft>;

    expect(entries, hasLength(2));
    expect(entries[0].symptomCode, isNull);
    expect(entries[0].intensity, 5);
    expect(entries[0].region, 'pelvis');
    expect(entries[1].symptomCode, 'bloating');
    expect(entries[1].intensity, 3);
  });

  // ---------------------------------------------------------------------------
  // R9 — error binding integration
  // ---------------------------------------------------------------------------

  group('R9 — error binding integration', () {
    test('a rejected submit retains the submitted drafts and pain index, '
        'and painRowError/relatedRowError resolve against them', () async {
      container = buildContainer();
      when(
        () => repo.createBatch(
          entries: any(named: 'entries'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer(
        (_) async => throw const ValidationFailure(
          fields: {
            'entries[1].intensity': ['must be between 0 and 10'],
          },
        ),
      );

      notifier(container).setPainIntensity(5); // index 0
      notifier(container).toggleRelated('bloating');
      notifier(container).setRelatedIntensity('bloating', 11); // index 1

      final ok = await notifier(container).submit();
      expect(ok, isFalse);

      final form = state(container);
      expect(
        form.relatedRowError('bloating', 'intensity'),
        'must be between 0 and 10',
      );
      expect(form.painRowError('intensity'), isNull);
    });

    test('a RELATED-only rejected submit records submittedPainIndex as '
        'null (no pain row was sent)', () async {
      container = buildContainer();
      when(
        () => repo.createBatch(
          entries: any(named: 'entries'),
          fallbackDay: any(named: 'fallbackDay'),
        ),
      ).thenAnswer(
        (_) async => throw const ValidationFailure(
          fields: {
            'entries[0].intensity': ['x'],
          },
        ),
      );

      notifier(container).toggleRelated('bloating');
      notifier(container).setRelatedIntensity('bloating', 11);
      await notifier(container).submit();

      expect(state(container).submittedPainIndex, isNull);
      expect(state(container).painRowError('intensity'), isNull);
      expect(state(container).relatedRowError('bloating', 'intensity'), 'x');
    });
  });

  // ---------------------------------------------------------------------------
  // R10 — on ANY failure, state is preserved intact
  // ---------------------------------------------------------------------------

  group('R10 — a rejected submit preserves the form untouched', () {
    test(
      'every selection field is unchanged after a rejected submit',
      () async {
        container = buildContainer();
        when(
          () => repo.createBatch(
            entries: any(named: 'entries'),
            fallbackDay: any(named: 'fallbackDay'),
          ),
        ).thenAnswer((_) async => throw const NetworkFailure());

        notifier(container).setPainIntensity(6);
        notifier(container).setRegion('pelvis');
        notifier(container).togglePainType('cramping');
        notifier(container).toggleTrigger('stress');
        notifier(container).toggleRelated('bloating');
        notifier(container).setRelatedIntensity('bloating', 2);
        notifier(container).setNotes('still hurts');

        final ok = await notifier(container).submit();
        expect(ok, isFalse);

        final form = state(container);
        expect(form.painIntensity, 6);
        expect(form.region, 'pelvis');
        expect(form.painTypes, {'cramping'});
        expect(form.triggers, {'stress'});
        expect(form.relatedIntensities, {'bloating': 2});
        expect(form.notes, 'still hurts');
        expect(form.submitting, isFalse);
        expect(form.failure, isA<NetworkFailure>());
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Non-Failure exceptions
  // ---------------------------------------------------------------------------

  test('a non-Failure exception becomes UnknownFailure, never an unhandled '
      'rejection', () async {
    container = buildContainer();
    when(
      () => repo.createBatch(
        entries: any(named: 'entries'),
        fallbackDay: any(named: 'fallbackDay'),
      ),
    ).thenAnswer((_) async => throw StateError('box closed'));

    notifier(container).setPainIntensity(4);
    final ok = await notifier(container).submit();

    expect(ok, isFalse);
    expect(state(container).failure, isA<UnknownFailure>());
  });

  // ---------------------------------------------------------------------------
  // Success
  // ---------------------------------------------------------------------------

  test('a successful submit clears submitting and any prior failure', () async {
    container = buildContainer();
    stubCreateBatchSuccess();

    notifier(container).setPainIntensity(4);
    final ok = await notifier(container).submit();

    expect(ok, isTrue);
    final form = state(container);
    expect(form.submitting, isFalse);
    expect(form.failure, isNull);
  });

  // ---------------------------------------------------------------------------
  // Mounted guard (the quick_checkin_controller.dart precedent)
  // ---------------------------------------------------------------------------

  test('a container disposed mid-write settles without throwing', () async {
    final localRepo = _MockSymptomsRepository();
    final localToday = _MockServerTodayRepository();
    when(localToday.today).thenAnswer((_) async => Date(2026, 4, 20));
    final release = Completer<List<SymptomResponse>>();
    when(
      () => localRepo.createBatch(
        entries: any(named: 'entries'),
        fallbackDay: any(named: 'fallbackDay'),
      ),
    ).thenAnswer((_) => release.future);

    final localContainer = ProviderContainer(
      overrides: <Override>[
        symptomsRepositoryProvider.overrideWithValue(localRepo),
        serverTodayRepositoryProvider.overrideWithValue(localToday),
      ],
    );
    localContainer.listen(symptomFormControllerProvider, (_, _) {});

    localContainer
        .read(symptomFormControllerProvider.notifier)
        .setPainIntensity(4);
    final submitFuture = localContainer
        .read(symptomFormControllerProvider.notifier)
        .submit();
    await settle();

    localContainer.dispose();
    release.complete(const <SymptomResponse>[]);

    Object? thrown;
    await submitFuture.then<void>((_) {}, onError: (Object e) => thrown = e);
    expect(thrown, isNull);
  });
}
