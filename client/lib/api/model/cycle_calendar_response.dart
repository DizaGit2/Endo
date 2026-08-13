//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cycle_calendar_response.g.dart';

/// CycleCalendarResponse
///
/// Properties:
/// * [days] 
/// * [from] 
/// * [phase] 
/// * [timezone] 
/// * [to] 
/// * [today] 
@BuiltValue()
abstract class CycleCalendarResponse implements Built<CycleCalendarResponse, CycleCalendarResponseBuilder> {
  @BuiltValueField(wireName: r'days')
  BuiltList<CycleCalendarDay>? get days;

  @BuiltValueField(wireName: r'from')
  Date? get from;

  @BuiltValueField(wireName: r'phase')
  CyclePhaseAvailabilityResponse? get phase;

  @BuiltValueField(wireName: r'timezone')
  String? get timezone;

  @BuiltValueField(wireName: r'to')
  Date? get to;

  @BuiltValueField(wireName: r'today')
  Date? get today;

  CycleCalendarResponse._();

  factory CycleCalendarResponse([void updates(CycleCalendarResponseBuilder b)]) = _$CycleCalendarResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CycleCalendarResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CycleCalendarResponse> get serializer => _$CycleCalendarResponseSerializer();
}

class _$CycleCalendarResponseSerializer implements PrimitiveSerializer<CycleCalendarResponse> {
  @override
  final Iterable<Type> types = const [CycleCalendarResponse, _$CycleCalendarResponse];

  @override
  final String wireName = r'CycleCalendarResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CycleCalendarResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.days != null) {
      yield r'days';
      yield serializers.serialize(
        object.days,
        specifiedType: const FullType.nullable(BuiltList, [FullType(CycleCalendarDay)]),
      );
    }
    if (object.from != null) {
      yield r'from';
      yield serializers.serialize(
        object.from,
        specifiedType: const FullType(Date),
      );
    }
    if (object.phase != null) {
      yield r'phase';
      yield serializers.serialize(
        object.phase,
        specifiedType: const FullType(CyclePhaseAvailabilityResponse),
      );
    }
    if (object.timezone != null) {
      yield r'timezone';
      yield serializers.serialize(
        object.timezone,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.to != null) {
      yield r'to';
      yield serializers.serialize(
        object.to,
        specifiedType: const FullType(Date),
      );
    }
    if (object.today != null) {
      yield r'today';
      yield serializers.serialize(
        object.today,
        specifiedType: const FullType(Date),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CycleCalendarResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CycleCalendarResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'days':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(CycleCalendarDay)]),
          ) as BuiltList<CycleCalendarDay>?;
          if (valueDes == null) continue;
          result.days.replace(valueDes);
          break;
        case r'from':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.from = valueDes;
          break;
        case r'phase':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CyclePhaseAvailabilityResponse),
          ) as CyclePhaseAvailabilityResponse;
          result.phase.replace(valueDes);
          break;
        case r'timezone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.timezone = valueDes;
          break;
        case r'to':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.to = valueDes;
          break;
        case r'today':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.today = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CycleCalendarResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CycleCalendarResponseBuilder();
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

