// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_category_selection.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationCategorySelection extends NotificationCategorySelection {
  @override
  final String? code;
  @override
  final bool? enabled;

  factory _$NotificationCategorySelection([
    void Function(NotificationCategorySelectionBuilder)? updates,
  ]) => (NotificationCategorySelectionBuilder()..update(updates))._build();

  _$NotificationCategorySelection._({this.code, this.enabled}) : super._();
  @override
  NotificationCategorySelection rebuild(
    void Function(NotificationCategorySelectionBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationCategorySelectionBuilder toBuilder() =>
      NotificationCategorySelectionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationCategorySelection &&
        code == other.code &&
        enabled == other.enabled;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, enabled.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationCategorySelection')
          ..add('code', code)
          ..add('enabled', enabled))
        .toString();
  }
}

class NotificationCategorySelectionBuilder
    implements
        Builder<
          NotificationCategorySelection,
          NotificationCategorySelectionBuilder
        > {
  _$NotificationCategorySelection? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  bool? _enabled;
  bool? get enabled => _$this._enabled;
  set enabled(bool? enabled) => _$this._enabled = enabled;

  NotificationCategorySelectionBuilder() {
    NotificationCategorySelection._defaults(this);
  }

  NotificationCategorySelectionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _enabled = $v.enabled;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationCategorySelection other) {
    _$v = other as _$NotificationCategorySelection;
  }

  @override
  void update(void Function(NotificationCategorySelectionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationCategorySelection build() => _build();

  _$NotificationCategorySelection _build() {
    final _$result =
        _$v ?? _$NotificationCategorySelection._(code: code, enabled: enabled);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
