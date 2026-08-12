// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_onboarding_cycle_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SaveOnboardingCycleRequest extends SaveOnboardingCycleRequest {
  @override
  final int? avgCycleLengthDays;
  @override
  final int? avgPeriodLengthDays;
  @override
  final Date? lastPeriodStart;
  @override
  final String? regularity;

  factory _$SaveOnboardingCycleRequest([
    void Function(SaveOnboardingCycleRequestBuilder)? updates,
  ]) => (SaveOnboardingCycleRequestBuilder()..update(updates))._build();

  _$SaveOnboardingCycleRequest._({
    this.avgCycleLengthDays,
    this.avgPeriodLengthDays,
    this.lastPeriodStart,
    this.regularity,
  }) : super._();
  @override
  SaveOnboardingCycleRequest rebuild(
    void Function(SaveOnboardingCycleRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SaveOnboardingCycleRequestBuilder toBuilder() =>
      SaveOnboardingCycleRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SaveOnboardingCycleRequest &&
        avgCycleLengthDays == other.avgCycleLengthDays &&
        avgPeriodLengthDays == other.avgPeriodLengthDays &&
        lastPeriodStart == other.lastPeriodStart &&
        regularity == other.regularity;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, avgCycleLengthDays.hashCode);
    _$hash = $jc(_$hash, avgPeriodLengthDays.hashCode);
    _$hash = $jc(_$hash, lastPeriodStart.hashCode);
    _$hash = $jc(_$hash, regularity.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SaveOnboardingCycleRequest')
          ..add('avgCycleLengthDays', avgCycleLengthDays)
          ..add('avgPeriodLengthDays', avgPeriodLengthDays)
          ..add('lastPeriodStart', lastPeriodStart)
          ..add('regularity', regularity))
        .toString();
  }
}

class SaveOnboardingCycleRequestBuilder
    implements
        Builder<SaveOnboardingCycleRequest, SaveOnboardingCycleRequestBuilder> {
  _$SaveOnboardingCycleRequest? _$v;

  int? _avgCycleLengthDays;
  int? get avgCycleLengthDays => _$this._avgCycleLengthDays;
  set avgCycleLengthDays(int? avgCycleLengthDays) =>
      _$this._avgCycleLengthDays = avgCycleLengthDays;

  int? _avgPeriodLengthDays;
  int? get avgPeriodLengthDays => _$this._avgPeriodLengthDays;
  set avgPeriodLengthDays(int? avgPeriodLengthDays) =>
      _$this._avgPeriodLengthDays = avgPeriodLengthDays;

  Date? _lastPeriodStart;
  Date? get lastPeriodStart => _$this._lastPeriodStart;
  set lastPeriodStart(Date? lastPeriodStart) =>
      _$this._lastPeriodStart = lastPeriodStart;

  String? _regularity;
  String? get regularity => _$this._regularity;
  set regularity(String? regularity) => _$this._regularity = regularity;

  SaveOnboardingCycleRequestBuilder() {
    SaveOnboardingCycleRequest._defaults(this);
  }

  SaveOnboardingCycleRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _avgCycleLengthDays = $v.avgCycleLengthDays;
      _avgPeriodLengthDays = $v.avgPeriodLengthDays;
      _lastPeriodStart = $v.lastPeriodStart;
      _regularity = $v.regularity;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SaveOnboardingCycleRequest other) {
    _$v = other as _$SaveOnboardingCycleRequest;
  }

  @override
  void update(void Function(SaveOnboardingCycleRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SaveOnboardingCycleRequest build() => _build();

  _$SaveOnboardingCycleRequest _build() {
    final _$result =
        _$v ??
        _$SaveOnboardingCycleRequest._(
          avgCycleLengthDays: avgCycleLengthDays,
          avgPeriodLengthDays: avgPeriodLengthDays,
          lastPeriodStart: lastPeriodStart,
          regularity: regularity,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
