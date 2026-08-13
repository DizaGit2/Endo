// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_selection.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GoalSelection extends GoalSelection {
  @override
  final String? code;
  @override
  final bool? selected;

  factory _$GoalSelection([void Function(GoalSelectionBuilder)? updates]) =>
      (GoalSelectionBuilder()..update(updates))._build();

  _$GoalSelection._({this.code, this.selected}) : super._();
  @override
  GoalSelection rebuild(void Function(GoalSelectionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GoalSelectionBuilder toBuilder() => GoalSelectionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GoalSelection &&
        code == other.code &&
        selected == other.selected;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, selected.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GoalSelection')
          ..add('code', code)
          ..add('selected', selected))
        .toString();
  }
}

class GoalSelectionBuilder
    implements Builder<GoalSelection, GoalSelectionBuilder> {
  _$GoalSelection? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  bool? _selected;
  bool? get selected => _$this._selected;
  set selected(bool? selected) => _$this._selected = selected;

  GoalSelectionBuilder() {
    GoalSelection._defaults(this);
  }

  GoalSelectionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _selected = $v.selected;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GoalSelection other) {
    _$v = other as _$GoalSelection;
  }

  @override
  void update(void Function(GoalSelectionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GoalSelection build() => _build();

  _$GoalSelection _build() {
    final _$result = _$v ?? _$GoalSelection._(code: code, selected: selected);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
