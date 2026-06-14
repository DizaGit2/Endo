import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

// ---------------------------------------------------------------------------
// Fake auth controller — avoids real TokenStore / OidcClient in tests
// ---------------------------------------------------------------------------

/// Minimal [AuthController] stub that returns a fixed [AuthStatus] without
/// touching [TokenStore] or [IOidcClient] — safe for widget tests.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._status);
  final AuthStatus _status;

  @override
  AuthStatus build() {
    initialized = Future.value();
    return _status;
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Returns a [ProviderScope] with [authStatusProvider] overridden to
/// [status] so the router guard renders the expected screen.
Widget _appWithAuth(AuthStatus status) {
  return ProviderScope(
    overrides: [
      authStatusProvider.overrideWith(() => _FakeAuthController(status)),
    ],
    child: const LumenApp(),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('LumenApp smoke test — welcome screen renders when unauthenticated',
      (tester) async {
    await tester.pumpWidget(_appWithAuth(AuthStatus.unauthenticated));

    // Give GoRouter a frame to settle on the welcome route.
    await tester.pumpAndSettle();

    // The welcome screen shows the app tagline headline.
    expect(find.text('Your cycle, understood'), findsOneWidget);
  });

  testWidgets(
    'LumenApp smoke test — light theme carries LumenColors extension',
    (tester) async {
      await tester.pumpWidget(_appWithAuth(AuthStatus.unauthenticated));

      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final ext = app.theme!.extension<LumenColors>();

      expect(ext, isNotNull);
      // Spot-check: the extension's accent matches the light-mode token.
      expect(ext!.accent, lumenLight.accent);
      expect(ext.bg, lumenLight.bg);
    },
  );
}
