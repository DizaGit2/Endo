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
  /// P4b-T15 replaces its placeholder with the real dashboard.
  static const home = '/home';

  /// Cycle tab (screens 10/11/14) — branch 1.
  ///
  /// P4b-T16/T17 replace its placeholder with the calendar and day detail.
  static const cycle = '/cycle';

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
