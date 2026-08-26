import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/api/model/register_device_request.dart';
import 'package:lumen/api/model/register_device_response.dart';
import 'package:lumen/core/error/error_mapper.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/network/api_client.dart';

// ---------------------------------------------------------------------------
// DeviceRepository
// ---------------------------------------------------------------------------

/// The settings module's door to `POST /me/devices` — push-token registration.
///
/// One operation, and it exists in P4b for the **cadence** rather than for a
/// screen: §C.9 says the client registers on *every app start*, and §C.0.3
/// assigns that obligation to this phase. See
/// `lib/core/push/push_registration_controller.dart` for the hook that calls
/// it, and `push_token_source.dart` for why nothing is sent yet.
///
/// ## What the endpoint does, and what this class must not assume
///
/// It is an **UPSERT on the pre-existing unique `(UserId, PushToken)`** — found
/// ⇒ `platform` and `last_seen_at` move, else insert — and it answers **200
/// either way**. There is deliberately no created/updated distinction: a caller
/// that re-registers on every start has nothing to do with one, and §C.9
/// exposes no `GET /me/devices/{id}` for a `Location` header to point at.
///
/// **Registering a token DETACHES it from every other account.** That is what
/// makes the every-app-start cadence load-bearing rather than cosmetic: the
/// detach's accepted cost is bounded only because the victim's app takes the
/// token back on its next start. "First launch + token refresh" would leave a
/// silenced user silenced until the provider happened to rotate their token.
///
/// ## Both members are required here — unlike on the onboarding step
///
/// `platform` ∈ {`ios`, `android`} and `pushToken` is 1–512 characters, both
/// **required**, trimmed before they are measured; a blank or overlength token
/// or an unknown platform is the shared 400 and writes nothing. That is the
/// opposite of `POST /onboarding/notifications`, where the pair is *optional*
/// and a blank counts as *absent* — two endpoints writing `user_devices` with
/// two different rules, and neither rule is visible in the generated Dart.
///
/// ## No cache
///
/// `user_devices` appears in no cached read: the key policy names none and no
/// `GET /me/devices` exists. So this write invalidates nothing and this class
/// holds no `CacheStore` — a `cachedWrite` with an empty key list would be a
/// dependency taken for the exception mapping alone, which [mapDioException]
/// already does.
///
/// ## §F — the token is PII
///
/// It is never logged and never echoed: [RegisterDeviceResponse] has no
/// `pushToken` member by construction, and nothing here writes one to a
/// message.
class DeviceRepository {
  const DeviceRepository({
    required LumenApiApi api,
    // ignore: prefer_initializing_formals — private fields can't use
    // initialising formals with public names; the initialiser list is required.
  }) : _api = api; // ignore: prefer_initializing_formals

  final LumenApiApi _api;

  /// Calls `POST /me/devices` and returns the row the server holds.
  ///
  /// Errors, all as typed [Failure]s:
  /// - **400** → [ValidationFailure] keyed `platform` or `pushToken`.
  /// - **404** → the shared tenant fence: a missing (or crypto-shredded) user
  ///   is a 404 from every endpoint, decided before validation.
  Future<RegisterDeviceResponse> registerDevice({
    required String platform,
    required String pushToken,
  }) async {
    final request = RegisterDeviceRequest(
      (b) => b
        ..platform = platform
        ..pushToken = pushToken,
    );

    try {
      final response = await _api.meDevicesPost(registerDeviceRequest: request);
      final data = response.data;
      if (data == null) {
        // A 200 with no body is a server fault. A typed failure keeps it out of
        // the caller as a raw TypeError from a force-unwrap.
        throw const ServerFailure(
          'The server returned an empty device registration.',
        );
      }
      return data;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides [DeviceRepository] wired to the shared API client.
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(api: ref.watch(lumenApiProvider));
});
