// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quick_checkin_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$QuickCheckinResponse extends QuickCheckinResponse {
  @override
  final Date? day;
  @override
  final int? mood;
  @override
  final int? pain;
  @override
  final DateTime? updatedAt;

  factory _$QuickCheckinResponse([
    void Function(QuickCheckinResponseBuilder)? updates,
  ]) => (QuickCheckinResponseBuilder()..update(updates))._build();

  _$QuickCheckinResponse._({this.day, this.mood, this.pain, this.updatedAt})
    : super._();
  @override
  QuickCheckinResponse rebuild(
    void Function(QuickCheckinResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  QuickCheckinResponseBuilder toBuilder() =>
      QuickCheckinResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is QuickCheckinResponse &&
        day == other.day &&
        mood == other.mood &&
        pain == other.pain &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, day.hashCode);
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, pain.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'QuickCheckinResponse')
          ..add('day', day)
          ..add('mood', mood)
          ..add('pain', pain)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class QuickCheckinResponseBuilder
    implements Builder<QuickCheckinResponse, QuickCheckinResponseBuilder> {
  _$QuickCheckinResponse? _$v;

  Date? _day;
  Date? get day => _$this._day;
  set day(Date? day) => _$this._day = day;

  int? _mood;
  int? get mood => _$this._mood;
  set mood(int? mood) => _$this._mood = mood;

  int? _pain;
  int? get pain => _$this._pain;
  set pain(int? pain) => _$this._pain = pain;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  QuickCheckinResponseBuilder() {
    QuickCheckinResponse._defaults(this);
  }

  QuickCheckinResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _day = $v.day;
      _mood = $v.mood;
      _pain = $v.pain;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(QuickCheckinResponse other) {
    _$v = other as _$QuickCheckinResponse;
  }

  @override
  void update(void Function(QuickCheckinResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  QuickCheckinResponse build() => _build();

  _$QuickCheckinResponse _build() {
    final _$result =
        _$v ??
        _$QuickCheckinResponse._(
          day: day,
          mood: mood,
          pain: pain,
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
