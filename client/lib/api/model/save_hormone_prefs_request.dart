//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'save_hormone_prefs_request.g.dart';

/// SaveHormonePrefsRequest
///
/// Properties:
/// * [chartedHormones] 
@BuiltValue()
abstract class SaveHormonePrefsRequest implements Built<SaveHormonePrefsRequest, SaveHormonePrefsRequestBuilder> {
  @BuiltValueField(wireName: r'chartedHormones')
  BuiltList<String>? get chartedHormones;

  SaveHormonePrefsRequest._();

  factory SaveHormonePrefsRequest([void updates(SaveHormonePrefsRequestBuilder b)]) = _$SaveHormonePrefsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SaveHormonePrefsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SaveHormonePrefsRequest> get serializer => _$SaveHormonePrefsRequestSerializer();
}

class _$SaveHormonePrefsRequestSerializer implements PrimitiveSerializer<SaveHormonePrefsRequest> {
  @override
  final Iterable<Type> types = const [SaveHormonePrefsRequest, _$SaveHormonePrefsRequest];

  @override
  final String wireName = r'SaveHormonePrefsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SaveHormonePrefsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.chartedHormones != null) {
      yield r'chartedHormones';
      yield serializers.serialize(
        object.chartedHormones,
        specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SaveHormonePrefsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SaveHormonePrefsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'chartedHormones':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.chartedHormones.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SaveHormonePrefsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SaveHormonePrefsRequestBuilder();
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

