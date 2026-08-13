// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_start_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OnboardingStartResponse extends OnboardingStartResponse {
  @override
  final String? userId;

  factory _$OnboardingStartResponse([
    void Function(OnboardingStartResponseBuilder)? updates,
  ]) => (OnboardingStartResponseBuilder()..update(updates))._build();

  _$OnboardingStartResponse._({this.userId}) : super._();
  @override
  OnboardingStartResponse rebuild(
    void Function(OnboardingStartResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  OnboardingStartResponseBuilder toBuilder() =>
      OnboardingStartResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OnboardingStartResponse && userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'OnboardingStartResponse',
    )..add('userId', userId)).toString();
  }
}

class OnboardingStartResponseBuilder
    implements
        Builder<OnboardingStartResponse, OnboardingStartResponseBuilder> {
  _$OnboardingStartResponse? _$v;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  OnboardingStartResponseBuilder() {
    OnboardingStartResponse._defaults(this);
  }

  OnboardingStartResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OnboardingStartResponse other) {
    _$v = other as _$OnboardingStartResponse;
  }

  @override
  void update(void Function(OnboardingStartResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OnboardingStartResponse build() => _build();

  _$OnboardingStartResponse _build() {
    final _$result = _$v ?? _$OnboardingStartResponse._(userId: userId);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
