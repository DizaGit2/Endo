// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hormone_prefs_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HormonePrefsResponse extends HormonePrefsResponse {
  @override
  final BuiltList<HormoneSelection>? hormones;

  factory _$HormonePrefsResponse([
    void Function(HormonePrefsResponseBuilder)? updates,
  ]) => (HormonePrefsResponseBuilder()..update(updates))._build();

  _$HormonePrefsResponse._({this.hormones}) : super._();
  @override
  HormonePrefsResponse rebuild(
    void Function(HormonePrefsResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  HormonePrefsResponseBuilder toBuilder() =>
      HormonePrefsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HormonePrefsResponse && hormones == other.hormones;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, hormones.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'HormonePrefsResponse',
    )..add('hormones', hormones)).toString();
  }
}

class HormonePrefsResponseBuilder
    implements Builder<HormonePrefsResponse, HormonePrefsResponseBuilder> {
  _$HormonePrefsResponse? _$v;

  ListBuilder<HormoneSelection>? _hormones;
  ListBuilder<HormoneSelection> get hormones =>
      _$this._hormones ??= ListBuilder<HormoneSelection>();
  set hormones(ListBuilder<HormoneSelection>? hormones) =>
      _$this._hormones = hormones;

  HormonePrefsResponseBuilder() {
    HormonePrefsResponse._defaults(this);
  }

  HormonePrefsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _hormones = $v.hormones?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HormonePrefsResponse other) {
    _$v = other as _$HormonePrefsResponse;
  }

  @override
  void update(void Function(HormonePrefsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HormonePrefsResponse build() => _build();

  _$HormonePrefsResponse _build() {
    _$HormonePrefsResponse _$result;
    try {
      _$result = _$v ?? _$HormonePrefsResponse._(hormones: _hormones?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'hormones';
        _hormones?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'HormonePrefsResponse',
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
