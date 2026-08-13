//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/goal_selection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'goals_response.g.dart';

/// GoalsResponse
///
/// Properties:
/// * [goals] 
@BuiltValue()
abstract class GoalsResponse implements Built<GoalsResponse, GoalsResponseBuilder> {
  @BuiltValueField(wireName: r'goals')
  BuiltList<GoalSelection>? get goals;

  GoalsResponse._();

  factory GoalsResponse([void updates(GoalsResponseBuilder b)]) = _$GoalsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GoalsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GoalsResponse> get serializer => _$GoalsResponseSerializer();
}

class _$GoalsResponseSerializer implements PrimitiveSerializer<GoalsResponse> {
  @override
  final Iterable<Type> types = const [GoalsResponse, _$GoalsResponse];

  @override
  final String wireName = r'GoalsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GoalsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.goals != null) {
      yield r'goals';
      yield serializers.serialize(
        object.goals,
        specifiedType: const FullType.nullable(BuiltList, [FullType(GoalSelection)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GoalsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GoalsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'goals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(GoalSelection)]),
          ) as BuiltList<GoalSelection>?;
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
  GoalsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GoalsResponseBuilder();
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

