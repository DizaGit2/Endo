import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_start_request.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/api/serializers.dart';
import 'package:lumen/core/cache/cache_keys.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/error_mapper.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// OnboardingRepository
// ---------------------------------------------------------------------------

/// The onboarding feature's one door to the API.
///
/// Three operations today, and they belong together because they are three
/// points on one flow rather than three features:
///
/// - [startOnboarding] — `POST /onboarding/start`, screen 2 (P3b).
/// - [getState]        — `GET /onboarding/state`, the resume read every one of
///                       screens 3-7 lands behind.
/// - [complete]        — `POST /onboarding/complete`, the end of the flow.
///
/// **What [getState] deliberately does NOT do.** It returns the response whole
/// and narrows nothing. `OnboardingStateResponse` carries `lastPeriodStart`,
/// the three preference lists and the five step booleans, and screens 3-7 each
/// prefill from a different subset — a narrowed model here would force the next
/// five tasks either to re-read the endpoint or to widen this one, and the
/// widening would happen five times.
///
/// **The one asymmetry to know about** (§C.0.1, `POST /onboarding/cycle`):
/// `GET /onboarding/state` answers `lastPeriodStart` but **not**
/// `avgCycleLengthDays`, `avgPeriodLengthDays` or `regularity`. Screen 3 needs
/// all four. The other three live on `GET /settings/cycle`, which is a settings
/// read with its own key already reserved in the policy
/// (`CacheKeys.cycleSettings`) — so screen 3 composes two reads, and this
/// repository does not pretend to be the second one. Wrapping a settings
/// endpoint here would give `GET /settings/cycle` two owners the moment screen
/// 32 is built.
class OnboardingRepository {
  const OnboardingRepository({
    required LumenApiApi api,
    required CacheStore store,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api, // ignore: prefer_initializing_formals
       _store = store; // ignore: prefer_initializing_formals

  final LumenApiApi _api;
  final CacheStore _store;

  // ── startOnboarding ────────────────────────────────────────────────────────

  /// Registers a new user account by calling `POST /onboarding/start`.
  ///
  /// Fields sent to the server:
  /// - [email]       — required
  /// - [password]    — required
  /// - [displayName] — required (the "Name" field in the mockup)
  /// - [locale] / [timezone] / [policyVersion] — optional; the server applies
  ///   `es-ES` / `Europe/Madrid` / `v1-draft` when they are absent.
  ///
  /// Throws a [Failure] subtype on any error (network, validation, server).
  Future<void> startOnboarding({
    required String email,
    required String password,
    required String displayName,
    String? locale,
    String? timezone,
    String? policyVersion,
  }) async {
    final request = OnboardingStartRequest(
      (b) => b
        ..email = email
        ..password = password
        ..displayName = displayName
        ..locale = locale
        ..timezone = timezone
        ..policyVersion = policyVersion,
    );

    try {
      await _api.onboardingStartPost(onboardingStartRequest: request);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // ── getState ───────────────────────────────────────────────────────────────

  /// Reads `GET /onboarding/state` — where the user left off.
  ///
  /// Stale-while-revalidate, filed under [CacheKeys.onboardingState] at the
  /// shared [CacheKeys.ttl]: the key comes from the policy rather than a
  /// literal here so that a step write (T9-T13) can invalidate the read without
  /// the two spellings drifting.
  ///
  /// Returns [Fresh] on a successful call, [Stale] when the network failed but
  /// a cached answer exists, and [NetworkRequired] when there is neither. A
  /// stale resume is still usable — the read is idempotent and the flow it
  /// describes is the user's own — so callers may treat [Stale] exactly as they
  /// treat [Fresh].
  Future<CacheResult<OnboardingStateResponse>> getState() {
    return cachedRead<OnboardingStateResponse>(
      key: CacheKeys.onboardingState,
      store: _store,
      fetch: () async {
        final response = await _api.onboardingStateGet();
        final body = response.data;
        if (body == null) {
          // A 200 with no body is a server fault. Mapping it to a typed failure
          // keeps it out of the shell as a raw TypeError from a force-unwrap.
          throw const ServerFailure(
            'The server returned an empty onboarding state.',
          );
        }
        return body;
      },
      toJson: _stateToJson,
      fromJson: _stateFromJson,
      ttl: CacheKeys.ttl,
    );
  }

  // ── complete ───────────────────────────────────────────────────────────────

  /// Calls `POST /onboarding/complete` — no body, per the contract.
  ///
  /// **Invalidates the profile as well as the onboarding state.** Completion
  /// stamps `onboarding_completed_at`, which is what `GET /me.onboardingCompleted`
  /// reports and what the router's gate reads; leaving `GET:/me` cached would
  /// keep the gate shut for up to the whole TTL after the user finished.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **409** → [ConflictFailure] carrying `code: onboarding_incomplete` and
  ///   `missingSteps: ["cycle"]`. Those two are problem-details *extensions*
  ///   that `error_mapper.dart` lifts off the body; a caller reads them from the
  ///   failure and never from `DioException.response.data`.
  /// - a repeat call is **not** an error: the server answers 200 with the
  ///   original `completedAt` and `alreadyCompleted: true`.
  Future<OnboardingCompleteResponse> complete() async {
    late final OnboardingCompleteResponse body;

    await cachedWrite(
      store: _store,
      write: () async {
        final response = await _api.onboardingCompletePost();
        final data = response.data;
        if (data == null) {
          throw const ServerFailure(
            'The server returned an empty completion response.',
          );
        }
        body = data;
      },
      invalidateKeys: const <String>[
        CacheKeys.onboardingState,
        CacheKeys.profile,
      ],
    );

    return body;
  }

  // ── built_value ↔ JSON-map helpers ─────────────────────────────────────────

  /// Serializes for the Hive cache. Round-tripped through `json.encode` so no
  /// Dart-only type (the custom-serialized `Date` included) reaches the box.
  static Map<String, dynamic> _stateToJson(OnboardingStateResponse state) {
    final encoded = standardSerializers.serializeWith(
      OnboardingStateResponse.serializer,
      state,
    );
    return json.decode(json.encode(encoded)) as Map<String, dynamic>;
  }

  static OnboardingStateResponse _stateFromJson(Map<String, dynamic> map) {
    return standardSerializers.deserializeWith(
      OnboardingStateResponse.serializer,
      map,
    )!;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [OnboardingRepository] wired to the shared API client and cache
/// store.
final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    api: ref.watch(lumenApiProvider),
    store: ref.watch(cacheStoreProvider),
  );
});
