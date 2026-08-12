// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phase_override_boundary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhaseOverrideBoundary extends PhaseOverrideBoundary {
  @override
  final String? boundary;
  @override
  final Date? occurredOn;
  @override
  final String? phase;

  factory _$PhaseOverrideBoundary([
    void Function(PhaseOverrideBoundaryBuilder)? updates,
  ]) => (PhaseOverrideBoundaryBuilder()..update(updates))._build();

  _$PhaseOverrideBoundary._({this.boundary, this.occurredOn, this.phase})
    : super._();
  @override
  PhaseOverrideBoundary rebuild(
    void Function(PhaseOverrideBoundaryBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PhaseOverrideBoundaryBuilder toBuilder() =>
      PhaseOverrideBoundaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhaseOverrideBoundary &&
        boundary == other.boundary &&
        occurredOn == other.occurredOn &&
        phase == other.phase;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, boundary.hashCode);
    _$hash = $jc(_$hash, occurredOn.hashCode);
    _$hash = $jc(_$hash, phase.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhaseOverrideBoundary')
          ..add('boundary', boundary)
          ..add('occurredOn', occurredOn)
          ..add('phase', phase))
        .toString();
  }
}

class PhaseOverrideBoundaryBuilder
    implements Builder<PhaseOverrideBoundary, PhaseOverrideBoundaryBuilder> {
  _$PhaseOverrideBoundary? _$v;

  String? _boundary;
  String? get boundary => _$this._boundary;
  set boundary(String? boundary) => _$this._boundary = boundary;

  Date? _occurredOn;
  Date? get occurredOn => _$this._occurredOn;
  set occurredOn(Date? occurredOn) => _$this._occurredOn = occurredOn;

  String? _phase;
  String? get phase => _$this._phase;
  set phase(String? phase) => _$this._phase = phase;

  PhaseOverrideBoundaryBuilder() {
    PhaseOverrideBoundary._defaults(this);
  }

  PhaseOverrideBoundaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _boundary = $v.boundary;
      _occurredOn = $v.occurredOn;
      _phase = $v.phase;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhaseOverrideBoundary other) {
    _$v = other as _$PhaseOverrideBoundary;
  }

  @override
  void update(void Function(PhaseOverrideBoundaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhaseOverrideBoundary build() => _build();

  _$PhaseOverrideBoundary _build() {
    final _$result =
        _$v ??
        _$PhaseOverrideBoundary._(
          boundary: boundary,
          occurredOn: occurredOn,
          phase: phase,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
