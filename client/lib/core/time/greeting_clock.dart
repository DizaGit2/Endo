// ---------------------------------------------------------------------------
// greetingTimeOfDay — wall-clock courtesy text ONLY, never a cycle date
// ---------------------------------------------------------------------------
//
// `greetingTimeOfDayProvider` is a thin Riverpod seam over [greetingTimeOfDay]
// — the same reason `sessionTodayProvider` sits beside
// `ServerTodayRepository.today()` in `server_today.dart`: a screen reads the
// PROVIDER, never the bare function, so a widget/golden test can override it
// to a fixed band instead of being at the mercy of whatever wall-clock hour
// happens to be running the suite.
//
// Screen 8's "Good morning, Maya" greeting needs a time-of-day band, and that
// band is genuinely decorative: it carries no clinical meaning and answers no
// question D-12 governs. D-12 is about which DAY a health record files under
// — `server_today.dart` is the positive half of that rule, and its own
// dartdoc is the place to read why a cycle date must come from the server.
// This file is deliberately NOT that: there is no date here at all, only a
// hint about which greeting reads naturally right now, and getting it wrong
// by an hour around a band boundary has no data-integrity consequence.
//
// `test/core/locale/formatting_guard_test.dart` enforces the negative half of
// D-12 — a bare `DateTime.now()` anywhere under `lib/` fails the build unless
// it carries a line-level waiver — and there is NO directory exemption, so
// living under `lib/core/time/` does not by itself grant this file anything.
// The waiver below is what does, and `deviceClockWaivers` pins the whole list
// at exactly three entries (was two): this file, plus the two pre-existing
// non-cycle reads in `auth_interceptor.dart` (token expiry) and
// `hive_boot.dart` (cache TTL) — same shape, same reasoning.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The English greeting for the current wall-clock hour: `"Good morning"`,
/// `"Good afternoon"` or `"Good evening"`.
///
/// **Never reuse this for anything cycle-related.** It is deliberately the
/// one place in `lib/core/time/` that reads the device's own clock rather
/// than the server's; `sessionTodayProvider` (`server_today.dart`) is what
/// every dated screen must use instead.
///
/// [clock] is injectable for tests, defaulting to the real wall clock.
String greetingTimeOfDay({DateTime Function()? clock}) {
  // lumen:allow-device-clock decorative "good morning/afternoon/evening" band only — no date is read here, so D-12 (which cycle DAY a record files under) does not govern this line.
  final hour = (clock ?? DateTime.now)().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// The Riverpod seam screens read instead of calling [greetingTimeOfDay]
/// directly — see the file header for why. `Provider`, not `Provider.
/// autoDispose`: the greeting carries no PII and no per-user state, so there
/// is nothing session-scoped to tear down, unlike `sessionTodayProvider`.
final greetingTimeOfDayProvider = Provider<String>((_) => greetingTimeOfDay());
