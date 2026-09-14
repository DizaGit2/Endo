/// The device's IANA timezone id (D-12 — the client half, D1 / B-50).
///
/// Every day-keyed read and write on the server is resolved in the zone the
/// profile stores (`users.timezone`, `UserDayResolver`): "today", the day a
/// check-in files under, the calendar window. D-12 says that zone is *captured
/// at `/onboarding/start`* — and the device is the only party that knows it.
/// Until the PR #4 review hand-back the client never sent it, so every account
/// registered through the app lived on the server's default, Madrid's calendar
/// day, with real data loss on the one-row-per-day check-in upsert (walk
/// 2026-08-25, D1).
///
/// Dart itself cannot answer the question: `DateTime.now().timeZoneName` is an
/// abbreviation ("CST"), not an id the server's `TimeZoneInfo` can resolve, and
/// `DateTime.now()` is build-guarded under `lib/` anyway
/// (`formatting_guard.dart`). So the id comes from the platform through
/// `flutter_timezone`, behind a provider tests override — the same shape as
/// `deviceLocaleProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// The widest a `users.timezone` value can be (`OnboardingService.cs`,
/// `varchar(64)`); anything longer would be a 400 on a field screen 2 does not
/// draw.
const int kMaxTimezoneIdLength = 64;

/// An IANA zone id: `Area/Location`, optionally `Area/Region/Location`, or the
/// bare `UTC` some emulators report. Anchored: this is a gate.
///
/// Abbreviations (`CST`), offsets (`GMT+1`, `UTC+02:00`) and display names are
/// exactly what it must NOT let through — the server answers 400 to all of
/// them, and the user has no field to fix.
final RegExp _ianaZoneId = RegExp(r'^(?:UTC|[A-Za-z_]+(?:/[A-Za-z0-9_+\-]+)+)$');

/// [raw] as an IANA id the server can resolve, or `null` if it is not one.
String? usableTimezoneId(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.length > kMaxTimezoneIdLength) return null;
  return _ianaZoneId.hasMatch(trimmed) ? trimmed : null;
}

// ---------------------------------------------------------------------------
// Source
// ---------------------------------------------------------------------------

/// How long to wait for the platform before treating the zone as unknown.
///
/// A real device answers in single-digit milliseconds. The bound exists so
/// that a platform that never answers cannot hold the onboarding gate or a
/// registration: in a widget test an unmocked channel is exactly that, and a
/// hung engine would be too.
const Duration kDeviceTimezoneWait = Duration(seconds: 2);

/// Reads the device's zone defensively: `null` when the platform will not say
/// (no plugin handler in a test, a platform error, no answer within
/// [kDeviceTimezoneWait]) or says something that is not an IANA id.
///
/// Never throws. The zone is a *fallback the server can supply itself*, so a
/// failure to read it must not block a registration or hold a cold start.
Future<String?> readDeviceTimezone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone().timeout(
      kDeviceTimezoneWait,
    );
    return usableTimezoneId(info.identifier);
  } catch (_) {
    return null;
  }
}

/// The device's IANA zone id, or `null` if the platform will not say.
///
/// **Read once per app run.** Like `deviceLocaleProvider`, it does not observe
/// system changes while Lumen is running: a traveller who lands and opens the
/// app is served on the next cold start, when the once-per-session `/me` read
/// re-syncs the profile (`OnboardingStatusController`).
///
/// Two consumers:
///  * `AccountController.register` — the value D-12 captures at
///    `/onboarding/start`;
///  * `OnboardingStatusController` — the app-start re-sync via `PATCH /me`
///    when the profile's zone differs (PO ruling 2026-09-14, PR #4 review).
final deviceTimezoneProvider = FutureProvider<String?>(
  (_) => readDeviceTimezone(),
);
