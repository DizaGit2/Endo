//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'quick_checkin_response.g.dart';

/// QuickCheckinResponse
///
/// Properties:
/// * [day] 
/// * [mood] 
/// * [pain] 
/// * [updatedAt] 
@BuiltValue()
abstract class QuickCheckinResponse implements Built<QuickCheckinResponse, QuickCheckinResponseBuilder> {
  @BuiltValueField(wireName: r'day')
  Date? get day;

  @BuiltValueField(wireName: r'mood')
  int? get mood;

  @BuiltValueField(wireName: r'pain')
  int? get pain;

  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  QuickCheckinResponse._();

  factory QuickCheckinResponse([void updates(QuickCheckinResponseBuilder b)]) = _$QuickCheckinResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(QuickCheckinResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<QuickCheckinResponse> get serializer => _$QuickCheckinResponseSerializer();
}

class _$QuickCheckinResponseSerializer implements PrimitiveSerializer<QuickCheckinResponse> {
  @override
  final Iterable<Type> types = const [QuickCheckinResponse, _$QuickCheckinResponse];

  @override
  final String wireName = r'QuickCheckinResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    QuickCheckinResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.day != null) {
      yield r'day';
      yield serializers.serialize(
        object.day,
        specifiedType: const FullType(Date),
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
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    QuickCheckinResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required QuickCheckinResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'day':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.day = valueDes;
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
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  QuickCheckinResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = QuickCheckinResponseBuilder();
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

