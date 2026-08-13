// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_baseline_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SaveBaselineRequest extends SaveBaselineRequest {
  @override
  final String? diagnosedOn;
  @override
  final Date? dob;
  @override
  final String? endoStatus;
  @override
  final int? heightCm;
  @override
  final int? rasrmStage;
  @override
  final double? weightKg;

  factory _$SaveBaselineRequest([
    void Function(SaveBaselineRequestBuilder)? updates,
  ]) => (SaveBaselineRequestBuilder()..update(updates))._build();

  _$SaveBaselineRequest._({
    this.diagnosedOn,
    this.dob,
    this.endoStatus,
    this.heightCm,
    this.rasrmStage,
    this.weightKg,
  }) : super._();
  @override
  SaveBaselineRequest rebuild(
    void Function(SaveBaselineRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SaveBaselineRequestBuilder toBuilder() =>
      SaveBaselineRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SaveBaselineRequest &&
        diagnosedOn == other.diagnosedOn &&
        dob == other.dob &&
        endoStatus == other.endoStatus &&
        heightCm == other.heightCm &&
        rasrmStage == other.rasrmStage &&
        weightKg == other.weightKg;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, diagnosedOn.hashCode);
    _$hash = $jc(_$hash, dob.hashCode);
    _$hash = $jc(_$hash, endoStatus.hashCode);
    _$hash = $jc(_$hash, heightCm.hashCode);
    _$hash = $jc(_$hash, rasrmStage.hashCode);
    _$hash = $jc(_$hash, weightKg.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SaveBaselineRequest')
          ..add('diagnosedOn', diagnosedOn)
          ..add('dob', dob)
          ..add('endoStatus', endoStatus)
          ..add('heightCm', heightCm)
          ..add('rasrmStage', rasrmStage)
          ..add('weightKg', weightKg))
        .toString();
  }
}

class SaveBaselineRequestBuilder
    implements Builder<SaveBaselineRequest, SaveBaselineRequestBuilder> {
  _$SaveBaselineRequest? _$v;

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

  int? _rasrmStage;
  int? get rasrmStage => _$this._rasrmStage;
  set rasrmStage(int? rasrmStage) => _$this._rasrmStage = rasrmStage;

  double? _weightKg;
  double? get weightKg => _$this._weightKg;
  set weightKg(double? weightKg) => _$this._weightKg = weightKg;

  SaveBaselineRequestBuilder() {
    SaveBaselineRequest._defaults(this);
  }

  SaveBaselineRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _diagnosedOn = $v.diagnosedOn;
      _dob = $v.dob;
      _endoStatus = $v.endoStatus;
      _heightCm = $v.heightCm;
      _rasrmStage = $v.rasrmStage;
      _weightKg = $v.weightKg;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SaveBaselineRequest other) {
    _$v = other as _$SaveBaselineRequest;
  }

  @override
  void update(void Function(SaveBaselineRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SaveBaselineRequest build() => _build();

  _$SaveBaselineRequest _build() {
    final _$result =
        _$v ??
        _$SaveBaselineRequest._(
          diagnosedOn: diagnosedOn,
          dob: dob,
          endoStatus: endoStatus,
          heightCm: heightCm,
          rasrmStage: rasrmStage,
          weightKg: weightKg,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
