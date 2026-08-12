//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/phase_override_boundary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'phase_overrides_response.g.dart';

/// PhaseOverridesResponse
///
/// Properties:
/// * [boundaries] 
/// * [cycleStartOn] 
@BuiltValue()
abstract class PhaseOverridesResponse implements Built<PhaseOverridesResponse, PhaseOverridesResponseBuilder> {
  @BuiltValueField(wireName: r'boundaries')
  BuiltList<PhaseOverrideBoundary>? get boundaries;

  @BuiltValueField(wireName: r'cycleStartOn')
  Date? get cycleStartOn;

  PhaseOverridesResponse._();

  factory PhaseOverridesResponse([void updates(PhaseOverridesResponseBuilder b)]) = _$PhaseOverridesResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhaseOverridesResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhaseOverridesResponse> get serializer => _$PhaseOverridesResponseSerializer();
}

class _$PhaseOverridesResponseSerializer implements PrimitiveSerializer<PhaseOverridesResponse> {
  @override
  final Iterable<Type> types = const [PhaseOverridesResponse, _$PhaseOverridesResponse];

  @override
  final String wireName = r'PhaseOverridesResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhaseOverridesResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.boundaries != null) {
      yield r'boundaries';
      yield serializers.serialize(
        object.boundaries,
        specifiedType: const FullType.nullable(BuiltList, [FullType(PhaseOverrideBoundary)]),
      );
    }
    if (object.cycleStartOn != null) {
      yield r'cycleStartOn';
      yield serializers.serialize(
        object.cycleStartOn,
        specifiedType: const FullType(Date),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PhaseOverridesResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PhaseOverridesResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'boundaries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(PhaseOverrideBoundary)]),
          ) as BuiltList<PhaseOverrideBoundary>?;
          if (valueDes == null) continue;
          result.boundaries.replace(valueDes);
          break;
        case r'cycleStartOn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.cycleStartOn = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhaseOverridesResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhaseOverridesResponseBuilder();
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

