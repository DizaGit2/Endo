//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lumen/api/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'log_cycle_event_request.g.dart';

/// LogCycleEventRequest
///
/// Properties:
/// * [flowIntensity] 
/// * [kind] 
/// * [notes] 
/// * [occurredOn] 
@BuiltValue()
abstract class LogCycleEventRequest implements Built<LogCycleEventRequest, LogCycleEventRequestBuilder> {
  @BuiltValueField(wireName: r'flowIntensity')
  int? get flowIntensity;

  @BuiltValueField(wireName: r'kind')
  String? get kind;

  @BuiltValueField(wireName: r'notes')
  String? get notes;

  @BuiltValueField(wireName: r'occurredOn')
  Date? get occurredOn;

  LogCycleEventRequest._();

  factory LogCycleEventRequest([void updates(LogCycleEventRequestBuilder b)]) = _$LogCycleEventRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LogCycleEventRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LogCycleEventRequest> get serializer => _$LogCycleEventRequestSerializer();
}

class _$LogCycleEventRequestSerializer implements PrimitiveSerializer<LogCycleEventRequest> {
  @override
  final Iterable<Type> types = const [LogCycleEventRequest, _$LogCycleEventRequest];

  @override
  final String wireName = r'LogCycleEventRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LogCycleEventRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.flowIntensity != null) {
      yield r'flowIntensity';
      yield serializers.serialize(
        object.flowIntensity,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.kind != null) {
      yield r'kind';
      yield serializers.serialize(
        object.kind,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.occurredOn != null) {
      yield r'occurredOn';
      yield serializers.serialize(
        object.occurredOn,
        specifiedType: const FullType.nullable(Date),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LogCycleEventRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LogCycleEventRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'flowIntensity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.flowIntensity = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.kind = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.notes = valueDes;
          break;
        case r'occurredOn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.occurredOn = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LogCycleEventRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LogCycleEventRequestBuilder();
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

