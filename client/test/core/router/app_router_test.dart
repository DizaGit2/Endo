import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/app_router.dart';

void main() {
  group('lumenRedirect — unknown (holds on splash)', () {
    test('unknown + "/" redirects to "/splash"', () {
      expect(lumenRedirect(AuthStatus.unknown, '/'), equals('/splash'));
    });

    test('unknown + "/account" redirects to "/splash"', () {
      expect(lumenRedirect(AuthStatus.unknown, '/account'), equals('/splash'));
    });

    test('unknown + "/profile" redirects to "/splash"', () {
      expect(lumenRedirect(AuthStatus.unknown, '/profile'), equals('/splash'));
    });

    test('unknown + "/splash" returns null (already on splash)', () {
      expect(lumenRedirect(AuthStatus.unknown, '/splash'), isNull);
    });
  });

  group('lumenRedirect — unauthenticated', () {
    test('unauthenticated on "/" returns null (already at welcome)', () {
      expect(lumenRedirect(AuthStatus.unauthenticated, '/'), isNull);
    });

    test('unauthenticated on "/account" returns null (login screen allowed)', () {
      expect(lumenRedirect(AuthStatus.unauthenticated, '/account'), isNull);
    });

    test('unauthenticated on "/profile" redirects to "/"', () {
      expect(lumenRedirect(AuthStatus.unauthenticated, '/profile'), equals('/'));
    });

    test('unauthenticated on any other path redirects to "/"', () {
      expect(
        lumenRedirect(AuthStatus.unauthenticated, '/some/deep/path'),
        equals('/'),
      );
    });

    test('unauthenticated on "/splash" redirects to "/"', () {
      expect(lumenRedirect(AuthStatus.unauthenticated, '/splash'), equals('/'));
    });
  });

  group('lumenRedirect — authenticated', () {
    test('authenticated on "/" redirects to "/profile"', () {
      expect(lumenRedirect(AuthStatus.authenticated, '/'), equals('/profile'));
    });

    test('authenticated on "/account" redirects to "/profile"', () {
      expect(
        lumenRedirect(AuthStatus.authenticated, '/account'),
        equals('/profile'),
      );
    });

    test('authenticated on "/profile" returns null (no redirect needed)', () {
      expect(lumenRedirect(AuthStatus.authenticated, '/profile'), isNull);
    });

    test('authenticated on "/splash" redirects to "/profile"', () {
      expect(
        lumenRedirect(AuthStatus.authenticated, '/splash'),
        equals('/profile'),
      );
    });
  });

  group('lumenRedirect — unknown-route fallback (unregistered paths)', () {
    // "/nope" and "/onboarding" are not registered GoRoutes (Routes.onboarding
    // is a reserved constant for P4 — see the TODO(P4) doc comment on
    // lumenRedirect). Both must be routed by auth status instead of falling
    // through to GoRouter's built-in "page not found" error screen — this
    // used to be a bug for authenticated users (see the removed "allow
    // through" test above), who would hit that error page directly.

    test('authenticated + "/nope" redirects to "/profile"', () {
      expect(
        lumenRedirect(AuthStatus.authenticated, '/nope'),
        equals('/profile'),
      );
    });

    test(
      'authenticated + "/onboarding" redirects to "/profile" (not yet registered)',
      () {
        expect(
          lumenRedirect(AuthStatus.authenticated, '/onboarding'),
          equals('/profile'),
        );
      },
    );

    test('unauthenticated + "/nope" redirects to "/"', () {
      expect(lumenRedirect(AuthStatus.unauthenticated, '/nope'), equals('/'));
    });

    test('unauthenticated + "/onboarding" redirects to "/"', () {
      expect(
        lumenRedirect(AuthStatus.unauthenticated, '/onboarding'),
        equals('/'),
      );
    });

    test('unknown auth + "/nope" redirects to "/splash"', () {
      expect(lumenRedirect(AuthStatus.unknown, '/nope'), equals('/splash'));
    });

    test('unknown auth + "/onboarding" redirects to "/splash"', () {
      expect(
        lumenRedirect(AuthStatus.unknown, '/onboarding'),
        equals('/splash'),
      );
    });
  });
}
