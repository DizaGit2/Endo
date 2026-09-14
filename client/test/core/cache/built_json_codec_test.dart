// Direct tests for toCacheJson / fromCacheJson (core/cache/built_json_codec.dart),
// the two generic functions P4b-T14b collapsed six verbatim per-repository
// copies into. Every one of the six repository test suites already exercises
// these indirectly through a real cachedRead round trip; this file targets
// the functions themselves — a round trip, and the malformed-input behaviour
// the six original copies shared (an uncaught DeserializationError, not a
// null and not a swallowed failure).
//
// MeResponse is the vehicle: an ordinary generated built_value response type
// already used the same way in me_repository_test.dart, chosen only because
// every one of its fields is a plain scalar (String/Date/int/double/bool),
// which keeps the malformed-value case legible.

import 'dart:convert';

import 'package:built_value/serializer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/built_json_codec.dart';

MeResponse _sampleMe() {
  return MeResponse(
    (b) => b
      ..id = 'user-123'
      ..displayName = 'María'
      ..locale = 'es'
      ..timezone = 'Europe/Madrid'
      ..onboardingCompleted = true
      ..dob = Date(1990, 5, 12)
      ..heightCm = 165
      ..latestWeightKg = 61.5
      ..rasrmStage = 2
      ..endoStatus = 'diagnosed'
      ..diagnosedOn = '2020-03',
  );
}

void main() {
  group('toCacheJson / fromCacheJson', () {
    test('round-trips a built_value object through a JSON-safe map', () {
      final original = _sampleMe();

      final map = toCacheJson<MeResponse>(MeResponse.serializer, original);

      // JSON-safe: every value in the map must already be encodable as-is —
      // the whole reason the original six copies round-tripped through
      // json.encode/json.decode rather than returning serializeWith's result
      // directly (which can still carry non-JSON Dart types).
      expect(() => json.encode(map), returnsNormally);

      final decoded = fromCacheJson<MeResponse>(MeResponse.serializer, map);

      expect(decoded, equals(original));
      expect(decoded.id, 'user-123');
      expect(decoded.displayName, 'María');
      expect(decoded.dob, original.dob);
      expect(decoded.heightCm, 165);
      expect(decoded.latestWeightKg, 61.5);
      expect(decoded.onboardingCompleted, true);
    });

    test('a map missing every key decodes to an all-null object', () {
      // Every property MeResponse exposes is nullable (the OpenAPI generator
      // makes every field on every response type optional) — an absent key
      // is therefore not malformed input, it is simply "the server/cache
      // said nothing about this field", the same as a real omitted-field
      // response.
      final decoded = fromCacheJson<MeResponse>(
        MeResponse.serializer,
        <String, dynamic>{},
      );

      expect(decoded.id, isNull);
      expect(decoded.displayName, isNull);
      expect(decoded.onboardingCompleted, isNull);
    });

    test(
      'a value of the wrong wire type throws DeserializationError, uncaught',
      () {
        // onboardingCompleted is wired as a non-nullable bool once the key is
        // present at all (see me_response.g.dart's generated switch case) —
        // a String in its place is exactly the "malformed input" this
        // function's dartdoc describes: neither swallowed nor turned into a
        // null, but propagated as built_value's own DeserializationError.
        final malformed = <String, dynamic>{'onboardingCompleted': 'nope'};

        expect(
          () => fromCacheJson<MeResponse>(MeResponse.serializer, malformed),
          throwsA(isA<DeserializationError>()),
        );
      },
    );
  });
}
