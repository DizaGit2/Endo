// CycleSettingsRepository — the read screen 3 composes with (P4b-T9).
//
// `GET /onboarding/state` answers `lastPeriodStart` and NONE of
// `avgCycleLengthDays` / `avgPeriodLengthDays` / `regularity` (ARCHITECTURE.md
// §C.0.1, the `POST /onboarding/cycle` row). Those three live here, and that
// asymmetry is the whole reason screen 3's resume is two calls: showing a
// returning user the DEFAULTS for two answers they already gave is exactly the
// state the endpoint's merge semantics exist to prevent.
//
// Everything asserted about the READ below is about that resume being
// trustworthy: the right key, the right TTL, and the three values surviving a
// cache round trip. The WRITES arrived with screen 32 — the settings save at
// P4b-T22a and the C-12 pause pair at P4b-T22b — and each has its own group
// below, plus a third that audits the three signatures at the SOURCE. One
// endpoint, one owner, and one place to look for why it is three methods.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/update_cycle_settings_request.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/data/cycle_settings_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';
import '../../support/screen_registry.dart';

/// The exact string this repository must file its read under, written out
/// rather than read back from [CacheKeys].
///
/// Comparing the repository's key to `CacheKeys.cycleSettings` would pass for
/// any pair of values as long as both sides moved together — including the
/// wrong one.
const _settingsKey = 'GET:/settings/cycle';

/// The captured `PATCH /settings/cycle` body the repository put on the wire.
UpdateCycleSettingsRequest _capturedPatch(MockLumenApiApi api) {
  return verify(
        () => api.settingsCyclePatch(
          updateCycleSettingsRequest: captureAny(
            named: 'updateCycleSettingsRequest',
          ),
        ),
      ).captured.last
      as UpdateCycleSettingsRequest;
}

/// [request], serialized exactly as it would go on the wire.
///
/// The whole touched-flag design is only observable HERE: a field the caller
/// did not touch must be **missing from this map**, because absence is what
/// the MERGE endpoint reads as "leave the stored value alone"
/// (`CycleSettingsService.UpdateAsync` assigns only `if (… is { } value)`).
/// `built_value` drops a null member from its own serialized form, so a key
/// present in this map was genuinely sent.
Map<String, dynamic> _wirePatchMap(UpdateCycleSettingsRequest request) {
  final encoded = standardSerializers.serializeWith(
    UpdateCycleSettingsRequest.serializer,
    request,
  );
  return json.decode(json.encode(encoded)) as Map<String, dynamic>;
}

void main() {
  late MockLumenApiApi api;
  late MockCacheStore store;
  late CycleSettingsRepository repo;

  setUpAll(() {
    registerFallbackValue(UpdateCycleSettingsRequest((b) => b));
  });

  setUp(() {
    api = MockLumenApiApi();
    store = emptyCacheStore();
    repo = CycleSettingsRepository(api: api, store: store);
  });

  test(
    'fetches the settings and files them under the shared key and TTL',
    () async {
      when(
        api.settingsCycleGet,
      ).thenAnswer(apiSuccess(cycleSettingsFixture(avgCycleLengthDays: 29)));

      final result = await repo.getSettings();

      expect(result, isA<Fresh<CycleSettingsResponse>>());
      expect(
        (result as Fresh<CycleSettingsResponse>).value.avgCycleLengthDays,
        29,
      );
      verify(
        () => store.putJson(_settingsKey, any(), ttl: CacheKeys.ttl),
      ).called(1);
    },
  );

  test('serves a fresh cache entry without touching the network', () async {
    when(() => store.isFresh(_settingsKey)).thenReturn(true);
    when(() => store.getJson(_settingsKey)).thenReturn(<String, dynamic>{
      'avgCycleLengthDays': 33,
      'regularity': 'irregular',
    });
    when(api.settingsCycleGet).thenAnswer(apiSuccess(cycleSettingsFixture()));

    final cached = await repo.getSettings();

    expect(cached, isA<Fresh<CycleSettingsResponse>>());
    expect(
      (cached as Fresh<CycleSettingsResponse>).value.avgCycleLengthDays,
      33,
    );
    verifyNever(api.settingsCycleGet);

    // Positive control for the `verifyNever` above: an UNWIRED mock also never
    // answers, so the absence of a call only means something if the SAME mock,
    // in the SAME test, is shown making one the moment the cache goes stale.
    when(() => store.isFresh(_settingsKey)).thenReturn(false);
    await repo.getSettings();
    verify(api.settingsCycleGet).called(1);
  });

  test('the three self-reports survive the cache round trip', () async {
    when(api.settingsCycleGet).thenAnswer(
      apiSuccess(
        cycleSettingsFixture(
          avgCycleLengthDays: 33,
          avgPeriodLengthDays: 5,
          regularity: 'irregular',
        ),
      ),
    );

    await repo.getSettings();

    // What was written, asserted BEFORE the read-back: a `fromJson` that
    // rebuilt the values out of thin air would pass a read-back-only test.
    final written =
        verify(
              () => store.putJson(
                _settingsKey,
                captureAny(),
                ttl: any(named: 'ttl'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(written['avgCycleLengthDays'], 33);
    expect(written['avgPeriodLengthDays'], 5);
    expect(written['regularity'], 'irregular');

    when(() => store.isFresh(_settingsKey)).thenReturn(true);
    when(() => store.getJson(_settingsKey)).thenReturn(written);

    final cached = await repo.getSettings();
    final value = (cached as Fresh<CycleSettingsResponse>).value;
    expect(value.avgCycleLengthDays, 33);
    expect(value.avgPeriodLengthDays, 5);
    expect(value.regularity, 'irregular');
  });

  test(
    'a 200 with no body is a typed failure, not a null settings row',
    () async {
      when(api.settingsCycleGet).thenAnswer(
        (_) async => Response<CycleSettingsResponse>(
          requestOptions: RequestOptions(path: '/settings/cycle'),
          statusCode: 200,
        ),
      );

      final empty = await repo.getSettings();

      expect(empty, isA<NetworkRequired<CycleSettingsResponse>>());
      expect(
        (empty as NetworkRequired<CycleSettingsResponse>).failure,
        isA<ServerFailure>(),
      );

      // The offline case lands on the SAME arm, so asserting the arm alone would
      // not distinguish "empty body" from "no network". Run both and assert they
      // carry different failures.
      when(
        api.settingsCycleGet,
      ).thenAnswer(apiNetworkFailure<CycleSettingsResponse>());
      final offline = await repo.getSettings();
      expect(
        (offline as NetworkRequired<CycleSettingsResponse>).failure,
        isA<NetworkFailure>(),
      );
    },
  );

  // -------------------------------------------------------------------------
  // updateSettings — `PATCH /settings/cycle` (screen 32, P4b-T22a)
  // -------------------------------------------------------------------------
  //
  // This endpoint MERGES: an absent key leaves the stored column alone, and
  // there is no way to clear one at all (`UpdateCycleSettingsRequest`'s own
  // doc: a positional record with `int?` cannot tell absent from explicit null
  // under System.Text.Json, and built_value omits nulls on the wire). So
  // "omit the field" is the safe answer, and the danger is asserting a field
  // the user never touched — `logDay`'s shape, for `logDay`'s reason.
  //
  // Six explicit `touched*` flags decide what is sent, and they are NEVER
  // re-derived from whether the value is null. The matrix below varies the two
  // inputs INDEPENDENTLY — untouched+null, untouched+SET, touched+null,
  // touched+SET — because a suite that only ever supplies "untouched AND null"
  // together cannot tell the guard from the serializer, and deleting either
  // one would leave it green (P4b-T18's own defect).

  group('updateSettings', () {
    void stubPatch({CycleSettingsResponse? body}) {
      when(
        () => api.settingsCyclePatch(
          updateCycleSettingsRequest: any(named: 'updateCycleSettingsRequest'),
        ),
      ).thenAnswer(apiSuccess(body ?? cycleSettingsFixture()));
    }

    /// Every argument defaulted to "untouched, holding nothing", so each test
    /// states only the axis it varies.
    Future<CycleSettingsResponse> update({
      int? avgCycleLengthDays,
      int? avgPeriodLengthDays,
      String? regularity,
      bool? phasePredictionEnabled,
      bool? autoDetectPeriodStartEnabled,
      bool? showFertilityWindowEnabled,
      bool touchedAvgCycleLengthDays = false,
      bool touchedAvgPeriodLengthDays = false,
      bool touchedRegularity = false,
      bool touchedPhasePredictionEnabled = false,
      bool touchedAutoDetectPeriodStartEnabled = false,
      bool touchedShowFertilityWindowEnabled = false,
    }) {
      return repo.updateSettings(
        avgCycleLengthDays: avgCycleLengthDays,
        avgPeriodLengthDays: avgPeriodLengthDays,
        regularity: regularity,
        phasePredictionEnabled: phasePredictionEnabled,
        autoDetectPeriodStartEnabled: autoDetectPeriodStartEnabled,
        showFertilityWindowEnabled: showFertilityWindowEnabled,
        touchedAvgCycleLengthDays: touchedAvgCycleLengthDays,
        touchedAvgPeriodLengthDays: touchedAvgPeriodLengthDays,
        touchedRegularity: touchedRegularity,
        touchedPhasePredictionEnabled: touchedPhasePredictionEnabled,
        touchedAutoDetectPeriodStartEnabled:
            touchedAutoDetectPeriodStartEnabled,
        touchedShowFertilityWindowEnabled: touchedShowFertilityWindowEnabled,
      );
    }

    // -- the touched-flag matrix, both inputs varied independently -----------

    test('UNTOUCHED + null — the field is absent from the wire', () async {
      stubPatch();

      await update(
        // One unrelated flag on, so the body is not empty for another reason.
        showFertilityWindowEnabled: true,
        touchedShowFertilityWindowEnabled: true,
      );

      final wire = _wirePatchMap(_capturedPatch(api));
      expect(wire.containsKey('avgCycleLengthDays'), isFalse);
      expect(wire.containsKey('avgPeriodLengthDays'), isFalse);
      expect(wire.containsKey('regularity'), isFalse);
    });

    test(
      'UNTOUCHED + SET — the field is STILL absent. This is the case a guard '
      're-derived from nullability (`if (avgCycleLengthDays != null)`) would '
      'get wrong, and it is the only case that can tell the two apart',
      () async {
        stubPatch();

        await update(
          // Every value present — a seed read off a 5-minute-TTL cache that
          // the user never edited. None of it may travel: under MERGE each one
          // would OVERWRITE whatever the server now holds.
          avgCycleLengthDays: 29,
          avgPeriodLengthDays: 5,
          regularity: 'irregular',
          phasePredictionEnabled: true,
          autoDetectPeriodStartEnabled: true,
          showFertilityWindowEnabled: false,
        );

        final wire = _wirePatchMap(_capturedPatch(api));
        expect(
          wire,
          isEmpty,
          reason:
              'nothing was touched, so nothing may be asserted — every one of '
              'these six values would overwrite newer server state',
        );
      },
    );

    test('TOUCHED + null — the field is absent, and in particular is NOT '
        'defaulted (a `?? 28` here would store a self-report the user never '
        'made, on a column onboarding also writes)', () async {
      stubPatch();

      await update(
        avgCycleLengthDays: null,
        avgPeriodLengthDays: null,
        regularity: null,
        phasePredictionEnabled: null,
        touchedAvgCycleLengthDays: true,
        touchedAvgPeriodLengthDays: true,
        touchedRegularity: true,
        touchedPhasePredictionEnabled: true,
        // One real change, so this is not merely the empty-body case.
        showFertilityWindowEnabled: true,
        touchedShowFertilityWindowEnabled: true,
      );

      final wire = _wirePatchMap(_capturedPatch(api));
      expect(
        wire.keys,
        unorderedEquals(<String>['showFertilityWindowEnabled']),
      );
      expect(wire['avgCycleLengthDays'], isNot(28));
      expect(wire['phasePredictionEnabled'], isNot(false));
    });

    test('TOUCHED + SET — the field travels, and `false` travels as false (the '
        'boolean analogue of D-08: the server merges with `is { }`, never a '
        'truthiness test, so a deliberate "off" is a real datum)', () async {
      stubPatch();

      await update(
        avgCycleLengthDays: 45,
        avgPeriodLengthDays: 8,
        regularity: 'irregular',
        phasePredictionEnabled: false,
        autoDetectPeriodStartEnabled: false,
        showFertilityWindowEnabled: false,
        touchedAvgCycleLengthDays: true,
        touchedAvgPeriodLengthDays: true,
        touchedRegularity: true,
        touchedPhasePredictionEnabled: true,
        touchedAutoDetectPeriodStartEnabled: true,
        touchedShowFertilityWindowEnabled: true,
      );

      final wire = _wirePatchMap(_capturedPatch(api));
      expect(wire['avgCycleLengthDays'], 45);
      expect(wire['avgPeriodLengthDays'], 8);
      expect(wire['regularity'], 'irregular');
      expect(wire['phasePredictionEnabled'], false);
      expect(wire['autoDetectPeriodStartEnabled'], false);
      expect(wire['showFertilityWindowEnabled'], false);
    });

    test(
      'the six flags are INDEPENDENT — touching only the period length sends '
      'only the period length, even while the other five hold values',
      () async {
        stubPatch();

        await update(
          avgCycleLengthDays: 29,
          avgPeriodLengthDays: 6,
          regularity: 'regular',
          phasePredictionEnabled: true,
          autoDetectPeriodStartEnabled: true,
          showFertilityWindowEnabled: true,
          touchedAvgPeriodLengthDays: true,
        );

        final wire = _wirePatchMap(_capturedPatch(api));
        expect(wire.keys, unorderedEquals(<String>['avgPeriodLengthDays']));
        expect(wire['avgPeriodLengthDays'], 6);
      },
    );

    test(
      'R2 — `avgPeriodLengthDays` really can be set from here, and this is '
      'the ONLY surface in the app that can: onboarding screen 3 never '
      'collects it, so if this method could not send it nothing could',
      () async {
        stubPatch();

        await update(avgPeriodLengthDays: 4, touchedAvgPeriodLengthDays: true);

        final wire = _wirePatchMap(_capturedPatch(api));
        expect(wire['avgPeriodLengthDays'], 4);
      },
    );

    test(
      'the request can NEVER carry a pause field, whatever the caller does — '
      'the three C-12 members are not parameters of this method at all, so '
      'echoing a 200 back is structurally impossible rather than merely '
      'avoided. (That echo is a 400 for any user who has paused and resumed: '
      '`pauseReason` survives a resume by design, and `Validate` rejects it '
      'whenever the effective state is not paused.)',
      () async {
        stubPatch(
          body: cycleSettingsFixture(
            trackingPaused: false,
            pauseReason: 'pregnancy',
          ),
        );

        await update(
          avgCycleLengthDays: 30,
          avgPeriodLengthDays: 5,
          regularity: 'regular',
          phasePredictionEnabled: true,
          autoDetectPeriodStartEnabled: true,
          showFertilityWindowEnabled: true,
          touchedAvgCycleLengthDays: true,
          touchedAvgPeriodLengthDays: true,
          touchedRegularity: true,
          touchedPhasePredictionEnabled: true,
          touchedAutoDetectPeriodStartEnabled: true,
          touchedShowFertilityWindowEnabled: true,
        );

        final wire = _wirePatchMap(_capturedPatch(api));
        expect(wire.containsKey('trackingPaused'), isFalse);
        expect(wire.containsKey('pauseReason'), isFalse);
        expect(wire.containsKey('pausedSince'), isFalse);
        // …and the six that ARE this task's did travel, so the three absences
        // above are about the pause triple and not about an empty request.
        expect(wire.keys, hasLength(6));
      },
    );

    // -- cache ---------------------------------------------------------------

    test('a successful save invalidates the settings read', () async {
      stubPatch();

      await update(regularity: 'regular', touchedRegularity: true);

      verify(() => store.invalidate(_settingsKey)).called(1);
    });

    test(
      'an AMBIGUOUS failure invalidates too (S-6: a write that committed and '
      'then timed out would otherwise leave the read fresh for the rest of '
      'the TTL), while a 400 invalidates NOTHING — the server collects every '
      'error before the first write, so a rejected request changed nothing',
      () async {
        when(
          () => api.settingsCyclePatch(
            updateCycleSettingsRequest: any(
              named: 'updateCycleSettingsRequest',
            ),
          ),
        ).thenAnswer(apiNetworkFailure<CycleSettingsResponse>());

        await expectLater(
          update(regularity: 'regular', touchedRegularity: true),
          throwsA(isA<NetworkFailure>()),
        );
        verify(() => store.invalidate(_settingsKey)).called(1);

        when(
          () => api.settingsCyclePatch(
            updateCycleSettingsRequest: any(
              named: 'updateCycleSettingsRequest',
            ),
          ),
        ).thenAnswer(
          apiValidationProblem<CycleSettingsResponse>(
            fields: <String, List<String>>{
              'avgCycleLengthDays': <String>[
                'value must be between 1 and 32767',
              ],
            },
          ),
        );

        await expectLater(
          update(avgCycleLengthDays: 99999, touchedAvgCycleLengthDays: true),
          throwsA(isA<ValidationFailure>()),
        );
        verifyNever(() => store.invalidate(_settingsKey));
      },
    );

    test('a 200 with no body is a typed ServerFailure', () async {
      when(
        () => api.settingsCyclePatch(
          updateCycleSettingsRequest: any(named: 'updateCycleSettingsRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<CycleSettingsResponse>(
          requestOptions: RequestOptions(path: '/settings/cycle'),
          statusCode: 200,
        ),
      );

      await expectLater(
        update(regularity: 'regular', touchedRegularity: true),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('the 200 body is returned to the caller unchanged', () async {
      stubPatch(
        body: cycleSettingsFixture(
          avgCycleLengthDays: 45,
          warnings: const <String>['avg_cycle_length_out_of_sanity_band'],
        ),
      );

      final saved = await update(
        avgCycleLengthDays: 45,
        touchedAvgCycleLengthDays: true,
      );

      expect(saved.avgCycleLengthDays, 45);
      expect(saved.warnings?.toList(), <String>[
        'avg_cycle_length_out_of_sanity_band',
      ]);
    });
  });

  // -------------------------------------------------------------------------
  // pauseTracking / resumeTracking — the C-12 sub-flow (screen 32, P4b-T22b)
  // -------------------------------------------------------------------------
  //
  // **These are separate methods on purpose, and the reason is the whole of
  // this task's safety argument.** Before T22b the response could not be
  // echoed back at the endpoint because `updateSettings` had no `pauseReason`
  // parameter — *"the current guard is: the parameter does not exist"*. T22b
  // writes the same row through the same endpoint, so that guard had to be
  // REPLACED rather than merely inherited. What replaces it:
  //
  //   * `updateSettings` still has NO pause parameter (unchanged);
  //   * `pauseTracking` sends `trackingPaused: true` as a LITERAL — it has no
  //     `trackingPaused` parameter, so a reason can never ride an unpaused
  //     request;
  //   * `resumeTracking` takes NO ARGUMENTS AT ALL and sends
  //     `trackingPaused: false` and nothing else, so the remembered reason a
  //     resumed user's 200 still carries — the server preserves it across a
  //     resume on purpose — has no way back onto the wire.
  //
  // The 400-producing combination is `trackingPaused: false` WITH a
  // `pauseReason` (`CycleSettingsValidationMessages.PauseFieldRequiresPause`:
  // *"value is only allowed while cycle tracking is paused"*). No public
  // method on this repository can express it. The exact-key-set assertions
  // below are what pin that: each reddens if the flag becomes a parameter, or
  // if a reason is added to the resume path.
  //
  // Neither method carries any of the six self-report values either, which
  // closes the second half of the same hazard: `UpdateCycleSettingsRequest`'s
  // own contract doc warns that a pause card posting the whole resource would
  // *"silently reset AvgCycleLengthDays … and destroy a self-report the user
  // made on a different control"*.

  group('the pause sub-flow', () {
    void stubPatch({CycleSettingsResponse? body}) {
      when(
        () => api.settingsCyclePatch(
          updateCycleSettingsRequest: any(named: 'updateCycleSettingsRequest'),
        ),
      ).thenAnswer(apiSuccess(body ?? cycleSettingsFixture()));
    }

    /// The five C-12 members, written out rather than read off any symbol —
    /// the same reason `_settingsKey` is a literal. A test that compared the
    /// repository's codes to the app's own enum would pass for any pair of
    /// values as long as both sides moved together, including the wrong one.
    const wireReasons = <String>[
      'pregnancy',
      'hormonal_suppression',
      'surgical',
      'menopause',
      'other',
    ];

    test('resumeTracking puts EXACTLY `{trackingPaused: false}` on the wire — '
        'this is the guard that replaces "the parameter does not exist". A '
        'resumed user 200 still carries their last `pauseReason` BY DESIGN, and '
        'echoing that back alongside `trackingPaused: false` is a 400 keyed '
        '`pauseReason`. This method takes no arguments, so there is nothing to '
        'echo it with', () async {
      stubPatch(
        body: cycleSettingsFixture(
          trackingPaused: false,
          pauseReason: 'pregnancy',
        ),
      );

      await repo.resumeTracking();

      final wire = _wirePatchMap(_capturedPatch(api));
      expect(wire.keys, unorderedEquals(<String>['trackingPaused']));
      expect(wire['trackingPaused'], isFalse);
    });

    test(
      'pauseTracking puts EXACTLY `{trackingPaused: true, pauseReason: …}` on '
      'the wire — never `pausedSince`, which the server defaults to the user '
      'own today and which this client deliberately cannot supply',
      () async {
        stubPatch();

        await repo.pauseTracking(reason: 'surgical');

        final wire = _wirePatchMap(_capturedPatch(api));
        expect(
          wire.keys,
          unorderedEquals(<String>['trackingPaused', 'pauseReason']),
        );
        expect(wire['trackingPaused'], isTrue);
        expect(wire['pauseReason'], 'surgical');
      },
    );

    for (final reason in wireReasons) {
      test('`$reason` reaches the wire verbatim, and pauses', () async {
        stubPatch();

        await repo.pauseTracking(reason: reason);

        final wire = _wirePatchMap(_capturedPatch(api));
        expect(wire['pauseReason'], reason);
        expect(wire['trackingPaused'], isTrue);
      });
    }

    test('NEITHER method can carry one of the six self-report values, whatever '
        'the caller does — so a pause can never re-assert a stale seed over '
        'whatever the server now holds (the cross-surface wipe merge exists to '
        'prevent). The same structural argument as `updateSettings` having no '
        'pause parameter, in the other direction', () async {
      stubPatch(
        body: cycleSettingsFixture(
          avgCycleLengthDays: 45,
          avgPeriodLengthDays: 9,
          regularity: 'irregular',
          trackingPaused: true,
          pauseReason: 'menopause',
        ),
      );

      await repo.pauseTracking(reason: 'menopause');
      final paused = _wirePatchMap(_capturedPatch(api));
      await repo.resumeTracking();
      final resumed = _wirePatchMap(_capturedPatch(api));

      for (final wire in <Map<String, dynamic>>[paused, resumed]) {
        for (final field in <String>[
          'avgCycleLengthDays',
          'avgPeriodLengthDays',
          'regularity',
          'phasePredictionEnabled',
          'autoDetectPeriodStartEnabled',
          'showFertilityWindowEnabled',
          'pausedSince',
        ]) {
          expect(
            wire.containsKey(field),
            isFalse,
            reason: '$field must not ride a pause request',
          );
        }
      }
    });

    test('a pause-only body is NOT the endpoint empty body — `Validate` '
        'emptiness test spans all NINE members, so `{trackingPaused: false}` '
        'alone names a field and is a legal request', () async {
      stubPatch();

      await repo.resumeTracking();

      final wire = _wirePatchMap(_capturedPatch(api));
      expect(wire, isNotEmpty);
    });

    // -- cache ---------------------------------------------------------------

    test('both writes invalidate the settings read on success and on an '
        'AMBIGUOUS failure (S-6), and neither invalidates on a 400', () async {
      stubPatch();
      await repo.pauseTracking(reason: 'other');
      verify(() => store.invalidate(_settingsKey)).called(1);

      await repo.resumeTracking();
      verify(() => store.invalidate(_settingsKey)).called(1);

      when(
        () => api.settingsCyclePatch(
          updateCycleSettingsRequest: any(named: 'updateCycleSettingsRequest'),
        ),
      ).thenAnswer(apiNetworkFailure<CycleSettingsResponse>());
      await expectLater(
        repo.pauseTracking(reason: 'other'),
        throwsA(isA<NetworkFailure>()),
      );
      verify(() => store.invalidate(_settingsKey)).called(1);

      when(
        () => api.settingsCyclePatch(
          updateCycleSettingsRequest: any(named: 'updateCycleSettingsRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem<CycleSettingsResponse>(
          fields: <String, List<String>>{
            'pauseReason': <String>['value is not an allowed value'],
          },
        ),
      );
      await expectLater(
        repo.pauseTracking(reason: 'other'),
        throwsA(isA<ValidationFailure>()),
      );
      verifyNever(() => store.invalidate(_settingsKey));
    });

    test('a 200 with no body is a typed ServerFailure on both', () async {
      when(
        () => api.settingsCyclePatch(
          updateCycleSettingsRequest: any(named: 'updateCycleSettingsRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<CycleSettingsResponse>(
          requestOptions: RequestOptions(path: '/settings/cycle'),
          statusCode: 200,
        ),
      );

      await expectLater(
        repo.pauseTracking(reason: 'other'),
        throwsA(isA<ServerFailure>()),
      );
      await expectLater(repo.resumeTracking(), throwsA(isA<ServerFailure>()));
    });

    test(
      'the 200 body reaches the caller unchanged, pause triple and all',
      () async {
        stubPatch(
          body: cycleSettingsFixture(
            trackingPaused: true,
            pauseReason: 'hormonal_suppression',
            phasesUnavailable: true,
          ),
        );

        final saved = await repo.pauseTracking(reason: 'hormonal_suppression');

        expect(saved.trackingPaused, isTrue);
        expect(saved.pauseReason, 'hormonal_suppression');
        expect(saved.phasesUnavailable, isTrue);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The round-trip guard, at the SOURCE (P4b-T22b)
  // -------------------------------------------------------------------------
  //
  // **This group is what replaces "the parameter does not exist".**
  //
  // Until T22b, the 400-producing echo — `trackingPaused: false` together with
  // the `pauseReason` a resumed user's own 200 still carries — could not be
  // built by any caller, because `updateSettings` had no such parameter. That
  // was a property of a method SIGNATURE, held by nothing but its own absence:
  // adding the parameter would have made the echo constructible and reddened
  // nothing. T22b writes the same row through the same endpoint, so the
  // property had to be re-established and then PINNED.
  //
  // The property, stated as a shape rather than as a behaviour:
  //
  //   * `updateSettings` names none of the three pause members;
  //   * `pauseTracking` takes a reason and NOT the flag — it sends
  //     `trackingPaused: true` as a literal;
  //   * `resumeTracking` takes nothing at all;
  //   * `pausedSince` is set by nothing, anywhere in the file;
  //   * and no PUBLIC method takes a request object, which would hand a caller
  //     back everything the three signatures withhold.
  //
  // Behaviour tests cannot see this. The wire assertions above prove what
  // today's callers send; they cannot prove what tomorrow's caller COULD send,
  // and that is exactly the difference the old guard lived in. So this is a
  // syntactic audit of the repository's own source — the shape
  // `duration_days_guard.dart` and `golden_comparison_gate_test.dart` already
  // use in this repo, for the same reason: some properties are about the code
  // rather than about a run of it.
  //
  // **Every assertion here has been watched to fail** (T22b's mutation round,
  // g1–g4): a `pauseReason` parameter added to `updateSettings`, a `reason`
  // added to `resumeTracking`, a `pausedSince` added to `pauseTracking`, and
  // `_patch` made public each redden exactly the clause that names them.

  group('the round-trip guard, at the source', () {
    late String source;
    late Map<String, MethodDeclaration> methods;

    setUpAll(() {
      final file = File(
        '${resolvePackageRoot().path}/lib/features/settings/data/'
        'cycle_settings_repository.dart',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'the repository moved; re-point this guard rather than deleting '
            'it — it is the only thing standing where "the parameter does not '
            'exist" used to',
      );
      source = file.readAsStringSync();
      final parsed = parseString(
        content: source,
        path: file.path,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      final collector = _MethodCollector();
      parsed.unit.accept(collector);
      methods = collector.byName;
      expect(
        methods.keys,
        containsAll(<String>[
          'getSettings',
          'updateSettings',
          'pauseTracking',
          'resumeTracking',
        ]),
        reason: 'the repository was reshaped; re-point this guard',
      );
    });

    List<String> parameterNames(String name) {
      final method = methods[name];
      expect(method, isNotNull, reason: '$name is gone from the repository');
      return (method!.parameters?.parameters ?? const <FormalParameter>[])
          .map((p) => p.name?.lexeme ?? '')
          .toList();
    }

    test('updateSettings names NONE of the three pause members — the original '
        'guard, unchanged and now asserted rather than merely true', () {
      final names = parameterNames('updateSettings');
      expect(names, isNotEmpty);
      for (final member in <String>[
        'trackingPaused',
        'pauseReason',
        'pausedSince',
      ]) {
        expect(
          names,
          isNot(contains(member)),
          reason:
              'a settings save that can carry $member can echo a response '
              'back, and for a paused-then-resumed user that echo is a 400',
        );
      }
    });

    test('pauseTracking takes the reason and NOT the flag: `trackingPaused = '
        'true` is a literal in its body, so a reason can never ride an unpaused '
        'request', () {
      expect(parameterNames('pauseTracking'), <String>['reason']);
      expect(
        methods['pauseTracking']!.toSource(),
        contains('trackingPaused = true'),
      );
    });

    test('resumeTracking takes NOTHING — the remembered reason a resumed user '
        'still carries has no parameter to travel in', () {
      expect(parameterNames('resumeTracking'), isEmpty);
      expect(
        methods['resumeTracking']!.toSource(),
        contains('trackingPaused = false'),
      );
    });

    test(
      'nothing in this file sets `pausedSince`. The server defaults it to the '
      "caller's own user-local today; sending one would need a date derived "
      'from the device clock and opens two 400s (FutureDate, and '
      'PauseFieldRequiresPause while unpaused) for a gesture screen 32 does '
      'not offer',
      () {
        expect(source, isNot(contains('pausedSince =')));
      },
    );

    test('no PUBLIC method takes an UpdateCycleSettingsRequest — the three '
        'signatures ARE the guard, and one method that accepts a prebuilt body '
        'hands a caller back everything they withhold', () {
      for (final entry in methods.entries) {
        final takesRequest =
            (entry.value.parameters?.parameters ?? const <FormalParameter>[])
                .map((p) => p.toSource())
                .any((s) => s.contains('UpdateCycleSettingsRequest'));
        if (!takesRequest) continue;
        expect(
          entry.key.startsWith('_'),
          isTrue,
          reason:
              '${entry.key} takes a request object and is public. Keep the '
              'body-building inside the repository, where each method fixes '
              'what its own request may contain.',
        );
      }
    });
  });
}

/// Every method declared in the parsed unit, by name.
///
/// A visitor rather than `ClassDeclaration.members`: analyzer 12 reshaped the
/// class-declaration API (`screen_registry.dart` records the same surprise
/// about `namePart`), and this audit does not need to know which class a
/// method belongs to — the repository file declares exactly one.
class _MethodCollector extends RecursiveAstVisitor<void> {
  final Map<String, MethodDeclaration> byName = <String, MethodDeclaration>{};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    byName[node.name.lexeme] = node;
    super.visitMethodDeclaration(node);
  }
}
