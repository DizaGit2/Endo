/// Route path constants for the Lumen app.
///
/// These constants are the single source of truth for navigation paths used
/// in [AppRouter] and throughout the feature screens.
abstract final class Routes {
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
  /// Not yet backed by a real screen; routing authed-but-not-onboarded users
  /// here is a P4 refinement (see TODO(P4) in [lumenRedirect]).
  static const onboarding = '/onboarding';
}
