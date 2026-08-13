//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'phase_override_boundary.g.dart';

/// PhaseOverrideBoundary
///
/// Properties:
/// * [boundary] 
/// * [occurredOn] 
/// * [phase] 
@BuiltValue()
abstract class PhaseOverrideBoundary implements Built<PhaseOverrideBoundary, PhaseOverrideBoundaryBuilder> {
  @BuiltValueField(wireName: r'boundary')
  String? get boundary;

  @BuiltValueField(wireName: r'occurredOn')
  Date? get occurredOn;

  @BuiltValueField(wireName: r'phase')
  String? get phase;

  PhaseOverrideBoundary._();

  factory PhaseOverrideBoundary([void updates(PhaseOverrideBoundaryBuilder b)]) = _$PhaseOverrideBoundary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhaseOverrideBoundaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhaseOverrideBoundary> get serializer => _$PhaseOverrideBoundarySerializer();
}

class _$PhaseOverrideBoundarySerializer implements PrimitiveSerializer<PhaseOverrideBoundary> {
  @override
  final Iterable<Type> types = const [PhaseOverrideBoundary, _$PhaseOverrideBoundary];

  @override
  final String wireName = r'PhaseOverrideBoundary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhaseOverrideBoundary object, {
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
        specifiedType: const FullType(Date),
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
    PhaseOverrideBoundary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PhaseOverrideBoundaryBuilder result,
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
            specifiedType: const FullType(Date),
          ) as Date;
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
  PhaseOverrideBoundary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhaseOverrideBoundaryBuilder();
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

