//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/phase_override_input.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'save_phase_overrides_request.g.dart';

/// SavePhaseOverridesRequest
///
/// Properties:
/// * [boundaries] 
/// * [cycleStartOn] 
@BuiltValue()
abstract class SavePhaseOverridesRequest implements Built<SavePhaseOverridesRequest, SavePhaseOverridesRequestBuilder> {
  @BuiltValueField(wireName: r'boundaries')
  BuiltList<PhaseOverrideInput>? get boundaries;

  @BuiltValueField(wireName: r'cycleStartOn')
  Date? get cycleStartOn;

  SavePhaseOverridesRequest._();

  factory SavePhaseOverridesRequest([void updates(SavePhaseOverridesRequestBuilder b)]) = _$SavePhaseOverridesRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SavePhaseOverridesRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SavePhaseOverridesRequest> get serializer => _$SavePhaseOverridesRequestSerializer();
}

class _$SavePhaseOverridesRequestSerializer implements PrimitiveSerializer<SavePhaseOverridesRequest> {
  @override
  final Iterable<Type> types = const [SavePhaseOverridesRequest, _$SavePhaseOverridesRequest];

  @override
  final String wireName = r'SavePhaseOverridesRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SavePhaseOverridesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.boundaries != null) {
      yield r'boundaries';
      yield serializers.serialize(
        object.boundaries,
        specifiedType: const FullType.nullable(BuiltList, [FullType(PhaseOverrideInput)]),
      );
    }
    if (object.cycleStartOn != null) {
      yield r'cycleStartOn';
      yield serializers.serialize(
        object.cycleStartOn,
        specifiedType: const FullType.nullable(Date),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SavePhaseOverridesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SavePhaseOverridesRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'boundaries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(PhaseOverrideInput)]),
          ) as BuiltList<PhaseOverrideInput>?;
          if (valueDes == null) continue;
          result.boundaries.replace(valueDes);
          break;
        case r'cycleStartOn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
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
  SavePhaseOverridesRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SavePhaseOverridesRequestBuilder();
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

