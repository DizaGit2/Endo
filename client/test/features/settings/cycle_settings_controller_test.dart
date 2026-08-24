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
//  2. **The two sanity warnings are an advisory, and NEVER a blocker.** R-17
//     is a PO ruling and not a style preference: clinical bounds are
//     estimator-only and NEVER entry blockers, because endometriosis cycles
//     are irregular. So the ordering is pinned in both directions — a value
//     the server will warn about still SAVES, and the note produced BY a save
//     appears only once the 200 carrying it has landed.
//
//     Since T22a's fix round 1 the codes are also adopted from the READ, so
//     the hint renders on LOAD: the server computes them on the GET for that
//     purpose, and dropping them made the hint unreachable for the one user it
//     exists for — someone whose value went out of band in an earlier session,
//     who sees nothing on open and cannot re-save an unchanged form. Both
//     halves are pinned here: it appears on load, AND it still blocks nothing.

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
    // The pause triple (P4b-T22b). Defaulted to the ordinary never-paused row,
    // so every T22a test above is unchanged. `trackingPaused` and
    // `pauseReason` are supplied INDEPENDENTLY on purpose — the pair
    // `(false, 'pregnancy')` is a resumed user, which the server produces by
    // design and which R2 exists for.
    bool? trackingPaused = false,
    String? pauseReason,
  }) {
    return cycleSettingsFixture(
      avgCycleLengthDays: avgCycleLengthDays,
      avgPeriodLengthDays: avgPeriodLengthDays,
      regularity: regularity,
      phasePredictionEnabled: phasePredictionEnabled,
      autoDetectPeriodStartEnabled: autoDetectPeriodStartEnabled,
      showFertilityWindowEnabled: showFertilityWindowEnabled,
      trackingPaused: trackingPaused,
      pauseReason: pauseReason,
      phasesUnavailable:
          (trackingPaused ?? false) || !(phasePredictionEnabled ?? false),
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
        showFertilityWindowEnabled: named[#showFertilityWindowEnabled] as bool?,
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

    test('the warnings the READ carries ARE adopted — the hint renders on LOAD '
        'and not only after a save, which is the only way it can reach the user '
        'whose bad value was stored in an earlier session', () async {
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

      expect(form.warnings, <String>['avg_cycle_length_out_of_sanity_band']);

      // Advisory, never a blocker: adopting the codes changes nothing about
      // what the form will let the user do. The block that IS in force here
      // is the empty-body one — nothing has been touched yet — and it says
      // so in those words rather than anything about the number.
      expect(form.blockReason, kCycleSettingsNothingChangedMessage);
    });

    test('a read whose `warnings` member is ABSENT seeds an empty list, never '
        'null — "no warnings" and "the server said nothing" must not render '
        'differently', () async {
      stubRead(Fresh(stored(warnings: null)));
      final container = buildContainer();

      final form = await settled(container);

      expect(form.warnings, isEmpty);
    });

    test('a hint adopted on LOAD is dropped the moment the user changes '
        'something — it describes the STORED values, and stops being true about '
        'the ones on screen', () async {
      stubRead(
        Fresh(
          stored(
            avgCycleLengthDays: 200,
            warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
          ),
        ),
      );
      final container = buildContainer();
      await settled(container);

      notifier(container).setAvgCycleLengthDays(29);

      expect(current(container).warnings, isEmpty);
    });

    test(
      'a form carrying a LOAD warning still submits: the hint is advisory, so '
      'the save it does not block goes out with the touched field on it '
      '(R-17)',
      () async {
        stubRead(
          Fresh(
            stored(
              avgCycleLengthDays: 200,
              warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
            ),
          ),
        );
        stubSave(body: stored(avgCycleLengthDays: 300));
        final container = buildContainer();
        await settled(container);

        notifier(container).setAvgCycleLengthDays(300);
        expect(current(container).blockReason, isNull);

        expect(await notifier(container).submit(), isTrue);
        expect(calls, hasLength(1));
        expect(calls.single.avgCycleLengthDays, 300);
      },
    );
  });

  // ── the block, and the empty-body 400 it prevents ─────────────────────────

  group('blockReason', () {
    test('a freshly-opened form is blocked with a rendered reason: nothing was '
        'touched, so the request would be `{}` and the server answers that with '
        'a 400 keyed `request`', () async {
      final container = buildContainer();

      final form = await settled(container);

      expect(form.blockReason, kCycleSettingsNothingChangedMessage);
      expect(form.canSubmit, isFalse);
    });

    test('any one touched field unblocks it', () async {
      final container = buildContainer();
      await settled(container);

      notifier(container).setShowFertilityWindowEnabled(true);

      expect(current(container).blockReason, isNull);
      expect(current(container).canSubmit, isTrue);
    });

    test('TOUCHED but holding null is still blocked — the serializer drops a '
        'null member, so such a save would put `{}` on the wire', () async {
      final container = buildContainer();
      await settled(container);

      notifier(container).setAvgCycleLengthDays(null);

      expect(current(container).touchedAvgCycleLengthDays, isTrue);
      expect(current(container).avgCycleLengthDays, isNull);
      expect(
        current(container).blockReason,
        kCycleSettingsNothingChangedMessage,
      );
    });

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
    test('only the touched field travels TOUCHED; the other five travel with '
        'their seeded values and touched FALSE, which is what stops the '
        'repository from sending them', () async {
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
    });

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

    test('R-17 — a value the server WILL warn about does not block the save. '
        'The clinical bounds are estimator-only and never entry blockers, '
        'because endometriosis cycles are irregular; 200 days is far outside '
        'the sanity band and is submitted without argument', () async {
      final container = buildContainer();
      await settled(container);

      notifier(container).setAvgCycleLengthDays(200);

      expect(current(container).canSubmit, isTrue);
      expect(current(container).blockReason, isNull);

      final saved = await notifier(container).submit();

      expect(saved, isTrue);
      expect(calls.single.avgCycleLengthDays, 200);
    });

    test(
      'a second submit while one is in flight issues no second request',
      () async {
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
            showFertilityWindowEnabled: any(
              named: 'showFertilityWindowEnabled',
            ),
            touchedAvgCycleLengthDays: any(named: 'touchedAvgCycleLengthDays'),
            touchedAvgPeriodLengthDays: any(
              named: 'touchedAvgPeriodLengthDays',
            ),
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
      },
    );

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
    test('a warning-bearing 200 puts the note on the form ONLY after the save '
        'has succeeded — the save comes first, the note second', () async {
      // Still true with warnings adopted on the READ too, and for a
      // structural reason rather than a lucky fixture: a form that can
      // submit has had a setter called, every setter goes through `_write`,
      // and `_write` clears the warnings. So the in-flight states below are
      // warning-free no matter what the read carried.

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
        reason:
            'the in-flight state must actually have been observed, or '
            'the assertion below is vacuous',
      );
      // The note cannot precede the 200 that produced it.
      for (final warnings in duringFlight) {
        expect(warnings, isEmpty);
      }
    });

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

  // ── the C-12 pause sub-flow (P4b-T22b) ────────────────────────────────────
  //
  // Two properties this group exists for, and both have a shape that would
  // otherwise pass unnoticed.
  //
  //  1. **R2 — "is this user paused" is `trackingPaused`, and NEVER
  //     `pauseReason != null`.** The server preserves the reason across a
  //     resume ON PURPOSE, so screen 32 can pre-select it next time:
  //     `CycleSettingsResponse.PauseReason`'s own doc says *"there is
  //     deliberately no CHECK tying it to TrackingPaused"*, and
  //     `ReconcilePauseAsync`'s resume arm leaves the column alone. A client
  //     that read the reason as the state would show a resumed user as paused
  //     FOREVER — and no test that only ever supplies the two together could
  //     tell. Every case below therefore varies them INDEPENDENTLY, and the
  //     pair `(trackingPaused: false, pauseReason: 'pregnancy')` — a real,
  //     ordinary, resumed user — is asserted directly.
  //
  //  2. **R1 — resume is unconditional for EVERY reason, pregnancy
  //     included.** C-12: *"resume is user-controlled and always available for
  //     every pause reason"*. The pause and resume cases are parameterised
  //     over the whole vocabulary so a sixth member cannot be added untested.

  group('the pause sub-flow', () {
    /// The five C-12 wire codes, written out rather than read off the app's
    /// own enum: comparing the controller's vocabulary to the app's would pass
    /// for any pair of values as long as both moved together.
    const wireReasons = <String>[
      'pregnancy',
      'hormonal_suppression',
      'surgical',
      'menopause',
      'other',
    ];

    late List<String> pauseCalls;
    late int resumeCalls;

    void stubPause({CycleSettingsResponse? body, Object? throws}) {
      when(() => repo.pauseTracking(reason: any(named: 'reason'))).thenAnswer((
        invocation,
      ) async {
        final reason = invocation.namedArguments[#reason] as String;
        pauseCalls.add(reason);
        if (throws != null) throw throws;
        return body ?? stored(trackingPaused: true, pauseReason: reason);
      });
    }

    void stubResume({CycleSettingsResponse? body, Object? throws}) {
      when(repo.resumeTracking).thenAnswer((_) async {
        resumeCalls++;
        if (throws != null) throw throws;
        // The DEFAULT is the honest one: a resume answers `trackingPaused:
        // false` with the reason STILL SET.
        return body ?? stored(trackingPaused: false, pauseReason: 'pregnancy');
      });
    }

    setUp(() {
      pauseCalls = <String>[];
      resumeCalls = 0;
      stubPause();
      stubResume();
    });

    // -- R2: the state is the flag ------------------------------------------

    test(
      'R2 — a RESUMED user is NOT paused, though their response still carries '
      'the last reason. Reading `pauseReason != null` as "is paused" would '
      'show them as paused forever',
      () async {
        stubRead(
          Fresh(stored(trackingPaused: false, pauseReason: 'pregnancy')),
        );
        final container = buildContainer();

        final form = await settled(container);

        expect(form.trackingPaused, isFalse);
        expect(
          form.pauseReason,
          'pregnancy',
          reason: 'the remembered reason survives a resume, by design',
        );
        // …and it is used for what the server says it is for: a
        // pre-selection, so the card opens on the reason this user last chose.
        expect(form.selectedPauseReason, 'pregnancy');
        expect(form.pauseBlockReason, isNull);
      },
    );

    test('a paused seed reads paused', () async {
      stubRead(Fresh(stored(trackingPaused: true, pauseReason: 'surgical')));
      final container = buildContainer();

      final form = await settled(container);

      expect(form.trackingPaused, isTrue);
      expect(form.pauseReason, 'surgical');
    });

    test(
      'a body with NO `trackingPaused` reads as not paused, never as a third '
      'state',
      () async {
        stubRead(Fresh(stored(trackingPaused: null, pauseReason: 'other')));
        final container = buildContainer();

        final form = await settled(container);

        expect(form.trackingPaused, isFalse);
      },
    );

    // -- R1: five reasons in, five reasons out ------------------------------

    for (final reason in wireReasons) {
      test('pauses with `$reason`', () async {
        stubRead(Fresh(stored()));
        final container = buildContainer();
        await settled(container);

        notifier(container).selectPauseReason(reason);
        expect(current(container).pauseBlockReason, isNull);
        final ok = await notifier(container).pause();

        expect(ok, isTrue);
        expect(pauseCalls, <String>[reason]);
        expect(current(container).trackingPaused, isTrue);
        expect(current(container).pauseReason, reason);
      });

      test('resumes from `$reason` — unconditionally, with no gate and no '
          'question asked (C-12: "resume is user-controlled and always '
          'available for every pause reason", pregnancy included)', () async {
        stubRead(Fresh(stored(trackingPaused: true, pauseReason: reason)));
        stubResume(body: stored(trackingPaused: false, pauseReason: reason));
        final container = buildContainer();
        final opened = await settled(container);

        expect(
          opened.pauseBlockReason,
          isNull,
          reason: 'nothing may block a resume, for any reason',
        );
        final ok = await notifier(container).resume();

        expect(ok, isTrue);
        expect(resumeCalls, 1);
        expect(current(container).trackingPaused, isFalse);
        expect(
          current(container).pauseReason,
          reason,
          reason:
              'the server preserves it; the client must not invent a '
              'clear the endpoint has no way to express',
        );
      });
    }

    test('R2, end to end — resuming leaves the reason SET and the form still '
        'reads RESUMED. This is the exact state that would render as "paused '
        'forever" under a `pauseReason != null` gate', () async {
      stubRead(Fresh(stored(trackingPaused: true, pauseReason: 'pregnancy')));
      stubResume(body: stored(trackingPaused: false, pauseReason: 'pregnancy'));
      final container = buildContainer();
      await settled(container);
      expect(current(container).trackingPaused, isTrue);

      await notifier(container).resume();

      final form = current(container);
      expect(form.trackingPaused, isFalse);
      expect(form.pauseReason, 'pregnancy');
      expect(form.selectedPauseReason, 'pregnancy');
      expect(form.pauseBlockReason, isNull);
    });

    // -- R3: the reason rides with the pause, and only with the pause -------

    test(
      'pause() is BLOCKED until a reason is named — with a stated reason and '
      'NO request. The server requires one on the transition into paused, and '
      'a remembered reason is a pre-selection rather than consent',
      () async {
        stubRead(Fresh(stored()));
        final container = buildContainer();
        final form = await settled(container);

        expect(form.selectedPauseReason, isNull);
        expect(form.pauseBlockReason, kCycleSettingsChooseReasonMessage);
        expect(form.canTogglePause, isFalse);

        final ok = await notifier(container).pause();

        expect(ok, isFalse);
        expect(pauseCalls, isEmpty);
      },
    );

    test('the empty-body guard belongs to the SETTINGS save alone — a pause '
        'needs nothing touched. `Validate`\'s emptiness test spans all NINE '
        'members, so a pause-only body names a field', () async {
      stubRead(Fresh(stored(trackingPaused: false, pauseReason: 'menopause')));
      final container = buildContainer();
      final form = await settled(container);

      // Nothing touched: the SAVE is blocked…
      expect(form.blockReason, kCycleSettingsNothingChangedMessage);
      expect(await notifier(container).submit(), isFalse);
      expect(calls, isEmpty);

      // …and the PAUSE is not.
      expect(form.pauseBlockReason, isNull);
      expect(await notifier(container).pause(), isTrue);
      expect(pauseCalls, <String>['menopause']);
    });

    test('selectPauseReason is a no-op while PAUSED', () async {
      stubRead(Fresh(stored(trackingPaused: true, pauseReason: 'surgical')));
      final container = buildContainer();
      await settled(container);

      notifier(container).selectPauseReason('other');

      expect(current(container).selectedPauseReason, 'surgical');
    });

    // -- what a pause 200 is allowed to change ------------------------------

    test('a successful pause adopts ONLY the pause state — every touched '
        'settings edit and every flag survives it, so a pause can never discard '
        'an answer the user has typed but not yet saved', () async {
      stubRead(Fresh(stored(avgCycleLengthDays: 29)));
      stubPause(
        body: stored(
          // The server\'s own values, deliberately different from the ones
          // the user is holding.
          avgCycleLengthDays: 28,
          regularity: 'irregular',
          trackingPaused: true,
          pauseReason: 'other',
        ),
      );
      final container = buildContainer();
      await settled(container);

      notifier(container).setAvgCycleLengthDays(45);
      notifier(container).selectPauseReason('other');
      await notifier(container).pause();

      final form = current(container);
      expect(form.trackingPaused, isTrue);
      expect(form.avgCycleLengthDays, 45);
      expect(form.touchedAvgCycleLengthDays, isTrue);
      expect(form.regularity, 'somewhat');
      expect(form.blockReason, isNull);

      // …and the pending save still goes out with exactly what was touched.
      await notifier(container).submit();
      expect(calls.single.avgCycleLengthDays, 45);
      expect(calls.single.touchedAvgCycleLengthDays, isTrue);
      expect(calls.single.touchedRegularity, isFalse);
    });

    test('the 200 is the truth about the pause fields even when it DISAGREES '
        'with the client: `pauseReason` is a server-owned column another '
        'surface can move, so both the memory and the pre-selection come from '
        'the response rather than from what this screen last sent', () async {
      // Every other case here echoes back the reason the client just chose,
      // which makes the adoption look redundant — measured: dropping it left
      // the suite green (T22b mutation m21). This is the case that tells the
      // two apart.
      stubRead(Fresh(stored(trackingPaused: true, pauseReason: 'surgical')));
      stubResume(body: stored(trackingPaused: false, pauseReason: 'menopause'));
      final container = buildContainer();
      final opened = await settled(container);
      expect(opened.selectedPauseReason, 'surgical');

      await notifier(container).resume();

      expect(current(container).pauseReason, 'menopause');
      expect(current(container).selectedPauseReason, 'menopause');
    });

    test(
      'a pause 200 does NOT adopt the response warnings — they describe the '
      'STORED values, and the user may be holding edits that made them stale',
      () async {
        stubRead(Fresh(stored(avgCycleLengthDays: 200)));
        stubPause(
          body: stored(
            avgCycleLengthDays: 200,
            trackingPaused: true,
            pauseReason: 'other',
            warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
          ),
        );
        final container = buildContainer();
        await settled(container);

        notifier(container).setAvgCycleLengthDays(29);
        expect(current(container).warnings, isEmpty);
        notifier(container).selectPauseReason('other');
        await notifier(container).pause();

        expect(current(container).warnings, isEmpty);
      },
    );

    test(
      'a successful SETTINGS save carries the pause card\'s pending selection '
      'across — the save concerned none of it, and re-seeding it from the '
      'response would silently discard a chip the user had already tapped',
      () async {
        stubRead(Fresh(stored(pauseReason: 'pregnancy')));
        final container = buildContainer();
        await settled(container);

        notifier(container).selectPauseReason('menopause');
        notifier(container).setRegularity('regular');
        await notifier(container).submit();

        expect(current(container).selectedPauseReason, 'menopause');
      },
    );

    // -- failure, retry, and the one-message invariant ----------------------

    test('a failed pause preserves the selection and records a PAUSE failure; '
        'retrying sends the identical request', () async {
      stubRead(Fresh(stored()));
      stubPause(throws: const NetworkFailure('offline'));
      final container = buildContainer();
      await settled(container);

      notifier(container).selectPauseReason('surgical');
      final ok = await notifier(container).pause();

      expect(ok, isFalse);
      final failed = current(container);
      expect(failed.pauseFailure, isA<NetworkFailure>());
      expect(failed.failure, isNull);
      expect(failed.pausing, isFalse);
      expect(failed.trackingPaused, isFalse);
      expect(failed.selectedPauseReason, 'surgical');

      stubPause();
      await notifier(container).pause();

      expect(pauseCalls, <String>['surgical', 'surgical']);
      expect(current(container).pauseFailure, isNull);
      expect(current(container).trackingPaused, isTrue);
    });

    test('a failed resume leaves the user PAUSED and says so', () async {
      stubRead(Fresh(stored(trackingPaused: true, pauseReason: 'other')));
      stubResume(throws: const NetworkFailure('offline'));
      final container = buildContainer();
      await settled(container);

      final ok = await notifier(container).resume();

      expect(ok, isFalse);
      expect(current(container).trackingPaused, isTrue);
      expect(current(container).pauseFailure, isA<NetworkFailure>());
    });

    test(
      'at most ONE failure is ever on the form: starting either attempt '
      'clears both. Two simultaneous "this did not work" banners would be two '
      'explanations for one screen, and two controls both labelled Try again',
      () async {
        // The REMEMBERED reason pre-selects the chip, which is what makes this
        // test able to fail at all. Its first version reached the pause by
        // calling `selectPauseReason` between the two attempts — and every
        // setter goes through `_write`, which clears `failure` itself. So the
        // settings banner was always already gone by the time `pause()` ran,
        // and dropping `clearFailure` from the pause path left the whole suite
        // GREEN (T22b mutation m8). An assertion evaluated where the two
        // outcomes look identical: this phase's signature defect, found in the
        // test written to prevent it. Here nothing is touched between the
        // failed save and the failed pause, so only the pause path can clear
        // the settings banner.
        stubRead(
          Fresh(stored(trackingPaused: false, pauseReason: 'menopause')),
        );
        stubSave(throws: const NetworkFailure('offline'));
        final container = buildContainer();
        final opened = await settled(container);
        expect(opened.selectedPauseReason, 'menopause');

        notifier(container).setRegularity('regular');
        await notifier(container).submit();
        expect(current(container).failure, isA<NetworkFailure>());
        expect(current(container).pauseFailure, isNull);

        stubPause(throws: const ServerFailure('boom'));
        await notifier(container).pause();
        expect(current(container).pauseFailure, isA<ServerFailure>());
        expect(
          current(container).failure,
          isNull,
          reason: 'the settings banner was cleared when the pause started',
        );

        // …and the mirror direction, including its own failure arm: a FAILED
        // settings save clears the pause banner too. Both arms rebuild from a
        // pre-write snapshot that still holds the other message, so each one
        // has to drop it explicitly — which is the defect this test caught.
        // Nothing is touched here either: the form still holds the regularity
        // edit from above, so `submit()` is reachable without a setter call.
        stubSave(throws: const NetworkFailure('offline'));
        await notifier(container).submit();
        expect(current(container).failure, isA<NetworkFailure>());
        expect(current(container).pauseFailure, isNull);

        stubSave();
        await notifier(container).submit();
        expect(current(container).failure, isNull);
        expect(current(container).pauseFailure, isNull);
      },
    );

    test(
      'and the IN-FLIGHT state carries neither message: whichever attempt is '
      'running has already dropped the other one, so a spinner never runs '
      'under a banner explaining something else',
      () async {
        // Without this the invariant would be held entirely by the two
        // FAILURE arms and the clear at each attempt's start would be a line
        // no test could redden (T22b mutation m8, which survived until this
        // test existed). It is a real behaviour, so it is pinned rather than
        // deleted or called inert.
        stubRead(
          Fresh(stored(trackingPaused: false, pauseReason: 'menopause')),
        );
        stubSave(throws: const NetworkFailure('offline'));
        final container = buildContainer();
        await settled(container);

        notifier(container).setRegularity('regular');
        await notifier(container).submit();
        expect(current(container).failure, isA<NetworkFailure>());

        // A pause starts while the settings banner is up. Nothing is touched
        // in between, so only `_pauseWrite`'s own clear can drop it.
        final pauseGate = Completer<CycleSettingsResponse>();
        when(
          () => repo.pauseTracking(reason: any(named: 'reason')),
        ).thenAnswer((_) => pauseGate.future);
        final pausing = notifier(container).pause();
        await settle();

        expect(current(container).pausing, isTrue);
        expect(
          current(container).failure,
          isNull,
          reason: 'a stale settings banner over a running pause spinner',
        );
        pauseGate.completeError(const ServerFailure('boom'));
        await pausing;
        expect(current(container).pauseFailure, isA<ServerFailure>());

        // …and the mirror: a settings save starts while the PAUSE banner is
        // up. The form still holds the regularity edit, so no setter runs.
        final saveGate = Completer<CycleSettingsResponse>();
        when(
          () => repo.updateSettings(
            avgCycleLengthDays: any(named: 'avgCycleLengthDays'),
            avgPeriodLengthDays: any(named: 'avgPeriodLengthDays'),
            regularity: any(named: 'regularity'),
            phasePredictionEnabled: any(named: 'phasePredictionEnabled'),
            autoDetectPeriodStartEnabled: any(
              named: 'autoDetectPeriodStartEnabled',
            ),
            showFertilityWindowEnabled: any(
              named: 'showFertilityWindowEnabled',
            ),
            touchedAvgCycleLengthDays: any(named: 'touchedAvgCycleLengthDays'),
            touchedAvgPeriodLengthDays: any(
              named: 'touchedAvgPeriodLengthDays',
            ),
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
        ).thenAnswer((_) => saveGate.future);
        final saving = notifier(container).submit();
        await settle();

        expect(current(container).submitting, isTrue);
        expect(current(container).pauseFailure, isNull);
        saveGate.complete(stored());
        await saving;
      },
    );

    // -- in flight ----------------------------------------------------------

    test(
      'while a pause is in flight: a second pause is a no-op, a settings save '
      'is refused, and an edit is discarded rather than half-applied',
      () async {
        stubRead(Fresh(stored()));
        final gate = Completer<CycleSettingsResponse>();
        when(() => repo.pauseTracking(reason: any(named: 'reason'))).thenAnswer(
          (invocation) {
            pauseCalls.add(invocation.namedArguments[#reason] as String);
            return gate.future;
          },
        );
        final container = buildContainer();
        await settled(container);

        // A settings field is touched FIRST, so the save below is refused by
        // the in-flight guard and by nothing else. Without it `blockReason`
        // refuses the save on its own and `submit()`'s `|| form.pausing` is
        // untested — measured: dropping that clause left the suite green
        // (T22b mutation m10).
        notifier(container).setPhasePredictionEnabled(false);
        expect(current(container).blockReason, isNull);

        notifier(container).selectPauseReason('other');
        final inFlight = notifier(container).pause();
        await settle();

        expect(current(container).pausing, isTrue);
        expect(await notifier(container).pause(), isFalse);
        expect(await notifier(container).submit(), isFalse);
        notifier(container).setRegularity('regular');
        notifier(container).selectPauseReason('surgical');
        expect(current(container).regularity, 'somewhat');
        expect(current(container).selectedPauseReason, 'other');
        expect(pauseCalls, <String>['other']);
        expect(calls, isEmpty);

        gate.complete(stored(trackingPaused: true, pauseReason: 'other'));
        expect(await inFlight, isTrue);
        expect(current(container).pausing, isFalse);
      },
    );

    test('and while a SETTINGS save is in flight the pause pair is refused, so '
        'the two writes on this row can never overlap', () async {
      stubRead(Fresh(stored(pauseReason: 'other')));
      final gate = Completer<CycleSettingsResponse>();
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
      ).thenAnswer((_) => gate.future);
      final container = buildContainer();
      await settled(container);

      notifier(container).setRegularity('regular');
      final inFlight = notifier(container).submit();
      await settle();

      expect(current(container).submitting, isTrue);
      expect(await notifier(container).pause(), isFalse);
      expect(await notifier(container).resume(), isFalse);
      expect(pauseCalls, isEmpty);
      expect(resumeCalls, 0);

      gate.complete(stored());
      expect(await inFlight, isTrue);
    });
  });

  group('dependents — the pause sub-flow (P4b-T22b)', () {
    test('pausing and resuming refresh NEITHER the dashboard NOR the calendar '
        'either, and that was re-measured for T22b rather than inherited: '
        '`CycleCalendarService` builds its phase envelope as a literal '
        '`PhaseEngineNotImplemented` without reading `user_cycle_settings` at '
        'all, `CyclePhaseAvailability.TrackingPaused` is reserved for P6 and '
        'never emitted, and `CycleSettingsResponse.phasesUnavailable` still has '
        'no reader anywhere in `client/lib`. If a later phase gives either '
        'screen something derived from the pause state, change THIS test on '
        'purpose', () async {
      final dashboardBuilds = _Counter();
      final calendarBuilds = _Counter();
      final calendarRefreshes = _Counter();
      when(() => repo.pauseTracking(reason: any(named: 'reason'))).thenAnswer(
        (_) async => cycleSettingsFixture(
          trackingPaused: true,
          pauseReason: 'other',
          phasesUnavailable: true,
        ),
      );
      when(
        repo.resumeTracking,
      ).thenAnswer((_) async => cycleSettingsFixture(pauseReason: 'other'));

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
      notifier(container).selectPauseReason('other');
      await notifier(container).pause();
      await notifier(container).resume();
      await settle();

      expect(dashboardBuilds.value, 1);
      expect(calendarBuilds.value, 1);
      expect(calendarRefreshes.value, 0);
    });
  });
}
