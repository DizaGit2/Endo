/// Route path constants for the Lumen app.
///
/// These constants are the single source of truth for navigation paths used
/// in [AppRouter] and throughout the feature screens.
abstract final class Routes {
  /// Splash shown while auth state is still resolving (cold start), so a stored
  /// session lands on [home] without a flash of [welcome].
  static const splash = '/splash';

  /// Welcome / login gateway (onboarding step 1).
  static const welcome = '/';

  /// Account screen — register or sign in (onboarding step 2).
  ///
  /// Both "Begin" and "I already have an account" on [WelcomeScreen] land here;
  /// the login-vs-register split is handled within the account screen (T7).
  static const account = '/account';

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

  /// Screen 12 (the symptom form) — a TOP-LEVEL, non-shell route (P4b-T20b).
  ///
  /// **Outside the shell, and exactly one URL.** The mockup draws no bottom
  /// nav, and this is a task flow you enter and leave — the same shape
  /// [account] and [onboarding] already have, so it is not a new routing
  /// pattern for this app. It is PUSHED (never `go`) from whichever tab the
  /// user was in — today the Home branch's Symptom quick-log tile and screen
  /// 9's "+ Add details" — so popping returns them to that branch with its
  /// own back stack intact. Registering it under one tab instead would have
  /// given the same screen two addresses with different back behaviour, which
  /// is the problem R-19 exists to prevent.
  ///
  /// `/new` rather than a bare `/symptoms`: T19 cut `PUT` and `DELETE`, so
  /// this screen is CREATE-ONLY, and `/symptoms` is the collection this app
  /// has no browse surface for. Symptom edit is booked for P6 and will want
  /// its own `/symptoms/:id`, which this path leaves free.
  static const symptomsNew = '/symptoms/new';

  /// Screen 13 (the body map) — a TOP-LEVEL, non-shell route (P4b-T21b).
  ///
  /// [symptomsNew]'s shape, for [symptomsNew]'s reasons: the mockup draws no
  /// bottom nav, and this is a task flow pushed from screen 12 and popped back
  /// into it. It is a SIBLING of `/symptoms/new` rather than a child of it —
  /// a child route would nest screen 13's Navigator inside screen 12's, and
  /// `/symptoms/new` is not itself a shell.
  ///
  /// **It writes nothing** (R-11: the batch is screen 12's, all-or-nothing),
  /// so the path names a surface rather than a resource: `body-map`, not
  /// `points`. Kebab-case matches nothing else in this file only because
  /// nothing else in this file is two words.
  ///
  /// A COLD deep link here is legal and lands on the screen, with an empty
  /// autoDispose form behind it — see [BodyMapScreen]'s own dartdoc for what
  /// leaving then does, and `test/core/router/body_map_route_test.dart` for
  /// the test that pins it.
  static const symptomsBodyMap = '/symptoms/body-map';

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
  /// **The authenticated default since R-19 (P4b-T17)** — `lumenRedirect`
  /// sends a signed-in, onboarded user here now, not to a top-level
  /// `/profile` route (removed — screen 31 now mounts under [more]).
  /// `docs/superpowers/plans/lumen-build.md`'s R-19 entry has the full
  /// reasoning for why the redirect flip and the [more] branch mount had to
  /// land in the same commit.
  static const home = '/home';

  /// Cycle tab (screens 10/11/14) — branch 1.
  ///
  /// Screen 10 (calendar) shipped at P4b-T15. P4b-T16 adds screen 11 (day
  /// detail) as a child route (`/cycle/day/:date`); P4b-T23 adds screen 14
  /// (phase correction) — see the **T23** entry in
  /// `docs/superpowers/plans/lumen-build.md` for the ledger.
  ///
  /// (Citation history, kept because it is the case R-23 exists for: this
  /// cited `:1132` at T16, was "corrected" to `:1136` in the same breath, and
  /// `:1136` had drifted onto an unrelated paragraph by P4b-T22c without
  /// anyone touching this file. Naming the task instead of the line is the
  /// rule now.)
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

  /// More tab (treatment, reports, settings) — branch 4.
  ///
  /// **Screen 31 (profile) mounts as this branch's ROOT since P4b-T17
  /// (R-19)** — the settled home CLAUDE.md always intended for it, and the
  /// ONLY URL that reaches it: there is no longer a top-level `/profile`
  /// route, so profile has exactly one address. **[privacy] is that root's
  /// first child, since P4b-T22c**, the same way `/cycle/day/:date` sits under
  /// [cycle]; T22a pushes screen 32 in beside it. Treatment and reports (the
  /// rest of what this tab names) are not built in P4b and stay on
  /// [TabPlaceholderScreen] — R-10.
  static const more = '/more';

  /// The RELATIVE path segment screen 36 (privacy & security) registers as a
  /// CHILD of [more] — go_router requires a sub-route's `path` to be relative,
  /// the same shape [cycleDaySegment] has under [cycle]. Not a usable
  /// navigation target on its own; [privacy] is the concrete path.
  static const privacySegment = 'privacy';

  /// Screen 36 (privacy & security) — `/more/privacy`, a CHILD of [more]
  /// (P4b-T22c).
  ///
  /// **A child of the More branch root, not a top-level route.** Screen 36 is
  /// a settings leaf reached from screen 31, so it belongs inside that
  /// branch's own Navigator: `context.pop()` returns to profile with the tab
  /// still selected and the bottom nav still on screen. Registering it
  /// top-level would render it over the whole app and throw the More branch's
  /// history away — the shape [symptomsNew] uses deliberately, for a task flow
  /// entered from ANY tab, which this is not.
  ///
  /// Composed from [more] rather than spelled out, so renaming the branch root
  /// cannot leave this pointing at a path that no longer exists.
  ///
  /// **What it reaches matters more than where it sits.** `DELETE /me` has
  /// worked end to end since P4a and, until this route existed, was reachable
  /// by nobody — behind a screen that advertises the affordance. See the T22c
  /// entry in `docs/superpowers/plans/lumen-build.md`.
  static const privacy = '$more/$privacySegment';
}
