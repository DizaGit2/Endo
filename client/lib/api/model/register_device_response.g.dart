// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_device_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RegisterDeviceResponse extends RegisterDeviceResponse {
  @override
  final DateTime? createdAt;
  @override
  final String? deviceId;
  @override
  final DateTime? lastSeenAt;
  @override
  final String? platform;

  factory _$RegisterDeviceResponse([
    void Function(RegisterDeviceResponseBuilder)? updates,
  ]) => (RegisterDeviceResponseBuilder()..update(updates))._build();

  _$RegisterDeviceResponse._({
    this.createdAt,
    this.deviceId,
    this.lastSeenAt,
    this.platform,
  }) : super._();
  @override
  RegisterDeviceResponse rebuild(
    void Function(RegisterDeviceResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  RegisterDeviceResponseBuilder toBuilder() =>
      RegisterDeviceResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegisterDeviceResponse &&
        createdAt == other.createdAt &&
        deviceId == other.deviceId &&
        lastSeenAt == other.lastSeenAt &&
        platform == other.platform;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, deviceId.hashCode);
    _$hash = $jc(_$hash, lastSeenAt.hashCode);
    _$hash = $jc(_$hash, platform.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegisterDeviceResponse')
          ..add('createdAt', createdAt)
          ..add('deviceId', deviceId)
          ..add('lastSeenAt', lastSeenAt)
          ..add('platform', platform))
        .toString();
  }
}

class RegisterDeviceResponseBuilder
    implements Builder<RegisterDeviceResponse, RegisterDeviceResponseBuilder> {
  _$RegisterDeviceResponse? _$v;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _deviceId;
  String? get deviceId => _$this._deviceId;
  set deviceId(String? deviceId) => _$this._deviceId = deviceId;

  DateTime? _lastSeenAt;
  DateTime? get lastSeenAt => _$this._lastSeenAt;
  set lastSeenAt(DateTime? lastSeenAt) => _$this._lastSeenAt = lastSeenAt;

  String? _platform;
  String? get platform => _$this._platform;
  set platform(String? platform) => _$this._platform = platform;

  RegisterDeviceResponseBuilder() {
    RegisterDeviceResponse._defaults(this);
  }

  RegisterDeviceResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _createdAt = $v.createdAt;
      _deviceId = $v.deviceId;
      _lastSeenAt = $v.lastSeenAt;
      _platform = $v.platform;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegisterDeviceResponse other) {
    _$v = other as _$RegisterDeviceResponse;
  }

  @override
  void update(void Function(RegisterDeviceResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegisterDeviceResponse build() => _build();

  _$RegisterDeviceResponse _build() {
    final _$result =
        _$v ??
        _$RegisterDeviceResponse._(
          createdAt: createdAt,
          deviceId: deviceId,
          lastSeenAt: lastSeenAt,
          platform: platform,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
