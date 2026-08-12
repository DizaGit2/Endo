// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'http_validation_problem_details.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HttpValidationProblemDetails extends HttpValidationProblemDetails {
  @override
  final String? detail;
  @override
  final BuiltMap<String, BuiltList<String>>? errors;
  @override
  final String? instance;
  @override
  final int? status;
  @override
  final String? title;
  @override
  final String? type;

  factory _$HttpValidationProblemDetails([
    void Function(HttpValidationProblemDetailsBuilder)? updates,
  ]) => (HttpValidationProblemDetailsBuilder()..update(updates))._build();

  _$HttpValidationProblemDetails._({
    this.detail,
    this.errors,
    this.instance,
    this.status,
    this.title,
    this.type,
  }) : super._();
  @override
  HttpValidationProblemDetails rebuild(
    void Function(HttpValidationProblemDetailsBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  HttpValidationProblemDetailsBuilder toBuilder() =>
      HttpValidationProblemDetailsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HttpValidationProblemDetails &&
        detail == other.detail &&
        errors == other.errors &&
        instance == other.instance &&
        status == other.status &&
        title == other.title &&
        type == other.type;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, errors.hashCode);
    _$hash = $jc(_$hash, instance.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HttpValidationProblemDetails')
          ..add('detail', detail)
          ..add('errors', errors)
          ..add('instance', instance)
          ..add('status', status)
          ..add('title', title)
          ..add('type', type))
        .toString();
  }
}

class HttpValidationProblemDetailsBuilder
    implements
        Builder<
          HttpValidationProblemDetails,
          HttpValidationProblemDetailsBuilder
        > {
  _$HttpValidationProblemDetails? _$v;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  MapBuilder<String, BuiltList<String>>? _errors;
  MapBuilder<String, BuiltList<String>> get errors =>
      _$this._errors ??= MapBuilder<String, BuiltList<String>>();
  set errors(MapBuilder<String, BuiltList<String>>? errors) =>
      _$this._errors = errors;

  String? _instance;
  String? get instance => _$this._instance;
  set instance(String? instance) => _$this._instance = instance;

  int? _status;
  int? get status => _$this._status;
  set status(int? status) => _$this._status = status;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  HttpValidationProblemDetailsBuilder() {
    HttpValidationProblemDetails._defaults(this);
  }

  HttpValidationProblemDetailsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _detail = $v.detail;
      _errors = $v.errors?.toBuilder();
      _instance = $v.instance;
      _status = $v.status;
      _title = $v.title;
      _type = $v.type;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HttpValidationProblemDetails other) {
    _$v = other as _$HttpValidationProblemDetails;
  }

  @override
  void update(void Function(HttpValidationProblemDetailsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HttpValidationProblemDetails build() => _build();

  _$HttpValidationProblemDetails _build() {
    _$HttpValidationProblemDetails _$result;
    try {
      _$result =
          _$v ??
          _$HttpValidationProblemDetails._(
            detail: detail,
            errors: _errors?.build(),
            instance: instance,
            status: status,
            title: title,
            type: type,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'errors';
        _errors?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'HttpValidationProblemDetails',
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
