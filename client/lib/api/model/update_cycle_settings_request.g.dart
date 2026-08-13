// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_cycle_settings_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateCycleSettingsRequest extends UpdateCycleSettingsRequest {
  @override
  final bool? autoDetectPeriodStartEnabled;
  @override
  final int? avgCycleLengthDays;
  @override
  final int? avgPeriodLengthDays;
  @override
  final String? pauseReason;
  @override
  final Date? pausedSince;
  @override
  final bool? phasePredictionEnabled;
  @override
  final String? regularity;
  @override
  final bool? showFertilityWindowEnabled;
  @override
  final bool? trackingPaused;

  factory _$UpdateCycleSettingsRequest([
    void Function(UpdateCycleSettingsRequestBuilder)? updates,
  ]) => (UpdateCycleSettingsRequestBuilder()..update(updates))._build();

  _$UpdateCycleSettingsRequest._({
    this.autoDetectPeriodStartEnabled,
    this.avgCycleLengthDays,
    this.avgPeriodLengthDays,
    this.pauseReason,
    this.pausedSince,
    this.phasePredictionEnabled,
    this.regularity,
    this.showFertilityWindowEnabled,
    this.trackingPaused,
  }) : super._();
  @override
  UpdateCycleSettingsRequest rebuild(
    void Function(UpdateCycleSettingsRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  UpdateCycleSettingsRequestBuilder toBuilder() =>
      UpdateCycleSettingsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateCycleSettingsRequest &&
        autoDetectPeriodStartEnabled == other.autoDetectPeriodStartEnabled &&
        avgCycleLengthDays == other.avgCycleLengthDays &&
        avgPeriodLengthDays == other.avgPeriodLengthDays &&
        pauseReason == other.pauseReason &&
        pausedSince == other.pausedSince &&
        phasePredictionEnabled == other.phasePredictionEnabled &&
        regularity == other.regularity &&
        showFertilityWindowEnabled == other.showFertilityWindowEnabled &&
        trackingPaused == other.trackingPaused;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, autoDetectPeriodStartEnabled.hashCode);
    _$hash = $jc(_$hash, avgCycleLengthDays.hashCode);
    _$hash = $jc(_$hash, avgPeriodLengthDays.hashCode);
    _$hash = $jc(_$hash, pauseReason.hashCode);
    _$hash = $jc(_$hash, pausedSince.hashCode);
    _$hash = $jc(_$hash, phasePredictionEnabled.hashCode);
    _$hash = $jc(_$hash, regularity.hashCode);
    _$hash = $jc(_$hash, showFertilityWindowEnabled.hashCode);
    _$hash = $jc(_$hash, trackingPaused.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateCycleSettingsRequest')
          ..add('autoDetectPeriodStartEnabled', autoDetectPeriodStartEnabled)
          ..add('avgCycleLengthDays', avgCycleLengthDays)
          ..add('avgPeriodLengthDays', avgPeriodLengthDays)
          ..add('pauseReason', pauseReason)
          ..add('pausedSince', pausedSince)
          ..add('phasePredictionEnabled', phasePredictionEnabled)
          ..add('regularity', regularity)
          ..add('showFertilityWindowEnabled', showFertilityWindowEnabled)
          ..add('trackingPaused', trackingPaused))
        .toString();
  }
}

class UpdateCycleSettingsRequestBuilder
    implements
        Builder<UpdateCycleSettingsRequest, UpdateCycleSettingsRequestBuilder> {
  _$UpdateCycleSettingsRequest? _$v;

  bool? _autoDetectPeriodStartEnabled;
  bool? get autoDetectPeriodStartEnabled =>
      _$this._autoDetectPeriodStartEnabled;
  set autoDetectPeriodStartEnabled(bool? autoDetectPeriodStartEnabled) =>
      _$this._autoDetectPeriodStartEnabled = autoDetectPeriodStartEnabled;

  int? _avgCycleLengthDays;
  int? get avgCycleLengthDays => _$this._avgCycleLengthDays;
  set avgCycleLengthDays(int? avgCycleLengthDays) =>
      _$this._avgCycleLengthDays = avgCycleLengthDays;

  int? _avgPeriodLengthDays;
  int? get avgPeriodLengthDays => _$this._avgPeriodLengthDays;
  set avgPeriodLengthDays(int? avgPeriodLengthDays) =>
      _$this._avgPeriodLengthDays = avgPeriodLengthDays;

  String? _pauseReason;
  String? get pauseReason => _$this._pauseReason;
  set pauseReason(String? pauseReason) => _$this._pauseReason = pauseReason;

  Date? _pausedSince;
  Date? get pausedSince => _$this._pausedSince;
  set pausedSince(Date? pausedSince) => _$this._pausedSince = pausedSince;

  bool? _phasePredictionEnabled;
  bool? get phasePredictionEnabled => _$this._phasePredictionEnabled;
  set phasePredictionEnabled(bool? phasePredictionEnabled) =>
      _$this._phasePredictionEnabled = phasePredictionEnabled;

  String? _regularity;
  String? get regularity => _$this._regularity;
  set regularity(String? regularity) => _$this._regularity = regularity;

  bool? _showFertilityWindowEnabled;
  bool? get showFertilityWindowEnabled => _$this._showFertilityWindowEnabled;
  set showFertilityWindowEnabled(bool? showFertilityWindowEnabled) =>
      _$this._showFertilityWindowEnabled = showFertilityWindowEnabled;

  bool? _trackingPaused;
  bool? get trackingPaused => _$this._trackingPaused;
  set trackingPaused(bool? trackingPaused) =>
      _$this._trackingPaused = trackingPaused;

  UpdateCycleSettingsRequestBuilder() {
    UpdateCycleSettingsRequest._defaults(this);
  }

  UpdateCycleSettingsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _autoDetectPeriodStartEnabled = $v.autoDetectPeriodStartEnabled;
      _avgCycleLengthDays = $v.avgCycleLengthDays;
      _avgPeriodLengthDays = $v.avgPeriodLengthDays;
      _pauseReason = $v.pauseReason;
      _pausedSince = $v.pausedSince;
      _phasePredictionEnabled = $v.phasePredictionEnabled;
      _regularity = $v.regularity;
      _showFertilityWindowEnabled = $v.showFertilityWindowEnabled;
      _trackingPaused = $v.trackingPaused;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateCycleSettingsRequest other) {
    _$v = other as _$UpdateCycleSettingsRequest;
  }

  @override
  void update(void Function(UpdateCycleSettingsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateCycleSettingsRequest build() => _build();

  _$UpdateCycleSettingsRequest _build() {
    final _$result =
        _$v ??
        _$UpdateCycleSettingsRequest._(
          autoDetectPeriodStartEnabled: autoDetectPeriodStartEnabled,
          avgCycleLengthDays: avgCycleLengthDays,
          avgPeriodLengthDays: avgPeriodLengthDays,
          pauseReason: pauseReason,
          pausedSince: pausedSince,
          phasePredictionEnabled: phasePredictionEnabled,
          regularity: regularity,
          showFertilityWindowEnabled: showFertilityWindowEnabled,
          trackingPaused: trackingPaused,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
