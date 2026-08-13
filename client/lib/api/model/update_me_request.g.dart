// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_me_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateMeRequest extends UpdateMeRequest {
  @override
  final String? displayName;
  @override
  final String? locale;
  @override
  final String? timezone;

  factory _$UpdateMeRequest([void Function(UpdateMeRequestBuilder)? updates]) =>
      (UpdateMeRequestBuilder()..update(updates))._build();

  _$UpdateMeRequest._({this.displayName, this.locale, this.timezone})
    : super._();
  @override
  UpdateMeRequest rebuild(void Function(UpdateMeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateMeRequestBuilder toBuilder() => UpdateMeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateMeRequest &&
        displayName == other.displayName &&
        locale == other.locale &&
        timezone == other.timezone;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateMeRequest')
          ..add('displayName', displayName)
          ..add('locale', locale)
          ..add('timezone', timezone))
        .toString();
  }
}

class UpdateMeRequestBuilder
    implements Builder<UpdateMeRequest, UpdateMeRequestBuilder> {
  _$UpdateMeRequest? _$v;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _locale;
  String? get locale => _$this._locale;
  set locale(String? locale) => _$this._locale = locale;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  UpdateMeRequestBuilder() {
    UpdateMeRequest._defaults(this);
  }

  UpdateMeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayName = $v.displayName;
      _locale = $v.locale;
      _timezone = $v.timezone;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateMeRequest other) {
    _$v = other as _$UpdateMeRequest;
  }

  @override
  void update(void Function(UpdateMeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateMeRequest build() => _build();

  _$UpdateMeRequest _build() {
    final _$result =
        _$v ??
        _$UpdateMeRequest._(
          displayName: displayName,
          locale: locale,
          timezone: timezone,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
