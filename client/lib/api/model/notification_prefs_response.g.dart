// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_prefs_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NotificationPrefsResponse extends NotificationPrefsResponse {
  @override
  final BuiltList<NotificationCategorySelection>? categories;
  @override
  final bool? deviceRegistered;

  factory _$NotificationPrefsResponse([
    void Function(NotificationPrefsResponseBuilder)? updates,
  ]) => (NotificationPrefsResponseBuilder()..update(updates))._build();

  _$NotificationPrefsResponse._({this.categories, this.deviceRegistered})
    : super._();
  @override
  NotificationPrefsResponse rebuild(
    void Function(NotificationPrefsResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  NotificationPrefsResponseBuilder toBuilder() =>
      NotificationPrefsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NotificationPrefsResponse &&
        categories == other.categories &&
        deviceRegistered == other.deviceRegistered;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categories.hashCode);
    _$hash = $jc(_$hash, deviceRegistered.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NotificationPrefsResponse')
          ..add('categories', categories)
          ..add('deviceRegistered', deviceRegistered))
        .toString();
  }
}

class NotificationPrefsResponseBuilder
    implements
        Builder<NotificationPrefsResponse, NotificationPrefsResponseBuilder> {
  _$NotificationPrefsResponse? _$v;

  ListBuilder<NotificationCategorySelection>? _categories;
  ListBuilder<NotificationCategorySelection> get categories =>
      _$this._categories ??= ListBuilder<NotificationCategorySelection>();
  set categories(ListBuilder<NotificationCategorySelection>? categories) =>
      _$this._categories = categories;

  bool? _deviceRegistered;
  bool? get deviceRegistered => _$this._deviceRegistered;
  set deviceRegistered(bool? deviceRegistered) =>
      _$this._deviceRegistered = deviceRegistered;

  NotificationPrefsResponseBuilder() {
    NotificationPrefsResponse._defaults(this);
  }

  NotificationPrefsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categories = $v.categories?.toBuilder();
      _deviceRegistered = $v.deviceRegistered;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NotificationPrefsResponse other) {
    _$v = other as _$NotificationPrefsResponse;
  }

  @override
  void update(void Function(NotificationPrefsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NotificationPrefsResponse build() => _build();

  _$NotificationPrefsResponse _build() {
    _$NotificationPrefsResponse _$result;
    try {
      _$result =
          _$v ??
          _$NotificationPrefsResponse._(
            categories: _categories?.build(),
            deviceRegistered: deviceRegistered,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'categories';
        _categories?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'NotificationPrefsResponse',
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
