//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'onboarding_cycle_response.g.dart';

/// OnboardingCycleResponse
///
/// Properties:
/// * [avgCycleLengthDays] 
/// * [avgPeriodLengthDays] 
/// * [lastPeriodStart] 
/// * [regularity] 
/// * [warnings] 
@BuiltValue()
abstract class OnboardingCycleResponse implements Built<OnboardingCycleResponse, OnboardingCycleResponseBuilder> {
  @BuiltValueField(wireName: r'avgCycleLengthDays')
  int? get avgCycleLengthDays;

  @BuiltValueField(wireName: r'avgPeriodLengthDays')
  int? get avgPeriodLengthDays;

  @BuiltValueField(wireName: r'lastPeriodStart')
  Date? get lastPeriodStart;

  @BuiltValueField(wireName: r'regularity')
  String? get regularity;

  @BuiltValueField(wireName: r'warnings')
  BuiltList<String>? get warnings;

  OnboardingCycleResponse._();

  factory OnboardingCycleResponse([void updates(OnboardingCycleResponseBuilder b)]) = _$OnboardingCycleResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OnboardingCycleResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OnboardingCycleResponse> get serializer => _$OnboardingCycleResponseSerializer();
}

class _$OnboardingCycleResponseSerializer implements PrimitiveSerializer<OnboardingCycleResponse> {
  @override
  final Iterable<Type> types = const [OnboardingCycleResponse, _$OnboardingCycleResponse];

  @override
  final String wireName = r'OnboardingCycleResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OnboardingCycleResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    if (object.lastPeriodStart != null) {
      yield r'lastPeriodStart';
      yield serializers.serialize(
        object.lastPeriodStart,
        specifiedType: const FullType(Date),
      );
    }
    if (object.regularity != null) {
      yield r'regularity';
      yield serializers.serialize(
        object.regularity,
        specifiedType: const FullType.nullable(String),
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
    OnboardingCycleResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OnboardingCycleResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'lastPeriodStart':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.lastPeriodStart = valueDes;
          break;
        case r'regularity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.regularity = valueDes;
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
  OnboardingCycleResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OnboardingCycleResponseBuilder();
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

