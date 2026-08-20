// CheckinRepository — `POST /checkin/quick` (P4b-T18).
//
// TDD (RED first). This is the layer the anti-fabrication rules bite at: the
// generated QuickCheckinRequest serializer OMITS a null member from the wire
// (`quick_checkin_request.dart:47,:54`), so the only way "not touched" can be
// represented correctly is to leave the builder field UNSET — and the only
// way to PROVE that from a test is to serialize the captured request and
// inspect the wire map, never `request.pain == null` (a null Dart value and
// an omitted wire key are two different facts; asserting the first does not
// prove the second).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/quick_checkin_request.dart';
import 'package:lumen/api/model/quick_checkin_response.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/checkin/data/checkin_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const _fallbackDay = 'GET:/cycle/day/2026-04-20';
const _fallbackMonth = 'GET:/cycle/calendar?month=2026-04';
const _fallbackSymptoms = 'GET:/symptoms?day=2026-04-20';
final _fallbackKeys = <String>[_fallbackDay, _fallbackSymptoms, _fallbackMonth];

const _responseDay = 'GET:/cycle/day/2026-04-21';
const _responseMonth = 'GET:/cycle/calendar?month=2026-04';
const _responseSymptoms = 'GET:/symptoms?day=2026-04-21';
final _responseKeys = <String>[_responseDay, _responseSymptoms, _responseMonth];

QuickCheckinRequest _capturedRequest(MockLumenApiApi api) {
  return verify(
        () => api.checkinQuickPost(
          quickCheckinRequest: captureAny(named: 'quickCheckinRequest'),
        ),
      ).captured.last
      as QuickCheckinRequest;
}

/// [request] serialized exactly as it would go on the wire — the level at
/// which "not touched" (omitted) and "touched and cleared/zero" (present)
/// actually differ. Asserting `request.pain == null` would NOT distinguish
/// "never set" from "set to null", because both read back as `null` off the
/// SAME built_value object; only the serialized shape does.
Map<String, dynamic> _wireMap(QuickCheckinRequest request) {
  final encoded = standardSerializers.serializeWith(
    QuickCheckinRequest.serializer,
    request,
  );
  return json.decode(json.encode(encoded)) as Map<String, dynamic>;
}

DioException _timeout() => DioException(
  requestOptions: RequestOptions(path: '/checkin/quick'),
  type: DioExceptionType.connectionError,
);

void main() {
  late MockLumenApiApi api;
  late MockCacheStore store;
  late CheckinRepository repo;

  setUpAll(() {
    registerFallbackValue(QuickCheckinRequest((b) => b..pain = 0));
  });

  setUp(() {
    api = MockLumenApiApi();
    store = emptyCacheStore();
    repo = CheckinRepository(api: api, store: store);
  });

  // -------------------------------------------------------------------------
  // Rule 1 — never send a field the user did not touch (payload proof)
  // -------------------------------------------------------------------------

  group('touched-only serialization — asserted on the WIRE PAYLOAD', () {
    // Fix round 1, I-2. Every OTHER test in this group pairs an untouched
    // field with a NULL value, which cannot tell "sends what the caller
    // says was touched" apart from "sends whatever is non-null" — deleting
    // either `if (touched…)` guard in `checkin_repository.dart` and
    // replacing it with an unconditional assignment leaves every one of
    // those tests green, because `b.pain = null` and "never touched b.pain"
    // produce the IDENTICAL wire shape either way. These two tests pair a
    // NON-NULL value with `touched…: false`, which is the one shape that
    // actually distinguishes the two: only the EXPLICIT flag, never the
    // value's nullness, may decide what is sent.
    test('pain=7 with touchedPain:false is OMITTED — the wire decision is '
        'driven by the touched FLAG, never by whether the value is '
        'non-null', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(QuickCheckinResponse((b) => b..mood = 2)));

      await repo.quickCheckin(
        pain: 7,
        mood: 2,
        touchedPain: false,
        touchedMood: true,
        fallbackDay: DateTime(2026, 4, 20),
      );

      final wire = _wireMap(_capturedRequest(api));
      expect(
        wire.containsKey('pain'),
        isFalse,
        reason:
            'pain=7 was never touched — an unconditional `b.pain = '
            'pain;` would send it despite this flag, and only THIS test '
            '(non-null value, untouched flag) can catch that regression',
      );
      expect(wire['mood'], 2);
    });

    test('mood=3 with touchedMood:false is OMITTED — the mood mirror of '
        'the pain test above', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(QuickCheckinResponse((b) => b..pain = 5)));

      await repo.quickCheckin(
        pain: 5,
        mood: 3,
        touchedPain: true,
        touchedMood: false,
        fallbackDay: DateTime(2026, 4, 20),
      );

      final wire = _wireMap(_capturedRequest(api));
      expect(wire['pain'], 5);
      expect(
        wire.containsKey('mood'),
        isFalse,
        reason:
            'mood=3 was never touched — an unconditional `b.mood = '
            'mood;` would send it despite this flag',
      );
    });

    test('an untouched pain field is ABSENT from the serialised JSON — '
        'touching only mood', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(QuickCheckinResponse((b) => b..mood = 3)));

      await repo.quickCheckin(
        pain: null,
        mood: 3,
        touchedPain: false,
        touchedMood: true,
        fallbackDay: DateTime(2026, 4, 20),
      );

      final wire = _wireMap(_capturedRequest(api));
      expect(
        wire.containsKey('pain'),
        isFalse,
        reason:
            'pain was never touched; sending it (even as null) would '
            'fabricate a datum the user never entered',
      );
      expect(wire['mood'], 3);
    });

    test('an untouched mood field is ABSENT from the serialised JSON — '
        'touching only pain', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(QuickCheckinResponse((b) => b..pain = 4)));

      await repo.quickCheckin(
        pain: 4,
        mood: null,
        touchedPain: true,
        touchedMood: false,
        fallbackDay: DateTime(2026, 4, 20),
      );

      final wire = _wireMap(_capturedRequest(api));
      expect(wire['pain'], 4);
      expect(wire.containsKey('mood'), isFalse);
    });

    test('pain: 0 IS sent when the user actually touched and chose 0 — 0 is '
        'a real datum (D-08), never conflated with "not touched"', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(QuickCheckinResponse((b) => b..pain = 0)));

      await repo.quickCheckin(
        pain: 0,
        mood: null,
        touchedPain: true,
        touchedMood: false,
        fallbackDay: DateTime(2026, 4, 20),
      );

      final wire = _wireMap(_capturedRequest(api));
      expect(
        wire.containsKey('pain'),
        isTrue,
        reason:
            'pain WAS touched — 0 must be sent, not silently dropped '
            'for being falsy',
      );
      expect(wire['pain'], 0);
    });

    test('both touched sends both', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(
        apiSuccess(
          QuickCheckinResponse(
            (b) => b
              ..pain = 2
              ..mood = 1,
          ),
        ),
      );

      await repo.quickCheckin(
        pain: 2,
        mood: 1,
        touchedPain: true,
        touchedMood: true,
        fallbackDay: DateTime(2026, 4, 20),
      );

      final wire = _wireMap(_capturedRequest(api));
      expect(wire['pain'], 2);
      expect(wire['mood'], 1);
    });

    test('neither touched sends an empty body — both keys absent', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(QuickCheckinResponse((b) => b)));

      await repo.quickCheckin(
        pain: null,
        mood: null,
        touchedPain: false,
        touchedMood: false,
        fallbackDay: DateTime(2026, 4, 20),
      );

      final wire = _wireMap(_capturedRequest(api));
      expect(wire.containsKey('pain'), isFalse);
      expect(wire.containsKey('mood'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Invalidation — the RESPONSE's day, not the fallback
  // -------------------------------------------------------------------------

  group('invalidation uses the RESPONSE\'s own day', () {
    test('a fixture whose response day differs from fallbackDay proves the '
        'RESPONSE day is what gets invalidated', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(
        apiSuccess(
          QuickCheckinResponse(
            (b) => b
              ..pain = 4
              ..day = Date(2026, 4, 21), // one day AHEAD of fallbackDay
          ),
        ),
      );

      await repo.quickCheckin(
        pain: 4,
        mood: null,
        touchedPain: true,
        touchedMood: false,
        fallbackDay: DateTime(2026, 4, 20), // the pinned sessionToday
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(
        invalidated,
        unorderedEquals(_responseKeys),
        reason:
            'must invalidate the RESPONSE day (the 21st), not the '
            'pinned fallback day (the 20th) — a month-boundary write would '
            'otherwise be invisible',
      );
    });

    test('falls back to fallbackDay when the response omits `day`', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(QuickCheckinResponse((b) => b..pain = 4)));

      await repo.quickCheckin(
        pain: 4,
        mood: null,
        touchedPain: true,
        touchedMood: false,
        fallbackDay: DateTime(2026, 4, 20),
      );

      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(invalidated, unorderedEquals(_fallbackKeys));
    });
  });

  // -------------------------------------------------------------------------
  // Ambiguous failure — S-6 (adapted) and the L3 escape
  // -------------------------------------------------------------------------

  group('an ambiguous write failure still invalidates — over-invalidation is '
      'safe, under-invalidation ships a stale cache silently', () {
    test('a network timeout (may have committed server-side) invalidates '
        'fallbackDay before rethrowing', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer((_) async => throw _timeout());

      Object? thrown;
      await repo
          .quickCheckin(
            pain: 5,
            mood: null,
            touchedPain: true,
            touchedMood: false,
            fallbackDay: DateTime(2026, 4, 20),
          )
          .then<void>((_) {}, onError: (Object e) => thrown = e);

      expect(thrown, isA<NetworkFailure>());
      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(invalidated, unorderedEquals(_fallbackKeys));
    });

    test('a malformed 200 (empty body) throws a typed Failure INSIDE the '
        'write closure — this escapes cachedWrite\'s own `on DioException` '
        'catch entirely (cached_query.dart:214), and this repository must '
        'still invalidate before the failure reaches the caller', () async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<QuickCheckinResponse>(
          requestOptions: RequestOptions(path: '/checkin/quick'),
          statusCode: 200,
        ),
      );

      Object? thrown;
      await repo
          .quickCheckin(
            pain: 5,
            mood: null,
            touchedPain: true,
            touchedMood: false,
            fallbackDay: DateTime(2026, 4, 20),
          )
          .then<void>((_) {}, onError: (Object e) => thrown = e);

      expect(thrown, isA<ServerFailure>());
      final invalidated = verify(() => store.invalidate(captureAny())).captured;
      expect(
        invalidated,
        unorderedEquals(_fallbackKeys),
        reason:
            'the empty-body guard throws INSIDE write(), bypassing '
            'cachedWrite\'s DioException-only catch — a repository that '
            'copied that guard without a broader catch of its own would '
            'invalidate NOTHING here, exactly the L3 gap the survey named',
      );
    });

    test(
      'a genuine validation rejection (nothing stored) ALSO invalidates '
      '— harmless over-invalidation, never a silent under-invalidation',
      () async {
        when(
          () => api.checkinQuickPost(
            quickCheckinRequest: any(named: 'quickCheckinRequest'),
          ),
        ).thenAnswer(
          apiValidationProblem(
            fields: {
              'request': ['at least one of pain or mood is required'],
            },
          ),
        );

        Object? thrown;
        await repo
            .quickCheckin(
              pain: null,
              mood: null,
              touchedPain: false,
              touchedMood: false,
              fallbackDay: DateTime(2026, 4, 20),
            )
            .then<void>((_) {}, onError: (Object e) => thrown = e);

        expect(thrown, isA<ValidationFailure>());
        verify(() => store.invalidate(any())).called(_fallbackKeys.length);
      },
    );
  });

  // -------------------------------------------------------------------------
  // A successful write DOES invalidate — the positive control for all of the
  // above "invalidates nothing on X" reasoning being meaningful
  // -------------------------------------------------------------------------

  test('a successful write returns the server\'s response and invalidates '
      'exactly its day\'s three keys, no more, no fewer', () async {
    when(
      () => api.checkinQuickPost(
        quickCheckinRequest: any(named: 'quickCheckinRequest'),
      ),
    ).thenAnswer(
      apiSuccess(
        QuickCheckinResponse(
          (b) => b
            ..pain = 4
            ..mood = 2
            ..day = Date(2026, 4, 20),
        ),
      ),
    );

    final response = await repo.quickCheckin(
      pain: 4,
      mood: 2,
      touchedPain: true,
      touchedMood: true,
      fallbackDay: DateTime(2026, 4, 20),
    );

    expect(response.pain, 4);
    expect(response.mood, 2);
    final invalidated = verify(() => store.invalidate(captureAny())).captured;
    expect(invalidated, unorderedEquals(_fallbackKeys));
  });
}
