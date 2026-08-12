// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_symptoms_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateSymptomsResponse extends CreateSymptomsResponse {
  @override
  final BuiltList<SymptomResponse>? items;

  factory _$CreateSymptomsResponse([
    void Function(CreateSymptomsResponseBuilder)? updates,
  ]) => (CreateSymptomsResponseBuilder()..update(updates))._build();

  _$CreateSymptomsResponse._({this.items}) : super._();
  @override
  CreateSymptomsResponse rebuild(
    void Function(CreateSymptomsResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CreateSymptomsResponseBuilder toBuilder() =>
      CreateSymptomsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateSymptomsResponse && items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'CreateSymptomsResponse',
    )..add('items', items)).toString();
  }
}

class CreateSymptomsResponseBuilder
    implements Builder<CreateSymptomsResponse, CreateSymptomsResponseBuilder> {
  _$CreateSymptomsResponse? _$v;

  ListBuilder<SymptomResponse>? _items;
  ListBuilder<SymptomResponse> get items =>
      _$this._items ??= ListBuilder<SymptomResponse>();
  set items(ListBuilder<SymptomResponse>? items) => _$this._items = items;

  CreateSymptomsResponseBuilder() {
    CreateSymptomsResponse._defaults(this);
  }

  CreateSymptomsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateSymptomsResponse other) {
    _$v = other as _$CreateSymptomsResponse;
  }

  @override
  void update(void Function(CreateSymptomsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateSymptomsResponse build() => _build();

  _$CreateSymptomsResponse _build() {
    _$CreateSymptomsResponse _$result;
    try {
      _$result = _$v ?? _$CreateSymptomsResponse._(items: _items?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        _items?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CreateSymptomsResponse',
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
