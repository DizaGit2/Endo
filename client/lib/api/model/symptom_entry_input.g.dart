// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'symptom_entry_input.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SymptomEntryInput extends SymptomEntryInput {
  @override
  final int? intensity;
  @override
  final String? notes;
  @override
  final DateTime? occurredAt;
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

  factory _$SymptomEntryInput([
    void Function(SymptomEntryInputBuilder)? updates,
  ]) => (SymptomEntryInputBuilder()..update(updates))._build();

  _$SymptomEntryInput._({
    this.intensity,
    this.notes,
    this.occurredAt,
    this.painTypes,
    this.region,
    this.side,
    this.symptomCode,
    this.triggers,
  }) : super._();
  @override
  SymptomEntryInput rebuild(void Function(SymptomEntryInputBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SymptomEntryInputBuilder toBuilder() =>
      SymptomEntryInputBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SymptomEntryInput &&
        intensity == other.intensity &&
        notes == other.notes &&
        occurredAt == other.occurredAt &&
        painTypes == other.painTypes &&
        region == other.region &&
        side == other.side &&
        symptomCode == other.symptomCode &&
        triggers == other.triggers;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, intensity.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, occurredAt.hashCode);
    _$hash = $jc(_$hash, painTypes.hashCode);
    _$hash = $jc(_$hash, region.hashCode);
    _$hash = $jc(_$hash, side.hashCode);
    _$hash = $jc(_$hash, symptomCode.hashCode);
    _$hash = $jc(_$hash, triggers.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SymptomEntryInput')
          ..add('intensity', intensity)
          ..add('notes', notes)
          ..add('occurredAt', occurredAt)
          ..add('painTypes', painTypes)
          ..add('region', region)
          ..add('side', side)
          ..add('symptomCode', symptomCode)
          ..add('triggers', triggers))
        .toString();
  }
}

class SymptomEntryInputBuilder
    implements Builder<SymptomEntryInput, SymptomEntryInputBuilder> {
  _$SymptomEntryInput? _$v;

  int? _intensity;
  int? get intensity => _$this._intensity;
  set intensity(int? intensity) => _$this._intensity = intensity;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  DateTime? _occurredAt;
  DateTime? get occurredAt => _$this._occurredAt;
  set occurredAt(DateTime? occurredAt) => _$this._occurredAt = occurredAt;

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

  SymptomEntryInputBuilder() {
    SymptomEntryInput._defaults(this);
  }

  SymptomEntryInputBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _intensity = $v.intensity;
      _notes = $v.notes;
      _occurredAt = $v.occurredAt;
      _painTypes = $v.painTypes?.toBuilder();
      _region = $v.region;
      _side = $v.side;
      _symptomCode = $v.symptomCode;
      _triggers = $v.triggers?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SymptomEntryInput other) {
    _$v = other as _$SymptomEntryInput;
  }

  @override
  void update(void Function(SymptomEntryInputBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SymptomEntryInput build() => _build();

  _$SymptomEntryInput _build() {
    _$SymptomEntryInput _$result;
    try {
      _$result =
          _$v ??
          _$SymptomEntryInput._(
            intensity: intensity,
            notes: notes,
            occurredAt: occurredAt,
            painTypes: _painTypes?.build(),
            region: region,
            side: side,
            symptomCode: symptomCode,
            triggers: _triggers?.build(),
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
          r'SymptomEntryInput',
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
