// Semantics test — the splash spinner (P3c-T13, house a11y pattern).
//
// TDD (RED first): _SplashScreen's CircularProgressIndicator (app_router.dart)
// had no semanticsLabel — a screen reader user landing on a cold start hears
// nothing while auth state resolves. _SplashScreen is private to
// app_router.dart, so this is exercised through the real LumenApp + GoRouter
// (matching lumenRedirect's own "unknown auth stays on /splash" contract
// already covered by app_router_test.dart's pure-function tests).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app.dart';
import 'package:lumen/core/auth/auth_controller.dart';

/// Stays at AuthStatus.unknown forever — lumenRedirect holds unknown-auth
/// on "/splash" (see app_router_test.dart), so the splash screen keeps
/// rendering for the duration of the test.
class _UnknownAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.unknown;
}

void main() {
  testWidgets('Splash spinner exposes a semantics label', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStatusProvider.overrideWith(() => _UnknownAuthController()),
        ],
        child: const LumenApp(),
      ),
    );
    // Not pumpAndSettle(): the splash's CircularProgressIndicator is
    // indeterminate and animates forever, so "settle" never arrives. Two
    // pumps are enough for GoRouter's initial redirect evaluation + build.
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    handle.dispose();
  });
}
