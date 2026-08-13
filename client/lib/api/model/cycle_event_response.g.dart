// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_event_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CycleEventResponse extends CycleEventResponse {
  @override
  final DateTime? createdAt;
  @override
  final int? flowIntensity;
  @override
  final String? id;
  @override
  final String? kind;
  @override
  final String? notes;
  @override
  final Date? occurredOn;
  @override
  final String? source_;
  @override
  final DateTime? updatedAt;

  factory _$CycleEventResponse([
    void Function(CycleEventResponseBuilder)? updates,
  ]) => (CycleEventResponseBuilder()..update(updates))._build();

  _$CycleEventResponse._({
    this.createdAt,
    this.flowIntensity,
    this.id,
    this.kind,
    this.notes,
    this.occurredOn,
    this.source_,
    this.updatedAt,
  }) : super._();
  @override
  CycleEventResponse rebuild(
    void Function(CycleEventResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CycleEventResponseBuilder toBuilder() =>
      CycleEventResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CycleEventResponse &&
        createdAt == other.createdAt &&
        flowIntensity == other.flowIntensity &&
        id == other.id &&
        kind == other.kind &&
        notes == other.notes &&
        occurredOn == other.occurredOn &&
        source_ == other.source_ &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, flowIntensity.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, occurredOn.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CycleEventResponse')
          ..add('createdAt', createdAt)
          ..add('flowIntensity', flowIntensity)
          ..add('id', id)
          ..add('kind', kind)
          ..add('notes', notes)
          ..add('occurredOn', occurredOn)
          ..add('source_', source_)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class CycleEventResponseBuilder
    implements Builder<CycleEventResponse, CycleEventResponseBuilder> {
  _$CycleEventResponse? _$v;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  int? _flowIntensity;
  int? get flowIntensity => _$this._flowIntensity;
  set flowIntensity(int? flowIntensity) =>
      _$this._flowIntensity = flowIntensity;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  Date? _occurredOn;
  Date? get occurredOn => _$this._occurredOn;
  set occurredOn(Date? occurredOn) => _$this._occurredOn = occurredOn;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  CycleEventResponseBuilder() {
    CycleEventResponse._defaults(this);
  }

  CycleEventResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _createdAt = $v.createdAt;
      _flowIntensity = $v.flowIntensity;
      _id = $v.id;
      _kind = $v.kind;
      _notes = $v.notes;
      _occurredOn = $v.occurredOn;
      _source_ = $v.source_;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CycleEventResponse other) {
    _$v = other as _$CycleEventResponse;
  }

  @override
  void update(void Function(CycleEventResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CycleEventResponse build() => _build();

  _$CycleEventResponse _build() {
    final _$result =
        _$v ??
        _$CycleEventResponse._(
          createdAt: createdAt,
          flowIntensity: flowIntensity,
          id: id,
          kind: kind,
          notes: notes,
          occurredOn: occurredOn,
          source_: source_,
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
