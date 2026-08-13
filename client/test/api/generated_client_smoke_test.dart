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
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/serializers.dart';
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

  // P4a-T21. The cycle calendar reports phase availability, and P4a always
  // answers `available: false, unavailableReason: "phase_engine_not_implemented"`
  // (§G6 — P4a ships zero clinical inference). When P6 lands the phase engine the
  // server flips to `available: true, unavailableReason: null`.
  //
  // That transition only works if the client can OBSERVE an explicit null. A
  // schema-level `default` on `unavailableReason` would become a built_value
  // BUILDER default, and the generated deserializer skips explicit nulls
  // (`if (valueDes == null) continue;`) — so the builder default would survive
  // and the client would keep reporting the P4a reason forever. T13's
  // `[DefaultValue]` was removed for exactly this reason and T20 added a backend
  // contract guard; these are the client-side half of that guard.
  group('CyclePhaseAvailabilityResponse — unavailableReason stays observable', () {
    test('the builder defaults `available` but leaves `unavailableReason` unset', () {
      final builder = CyclePhaseAvailabilityResponseBuilder();

      // `available` carries `"default": false` in the contract, so a builder
      // default here is expected and harmless (the field is non-nullable).
      expect(builder.available, isFalse);

      // `unavailableReason` must NOT have one. If this ever fails, the contract
      // grew a `default` for it and P6 can no longer clear the reason.
      expect(
        builder.unavailableReason,
        isNull,
        reason: 'a builder default would make an explicit null unobservable',
      );
    });

    test('P4a shape: the unavailable reason is carried through', () {
      final phase = standardSerializers.deserializeWith(
        CyclePhaseAvailabilityResponse.serializer,
        <String, dynamic>{
          'available': false,
          'unavailableReason': 'phase_engine_not_implemented',
        },
      )!;

      expect(phase.available, isFalse);
      expect(phase.unavailableReason, 'phase_engine_not_implemented');
    });

    test('P6 shape: an explicit null unavailableReason deserializes to null', () {
      final phase = standardSerializers.deserializeWith(
        CyclePhaseAvailabilityResponse.serializer,
        <String, dynamic>{'available': true, 'unavailableReason': null},
      )!;

      expect(phase.available, isTrue);
      expect(phase.unavailableReason, isNull);
    });

    test('nested in a calendar payload, an explicit null still survives', () {
      final calendar = standardSerializers.deserializeWith(
        CycleCalendarResponse.serializer,
        <String, dynamic>{
          'from': '2026-08-01',
          'to': '2026-08-03',
          'today': '2026-08-03',
          'timezone': 'America/Santiago',
          'phase': <String, dynamic>{
            'available': true,
            'unavailableReason': null,
          },
          'days': <dynamic>[
            <String, dynamic>{
              'date': '2026-08-01',
              'eventCount': 1,
              'symptomCount': 2,
              'hasNotes': true,
              'pain': 0,
              'mood': null,
            },
          ],
        },
      )!;

      expect(calendar.phase?.available, isTrue);
      expect(calendar.phase?.unavailableReason, isNull);

      // §G6: no day row carries a phase, cycleDay or confidence key — the
      // generated model has no such fields to read. `pain: 0` is a valid datum
      // (D-08), so it must not be conflated with absent.
      expect(calendar.days, hasLength(1));
      expect(calendar.days!.first.pain, 0);
      expect(calendar.days!.first.mood, isNull);
      expect(calendar.days!.first.date.toString(), '2026-08-01');
    });
  });
}
