// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_me_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateMeRequest extends UpdateMeRequest {
  @override
  final String? displayName;

  factory _$UpdateMeRequest([void Function(UpdateMeRequestBuilder)? updates]) =>
      (UpdateMeRequestBuilder()..update(updates))._build();

  _$UpdateMeRequest._({this.displayName}) : super._();
  @override
  UpdateMeRequest rebuild(void Function(UpdateMeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateMeRequestBuilder toBuilder() => UpdateMeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateMeRequest && displayName == other.displayName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'UpdateMeRequest',
    )..add('displayName', displayName)).toString();
  }
}

class UpdateMeRequestBuilder
    implements Builder<UpdateMeRequest, UpdateMeRequestBuilder> {
  _$UpdateMeRequest? _$v;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  UpdateMeRequestBuilder() {
    UpdateMeRequest._defaults(this);
  }

  UpdateMeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayName = $v.displayName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateMeRequest other) {
    _$v = other as _$UpdateMeRequest;
  }

  @override
  void update(void Function(UpdateMeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateMeRequest build() => _build();

  _$UpdateMeRequest _build() {
    final _$result = _$v ?? _$UpdateMeRequest._(displayName: displayName);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
