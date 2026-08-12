//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cycle_phase_availability_response.g.dart';

/// CyclePhaseAvailabilityResponse
///
/// Properties:
/// * [available] 
/// * [unavailableReason] 
@BuiltValue()
abstract class CyclePhaseAvailabilityResponse implements Built<CyclePhaseAvailabilityResponse, CyclePhaseAvailabilityResponseBuilder> {
  @BuiltValueField(wireName: r'available')
  bool? get available;

  @BuiltValueField(wireName: r'unavailableReason')
  String? get unavailableReason;

  CyclePhaseAvailabilityResponse._();

  factory CyclePhaseAvailabilityResponse([void updates(CyclePhaseAvailabilityResponseBuilder b)]) = _$CyclePhaseAvailabilityResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CyclePhaseAvailabilityResponseBuilder b) => b
      ..available = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<CyclePhaseAvailabilityResponse> get serializer => _$CyclePhaseAvailabilityResponseSerializer();
}

class _$CyclePhaseAvailabilityResponseSerializer implements PrimitiveSerializer<CyclePhaseAvailabilityResponse> {
  @override
  final Iterable<Type> types = const [CyclePhaseAvailabilityResponse, _$CyclePhaseAvailabilityResponse];

  @override
  final String wireName = r'CyclePhaseAvailabilityResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CyclePhaseAvailabilityResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.available != null) {
      yield r'available';
      yield serializers.serialize(
        object.available,
        specifiedType: const FullType(bool),
      );
    }
    if (object.unavailableReason != null) {
      yield r'unavailableReason';
      yield serializers.serialize(
        object.unavailableReason,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CyclePhaseAvailabilityResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CyclePhaseAvailabilityResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'available':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.available = valueDes;
          break;
        case r'unavailableReason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.unavailableReason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CyclePhaseAvailabilityResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CyclePhaseAvailabilityResponseBuilder();
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

