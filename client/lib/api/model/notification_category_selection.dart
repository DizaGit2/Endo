//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_category_selection.g.dart';

/// NotificationCategorySelection
///
/// Properties:
/// * [code] 
/// * [enabled] 
@BuiltValue()
abstract class NotificationCategorySelection implements Built<NotificationCategorySelection, NotificationCategorySelectionBuilder> {
  @BuiltValueField(wireName: r'code')
  String? get code;

  @BuiltValueField(wireName: r'enabled')
  bool? get enabled;

  NotificationCategorySelection._();

  factory NotificationCategorySelection([void updates(NotificationCategorySelectionBuilder b)]) = _$NotificationCategorySelection;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationCategorySelectionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationCategorySelection> get serializer => _$NotificationCategorySelectionSerializer();
}

class _$NotificationCategorySelectionSerializer implements PrimitiveSerializer<NotificationCategorySelection> {
  @override
  final Iterable<Type> types = const [NotificationCategorySelection, _$NotificationCategorySelection];

  @override
  final String wireName = r'NotificationCategorySelection';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationCategorySelection object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.enabled != null) {
      yield r'enabled';
      yield serializers.serialize(
        object.enabled,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationCategorySelection object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationCategorySelectionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.code = valueDes;
          break;
        case r'enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.enabled = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationCategorySelection deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationCategorySelectionBuilder();
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

