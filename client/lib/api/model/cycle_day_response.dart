//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/phase_override_boundary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cycle_day_response.g.dart';

/// CycleDayResponse
///
/// Properties:
/// * [date] 
/// * [events] 
/// * [log] 
/// * [phaseOverrides] 
@BuiltValue()
abstract class CycleDayResponse implements Built<CycleDayResponse, CycleDayResponseBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'events')
  BuiltList<CycleEventResponse>? get events;

  @BuiltValueField(wireName: r'log')
  CycleDayLogResponse? get log;

  @BuiltValueField(wireName: r'phaseOverrides')
  BuiltList<PhaseOverrideBoundary>? get phaseOverrides;

  CycleDayResponse._();

  factory CycleDayResponse([void updates(CycleDayResponseBuilder b)]) = _$CycleDayResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CycleDayResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CycleDayResponse> get serializer => _$CycleDayResponseSerializer();
}

class _$CycleDayResponseSerializer implements PrimitiveSerializer<CycleDayResponse> {
  @override
  final Iterable<Type> types = const [CycleDayResponse, _$CycleDayResponse];

  @override
  final String wireName = r'CycleDayResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CycleDayResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(Date),
      );
    }
    if (object.events != null) {
      yield r'events';
      yield serializers.serialize(
        object.events,
        specifiedType: const FullType.nullable(BuiltList, [FullType(CycleEventResponse)]),
      );
    }
    if (object.log != null) {
      yield r'log';
      yield serializers.serialize(
        object.log,
        specifiedType: const FullType(CycleDayLogResponse),
      );
    }
    if (object.phaseOverrides != null) {
      yield r'phaseOverrides';
      yield serializers.serialize(
        object.phaseOverrides,
        specifiedType: const FullType.nullable(BuiltList, [FullType(PhaseOverrideBoundary)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CycleDayResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CycleDayResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.date = valueDes;
          break;
        case r'events':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(CycleEventResponse)]),
          ) as BuiltList<CycleEventResponse>?;
          if (valueDes == null) continue;
          result.events.replace(valueDes);
          break;
        case r'log':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CycleDayLogResponse),
          ) as CycleDayLogResponse;
          result.log.replace(valueDes);
          break;
        case r'phaseOverrides':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(PhaseOverrideBoundary)]),
          ) as BuiltList<PhaseOverrideBoundary>?;
          if (valueDes == null) continue;
          result.phaseOverrides.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CycleDayResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CycleDayResponseBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

