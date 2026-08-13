//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'save_baseline_request.g.dart';

/// SaveBaselineRequest
///
/// Properties:
/// * [diagnosedOn] 
/// * [dob] 
/// * [endoStatus] 
/// * [heightCm] 
/// * [rasrmStage] 
/// * [weightKg] 
@BuiltValue()
abstract class SaveBaselineRequest implements Built<SaveBaselineRequest, SaveBaselineRequestBuilder> {
  @BuiltValueField(wireName: r'diagnosedOn')
  String? get diagnosedOn;

  @BuiltValueField(wireName: r'dob')
  Date? get dob;

  @BuiltValueField(wireName: r'endoStatus')
  String? get endoStatus;

  @BuiltValueField(wireName: r'heightCm')
  int? get heightCm;

  @BuiltValueField(wireName: r'rasrmStage')
  int? get rasrmStage;

  @BuiltValueField(wireName: r'weightKg')
  double? get weightKg;

  SaveBaselineRequest._();

  factory SaveBaselineRequest([void updates(SaveBaselineRequestBuilder b)]) = _$SaveBaselineRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SaveBaselineRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SaveBaselineRequest> get serializer => _$SaveBaselineRequestSerializer();
}

class _$SaveBaselineRequestSerializer implements PrimitiveSerializer<SaveBaselineRequest> {
  @override
  final Iterable<Type> types = const [SaveBaselineRequest, _$SaveBaselineRequest];

  @override
  final String wireName = r'SaveBaselineRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SaveBaselineRequest object, {
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
    if (object.rasrmStage != null) {
      yield r'rasrmStage';
      yield serializers.serialize(
        object.rasrmStage,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.weightKg != null) {
      yield r'weightKg';
      yield serializers.serialize(
        object.weightKg,
        specifiedType: const FullType.nullable(double),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SaveBaselineRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SaveBaselineRequestBuilder result,
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
        case r'rasrmStage':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.rasrmStage = valueDes;
          break;
        case r'weightKg':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(double),
          ) as double?;
          if (valueDes == null) continue;
          result.weightKg = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SaveBaselineRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SaveBaselineRequestBuilder();
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

