// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_phase_availability_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CyclePhaseAvailabilityResponse extends CyclePhaseAvailabilityResponse {
  @override
  final bool? available;
  @override
  final String? unavailableReason;

  factory _$CyclePhaseAvailabilityResponse([
    void Function(CyclePhaseAvailabilityResponseBuilder)? updates,
  ]) => (CyclePhaseAvailabilityResponseBuilder()..update(updates))._build();

  _$CyclePhaseAvailabilityResponse._({this.available, this.unavailableReason})
    : super._();
  @override
  CyclePhaseAvailabilityResponse rebuild(
    void Function(CyclePhaseAvailabilityResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CyclePhaseAvailabilityResponseBuilder toBuilder() =>
      CyclePhaseAvailabilityResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CyclePhaseAvailabilityResponse &&
        available == other.available &&
        unavailableReason == other.unavailableReason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, available.hashCode);
    _$hash = $jc(_$hash, unavailableReason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CyclePhaseAvailabilityResponse')
          ..add('available', available)
          ..add('unavailableReason', unavailableReason))
        .toString();
  }
}

class CyclePhaseAvailabilityResponseBuilder
    implements
        Builder<
          CyclePhaseAvailabilityResponse,
          CyclePhaseAvailabilityResponseBuilder
        > {
  _$CyclePhaseAvailabilityResponse? _$v;

  bool? _available;
  bool? get available => _$this._available;
  set available(bool? available) => _$this._available = available;

  String? _unavailableReason;
  String? get unavailableReason => _$this._unavailableReason;
  set unavailableReason(String? unavailableReason) =>
      _$this._unavailableReason = unavailableReason;

  CyclePhaseAvailabilityResponseBuilder() {
    CyclePhaseAvailabilityResponse._defaults(this);
  }

  CyclePhaseAvailabilityResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _available = $v.available;
      _unavailableReason = $v.unavailableReason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CyclePhaseAvailabilityResponse other) {
    _$v = other as _$CyclePhaseAvailabilityResponse;
  }

  @override
  void update(void Function(CyclePhaseAvailabilityResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CyclePhaseAvailabilityResponse build() => _build();

  _$CyclePhaseAvailabilityResponse _build() {
    final _$result =
        _$v ??
        _$CyclePhaseAvailabilityResponse._(
          available: available,
          unavailableReason: unavailableReason,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
