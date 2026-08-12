//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'save_goals_request.g.dart';

/// SaveGoalsRequest
///
/// Properties:
/// * [goals] 
@BuiltValue()
abstract class SaveGoalsRequest implements Built<SaveGoalsRequest, SaveGoalsRequestBuilder> {
  @BuiltValueField(wireName: r'goals')
  BuiltList<String>? get goals;

  SaveGoalsRequest._();

  factory SaveGoalsRequest([void updates(SaveGoalsRequestBuilder b)]) = _$SaveGoalsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SaveGoalsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SaveGoalsRequest> get serializer => _$SaveGoalsRequestSerializer();
}

class _$SaveGoalsRequestSerializer implements PrimitiveSerializer<SaveGoalsRequest> {
  @override
  final Iterable<Type> types = const [SaveGoalsRequest, _$SaveGoalsRequest];

  @override
  final String wireName = r'SaveGoalsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SaveGoalsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.goals != null) {
      yield r'goals';
      yield serializers.serialize(
        object.goals,
        specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SaveGoalsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SaveGoalsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'goals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.goals.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SaveGoalsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SaveGoalsRequestBuilder();
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

