//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'save_onboarding_cycle_request.g.dart';

/// SaveOnboardingCycleRequest
///
/// Properties:
/// * [avgCycleLengthDays] 
/// * [avgPeriodLengthDays] 
/// * [lastPeriodStart] 
/// * [regularity] 
@BuiltValue()
abstract class SaveOnboardingCycleRequest implements Built<SaveOnboardingCycleRequest, SaveOnboardingCycleRequestBuilder> {
  @BuiltValueField(wireName: r'avgCycleLengthDays')
  int? get avgCycleLengthDays;

  @BuiltValueField(wireName: r'avgPeriodLengthDays')
  int? get avgPeriodLengthDays;

  @BuiltValueField(wireName: r'lastPeriodStart')
  Date? get lastPeriodStart;

  @BuiltValueField(wireName: r'regularity')
  String? get regularity;

  SaveOnboardingCycleRequest._();

  factory SaveOnboardingCycleRequest([void updates(SaveOnboardingCycleRequestBuilder b)]) = _$SaveOnboardingCycleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SaveOnboardingCycleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SaveOnboardingCycleRequest> get serializer => _$SaveOnboardingCycleRequestSerializer();
}

class _$SaveOnboardingCycleRequestSerializer implements PrimitiveSerializer<SaveOnboardingCycleRequest> {
  @override
  final Iterable<Type> types = const [SaveOnboardingCycleRequest, _$SaveOnboardingCycleRequest];

  @override
  final String wireName = r'SaveOnboardingCycleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SaveOnboardingCycleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    if (object.lastPeriodStart != null) {
      yield r'lastPeriodStart';
      yield serializers.serialize(
        object.lastPeriodStart,
        specifiedType: const FullType.nullable(Date),
      );
    }
    if (object.regularity != null) {
      yield r'regularity';
      yield serializers.serialize(
        object.regularity,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SaveOnboardingCycleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SaveOnboardingCycleRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'lastPeriodStart':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SaveOnboardingCycleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SaveOnboardingCycleRequestBuilder();
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

