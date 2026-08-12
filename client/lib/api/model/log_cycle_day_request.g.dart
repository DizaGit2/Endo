// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_cycle_day_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LogCycleDayRequest extends LogCycleDayRequest {
  @override
  final int? mood;
  @override
  final String? notes;
  @override
  final int? pain;

  factory _$LogCycleDayRequest([
    void Function(LogCycleDayRequestBuilder)? updates,
  ]) => (LogCycleDayRequestBuilder()..update(updates))._build();

  _$LogCycleDayRequest._({this.mood, this.notes, this.pain}) : super._();
  @override
  LogCycleDayRequest rebuild(
    void Function(LogCycleDayRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  LogCycleDayRequestBuilder toBuilder() =>
      LogCycleDayRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LogCycleDayRequest &&
        mood == other.mood &&
        notes == other.notes &&
        pain == other.pain;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, pain.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LogCycleDayRequest')
          ..add('mood', mood)
          ..add('notes', notes)
          ..add('pain', pain))
        .toString();
  }
}

class LogCycleDayRequestBuilder
    implements Builder<LogCycleDayRequest, LogCycleDayRequestBuilder> {
  _$LogCycleDayRequest? _$v;

  int? _mood;
  int? get mood => _$this._mood;
  set mood(int? mood) => _$this._mood = mood;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  int? _pain;
  int? get pain => _$this._pain;
  set pain(int? pain) => _$this._pain = pain;

  LogCycleDayRequestBuilder() {
    LogCycleDayRequest._defaults(this);
  }

  LogCycleDayRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mood = $v.mood;
      _notes = $v.notes;
      _pain = $v.pain;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LogCycleDayRequest other) {
    _$v = other as _$LogCycleDayRequest;
  }

  @override
  void update(void Function(LogCycleDayRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LogCycleDayRequest build() => _build();

  _$LogCycleDayRequest _build() {
    final _$result =
        _$v ?? _$LogCycleDayRequest._(mood: mood, notes: notes, pain: pain);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
