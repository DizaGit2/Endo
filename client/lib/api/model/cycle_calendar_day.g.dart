// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_calendar_day.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CycleCalendarDay extends CycleCalendarDay {
  @override
  final Date? date;
  @override
  final int? eventCount;
  @override
  final bool? hasNotes;
  @override
  final int? mood;
  @override
  final int? pain;
  @override
  final int? symptomCount;

  factory _$CycleCalendarDay([
    void Function(CycleCalendarDayBuilder)? updates,
  ]) => (CycleCalendarDayBuilder()..update(updates))._build();

  _$CycleCalendarDay._({
    this.date,
    this.eventCount,
    this.hasNotes,
    this.mood,
    this.pain,
    this.symptomCount,
  }) : super._();
  @override
  CycleCalendarDay rebuild(void Function(CycleCalendarDayBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CycleCalendarDayBuilder toBuilder() =>
      CycleCalendarDayBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CycleCalendarDay &&
        date == other.date &&
        eventCount == other.eventCount &&
        hasNotes == other.hasNotes &&
        mood == other.mood &&
        pain == other.pain &&
        symptomCount == other.symptomCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, eventCount.hashCode);
    _$hash = $jc(_$hash, hasNotes.hashCode);
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, pain.hashCode);
    _$hash = $jc(_$hash, symptomCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CycleCalendarDay')
          ..add('date', date)
          ..add('eventCount', eventCount)
          ..add('hasNotes', hasNotes)
          ..add('mood', mood)
          ..add('pain', pain)
          ..add('symptomCount', symptomCount))
        .toString();
  }
}

class CycleCalendarDayBuilder
    implements Builder<CycleCalendarDay, CycleCalendarDayBuilder> {
  _$CycleCalendarDay? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  int? _eventCount;
  int? get eventCount => _$this._eventCount;
  set eventCount(int? eventCount) => _$this._eventCount = eventCount;

  bool? _hasNotes;
  bool? get hasNotes => _$this._hasNotes;
  set hasNotes(bool? hasNotes) => _$this._hasNotes = hasNotes;

  int? _mood;
  int? get mood => _$this._mood;
  set mood(int? mood) => _$this._mood = mood;

  int? _pain;
  int? get pain => _$this._pain;
  set pain(int? pain) => _$this._pain = pain;

  int? _symptomCount;
  int? get symptomCount => _$this._symptomCount;
  set symptomCount(int? symptomCount) => _$this._symptomCount = symptomCount;

  CycleCalendarDayBuilder() {
    CycleCalendarDay._defaults(this);
  }

  CycleCalendarDayBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _eventCount = $v.eventCount;
      _hasNotes = $v.hasNotes;
      _mood = $v.mood;
      _pain = $v.pain;
      _symptomCount = $v.symptomCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CycleCalendarDay other) {
    _$v = other as _$CycleCalendarDay;
  }

  @override
  void update(void Function(CycleCalendarDayBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CycleCalendarDay build() => _build();

  _$CycleCalendarDay _build() {
    final _$result =
        _$v ??
        _$CycleCalendarDay._(
          date: date,
          eventCount: eventCount,
          hasNotes: hasNotes,
          mood: mood,
          pain: pain,
          symptomCount: symptomCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
