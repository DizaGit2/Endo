//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cycle_settings_response.g.dart';

/// CycleSettingsResponse
///
/// Properties:
/// * [autoDetectPeriodStartEnabled] 
/// * [avgCycleLengthDays] 
/// * [avgPeriodLengthDays] 
/// * [createdAt] 
/// * [pauseReason] 
/// * [pausedSince] 
/// * [phasePredictionEnabled] 
/// * [phasesUnavailable] 
/// * [regularity] 
/// * [showFertilityWindowEnabled] 
/// * [trackingPaused] 
/// * [updatedAt] 
/// * [warnings] 
@BuiltValue()
abstract class CycleSettingsResponse implements Built<CycleSettingsResponse, CycleSettingsResponseBuilder> {
  @BuiltValueField(wireName: r'autoDetectPeriodStartEnabled')
  bool? get autoDetectPeriodStartEnabled;

  @BuiltValueField(wireName: r'avgCycleLengthDays')
  int? get avgCycleLengthDays;

  @BuiltValueField(wireName: r'avgPeriodLengthDays')
  int? get avgPeriodLengthDays;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  @BuiltValueField(wireName: r'pauseReason')
  String? get pauseReason;

  @BuiltValueField(wireName: r'pausedSince')
  Date? get pausedSince;

  @BuiltValueField(wireName: r'phasePredictionEnabled')
  bool? get phasePredictionEnabled;

  @BuiltValueField(wireName: r'phasesUnavailable')
  bool? get phasesUnavailable;

  @BuiltValueField(wireName: r'regularity')
  String? get regularity;

  @BuiltValueField(wireName: r'showFertilityWindowEnabled')
  bool? get showFertilityWindowEnabled;

  @BuiltValueField(wireName: r'trackingPaused')
  bool? get trackingPaused;

  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  @BuiltValueField(wireName: r'warnings')
  BuiltList<String>? get warnings;

  CycleSettingsResponse._();

  factory CycleSettingsResponse([void updates(CycleSettingsResponseBuilder b)]) = _$CycleSettingsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CycleSettingsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CycleSettingsResponse> get serializer => _$CycleSettingsResponseSerializer();
}

class _$CycleSettingsResponseSerializer implements PrimitiveSerializer<CycleSettingsResponse> {
  @override
  final Iterable<Type> types = const [CycleSettingsResponse, _$CycleSettingsResponse];

  @override
  final String wireName = r'CycleSettingsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CycleSettingsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.autoDetectPeriodStartEnabled != null) {
      yield r'autoDetectPeriodStartEnabled';
      yield serializers.serialize(
        object.autoDetectPeriodStartEnabled,
        specifiedType: const FullType(bool),
      );
    }
    if (object.avgCycleLengthDays != null) {
      yield r'avgCycleLengthDays';
      yield serializers.serialize(
        object.avgCycleLengthDays,
        specifiedType: const FullType(int),
      );
    }
    if (object.avgPeriodLengthDays != null) {
      yield r'avgPeriodLengthDays';
      yield serializers.serialize(
        object.avgPeriodLengthDays,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType.nullable(DateTime),
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
        specifiedType: const FullType(bool),
      );
    }
    if (object.phasesUnavailable != null) {
      yield r'phasesUnavailable';
      yield serializers.serialize(
        object.phasesUnavailable,
        specifiedType: const FullType(bool),
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
        specifiedType: const FullType(bool),
      );
    }
    if (object.trackingPaused != null) {
      yield r'trackingPaused';
      yield serializers.serialize(
        object.trackingPaused,
        specifiedType: const FullType(bool),
      );
    }
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    if (object.warnings != null) {
      yield r'warnings';
      yield serializers.serialize(
        object.warnings,
        specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CycleSettingsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CycleSettingsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'autoDetectPeriodStartEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.autoDetectPeriodStartEnabled = valueDes;
          break;
        case r'avgCycleLengthDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
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
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.createdAt = valueDes;
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
            specifiedType: const FullType(bool),
          ) as bool;
          result.phasePredictionEnabled = valueDes;
          break;
        case r'phasesUnavailable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.phasesUnavailable = valueDes;
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
            specifiedType: const FullType(bool),
          ) as bool;
          result.showFertilityWindowEnabled = valueDes;
          break;
        case r'trackingPaused':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.trackingPaused = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.updatedAt = valueDes;
          break;
        case r'warnings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.warnings.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CycleSettingsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CycleSettingsResponseBuilder();
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

