// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'me_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MeResponse extends MeResponse {
  @override
  final String? displayName;
  @override
  final String? id;
  @override
  final String? locale;
  @override
  final bool? onboardingCompleted;
  @override
  final String? timezone;

  factory _$MeResponse([void Function(MeResponseBuilder)? updates]) =>
      (MeResponseBuilder()..update(updates))._build();

  _$MeResponse._({
    this.displayName,
    this.id,
    this.locale,
    this.onboardingCompleted,
    this.timezone,
  }) : super._();
  @override
  MeResponse rebuild(void Function(MeResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MeResponseBuilder toBuilder() => MeResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MeResponse &&
        displayName == other.displayName &&
        id == other.id &&
        locale == other.locale &&
        onboardingCompleted == other.onboardingCompleted &&
        timezone == other.timezone;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, onboardingCompleted.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MeResponse')
          ..add('displayName', displayName)
          ..add('id', id)
          ..add('locale', locale)
          ..add('onboardingCompleted', onboardingCompleted)
          ..add('timezone', timezone))
        .toString();
  }
}

class MeResponseBuilder implements Builder<MeResponse, MeResponseBuilder> {
  _$MeResponse? _$v;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _locale;
  String? get locale => _$this._locale;
  set locale(String? locale) => _$this._locale = locale;

  bool? _onboardingCompleted;
  bool? get onboardingCompleted => _$this._onboardingCompleted;
  set onboardingCompleted(bool? onboardingCompleted) =>
      _$this._onboardingCompleted = onboardingCompleted;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  MeResponseBuilder() {
    MeResponse._defaults(this);
  }

  MeResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayName = $v.displayName;
      _id = $v.id;
      _locale = $v.locale;
      _onboardingCompleted = $v.onboardingCompleted;
      _timezone = $v.timezone;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MeResponse other) {
    _$v = other as _$MeResponse;
  }

  @override
  void update(void Function(MeResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MeResponse build() => _build();

  _$MeResponse _build() {
    final _$result =
        _$v ??
        _$MeResponse._(
          displayName: displayName,
          id: id,
          locale: locale,
          onboardingCompleted: onboardingCompleted,
          timezone: timezone,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
