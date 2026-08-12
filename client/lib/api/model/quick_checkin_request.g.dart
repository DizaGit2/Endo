// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quick_checkin_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$QuickCheckinRequest extends QuickCheckinRequest {
  @override
  final int? mood;
  @override
  final int? pain;

  factory _$QuickCheckinRequest([
    void Function(QuickCheckinRequestBuilder)? updates,
  ]) => (QuickCheckinRequestBuilder()..update(updates))._build();

  _$QuickCheckinRequest._({this.mood, this.pain}) : super._();
  @override
  QuickCheckinRequest rebuild(
    void Function(QuickCheckinRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  QuickCheckinRequestBuilder toBuilder() =>
      QuickCheckinRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is QuickCheckinRequest &&
        mood == other.mood &&
        pain == other.pain;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, pain.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'QuickCheckinRequest')
          ..add('mood', mood)
          ..add('pain', pain))
        .toString();
  }
}

class QuickCheckinRequestBuilder
    implements Builder<QuickCheckinRequest, QuickCheckinRequestBuilder> {
  _$QuickCheckinRequest? _$v;

  int? _mood;
  int? get mood => _$this._mood;
  set mood(int? mood) => _$this._mood = mood;

  int? _pain;
  int? get pain => _$this._pain;
  set pain(int? pain) => _$this._pain = pain;

  QuickCheckinRequestBuilder() {
    QuickCheckinRequest._defaults(this);
  }

  QuickCheckinRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mood = $v.mood;
      _pain = $v.pain;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(QuickCheckinRequest other) {
    _$v = other as _$QuickCheckinRequest;
  }

  @override
  void update(void Function(QuickCheckinRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  QuickCheckinRequest build() => _build();

  _$QuickCheckinRequest _build() {
    final _$result = _$v ?? _$QuickCheckinRequest._(mood: mood, pain: pain);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
