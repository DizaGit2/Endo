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

    test('authenticated on other paths returns null (allow through)', () {
      expect(
        lumenRedirect(AuthStatus.authenticated, '/onboarding'),
        isNull,
      );
    });

    test('authenticated on "/splash" redirects to "/profile"', () {
      expect(
        lumenRedirect(AuthStatus.authenticated, '/splash'),
        equals('/profile'),
      );
    });
  });
}
