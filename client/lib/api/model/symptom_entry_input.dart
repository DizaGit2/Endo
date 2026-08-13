//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'symptom_entry_input.g.dart';

/// SymptomEntryInput
///
/// Properties:
/// * [intensity] 
/// * [notes] 
/// * [occurredAt] 
/// * [painTypes] 
/// * [region] 
/// * [side] 
/// * [symptomCode] 
/// * [triggers] 
@BuiltValue()
abstract class SymptomEntryInput implements Built<SymptomEntryInput, SymptomEntryInputBuilder> {
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

  @BuiltValueField(wireName: r'symptomCode')
  String? get symptomCode;

  @BuiltValueField(wireName: r'triggers')
  BuiltList<String>? get triggers;

  SymptomEntryInput._();

  factory SymptomEntryInput([void updates(SymptomEntryInputBuilder b)]) = _$SymptomEntryInput;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SymptomEntryInputBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SymptomEntryInput> get serializer => _$SymptomEntryInputSerializer();
}

class _$SymptomEntryInputSerializer implements PrimitiveSerializer<SymptomEntryInput> {
  @override
  final Iterable<Type> types = const [SymptomEntryInput, _$SymptomEntryInput];

  @override
  final String wireName = r'SymptomEntryInput';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SymptomEntryInput object, {
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
    if (object.symptomCode != null) {
      yield r'symptomCode';
      yield serializers.serialize(
        object.symptomCode,
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
    SymptomEntryInput object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SymptomEntryInputBuilder result,
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
        case r'symptomCode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.symptomCode = valueDes;
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
  SymptomEntryInput deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SymptomEntryInputBuilder();
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

