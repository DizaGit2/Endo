// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_device_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RegisterDeviceRequest extends RegisterDeviceRequest {
  @override
  final String? platform;
  @override
  final String? pushToken;

  factory _$RegisterDeviceRequest([
    void Function(RegisterDeviceRequestBuilder)? updates,
  ]) => (RegisterDeviceRequestBuilder()..update(updates))._build();

  _$RegisterDeviceRequest._({this.platform, this.pushToken}) : super._();
  @override
  RegisterDeviceRequest rebuild(
    void Function(RegisterDeviceRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  RegisterDeviceRequestBuilder toBuilder() =>
      RegisterDeviceRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegisterDeviceRequest &&
        platform == other.platform &&
        pushToken == other.pushToken;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, platform.hashCode);
    _$hash = $jc(_$hash, pushToken.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegisterDeviceRequest')
          ..add('platform', platform)
          ..add('pushToken', pushToken))
        .toString();
  }
}

class RegisterDeviceRequestBuilder
    implements Builder<RegisterDeviceRequest, RegisterDeviceRequestBuilder> {
  _$RegisterDeviceRequest? _$v;

  String? _platform;
  String? get platform => _$this._platform;
  set platform(String? platform) => _$this._platform = platform;

  String? _pushToken;
  String? get pushToken => _$this._pushToken;
  set pushToken(String? pushToken) => _$this._pushToken = pushToken;

  RegisterDeviceRequestBuilder() {
    RegisterDeviceRequest._defaults(this);
  }

  RegisterDeviceRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _platform = $v.platform;
      _pushToken = $v.pushToken;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegisterDeviceRequest other) {
    _$v = other as _$RegisterDeviceRequest;
  }

  @override
  void update(void Function(RegisterDeviceRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegisterDeviceRequest build() => _build();

  _$RegisterDeviceRequest _build() {
    final _$result =
        _$v ??
        _$RegisterDeviceRequest._(platform: platform, pushToken: pushToken);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
