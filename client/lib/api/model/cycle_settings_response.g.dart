// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_settings_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CycleSettingsResponse extends CycleSettingsResponse {
  @override
  final bool? autoDetectPeriodStartEnabled;
  @override
  final int? avgCycleLengthDays;
  @override
  final int? avgPeriodLengthDays;
  @override
  final DateTime? createdAt;
  @override
  final String? pauseReason;
  @override
  final Date? pausedSince;
  @override
  final bool? phasePredictionEnabled;
  @override
  final bool? phasesUnavailable;
  @override
  final String? regularity;
  @override
  final bool? showFertilityWindowEnabled;
  @override
  final bool? trackingPaused;
  @override
  final DateTime? updatedAt;
  @override
  final BuiltList<String>? warnings;

  factory _$CycleSettingsResponse([
    void Function(CycleSettingsResponseBuilder)? updates,
  ]) => (CycleSettingsResponseBuilder()..update(updates))._build();

  _$CycleSettingsResponse._({
    this.autoDetectPeriodStartEnabled,
    this.avgCycleLengthDays,
    this.avgPeriodLengthDays,
    this.createdAt,
    this.pauseReason,
    this.pausedSince,
    this.phasePredictionEnabled,
    this.phasesUnavailable,
    this.regularity,
    this.showFertilityWindowEnabled,
    this.trackingPaused,
    this.updatedAt,
    this.warnings,
  }) : super._();
  @override
  CycleSettingsResponse rebuild(
    void Function(CycleSettingsResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CycleSettingsResponseBuilder toBuilder() =>
      CycleSettingsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CycleSettingsResponse &&
        autoDetectPeriodStartEnabled == other.autoDetectPeriodStartEnabled &&
        avgCycleLengthDays == other.avgCycleLengthDays &&
        avgPeriodLengthDays == other.avgPeriodLengthDays &&
        createdAt == other.createdAt &&
        pauseReason == other.pauseReason &&
        pausedSince == other.pausedSince &&
        phasePredictionEnabled == other.phasePredictionEnabled &&
        phasesUnavailable == other.phasesUnavailable &&
        regularity == other.regularity &&
        showFertilityWindowEnabled == other.showFertilityWindowEnabled &&
        trackingPaused == other.trackingPaused &&
        updatedAt == other.updatedAt &&
        warnings == other.warnings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, autoDetectPeriodStartEnabled.hashCode);
    _$hash = $jc(_$hash, avgCycleLengthDays.hashCode);
    _$hash = $jc(_$hash, avgPeriodLengthDays.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, pauseReason.hashCode);
    _$hash = $jc(_$hash, pausedSince.hashCode);
    _$hash = $jc(_$hash, phasePredictionEnabled.hashCode);
    _$hash = $jc(_$hash, phasesUnavailable.hashCode);
    _$hash = $jc(_$hash, regularity.hashCode);
    _$hash = $jc(_$hash, showFertilityWindowEnabled.hashCode);
    _$hash = $jc(_$hash, trackingPaused.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, warnings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CycleSettingsResponse')
          ..add('autoDetectPeriodStartEnabled', autoDetectPeriodStartEnabled)
          ..add('avgCycleLengthDays', avgCycleLengthDays)
          ..add('avgPeriodLengthDays', avgPeriodLengthDays)
          ..add('createdAt', createdAt)
          ..add('pauseReason', pauseReason)
          ..add('pausedSince', pausedSince)
          ..add('phasePredictionEnabled', phasePredictionEnabled)
          ..add('phasesUnavailable', phasesUnavailable)
          ..add('regularity', regularity)
          ..add('showFertilityWindowEnabled', showFertilityWindowEnabled)
          ..add('trackingPaused', trackingPaused)
          ..add('updatedAt', updatedAt)
          ..add('warnings', warnings))
        .toString();
  }
}

class CycleSettingsResponseBuilder
    implements Builder<CycleSettingsResponse, CycleSettingsResponseBuilder> {
  _$CycleSettingsResponse? _$v;

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

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

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

  bool? _phasesUnavailable;
  bool? get phasesUnavailable => _$this._phasesUnavailable;
  set phasesUnavailable(bool? phasesUnavailable) =>
      _$this._phasesUnavailable = phasesUnavailable;

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

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  ListBuilder<String>? _warnings;
  ListBuilder<String> get warnings =>
      _$this._warnings ??= ListBuilder<String>();
  set warnings(ListBuilder<String>? warnings) => _$this._warnings = warnings;

  CycleSettingsResponseBuilder() {
    CycleSettingsResponse._defaults(this);
  }

  CycleSettingsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _autoDetectPeriodStartEnabled = $v.autoDetectPeriodStartEnabled;
      _avgCycleLengthDays = $v.avgCycleLengthDays;
      _avgPeriodLengthDays = $v.avgPeriodLengthDays;
      _createdAt = $v.createdAt;
      _pauseReason = $v.pauseReason;
      _pausedSince = $v.pausedSince;
      _phasePredictionEnabled = $v.phasePredictionEnabled;
      _phasesUnavailable = $v.phasesUnavailable;
      _regularity = $v.regularity;
      _showFertilityWindowEnabled = $v.showFertilityWindowEnabled;
      _trackingPaused = $v.trackingPaused;
      _updatedAt = $v.updatedAt;
      _warnings = $v.warnings?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CycleSettingsResponse other) {
    _$v = other as _$CycleSettingsResponse;
  }

  @override
  void update(void Function(CycleSettingsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CycleSettingsResponse build() => _build();

  _$CycleSettingsResponse _build() {
    _$CycleSettingsResponse _$result;
    try {
      _$result =
          _$v ??
          _$CycleSettingsResponse._(
            autoDetectPeriodStartEnabled: autoDetectPeriodStartEnabled,
            avgCycleLengthDays: avgCycleLengthDays,
            avgPeriodLengthDays: avgPeriodLengthDays,
            createdAt: createdAt,
            pauseReason: pauseReason,
            pausedSince: pausedSince,
            phasePredictionEnabled: phasePredictionEnabled,
            phasesUnavailable: phasesUnavailable,
            regularity: regularity,
            showFertilityWindowEnabled: showFertilityWindowEnabled,
            trackingPaused: trackingPaused,
            updatedAt: updatedAt,
            warnings: _warnings?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'warnings';
        _warnings?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CycleSettingsResponse',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
