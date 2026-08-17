// Semantics test — the splash spinner (P3c-T13, house a11y pattern).
//
// TDD (RED first): _SplashScreen's CircularProgressIndicator (app_router.dart)
// had no semanticsLabel — a screen reader user landing on a cold start hears
// nothing while auth state resolves. _SplashScreen is private to
// app_router.dart, so this is exercised through the real LumenApp + GoRouter
// (matching lumenRedirect's own "unknown auth stays on /splash" contract
// already covered by app_router_test.dart's pure-function tests).
//
// _SplashScreen is private, so it is NOT a `*_screen.dart` file under
// `lib/features/**/presentation/` and the screen registry does not discover
// it. This file is its coverage.

import 'package:lumen/core/auth/auth_controller.dart';

import '../../support/harness.dart';

void main() {
  testWidgetsWithSemantics('Splash spinner exposes a semantics label', (
    tester,
  ) async {
    // AuthStatus.unknown forever — lumenRedirect holds unknown-auth on
    // "/splash" (see app_router_test.dart), so the splash keeps rendering.
    //
    // settle: false — the splash's CircularProgressIndicator is indeterminate
    // and animates forever, so "settle" never arrives. Two pumps in total are
    // enough for GoRouter's initial redirect evaluation + build.
    await pumpLumenApp(
      tester,
      overrides: lumenOverrides(auth: AuthStatus.unknown),
      settle: false,
    );
    await tester.pump();

    expectLabeledSpinner(tester, 'Loading');
  });
}
