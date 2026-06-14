import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/onboarding/application/account_controller.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';

// Phone-frame dimensions matching the design spec.
const _kWidth = 390.0;
const _kHeight = 844.0;

// ---------------------------------------------------------------------------
// Fake controllers for golden tests (no real network / auth)
// ---------------------------------------------------------------------------

/// A minimal [AuthController] that never transitions state.
/// Golden tests only need the idle state of the AccountScreen.
class _FakeAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.unauthenticated;
}

/// An idle [AccountController] (`AsyncData&lt;void&gt;`) with no-op actions.
class _FakeAccountController extends AccountController {
  @override
  Future<void> build() async {}
}

// ---------------------------------------------------------------------------
// Test wrapper
// ---------------------------------------------------------------------------

/// Wraps [AccountScreen] in a ProviderScope with safe overrides, a sized box,
/// and a MaterialApp so Scaffold + theme tokens resolve correctly.
Widget _buildApp(Brightness brightness) {
  return ProviderScope(
    overrides: [
      authStatusProvider.overrideWith(() => _FakeAuthController()),
      accountControllerProvider.overrideWith(() => _FakeAccountController()),
    ],
    child: SizedBox(
      width: _kWidth,
      height: _kHeight,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(_kWidth, _kHeight)),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lumenTheme(brightness),
          home: const AccountScreen(),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  goldenTest(
    'AccountScreen light theme',
    fileName: 'account_screen_light',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'Light',
          child: _buildApp(Brightness.light),
        ),
      ],
    ),
  );

  goldenTest(
    'AccountScreen dark theme',
    fileName: 'account_screen_dark',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'Dark',
          child: _buildApp(Brightness.dark),
        ),
      ],
    ),
  );
}
