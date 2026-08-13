// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_phase_overrides_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SavePhaseOverridesRequest extends SavePhaseOverridesRequest {
  @override
  final BuiltList<PhaseOverrideInput>? boundaries;
  @override
  final Date? cycleStartOn;

  factory _$SavePhaseOverridesRequest([
    void Function(SavePhaseOverridesRequestBuilder)? updates,
  ]) => (SavePhaseOverridesRequestBuilder()..update(updates))._build();

  _$SavePhaseOverridesRequest._({this.boundaries, this.cycleStartOn})
    : super._();
  @override
  SavePhaseOverridesRequest rebuild(
    void Function(SavePhaseOverridesRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SavePhaseOverridesRequestBuilder toBuilder() =>
      SavePhaseOverridesRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SavePhaseOverridesRequest &&
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
    return (newBuiltValueToStringHelper(r'SavePhaseOverridesRequest')
          ..add('boundaries', boundaries)
          ..add('cycleStartOn', cycleStartOn))
        .toString();
  }
}

class SavePhaseOverridesRequestBuilder
    implements
        Builder<SavePhaseOverridesRequest, SavePhaseOverridesRequestBuilder> {
  _$SavePhaseOverridesRequest? _$v;

  ListBuilder<PhaseOverrideInput>? _boundaries;
  ListBuilder<PhaseOverrideInput> get boundaries =>
      _$this._boundaries ??= ListBuilder<PhaseOverrideInput>();
  set boundaries(ListBuilder<PhaseOverrideInput>? boundaries) =>
      _$this._boundaries = boundaries;

  Date? _cycleStartOn;
  Date? get cycleStartOn => _$this._cycleStartOn;
  set cycleStartOn(Date? cycleStartOn) => _$this._cycleStartOn = cycleStartOn;

  SavePhaseOverridesRequestBuilder() {
    SavePhaseOverridesRequest._defaults(this);
  }

  SavePhaseOverridesRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _boundaries = $v.boundaries?.toBuilder();
      _cycleStartOn = $v.cycleStartOn;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SavePhaseOverridesRequest other) {
    _$v = other as _$SavePhaseOverridesRequest;
  }

  @override
  void update(void Function(SavePhaseOverridesRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SavePhaseOverridesRequest build() => _build();

  _$SavePhaseOverridesRequest _build() {
    _$SavePhaseOverridesRequest _$result;
    try {
      _$result =
          _$v ??
          _$SavePhaseOverridesRequest._(
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
          r'SavePhaseOverridesRequest',
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
