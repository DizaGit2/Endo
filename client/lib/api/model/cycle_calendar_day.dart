//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cycle_calendar_day.g.dart';

/// CycleCalendarDay
///
/// Properties:
/// * [date] 
/// * [eventCount] 
/// * [hasNotes] 
/// * [mood] 
/// * [pain] 
/// * [symptomCount] 
@BuiltValue()
abstract class CycleCalendarDay implements Built<CycleCalendarDay, CycleCalendarDayBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'eventCount')
  int? get eventCount;

  @BuiltValueField(wireName: r'hasNotes')
  bool? get hasNotes;

  @BuiltValueField(wireName: r'mood')
  int? get mood;

  @BuiltValueField(wireName: r'pain')
  int? get pain;

  @BuiltValueField(wireName: r'symptomCount')
  int? get symptomCount;

  CycleCalendarDay._();

  factory CycleCalendarDay([void updates(CycleCalendarDayBuilder b)]) = _$CycleCalendarDay;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CycleCalendarDayBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CycleCalendarDay> get serializer => _$CycleCalendarDaySerializer();
}

class _$CycleCalendarDaySerializer implements PrimitiveSerializer<CycleCalendarDay> {
  @override
  final Iterable<Type> types = const [CycleCalendarDay, _$CycleCalendarDay];

  @override
  final String wireName = r'CycleCalendarDay';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CycleCalendarDay object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(Date),
      );
    }
    if (object.eventCount != null) {
      yield r'eventCount';
      yield serializers.serialize(
        object.eventCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.hasNotes != null) {
      yield r'hasNotes';
      yield serializers.serialize(
        object.hasNotes,
        specifiedType: const FullType(bool),
      );
    }
    if (object.mood != null) {
      yield r'mood';
      yield serializers.serialize(
        object.mood,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.pain != null) {
      yield r'pain';
      yield serializers.serialize(
        object.pain,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.symptomCount != null) {
      yield r'symptomCount';
      yield serializers.serialize(
        object.symptomCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CycleCalendarDay object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CycleCalendarDayBuilder result,
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
        case r'eventCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.eventCount = valueDes;
          break;
        case r'hasNotes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasNotes = valueDes;
          break;
        case r'mood':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.mood = valueDes;
          break;
        case r'pain':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.pain = valueDes;
          break;
        case r'symptomCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.symptomCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CycleCalendarDay deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CycleCalendarDayBuilder();
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

