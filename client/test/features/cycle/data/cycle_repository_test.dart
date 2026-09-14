// CycleRepository — the calendar/day reads and the events write/delete
// (P4b-T14).
//
// The one write worth being careful about is `POST /cycle/events`: it is a
// FULL UPSERT (`ARCHITECTURE.md` §C.0.1) — an omitted `flowIntensity` or
// `notes` is CLEARED, not left alone. `logEvent` makes all four wire fields
// `required` named parameters (two non-nullable, two nullable-but-required),
// so a call site that does not mention `flowIntensity`/`notes` fails to
// COMPILE — there is no runtime path that "forgets" one. What these tests
// pin instead is the other half: that an explicit `null` really does travel
// as an OMITTED field on the wire (proving the clearing mechanism actually
// works the way §C.0.1 describes), and that every write's invalidation set
// comes from `CacheKeys.keysForDate` — the same derivation every other P4b
// write uses — rather than being hand-rolled here.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_day_response.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/log_cycle_day_request.dart';
import 'package:lumen/api/model/log_cycle_event_request.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/cycle/data/cycle_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// The exact strings this repository must file its reads and invalidations
/// under, written out rather than read back from [CacheKeys] — comparing to
/// the policy constant would pass for any pair of values that moved
/// together, including the wrong one.
const _dayKey = 'GET:/cycle/day/2026-04-20';
const _monthKey = 'GET:/cycle/calendar?month=2026-04';
const _symptomsDayKey = 'GET:/symptoms?day=2026-04-20';
const _threeDateKeys = <String>[_dayKey, _symptomsDayKey, _monthKey];

/// The captured request the repository actually put on the wire.
LogCycleEventRequest _capturedEventRequest(MockLumenApiApi api) {
  return verify(
        () => api.cycleEventsPost(
          logCycleEventRequest: captureAny(named: 'logCycleEventRequest'),
        ),
      ).captured.last
      as LogCycleEventRequest;
}

/// [request], serialized exactly as it would go on the wire — the level at
/// which "omitted" vs "explicit null" actually differ. `built_value` drops a
/// null member from its own serialized form (see every generated
/// `_serializeProperties`, `if (object.x != null) yield …`), so a field
/// missing from this map is the proof a null field is OMITTED, not sent as
/// `"field": null`.
Map<String, dynamic> _wireMap(LogCycleEventRequest request) {
  final encoded = standardSerializers.serializeWith(
    LogCycleEventRequest.serializer,
    request,
  );
  return json.decode(json.encode(encoded)) as Map<String, dynamic>;
}

/// The captured `POST /cycle/day/{date}` body the repository put on the wire.
LogCycleDayRequest _capturedDayRequest(MockLumenApiApi api) {
  return verify(
        () => api.cycleDayDatePost(
          date: any(named: 'date'),
          logCycleDayRequest: captureAny(named: 'logCycleDayRequest'),
        ),
      ).captured.last
      as LogCycleDayRequest;
}

/// [request], serialized exactly as it would go on the wire.
///
/// The whole day-log touched-flag design is only observable HERE: a field the
/// caller did not touch must be **missing from this map**, because absence is
/// what the MERGE endpoint reads as "leave the stored value alone"
/// (`CycleDayService.MergeScales` assigns only `if (pain is { } value)`).
Map<String, dynamic> _wireDayMap(LogCycleDayRequest request) {
  final encoded = standardSerializers.serializeWith(
    LogCycleDayRequest.serializer,
    request,
  );
  return json.decode(json.encode(encoded)) as Map<String, dynamic>;
}

DioException _notFound404({String path = '/cycle/events/evt-1'}) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<void>(requestOptions: options, statusCode: 404),
  );
}

void main() {
  late MockLumenApiApi api;
  late MockCacheStore store;
  late CycleRepository repo;

  setUpAll(() {
    registerFallbackValue(Date(2026, 1, 1));
    registerFallbackValue(
      LogCycleEventRequest(
        (b) => b
          ..kind = 'period_start'
          ..occurredOn = Date(2026, 1, 1),
      ),
    );
    registerFallbackValue(LogCycleDayRequest((b) => b..pain = 1));
  });

  setUp(() {
    api = MockLumenApiApi();
    store = emptyCacheStore();
    repo = CycleRepository(api: api, store: store);
  });

  // -------------------------------------------------------------------------
  // GET /cycle/calendar — month-bucketed
  // -------------------------------------------------------------------------

  group('getCalendarMonth', () {
    test(
      'requests the exact inclusive window CacheKeys.monthWindow derives, '
      'and files the response under the month bucket at the shared TTL',
      () async {
        when(
          () => api.cycleCalendarGet(
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer(apiSuccess(cycleCalendarFixture()));

        await repo.getCalendarMonth(DateTime(2026, 4, 15));

        final captured = verify(
          () => api.cycleCalendarGet(
            from: captureAny(named: 'from'),
            to: captureAny(named: 'to'),
          ),
        ).captured;
        expect(captured, <Object?>[Date(2026, 4, 1), Date(2026, 4, 30)]);
        verify(
          () => store.putJson(_monthKey, any(), ttl: CacheKeys.ttl),
        ).called(1);
      },
    );

    test('a December window does not roll into next year, and is keyed under '
        'ITS OWN month — the rollover CacheKeys.monthWindow exists to get '
        'right, wired through rather than re-derived here', () async {
      when(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(apiSuccess(cycleCalendarFixture()));

      await repo.getCalendarMonth(DateTime(2026, 12, 3));

      final captured = verify(
        () => api.cycleCalendarGet(
          from: captureAny(named: 'from'),
          to: captureAny(named: 'to'),
        ),
      ).captured;
      expect(captured, <Object?>[Date(2026, 12, 1), Date(2026, 12, 31)]);
      verify(
        () => store.putJson(
          'GET:/cycle/calendar?month=2026-12',
          any(),
          ttl: CacheKeys.ttl,
        ),
      ).called(1);
    });

    test('serves a fresh cache entry without touching the network', () async {
      when(() => store.isFresh(_monthKey)).thenReturn(true);
      when(
        () => store.getJson(_monthKey),
      ).thenReturn(<String, dynamic>{'today': '2026-04-20'});
      when(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(apiSuccess(cycleCalendarFixture()));

      final cached = await repo.getCalendarMonth(DateTime(2026, 4, 20));

      expect(cached, isA<Fresh<CycleCalendarResponse>>());
      verifyNever(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      );

      // Positive control: the same mock DOES answer once the entry goes
      // stale — the verifyNever above is a fact about the short-circuit.
      when(() => store.isFresh(_monthKey)).thenReturn(false);
      await repo.getCalendarMonth(DateTime(2026, 4, 20));
      verify(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).called(1);
    });

    test('falls back to Stale when offline with a cached value, and reports '
        'NetworkRequired when there is neither', () async {
      when(
        () => store.getJson(_monthKey),
      ).thenReturn(<String, dynamic>{'today': '2026-04-20'});
      when(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(apiNetworkFailure<CycleCalendarResponse>());

      final stale = await repo.getCalendarMonth(DateTime(2026, 4, 20));
      expect(stale, isA<Stale<CycleCalendarResponse>>());

      when(() => store.getJson(_monthKey)).thenReturn(null);
      final required = await repo.getCalendarMonth(DateTime(2026, 4, 20));
      expect(required, isA<NetworkRequired<CycleCalendarResponse>>());
      expect(
        (required as NetworkRequired<CycleCalendarResponse>).failure,
        isA<NetworkFailure>(),
      );
    });

    test('the sparse days list and its nested Date fields survive a cache '
        'round trip', () async {
      Map<String, dynamic>? written;
      when(
        () => store.putJson(any(), any(), ttl: any(named: 'ttl')),
      ).thenAnswer((invocation) async {
        written = invocation.positionalArguments[1] as Map<String, dynamic>;
      });
      when(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        apiSuccess(
          cycleCalendarFixture(
            days: [
              cycleCalendarDayFixture(date: Date(2026, 4, 3), pain: 4),
              // D-08: pain 0 is a REAL logged datum, not "no data" — distinct
              // from pain: null. T15 keys its calendar marker dot off
              // `pain != null`, so a round trip that coerced 0 to null would
              // silently hide a day the user did log.
              cycleCalendarDayFixture(date: Date(2026, 4, 10), pain: 0),
              cycleCalendarDayFixture(date: Date(2026, 4, 20), pain: 1),
            ],
          ),
        ),
      );

      await repo.getCalendarMonth(DateTime(2026, 4, 20));
      expect(written, isNotNull, reason: 'premise: the read wrote through');

      when(() => store.isFresh(_monthKey)).thenReturn(true);
      when(() => store.getJson(_monthKey)).thenReturn(written);

      final cached =
          await repo.getCalendarMonth(DateTime(2026, 4, 20))
              as Fresh<CycleCalendarResponse>;

      expect(cached.value.days, hasLength(3));
      expect(cached.value.days!.first.date, Date(2026, 4, 3));
      expect(cached.value.days!.first.pain, 4);
      expect(cached.value.days![1].date, Date(2026, 4, 10));
      expect(
        cached.value.days![1].pain,
        0,
        reason: 'pain: 0 must survive as 0, never as null',
      );
      expect(cached.value.days!.last.date, Date(2026, 4, 20));
    });

    test('a 200 with no body is a typed server failure — surfaced as '
        'NetworkRequired with no cache to fall back on, since cachedRead '
        'treats a ServerFailure like a transient one (§4.1)', () async {
      when(
        () => api.cycleCalendarGet(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => Response<CycleCalendarResponse>(
          requestOptions: RequestOptions(path: '/cycle/calendar'),
          statusCode: 200,
        ),
      );

      final result = await repo.getCalendarMonth(DateTime(2026, 4, 20));

      expect(result, isA<NetworkRequired<CycleCalendarResponse>>());
      expect(
        (result as NetworkRequired<CycleCalendarResponse>).failure,
        isA<ServerFailure>(),
      );
    });
  });

  // -------------------------------------------------------------------------
  // GET /cycle/day/{date}
  // -------------------------------------------------------------------------

  group('getDay', () {
    test('requests the exact date and files under the day key', () async {
      when(
        () => api.cycleDayDateGet(date: any(named: 'date')),
      ).thenAnswer(apiSuccess(cycleDayFixture()));

      await repo.getDay(DateTime(2026, 4, 20));

      verify(() => api.cycleDayDateGet(date: Date(2026, 4, 20))).called(1);
      verify(() => store.putJson(_dayKey, any(), ttl: CacheKeys.ttl)).called(1);
    });

    test(
      'an empty day — log: null — is a normal Fresh result, not an error',
      () async {
        when(
          () => api.cycleDayDateGet(date: any(named: 'date')),
        ).thenAnswer(apiSuccess(cycleDayFixture()));

        final empty =
            await repo.getDay(DateTime(2026, 4, 20)) as Fresh<CycleDayResponse>;
        expect(empty.value.log, isNull);

        // Positive control: a day WITH a log survives identically in shape —
        // `log: null` is not being masked as an error, it is one legitimate
        // value among others.
        when(() => store.isFresh(_dayKey)).thenReturn(false);
        when(() => api.cycleDayDateGet(date: any(named: 'date'))).thenAnswer(
          apiSuccess(
            cycleDayFixture(log: cycleDayLogFixture(pain: 6, mood: 2)),
          ),
        );
        final logged =
            await repo.getDay(DateTime(2026, 4, 20)) as Fresh<CycleDayResponse>;
        expect(logged.value.log, isNotNull);
        expect(logged.value.log!.pain, 6);
      },
    );

    test('falls back to Stale when offline with a cached value, and reports '
        'NetworkRequired when there is neither', () async {
      when(
        () => store.getJson(_dayKey),
      ).thenReturn(<String, dynamic>{'date': '2026-04-20'});
      when(
        () => api.cycleDayDateGet(date: any(named: 'date')),
      ).thenAnswer(apiNetworkFailure<CycleDayResponse>());

      final stale = await repo.getDay(DateTime(2026, 4, 20));
      expect(stale, isA<Stale<CycleDayResponse>>());

      when(() => store.getJson(_dayKey)).thenReturn(null);
      final required = await repo.getDay(DateTime(2026, 4, 20));
      expect(required, isA<NetworkRequired<CycleDayResponse>>());
    });

    test('the log and events lists, and their nested Date/DateTime fields, '
        'survive a cache round trip', () async {
      Map<String, dynamic>? written;
      when(
        () => store.putJson(any(), any(), ttl: any(named: 'ttl')),
      ).thenAnswer((invocation) async {
        written = invocation.positionalArguments[1] as Map<String, dynamic>;
      });
      when(() => api.cycleDayDateGet(date: any(named: 'date'))).thenAnswer(
        apiSuccess(
          cycleDayFixture(
            log: cycleDayLogFixture(pain: 5, notes: 'cramping'),
            events: [
              cycleEventFixture(
                id: 'evt-1',
                occurredOn: Date(2026, 4, 20),
                flowIntensity: 3,
              ),
            ],
          ),
        ),
      );

      await repo.getDay(DateTime(2026, 4, 20));
      expect(written, isNotNull, reason: 'premise: the read wrote through');

      when(() => store.isFresh(_dayKey)).thenReturn(true);
      when(() => store.getJson(_dayKey)).thenReturn(written);

      final cached =
          await repo.getDay(DateTime(2026, 4, 20)) as Fresh<CycleDayResponse>;

      // Nullity asserted BEFORE any force-unwrap: a `!` on a null value is a
      // raw Dart crash (an uncaught `TypeError`, not a `TestFailure`), which
      // would make a deserialisation regression here an out-of-contract red
      // instead of a clean matcher failure.
      final log = cached.value.log;
      expect(log, isNotNull, reason: 'the log must survive the round trip');
      expect(log!.pain, 5);
      expect(log.notes, 'cramping');

      expect(cached.value.events, hasLength(1));
      final events = cached.value.events;
      expect(events!.first.occurredOn, Date(2026, 4, 20));
      expect(events.first.flowIntensity, 3);
    });

    test('a 200 with no body is a typed server failure — surfaced as '
        'NetworkRequired with no cache to fall back on, since cachedRead '
        'treats a ServerFailure like a transient one (§4.1)', () async {
      when(() => api.cycleDayDateGet(date: any(named: 'date'))).thenAnswer(
        (_) async => Response<CycleDayResponse>(
          requestOptions: RequestOptions(path: '/cycle/day/2026-04-20'),
          statusCode: 200,
        ),
      );

      final result = await repo.getDay(DateTime(2026, 4, 20));

      expect(result, isA<NetworkRequired<CycleDayResponse>>());
      expect(
        (result as NetworkRequired<CycleDayResponse>).failure,
        isA<ServerFailure>(),
      );
    });
  });

  // -------------------------------------------------------------------------
  // POST /cycle/events — FULL UPSERT
  // -------------------------------------------------------------------------

  group('logEvent', () {
    test('sends kind/occurredOn/flowIntensity/notes exactly as given, and an '
        'explicit null OMITS the field from the wire rather than sending an '
        'explicit null value', () async {
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(apiSuccess(cycleEventFixture()));

      await repo.logEvent(
        kind: 'period_start',
        occurredOn: Date(2026, 4, 20),
        flowIntensity: null,
        notes: null,
      );

      final wire = _wireMap(_capturedEventRequest(api));
      expect(wire['kind'], 'period_start');
      expect(wire['occurredOn'], '2026-04-20');
      expect(
        wire.containsKey('flowIntensity'),
        isFalse,
        reason:
            'an explicit null must be OMITTED, not sent as null — '
            'that omission is what the server reads as CLEAR',
      );
      expect(wire.containsKey('notes'), isFalse);
    });

    test('a caller that re-hydrated the row sends the EXISTING flowIntensity '
        'and notes back, preserving them on the wire', () async {
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(apiSuccess(cycleEventFixture()));

      await repo.logEvent(
        kind: 'period_start',
        occurredOn: Date(2026, 4, 20),
        flowIntensity: 3,
        notes: 'heavy cramping',
      );

      final wire = _wireMap(_capturedEventRequest(api));
      expect(wire['flowIntensity'], 3);
      expect(wire['notes'], 'heavy cramping');
    });

    test('invalidates exactly the three date-derived keys for occurredOn — '
        "T4's CacheKeys.keysForDate, not a hand-picked subset", () async {
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(apiSuccess(cycleEventFixture()));

      await repo.logEvent(
        kind: 'period_start',
        occurredOn: Date(2026, 4, 20),
        flowIntensity: null,
        notes: null,
      );

      // One capture, so "exactly these three" is one assertion rather than
      // per-key `verify`s (which would each consume the interaction and
      // make a trailing total-count check find nothing left to match).
      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(invalidated, unorderedEquals(_threeDateKeys));
    });

    test('a rejected write invalidates nothing', () async {
      // Positive control first: the SAME store IS shown invalidating on a
      // successful write, in the SAME test — "invalidates nothing" is also
      // true of a store nobody ever calls.
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(apiSuccess(cycleEventFixture()));
      await repo.logEvent(
        kind: 'period_start',
        occurredOn: Date(2026, 4, 20),
        flowIntensity: null,
        notes: null,
      );
      verify(() => store.invalidate(any())).called(_threeDateKeys.length);

      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: {
            'occurredOn': ['date is before the earliest allowed date'],
          },
        ),
      );

      await expectLater(
        repo.logEvent(
          kind: 'period_start',
          occurredOn: Date(2020, 1, 1),
          flowIntensity: null,
          notes: null,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      verifyNever(() => store.invalidate(any()));
    });

    test('a 400 arrives as a ValidationFailure keyed by field', () async {
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: {
            'flowIntensity': ['value must be between 1 and 4'],
          },
        ),
      );

      final failure = await repo
          .logEvent(
            kind: 'period_start',
            occurredOn: Date(2026, 4, 20),
            flowIntensity: 9,
            notes: null,
          )
          .then<Object?>((value) => value, onError: (Object error) => error);

      expect(failure, isA<ValidationFailure>());
      expect(
        (failure! as ValidationFailure).messageFor('flowIntensity'),
        'value must be between 1 and 4',
      );
    });

    test('S-1 AT THE WIRE — an EMPTY note travels as `"notes": ""`, present '
        'and empty, and that is what ERASES the stored ciphertext. It is NOT '
        'quietly dropped on its way out: `CycleService` trims it, finds it '
        'empty, and assigns row.NotesEnc = null UNCONDITIONALLY. On '
        'POST /cycle/day/{date} the same value is a no-op; here it is the '
        'only way a user can remove a note.', () async {
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(apiSuccess(cycleEventFixture()));

      await repo.logEvent(
        kind: 'period_start',
        occurredOn: Date(2026, 4, 20),
        flowIntensity: 2,
        notes: '',
      );

      final wire = _wireMap(_capturedEventRequest(api));
      expect(
        wire.containsKey('notes'),
        isTrue,
        reason:
            'an empty string is a VALUE, not an omission — and the two are '
            'different requests even though the server clears on both',
      );
      expect(wire['notes'], '');
      expect(
        wire['flowIntensity'],
        2,
        reason: 'the other field is untouched by the note being emptied',
      );
    });

    // -- S-6 / S-7, retrofitted at P4b-T16c with the first caller ----------

    test('S-7 — the invalidation is keyed on the RESPONSE\'s own occurredOn, '
        'not on the date the caller asked for', () async {
      // The two are deliberately DIFFERENT here. They are identical in
      // production (the server echoes the request's own upsert key), so a
      // fixture that let them agree would make "keyed on the response" and
      // "keyed on the request" the same assertion — the false-green shape
      // this phase keeps finding.
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(
        apiSuccess(cycleEventFixture(occurredOn: Date(2026, 5, 9))),
      );

      await repo.logEvent(
        kind: 'period_start',
        occurredOn: Date(2026, 4, 20),
        flowIntensity: null,
        notes: null,
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(
        invalidated,
        containsAll(<String>[
          'GET:/cycle/day/2026-05-09',
          'GET:/symptoms?day=2026-05-09',
          'GET:/cycle/calendar?month=2026-05',
        ]),
        reason:
            'the row the server actually wrote is the one whose cached day '
            'is now wrong',
      );
      expect(
        invalidated,
        containsAll(_threeDateKeys),
        reason:
            'the requested day was showing this event a moment ago, so its '
            'keys are cleared too — the union, never one instead of the other',
      );
    });

    test('an AMBIGUOUS failure (the write may have committed) invalidates the '
        'requested day\'s three keys — S-6, through cachedWrite\'s own '
        'invalidateKeysOnAmbiguousFailure', () async {
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(apiNetworkFailure());

      await expectLater(
        repo.logEvent(
          kind: 'period_start',
          occurredOn: Date(2026, 4, 20),
          flowIntensity: 2,
          notes: 'a note',
        ),
        throwsA(isA<NetworkFailure>()),
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(invalidated, unorderedEquals(_threeDateKeys));
    });

    test('a 200 with no body is a typed server failure', () async {
      when(
        () => api.cycleEventsPost(
          logCycleEventRequest: any(named: 'logCycleEventRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<CycleEventResponse>(
          requestOptions: RequestOptions(path: '/cycle/events'),
          statusCode: 200,
        ),
      );

      await expectLater(
        repo.logEvent(
          kind: 'period_start',
          occurredOn: Date(2026, 4, 20),
          flowIntensity: null,
          notes: null,
        ),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // POST /cycle/day/{date} — MERGE (P4b-T16b)
  //
  // The OPPOSITE endpoint to `logEvent` above, and the whole reason this group
  // is written the way it is. `/cycle/events` clears by omission;
  // `/cycle/day/{date}` LEAVES ALONE by omission
  // (`CycleDayService.UpsertDayAsync` -> `MergeScales`, and the note column is
  // assigned only when the trimmed note is non-empty). So on THIS endpoint
  // "omit the field" is the safe answer, and the danger is sending a field the
  // user never touched.
  //
  // `touchedPain` / `touchedMood` / `touchedNotes` are therefore the ONLY
  // thing that decides what goes on the wire, and they are never re-derived
  // from whether the value happens to be null. The matrix below varies the two
  // inputs INDEPENDENTLY - untouched+null, untouched+set, touched+null,
  // touched+set - because a suite that only ever supplies "untouched AND null"
  // together cannot tell the guard from the serializer, and deleting either
  // one would leave it green (the defect P4b-T18's own review found).
  // -------------------------------------------------------------------------

  group('logDay', () {
    void stubDayPost({CycleDayLogResponse? body}) {
      when(
        () => api.cycleDayDatePost(
          date: any(named: 'date'),
          logCycleDayRequest: any(named: 'logCycleDayRequest'),
        ),
      ).thenAnswer(apiSuccess(body ?? cycleDayLogFixture()));
    }

    test('posts to the ROUTE date - the day is the path, never a body field '
        '(there is no `day`/`date` member on LogCycleDayRequest at all)', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: 4,
        mood: null,
        notes: null,
        touchedPain: true,
        touchedMood: false,
        touchedNotes: false,
      );

      // ONE verify: a second one would find the interaction already
      // consumed and fail with "No matching calls".
      final captured = verify(
        () => api.cycleDayDatePost(
          date: captureAny(named: 'date'),
          logCycleDayRequest: captureAny(named: 'logCycleDayRequest'),
        ),
      ).captured;
      expect(captured.first, Date(2026, 4, 20));

      final wire = _wireDayMap(captured.last as LogCycleDayRequest);
      expect(wire.keys, unorderedEquals(<String>['pain']));
    });

    // -- the touched-flag matrix, both inputs varied independently ----------

    test('UNTOUCHED + null - the field is absent from the wire', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: null,
        mood: null,
        notes: null,
        touchedPain: false,
        touchedMood: false,
        touchedNotes: true,
      );

      final wire = _wireDayMap(_capturedDayRequest(api));
      expect(wire.containsKey('pain'), isFalse);
      expect(wire.containsKey('mood'), isFalse);
    });

    test('UNTOUCHED + SET - the field is STILL absent. This is the case a '
        'guard re-derived from nullability (`if (pain != null)`) would get '
        'wrong, and it is the only case that can tell the two apart', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        // Values are present - a stale seed the user never edited - and must
        // not travel. This is S-2 dissolved: a stale rehydration that is
        // never SENT cannot be a lost update.
        pain: 8,
        mood: 2,
        notes: 'a note the user never touched',
        touchedPain: false,
        touchedMood: false,
        touchedNotes: false,
      );

      final wire = _wireDayMap(_capturedDayRequest(api));
      expect(
        wire,
        isEmpty,
        reason:
            'nothing was touched, so nothing may be asserted - every one of '
            'these three values would OVERWRITE newer server state',
      );
    });

    test('TOUCHED + null - the field is absent, and in particular is NOT '
        'defaulted to 0 (S-4: `pain: _pain ?? 0` would fabricate a real '
        '"none today" that D-08 makes permanently indistinguishable from a '
        'logged one)', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: null,
        mood: null,
        notes: 'something',
        touchedPain: true,
        touchedMood: true,
        touchedNotes: true,
      );

      final wire = _wireDayMap(_capturedDayRequest(api));
      expect(wire.containsKey('pain'), isFalse);
      expect(wire.containsKey('mood'), isFalse);
      expect(wire['pain'], isNot(0));
      expect(wire['mood'], isNot(0));
      expect(wire['notes'], 'something');
    });

    test('TOUCHED + SET - the field travels, and `pain: 0` travels as the '
        'integer 0 (D-08: 0 is a real datum that OVERWRITES a stored 8)', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: 0,
        mood: 1,
        notes: null,
        touchedPain: true,
        touchedMood: true,
        touchedNotes: false,
      );

      final wire = _wireDayMap(_capturedDayRequest(api));
      expect(wire['pain'], 0);
      expect(wire['mood'], 1);
      expect(wire.containsKey('notes'), isFalse);
    });

    test('the three flags are INDEPENDENT - touching only mood sends only '
        'mood, even when pain and notes hold values', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: 7,
        mood: 3,
        notes: 'kept',
        touchedPain: false,
        touchedMood: true,
        touchedNotes: false,
      );

      final wire = _wireDayMap(_capturedDayRequest(api));
      expect(wire.keys, unorderedEquals(<String>['mood']));
      expect(wire['mood'], 3);
    });

    test('S-1 - an EMPTY notes controller the user never touched does not '
        'send an empty string', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: 5,
        mood: null,
        notes: '',
        touchedPain: true,
        touchedMood: false,
        touchedNotes: false,
      );

      final wire = _wireDayMap(_capturedDayRequest(api));
      expect(wire.containsKey('notes'), isFalse);
      expect(wire['notes'], isNot(''));
    });

    test('a TOUCHED empty note is sent verbatim - the guard is the flag '
        'alone, never the value. (On THIS endpoint the server trims it to '
        'absent text and leaves the stored note alone; the same string on '
        '`/cycle/events` would destroy the ciphertext, which is why the two '
        'editors are separate tasks.)', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: 5,
        mood: null,
        notes: '',
        touchedPain: true,
        touchedMood: false,
        touchedNotes: true,
      );

      final wire = _wireDayMap(_capturedDayRequest(api));
      expect(wire['notes'], '');
    });

    // -- cache -------------------------------------------------------------

    test('invalidates exactly the three date-derived keys for the ROUTE date '
        'on success', () async {
      stubDayPost();

      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: 4,
        mood: null,
        notes: null,
        touchedPain: true,
        touchedMood: false,
        touchedNotes: false,
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(invalidated, unorderedEquals(_threeDateKeys));
    });

    test('an AMBIGUOUS failure (the write may have committed) invalidates '
        'the same three keys - S-6, closed with cachedWrite own '
        'invalidateKeysOnAmbiguousFailure rather than a hand-rolled catch',
        () async {
      when(
        () => api.cycleDayDatePost(
          date: any(named: 'date'),
          logCycleDayRequest: any(named: 'logCycleDayRequest'),
        ),
      ).thenAnswer(apiNetworkFailure());

      await expectLater(
        repo.logDay(
          date: DateTime(2026, 4, 20),
          pain: 4,
          mood: null,
          notes: null,
          touchedPain: true,
          touchedMood: false,
          touchedNotes: false,
        ),
        throwsA(isA<NetworkFailure>()),
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(invalidated, unorderedEquals(_threeDateKeys));
    });

    test('a 400 invalidates NOTHING - the server rejected before writing, so '
        'the cache is still correct', () async {
      // Positive control in the same test, on the same store.
      stubDayPost();
      await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: 4,
        mood: null,
        notes: null,
        touchedPain: true,
        touchedMood: false,
        touchedNotes: false,
      );
      verify(() => store.invalidate(any())).called(_threeDateKeys.length);

      when(
        () => api.cycleDayDatePost(
          date: any(named: 'date'),
          logCycleDayRequest: any(named: 'logCycleDayRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: {
            'request': ['at least one of pain, mood or notes is required'],
          },
        ),
      );

      await expectLater(
        repo.logDay(
          date: DateTime(2026, 4, 20),
          pain: null,
          mood: null,
          notes: '',
          touchedPain: true,
          touchedMood: false,
          touchedNotes: true,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      verifyNever(() => store.invalidate(any()));
    });

    // -- response ----------------------------------------------------------

    test('returns the 200 body - the STORED row, which carries fields this '
        'call never sent (a notes-only write comes back with the day existing '
        'pain and mood)', () async {
      stubDayPost(
        body: cycleDayLogFixture(pain: 8, mood: 2, notes: 'stored note'),
      );

      final saved = await repo.logDay(
        date: DateTime(2026, 4, 20),
        pain: null,
        mood: null,
        notes: 'stored note',
        touchedPain: false,
        touchedMood: false,
        touchedNotes: true,
      );

      expect(saved.pain, 8);
      expect(saved.mood, 2);
      expect(saved.notes, 'stored note');
    });

    test('a 400 arrives as a ValidationFailure keyed by field, including the '
        'cross-field `request` key the empty-body rule uses', () async {
      when(
        () => api.cycleDayDatePost(
          date: any(named: 'date'),
          logCycleDayRequest: any(named: 'logCycleDayRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem(
          fields: {
            'request': ['at least one of pain, mood or notes is required'],
            'date': ['date must not be in the future'],
          },
        ),
      );

      final failure = await repo
          .logDay(
            date: DateTime(2099, 4, 20),
            pain: 4,
            mood: null,
            notes: null,
            touchedPain: true,
            touchedMood: false,
            touchedNotes: false,
          )
          .then<Object?>((value) => value, onError: (Object error) => error);

      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).requestMessages, <String>[
        'at least one of pain, mood or notes is required',
      ]);
      expect(
        (failure as ValidationFailure).messageFor('date'),
        'date must not be in the future',
      );
    });

    test('a 200 with no body is a typed server failure', () async {
      when(
        () => api.cycleDayDatePost(
          date: any(named: 'date'),
          logCycleDayRequest: any(named: 'logCycleDayRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<CycleDayLogResponse>(
          requestOptions: RequestOptions(path: '/cycle/day/2026-04-20'),
          statusCode: 200,
        ),
      );

      await expectLater(
        repo.logDay(
          date: DateTime(2026, 4, 20),
          pain: 4,
          mood: null,
          notes: null,
          touchedPain: true,
          touchedMood: false,
          touchedNotes: false,
        ),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // DELETE /cycle/events/{id} — D-13 soft-delete
  // -------------------------------------------------------------------------

  group('deleteEvent', () {
    test(
      'deletes by id and invalidates occurredOn\'s keys on success',
      () async {
        when(() => api.cycleEventsIdDelete(id: any(named: 'id'))).thenAnswer(
          (_) async => Response<void>(
            requestOptions: RequestOptions(path: '/cycle/events/evt-1'),
            statusCode: 204,
          ),
        );

        await repo.deleteEvent(id: 'evt-1', occurredOn: Date(2026, 4, 20));

        verify(() => api.cycleEventsIdDelete(id: 'evt-1')).called(1);
        for (final key in _threeDateKeys) {
          verify(() => store.invalidate(key)).called(1);
        }
      },
    );

    test('a SECOND delete (404) is treated as success — and STILL invalidates '
        "occurredOn's keys, because cachedWrite does not invalidate on a "
        'thrown failure and this path must do it itself', () async {
      when(
        () => api.cycleEventsIdDelete(id: any(named: 'id')),
      ).thenAnswer((_) async => throw _notFound404());

      // Must NOT throw — D-13 treats a 404 on delete as success. Brought
      // in-contract per fix round 1, corrected in round 2. Neither
      // `expectLater(..., completes)` nor a bare `try/catch + fail()` is a
      // sanctioned route: `completes`/`completion` never catch a REJECTION
      // at all — `_Completes.matchAsync`
      // (package:matcher/src/expect/future_matchers.dart) does
      // `item.then((value) async {...})` with no `onError` arm, and
      // `AsyncMatcher.matches` (`async_matcher.dart`) does the same on the
      // result — so a rejected future is simply never given to the
      // matcher's own failure formatter. (It is NOT "unhandled" in the
      // zone-error sense: `await expectLater(...)` awaits the chain, and
      // that `await` rethrows the rejection directly into this test body —
      // the un-awaited `expect()` form is the one that would be a genuine
      // unhandled zone error. Either way nothing constructs a `TestFailure`,
      // which is what `isFailure` is keyed on —
      // `error is TestFailure`, `test_core/src/runner/reporter/json.dart:294`
      // — so both forms read `isFailure: false`.) `fail()` alone produces
      // `isFailure: true` but skips matcher's own failure formatter
      // entirely, so it carries no `Expected:`/`Actual:` block. None of this
      // makes `completes`/`completion` useless — `completes` still fails on
      // a non-`Future`, and `completion(m)` still fails a wrong VALUE. The
      // gap is narrow and specific: neither converts a REJECTION into a
      // `TestFailure`.
      //
      // The sanctioned shape: capture the rejection with `.then(onError:)`
      // — never letting it reject the awaited future at all — then assert
      // on the captured value with a real matcher, so `expect`'s own
      // formatter writes the `Expected:`/`Actual:` block.
      Object? thrown;
      await repo
          .deleteEvent(id: 'evt-1', occurredOn: Date(2026, 4, 20))
          .then<void>((_) {}, onError: (Object e) => thrown = e);
      expect(
        thrown,
        isNull,
        reason: 'D-13: a second (404) delete must be treated as success',
      );

      for (final key in _threeDateKeys) {
        verify(() => store.invalidate(key)).called(1);
      }
    });

    test('an AMBIGUOUS failure (the delete may have committed) STILL '
        'propagates, and invalidates occurredOn\'s three keys — S-6, '
        'retrofitted at P4b-T16c with the first caller', () async {
      when(
        () => api.cycleEventsIdDelete(id: any(named: 'id')),
      ).thenAnswer(apiNetworkFailure<void>());

      await expectLater(
        repo.deleteEvent(id: 'evt-1', occurredOn: Date(2026, 4, 20)),
        throwsA(isA<NetworkFailure>()),
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(
        invalidated,
        unorderedEquals(_threeDateKeys),
        reason:
            'a soft delete that committed and then timed out would otherwise '
            'leave the event on screen for the rest of the 5-minute TTL',
      );
    });

    test('a 5xx invalidates TOO and still throws — it is a [ServerFailure], '
        'so it takes the AMBIGUOUS branch, not the "any other failure" one '
        '(T16c fix round 1: the dartdoc for this method listed 5xx among '
        'the failures that invalidate nothing, which contradicted its own '
        'paragraph three lines up)', () async {
      // 503 through the problem+json archetype, the same idiom the 401 case
      // below uses: `mapDioException` sends every `500..599` to
      // [ServerFailure] regardless of the body, and
      // `cachedWrite._invalidateOnAmbiguousFailure` tests
      // `failure is! NetworkFailure && failure is! ServerFailure`.
      when(() => api.cycleEventsIdDelete(id: any(named: 'id'))).thenAnswer(
        apiValidationProblem<void>(
          statusCode: 503,
          title: 'Service Unavailable',
        ),
      );

      await expectLater(
        repo.deleteEvent(id: 'evt-1', occurredOn: Date(2026, 4, 20)),
        throwsA(isA<ServerFailure>()),
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(
        invalidated,
        unorderedEquals(_threeDateKeys),
        reason:
            'a 5xx on a soft delete is as ambiguous as a timeout — the row '
            'may already be gone, and a cache that still holds it shows the '
            'user an error over an event the server no longer has',
      );
    });

    test('a NON-ambiguous failure propagates and invalidates NOTHING — the '
        'positive control the network case above cannot be', () async {
      // A 401 is the sharpest available: the server is KNOWN not to have
      // deleted anything, so the cache is still correct. (This test used to
      // use a NetworkFailure; P4b-T16c's S-6 retrofit made that case
      // invalidate, which is the point of the test above.)
      when(() => api.cycleEventsIdDelete(id: any(named: 'id'))).thenAnswer(
        apiValidationProblem<void>(statusCode: 401, title: 'Unauthorized'),
      );

      await expectLater(
        repo.deleteEvent(id: 'evt-1', occurredOn: Date(2026, 4, 20)),
        throwsA(isA<Failure>()),
      );
      verifyNever(() => store.invalidate(any()));
    });
  });
}
