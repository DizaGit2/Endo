//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'onboarding_start_response.g.dart';

/// OnboardingStartResponse
///
/// Properties:
/// * [userId] 
@BuiltValue()
abstract class OnboardingStartResponse implements Built<OnboardingStartResponse, OnboardingStartResponseBuilder> {
  @BuiltValueField(wireName: r'userId')
  String? get userId;

  OnboardingStartResponse._();

  factory OnboardingStartResponse([void updates(OnboardingStartResponseBuilder b)]) = _$OnboardingStartResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OnboardingStartResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OnboardingStartResponse> get serializer => _$OnboardingStartResponseSerializer();
}

class _$OnboardingStartResponseSerializer implements PrimitiveSerializer<OnboardingStartResponse> {
  @override
  final Iterable<Type> types = const [OnboardingStartResponse, _$OnboardingStartResponse];

  @override
  final String wireName = r'OnboardingStartResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OnboardingStartResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.userId != null) {
      yield r'userId';
      yield serializers.serialize(
        object.userId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OnboardingStartResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OnboardingStartResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'userId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OnboardingStartResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OnboardingStartResponseBuilder();
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

