// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'problem_details.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ProblemDetails extends ProblemDetails {
  @override
  final String? detail;
  @override
  final String? instance;
  @override
  final int? status;
  @override
  final String? title;
  @override
  final String? type;

  factory _$ProblemDetails([void Function(ProblemDetailsBuilder)? updates]) =>
      (ProblemDetailsBuilder()..update(updates))._build();

  _$ProblemDetails._({
    this.detail,
    this.instance,
    this.status,
    this.title,
    this.type,
  }) : super._();
  @override
  ProblemDetails rebuild(void Function(ProblemDetailsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ProblemDetailsBuilder toBuilder() => ProblemDetailsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ProblemDetails &&
        detail == other.detail &&
        instance == other.instance &&
        status == other.status &&
        title == other.title &&
        type == other.type;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, instance.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ProblemDetails')
          ..add('detail', detail)
          ..add('instance', instance)
          ..add('status', status)
          ..add('title', title)
          ..add('type', type))
        .toString();
  }
}

class ProblemDetailsBuilder
    implements Builder<ProblemDetails, ProblemDetailsBuilder> {
  _$ProblemDetails? _$v;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

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

  ProblemDetailsBuilder() {
    ProblemDetails._defaults(this);
  }

  ProblemDetailsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _detail = $v.detail;
      _instance = $v.instance;
      _status = $v.status;
      _title = $v.title;
      _type = $v.type;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ProblemDetails other) {
    _$v = other as _$ProblemDetails;
  }

  @override
  void update(void Function(ProblemDetailsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ProblemDetails build() => _build();

  _$ProblemDetails _build() {
    final _$result =
        _$v ??
        _$ProblemDetails._(
          detail: detail,
          instance: instance,
          status: status,
          title: title,
          type: type,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
