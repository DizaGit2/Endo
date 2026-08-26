/// Which locale the app formats in (D-03 / D-05).
///
/// **es-ES is the primary locale**, which means Monday-first weeks, a 24-hour
/// clock and comma decimals. That is a formatting decision, not a translation
/// one: UI strings stay English in P4b (ruling R-04), there is no
/// `flutter_localizations` and no in-app language picker (D-07).
///
/// The effective locale is resolved once, here, and read synchronously by
/// widgets during `build`:
///
/// ```dart
/// final locale = ref.watch(localeProvider);
/// Text(LumenFormats.date(day, locale));
/// ```
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/formatters/lumen_formats.dart';

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

/// The locale used when nothing else is available — **es-ES** (D-03), in the
/// underscore form `intl` expects.
const String kFallbackLocale = 'es_ES';

/// The widest a `users.locale` value can legitimately be.
///
/// `varchar(35)` in the schema, so anything longer did not come from us and is
/// treated as junk rather than trusted into a formatter.
const int kMaxLocaleLength = 35;

/// A language tag, optionally with a script and/or a region:
/// `es` · `es-ES` · `es_ES` · `zh-Hans-CN` · `es-419`.
///
/// Anchored at both ends: this is a gate, and an unanchored pattern would find
/// `es` inside any sentence and hand it to `intl` as a locale.
final RegExp _wellFormedLocale =
    RegExp(r'^[A-Za-z]{2,3}([_-][A-Za-z]{4})?([_-]([A-Za-z]{2}|[0-9]{3}))?$');

/// Resolves the effective locale: **profile → device → es-ES**.
///
/// A candidate is skipped — not thrown on — when it is malformed, longer than
/// [kMaxLocaleLength], or well-formed but unknown to `intl`. The returned value
/// is therefore always safe to hand to [LumenFormats]; every candidate that is
/// not is dropped here, where the fallback is, rather than at a `DateFormat`
/// call somewhere inside a screen.
String resolveLocale({String? profileLocale, String? deviceLocale}) =>
    _usable(profileLocale) ?? _usable(deviceLocale) ?? kFallbackLocale;

/// The canonical, data-backed form of [raw], or `null` if there is none.
String? _usable(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.length > kMaxLocaleLength) return null;
  if (!_wellFormedLocale.hasMatch(trimmed)) return null;

  // `es-ES` → `es_ES`; `en-us` → `en_US`.
  final canonical = Intl.canonicalizedLocale(trimmed);

  // The shortened form is a real fallback, not a nicety: `intl` ships data for
  // `de` but has no `de_DE` entry at all, and dropping to the DEVICE locale
  // there would hand a German user an American calendar.
  for (final candidate in <String>[canonical, Intl.shortLocale(canonical)]) {
    if (LumenFormats.hasLocaleData(candidate)) return candidate;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------

/// The device's locale as a BCP-47 tag (`en-US`), or `null` if the platform
/// will not say.
///
/// A provider rather than a direct read so tests pin it: otherwise every
/// formatting assertion would depend on the regional settings of whichever
/// machine ran them.
///
/// **Read once, at first use.** It does not observe
/// `WidgetsBindingObserver.didChangeLocales`, so changing the system language
/// while Lumen is running is not picked up until the app is restarted. That is
/// accepted for v1: the device locale is only the *second* source (a
/// signed-in user's own `MeResponse.locale` wins), and D-07 rules out an in-app
/// language picker, so the in-session change is rare and self-correcting on the
/// next launch. Making it live means an observer whose only job is to
/// invalidate this provider.
final deviceLocaleProvider = Provider<String?>((ref) => readDeviceLocale());

/// Reads the platform locale defensively.
///
/// `PlatformDispatcher.instance.locale` throws when the embedder has reported
/// no locales at all, which is a state some test and headless environments
/// start in — and a missing device locale is a *fallback*, never a crash.
String? readDeviceLocale() {
  try {
    return PlatformDispatcher.instance.locale.toLanguageTag();
  } catch (_) {
    return null;
  }
}

/// The locale the signed-in user's profile reports (`MeResponse.locale`), or
/// `null` before a profile has loaded.
///
/// This is a **sink, not a fetch**: it does not read `/me`. Whoever loads a
/// profile pushes into it, so a screen that only needs to format a date does
/// not drag a PII-bearing profile request behind it.
///
/// **Two producers, and the first is the one that matters:**
///  * `OnboardingStatusController` — the router's gate, which performs the
///    app's only once-per-session `/me` on every authenticated cold start.
///    This is what makes the app locale-aware from the first frame.
///  * `ProfileController` — screen 31, on load and on the post-save re-fetch.
///
/// `/me` **is** read during onboarding (by that same gate), so "no profile
/// exists yet" is not the reason the device fallback matters — it matters for
/// the window before the gate's read lands, and for a user whose profile
/// carries no `locale`.
///
/// A producer must adopt only once it knows its response still belongs to the
/// current session; see `OnboardingStatusController._load`, which adopts after
/// its generation check.
class ProfileLocaleController extends Notifier<String?> {
  @override
  String? build() {
    // Sign-out MUST forget it. Nothing else clears this provider: it is
    // root-scoped (never `autoDispose`, because the whole point is to outlive
    // the one screen that loads the profile) and `AuthController.logout` clears
    // tokens and purges the Hive cache but resets no providers.
    //
    // Without this line, user A's `es-ES` survives into user B's session on a
    // shared device — B gets Monday-first weeks and comma decimals until
    // something happens to re-adopt, which is exactly the leak the rest of this
    // file's `autoDispose`-for-PII reasoning exists to prevent. Watching
    // `authStatusProvider` rebuilds this notifier back to `null` on every auth
    // transition; `OnboardingStatusController` uses the same pattern for the
    // same reason.
    ref.watch(authStatusProvider);
    return null;
  }

  /// Adopts the profile's locale. Accepts whatever the server sent, including
  /// `null` and junk: validation belongs to [resolveLocale], which has the
  /// fallbacks.
  void adopt(String? locale) => state = locale;
}

/// See [ProfileLocaleController].
final profileLocaleProvider =
    NotifierProvider<ProfileLocaleController, String?>(
  ProfileLocaleController.new,
);

// ---------------------------------------------------------------------------
// The providers screens use
// ---------------------------------------------------------------------------

/// The effective locale, e.g. `es_ES`. Readable synchronously during `build`,
/// and rebuilds its watchers when the profile's locale arrives or changes.
final localeProvider = Provider<String>((ref) {
  return resolveLocale(
    profileLocale: ref.watch(profileLocaleProvider),
    deviceLocale: ref.watch(deviceLocaleProvider),
  );
});

/// The first day of the week, as a [DateTime] weekday constant — Monday under
/// es-ES, Sunday under en-US.
///
/// **Derived, never stored.** There is no `first_day_of_week` column and there
/// must not be one; screen 32's settable row is dropped (ruling R-10) and the
/// behaviour ships derived from the locale.
final firstDayOfWeekProvider = Provider<int>(
  (ref) => LumenFormats.firstDayOfWeek(ref.watch(localeProvider)),
);
