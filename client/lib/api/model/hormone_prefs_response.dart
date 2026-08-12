//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/hormone_selection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'hormone_prefs_response.g.dart';

/// HormonePrefsResponse
///
/// Properties:
/// * [hormones] 
@BuiltValue()
abstract class HormonePrefsResponse implements Built<HormonePrefsResponse, HormonePrefsResponseBuilder> {
  @BuiltValueField(wireName: r'hormones')
  BuiltList<HormoneSelection>? get hormones;

  HormonePrefsResponse._();

  factory HormonePrefsResponse([void updates(HormonePrefsResponseBuilder b)]) = _$HormonePrefsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HormonePrefsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HormonePrefsResponse> get serializer => _$HormonePrefsResponseSerializer();
}

class _$HormonePrefsResponseSerializer implements PrimitiveSerializer<HormonePrefsResponse> {
  @override
  final Iterable<Type> types = const [HormonePrefsResponse, _$HormonePrefsResponse];

  @override
  final String wireName = r'HormonePrefsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HormonePrefsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.hormones != null) {
      yield r'hormones';
      yield serializers.serialize(
        object.hormones,
        specifiedType: const FullType.nullable(BuiltList, [FullType(HormoneSelection)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    HormonePrefsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HormonePrefsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'hormones':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(HormoneSelection)]),
          ) as BuiltList<HormoneSelection>?;
          if (valueDes == null) continue;
          result.hormones.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HormonePrefsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HormonePrefsResponseBuilder();
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

