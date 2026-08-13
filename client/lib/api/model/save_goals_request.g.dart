// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_goals_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SaveGoalsRequest extends SaveGoalsRequest {
  @override
  final BuiltList<String>? goals;

  factory _$SaveGoalsRequest([
    void Function(SaveGoalsRequestBuilder)? updates,
  ]) => (SaveGoalsRequestBuilder()..update(updates))._build();

  _$SaveGoalsRequest._({this.goals}) : super._();
  @override
  SaveGoalsRequest rebuild(void Function(SaveGoalsRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SaveGoalsRequestBuilder toBuilder() =>
      SaveGoalsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SaveGoalsRequest && goals == other.goals;
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
      r'SaveGoalsRequest',
    )..add('goals', goals)).toString();
  }
}

class SaveGoalsRequestBuilder
    implements Builder<SaveGoalsRequest, SaveGoalsRequestBuilder> {
  _$SaveGoalsRequest? _$v;

  ListBuilder<String>? _goals;
  ListBuilder<String> get goals => _$this._goals ??= ListBuilder<String>();
  set goals(ListBuilder<String>? goals) => _$this._goals = goals;

  SaveGoalsRequestBuilder() {
    SaveGoalsRequest._defaults(this);
  }

  SaveGoalsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _goals = $v.goals?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SaveGoalsRequest other) {
    _$v = other as _$SaveGoalsRequest;
  }

  @override
  void update(void Function(SaveGoalsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SaveGoalsRequest build() => _build();

  _$SaveGoalsRequest _build() {
    _$SaveGoalsRequest _$result;
    try {
      _$result = _$v ?? _$SaveGoalsRequest._(goals: _goals?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'goals';
        _goals?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SaveGoalsRequest',
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
