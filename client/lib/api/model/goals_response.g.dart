// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goals_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GoalsResponse extends GoalsResponse {
  @override
  final BuiltList<GoalSelection>? goals;

  factory _$GoalsResponse([void Function(GoalsResponseBuilder)? updates]) =>
      (GoalsResponseBuilder()..update(updates))._build();

  _$GoalsResponse._({this.goals}) : super._();
  @override
  GoalsResponse rebuild(void Function(GoalsResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GoalsResponseBuilder toBuilder() => GoalsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GoalsResponse && goals == other.goals;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, goals.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'GoalsResponse',
    )..add('goals', goals)).toString();
  }
}

class GoalsResponseBuilder
    implements Builder<GoalsResponse, GoalsResponseBuilder> {
  _$GoalsResponse? _$v;

  ListBuilder<GoalSelection>? _goals;
  ListBuilder<GoalSelection> get goals =>
      _$this._goals ??= ListBuilder<GoalSelection>();
  set goals(ListBuilder<GoalSelection>? goals) => _$this._goals = goals;

  GoalsResponseBuilder() {
    GoalsResponse._defaults(this);
  }

  GoalsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _goals = $v.goals?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GoalsResponse other) {
    _$v = other as _$GoalsResponse;
  }

  @override
  void update(void Function(GoalsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GoalsResponse build() => _build();

  _$GoalsResponse _build() {
    _$GoalsResponse _$result;
    try {
      _$result = _$v ?? _$GoalsResponse._(goals: _goals?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'goals';
        _goals?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'GoalsResponse',
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
