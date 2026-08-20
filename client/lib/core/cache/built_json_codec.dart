// ---------------------------------------------------------------------------
// built_json_codec — the built_value <-> JSON-map pair every cache-backed
// repository needs, collapsed to one copy (P4b-T14b).
// ---------------------------------------------------------------------------
//
// Six verbatim copies of this exact pair (two in `CycleRepository`, one each
// in `MeRepository`, `CycleSettingsRepository`, `OnboardingRepository` and
// `SymptomsRepository`) existed before this file did — one per cached
// response type, all doing the same three steps in the same order. This is
// the shared, generic version; `cachedRead`'s `toJson`/`fromJson` parameters
// already take a closure of the right shape (`Map<String, dynamic>
// Function(T)` / `T Function(Map<String, dynamic>)`), so a call site wraps
// [toCacheJson] / [fromCacheJson] with its own serializer and nothing else
// changes.

import 'dart:convert';

import 'package:built_value/serializer.dart';
import 'package:lumen/api/serializers.dart';

/// Serializes a built_value object to a plain, JSON-safe
/// `Map<String, dynamic>` for storage in the Hive cache box.
///
/// Uses [standardSerializers] — the package-wide [Serializers] instance
/// (`lib/api/serializers.dart`) with `StandardJsonPlugin` installed, which is
/// what turns built_value's native flat key/value-pair wire format into a
/// regular JSON object keyed by wire name. The result is then round-tripped
/// through `json.encode`/`json.decode` to strip any value
/// `serializeWith` left that is not itself JSON-safe (a `DateTime`, for
/// instance) — the same reason every one of the six original copies did this
/// same round trip rather than returning `serializeWith`'s result directly.
///
/// [serializer] must be the `T.serializer` static getter the built_value code
/// generator produced for [T] — there is no "malformed input" case on this
/// side: [value] is already a well-typed [T], so the only way this call fails
/// is a serializer/type mismatch, which throws whatever built_value itself
/// throws (a programming error, not a data error).
Map<String, dynamic> toCacheJson<T>(Serializer<T> serializer, T value) {
  final encoded = standardSerializers.serializeWith(serializer, value);
  return json.decode(json.encode(encoded)) as Map<String, dynamic>;
}

/// Deserializes a `Map<String, dynamic>` — typically one this same box handed
/// back from [toCacheJson] — into a [T] using [standardSerializers] (see
/// [toCacheJson]).
///
/// **Malformed input.** Every property the OpenAPI generator produces on
/// these response types is nullable, so a key that is simply ABSENT from
/// [map] is not an error: the corresponding field decodes as `null`, the same
/// as if the server itself had omitted it. An unrecognised key is silently
/// ignored (built_value collects it into an internal "unhandled" list that
/// nothing reads). What is NOT tolerated is a key whose *value* cannot be
/// coerced to its declared wire type (a string where a number was expected,
/// for example) — that throws a [DeserializationError] out of
/// `standardSerializers.deserializeWith`, uncaught. This function adds no
/// try/catch of its own: a cache entry that fails to decode this way is a
/// corrupt box, not a recoverable state, and every original copy let it
/// propagate the same way.
///
/// The trailing `!` asserts non-null on the result: `deserializeWith` is
/// `T?`-typed in general (it also serves callers deserializing `null`
/// itself), but a [map] that decodes at all always yields a `T`, never a bare
/// `null`. Every one of the six original copies used the same `!` against a
/// concrete (non-generic) `T?`, where this lint does not fire; ignored here
/// only because making `T` generic is what makes the analyzer flag it — the
/// runtime behaviour (a thrown `TypeError` on an actual null) is unchanged.
T fromCacheJson<T>(Serializer<T> serializer, Map<String, dynamic> map) {
  // ignore: null_check_on_nullable_type_parameter
  return standardSerializers.deserializeWith(serializer, map)!;
}
