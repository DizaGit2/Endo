//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'replace_symptom_request.g.dart';

/// ReplaceSymptomRequest
///
/// Properties:
/// * [intensity] 
/// * [notes] 
/// * [occurredAt] 
/// * [painTypes] 
/// * [region] 
/// * [side] 
/// * [triggers] 
@BuiltValue()
abstract class ReplaceSymptomRequest implements Built<ReplaceSymptomRequest, ReplaceSymptomRequestBuilder> {
  @BuiltValueField(wireName: r'intensity')
  int? get intensity;

  @BuiltValueField(wireName: r'notes')
  String? get notes;

  @BuiltValueField(wireName: r'occurredAt')
  DateTime? get occurredAt;

  @BuiltValueField(wireName: r'painTypes')
  BuiltList<String>? get painTypes;

  @BuiltValueField(wireName: r'region')
  String? get region;

  @BuiltValueField(wireName: r'side')
  String? get side;

  @BuiltValueField(wireName: r'triggers')
  BuiltList<String>? get triggers;

  ReplaceSymptomRequest._();

  factory ReplaceSymptomRequest([void updates(ReplaceSymptomRequestBuilder b)]) = _$ReplaceSymptomRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReplaceSymptomRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReplaceSymptomRequest> get serializer => _$ReplaceSymptomRequestSerializer();
}

class _$ReplaceSymptomRequestSerializer implements PrimitiveSerializer<ReplaceSymptomRequest> {
  @override
  final Iterable<Type> types = const [ReplaceSymptomRequest, _$ReplaceSymptomRequest];

  @override
  final String wireName = r'ReplaceSymptomRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReplaceSymptomRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.intensity != null) {
      yield r'intensity';
      yield serializers.serialize(
        object.intensity,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.occurredAt != null) {
      yield r'occurredAt';
      yield serializers.serialize(
        object.occurredAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    if (object.painTypes != null) {
      yield r'painTypes';
      yield serializers.serialize(
        object.painTypes,
        specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
      );
    }
    if (object.region != null) {
      yield r'region';
      yield serializers.serialize(
        object.region,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.side != null) {
      yield r'side';
      yield serializers.serialize(
        object.side,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.triggers != null) {
      yield r'triggers';
      yield serializers.serialize(
        object.triggers,
        specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReplaceSymptomRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReplaceSymptomRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'intensity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.intensity = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.notes = valueDes;
          break;
        case r'occurredAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.occurredAt = valueDes;
          break;
        case r'painTypes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.painTypes.replace(valueDes);
          break;
        case r'region':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.region = valueDes;
          break;
        case r'side':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.side = valueDes;
          break;
        case r'triggers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.triggers.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReplaceSymptomRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReplaceSymptomRequestBuilder();
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

