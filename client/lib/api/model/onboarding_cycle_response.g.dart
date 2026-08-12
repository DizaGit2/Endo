// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_cycle_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OnboardingCycleResponse extends OnboardingCycleResponse {
  @override
  final int? avgCycleLengthDays;
  @override
  final int? avgPeriodLengthDays;
  @override
  final Date? lastPeriodStart;
  @override
  final String? regularity;
  @override
  final BuiltList<String>? warnings;

  factory _$OnboardingCycleResponse([
    void Function(OnboardingCycleResponseBuilder)? updates,
  ]) => (OnboardingCycleResponseBuilder()..update(updates))._build();

  _$OnboardingCycleResponse._({
    this.avgCycleLengthDays,
    this.avgPeriodLengthDays,
    this.lastPeriodStart,
    this.regularity,
    this.warnings,
  }) : super._();
  @override
  OnboardingCycleResponse rebuild(
    void Function(OnboardingCycleResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  OnboardingCycleResponseBuilder toBuilder() =>
      OnboardingCycleResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OnboardingCycleResponse &&
        avgCycleLengthDays == other.avgCycleLengthDays &&
        avgPeriodLengthDays == other.avgPeriodLengthDays &&
        lastPeriodStart == other.lastPeriodStart &&
        regularity == other.regularity &&
        warnings == other.warnings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, avgCycleLengthDays.hashCode);
    _$hash = $jc(_$hash, avgPeriodLengthDays.hashCode);
    _$hash = $jc(_$hash, lastPeriodStart.hashCode);
    _$hash = $jc(_$hash, regularity.hashCode);
    _$hash = $jc(_$hash, warnings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OnboardingCycleResponse')
          ..add('avgCycleLengthDays', avgCycleLengthDays)
          ..add('avgPeriodLengthDays', avgPeriodLengthDays)
          ..add('lastPeriodStart', lastPeriodStart)
          ..add('regularity', regularity)
          ..add('warnings', warnings))
        .toString();
  }
}

class OnboardingCycleResponseBuilder
    implements
        Builder<OnboardingCycleResponse, OnboardingCycleResponseBuilder> {
  _$OnboardingCycleResponse? _$v;

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

  ListBuilder<String>? _warnings;
  ListBuilder<String> get warnings =>
      _$this._warnings ??= ListBuilder<String>();
  set warnings(ListBuilder<String>? warnings) => _$this._warnings = warnings;

  OnboardingCycleResponseBuilder() {
    OnboardingCycleResponse._defaults(this);
  }

  OnboardingCycleResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _avgCycleLengthDays = $v.avgCycleLengthDays;
      _avgPeriodLengthDays = $v.avgPeriodLengthDays;
      _lastPeriodStart = $v.lastPeriodStart;
      _regularity = $v.regularity;
      _warnings = $v.warnings?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OnboardingCycleResponse other) {
    _$v = other as _$OnboardingCycleResponse;
  }

  @override
  void update(void Function(OnboardingCycleResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OnboardingCycleResponse build() => _build();

  _$OnboardingCycleResponse _build() {
    _$OnboardingCycleResponse _$result;
    try {
      _$result =
          _$v ??
          _$OnboardingCycleResponse._(
            avgCycleLengthDays: avgCycleLengthDays,
            avgPeriodLengthDays: avgPeriodLengthDays,
            lastPeriodStart: lastPeriodStart,
            regularity: regularity,
            warnings: _warnings?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'warnings';
        _warnings?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OnboardingCycleResponse',
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
