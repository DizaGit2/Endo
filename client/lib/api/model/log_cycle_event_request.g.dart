// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_cycle_event_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LogCycleEventRequest extends LogCycleEventRequest {
  @override
  final int? flowIntensity;
  @override
  final String? kind;
  @override
  final String? notes;
  @override
  final Date? occurredOn;

  factory _$LogCycleEventRequest([
    void Function(LogCycleEventRequestBuilder)? updates,
  ]) => (LogCycleEventRequestBuilder()..update(updates))._build();

  _$LogCycleEventRequest._({
    this.flowIntensity,
    this.kind,
    this.notes,
    this.occurredOn,
  }) : super._();
  @override
  LogCycleEventRequest rebuild(
    void Function(LogCycleEventRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  LogCycleEventRequestBuilder toBuilder() =>
      LogCycleEventRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LogCycleEventRequest &&
        flowIntensity == other.flowIntensity &&
        kind == other.kind &&
        notes == other.notes &&
        occurredOn == other.occurredOn;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, flowIntensity.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, occurredOn.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LogCycleEventRequest')
          ..add('flowIntensity', flowIntensity)
          ..add('kind', kind)
          ..add('notes', notes)
          ..add('occurredOn', occurredOn))
        .toString();
  }
}

class LogCycleEventRequestBuilder
    implements Builder<LogCycleEventRequest, LogCycleEventRequestBuilder> {
  _$LogCycleEventRequest? _$v;

  int? _flowIntensity;
  int? get flowIntensity => _$this._flowIntensity;
  set flowIntensity(int? flowIntensity) =>
      _$this._flowIntensity = flowIntensity;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  Date? _occurredOn;
  Date? get occurredOn => _$this._occurredOn;
  set occurredOn(Date? occurredOn) => _$this._occurredOn = occurredOn;

  LogCycleEventRequestBuilder() {
    LogCycleEventRequest._defaults(this);
  }

  LogCycleEventRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _flowIntensity = $v.flowIntensity;
      _kind = $v.kind;
      _notes = $v.notes;
      _occurredOn = $v.occurredOn;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LogCycleEventRequest other) {
    _$v = other as _$LogCycleEventRequest;
  }

  @override
  void update(void Function(LogCycleEventRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LogCycleEventRequest build() => _build();

  _$LogCycleEventRequest _build() {
    final _$result =
        _$v ??
        _$LogCycleEventRequest._(
          flowIntensity: flowIntensity,
          kind: kind,
          notes: notes,
          occurredOn: occurredOn,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
