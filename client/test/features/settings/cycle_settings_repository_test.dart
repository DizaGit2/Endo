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
// cache round trip. The PATCH half arrived with screen 32 (P4b-T22a) and has
// its own group at the bottom of this file — one endpoint, one owner.

import 'dart:convert';

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

    test(
      'TOUCHED + null — the field is absent, and in particular is NOT '
      'defaulted (a `?? 28` here would store a self-report the user never '
      'made, on a column onboarding also writes)',
      () async {
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
      },
    );

    test(
      'TOUCHED + SET — the field travels, and `false` travels as false (the '
      'boolean analogue of D-08: the server merges with `is { }`, never a '
      'truthiness test, so a deliberate "off" is a real datum)',
      () async {
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
      },
    );

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
}
