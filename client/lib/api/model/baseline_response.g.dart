// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baseline_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BaselineResponse extends BaselineResponse {
  @override
  final String? diagnosedOn;
  @override
  final Date? dob;
  @override
  final String? endoStatus;
  @override
  final int? heightCm;
  @override
  final double? latestWeightKg;
  @override
  final int? rasrmStage;

  factory _$BaselineResponse([
    void Function(BaselineResponseBuilder)? updates,
  ]) => (BaselineResponseBuilder()..update(updates))._build();

  _$BaselineResponse._({
    this.diagnosedOn,
    this.dob,
    this.endoStatus,
    this.heightCm,
    this.latestWeightKg,
    this.rasrmStage,
  }) : super._();
  @override
  BaselineResponse rebuild(void Function(BaselineResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BaselineResponseBuilder toBuilder() =>
      BaselineResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BaselineResponse &&
        diagnosedOn == other.diagnosedOn &&
        dob == other.dob &&
        endoStatus == other.endoStatus &&
        heightCm == other.heightCm &&
        latestWeightKg == other.latestWeightKg &&
        rasrmStage == other.rasrmStage;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, diagnosedOn.hashCode);
    _$hash = $jc(_$hash, dob.hashCode);
    _$hash = $jc(_$hash, endoStatus.hashCode);
    _$hash = $jc(_$hash, heightCm.hashCode);
    _$hash = $jc(_$hash, latestWeightKg.hashCode);
    _$hash = $jc(_$hash, rasrmStage.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BaselineResponse')
          ..add('diagnosedOn', diagnosedOn)
          ..add('dob', dob)
          ..add('endoStatus', endoStatus)
          ..add('heightCm', heightCm)
          ..add('latestWeightKg', latestWeightKg)
          ..add('rasrmStage', rasrmStage))
        .toString();
  }
}

class BaselineResponseBuilder
    implements Builder<BaselineResponse, BaselineResponseBuilder> {
  _$BaselineResponse? _$v;

  String? _diagnosedOn;
  String? get diagnosedOn => _$this._diagnosedOn;
  set diagnosedOn(String? diagnosedOn) => _$this._diagnosedOn = diagnosedOn;

  Date? _dob;
  Date? get dob => _$this._dob;
  set dob(Date? dob) => _$this._dob = dob;

  String? _endoStatus;
  String? get endoStatus => _$this._endoStatus;
  set endoStatus(String? endoStatus) => _$this._endoStatus = endoStatus;

  int? _heightCm;
  int? get heightCm => _$this._heightCm;
  set heightCm(int? heightCm) => _$this._heightCm = heightCm;

  double? _latestWeightKg;
  double? get latestWeightKg => _$this._latestWeightKg;
  set latestWeightKg(double? latestWeightKg) =>
      _$this._latestWeightKg = latestWeightKg;

  int? _rasrmStage;
  int? get rasrmStage => _$this._rasrmStage;
  set rasrmStage(int? rasrmStage) => _$this._rasrmStage = rasrmStage;

  BaselineResponseBuilder() {
    BaselineResponse._defaults(this);
  }

  BaselineResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _diagnosedOn = $v.diagnosedOn;
      _dob = $v.dob;
      _endoStatus = $v.endoStatus;
      _heightCm = $v.heightCm;
      _latestWeightKg = $v.latestWeightKg;
      _rasrmStage = $v.rasrmStage;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BaselineResponse other) {
    _$v = other as _$BaselineResponse;
  }

  @override
  void update(void Function(BaselineResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BaselineResponse build() => _build();

  _$BaselineResponse _build() {
    final _$result =
        _$v ??
        _$BaselineResponse._(
          diagnosedOn: diagnosedOn,
          dob: dob,
          endoStatus: endoStatus,
          heightCm: heightCm,
          latestWeightKg: latestWeightKg,
          rasrmStage: rasrmStage,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
