//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'goal_selection.g.dart';

/// GoalSelection
///
/// Properties:
/// * [code] 
/// * [selected] 
@BuiltValue()
abstract class GoalSelection implements Built<GoalSelection, GoalSelectionBuilder> {
  @BuiltValueField(wireName: r'code')
  String? get code;

  @BuiltValueField(wireName: r'selected')
  bool? get selected;

  GoalSelection._();

  factory GoalSelection([void updates(GoalSelectionBuilder b)]) = _$GoalSelection;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GoalSelectionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GoalSelection> get serializer => _$GoalSelectionSerializer();
}

class _$GoalSelectionSerializer implements PrimitiveSerializer<GoalSelection> {
  @override
  final Iterable<Type> types = const [GoalSelection, _$GoalSelection];

  @override
  final String wireName = r'GoalSelection';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GoalSelection object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.selected != null) {
      yield r'selected';
      yield serializers.serialize(
        object.selected,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GoalSelection object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GoalSelectionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.code = valueDes;
          break;
        case r'selected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.selected = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GoalSelection deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GoalSelectionBuilder();
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

