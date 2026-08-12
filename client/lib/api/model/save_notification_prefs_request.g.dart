// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_notification_prefs_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SaveNotificationPrefsRequest extends SaveNotificationPrefsRequest {
  @override
  final BuiltList<String>? enabledCategories;
  @override
  final String? platform;
  @override
  final String? pushToken;

  factory _$SaveNotificationPrefsRequest([
    void Function(SaveNotificationPrefsRequestBuilder)? updates,
  ]) => (SaveNotificationPrefsRequestBuilder()..update(updates))._build();

  _$SaveNotificationPrefsRequest._({
    this.enabledCategories,
    this.platform,
    this.pushToken,
  }) : super._();
  @override
  SaveNotificationPrefsRequest rebuild(
    void Function(SaveNotificationPrefsRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SaveNotificationPrefsRequestBuilder toBuilder() =>
      SaveNotificationPrefsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SaveNotificationPrefsRequest &&
        enabledCategories == other.enabledCategories &&
        platform == other.platform &&
        pushToken == other.pushToken;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, enabledCategories.hashCode);
    _$hash = $jc(_$hash, platform.hashCode);
    _$hash = $jc(_$hash, pushToken.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SaveNotificationPrefsRequest')
          ..add('enabledCategories', enabledCategories)
          ..add('platform', platform)
          ..add('pushToken', pushToken))
        .toString();
  }
}

class SaveNotificationPrefsRequestBuilder
    implements
        Builder<
          SaveNotificationPrefsRequest,
          SaveNotificationPrefsRequestBuilder
        > {
  _$SaveNotificationPrefsRequest? _$v;

  ListBuilder<String>? _enabledCategories;
  ListBuilder<String> get enabledCategories =>
      _$this._enabledCategories ??= ListBuilder<String>();
  set enabledCategories(ListBuilder<String>? enabledCategories) =>
      _$this._enabledCategories = enabledCategories;

  String? _platform;
  String? get platform => _$this._platform;
  set platform(String? platform) => _$this._platform = platform;

  String? _pushToken;
  String? get pushToken => _$this._pushToken;
  set pushToken(String? pushToken) => _$this._pushToken = pushToken;

  SaveNotificationPrefsRequestBuilder() {
    SaveNotificationPrefsRequest._defaults(this);
  }

  SaveNotificationPrefsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _enabledCategories = $v.enabledCategories?.toBuilder();
      _platform = $v.platform;
      _pushToken = $v.pushToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SaveNotificationPrefsRequest other) {
    _$v = other as _$SaveNotificationPrefsRequest;
  }

  @override
  void update(void Function(SaveNotificationPrefsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SaveNotificationPrefsRequest build() => _build();

  _$SaveNotificationPrefsRequest _build() {
    _$SaveNotificationPrefsRequest _$result;
    try {
      _$result =
          _$v ??
          _$SaveNotificationPrefsRequest._(
            enabledCategories: _enabledCategories?.build(),
            platform: platform,
            pushToken: pushToken,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'enabledCategories';
        _enabledCategories?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SaveNotificationPrefsRequest',
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
