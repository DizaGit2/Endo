import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/onboarding_start_request.dart';
import 'package:lumen/core/error/error_mapper.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// OnboardingRepository
// ---------------------------------------------------------------------------

/// Wraps [LumenApiApi.onboardingStartPost] and maps network errors to typed
/// [Failure]s.
///
/// Fields sent to the server:
/// - [email]       — required
/// - [password]    — required
/// - [displayName] — required (the "Name" field in the mockup)
/// - [locale]      — null (P4: read from device locale)
/// - [timezone]    — null (P4: read from device timezone)
/// - [policyVersion] — null (P4: bump when terms change)
class OnboardingRepository {
  const OnboardingRepository(this._api);

  final LumenApiApi _api;

  /// Registers a new user account by calling `POST /onboarding/start`.
  ///
  /// Throws a [Failure] subtype on any error (network, validation, server).
  /// On success returns normally.
  Future<void> startOnboarding({
    required String email,
    required String password,
    required String displayName,
    // Optional fields — deferred to P4.
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
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [OnboardingRepository] wired to the shared [LumenApiApi].
final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.watch(lumenApiProvider));
});
