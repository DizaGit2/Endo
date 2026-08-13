// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'replace_symptom_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReplaceSymptomRequest extends ReplaceSymptomRequest {
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
  final BuiltList<String>? triggers;

  factory _$ReplaceSymptomRequest([
    void Function(ReplaceSymptomRequestBuilder)? updates,
  ]) => (ReplaceSymptomRequestBuilder()..update(updates))._build();

  _$ReplaceSymptomRequest._({
    this.intensity,
    this.notes,
    this.occurredAt,
    this.painTypes,
    this.region,
    this.side,
    this.triggers,
  }) : super._();
  @override
  ReplaceSymptomRequest rebuild(
    void Function(ReplaceSymptomRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ReplaceSymptomRequestBuilder toBuilder() =>
      ReplaceSymptomRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReplaceSymptomRequest &&
        intensity == other.intensity &&
        notes == other.notes &&
        occurredAt == other.occurredAt &&
        painTypes == other.painTypes &&
        region == other.region &&
        side == other.side &&
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
    _$hash = $jc(_$hash, triggers.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReplaceSymptomRequest')
          ..add('intensity', intensity)
          ..add('notes', notes)
          ..add('occurredAt', occurredAt)
          ..add('painTypes', painTypes)
          ..add('region', region)
          ..add('side', side)
          ..add('triggers', triggers))
        .toString();
  }
}

class ReplaceSymptomRequestBuilder
    implements Builder<ReplaceSymptomRequest, ReplaceSymptomRequestBuilder> {
  _$ReplaceSymptomRequest? _$v;

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

  ListBuilder<String>? _triggers;
  ListBuilder<String> get triggers =>
      _$this._triggers ??= ListBuilder<String>();
  set triggers(ListBuilder<String>? triggers) => _$this._triggers = triggers;

  ReplaceSymptomRequestBuilder() {
    ReplaceSymptomRequest._defaults(this);
  }

  ReplaceSymptomRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _intensity = $v.intensity;
      _notes = $v.notes;
      _occurredAt = $v.occurredAt;
      _painTypes = $v.painTypes?.toBuilder();
      _region = $v.region;
      _side = $v.side;
      _triggers = $v.triggers?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReplaceSymptomRequest other) {
    _$v = other as _$ReplaceSymptomRequest;
  }

  @override
  void update(void Function(ReplaceSymptomRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReplaceSymptomRequest build() => _build();

  _$ReplaceSymptomRequest _build() {
    _$ReplaceSymptomRequest _$result;
    try {
      _$result =
          _$v ??
          _$ReplaceSymptomRequest._(
            intensity: intensity,
            notes: notes,
            occurredAt: occurredAt,
            painTypes: _painTypes?.build(),
            region: region,
            side: side,
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
          r'ReplaceSymptomRequest',
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
