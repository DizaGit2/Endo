// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_day_log_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CycleDayLogResponse extends CycleDayLogResponse {
  @override
  final DateTime? createdAt;
  @override
  final Date? day;
  @override
  final int? mood;
  @override
  final String? notes;
  @override
  final int? pain;
  @override
  final DateTime? updatedAt;

  factory _$CycleDayLogResponse([
    void Function(CycleDayLogResponseBuilder)? updates,
  ]) => (CycleDayLogResponseBuilder()..update(updates))._build();

  _$CycleDayLogResponse._({
    this.createdAt,
    this.day,
    this.mood,
    this.notes,
    this.pain,
    this.updatedAt,
  }) : super._();
  @override
  CycleDayLogResponse rebuild(
    void Function(CycleDayLogResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CycleDayLogResponseBuilder toBuilder() =>
      CycleDayLogResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CycleDayLogResponse &&
        createdAt == other.createdAt &&
        day == other.day &&
        mood == other.mood &&
        notes == other.notes &&
        pain == other.pain &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, day.hashCode);
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, pain.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CycleDayLogResponse')
          ..add('createdAt', createdAt)
          ..add('day', day)
          ..add('mood', mood)
          ..add('notes', notes)
          ..add('pain', pain)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class CycleDayLogResponseBuilder
    implements Builder<CycleDayLogResponse, CycleDayLogResponseBuilder> {
  _$CycleDayLogResponse? _$v;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  Date? _day;
  Date? get day => _$this._day;
  set day(Date? day) => _$this._day = day;

  int? _mood;
  int? get mood => _$this._mood;
  set mood(int? mood) => _$this._mood = mood;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  int? _pain;
  int? get pain => _$this._pain;
  set pain(int? pain) => _$this._pain = pain;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  CycleDayLogResponseBuilder() {
    CycleDayLogResponse._defaults(this);
  }

  CycleDayLogResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _createdAt = $v.createdAt;
      _day = $v.day;
      _mood = $v.mood;
      _notes = $v.notes;
      _pain = $v.pain;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CycleDayLogResponse other) {
    _$v = other as _$CycleDayLogResponse;
  }

  @override
  void update(void Function(CycleDayLogResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CycleDayLogResponse build() => _build();

  _$CycleDayLogResponse _build() {
    final _$result =
        _$v ??
        _$CycleDayLogResponse._(
          createdAt: createdAt,
          day: day,
          mood: mood,
          notes: notes,
          pain: pain,
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
