// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hormone_selection.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HormoneSelection extends HormoneSelection {
  @override
  final bool? charted;
  @override
  final String? code;

  factory _$HormoneSelection([
    void Function(HormoneSelectionBuilder)? updates,
  ]) => (HormoneSelectionBuilder()..update(updates))._build();

  _$HormoneSelection._({this.charted, this.code}) : super._();
  @override
  HormoneSelection rebuild(void Function(HormoneSelectionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HormoneSelectionBuilder toBuilder() =>
      HormoneSelectionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HormoneSelection &&
        charted == other.charted &&
        code == other.code;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, charted.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HormoneSelection')
          ..add('charted', charted)
          ..add('code', code))
        .toString();
  }
}

class HormoneSelectionBuilder
    implements Builder<HormoneSelection, HormoneSelectionBuilder> {
  _$HormoneSelection? _$v;

  bool? _charted;
  bool? get charted => _$this._charted;
  set charted(bool? charted) => _$this._charted = charted;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  HormoneSelectionBuilder() {
    HormoneSelection._defaults(this);
  }

  HormoneSelectionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _charted = $v.charted;
      _code = $v.code;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HormoneSelection other) {
    _$v = other as _$HormoneSelection;
  }

  @override
  void update(void Function(HormoneSelectionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HormoneSelection build() => _build();

  _$HormoneSelection _build() {
    final _$result = _$v ?? _$HormoneSelection._(charted: charted, code: code);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
