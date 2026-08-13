//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'phase_override_input.g.dart';

/// PhaseOverrideInput
///
/// Properties:
/// * [boundary] 
/// * [occurredOn] 
/// * [phase] 
@BuiltValue()
abstract class PhaseOverrideInput implements Built<PhaseOverrideInput, PhaseOverrideInputBuilder> {
  @BuiltValueField(wireName: r'boundary')
  String? get boundary;

  @BuiltValueField(wireName: r'occurredOn')
  Date? get occurredOn;

  @BuiltValueField(wireName: r'phase')
  String? get phase;

  PhaseOverrideInput._();

  factory PhaseOverrideInput([void updates(PhaseOverrideInputBuilder b)]) = _$PhaseOverrideInput;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhaseOverrideInputBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhaseOverrideInput> get serializer => _$PhaseOverrideInputSerializer();
}

class _$PhaseOverrideInputSerializer implements PrimitiveSerializer<PhaseOverrideInput> {
  @override
  final Iterable<Type> types = const [PhaseOverrideInput, _$PhaseOverrideInput];

  @override
  final String wireName = r'PhaseOverrideInput';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhaseOverrideInput object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.boundary != null) {
      yield r'boundary';
      yield serializers.serialize(
        object.boundary,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.occurredOn != null) {
      yield r'occurredOn';
      yield serializers.serialize(
        object.occurredOn,
        specifiedType: const FullType.nullable(Date),
      );
    }
    if (object.phase != null) {
      yield r'phase';
      yield serializers.serialize(
        object.phase,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PhaseOverrideInput object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PhaseOverrideInputBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'boundary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.boundary = valueDes;
          break;
        case r'occurredOn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.occurredOn = valueDes;
          break;
        case r'phase':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.phase = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhaseOverrideInput deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhaseOverrideInputBuilder();
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

