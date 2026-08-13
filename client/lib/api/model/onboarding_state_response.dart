//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/notification_category_selection.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/goal_selection.dart';
import 'package:lumen/api/model/hormone_selection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'onboarding_state_response.g.dart';

/// OnboardingStateResponse
///
/// Properties:
/// * [baselineProvided] 
/// * [completed] 
/// * [completedAt] 
/// * [cycleProvided] 
/// * [goals] 
/// * [goalsProvided] 
/// * [hormones] 
/// * [hormonesProvided] 
/// * [lastPeriodStart] 
/// * [missingMandatorySteps] 
/// * [notifications] 
/// * [notificationsProvided] 
@BuiltValue()
abstract class OnboardingStateResponse implements Built<OnboardingStateResponse, OnboardingStateResponseBuilder> {
  @BuiltValueField(wireName: r'baselineProvided')
  bool? get baselineProvided;

  @BuiltValueField(wireName: r'completed')
  bool? get completed;

  @BuiltValueField(wireName: r'completedAt')
  DateTime? get completedAt;

  @BuiltValueField(wireName: r'cycleProvided')
  bool? get cycleProvided;

  @BuiltValueField(wireName: r'goals')
  BuiltList<GoalSelection>? get goals;

  @BuiltValueField(wireName: r'goalsProvided')
  bool? get goalsProvided;

  @BuiltValueField(wireName: r'hormones')
  BuiltList<HormoneSelection>? get hormones;

  @BuiltValueField(wireName: r'hormonesProvided')
  bool? get hormonesProvided;

  @BuiltValueField(wireName: r'lastPeriodStart')
  Date? get lastPeriodStart;

  @BuiltValueField(wireName: r'missingMandatorySteps')
  BuiltList<String>? get missingMandatorySteps;

  @BuiltValueField(wireName: r'notifications')
  BuiltList<NotificationCategorySelection>? get notifications;

  @BuiltValueField(wireName: r'notificationsProvided')
  bool? get notificationsProvided;

  OnboardingStateResponse._();

  factory OnboardingStateResponse([void updates(OnboardingStateResponseBuilder b)]) = _$OnboardingStateResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OnboardingStateResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OnboardingStateResponse> get serializer => _$OnboardingStateResponseSerializer();
}

class _$OnboardingStateResponseSerializer implements PrimitiveSerializer<OnboardingStateResponse> {
  @override
  final Iterable<Type> types = const [OnboardingStateResponse, _$OnboardingStateResponse];

  @override
  final String wireName = r'OnboardingStateResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OnboardingStateResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.baselineProvided != null) {
      yield r'baselineProvided';
      yield serializers.serialize(
        object.baselineProvided,
        specifiedType: const FullType(bool),
      );
    }
    if (object.completed != null) {
      yield r'completed';
      yield serializers.serialize(
        object.completed,
        specifiedType: const FullType(bool),
      );
    }
    if (object.completedAt != null) {
      yield r'completedAt';
      yield serializers.serialize(
        object.completedAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    if (object.cycleProvided != null) {
      yield r'cycleProvided';
      yield serializers.serialize(
        object.cycleProvided,
        specifiedType: const FullType(bool),
      );
    }
    if (object.goals != null) {
      yield r'goals';
      yield serializers.serialize(
        object.goals,
        specifiedType: const FullType.nullable(BuiltList, [FullType(GoalSelection)]),
      );
    }
    if (object.goalsProvided != null) {
      yield r'goalsProvided';
      yield serializers.serialize(
        object.goalsProvided,
        specifiedType: const FullType(bool),
      );
    }
    if (object.hormones != null) {
      yield r'hormones';
      yield serializers.serialize(
        object.hormones,
        specifiedType: const FullType.nullable(BuiltList, [FullType(HormoneSelection)]),
      );
    }
    if (object.hormonesProvided != null) {
      yield r'hormonesProvided';
      yield serializers.serialize(
        object.hormonesProvided,
        specifiedType: const FullType(bool),
      );
    }
    if (object.lastPeriodStart != null) {
      yield r'lastPeriodStart';
      yield serializers.serialize(
        object.lastPeriodStart,
        specifiedType: const FullType.nullable(Date),
      );
    }
    if (object.missingMandatorySteps != null) {
      yield r'missingMandatorySteps';
      yield serializers.serialize(
        object.missingMandatorySteps,
        specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
      );
    }
    if (object.notifications != null) {
      yield r'notifications';
      yield serializers.serialize(
        object.notifications,
        specifiedType: const FullType.nullable(BuiltList, [FullType(NotificationCategorySelection)]),
      );
    }
    if (object.notificationsProvided != null) {
      yield r'notificationsProvided';
      yield serializers.serialize(
        object.notificationsProvided,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OnboardingStateResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OnboardingStateResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'baselineProvided':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.baselineProvided = valueDes;
          break;
        case r'completed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.completed = valueDes;
          break;
        case r'completedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.completedAt = valueDes;
          break;
        case r'cycleProvided':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.cycleProvided = valueDes;
          break;
        case r'goals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(GoalSelection)]),
          ) as BuiltList<GoalSelection>?;
          if (valueDes == null) continue;
          result.goals.replace(valueDes);
          break;
        case r'goalsProvided':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.goalsProvided = valueDes;
          break;
        case r'hormones':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(HormoneSelection)]),
          ) as BuiltList<HormoneSelection>?;
          if (valueDes == null) continue;
          result.hormones.replace(valueDes);
          break;
        case r'hormonesProvided':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hormonesProvided = valueDes;
          break;
        case r'lastPeriodStart':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.lastPeriodStart = valueDes;
          break;
        case r'missingMandatorySteps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.missingMandatorySteps.replace(valueDes);
          break;
        case r'notifications':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(NotificationCategorySelection)]),
          ) as BuiltList<NotificationCategorySelection>?;
          if (valueDes == null) continue;
          result.notifications.replace(valueDes);
          break;
        case r'notificationsProvided':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.notificationsProvided = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OnboardingStateResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OnboardingStateResponseBuilder();
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

