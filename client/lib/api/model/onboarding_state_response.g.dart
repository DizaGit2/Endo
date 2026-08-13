// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_state_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OnboardingStateResponse extends OnboardingStateResponse {
  @override
  final bool? baselineProvided;
  @override
  final bool? completed;
  @override
  final DateTime? completedAt;
  @override
  final bool? cycleProvided;
  @override
  final BuiltList<GoalSelection>? goals;
  @override
  final bool? goalsProvided;
  @override
  final BuiltList<HormoneSelection>? hormones;
  @override
  final bool? hormonesProvided;
  @override
  final Date? lastPeriodStart;
  @override
  final BuiltList<String>? missingMandatorySteps;
  @override
  final BuiltList<NotificationCategorySelection>? notifications;
  @override
  final bool? notificationsProvided;

  factory _$OnboardingStateResponse([
    void Function(OnboardingStateResponseBuilder)? updates,
  ]) => (OnboardingStateResponseBuilder()..update(updates))._build();

  _$OnboardingStateResponse._({
    this.baselineProvided,
    this.completed,
    this.completedAt,
    this.cycleProvided,
    this.goals,
    this.goalsProvided,
    this.hormones,
    this.hormonesProvided,
    this.lastPeriodStart,
    this.missingMandatorySteps,
    this.notifications,
    this.notificationsProvided,
  }) : super._();
  @override
  OnboardingStateResponse rebuild(
    void Function(OnboardingStateResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  OnboardingStateResponseBuilder toBuilder() =>
      OnboardingStateResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OnboardingStateResponse &&
        baselineProvided == other.baselineProvided &&
        completed == other.completed &&
        completedAt == other.completedAt &&
        cycleProvided == other.cycleProvided &&
        goals == other.goals &&
        goalsProvided == other.goalsProvided &&
        hormones == other.hormones &&
        hormonesProvided == other.hormonesProvided &&
        lastPeriodStart == other.lastPeriodStart &&
        missingMandatorySteps == other.missingMandatorySteps &&
        notifications == other.notifications &&
        notificationsProvided == other.notificationsProvided;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, baselineProvided.hashCode);
    _$hash = $jc(_$hash, completed.hashCode);
    _$hash = $jc(_$hash, completedAt.hashCode);
    _$hash = $jc(_$hash, cycleProvided.hashCode);
    _$hash = $jc(_$hash, goals.hashCode);
    _$hash = $jc(_$hash, goalsProvided.hashCode);
    _$hash = $jc(_$hash, hormones.hashCode);
    _$hash = $jc(_$hash, hormonesProvided.hashCode);
    _$hash = $jc(_$hash, lastPeriodStart.hashCode);
    _$hash = $jc(_$hash, missingMandatorySteps.hashCode);
    _$hash = $jc(_$hash, notifications.hashCode);
    _$hash = $jc(_$hash, notificationsProvided.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OnboardingStateResponse')
          ..add('baselineProvided', baselineProvided)
          ..add('completed', completed)
          ..add('completedAt', completedAt)
          ..add('cycleProvided', cycleProvided)
          ..add('goals', goals)
          ..add('goalsProvided', goalsProvided)
          ..add('hormones', hormones)
          ..add('hormonesProvided', hormonesProvided)
          ..add('lastPeriodStart', lastPeriodStart)
          ..add('missingMandatorySteps', missingMandatorySteps)
          ..add('notifications', notifications)
          ..add('notificationsProvided', notificationsProvided))
        .toString();
  }
}

class OnboardingStateResponseBuilder
    implements
        Builder<OnboardingStateResponse, OnboardingStateResponseBuilder> {
  _$OnboardingStateResponse? _$v;

  bool? _baselineProvided;
  bool? get baselineProvided => _$this._baselineProvided;
  set baselineProvided(bool? baselineProvided) =>
      _$this._baselineProvided = baselineProvided;

  bool? _completed;
  bool? get completed => _$this._completed;
  set completed(bool? completed) => _$this._completed = completed;

  DateTime? _completedAt;
  DateTime? get completedAt => _$this._completedAt;
  set completedAt(DateTime? completedAt) => _$this._completedAt = completedAt;

  bool? _cycleProvided;
  bool? get cycleProvided => _$this._cycleProvided;
  set cycleProvided(bool? cycleProvided) =>
      _$this._cycleProvided = cycleProvided;

  ListBuilder<GoalSelection>? _goals;
  ListBuilder<GoalSelection> get goals =>
      _$this._goals ??= ListBuilder<GoalSelection>();
  set goals(ListBuilder<GoalSelection>? goals) => _$this._goals = goals;

  bool? _goalsProvided;
  bool? get goalsProvided => _$this._goalsProvided;
  set goalsProvided(bool? goalsProvided) =>
      _$this._goalsProvided = goalsProvided;

  ListBuilder<HormoneSelection>? _hormones;
  ListBuilder<HormoneSelection> get hormones =>
      _$this._hormones ??= ListBuilder<HormoneSelection>();
  set hormones(ListBuilder<HormoneSelection>? hormones) =>
      _$this._hormones = hormones;

  bool? _hormonesProvided;
  bool? get hormonesProvided => _$this._hormonesProvided;
  set hormonesProvided(bool? hormonesProvided) =>
      _$this._hormonesProvided = hormonesProvided;

  Date? _lastPeriodStart;
  Date? get lastPeriodStart => _$this._lastPeriodStart;
  set lastPeriodStart(Date? lastPeriodStart) =>
      _$this._lastPeriodStart = lastPeriodStart;

  ListBuilder<String>? _missingMandatorySteps;
  ListBuilder<String> get missingMandatorySteps =>
      _$this._missingMandatorySteps ??= ListBuilder<String>();
  set missingMandatorySteps(ListBuilder<String>? missingMandatorySteps) =>
      _$this._missingMandatorySteps = missingMandatorySteps;

  ListBuilder<NotificationCategorySelection>? _notifications;
  ListBuilder<NotificationCategorySelection> get notifications =>
      _$this._notifications ??= ListBuilder<NotificationCategorySelection>();
  set notifications(
    ListBuilder<NotificationCategorySelection>? notifications,
  ) => _$this._notifications = notifications;

  bool? _notificationsProvided;
  bool? get notificationsProvided => _$this._notificationsProvided;
  set notificationsProvided(bool? notificationsProvided) =>
      _$this._notificationsProvided = notificationsProvided;

  OnboardingStateResponseBuilder() {
    OnboardingStateResponse._defaults(this);
  }

  OnboardingStateResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _baselineProvided = $v.baselineProvided;
      _completed = $v.completed;
      _completedAt = $v.completedAt;
      _cycleProvided = $v.cycleProvided;
      _goals = $v.goals?.toBuilder();
      _goalsProvided = $v.goalsProvided;
      _hormones = $v.hormones?.toBuilder();
      _hormonesProvided = $v.hormonesProvided;
      _lastPeriodStart = $v.lastPeriodStart;
      _missingMandatorySteps = $v.missingMandatorySteps?.toBuilder();
      _notifications = $v.notifications?.toBuilder();
      _notificationsProvided = $v.notificationsProvided;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OnboardingStateResponse other) {
    _$v = other as _$OnboardingStateResponse;
  }

  @override
  void update(void Function(OnboardingStateResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OnboardingStateResponse build() => _build();

  _$OnboardingStateResponse _build() {
    _$OnboardingStateResponse _$result;
    try {
      _$result =
          _$v ??
          _$OnboardingStateResponse._(
            baselineProvided: baselineProvided,
            completed: completed,
            completedAt: completedAt,
            cycleProvided: cycleProvided,
            goals: _goals?.build(),
            goalsProvided: goalsProvided,
            hormones: _hormones?.build(),
            hormonesProvided: hormonesProvided,
            lastPeriodStart: lastPeriodStart,
            missingMandatorySteps: _missingMandatorySteps?.build(),
            notifications: _notifications?.build(),
            notificationsProvided: notificationsProvided,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'goals';
        _goals?.build();

        _$failedField = 'hormones';
        _hormones?.build();

        _$failedField = 'missingMandatorySteps';
        _missingMandatorySteps?.build();
        _$failedField = 'notifications';
        _notifications?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OnboardingStateResponse',
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
