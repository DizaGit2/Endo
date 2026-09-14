import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// PushPlatform
// ---------------------------------------------------------------------------

/// The two platform codes `user_devices.platform` accepts.
///
/// `UserDevice.Platforms` (`backend/src/Lumen.Domain/Entities/UserDevice.cs:65-70`)
/// — and it is a **two**-member vocabulary: there is deliberately no `web`,
/// because the code decides which provider P9a dispatches through. Anything
/// outside it is a 400 on `POST /me/devices` and on
/// `POST /onboarding/notifications` alike.
///
/// Codes, not display labels: nothing on any screen renders these.
abstract final class PushPlatform {
  /// APNs.
  static const String ios = 'ios';

  /// FCM.
  static const String android = 'android';

  /// The vocabulary, in the server's declaration order.
  static const List<String> all = <String>[ios, android];
}

// ---------------------------------------------------------------------------
// PushToken
// ---------------------------------------------------------------------------

/// A registration token and the platform it belongs to — **always together**.
///
/// The pair is a single value rather than two nullable fields because the
/// contract makes half a pair an error on both endpoints that take it: a token
/// with no platform is a device P9a could never dispatch to, and a platform
/// with no token is not a registration at all
/// (`OnboardingStepsService.cs:524-530`, and both members are required on
/// `POST /me/devices`).
///
/// **What that shape does and does not buy, stated exactly.** It makes an
/// *omitted* half unconstructable — both members are `required` — and that is
/// all. A **blank** half is still constructible, and blank IS the invalid state
/// on `POST /me/devices`, where `pushToken` must be 1–512 characters after
/// trimming. It is also reachable in P9a rather than theoretical: FCM's
/// `getToken()` can answer an empty string while a `deleteToken()` is in
/// flight, so `PushToken(token: '', platform: 'android')` is a shape a real
/// source will hand over.
///
/// **So every consumer normalises through [sendable] before sending**, and the
/// repositories still guard on top of that, because a caller may also assemble
/// the pair from somewhere else.
///
/// **[token] is PII (§F).** It is never logged and never echoed back — neither
/// `RegisterDeviceResponse` nor `NotificationPrefsResponse` has a member for
/// it, by construction. Nothing here overrides `toString` to print it.
@immutable
class PushToken {
  const PushToken({required this.token, required this.platform});

  /// The FCM/APNs registration token, 1–512 characters
  /// (`UserDevice.PushTokenMaxLength` — the existing column's width, not a P4a
  /// invention).
  final String token;

  /// A member of [PushPlatform].
  final String platform;

  /// [token] unless either half is blank, in which case **null** — the device
  /// has nothing sendable, which is the documented "no device" outcome.
  ///
  /// **This is the guard the constructor cannot be.** A `required` parameter
  /// stops an *omitted* half; nothing stops a blank one, and an `assert` would
  /// be stripped from the release build that actually meets FCM's
  /// `getToken()`-during-`deleteToken()` race. So the rule lives here, where it
  /// runs in every build, and every consumer of [PushTokenSource] passes its
  /// answer through it.
  ///
  /// **What a blank half would otherwise cost, on screen 7.** A blank token
  /// with a real platform reaches `OnboardingRepository.saveNotifications`,
  /// where the server's own blank-is-absent rule (mirrored at
  /// `OnboardingStepsService.cs:521-522`) normalises it to null and the
  /// all-or-nothing guard then sees HALF a pair and throws. Screen 7's
  /// `catch (_)` turns that into an `UnknownFailure` banner — so a messaging
  /// fault with nothing to do with the categories would leave the four
  /// preference rows unsaved and onboarding unfinished. The categories are what
  /// the step is *for*; they must not be lost to a token.
  ///
  /// The blank pair is dropped rather than trimmed-and-sent: a token that is
  /// only whitespace is not a token, and the server would reject it.
  static PushToken? sendable(PushToken? token) {
    if (token == null) return null;
    if (token.token.trim().isEmpty || token.platform.trim().isEmpty) {
      return null;
    }
    return token;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushToken && other.token == token && other.platform == platform;

  @override
  int get hashCode => Object.hash(token, platform);
}

// ---------------------------------------------------------------------------
// PushTokenSource
// ---------------------------------------------------------------------------

/// Where the app's push token comes from.
///
/// **This interface is ruling R-09's shape, and only the app-start half of
/// it.** P4b ships push registration's *shape* — an app-start hook, a
/// repository and their tests — and not an SDK, because `firebase_messaging`
/// needs a Firebase project, a `google-services.json`, an APNs key and
/// build-config changes, none of which exist.
///
/// **What P9a inherits without changing it:** the every-app-start cadence, the
/// hook that runs it, [DeviceRepository], and the tests that pin both.
/// Replacing [NoPushToken] with an FCM/APNs implementation is what turns them
/// on.
///
/// **What P9a must still ADD, because this interface does not carry it** (§C.9
/// and §C.0.3, stated here so the next phase does not read "swap one class" and
/// find three obligations missing):
///  * **registration on every token REFRESH** as well as every app start —
///    that is a stream/callback, and `read()` is a pull. P9a widens this
///    interface or adds a second seam beside it;
///  * **unregister on sign-out**, and **delete on the provider's
///    `NotRegistered`** — neither has a method here, and neither has an
///    endpoint on the P4a surface either;
///  * the P9a-side `CREATE INDEX ON user_devices ("PushToken")` and the
///    duplicate-row collapse, which are backend obligations §C.9 lists in full.
///
/// The return is nullable on purpose, and null is a **normal outcome** rather
/// than a failure: a user may decline the OS permission prompt, and the
/// contract already says so — `POST /onboarding/notifications` answers
/// `deviceRegistered: false` for a request that carried no pair, and reports it
/// rather than rejecting it (`OnboardingContracts.cs:290-293`).
// ignore: one_member_abstracts — this is a seam, and its one member is the seam
abstract interface class PushTokenSource {
  /// The device's current token, or null when there is none to send.
  Future<PushToken?> read();
}

/// P4b's only implementation: there is no push SDK, so there is no token.
///
/// Not a stub in the pejorative sense — it is the honest answer for a build
/// that has no messaging service wired. Everything downstream treats it as the
/// documented "no device" path rather than as an error, so the seam is exercised
/// on every app start today and P9a inherits a path that already works.
class NoPushToken implements PushTokenSource {
  const NoPushToken();

  @override
  Future<PushToken?> read() async => null;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// The app's push-token source.
///
/// **The line P9a changes to turn the app-start cadence on** — and not the only
/// line P9a writes; see [PushTokenSource] for the three obligations this
/// interface deliberately does not carry. Overridden in tests to drive the
/// registration path that no P4b build can reach.
final pushTokenSourceProvider = Provider<PushTokenSource>((ref) {
  return const NoPushToken();
});
