//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_cycle_settings_request.g.dart';

/// UpdateCycleSettingsRequest
///
/// Properties:
/// * [autoDetectPeriodStartEnabled] 
/// * [avgCycleLengthDays] 
/// * [avgPeriodLengthDays] 
/// * [pauseReason] 
/// * [pausedSince] 
/// * [phasePredictionEnabled] 
/// * [regularity] 
/// * [showFertilityWindowEnabled] 
/// * [trackingPaused] 
@BuiltValue()
abstract class UpdateCycleSettingsRequest implements Built<UpdateCycleSettingsRequest, UpdateCycleSettingsRequestBuilder> {
  @BuiltValueField(wireName: r'autoDetectPeriodStartEnabled')
  bool? get autoDetectPeriodStartEnabled;

  @BuiltValueField(wireName: r'avgCycleLengthDays')
  int? get avgCycleLengthDays;

  @BuiltValueField(wireName: r'avgPeriodLengthDays')
  int? get avgPeriodLengthDays;

  @BuiltValueField(wireName: r'pauseReason')
  String? get pauseReason;

  @BuiltValueField(wireName: r'pausedSince')
  Date? get pausedSince;

  @BuiltValueField(wireName: r'phasePredictionEnabled')
  bool? get phasePredictionEnabled;

  @BuiltValueField(wireName: r'regularity')
  String? get regularity;

  @BuiltValueField(wireName: r'showFertilityWindowEnabled')
  bool? get showFertilityWindowEnabled;

  @BuiltValueField(wireName: r'trackingPaused')
  bool? get trackingPaused;

  UpdateCycleSettingsRequest._();

  factory UpdateCycleSettingsRequest([void updates(UpdateCycleSettingsRequestBuilder b)]) = _$UpdateCycleSettingsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateCycleSettingsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateCycleSettingsRequest> get serializer => _$UpdateCycleSettingsRequestSerializer();
}

class _$UpdateCycleSettingsRequestSerializer implements PrimitiveSerializer<UpdateCycleSettingsRequest> {
  @override
  final Iterable<Type> types = const [UpdateCycleSettingsRequest, _$UpdateCycleSettingsRequest];

  @override
  final String wireName = r'UpdateCycleSettingsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateCycleSettingsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.autoDetectPeriodStartEnabled != null) {
      yield r'autoDetectPeriodStartEnabled';
      yield serializers.serialize(
        object.autoDetectPeriodStartEnabled,
        specifiedType: const FullType.nullable(bool),
      );
    }
    if (object.avgCycleLengthDays != null) {
      yield r'avgCycleLengthDays';
      yield serializers.serialize(
        object.avgCycleLengthDays,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.avgPeriodLengthDays != null) {
      yield r'avgPeriodLengthDays';
      yield serializers.serialize(
        object.avgPeriodLengthDays,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.pauseReason != null) {
      yield r'pauseReason';
      yield serializers.serialize(
        object.pauseReason,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.pausedSince != null) {
      yield r'pausedSince';
      yield serializers.serialize(
        object.pausedSince,
        specifiedType: const FullType.nullable(Date),
      );
    }
    if (object.phasePredictionEnabled != null) {
      yield r'phasePredictionEnabled';
      yield serializers.serialize(
        object.phasePredictionEnabled,
        specifiedType: const FullType.nullable(bool),
      );
    }
    if (object.regularity != null) {
      yield r'regularity';
      yield serializers.serialize(
        object.regularity,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.showFertilityWindowEnabled != null) {
      yield r'showFertilityWindowEnabled';
      yield serializers.serialize(
        object.showFertilityWindowEnabled,
        specifiedType: const FullType.nullable(bool),
      );
    }
    if (object.trackingPaused != null) {
      yield r'trackingPaused';
      yield serializers.serialize(
        object.trackingPaused,
        specifiedType: const FullType.nullable(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateCycleSettingsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdateCycleSettingsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'autoDetectPeriodStartEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.autoDetectPeriodStartEnabled = valueDes;
          break;
        case r'avgCycleLengthDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.avgCycleLengthDays = valueDes;
          break;
        case r'avgPeriodLengthDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.avgPeriodLengthDays = valueDes;
          break;
        case r'pauseReason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.pauseReason = valueDes;
          break;
        case r'pausedSince':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.pausedSince = valueDes;
          break;
        case r'phasePredictionEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.phasePredictionEnabled = valueDes;
          break;
        case r'regularity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.regularity = valueDes;
          break;
        case r'showFertilityWindowEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.showFertilityWindowEnabled = valueDes;
          break;
        case r'trackingPaused':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.trackingPaused = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateCycleSettingsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateCycleSettingsRequestBuilder();
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

