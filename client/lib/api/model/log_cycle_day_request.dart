//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'log_cycle_day_request.g.dart';

/// LogCycleDayRequest
///
/// Properties:
/// * [mood] 
/// * [notes] 
/// * [pain] 
@BuiltValue()
abstract class LogCycleDayRequest implements Built<LogCycleDayRequest, LogCycleDayRequestBuilder> {
  @BuiltValueField(wireName: r'mood')
  int? get mood;

  @BuiltValueField(wireName: r'notes')
  String? get notes;

  @BuiltValueField(wireName: r'pain')
  int? get pain;

  LogCycleDayRequest._();

  factory LogCycleDayRequest([void updates(LogCycleDayRequestBuilder b)]) = _$LogCycleDayRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LogCycleDayRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LogCycleDayRequest> get serializer => _$LogCycleDayRequestSerializer();
}

class _$LogCycleDayRequestSerializer implements PrimitiveSerializer<LogCycleDayRequest> {
  @override
  final Iterable<Type> types = const [LogCycleDayRequest, _$LogCycleDayRequest];

  @override
  final String wireName = r'LogCycleDayRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LogCycleDayRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.mood != null) {
      yield r'mood';
      yield serializers.serialize(
        object.mood,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.pain != null) {
      yield r'pain';
      yield serializers.serialize(
        object.pain,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LogCycleDayRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LogCycleDayRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'mood':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.mood = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.notes = valueDes;
          break;
        case r'pain':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.pain = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LogCycleDayRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LogCycleDayRequestBuilder();
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

