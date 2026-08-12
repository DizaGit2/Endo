//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'save_notification_prefs_request.g.dart';

/// SaveNotificationPrefsRequest
///
/// Properties:
/// * [enabledCategories] 
/// * [platform] 
/// * [pushToken] 
@BuiltValue()
abstract class SaveNotificationPrefsRequest implements Built<SaveNotificationPrefsRequest, SaveNotificationPrefsRequestBuilder> {
  @BuiltValueField(wireName: r'enabledCategories')
  BuiltList<String>? get enabledCategories;

  @BuiltValueField(wireName: r'platform')
  String? get platform;

  @BuiltValueField(wireName: r'pushToken')
  String? get pushToken;

  SaveNotificationPrefsRequest._();

  factory SaveNotificationPrefsRequest([void updates(SaveNotificationPrefsRequestBuilder b)]) = _$SaveNotificationPrefsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SaveNotificationPrefsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SaveNotificationPrefsRequest> get serializer => _$SaveNotificationPrefsRequestSerializer();
}

class _$SaveNotificationPrefsRequestSerializer implements PrimitiveSerializer<SaveNotificationPrefsRequest> {
  @override
  final Iterable<Type> types = const [SaveNotificationPrefsRequest, _$SaveNotificationPrefsRequest];

  @override
  final String wireName = r'SaveNotificationPrefsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SaveNotificationPrefsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.enabledCategories != null) {
      yield r'enabledCategories';
      yield serializers.serialize(
        object.enabledCategories,
        specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
      );
    }
    if (object.platform != null) {
      yield r'platform';
      yield serializers.serialize(
        object.platform,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.pushToken != null) {
      yield r'pushToken';
      yield serializers.serialize(
        object.pushToken,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SaveNotificationPrefsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SaveNotificationPrefsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'enabledCategories':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.enabledCategories.replace(valueDes);
          break;
        case r'platform':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.platform = valueDes;
          break;
        case r'pushToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.pushToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SaveNotificationPrefsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SaveNotificationPrefsRequestBuilder();
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

