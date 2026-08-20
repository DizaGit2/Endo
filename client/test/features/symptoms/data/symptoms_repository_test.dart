// SymptomsRepository — the read-only day-scoped list P4b-T16 needs, and the
// slice P4b-T19 will extend with the writes.
//
// TDD (RED first). The two things worth being careful about, both named in
// the T16 brief: `from`/`to` are ALWAYS sent even though the generated
// client compiles without them (the contract wrongly marks them optional,
// but the validator 400s on a bare call), and `limit: 100` is ALWAYS sent
// (the default of 50 can silently exceed on a heavy day, and an out-of-range
// value is a 400 on this endpoint, never a clamp).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/create_symptoms_request.dart';
import 'package:lumen/api/model/create_symptoms_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/symptom_entry_input.dart';
import 'package:lumen/api/model/symptom_list_response.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/cache/built_json_codec.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/symptoms/data/symptoms_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/harness.dart';

const _symptomsDayKey = 'GET:/symptoms?day=2026-04-20';

// ---------------------------------------------------------------------------
// createBatch harness
// ---------------------------------------------------------------------------

/// A minimal, fully-explicit valid entry — every field named, so a test that
/// overrides one field cannot accidentally lean on another's default.
SymptomEntryDraft _draft({
  String? symptomCode = 'bloating',
  int intensity = 5,
  String? region = 'lower_abdomen',
  String? side,
  List<String> painTypes = const <String>[],
  List<String> triggers = const <String>[],
  DateTime? occurredAt,
  String? notes,
}) {
  return SymptomEntryDraft(
    symptomCode: symptomCode,
    intensity: intensity,
    region: region,
    side: side,
    painTypes: painTypes,
    triggers: triggers,
    occurredAt: occurredAt,
    notes: notes,
  );
}

/// The captured request the repository actually put on the wire.
CreateSymptomsRequest _capturedRequest(MockLumenApiApi api) {
  return verify(
        () => api.symptomsPost(
          createSymptomsRequest: captureAny(named: 'createSymptomsRequest'),
        ),
      ).captured.last
      as CreateSymptomsRequest;
}

/// [request], serialized exactly as it would go on the wire — the level at
/// which "omitted" vs "explicit null" actually differ. `built_value` drops a
/// null member from its own serialized form, so a field missing from this map
/// is the proof a null field is OMITTED, not sent as `"field": null`.
Map<String, dynamic> _wireMap(CreateSymptomsRequest request) {
  final encoded = standardSerializers.serializeWith(
    CreateSymptomsRequest.serializer,
    request,
  );
  return json.decode(json.encode(encoded)) as Map<String, dynamic>;
}

/// Entry `index` of [request], serialized exactly as it goes on the wire.
Map<String, dynamic> _wireEntry(CreateSymptomsRequest request, int index) {
  final entries = _wireMap(request)['entries'] as List<dynamic>;
  return entries[index] as Map<String, dynamic>;
}

void main() {
  late MockLumenApiApi api;
  late MockCacheStore store;
  late SymptomsRepository repo;

  setUpAll(() {
    registerFallbackValue(
      CreateSymptomsRequest((b) => b.entries.replace(<SymptomEntryInput>[])),
    );
  });

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

  // ---------------------------------------------------------------------
  // POST /symptoms — the P4b-T19 batch write
  // ---------------------------------------------------------------------

  group('createBatch', () {
    // ── The non-null mapper boundary (item 4) ──────────────────────────

    test('an explicit null symptomCode/region/side is OMITTED from the wire, '
        'not sent as an explicit null', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiSuccess(createSymptomsResponseFixture()));

      await repo.createBatch(
        entries: [
          _draft(
            symptomCode: null,
            region: null,
            side: null,
            occurredAt: DateTime.utc(2026, 4, 20, 8),
          ),
        ],
      );

      final entry = _wireEntry(_capturedRequest(api), 0);
      expect(
        entry.containsKey('symptomCode'),
        isFalse,
        reason:
            'an explicit null must be OMITTED — that is what the '
            'server reads as "give me the pain default"',
      );
      expect(entry.containsKey('region'), isFalse);
      expect(entry.containsKey('side'), isFalse);
    });

    test('an explicit symptomCode/region/side value reaches the wire unchanged '
        '— proving the mapper line for each field was not dropped', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiSuccess(createSymptomsResponseFixture()));

      await repo.createBatch(
        entries: [
          _draft(
            symptomCode: 'bloating',
            region: 'lower_abdomen',
            side: 'front',
            occurredAt: DateTime.utc(2026, 4, 20, 8),
          ),
        ],
      );

      final entry = _wireEntry(_capturedRequest(api), 0);
      expect(entry['symptomCode'], 'bloating');
      expect(entry['region'], 'lower_abdomen');
      expect(entry['side'], 'front');
    });

    test('intensity: 0 survives to the wire as the literal 0 — D-08, never '
        'omitted and never confused with absence', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiSuccess(createSymptomsResponseFixture()));

      await repo.createBatch(
        entries: [
          _draft(intensity: 0, occurredAt: DateTime.utc(2026, 4, 20, 8)),
        ],
      );

      final entry = _wireEntry(_capturedRequest(api), 0);
      expect(
        entry.containsKey('intensity'),
        isTrue,
        reason: 'D-08: 0 is a real datum, never omitted like an absent value',
      );
      expect(entry['intensity'], 0);
    });

    // ── R-18 batch bounds — refused client-side, no chunking ───────────

    test('a single entry (the floor) reaches the network', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiSuccess(createSymptomsResponseFixture()));

      await repo.createBatch(entries: [_draft()]);

      verify(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).called(1);
    });

    test('exactly 50 entries (the ceiling) reaches the network', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        apiSuccess(
          createSymptomsResponseFixture(
            items: List.generate(50, (_) => symptomResponseFixture()),
          ),
        ),
      );

      final created = await repo.createBatch(
        entries: List.generate(50, (_) => _draft()),
      );

      expect(created, hasLength(50));
      verify(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).called(1);
    });

    test(
      'an empty batch is refused CLIENT-SIDE — no network call, a '
      'ValidationFailure keyed "entries" reusing the server\'s own message',
      () async {
        final failure = await repo
            .createBatch(entries: const [])
            .then<Object?>((v) => v, onError: (Object e) => e);

        expect(failure, isA<ValidationFailure>());
        expect(
          (failure! as ValidationFailure).messageFor('entries'),
          'at least one entry is required',
        );
        verifyNever(
          () => api.symptomsPost(
            createSymptomsRequest: any(named: 'createSymptomsRequest'),
          ),
        );
      },
    );

    test('a 51-entry batch is refused CLIENT-SIDE — no network call, no '
        'chunking, a ValidationFailure keyed "entries"', () async {
      final failure = await repo
          .createBatch(entries: List.generate(51, (_) => _draft()))
          .then<Object?>((v) => v, onError: (Object e) => e);

      expect(failure, isA<ValidationFailure>());
      expect(
        (failure! as ValidationFailure).messageFor('entries'),
        'a request may contain at most 50 entries',
      );
      verifyNever(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      );
    });

    // ── All-or-nothing ───────────────────────────────────────────────

    test('a per-entry 400 keyed entries[N].field binds to that entry, and '
        'nothing is written', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: {
            'entries[1].intensity': ['value must be between 0 and 10'],
          },
        ),
      );

      final failure = await repo
          .createBatch(entries: [_draft(), _draft(intensity: 99)])
          .then<Object?>((v) => v, onError: (Object e) => e);

      expect(failure, isA<ValidationFailure>());
      expect(
        (failure! as ValidationFailure).messageFor('entries[1].intensity'),
        'value must be between 0 and 10',
      );
      verifyNever(() => store.invalidate(any()));
    });

    // ── Multi-day invalidation (item 2) ─────────────────────────────────

    test('invalidates CacheKeys.keysForDate for EVERY distinct occurredOn in '
        'the response — a batch spanning two days invalidates both', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        apiSuccess(
          createSymptomsResponseFixture(
            items: [
              symptomResponseFixture(occurredOn: Date(2026, 4, 20)),
              symptomResponseFixture(occurredOn: Date(2026, 5, 3)),
            ],
          ),
        ),
      );

      await repo.createBatch(
        entries: [
          _draft(occurredAt: DateTime.utc(2026, 4, 20, 8)),
          _draft(occurredAt: DateTime.utc(2026, 5, 3, 8)),
        ],
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(
        invalidated,
        unorderedEquals(<String>[
          'GET:/cycle/day/2026-04-20',
          'GET:/symptoms?day=2026-04-20',
          'GET:/cycle/calendar?month=2026-04',
          'GET:/cycle/day/2026-05-03',
          'GET:/symptoms?day=2026-05-03',
          'GET:/cycle/calendar?month=2026-05',
        ]),
      );
    });

    test('a response item with a null occurredOn is a loud ServerFailure — '
        'never a silently-skipped day', () async {
      // Built directly, NOT via symptomResponseFixture: that fixture's
      // `occurredOn` parameter follows this file's usual `?? default`
      // convention, so passing it an explicit `null` still yields the
      // default date — there is no way to ask it for a genuinely-null
      // occurredOn. This one pathological wire shape (illegal under the
      // contract's own `DateOnly`, but the generated Dart model allows it)
      // needs the builder directly.
      final malformed = SymptomResponse(
        (b) => b
          ..id = 'symptom-abc123'
          ..symptomCode = 'bloating'
          ..intensity = 3
          ..region = 'lower_abdomen'
          ..occurredAt = DateTime.utc(2026, 4, 20, 8)
          ..createdAt = DateTime.utc(2026, 4, 20, 8)
          ..updatedAt = DateTime.utc(2026, 4, 20, 8),
        // occurredOn left UNSET — null on the built model.
      );

      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        apiSuccess(createSymptomsResponseFixture(items: [malformed])),
      );

      await expectLater(
        repo.createBatch(entries: [_draft()]),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a response with no items list is a loud ServerFailure', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiSuccess(CreateSymptomsResponse((b) => b)));

      await expectLater(
        repo.createBatch(entries: [_draft()]),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a 201 with no body at all is a typed ServerFailure', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<CreateSymptomsResponse>(
          requestOptions: RequestOptions(path: '/symptoms'),
          statusCode: 201,
        ),
      );

      await expectLater(
        repo.createBatch(entries: [_draft()]),
        throwsA(isA<ServerFailure>()),
      );
    });

    // ── Ambiguous-failure invalidation (item 3 / S-6) ───────────────────

    test('a NetworkFailure invalidates every distinct CLIENT-SUPPLIED '
        'occurredAt in the batch, then rethrows — the server may have already '
        'committed before the response was lost', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiNetworkFailure());

      final failure = await repo
          .createBatch(
            entries: [
              _draft(occurredAt: DateTime.utc(2026, 4, 20, 8)),
              _draft(occurredAt: DateTime.utc(2026, 5, 3, 8)),
            ],
          )
          .then<Object?>((v) => v, onError: (Object e) => e);

      expect(failure, isA<NetworkFailure>());
      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(
        invalidated,
        unorderedEquals(<String>[
          'GET:/cycle/day/2026-04-20',
          'GET:/symptoms?day=2026-04-20',
          'GET:/cycle/calendar?month=2026-04',
          'GET:/cycle/day/2026-05-03',
          'GET:/symptoms?day=2026-05-03',
          'GET:/cycle/calendar?month=2026-05',
        ]),
      );
    });

    test('a real 400 (validated BEFORE anything is written) invalidates '
        'NOTHING — the positive control proving the ambiguity test actually '
        'discriminates', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: {
            'entries[0].intensity': ['value must be between 0 and 10'],
          },
        ),
      );

      final failure = await repo
          .createBatch(
            entries: [_draft(occurredAt: DateTime.utc(2026, 4, 20, 8))],
          )
          .then<Object?>((v) => v, onError: (Object e) => e);

      expect(failure, isA<ValidationFailure>());
      verifyNever(() => store.invalidate(any()));
    });

    test('an entry whose occurredAt is null contributes NO key to the '
        'ambiguous-failure fallback — a documented gap, never a device-clock '
        'guess (D-12)', () async {
      when(
        () => api.symptomsPost(
          createSymptomsRequest: any(named: 'createSymptomsRequest'),
        ),
      ).thenAnswer(apiNetworkFailure());

      final failure = await repo
          .createBatch(entries: [_draft(occurredAt: null)])
          .then<Object?>((v) => v, onError: (Object e) => e);

      expect(failure, isA<NetworkFailure>());
      verifyNever(() => store.invalidate(any()));
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
