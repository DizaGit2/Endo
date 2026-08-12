// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_symptoms_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateSymptomsRequest extends CreateSymptomsRequest {
  @override
  final BuiltList<SymptomEntryInput>? entries;

  factory _$CreateSymptomsRequest([
    void Function(CreateSymptomsRequestBuilder)? updates,
  ]) => (CreateSymptomsRequestBuilder()..update(updates))._build();

  _$CreateSymptomsRequest._({this.entries}) : super._();
  @override
  CreateSymptomsRequest rebuild(
    void Function(CreateSymptomsRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CreateSymptomsRequestBuilder toBuilder() =>
      CreateSymptomsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateSymptomsRequest && entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'CreateSymptomsRequest',
    )..add('entries', entries)).toString();
  }
}

class CreateSymptomsRequestBuilder
    implements Builder<CreateSymptomsRequest, CreateSymptomsRequestBuilder> {
  _$CreateSymptomsRequest? _$v;

  ListBuilder<SymptomEntryInput>? _entries;
  ListBuilder<SymptomEntryInput> get entries =>
      _$this._entries ??= ListBuilder<SymptomEntryInput>();
  set entries(ListBuilder<SymptomEntryInput>? entries) =>
      _$this._entries = entries;

  CreateSymptomsRequestBuilder() {
    CreateSymptomsRequest._defaults(this);
  }

  CreateSymptomsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateSymptomsRequest other) {
    _$v = other as _$CreateSymptomsRequest;
  }

  @override
  void update(void Function(CreateSymptomsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateSymptomsRequest build() => _build();

  _$CreateSymptomsRequest _build() {
    _$CreateSymptomsRequest _$result;
    try {
      _$result = _$v ?? _$CreateSymptomsRequest._(entries: _entries?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        _entries?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CreateSymptomsRequest',
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
