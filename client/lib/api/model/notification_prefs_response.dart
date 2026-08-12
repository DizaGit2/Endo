//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/notification_category_selection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_prefs_response.g.dart';

/// NotificationPrefsResponse
///
/// Properties:
/// * [categories] 
/// * [deviceRegistered] 
@BuiltValue()
abstract class NotificationPrefsResponse implements Built<NotificationPrefsResponse, NotificationPrefsResponseBuilder> {
  @BuiltValueField(wireName: r'categories')
  BuiltList<NotificationCategorySelection>? get categories;

  @BuiltValueField(wireName: r'deviceRegistered')
  bool? get deviceRegistered;

  NotificationPrefsResponse._();

  factory NotificationPrefsResponse([void updates(NotificationPrefsResponseBuilder b)]) = _$NotificationPrefsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationPrefsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationPrefsResponse> get serializer => _$NotificationPrefsResponseSerializer();
}

class _$NotificationPrefsResponseSerializer implements PrimitiveSerializer<NotificationPrefsResponse> {
  @override
  final Iterable<Type> types = const [NotificationPrefsResponse, _$NotificationPrefsResponse];

  @override
  final String wireName = r'NotificationPrefsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationPrefsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.categories != null) {
      yield r'categories';
      yield serializers.serialize(
        object.categories,
        specifiedType: const FullType.nullable(BuiltList, [FullType(NotificationCategorySelection)]),
      );
    }
    if (object.deviceRegistered != null) {
      yield r'deviceRegistered';
      yield serializers.serialize(
        object.deviceRegistered,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationPrefsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationPrefsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'categories':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(NotificationCategorySelection)]),
          ) as BuiltList<NotificationCategorySelection>?;
          if (valueDes == null) continue;
          result.categories.replace(valueDes);
          break;
        case r'deviceRegistered':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.deviceRegistered = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationPrefsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationPrefsResponseBuilder();
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

