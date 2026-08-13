// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_complete_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OnboardingCompleteResponse extends OnboardingCompleteResponse {
  @override
  final bool? alreadyCompleted;
  @override
  final DateTime? completedAt;

  factory _$OnboardingCompleteResponse([
    void Function(OnboardingCompleteResponseBuilder)? updates,
  ]) => (OnboardingCompleteResponseBuilder()..update(updates))._build();

  _$OnboardingCompleteResponse._({this.alreadyCompleted, this.completedAt})
    : super._();
  @override
  OnboardingCompleteResponse rebuild(
    void Function(OnboardingCompleteResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  OnboardingCompleteResponseBuilder toBuilder() =>
      OnboardingCompleteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OnboardingCompleteResponse &&
        alreadyCompleted == other.alreadyCompleted &&
        completedAt == other.completedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, alreadyCompleted.hashCode);
    _$hash = $jc(_$hash, completedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OnboardingCompleteResponse')
          ..add('alreadyCompleted', alreadyCompleted)
          ..add('completedAt', completedAt))
        .toString();
  }
}

class OnboardingCompleteResponseBuilder
    implements
        Builder<OnboardingCompleteResponse, OnboardingCompleteResponseBuilder> {
  _$OnboardingCompleteResponse? _$v;

  bool? _alreadyCompleted;
  bool? get alreadyCompleted => _$this._alreadyCompleted;
  set alreadyCompleted(bool? alreadyCompleted) =>
      _$this._alreadyCompleted = alreadyCompleted;

  DateTime? _completedAt;
  DateTime? get completedAt => _$this._completedAt;
  set completedAt(DateTime? completedAt) => _$this._completedAt = completedAt;

  OnboardingCompleteResponseBuilder() {
    OnboardingCompleteResponse._defaults(this);
  }

  OnboardingCompleteResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _alreadyCompleted = $v.alreadyCompleted;
      _completedAt = $v.completedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OnboardingCompleteResponse other) {
    _$v = other as _$OnboardingCompleteResponse;
  }

  @override
  void update(void Function(OnboardingCompleteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OnboardingCompleteResponse build() => _build();

  _$OnboardingCompleteResponse _build() {
    final _$result =
        _$v ??
        _$OnboardingCompleteResponse._(
          alreadyCompleted: alreadyCompleted,
          completedAt: completedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
