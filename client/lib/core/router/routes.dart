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
  /// [lumenRedirect]. P4b-T8 replaces its placeholder screen with the real
  /// step-by-step flow (screens 3–7).
  static const onboarding = '/onboarding';
}
