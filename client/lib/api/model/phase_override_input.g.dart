// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phase_override_input.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhaseOverrideInput extends PhaseOverrideInput {
  @override
  final String? boundary;
  @override
  final Date? occurredOn;
  @override
  final String? phase;

  factory _$PhaseOverrideInput([
    void Function(PhaseOverrideInputBuilder)? updates,
  ]) => (PhaseOverrideInputBuilder()..update(updates))._build();

  _$PhaseOverrideInput._({this.boundary, this.occurredOn, this.phase})
    : super._();
  @override
  PhaseOverrideInput rebuild(
    void Function(PhaseOverrideInputBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PhaseOverrideInputBuilder toBuilder() =>
      PhaseOverrideInputBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhaseOverrideInput &&
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
    return (newBuiltValueToStringHelper(r'PhaseOverrideInput')
          ..add('boundary', boundary)
          ..add('occurredOn', occurredOn)
          ..add('phase', phase))
        .toString();
  }
}

class PhaseOverrideInputBuilder
    implements Builder<PhaseOverrideInput, PhaseOverrideInputBuilder> {
  _$PhaseOverrideInput? _$v;

  String? _boundary;
  String? get boundary => _$this._boundary;
  set boundary(String? boundary) => _$this._boundary = boundary;

  Date? _occurredOn;
  Date? get occurredOn => _$this._occurredOn;
  set occurredOn(Date? occurredOn) => _$this._occurredOn = occurredOn;

  String? _phase;
  String? get phase => _$this._phase;
  set phase(String? phase) => _$this._phase = phase;

  PhaseOverrideInputBuilder() {
    PhaseOverrideInput._defaults(this);
  }

  PhaseOverrideInputBuilder get _$this {
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
  void replace(PhaseOverrideInput other) {
    _$v = other as _$PhaseOverrideInput;
  }

  @override
  void update(void Function(PhaseOverrideInputBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhaseOverrideInput build() => _build();

  _$PhaseOverrideInput _build() {
    final _$result =
        _$v ??
        _$PhaseOverrideInput._(
          boundary: boundary,
          occurredOn: occurredOn,
          phase: phase,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
