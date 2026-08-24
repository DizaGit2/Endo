// The push-registration seam and its cadence (P4b-T13, ruling R-09).
//
// P4b ships the SHAPE of push registration, not an SDK: `firebase_messaging`
// needs a Firebase project, a `google-services.json`, an APNs key and
// build-config changes, none of which exist. So the token comes from an
// injectable [PushTokenSource] whose only P4b implementation answers null, and
// P9a rewrites one class instead of adding one.
//
// **The cadence is the part that is load-bearing, and it is the part a null
// token source can still be tested for.** §C.9 assigns `POST /me/devices` to
// *every app start*, not "first launch + token refresh", because registering a
// token DETACHES it from every other account: the accepted cost of that detach
// is bounded only because the victim's app takes the token back on its next
// start. Under "first launch" a silenced user stays silenced until the provider
// happens to rotate their token, potentially for months. So the tests below
// pin two separate things:
//
//   1. with the SHIPPED (null) source nothing is sent — and the source was
//      still consulted, which is what tells [PushRegistrationOutcome.noToken]
//      apart from the `idle` a registrar that never ran would leave behind;
//   2. with a token, the registration is issued EVERY time the registrar runs,
//      unconditionally — a second authenticated session inside one app start
//      re-registers the SAME token. That is what kills a "remember what we
//      last sent" memo, and measurement rather than assumption says such a memo
//      would survive: in Riverpod 3.3.2 a `Notifier` whose watched dependency
//      changes has `build()` re-invoked on the SAME instance (probed at T13:
//      `identical(first, last) == true` across two rebuilds, one identity hash).
//
// What P9a inherits is these tests plus [PushTokenSource]; the only line it
// should have to change is which implementation the provider returns.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/register_device_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/push/push_registration_controller.dart';
import 'package:lumen/core/push/push_token_source.dart';
import 'package:lumen/features/settings/data/device_repository.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _MockDeviceRepository extends Mock implements DeviceRepository {}

class _MockMeRepository extends Mock implements MeRepository {}

/// A [PushTokenSource] that answers [token] and counts how often it was asked.
///
/// The count is what makes "nothing was sent" a statement about the seam rather
/// than about a registrar that never ran.
class _CountingSource implements PushTokenSource {
  _CountingSource([this.token]);

  final PushToken? token;
  int reads = 0;

  @override
  Future<PushToken?> read() async {
    reads += 1;
    return token;
  }
}

/// An [AuthController] whose status the test can move.
///
/// [FakeAuthController] is pinned to one value, and the cadence test needs the
/// transition: a second authenticated session inside one app start is what a
/// "first launch only" registrar gets wrong.
class _SwitchableAuth extends AuthController {
  _SwitchableAuth(this._initial);

  final AuthStatus _initial;

  @override
  AuthStatus build() {
    initialized = Future<void>.value();
    return _initial;
  }

  void moveTo(AuthStatus status) => state = status;
}

RegisterDeviceResponse _registered() => RegisterDeviceResponse(
  (b) => b
    ..deviceId = 'device-1'
    ..platform = 'android'
    ..lastSeenAt = DateTime.utc(2026, 4, 6)
    ..createdAt = DateTime.utc(2026, 4, 1),
);

/// One app start: a fresh container, with the seam's two ends overridable.
///
/// The subscription is what a real app start does — `LumenApp` listens to the
/// provider — and without it the registrar would never be built at all.
ProviderContainer _appStart({
  PushTokenSource? source,
  DeviceRepository? devices,
  AuthStatus auth = AuthStatus.authenticated,
}) {
  final container = ProviderContainer(
    retry: lumenRetry,
    overrides: <Override>[
      authStatusProvider.overrideWith(() => _SwitchableAuth(auth)),
      if (source != null) pushTokenSourceProvider.overrideWithValue(source),
      if (devices != null) deviceRepositoryProvider.overrideWithValue(devices),
    ],
  );
  addTearDown(container.dispose);
  container.listen(pushRegistrationProvider, (_, _) {});
  return container;
}

/// Pumps microtasks until the registrar has settled on something other than
/// [PushRegistrationOutcome.idle], or gives up.
Future<PushRegistrationOutcome> _settled(ProviderContainer container) async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
    final outcome = container.read(pushRegistrationProvider);
    if (outcome != PushRegistrationOutcome.idle) return outcome;
  }
  return container.read(pushRegistrationProvider);
}

_SwitchableAuth _auth(ProviderContainer container) =>
    container.read(authStatusProvider.notifier) as _SwitchableAuth;

void main() {
  setUpAll(() => registerFallbackValue('android'));

  // -------------------------------------------------------------------------
  // What P4b actually ships
  // -------------------------------------------------------------------------

  test(
    'the shipped token source answers null, and no push package is wired',
    () {
      final container = _appStart(devices: _MockDeviceRepository());

      // R-09 in one assertion: the production wiring is the null source. P9a
      // changes this line and nothing else in the seam.
      expect(container.read(pushTokenSourceProvider), isA<NoPushToken>());
    },
  );

  test('the device repository provider is wired to the shared API client', () {
    // Read WITHOUT overriding it, so this is the production graph: the seam's
    // far end resolves against `lumenApiProvider` rather than building a client
    // of its own.
    final api = MockLumenApiApi();
    final container = ProviderContainer(
      retry: lumenRetry,
      overrides: <Override>[...lumenOverrides(api: api)],
    );
    addTearDown(container.dispose);

    expect(container.read(deviceRepositoryProvider), isA<DeviceRepository>());
  });

  test('a push token is its PAIR, and the pair is its identity', () {
    // The token and the platform are one value because half a pair is an error
    // on both endpoints that take it. Equality follows from that: two devices
    // are the same registration only when both halves match.
    const a = PushToken(token: 'fcm-abc', platform: PushPlatform.android);
    expect(
      a,
      const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
    );
    expect(
      a.hashCode,
      const PushToken(
        token: 'fcm-abc',
        platform: PushPlatform.android,
      ).hashCode,
    );
    // …and it is not equal on either half alone.
    expect(
      a,
      isNot(const PushToken(token: 'fcm-abc', platform: PushPlatform.ios)),
    );
    expect(
      a,
      isNot(const PushToken(token: 'other', platform: PushPlatform.android)),
    );

    // The vocabulary has exactly two members: there is deliberately no `web`,
    // because the code decides which provider P9a dispatches through
    // (`UserDevice.cs:65-70`).
    expect(PushPlatform.all, <String>['ios', 'android']);
  });

  test(
    'with the shipped source nothing is sent — and the source WAS asked',
    () async {
      final devices = _MockDeviceRepository();
      // No `source:` override: this is the production wiring, running.
      final container = _appStart(devices: devices);

      final outcome = await _settled(container);

      // `noToken` rather than `idle` is the whole point. `idle` is the state a
      // registrar that never ran leaves behind, so asserting "nothing was sent"
      // alone would pass with the hook deleted; only a state reachable *by
      // running* says the seam was consulted and answered null.
      expect(outcome, PushRegistrationOutcome.noToken);
      expect(
        PushRegistrationOutcome.noToken,
        isNot(PushRegistrationOutcome.idle),
        reason:
            'the control for the row above: the two states must be distinct, or '
            'it asserts nothing',
      );

      // Nothing reached the network, and the repository was never even touched —
      // the token is read FIRST, so a build with no API client behind it is not
      // a crash on a device that has no push token.
      verifyZeroInteractions(devices);
    },
  );

  test('a BLANK half is not a token, so nothing is sent', () async {
    // `PushToken` makes an OMITTED half unconstructable; it does not make a
    // BLANK one unconstructable, and blank is the invalid state on
    // `POST /me/devices`, where both members are required and measured after
    // trimming. FCM's `getToken()` can answer an empty string during a
    // `deleteToken()` race, so P9a meets this shape for real.
    final devices = _MockDeviceRepository();
    when(
      () => devices.registerDevice(
        platform: any(named: 'platform'),
        pushToken: any(named: 'pushToken'),
      ),
    ).thenAnswer((_) async => _registered());

    final source = _CountingSource(
      const PushToken(token: '   ', platform: PushPlatform.android),
    );
    final container = _appStart(source: source, devices: devices);

    // `noToken`, not `failed`: an unusable token is the documented "no device"
    // outcome, not an error to report. And `noToken` is not `idle`, so the
    // source really was consulted.
    expect(await _settled(container), PushRegistrationOutcome.noToken);
    expect(source.reads, 1);
    verifyZeroInteractions(devices);

    // The control: the same source shape with a non-blank token DOES register,
    // so "nothing sent" is about the blank half rather than about a hook that
    // stopped working.
    final ok = _appStart(
      source: _CountingSource(
        const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
      ),
      devices: devices,
    );
    expect(await _settled(ok), PushRegistrationOutcome.registered);
    verify(
      () => devices.registerDevice(platform: 'android', pushToken: 'fcm-abc'),
    ).called(1);
  });

  test('sendable drops a pair with either half blank, and passes a real one '
      'through unchanged', () {
    const real = PushToken(token: 'fcm-abc', platform: PushPlatform.android);

    // Passed through by identity, not rebuilt: a token is not trimmed on its
    // way to the wire — the server trims before it measures, and a value this
    // client rewrote would no longer be the one the provider issued.
    expect(identical(PushToken.sendable(real), real), isTrue);

    expect(PushToken.sendable(null), isNull);
    expect(
      PushToken.sendable(
        const PushToken(token: '', platform: PushPlatform.android),
      ),
      isNull,
    );
    expect(
      PushToken.sendable(
        const PushToken(token: '\t \n', platform: PushPlatform.ios),
      ),
      isNull,
    );
    expect(
      PushToken.sendable(const PushToken(token: 'fcm-abc', platform: '')),
      isNull,
    );
    expect(
      PushToken.sendable(const PushToken(token: 'fcm-abc', platform: '  ')),
      isNull,
    );
  });

  // -------------------------------------------------------------------------
  // The cadence — EVERY app start, unconditionally
  // -------------------------------------------------------------------------

  test('an app start with a token registers it', () async {
    final devices = _MockDeviceRepository();
    when(
      () => devices.registerDevice(
        platform: any(named: 'platform'),
        pushToken: any(named: 'pushToken'),
      ),
    ).thenAnswer((_) async => _registered());

    final source = _CountingSource(
      const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
    );
    final container = _appStart(source: source, devices: devices);

    expect(await _settled(container), PushRegistrationOutcome.registered);
    verify(
      () => devices.registerDevice(platform: 'android', pushToken: 'fcm-abc'),
    ).called(1);

    // The control: a DIFFERENT token travels differently, so the two literals
    // above are the source's answer and not constants baked into the registrar.
    final second = _appStart(
      source: _CountingSource(
        const PushToken(token: 'apns-xyz', platform: PushPlatform.ios),
      ),
      devices: devices,
    );
    expect(await _settled(second), PushRegistrationOutcome.registered);
    verify(
      () => devices.registerDevice(platform: 'ios', pushToken: 'apns-xyz'),
    ).called(1);
  });

  test('a SECOND authenticated session inside one app start registers the '
      'SAME token again', () async {
    // The cadence rule, stated as the thing it forbids. A registrar that
    // remembered what it last sent — on the notifier (which survives a
    // dependency-driven rebuild, measured) or in a file-scope once-flag —
    // would issue ONE request here, and the user whose token had been detached
    // by another account would stay silenced.
    final devices = _MockDeviceRepository();
    when(
      () => devices.registerDevice(
        platform: any(named: 'platform'),
        pushToken: any(named: 'pushToken'),
      ),
    ).thenAnswer((_) async => _registered());

    final source = _CountingSource(
      const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
    );
    final container = _appStart(source: source, devices: devices);

    // Premise: the first session registered, so what follows is about the
    // second one rather than about a registrar that never ran.
    expect(await _settled(container), PushRegistrationOutcome.registered);
    expect(source.reads, 1);

    _auth(container).moveTo(AuthStatus.unauthenticated);
    await Future<void>.delayed(Duration.zero);
    _auth(container).moveTo(AuthStatus.authenticated);

    expect(await _settled(container), PushRegistrationOutcome.registered);

    // Twice, with the token unchanged. This is the assertion the cadence is.
    expect(source.reads, 2);
    verify(
      () => devices.registerDevice(platform: 'android', pushToken: 'fcm-abc'),
    ).called(2);
  });

  test('an unauthenticated app start registers nothing', () async {
    final devices = _MockDeviceRepository();
    when(
      () => devices.registerDevice(
        platform: any(named: 'platform'),
        pushToken: any(named: 'pushToken'),
      ),
    ).thenAnswer((_) async => _registered());

    final source = _CountingSource(
      const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
    );
    final container = _appStart(
      source: source,
      devices: devices,
      auth: AuthStatus.unauthenticated,
    );

    expect(await _settled(container), PushRegistrationOutcome.idle);
    expect(source.reads, 0);
    verifyZeroInteractions(devices);

    // The control: the SAME container, once signed in, does register — so the
    // three rows above are about the auth gate and not about an unwired hook.
    _auth(container).moveTo(AuthStatus.authenticated);
    expect(await _settled(container), PushRegistrationOutcome.registered);
    expect(source.reads, 1);
  });

  // -------------------------------------------------------------------------
  // Failure
  // -------------------------------------------------------------------------

  test('a failed registration is recorded, not thrown', () async {
    // App start must not become a crash because the network was down or the
    // token was rejected. There is no user-facing surface for this in P4b and
    // no retry: the next app start is the retry, which is the cadence again.
    final devices = _MockDeviceRepository();
    when(
      () => devices.registerDevice(
        platform: any(named: 'platform'),
        pushToken: any(named: 'pushToken'),
      ),
    ).thenAnswer((_) async => throw const NetworkFailure());

    final container = _appStart(
      source: _CountingSource(
        const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
      ),
      devices: devices,
    );

    expect(await _settled(container), PushRegistrationOutcome.failed);
  });

  test('a token source that throws is a failure, not a crash', () async {
    // P9a's source talks to FCM/APNs, which can throw. The registrar owns that
    // possibility now rather than leaving it for the phase that introduces it.
    final devices = _MockDeviceRepository();
    final container = _appStart(source: _ThrowingSource(), devices: devices);

    expect(await _settled(container), PushRegistrationOutcome.failed);
    verifyZeroInteractions(devices);
  });

  // -------------------------------------------------------------------------
  // Where "app start" comes from
  // -------------------------------------------------------------------------

  testWidgets('mounting the app is what starts the registration', (
    tester,
  ) async {
    // The cadence has to be attached to something that happens once per
    // process, and that is the root widget: `LumenApp` subscribes to the
    // registrar, so the provider is built inside the root `ProviderScope` — a
    // container that exists exactly once per app start.
    final devices = _MockDeviceRepository();
    when(
      () => devices.registerDevice(
        platform: any(named: 'platform'),
        pushToken: any(named: 'pushToken'),
      ),
    ).thenAnswer((_) async => _registered());

    final me = _MockMeRepository();
    when(
      me.getMe,
    ).thenAnswer((_) async => Fresh<MeResponse>(meResponseFixture()));

    await pumpLumenApp(
      tester,
      settle: false,
      overrides: <Override>[
        ...lumenOverrides(),
        meRepositoryProvider.overrideWithValue(me),
        pushTokenSourceProvider.overrideWithValue(
          _CountingSource(
            const PushToken(token: 'fcm-abc', platform: PushPlatform.android),
          ),
        ),
        deviceRepositoryProvider.overrideWithValue(devices),
      ],
    );
    await tester.pump(const Duration(milliseconds: 16));

    verify(
      () => devices.registerDevice(platform: 'android', pushToken: 'fcm-abc'),
    ).called(1);
  });
}

class _ThrowingSource implements PushTokenSource {
  @override
  Future<PushToken?> read() async => throw StateError('no messaging service');
}
