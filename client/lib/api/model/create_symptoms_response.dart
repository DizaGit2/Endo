//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/symptom_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_symptoms_response.g.dart';

/// CreateSymptomsResponse
///
/// Properties:
/// * [items] 
@BuiltValue()
abstract class CreateSymptomsResponse implements Built<CreateSymptomsResponse, CreateSymptomsResponseBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<SymptomResponse>? get items;

  CreateSymptomsResponse._();

  factory CreateSymptomsResponse([void updates(CreateSymptomsResponseBuilder b)]) = _$CreateSymptomsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateSymptomsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateSymptomsResponse> get serializer => _$CreateSymptomsResponseSerializer();
}

class _$CreateSymptomsResponseSerializer implements PrimitiveSerializer<CreateSymptomsResponse> {
  @override
  final Iterable<Type> types = const [CreateSymptomsResponse, _$CreateSymptomsResponse];

  @override
  final String wireName = r'CreateSymptomsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateSymptomsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.items != null) {
      yield r'items';
      yield serializers.serialize(
        object.items,
        specifiedType: const FullType.nullable(BuiltList, [FullType(SymptomResponse)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateSymptomsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateSymptomsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(SymptomResponse)]),
          ) as BuiltList<SymptomResponse>?;
          if (valueDes == null) continue;
          result.items.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateSymptomsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateSymptomsResponseBuilder();
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

