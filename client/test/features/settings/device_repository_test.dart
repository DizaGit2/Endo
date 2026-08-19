// DeviceRepository — `POST /me/devices` (P4b-T13).
//
// The endpoint P4b calls on EVERY app start (§C.9, and §C.0.3 assigns the
// cadence to this phase). Three things about it are worth a test rather than a
// comment:
//
//   * it is an UPSERT on `(UserId, PushToken)` and answers **200 either way**,
//     so there is no created/updated distinction for this client to branch on;
//   * the 200 body never carries the token back (§F) — `{ deviceId, platform,
//     lastSeenAt, createdAt }` — so nothing here may reconstruct it from the
//     response;
//   * both members are REQUIRED and trimmed before they are measured, so a
//     blank token is a 400 rather than "no device". That is the OPPOSITE of
//     `POST /onboarding/notifications`, where the pair is optional and blank
//     counts as absent — two endpoints writing the same table with two
//     different rules, which is exactly the kind of thing the generated client
//     cannot express (§C.0).
//
// Cache: nothing. `user_devices` appears in no cached read in the policy — no
// `GET /me/devices` exists on the P4a surface — so this write invalidates
// nothing and the repository holds no [CacheStore].

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/register_device_request.dart';
import 'package:lumen/api/model/register_device_response.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/data/device_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

/// The request the repository actually put on the wire.
RegisterDeviceRequest _captured(MockLumenApiApi api) {
  return verify(
        () => api.meDevicesPost(
          registerDeviceRequest: captureAny(named: 'registerDeviceRequest'),
        ),
      ).captured.last
      as RegisterDeviceRequest;
}

RegisterDeviceResponse _deviceFixture({
  String? deviceId = 'device-1',
  String? platform = 'android',
}) {
  return RegisterDeviceResponse(
    (b) => b
      ..deviceId = deviceId
      ..platform = platform
      ..lastSeenAt = DateTime.utc(2026, 4, 6, 9, 30)
      ..createdAt = DateTime.utc(2026, 4, 1, 9, 30),
  );
}

void main() {
  late MockLumenApiApi api;
  late DeviceRepository repo;

  setUpAll(
    () => registerFallbackValue(
      RegisterDeviceRequest(
        (b) => b
          ..platform = 'android'
          ..pushToken = 'seed',
      ),
    ),
  );

  setUp(() {
    api = MockLumenApiApi();
    repo = DeviceRepository(api: api);
  });

  void answerRegister([RegisterDeviceResponse? body]) {
    when(
      () => api.meDevicesPost(
        registerDeviceRequest: any(named: 'registerDeviceRequest'),
      ),
    ).thenAnswer(apiSuccess(body ?? _deviceFixture()));
  }

  test('it sends the token and the platform it was given', () async {
    answerRegister();

    await repo.registerDevice(platform: 'ios', pushToken: 'apns-token-1');

    RegisterDeviceRequest sent = _captured(api);
    expect(sent.platform, 'ios');
    expect(sent.pushToken, 'apns-token-1');

    // The control: a DIFFERENT pair travels differently. Without it the two
    // rows above would pass for a repository that ignored its arguments.
    await repo.registerDevice(platform: 'android', pushToken: 'fcm-token-2');
    sent = _captured(api);
    expect(sent.platform, 'android');
    expect(sent.pushToken, 'fcm-token-2');
  });

  test('the 200 is returned whole, and it carries no token', () async {
    answerRegister();

    final RegisterDeviceResponse body = await repo.registerDevice(
      platform: 'android',
      pushToken: 'fcm-token-1',
    );

    // An upsert answers 200 whether it inserted or moved a row, and §C.9
    // exposes no `GET /me/devices/{id}`, so `deviceId` is the only handle a
    // caller ever gets.
    expect(body.deviceId, 'device-1');
    expect(body.lastSeenAt, DateTime.utc(2026, 4, 6, 9, 30));

    // §F: the token is deliberately absent from the response type. This is a
    // structural statement about the generated model, and it is why the caller
    // must hold its own token rather than read one back.
    expect(
      body.toString().contains('fcm-token-1'),
      isFalse,
      reason:
          'RegisterDeviceResponse must never carry the push token back — it '
          'would put PII into client logs, proxy traces and every HAR file a '
          'support ticket carries (§F).',
    );
  });

  test(
    'a 400 arrives as a ValidationFailure keyed by wire field name',
    () async {
      when(
        () => api.meDevicesPost(
          registerDeviceRequest: any(named: 'registerDeviceRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem<RegisterDeviceResponse>(
          path: '/me/devices',
          fields: const <String, List<String>>{
            'platform': <String>['value is not one of the allowed values'],
          },
        ),
      );

      await expectLater(
        repo.registerDevice(platform: 'web', pushToken: 'token'),
        throwsA(
          isA<ValidationFailure>().having(
            (ValidationFailure f) => f.messageFor('platform'),
            'messageFor(platform)',
            'value is not one of the allowed values',
          ),
        ),
      );
    },
  );

  test('a network failure arrives as a typed NetworkFailure', () async {
    when(
      () => api.meDevicesPost(
        registerDeviceRequest: any(named: 'registerDeviceRequest'),
      ),
    ).thenAnswer(apiNetworkFailure<RegisterDeviceResponse>());

    await expectLater(
      repo.registerDevice(platform: 'android', pushToken: 'token'),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test('an empty 200 body is a typed failure, not a force-unwrap', () async {
    when(
      () => api.meDevicesPost(
        registerDeviceRequest: any(named: 'registerDeviceRequest'),
      ),
    ).thenAnswer(
      (_) async => Response<RegisterDeviceResponse>(
        requestOptions: RequestOptions(path: '/me/devices'),
        statusCode: 200,
      ),
    );

    await expectLater(
      repo.registerDevice(platform: 'android', pushToken: 'token'),
      throwsA(isA<ServerFailure>()),
    );
  });
}
