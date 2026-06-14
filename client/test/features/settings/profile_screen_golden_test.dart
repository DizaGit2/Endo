// Golden tests for ProfileScreen — light + dark at 390×844.
//
// Uses a fake ProfileController that holds a pre-loaded Fresh(MeResponse) so
// goldens are deterministic (no real network).

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';

const _kWidth = 390.0;
const _kHeight = 844.0;

// ---------------------------------------------------------------------------
// Fake controllers
// ---------------------------------------------------------------------------

/// A fake [AuthController] that is always authenticated (for golden tests).
class _FakeAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.authenticated;
}

/// A fake [ProfileController] that immediately yields a loaded profile.
class _FakeProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async {
    return Fresh(
      MeResponse(
        (b) => b
          ..id = 'user-golden'
          ..displayName = 'María'
          ..locale = 'es'
          ..timezone = 'Europe/Madrid'
          ..onboardingCompleted = true,
      ),
    );
  }

  @override
  Future<void> saveDisplayName(String name) async {}
}

// ---------------------------------------------------------------------------
// Test wrapper
// ---------------------------------------------------------------------------

Widget _buildApp(Brightness brightness) {
  return ProviderScope(
    overrides: [
      authStatusProvider.overrideWith(() => _FakeAuthController()),
      profileControllerProvider
          .overrideWith(() => _FakeProfileController()),
    ],
    child: SizedBox(
      width: _kWidth,
      height: _kHeight,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(_kWidth, _kHeight)),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lumenTheme(brightness),
          home: const ProfileScreen(),
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
    'ProfileScreen light theme',
    fileName: 'profile_screen_light',
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
    'ProfileScreen dark theme',
    fileName: 'profile_screen_dark',
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
