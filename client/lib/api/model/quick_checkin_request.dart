//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'quick_checkin_request.g.dart';

/// QuickCheckinRequest
///
/// Properties:
/// * [mood] 
/// * [pain] 
@BuiltValue()
abstract class QuickCheckinRequest implements Built<QuickCheckinRequest, QuickCheckinRequestBuilder> {
  @BuiltValueField(wireName: r'mood')
  int? get mood;

  @BuiltValueField(wireName: r'pain')
  int? get pain;

  QuickCheckinRequest._();

  factory QuickCheckinRequest([void updates(QuickCheckinRequestBuilder b)]) = _$QuickCheckinRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(QuickCheckinRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<QuickCheckinRequest> get serializer => _$QuickCheckinRequestSerializer();
}

class _$QuickCheckinRequestSerializer implements PrimitiveSerializer<QuickCheckinRequest> {
  @override
  final Iterable<Type> types = const [QuickCheckinRequest, _$QuickCheckinRequest];

  @override
  final String wireName = r'QuickCheckinRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    QuickCheckinRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    QuickCheckinRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required QuickCheckinRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  QuickCheckinRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = QuickCheckinRequestBuilder();
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

