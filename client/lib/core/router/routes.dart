/// Route path constants for the Lumen app.
///
/// These constants are the single source of truth for navigation paths used
/// in [AppRouter] and throughout the feature screens.
abstract final class Routes {
  /// Splash shown while auth state is still resolving (cold start), so a stored
  /// session lands on [profile] without a flash of [welcome].
  static const splash = '/splash';

  /// Welcome / login gateway (onboarding step 1).
  static const welcome = '/';

  /// Account screen — register or sign in (onboarding step 2).
  ///
  /// Both "Begin" and "I already have an account" on [WelcomeScreen] land here;
  /// the login-vs-register split is handled within the account screen (T7).
  static const account = '/account';

  /// Main profile / home destination for authenticated users.
  static const profile = '/profile';

  /// Onboarding flow (post-auth first-run wizard).
  ///
  /// A registered route since P4b-T1: authenticated users whose
  /// `MeResponse.onboardingCompleted` is not true are gated here by
  /// [lumenRedirect]. Since P4b-T8 it renders `OnboardingShellScreen`, which
  /// holds the whole of screens 3–7.
  ///
  /// **The steps are deliberately NOT sub-routes.** The gate funnels every
  /// location an un-onboarded user asks for to exactly this path, so
  /// `/onboarding/cycle` would be redirected straight back here; the step lives
  /// in the shell's controller instead.
  static const onboarding = '/onboarding';

  // ── The five bottom-nav tabs ───────────────────────────────────────────────
  // Order is CLAUDE.md's, and it is the order of the branches in the
  // `StatefulShellRoute.indexedStack` in [lumenRoutes] and of the destinations
  // in [LumenBottomNav]. All three must stay in step: the shell addresses its
  // branches by index.
  //
  // Each is a branch ROOT. Routes that live inside a tab are registered as
  // children of these (e.g. `/cycle/day/:date`), which keeps them inside the
  // branch's own Navigator and therefore inside its own back stack.

  /// Home tab (screen 8, the dashboard) — branch 0.
  ///
  /// P4b-T17 replaces its placeholder with the real dashboard.
  static const home = '/home';

  /// Cycle tab (screens 10/11/14) — branch 1.
  ///
  /// Screen 10 (calendar) shipped at P4b-T15. P4b-T16 adds screen 11 (day
  /// detail) as a child route (`/cycle/day/:date`); P4b-T23 adds screen 14
  /// (phase correction) — see `lumen-build.md:1136` for the ledger. (This
  /// comment used to cite `:1132`, which is a blank line; `:1136` is T23's
  /// actual line — corrected here per survey-t16/05-routing.md, which
  /// flagged the drift and noted this dartdoc was about to be edited anyway.)
  static const cycle = '/cycle';

  /// The RELATIVE path segment screen 11 (day detail) registers as a CHILD
  /// of [cycle] — go_router requires a sub-route's `path` to be relative
  /// (see the mirror table at `test/core/router/route_table_test.dart`, the
  /// only place this shape existed before P4b-T16). Not a usable navigation
  /// target on its own; [cycleDayPath] builds the concrete path a caller
  /// actually navigates to.
  static const cycleDaySegment = 'day/:date';

  /// Builds the concrete path for screen 11 on [date] —
  /// `/cycle/day/yyyy-MM-dd`.
  ///
  /// Built from zero-padded digits directly, **not** from `Date.toString()`
  /// (`api/model/date.dart:59-65`): that method pads the month and day but
  /// **not the year**, so a route built from it would mis-format any year
  /// under 1000 — harmless for a real calendar date, but this is the one
  /// place a route STRING gets built, so it is built to the same
  /// `yyyy-MM-dd` contract [parseCycleDayDate] parses, not to whatever a
  /// generated type happens to print.
  static String cycleDayPath(DateTime date) =>
      '$cycle/day/${_pad4(date.year)}-${_pad2(date.month)}-${_pad2(date.day)}';

  /// Parses the `:date` path parameter of [cycleDaySegment] into a
  /// local-midnight [DateTime], or `null` when [raw] is not exactly
  /// `yyyy-MM-dd`, names a month outside 1–12, or does not ROUND-TRIP.
  ///
  /// Anchored at both ends (`^...$`), the same discipline
  /// `LumenWire.parseDiagnosedOn` uses for `diagnosedOn` — so a longer
  /// string cannot match a prefix. The round-trip check is the one thing
  /// `parseDiagnosedOn` does not need and this parser does:
  /// `DateTime(2026, 2, 31)` is legal Dart and silently ROLLS to March 3rd,
  /// so a route matched against `/cycle/day/2026-02-31` would otherwise
  /// open — and, once T16b ships writes, WRITE TO — a day the user never
  /// asked for. Constructing the `DateTime` and comparing its own
  /// year/month/day back against the parsed digits is what catches the
  /// rollover; `GoRoute`'s pattern match alone cannot (`/cycle/day/2026-02-31`
  /// matches `day/:date` just as well as a real date does).
  static DateTime? parseCycleDayDate(String? raw) {
    if (raw == null) return null;
    final match = _cycleDayDatePattern.firstMatch(raw);
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12) return null;

    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  /// `yyyy-MM-dd`, anchored at both ends so a longer string (or a trailing
  /// path segment) cannot match a prefix.
  static final RegExp _cycleDayDatePattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})$',
  );

  static String _pad2(int value) => value.toString().padLeft(2, '0');

  static String _pad4(int value) => value.toString().padLeft(4, '0');

  /// Hormones tab (screens 15–21) — branch 2. Not built in P4b.
  static const hormones = '/hormones';

  /// Body tab (screens 22–25) — branch 3. Not built in P4b.
  static const body = '/body';

  /// More tab (treatment, reports, settings) — branch 4. Not built in P4b.
  ///
  /// Note that [profile] (screen 31) is deliberately NOT inside this branch
  /// yet: it is still the authenticated landing route and lives outside the
  /// shell until a task owns the More tab's real contents.
  static const more = '/more';
}
