// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_calendar_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CycleCalendarResponse extends CycleCalendarResponse {
  @override
  final BuiltList<CycleCalendarDay>? days;
  @override
  final Date? from;
  @override
  final CyclePhaseAvailabilityResponse? phase;
  @override
  final String? timezone;
  @override
  final Date? to;
  @override
  final Date? today;

  factory _$CycleCalendarResponse([
    void Function(CycleCalendarResponseBuilder)? updates,
  ]) => (CycleCalendarResponseBuilder()..update(updates))._build();

  _$CycleCalendarResponse._({
    this.days,
    this.from,
    this.phase,
    this.timezone,
    this.to,
    this.today,
  }) : super._();
  @override
  CycleCalendarResponse rebuild(
    void Function(CycleCalendarResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CycleCalendarResponseBuilder toBuilder() =>
      CycleCalendarResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CycleCalendarResponse &&
        days == other.days &&
        from == other.from &&
        phase == other.phase &&
        timezone == other.timezone &&
        to == other.to &&
        today == other.today;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, days.hashCode);
    _$hash = $jc(_$hash, from.hashCode);
    _$hash = $jc(_$hash, phase.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jc(_$hash, to.hashCode);
    _$hash = $jc(_$hash, today.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CycleCalendarResponse')
          ..add('days', days)
          ..add('from', from)
          ..add('phase', phase)
          ..add('timezone', timezone)
          ..add('to', to)
          ..add('today', today))
        .toString();
  }
}

class CycleCalendarResponseBuilder
    implements Builder<CycleCalendarResponse, CycleCalendarResponseBuilder> {
  _$CycleCalendarResponse? _$v;

  ListBuilder<CycleCalendarDay>? _days;
  ListBuilder<CycleCalendarDay> get days =>
      _$this._days ??= ListBuilder<CycleCalendarDay>();
  set days(ListBuilder<CycleCalendarDay>? days) => _$this._days = days;

  Date? _from;
  Date? get from => _$this._from;
  set from(Date? from) => _$this._from = from;

  CyclePhaseAvailabilityResponseBuilder? _phase;
  CyclePhaseAvailabilityResponseBuilder get phase =>
      _$this._phase ??= CyclePhaseAvailabilityResponseBuilder();
  set phase(CyclePhaseAvailabilityResponseBuilder? phase) =>
      _$this._phase = phase;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  Date? _to;
  Date? get to => _$this._to;
  set to(Date? to) => _$this._to = to;

  Date? _today;
  Date? get today => _$this._today;
  set today(Date? today) => _$this._today = today;

  CycleCalendarResponseBuilder() {
    CycleCalendarResponse._defaults(this);
  }

  CycleCalendarResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _days = $v.days?.toBuilder();
      _from = $v.from;
      _phase = $v.phase?.toBuilder();
      _timezone = $v.timezone;
      _to = $v.to;
      _today = $v.today;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CycleCalendarResponse other) {
    _$v = other as _$CycleCalendarResponse;
  }

  @override
  void update(void Function(CycleCalendarResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CycleCalendarResponse build() => _build();

  _$CycleCalendarResponse _build() {
    _$CycleCalendarResponse _$result;
    try {
      _$result =
          _$v ??
          _$CycleCalendarResponse._(
            days: _days?.build(),
            from: from,
            phase: _phase?.build(),
            timezone: timezone,
            to: to,
            today: today,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'days';
        _days?.build();

        _$failedField = 'phase';
        _phase?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CycleCalendarResponse',
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
