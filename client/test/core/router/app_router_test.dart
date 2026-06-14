import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/router/app_router.dart';

void main() {
  group('lumenRedirect — unknown', () {
    test('unknown + "/" returns null', () {
      expect(lumenRedirect(AuthStatus.unknown, '/'), isNull);
    });

    test('unknown + "/account" returns null', () {
      expect(lumenRedirect(AuthStatus.unknown, '/account'), isNull);
    });

    test('unknown + "/profile" returns null', () {
      expect(lumenRedirect(AuthStatus.unknown, '/profile'), isNull);
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
  });
}
