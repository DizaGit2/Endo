// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_hormone_prefs_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SaveHormonePrefsRequest extends SaveHormonePrefsRequest {
  @override
  final BuiltList<String>? chartedHormones;

  factory _$SaveHormonePrefsRequest([
    void Function(SaveHormonePrefsRequestBuilder)? updates,
  ]) => (SaveHormonePrefsRequestBuilder()..update(updates))._build();

  _$SaveHormonePrefsRequest._({this.chartedHormones}) : super._();
  @override
  SaveHormonePrefsRequest rebuild(
    void Function(SaveHormonePrefsRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SaveHormonePrefsRequestBuilder toBuilder() =>
      SaveHormonePrefsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SaveHormonePrefsRequest &&
        chartedHormones == other.chartedHormones;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, chartedHormones.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'SaveHormonePrefsRequest',
    )..add('chartedHormones', chartedHormones)).toString();
  }
}

class SaveHormonePrefsRequestBuilder
    implements
        Builder<SaveHormonePrefsRequest, SaveHormonePrefsRequestBuilder> {
  _$SaveHormonePrefsRequest? _$v;

  ListBuilder<String>? _chartedHormones;
  ListBuilder<String> get chartedHormones =>
      _$this._chartedHormones ??= ListBuilder<String>();
  set chartedHormones(ListBuilder<String>? chartedHormones) =>
      _$this._chartedHormones = chartedHormones;

  SaveHormonePrefsRequestBuilder() {
    SaveHormonePrefsRequest._defaults(this);
  }

  SaveHormonePrefsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _chartedHormones = $v.chartedHormones?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SaveHormonePrefsRequest other) {
    _$v = other as _$SaveHormonePrefsRequest;
  }

  @override
  void update(void Function(SaveHormonePrefsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SaveHormonePrefsRequest build() => _build();

  _$SaveHormonePrefsRequest _build() {
    _$SaveHormonePrefsRequest _$result;
    try {
      _$result =
          _$v ??
          _$SaveHormonePrefsRequest._(
            chartedHormones: _chartedHormones?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'chartedHormones';
        _chartedHormones?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SaveHormonePrefsRequest',
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
