//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'hormone_selection.g.dart';

/// HormoneSelection
///
/// Properties:
/// * [charted] 
/// * [code] 
@BuiltValue()
abstract class HormoneSelection implements Built<HormoneSelection, HormoneSelectionBuilder> {
  @BuiltValueField(wireName: r'charted')
  bool? get charted;

  @BuiltValueField(wireName: r'code')
  String? get code;

  HormoneSelection._();

  factory HormoneSelection([void updates(HormoneSelectionBuilder b)]) = _$HormoneSelection;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HormoneSelectionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HormoneSelection> get serializer => _$HormoneSelectionSerializer();
}

class _$HormoneSelectionSerializer implements PrimitiveSerializer<HormoneSelection> {
  @override
  final Iterable<Type> types = const [HormoneSelection, _$HormoneSelection];

  @override
  final String wireName = r'HormoneSelection';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HormoneSelection object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.charted != null) {
      yield r'charted';
      yield serializers.serialize(
        object.charted,
        specifiedType: const FullType(bool),
      );
    }
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    HormoneSelection object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HormoneSelectionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'charted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.charted = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.code = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HormoneSelection deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HormoneSelectionBuilder();
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

