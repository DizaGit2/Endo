//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'onboarding_complete_response.g.dart';

/// OnboardingCompleteResponse
///
/// Properties:
/// * [alreadyCompleted] 
/// * [completedAt] 
@BuiltValue()
abstract class OnboardingCompleteResponse implements Built<OnboardingCompleteResponse, OnboardingCompleteResponseBuilder> {
  @BuiltValueField(wireName: r'alreadyCompleted')
  bool? get alreadyCompleted;

  @BuiltValueField(wireName: r'completedAt')
  DateTime? get completedAt;

  OnboardingCompleteResponse._();

  factory OnboardingCompleteResponse([void updates(OnboardingCompleteResponseBuilder b)]) = _$OnboardingCompleteResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OnboardingCompleteResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OnboardingCompleteResponse> get serializer => _$OnboardingCompleteResponseSerializer();
}

class _$OnboardingCompleteResponseSerializer implements PrimitiveSerializer<OnboardingCompleteResponse> {
  @override
  final Iterable<Type> types = const [OnboardingCompleteResponse, _$OnboardingCompleteResponse];

  @override
  final String wireName = r'OnboardingCompleteResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OnboardingCompleteResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.alreadyCompleted != null) {
      yield r'alreadyCompleted';
      yield serializers.serialize(
        object.alreadyCompleted,
        specifiedType: const FullType(bool),
      );
    }
    if (object.completedAt != null) {
      yield r'completedAt';
      yield serializers.serialize(
        object.completedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OnboardingCompleteResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OnboardingCompleteResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'alreadyCompleted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.alreadyCompleted = valueDes;
          break;
        case r'completedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.completedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OnboardingCompleteResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OnboardingCompleteResponseBuilder();
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

