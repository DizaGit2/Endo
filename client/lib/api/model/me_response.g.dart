// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'me_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MeResponse extends MeResponse {
  @override
  final String? diagnosedOn;
  @override
  final String? displayName;
  @override
  final Date? dob;
  @override
  final String? endoStatus;
  @override
  final int? heightCm;
  @override
  final String? id;
  @override
  final double? latestWeightKg;
  @override
  final String? locale;
  @override
  final bool? onboardingCompleted;
  @override
  final int? rasrmStage;
  @override
  final String? timezone;

  factory _$MeResponse([void Function(MeResponseBuilder)? updates]) =>
      (MeResponseBuilder()..update(updates))._build();

  _$MeResponse._({
    this.diagnosedOn,
    this.displayName,
    this.dob,
    this.endoStatus,
    this.heightCm,
    this.id,
    this.latestWeightKg,
    this.locale,
    this.onboardingCompleted,
    this.rasrmStage,
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
        diagnosedOn == other.diagnosedOn &&
        displayName == other.displayName &&
        dob == other.dob &&
        endoStatus == other.endoStatus &&
        heightCm == other.heightCm &&
        id == other.id &&
        latestWeightKg == other.latestWeightKg &&
        locale == other.locale &&
        onboardingCompleted == other.onboardingCompleted &&
        rasrmStage == other.rasrmStage &&
        timezone == other.timezone;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, diagnosedOn.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, dob.hashCode);
    _$hash = $jc(_$hash, endoStatus.hashCode);
    _$hash = $jc(_$hash, heightCm.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, latestWeightKg.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, onboardingCompleted.hashCode);
    _$hash = $jc(_$hash, rasrmStage.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MeResponse')
          ..add('diagnosedOn', diagnosedOn)
          ..add('displayName', displayName)
          ..add('dob', dob)
          ..add('endoStatus', endoStatus)
          ..add('heightCm', heightCm)
          ..add('id', id)
          ..add('latestWeightKg', latestWeightKg)
          ..add('locale', locale)
          ..add('onboardingCompleted', onboardingCompleted)
          ..add('rasrmStage', rasrmStage)
          ..add('timezone', timezone))
        .toString();
  }
}

class MeResponseBuilder implements Builder<MeResponse, MeResponseBuilder> {
  _$MeResponse? _$v;

  String? _diagnosedOn;
  String? get diagnosedOn => _$this._diagnosedOn;
  set diagnosedOn(String? diagnosedOn) => _$this._diagnosedOn = diagnosedOn;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  Date? _dob;
  Date? get dob => _$this._dob;
  set dob(Date? dob) => _$this._dob = dob;

  String? _endoStatus;
  String? get endoStatus => _$this._endoStatus;
  set endoStatus(String? endoStatus) => _$this._endoStatus = endoStatus;

  int? _heightCm;
  int? get heightCm => _$this._heightCm;
  set heightCm(int? heightCm) => _$this._heightCm = heightCm;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  double? _latestWeightKg;
  double? get latestWeightKg => _$this._latestWeightKg;
  set latestWeightKg(double? latestWeightKg) =>
      _$this._latestWeightKg = latestWeightKg;

  String? _locale;
  String? get locale => _$this._locale;
  set locale(String? locale) => _$this._locale = locale;

  bool? _onboardingCompleted;
  bool? get onboardingCompleted => _$this._onboardingCompleted;
  set onboardingCompleted(bool? onboardingCompleted) =>
      _$this._onboardingCompleted = onboardingCompleted;

  int? _rasrmStage;
  int? get rasrmStage => _$this._rasrmStage;
  set rasrmStage(int? rasrmStage) => _$this._rasrmStage = rasrmStage;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  MeResponseBuilder() {
    MeResponse._defaults(this);
  }

  MeResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _diagnosedOn = $v.diagnosedOn;
      _displayName = $v.displayName;
      _dob = $v.dob;
      _endoStatus = $v.endoStatus;
      _heightCm = $v.heightCm;
      _id = $v.id;
      _latestWeightKg = $v.latestWeightKg;
      _locale = $v.locale;
      _onboardingCompleted = $v.onboardingCompleted;
      _rasrmStage = $v.rasrmStage;
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
          diagnosedOn: diagnosedOn,
          displayName: displayName,
          dob: dob,
          endoStatus: endoStatus,
          heightCm: heightCm,
          id: id,
          latestWeightKg: latestWeightKg,
          locale: locale,
          onboardingCompleted: onboardingCompleted,
          rasrmStage: rasrmStage,
          timezone: timezone,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
