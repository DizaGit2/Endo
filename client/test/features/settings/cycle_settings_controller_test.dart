// CycleSettingsController — screen 32's state machine (P4b-T22a).
//
// TDD (RED first). Screen 32 is the ONE write on `/settings/cycle` this phase
// ships, and it is a MERGE: an absent key leaves the stored column alone, and
// there is no way to clear one at all.
//
// The whole file exists to pin two properties.
//
//  1. **Only a field the user actually TOUCHED is sent**, and "touched" is its
//     own explicit state that is never re-derived from whether the value
//     happens to be null. Every assertion below varies the flag and the value
//     INDEPENDENTLY: a suite that only ever supplies "untouched AND null"
//     together cannot tell a `touched` guard from `built_value`'s own
//     omit-nulls serializer, and deleting either would leave it green
//     (P4b-T18's own defect).
//
//  2. **The two sanity warnings are an advisory AFTER a successful save, never
//     a validator.** R-17 is a PO ruling and not a style preference: clinical
//     bounds are estimator-only and NEVER entry blockers, because
//     endometriosis cycles are irregular. So the ordering is pinned in both
//     directions — a value the server will warn about still SAVES, and the
//     note appears only once the 200 carrying it has landed.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/application/cycle_calendar_controller.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/settings/application/cycle_settings_controller.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

class _MockCycleSettingsRepository extends Mock
    implements CycleSettingsRepository {}

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// The arguments one `updateSettings` call actually carried.
typedef _SaveCall = ({
  int? avgCycleLengthDays,
  int? avgPeriodLengthDays,
  String? regularity,
  bool? phasePredictionEnabled,
  bool? autoDetectPeriodStartEnabled,
  bool? showFertilityWindowEnabled,
  bool touchedAvgCycleLengthDays,
  bool touchedAvgPeriodLengthDays,
  bool touchedRegularity,
  bool touchedPhasePredictionEnabled,
  bool touchedAutoDetectPeriodStartEnabled,
  bool touchedShowFertilityWindowEnabled,
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

void main() {
  late _MockCycleSettingsRepository repo;
  late List<_SaveCall> calls;

  /// What the server holds when the screen opens: a saved row, so nothing in
  /// these tests depends on the never-saved defaults.
  CycleSettingsResponse stored({
    int? avgCycleLengthDays = 29,
    int? avgPeriodLengthDays = 5,
    String? regularity = 'somewhat',
    bool? phasePredictionEnabled = true,
    bool? autoDetectPeriodStartEnabled = true,
    bool? showFertilityWindowEnabled = false,
    List<String>? warnings = const <String>[],
  }) {
    return cycleSettingsFixture(
      avgCycleLengthDays: avgCycleLengthDays,
      avgPeriodLengthDays: avgPeriodLengthDays,
      regularity: regularity,
      phasePredictionEnabled: phasePredictionEnabled,
      autoDetectPeriodStartEnabled: autoDetectPeriodStartEnabled,
      showFertilityWindowEnabled: showFertilityWindowEnabled,
      warnings: warnings,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
  }

  void stubRead(CacheResult<CycleSettingsResponse> result) {
    when(() => repo.getSettings()).thenAnswer((_) async => result);
  }

  void stubSave({CycleSettingsResponse? body, Object? throws}) {
    when(
      () => repo.updateSettings(
        avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
        avgPeriodLengthDays: any(named: 'avgPeriodLengthDays'),
        regularity: any(named: 'regularity'),
        phasePredictionEnabled: any(named: 'phasePredictionEnabled'),
        autoDetectPeriodStartEnabled: any(
          named: 'autoDetectPeriodStartEnabled',
        ),
        showFertilityWindowEnabled: any(named: 'showFertilityWindowEnabled'),
        touchedAvgCycleLengthDays: any(named: 'touchedAvgCycleLengthDays'),
        touchedAvgPeriodLengthDays: any(named: 'touchedAvgPeriodLengthDays'),
        touchedRegularity: any(named: 'touchedRegularity'),
        touchedPhasePredictionEnabled: any(
          named: 'touchedPhasePredictionEnabled',
        ),
        touchedAutoDetectPeriodStartEnabled: any(
          named: 'touchedAutoDetectPeriodStartEnabled',
        ),
        touchedShowFertilityWindowEnabled: any(
          named: 'touchedShowFertilityWindowEnabled',
        ),
      ),
    ).thenAnswer((invocation) async {
      final named = invocation.namedArguments;
      calls.add((
        avgCycleLengthDays: named[#avgCycleLengthDays] as int?,
        avgPeriodLengthDays: named[#avgPeriodLengthDays] as int?,
        regularity: named[#regularity] as String?,
        phasePredictionEnabled: named[#phasePredictionEnabled] as bool?,
        autoDetectPeriodStartEnabled:
            named[#autoDetectPeriodStartEnabled] as bool?,
        showFertilityWindowEnabled:
            named[#showFertilityWindowEnabled] as bool?,
        touchedAvgCycleLengthDays: named[#touchedAvgCycleLengthDays] as bool,
        touchedAvgPeriodLengthDays: named[#touchedAvgPeriodLengthDays] as bool,
        touchedRegularity: named[#touchedRegularity] as bool,
        touchedPhasePredictionEnabled:
            named[#touchedPhasePredictionEnabled] as bool,
        touchedAutoDetectPeriodStartEnabled:
            named[#touchedAutoDetectPeriodStartEnabled] as bool,
        touchedShowFertilityWindowEnabled:
            named[#touchedShowFertilityWindowEnabled] as bool,
      ));
      if (throws != null) throw throws;
      return body ?? stored();
    });
  }

  ProviderContainer buildContainer({
    List<Override> extra = const <Override>[],
    Duration? Function(int retryCount, Object error)? retry,
  }) {
    final container = ProviderContainer(
      retry: retry,
      overrides: <Override>[
        cycleSettingsRepositoryProvider.overrideWithValue(repo),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    // The controller is `autoDispose`, and a bare `container.read` leaves no
    // subscriber: riverpod tears the element down between awaits and the next
    // read silently gets a FRESH controller in `AsyncLoading`. The screen
    // holds it with a `ref.watch`; this listener is that, in a container.
    container.listen<AsyncValue<CycleSettingsForm>>(
      cycleSettingsControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return container;
  }

  /// The settled form, after the read has landed.
  Future<CycleSettingsForm> settled(ProviderContainer container) async {
    return container.read(cycleSettingsControllerProvider.future);
  }

  CycleSettingsController notifier(ProviderContainer container) =>
      container.read(cycleSettingsControllerProvider.notifier);

  CycleSettingsForm current(ProviderContainer container) =>
      container.read(cycleSettingsControllerProvider).requireValue;

  setUp(() {
    repo = _MockCycleSettingsRepository();
    calls = <_SaveCall>[];
    stubRead(Fresh(stored()));
    stubSave();
  });

  // ── the read ──────────────────────────────────────────────────────────────

  group('build', () {
    test('seeds every field from the 200 and marks NOTHING touched', () async {
      final container = buildContainer();

      final form = await settled(container);

      expect(form.avgCycleLengthDays, 29);
      expect(form.avgPeriodLengthDays, 5);
      expect(form.regularity, 'somewhat');
      expect(form.phasePredictionEnabled, isTrue);
      expect(form.autoDetectPeriodStartEnabled, isTrue);
      expect(form.showFertilityWindowEnabled, isFalse);
      expect(form.touchedAvgCycleLengthDays, isFalse);
      expect(form.touchedAvgPeriodLengthDays, isFalse);
      expect(form.touchedRegularity, isFalse);
      expect(form.touchedPhasePredictionEnabled, isFalse);
      expect(form.touchedAutoDetectPeriodStartEnabled, isFalse);
      expect(form.touchedShowFertilityWindowEnabled, isFalse);
    });

    test(
      'a user with NO settings row seeds from the documented defaults and '
      'leaves the period length UNSET — onboarding never collects it, so a '
      'seeded number here would be a self-report the user never made',
      () async {
        stubRead(Fresh(cycleSettingsFixture()));
        final container = buildContainer();

        final form = await settled(container);

        expect(form.avgCycleLengthDays, 28);
        expect(form.avgPeriodLengthDays, isNull);
        expect(form.regularity, 'somewhat');
      },
    );

    test(
      'a STALE read seeds the form all the same — under MERGE an untouched '
      'field is omitted, so a stale seed can never be written back and its '
      'freshness stops mattering rather than having to be established',
      () async {
        stubRead(Stale(stored(avgCycleLengthDays: 33)));
        final container = buildContainer();

        final form = await settled(container);

        expect(form.avgCycleLengthDays, 33);
      },
    );

    test(
      'an unreachable read surfaces as AsyncError, never as an empty form — '
      'a form with no seed would show the user settings the server never sent',
      () async {
        stubRead(
          const NetworkRequired<CycleSettingsResponse>(NetworkFailure()),
        );
        // Retry disabled so this pins the TERMINAL state — the one the
        // screen's error/retry body renders. Left at riverpod 3.3.2's default
        // (`ProviderContainer.defaultRetry`) the element re-runs `build` up to
        // ten times with exponential backoff before it settles on
        // `AsyncError`, and until then the state is
        // `AsyncLoading(error: …, retrying: true)`, which `AsyncValue.when`
        // routes to `loading`. That is a pre-existing, app-wide property of
        // every `AsyncNotifier` screen here (a `Failure` is neither an `Error`
        // nor a `ProviderException`, so it is retried) and is recorded in the
        // T22a report rather than changed by this task.
        final container = buildContainer(retry: (_, _) => null);
        await settle();

        final value = container.read(cycleSettingsControllerProvider);
        expect(value, isA<AsyncError<CycleSettingsForm>>());
        expect(
          (value as AsyncError<CycleSettingsForm>).error,
          isA<NetworkFailure>(),
        );
      },
    );

    test(
      'the warnings the READ carries are not adopted — R3 makes the note an '
      'advisory after a SUCCESSFUL SAVE, and nothing has been saved yet',
      () async {
        stubRead(
          Fresh(
            stored(
              avgCycleLengthDays: 200,
              warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
            ),
          ),
        );
        final container = buildContainer();

        final form = await settled(container);

        expect(form.warnings, isEmpty);
      },
    );
  });

  // ── the block, and the empty-body 400 it prevents ─────────────────────────

  group('blockReason', () {
    test(
      'a freshly-opened form is blocked with a rendered reason: nothing was '
      'touched, so the request would be `{}` and the server answers that with '
      'a 400 keyed `request`',
      () async {
        final container = buildContainer();

        final form = await settled(container);

        expect(form.blockReason, kCycleSettingsNothingChangedMessage);
        expect(form.canSubmit, isFalse);
      },
    );

    test('any one touched field unblocks it', () async {
      final container = buildContainer();
      await settled(container);

      notifier(container).setShowFertilityWindowEnabled(true);

      expect(current(container).blockReason, isNull);
      expect(current(container).canSubmit, isTrue);
    });

    test(
      'TOUCHED but holding null is still blocked — the serializer drops a '
      'null member, so such a save would put `{}` on the wire',
      () async {
        final container = buildContainer();
        await settled(container);

        notifier(container).setAvgCycleLengthDays(null);

        expect(current(container).touchedAvgCycleLengthDays, isTrue);
        expect(current(container).avgCycleLengthDays, isNull);
        expect(
          current(container).blockReason,
          kCycleSettingsNothingChangedMessage,
        );
      },
    );

    test(
      'UNTOUCHED but holding values is blocked — the seeded form is exactly '
      'this state, and it is the case a block derived from nullability would '
      'get wrong (every value is non-null and none of it may be asserted)',
      () async {
        final container = buildContainer();

        final form = await settled(container);

        expect(form.avgCycleLengthDays, isNotNull);
        expect(form.regularity, isNotNull);
        expect(form.canSubmit, isFalse);
      },
    );

    test('a blocked submit issues NO request at all', () async {
      final container = buildContainer();
      await settled(container);

      final saved = await notifier(container).submit();

      expect(saved, isFalse);
      expect(calls, isEmpty);
      verifyNever(
        () => repo.updateSettings(
          avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
          avgPeriodLengthDays: any(named: 'avgPeriodLengthDays'),
          regularity: any(named: 'regularity'),
          phasePredictionEnabled: any(named: 'phasePredictionEnabled'),
          autoDetectPeriodStartEnabled: any(
            named: 'autoDetectPeriodStartEnabled',
          ),
          showFertilityWindowEnabled: any(named: 'showFertilityWindowEnabled'),
          touchedAvgCycleLengthDays: any(named: 'touchedAvgCycleLengthDays'),
          touchedAvgPeriodLengthDays: any(named: 'touchedAvgPeriodLengthDays'),
          touchedRegularity: any(named: 'touchedRegularity'),
          touchedPhasePredictionEnabled: any(
            named: 'touchedPhasePredictionEnabled',
          ),
          touchedAutoDetectPeriodStartEnabled: any(
            named: 'touchedAutoDetectPeriodStartEnabled',
          ),
          touchedShowFertilityWindowEnabled: any(
            named: 'touchedShowFertilityWindowEnabled',
          ),
        ),
      );
    });
  });

  // ── what a save carries ───────────────────────────────────────────────────

  group('submit', () {
    test(
      'only the touched field travels TOUCHED; the other five travel with '
      'their seeded values and touched FALSE, which is what stops the '
      'repository from sending them',
      () async {
        final container = buildContainer();
        await settled(container);

        notifier(container).setRegularity('irregular');
        final saved = await notifier(container).submit();

        expect(saved, isTrue);
        expect(calls, hasLength(1));
        final call = calls.single;
        expect(call.regularity, 'irregular');
        expect(call.touchedRegularity, isTrue);
        // The seeded values are still carried — the repository, not the
        // controller, is where the flag decides. Both halves matter: a
        // controller that nulled them out would hide a missing guard.
        expect(call.avgCycleLengthDays, 29);
        expect(call.avgPeriodLengthDays, 5);
        expect(call.phasePredictionEnabled, isTrue);
        expect(call.touchedAvgCycleLengthDays, isFalse);
        expect(call.touchedAvgPeriodLengthDays, isFalse);
        expect(call.touchedPhasePredictionEnabled, isFalse);
        expect(call.touchedAutoDetectPeriodStartEnabled, isFalse);
        expect(call.touchedShowFertilityWindowEnabled, isFalse);
      },
    );

    test(
      'R2 — the period length can be set from this controller, including on '
      'a row that had none: this is the only surface in the app that can',
      () async {
        stubRead(Fresh(stored(avgPeriodLengthDays: null)));
        final container = buildContainer();
        await settled(container);

        notifier(container).setAvgPeriodLengthDays(6);
        await notifier(container).submit();

        expect(calls.single.avgPeriodLengthDays, 6);
        expect(calls.single.touchedAvgPeriodLengthDays, isTrue);
      },
    );

    test(
      'turning a prediction toggle OFF sends `false`, not an omission — the '
      'server merges with `is { }`, so a deliberate off is a real datum',
      () async {
        final container = buildContainer();
        await settled(container);

        notifier(container).setPhasePredictionEnabled(false);
        await notifier(container).submit();

        expect(calls.single.phasePredictionEnabled, isFalse);
        expect(calls.single.touchedPhasePredictionEnabled, isTrue);
      },
    );

    test(
      'R-17 — a value the server WILL warn about does not block the save. '
      'The clinical bounds are estimator-only and never entry blockers, '
      'because endometriosis cycles are irregular; 200 days is far outside '
      'the sanity band and is submitted without argument',
      () async {
        final container = buildContainer();
        await settled(container);

        notifier(container).setAvgCycleLengthDays(200);

        expect(current(container).canSubmit, isTrue);
        expect(current(container).blockReason, isNull);

        final saved = await notifier(container).submit();

        expect(saved, isTrue);
        expect(calls.single.avgCycleLengthDays, 200);
      },
    );

    test('a second submit while one is in flight issues no second request', () async {
      final release = Completer<CycleSettingsResponse>();
      when(
        () => repo.updateSettings(
          avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
          avgPeriodLengthDays: any(named: 'avgPeriodLengthDays'),
          regularity: any(named: 'regularity'),
          phasePredictionEnabled: any(named: 'phasePredictionEnabled'),
          autoDetectPeriodStartEnabled: any(
            named: 'autoDetectPeriodStartEnabled',
          ),
          showFertilityWindowEnabled: any(named: 'showFertilityWindowEnabled'),
          touchedAvgCycleLengthDays: any(named: 'touchedAvgCycleLengthDays'),
          touchedAvgPeriodLengthDays: any(named: 'touchedAvgPeriodLengthDays'),
          touchedRegularity: any(named: 'touchedRegularity'),
          touchedPhasePredictionEnabled: any(
            named: 'touchedPhasePredictionEnabled',
          ),
          touchedAutoDetectPeriodStartEnabled: any(
            named: 'touchedAutoDetectPeriodStartEnabled',
          ),
          touchedShowFertilityWindowEnabled: any(
            named: 'touchedShowFertilityWindowEnabled',
          ),
        ),
      ).thenAnswer((_) {
        calls.add((
          avgCycleLengthDays: null,
          avgPeriodLengthDays: null,
          regularity: null,
          phasePredictionEnabled: null,
          autoDetectPeriodStartEnabled: null,
          showFertilityWindowEnabled: null,
          touchedAvgCycleLengthDays: false,
          touchedAvgPeriodLengthDays: false,
          touchedRegularity: false,
          touchedPhasePredictionEnabled: false,
          touchedAutoDetectPeriodStartEnabled: false,
          touchedShowFertilityWindowEnabled: false,
        ));
        return release.future;
      });

      final container = buildContainer();
      await settled(container);
      notifier(container).setRegularity('regular');

      final first = notifier(container).submit();
      await settle();
      expect(current(container).submitting, isTrue);

      final second = await notifier(container).submit();
      expect(second, isFalse);
      expect(calls, hasLength(1));

      release.complete(stored());
      await first;
    });

    test('every setter is inert while a save is in flight', () async {
      final release = Completer<CycleSettingsResponse>();
      stubSave();
      when(
        () => repo.updateSettings(
          avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
          avgPeriodLengthDays: any(named: 'avgPeriodLengthDays'),
          regularity: any(named: 'regularity'),
          phasePredictionEnabled: any(named: 'phasePredictionEnabled'),
          autoDetectPeriodStartEnabled: any(
            named: 'autoDetectPeriodStartEnabled',
          ),
          showFertilityWindowEnabled: any(named: 'showFertilityWindowEnabled'),
          touchedAvgCycleLengthDays: any(named: 'touchedAvgCycleLengthDays'),
          touchedAvgPeriodLengthDays: any(named: 'touchedAvgPeriodLengthDays'),
          touchedRegularity: any(named: 'touchedRegularity'),
          touchedPhasePredictionEnabled: any(
            named: 'touchedPhasePredictionEnabled',
          ),
          touchedAutoDetectPeriodStartEnabled: any(
            named: 'touchedAutoDetectPeriodStartEnabled',
          ),
          touchedShowFertilityWindowEnabled: any(
            named: 'touchedShowFertilityWindowEnabled',
          ),
        ),
      ).thenAnswer((_) => release.future);

      final container = buildContainer();
      await settled(container);
      notifier(container).setRegularity('regular');
      final first = notifier(container).submit();
      await settle();

      notifier(container).setAvgCycleLengthDays(31);
      notifier(container).setAvgPeriodLengthDays(9);
      notifier(container).setRegularity('irregular');
      notifier(container).setPhasePredictionEnabled(false);
      notifier(container).setAutoDetectPeriodStartEnabled(false);
      notifier(container).setShowFertilityWindowEnabled(true);

      expect(current(container).avgCycleLengthDays, 29);
      expect(current(container).regularity, 'regular');
      expect(current(container).touchedAvgCycleLengthDays, isFalse);

      release.complete(stored());
      await first;
    });
  });

  // ── R3: the advisory, and its ordering ────────────────────────────────────

  group('sanity warnings', () {
    test(
      'a warning-bearing 200 puts the note on the form ONLY after the save '
      'has succeeded — the save comes first, the note second',
      () async {
        // **Only the IN-FLIGHT states are collected, and this is the fix for a
        // false-green the mutation round found.** The first version recorded
        // every observed state and asserted `observed.first` was empty — but
        // `observed.first` is the state the SETTER pushed, before `submit()`
        // was even called, so it is empty whatever `submit()` does. A mutant
        // attaching the warnings before the request SURVIVED the whole suite.
        // Sampling `submitting == true` is what makes the two outcomes look
        // different, and the `isNotEmpty` assertion below is what stops the
        // whole check going vacuous if that state is never observed.
        final duringFlight = <List<String>>[];
        stubSave(
          body: stored(
            avgCycleLengthDays: 200,
            warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
          ),
        );
        final container = buildContainer();
        await settled(container);
        container.listen<AsyncValue<CycleSettingsForm>>(
          cycleSettingsControllerProvider,
          (_, next) {
            final value = next.value;
            if (value != null && value.submitting) {
              duringFlight.add(value.warnings);
            }
          },
        );

        notifier(container).setAvgCycleLengthDays(200);
        expect(current(container).warnings, isEmpty);

        final saved = await notifier(container).submit();

        expect(saved, isTrue);
        expect(current(container).warnings, <String>[
          'avg_cycle_length_out_of_sanity_band',
        ]);
        expect(
          duringFlight,
          isNotEmpty,
          reason: 'the in-flight state must actually have been observed, or '
              'the assertion below is vacuous',
        );
        // The note cannot precede the 200 that produced it.
        for (final warnings in duringFlight) {
          expect(warnings, isEmpty);
        }
      },
    );

    test('a clean 200 leaves the form with no advisory at all', () async {
      stubSave(body: stored(warnings: const <String>[]));
      final container = buildContainer();
      await settled(container);

      notifier(container).setRegularity('regular');
      await notifier(container).submit();

      expect(current(container).warnings, isEmpty);
    });

    test(
      'a 200 whose `warnings` member is absent altogether is read as "no '
      'warnings", never as null — the two must not render differently',
      () async {
        stubSave(body: stored(warnings: null));
        final container = buildContainer();
        await settled(container);

        notifier(container).setRegularity('regular');
        await notifier(container).submit();

        expect(current(container).warnings, isEmpty);
      },
    );

    test('the note is dropped the moment the user changes anything', () async {
      stubSave(
        body: stored(
          avgCycleLengthDays: 200,
          warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
        ),
      );
      final container = buildContainer();
      await settled(container);

      notifier(container).setAvgCycleLengthDays(200);
      await notifier(container).submit();
      expect(current(container).warnings, isNotEmpty);

      notifier(container).setAvgCycleLengthDays(30);

      expect(current(container).warnings, isEmpty);
    });

    test('a REJECTED save renders no advisory', () async {
      stubSave(throws: const NetworkFailure());
      final container = buildContainer();
      await settled(container);

      notifier(container).setAvgCycleLengthDays(200);
      final saved = await notifier(container).submit();

      expect(saved, isFalse);
      expect(current(container).warnings, isEmpty);
    });
  });

  // ── what a successful save does to the form ───────────────────────────────

  group('after a successful save', () {
    test(
      'the 200 becomes the new SEED — every value adopted, every touched flag '
      'back to false — so a second Save is blocked and cannot echo the body '
      'back at the endpoint',
      () async {
        stubSave(body: stored(avgCycleLengthDays: 31, regularity: 'regular'));
        final container = buildContainer();
        await settled(container);

        notifier(container).setAvgCycleLengthDays(31);
        await notifier(container).submit();

        final form = current(container);
        expect(form.avgCycleLengthDays, 31);
        expect(form.regularity, 'regular');
        expect(form.touchedAvgCycleLengthDays, isFalse);
        expect(form.touchedRegularity, isFalse);
        expect(form.canSubmit, isFalse);

        final again = await notifier(container).submit();
        expect(again, isFalse);
        expect(calls, hasLength(1));
      },
    );

    test('submitting is over and no failure is left behind', () async {
      final container = buildContainer();
      await settled(container);

      notifier(container).setRegularity('regular');
      await notifier(container).submit();

      expect(current(container).submitting, isFalse);
      expect(current(container).failure, isNull);
    });
  });

  // ── R6: failure preserves the form ────────────────────────────────────────

  group('a rejected save', () {
    test(
      'preserves every answer and every touched flag, so the retry sends the '
      'identical request',
      () async {
        stubSave(throws: const NetworkFailure());
        final container = buildContainer();
        await settled(container);

        notifier(container).setAvgCycleLengthDays(31);
        notifier(container).setRegularity('irregular');
        notifier(container).setShowFertilityWindowEnabled(true);

        final saved = await notifier(container).submit();

        expect(saved, isFalse);
        final form = current(container);
        expect(form.avgCycleLengthDays, 31);
        expect(form.regularity, 'irregular');
        expect(form.showFertilityWindowEnabled, isTrue);
        expect(form.touchedAvgCycleLengthDays, isTrue);
        expect(form.touchedRegularity, isTrue);
        expect(form.touchedShowFertilityWindowEnabled, isTrue);
        expect(form.submitting, isFalse);
        expect(form.failure, isA<NetworkFailure>());
        expect(form.canSubmit, isTrue);
      },
    );

    test('the retry re-issues exactly the same six arguments', () async {
      stubSave(throws: const NetworkFailure());
      final container = buildContainer();
      await settled(container);

      notifier(container).setAvgPeriodLengthDays(7);
      await notifier(container).submit();

      stubSave();
      final saved = await notifier(container).submit();

      expect(saved, isTrue);
      expect(calls, hasLength(2));
      expect(calls.first.avgPeriodLengthDays, 7);
      expect(calls.last.avgPeriodLengthDays, 7);
      expect(calls.last.touchedAvgPeriodLengthDays, isTrue);
    });

    test('a non-Failure throw is reported as an UnknownFailure', () async {
      stubSave(throws: StateError('boom'));
      final container = buildContainer();
      await settled(container);

      notifier(container).setRegularity('regular');
      await notifier(container).submit();

      expect(current(container).failure, isA<UnknownFailure>());
    });

    test('the failure clears the moment the user changes anything', () async {
      stubSave(throws: const NetworkFailure());
      final container = buildContainer();
      await settled(container);

      notifier(container).setRegularity('regular');
      await notifier(container).submit();
      expect(current(container).failure, isNotNull);

      notifier(container).setRegularity('irregular');

      expect(current(container).failure, isNull);
    });
  });

  // ── R7: what a save refreshes, and what it deliberately does not ──────────

  group('dependents', () {
    test(
      'a successful save refreshes NEITHER the dashboard NOR the calendar: '
      'measured, both render their phase state off `CycleCalendarResponse` '
      'and neither reads `/settings/cycle` at all, so invalidating them '
      'would re-issue three GETs for data that cannot have changed',
      () async {
        final dashboardBuilds = _Counter();
        final calendarBuilds = _Counter();
        final calendarRefreshes = _Counter();
        final container = buildContainer(
          extra: <Override>[
            dashboardControllerProvider.overrideWith(
              () => _CountingDashboard(dashboardBuilds),
            ),
            cycleCalendarControllerProvider.overrideWith(
              () => _CountingCalendar(calendarRefreshes, calendarBuilds),
            ),
          ],
        );

        // Both alive, SUBSCRIBED and settled BEFORE the save, so an
        // invalidation would genuinely show up as a rebuild. Without the
        // listeners riverpod would dispose them between awaits and the
        // counters would move for a reason that has nothing to do with the
        // save.
        container.listen<AsyncValue<CacheResult<DashboardView>>>(
          dashboardControllerProvider,
          (_, _) {},
          fireImmediately: true,
        );
        container.listen<AsyncValue<CycleCalendarView>>(
          cycleCalendarControllerProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await container.read(dashboardControllerProvider.future);
        await container.read(cycleCalendarControllerProvider.future);
        expect(dashboardBuilds.value, 1);
        expect(calendarBuilds.value, 1);

        await settled(container);
        notifier(container).setRegularity('regular');
        await notifier(container).submit();
        await settle();

        expect(dashboardBuilds.value, 1);
        expect(calendarBuilds.value, 1);
        expect(calendarRefreshes.value, 0);
      },
    );
  });
}
