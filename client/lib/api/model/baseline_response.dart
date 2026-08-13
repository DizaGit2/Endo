//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'baseline_response.g.dart';

/// BaselineResponse
///
/// Properties:
/// * [diagnosedOn] 
/// * [dob] 
/// * [endoStatus] 
/// * [heightCm] 
/// * [latestWeightKg] 
/// * [rasrmStage] 
@BuiltValue()
abstract class BaselineResponse implements Built<BaselineResponse, BaselineResponseBuilder> {
  @BuiltValueField(wireName: r'diagnosedOn')
  String? get diagnosedOn;

  @BuiltValueField(wireName: r'dob')
  Date? get dob;

  @BuiltValueField(wireName: r'endoStatus')
  String? get endoStatus;

  @BuiltValueField(wireName: r'heightCm')
  int? get heightCm;

  @BuiltValueField(wireName: r'latestWeightKg')
  double? get latestWeightKg;

  @BuiltValueField(wireName: r'rasrmStage')
  int? get rasrmStage;

  BaselineResponse._();

  factory BaselineResponse([void updates(BaselineResponseBuilder b)]) = _$BaselineResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BaselineResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BaselineResponse> get serializer => _$BaselineResponseSerializer();
}

class _$BaselineResponseSerializer implements PrimitiveSerializer<BaselineResponse> {
  @override
  final Iterable<Type> types = const [BaselineResponse, _$BaselineResponse];

  @override
  final String wireName = r'BaselineResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BaselineResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.diagnosedOn != null) {
      yield r'diagnosedOn';
      yield serializers.serialize(
        object.diagnosedOn,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.dob != null) {
      yield r'dob';
      yield serializers.serialize(
        object.dob,
        specifiedType: const FullType.nullable(Date),
      );
    }
    if (object.endoStatus != null) {
      yield r'endoStatus';
      yield serializers.serialize(
        object.endoStatus,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.heightCm != null) {
      yield r'heightCm';
      yield serializers.serialize(
        object.heightCm,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.latestWeightKg != null) {
      yield r'latestWeightKg';
      yield serializers.serialize(
        object.latestWeightKg,
        specifiedType: const FullType.nullable(double),
      );
    }
    if (object.rasrmStage != null) {
      yield r'rasrmStage';
      yield serializers.serialize(
        object.rasrmStage,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BaselineResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BaselineResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'diagnosedOn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.diagnosedOn = valueDes;
          break;
        case r'dob':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.dob = valueDes;
          break;
        case r'endoStatus':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.endoStatus = valueDes;
          break;
        case r'heightCm':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.heightCm = valueDes;
          break;
        case r'latestWeightKg':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(double),
          ) as double?;
          if (valueDes == null) continue;
          result.latestWeightKg = valueDes;
          break;
        case r'rasrmStage':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.rasrmStage = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BaselineResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BaselineResponseBuilder();
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

