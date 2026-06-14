// Smoke test for the generated OpenAPI client (P3a-T8).
//
// Proves the dio + built_value client generated into lib/api/ integrates with the
// app: the entry class wires a Dio, the typed API surface is reachable, and a
// built_value model round-trips through the generated serializers. This guards the
// generated client's compilation and basic wiring, not live HTTP behaviour.

import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:lumen/api/api.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generated lumen API client', () {
    test('Lumen entry wires a Dio and exposes the typed API', () {
      final api = Lumen(basePathOverride: 'https://example.test');

      expect(api.dio, isA<Dio>());
      expect(api.dio.options.baseUrl, 'https://example.test');
      expect(api.serializers, isA<Serializers>());
      expect(api.getLumenApiApi(), isA<LumenApiApi>());
    });

    test('MeResponse builds via built_value and round-trips through serializers', () {
      final me = MeResponse(
        (b) => b
          ..id = '11111111-1111-1111-1111-111111111111'
          ..displayName = 'Ada'
          ..onboardingCompleted = true,
      );

      expect(me.id, '11111111-1111-1111-1111-111111111111');
      expect(me.displayName, 'Ada');
      expect(me.onboardingCompleted, isTrue);

      final serializers = Lumen().serializers;
      final wire = serializers.serializeWith(MeResponse.serializer, me);
      final back = serializers.deserializeWith(MeResponse.serializer, wire);

      expect(back, equals(me));
    });
  });
}
