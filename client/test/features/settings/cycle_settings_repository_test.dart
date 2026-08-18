// CycleSettingsRepository — the read screen 3 composes with (P4b-T9).
//
// `GET /onboarding/state` answers `lastPeriodStart` and NONE of
// `avgCycleLengthDays` / `avgPeriodLengthDays` / `regularity` (ARCHITECTURE.md
// §C.0.1, the `POST /onboarding/cycle` row). Those three live here, and that
// asymmetry is the whole reason screen 3's resume is two calls: showing a
// returning user the DEFAULTS for two answers they already gave is exactly the
// state the endpoint's merge semantics exist to prevent.
//
// Everything asserted below is about that resume being trustworthy: the right
// key, the right TTL, and the three values surviving a cache round trip. The
// PATCH half of this endpoint belongs to screen 32 (T22a) and is deliberately
// not here — one endpoint, one owner, and a write nobody calls is a write
// nobody tests.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
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

void main() {
  late MockLumenApiApi api;
  late MockCacheStore store;
  late CycleSettingsRepository repo;

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
}
