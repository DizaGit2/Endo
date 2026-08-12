// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'symptom_list_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SymptomListResponse extends SymptomListResponse {
  @override
  final BuiltList<SymptomResponse>? items;
  @override
  final int? limit;
  @override
  final int? offset;
  @override
  final int? total;

  factory _$SymptomListResponse([
    void Function(SymptomListResponseBuilder)? updates,
  ]) => (SymptomListResponseBuilder()..update(updates))._build();

  _$SymptomListResponse._({this.items, this.limit, this.offset, this.total})
    : super._();
  @override
  SymptomListResponse rebuild(
    void Function(SymptomListResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SymptomListResponseBuilder toBuilder() =>
      SymptomListResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SymptomListResponse &&
        items == other.items &&
        limit == other.limit &&
        offset == other.offset &&
        total == other.total;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, limit.hashCode);
    _$hash = $jc(_$hash, offset.hashCode);
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SymptomListResponse')
          ..add('items', items)
          ..add('limit', limit)
          ..add('offset', offset)
          ..add('total', total))
        .toString();
  }
}

class SymptomListResponseBuilder
    implements Builder<SymptomListResponse, SymptomListResponseBuilder> {
  _$SymptomListResponse? _$v;

  ListBuilder<SymptomResponse>? _items;
  ListBuilder<SymptomResponse> get items =>
      _$this._items ??= ListBuilder<SymptomResponse>();
  set items(ListBuilder<SymptomResponse>? items) => _$this._items = items;

  int? _limit;
  int? get limit => _$this._limit;
  set limit(int? limit) => _$this._limit = limit;

  int? _offset;
  int? get offset => _$this._offset;
  set offset(int? offset) => _$this._offset = offset;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  SymptomListResponseBuilder() {
    SymptomListResponse._defaults(this);
  }

  SymptomListResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items?.toBuilder();
      _limit = $v.limit;
      _offset = $v.offset;
      _total = $v.total;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SymptomListResponse other) {
    _$v = other as _$SymptomListResponse;
  }

  @override
  void update(void Function(SymptomListResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SymptomListResponse build() => _build();

  _$SymptomListResponse _build() {
    _$SymptomListResponse _$result;
    try {
      _$result =
          _$v ??
          _$SymptomListResponse._(
            items: _items?.build(),
            limit: limit,
            offset: offset,
            total: total,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        _items?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SymptomListResponse',
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
