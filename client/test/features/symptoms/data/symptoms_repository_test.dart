// SymptomsRepository — the read-only day-scoped list P4b-T16 needs, and the
// slice P4b-T19 will extend with the writes.
//
// TDD (RED first). The two things worth being careful about, both named in
// the T16 brief: `from`/`to` are ALWAYS sent even though the generated
// client compiles without them (the contract wrongly marks them optional,
// but the validator 400s on a bare call), and `limit: 100` is ALWAYS sent
// (the default of 50 can silently exceed on a heavy day, and an out-of-range
// value is a 400 on this endpoint, never a clamp).

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/symptom_list_response.dart';
import 'package:lumen/core/cache/built_json_codec.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/harness.dart';

const _symptomsDayKey = 'GET:/symptoms?day=2026-04-20';

void main() {
  late MockLumenApiApi api;
  late MockCacheStore store;
  late SymptomsRepository repo;

  setUp(() {
    api = MockLumenApiApi();
    store = emptyCacheStore();
    repo = SymptomsRepository(api: api, store: store);
  });

  group('getDay', () {
    test('requests from=to=the given date AND limit=100, explicitly — not the '
        'compiled-but-wrong bare call', () async {
      when(
        () => api.symptomsGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(apiSuccess(symptomListResponseFixture()));

      await repo.getDay(DateTime(2026, 4, 20));

      final captured = verify(
        () => api.symptomsGet(
          from: captureAny(named: 'from'),
          to: captureAny(named: 'to'),
          limit: captureAny(named: 'limit'),
        ),
      ).captured;
      expect(captured, <Object?>[Date(2026, 4, 20), Date(2026, 4, 20), 100]);
    });

    test(
      'files the response under CacheKeys.symptomsDay at the shared TTL',
      () async {
        when(
          () => api.symptomsGet(
            from: any(named: 'from'),
            to: any(named: 'to'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(apiSuccess(symptomListResponseFixture()));

        await repo.getDay(DateTime(2026, 4, 20));

        verify(
          () => store.putJson(_symptomsDayKey, any(), ttl: CacheKeys.ttl),
        ).called(1);
      },
    );

    test('a fresh cache entry short-circuits — no network call', () async {
      final cached = _wireMapFor(symptomListResponseFixture());
      store = MockCacheStore();
      when(() => store.isFresh(_symptomsDayKey)).thenReturn(true);
      when(() => store.getJson(_symptomsDayKey)).thenReturn(cached);
      repo = SymptomsRepository(api: api, store: store);

      final result = await repo.getDay(DateTime(2026, 4, 20));

      expect(result, isA<Fresh<SymptomListResponse>>());
      verifyNever(
        () => api.symptomsGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
          limit: any(named: 'limit'),
        ),
      );
    });

    test('an empty day is a 200 with items:[] — passed straight through, not '
        'turned into an error', () async {
      when(
        () => api.symptomsGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        apiSuccess(symptomListResponseFixture(items: const [], total: 0)),
      );

      final result = await repo.getDay(DateTime(2026, 4, 20));

      expect(result, isA<Fresh<SymptomListResponse>>());
      final fresh = result as Fresh<SymptomListResponse>;
      expect(fresh.value.items!.isEmpty, isTrue);
      expect(fresh.value.total, 0);
    });

    test('a network failure with nothing cached answers NetworkRequired, not a '
        'thrown exception', () async {
      when(
        () => api.symptomsGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(apiNetworkFailure());

      final result = await repo.getDay(DateTime(2026, 4, 20));

      expect(result, isA<NetworkRequired<SymptomListResponse>>());
    });
  });
}

/// [value], serialized exactly the shape `SymptomsRepository` writes to and
/// reads from the cache box — `toCacheJson` (`core/cache/built_json_codec.dart`)
/// is the very function the repository's own `getDay` uses, so this is the
/// real round trip, not a reimplementation of it.
Map<String, dynamic> _wireMapFor(SymptomListResponse value) {
  return toCacheJson(SymptomListResponse.serializer, value);
}
