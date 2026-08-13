// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phase_overrides_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhaseOverridesResponse extends PhaseOverridesResponse {
  @override
  final BuiltList<PhaseOverrideBoundary>? boundaries;
  @override
  final Date? cycleStartOn;

  factory _$PhaseOverridesResponse([
    void Function(PhaseOverridesResponseBuilder)? updates,
  ]) => (PhaseOverridesResponseBuilder()..update(updates))._build();

  _$PhaseOverridesResponse._({this.boundaries, this.cycleStartOn}) : super._();
  @override
  PhaseOverridesResponse rebuild(
    void Function(PhaseOverridesResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PhaseOverridesResponseBuilder toBuilder() =>
      PhaseOverridesResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhaseOverridesResponse &&
        boundaries == other.boundaries &&
        cycleStartOn == other.cycleStartOn;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, boundaries.hashCode);
    _$hash = $jc(_$hash, cycleStartOn.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhaseOverridesResponse')
          ..add('boundaries', boundaries)
          ..add('cycleStartOn', cycleStartOn))
        .toString();
  }
}

class PhaseOverridesResponseBuilder
    implements Builder<PhaseOverridesResponse, PhaseOverridesResponseBuilder> {
  _$PhaseOverridesResponse? _$v;

  ListBuilder<PhaseOverrideBoundary>? _boundaries;
  ListBuilder<PhaseOverrideBoundary> get boundaries =>
      _$this._boundaries ??= ListBuilder<PhaseOverrideBoundary>();
  set boundaries(ListBuilder<PhaseOverrideBoundary>? boundaries) =>
      _$this._boundaries = boundaries;

  Date? _cycleStartOn;
  Date? get cycleStartOn => _$this._cycleStartOn;
  set cycleStartOn(Date? cycleStartOn) => _$this._cycleStartOn = cycleStartOn;

  PhaseOverridesResponseBuilder() {
    PhaseOverridesResponse._defaults(this);
  }

  PhaseOverridesResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _boundaries = $v.boundaries?.toBuilder();
      _cycleStartOn = $v.cycleStartOn;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhaseOverridesResponse other) {
    _$v = other as _$PhaseOverridesResponse;
  }

  @override
  void update(void Function(PhaseOverridesResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhaseOverridesResponse build() => _build();

  _$PhaseOverridesResponse _build() {
    _$PhaseOverridesResponse _$result;
    try {
      _$result =
          _$v ??
          _$PhaseOverridesResponse._(
            boundaries: _boundaries?.build(),
            cycleStartOn: cycleStartOn,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'boundaries';
        _boundaries?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PhaseOverridesResponse',
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
