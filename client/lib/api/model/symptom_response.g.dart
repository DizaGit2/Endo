// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'symptom_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SymptomResponse extends SymptomResponse {
  @override
  final DateTime? createdAt;
  @override
  final String? id;
  @override
  final int? intensity;
  @override
  final String? notes;
  @override
  final DateTime? occurredAt;
  @override
  final Date? occurredOn;
  @override
  final BuiltList<String>? painTypes;
  @override
  final String? region;
  @override
  final String? side;
  @override
  final String? symptomCode;
  @override
  final BuiltList<String>? triggers;
  @override
  final DateTime? updatedAt;

  factory _$SymptomResponse([void Function(SymptomResponseBuilder)? updates]) =>
      (SymptomResponseBuilder()..update(updates))._build();

  _$SymptomResponse._({
    this.createdAt,
    this.id,
    this.intensity,
    this.notes,
    this.occurredAt,
    this.occurredOn,
    this.painTypes,
    this.region,
    this.side,
    this.symptomCode,
    this.triggers,
    this.updatedAt,
  }) : super._();
  @override
  SymptomResponse rebuild(void Function(SymptomResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SymptomResponseBuilder toBuilder() => SymptomResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SymptomResponse &&
        createdAt == other.createdAt &&
        id == other.id &&
        intensity == other.intensity &&
        notes == other.notes &&
        occurredAt == other.occurredAt &&
        occurredOn == other.occurredOn &&
        painTypes == other.painTypes &&
        region == other.region &&
        side == other.side &&
        symptomCode == other.symptomCode &&
        triggers == other.triggers &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, intensity.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, occurredAt.hashCode);
    _$hash = $jc(_$hash, occurredOn.hashCode);
    _$hash = $jc(_$hash, painTypes.hashCode);
    _$hash = $jc(_$hash, region.hashCode);
    _$hash = $jc(_$hash, side.hashCode);
    _$hash = $jc(_$hash, symptomCode.hashCode);
    _$hash = $jc(_$hash, triggers.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SymptomResponse')
          ..add('createdAt', createdAt)
          ..add('id', id)
          ..add('intensity', intensity)
          ..add('notes', notes)
          ..add('occurredAt', occurredAt)
          ..add('occurredOn', occurredOn)
          ..add('painTypes', painTypes)
          ..add('region', region)
          ..add('side', side)
          ..add('symptomCode', symptomCode)
          ..add('triggers', triggers)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class SymptomResponseBuilder
    implements Builder<SymptomResponse, SymptomResponseBuilder> {
  _$SymptomResponse? _$v;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  int? _intensity;
  int? get intensity => _$this._intensity;
  set intensity(int? intensity) => _$this._intensity = intensity;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  DateTime? _occurredAt;
  DateTime? get occurredAt => _$this._occurredAt;
  set occurredAt(DateTime? occurredAt) => _$this._occurredAt = occurredAt;

  Date? _occurredOn;
  Date? get occurredOn => _$this._occurredOn;
  set occurredOn(Date? occurredOn) => _$this._occurredOn = occurredOn;

  ListBuilder<String>? _painTypes;
  ListBuilder<String> get painTypes =>
      _$this._painTypes ??= ListBuilder<String>();
  set painTypes(ListBuilder<String>? painTypes) =>
      _$this._painTypes = painTypes;

  String? _region;
  String? get region => _$this._region;
  set region(String? region) => _$this._region = region;

  String? _side;
  String? get side => _$this._side;
  set side(String? side) => _$this._side = side;

  String? _symptomCode;
  String? get symptomCode => _$this._symptomCode;
  set symptomCode(String? symptomCode) => _$this._symptomCode = symptomCode;

  ListBuilder<String>? _triggers;
  ListBuilder<String> get triggers =>
      _$this._triggers ??= ListBuilder<String>();
  set triggers(ListBuilder<String>? triggers) => _$this._triggers = triggers;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  SymptomResponseBuilder() {
    SymptomResponse._defaults(this);
  }

  SymptomResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _createdAt = $v.createdAt;
      _id = $v.id;
      _intensity = $v.intensity;
      _notes = $v.notes;
      _occurredAt = $v.occurredAt;
      _occurredOn = $v.occurredOn;
      _painTypes = $v.painTypes?.toBuilder();
      _region = $v.region;
      _side = $v.side;
      _symptomCode = $v.symptomCode;
      _triggers = $v.triggers?.toBuilder();
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SymptomResponse other) {
    _$v = other as _$SymptomResponse;
  }

  @override
  void update(void Function(SymptomResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SymptomResponse build() => _build();

  _$SymptomResponse _build() {
    _$SymptomResponse _$result;
    try {
      _$result =
          _$v ??
          _$SymptomResponse._(
            createdAt: createdAt,
            id: id,
            intensity: intensity,
            notes: notes,
            occurredAt: occurredAt,
            occurredOn: occurredOn,
            painTypes: _painTypes?.build(),
            region: region,
            side: side,
            symptomCode: symptomCode,
            triggers: _triggers?.build(),
            updatedAt: updatedAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'painTypes';
        _painTypes?.build();

        _$failedField = 'triggers';
        _triggers?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SymptomResponse',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
