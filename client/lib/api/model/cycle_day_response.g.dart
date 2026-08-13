// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_day_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CycleDayResponse extends CycleDayResponse {
  @override
  final Date? date;
  @override
  final BuiltList<CycleEventResponse>? events;
  @override
  final CycleDayLogResponse? log;
  @override
  final BuiltList<PhaseOverrideBoundary>? phaseOverrides;

  factory _$CycleDayResponse([
    void Function(CycleDayResponseBuilder)? updates,
  ]) => (CycleDayResponseBuilder()..update(updates))._build();

  _$CycleDayResponse._({this.date, this.events, this.log, this.phaseOverrides})
    : super._();
  @override
  CycleDayResponse rebuild(void Function(CycleDayResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CycleDayResponseBuilder toBuilder() =>
      CycleDayResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CycleDayResponse &&
        date == other.date &&
        events == other.events &&
        log == other.log &&
        phaseOverrides == other.phaseOverrides;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, events.hashCode);
    _$hash = $jc(_$hash, log.hashCode);
    _$hash = $jc(_$hash, phaseOverrides.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CycleDayResponse')
          ..add('date', date)
          ..add('events', events)
          ..add('log', log)
          ..add('phaseOverrides', phaseOverrides))
        .toString();
  }
}

class CycleDayResponseBuilder
    implements Builder<CycleDayResponse, CycleDayResponseBuilder> {
  _$CycleDayResponse? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  ListBuilder<CycleEventResponse>? _events;
  ListBuilder<CycleEventResponse> get events =>
      _$this._events ??= ListBuilder<CycleEventResponse>();
  set events(ListBuilder<CycleEventResponse>? events) =>
      _$this._events = events;

  CycleDayLogResponseBuilder? _log;
  CycleDayLogResponseBuilder get log =>
      _$this._log ??= CycleDayLogResponseBuilder();
  set log(CycleDayLogResponseBuilder? log) => _$this._log = log;

  ListBuilder<PhaseOverrideBoundary>? _phaseOverrides;
  ListBuilder<PhaseOverrideBoundary> get phaseOverrides =>
      _$this._phaseOverrides ??= ListBuilder<PhaseOverrideBoundary>();
  set phaseOverrides(ListBuilder<PhaseOverrideBoundary>? phaseOverrides) =>
      _$this._phaseOverrides = phaseOverrides;

  CycleDayResponseBuilder() {
    CycleDayResponse._defaults(this);
  }

  CycleDayResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _events = $v.events?.toBuilder();
      _log = $v.log?.toBuilder();
      _phaseOverrides = $v.phaseOverrides?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CycleDayResponse other) {
    _$v = other as _$CycleDayResponse;
  }

  @override
  void update(void Function(CycleDayResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CycleDayResponse build() => _build();

  _$CycleDayResponse _build() {
    _$CycleDayResponse _$result;
    try {
      _$result =
          _$v ??
          _$CycleDayResponse._(
            date: date,
            events: _events?.build(),
            log: _log?.build(),
            phaseOverrides: _phaseOverrides?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'events';
        _events?.build();
        _$failedField = 'log';
        _log?.build();
        _$failedField = 'phaseOverrides';
        _phaseOverrides?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CycleDayResponse',
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
