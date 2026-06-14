// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_start_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OnboardingStartRequest extends OnboardingStartRequest {
  @override
  final String? displayName;
  @override
  final String? email;
  @override
  final String? locale;
  @override
  final String? password;
  @override
  final String? policyVersion;
  @override
  final String? timezone;

  factory _$OnboardingStartRequest([
    void Function(OnboardingStartRequestBuilder)? updates,
  ]) => (OnboardingStartRequestBuilder()..update(updates))._build();

  _$OnboardingStartRequest._({
    this.displayName,
    this.email,
    this.locale,
    this.password,
    this.policyVersion,
    this.timezone,
  }) : super._();
  @override
  OnboardingStartRequest rebuild(
    void Function(OnboardingStartRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  OnboardingStartRequestBuilder toBuilder() =>
      OnboardingStartRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OnboardingStartRequest &&
        displayName == other.displayName &&
        email == other.email &&
        locale == other.locale &&
        password == other.password &&
        policyVersion == other.policyVersion &&
        timezone == other.timezone;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, policyVersion.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OnboardingStartRequest')
          ..add('displayName', displayName)
          ..add('email', email)
          ..add('locale', locale)
          ..add('password', password)
          ..add('policyVersion', policyVersion)
          ..add('timezone', timezone))
        .toString();
  }
}

class OnboardingStartRequestBuilder
    implements Builder<OnboardingStartRequest, OnboardingStartRequestBuilder> {
  _$OnboardingStartRequest? _$v;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _locale;
  String? get locale => _$this._locale;
  set locale(String? locale) => _$this._locale = locale;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  String? _policyVersion;
  String? get policyVersion => _$this._policyVersion;
  set policyVersion(String? policyVersion) =>
      _$this._policyVersion = policyVersion;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  OnboardingStartRequestBuilder() {
    OnboardingStartRequest._defaults(this);
  }

  OnboardingStartRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayName = $v.displayName;
      _email = $v.email;
      _locale = $v.locale;
      _password = $v.password;
      _policyVersion = $v.policyVersion;
      _timezone = $v.timezone;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OnboardingStartRequest other) {
    _$v = other as _$OnboardingStartRequest;
  }

  @override
  void update(void Function(OnboardingStartRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OnboardingStartRequest build() => _build();

  _$OnboardingStartRequest _build() {
    final _$result =
        _$v ??
        _$OnboardingStartRequest._(
          displayName: displayName,
          email: email,
          locale: locale,
          password: password,
          policyVersion: policyVersion,
          timezone: timezone,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
