// Guard test — TDD (P3c-T13, a11y pass + dingbat→Icon swap).
//
// Decorative dingbat glyphs ('✦', '✓', '›') must never appear inside a Text
// widget's rendered content: screen readers announce them as raw punctuation
// noise, and CLAUDE.md's "no emoji in UI" rule extends to them in spirit.
// Real `Icon`s (semantics-silent by default) replace them across the 5
// screens in scope for this task.
//
// Pumps each screen with its own minimal harness (mirroring each screen's
// golden-test setup) and walks every live `Text` widget, checking both the
// plain `data` string and the flattened `textSpan` (Text.rich) content.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/onboarding/application/account_controller.dart';
import 'package:lumen/features/onboarding/presentation/account_screen.dart';
import 'package:lumen/features/onboarding/presentation/welcome_screen.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/help_about_screen.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/features/shell/presentation/tab_placeholder_screen.dart';

// ---------------------------------------------------------------------------
// Banned glyphs + helpers
// ---------------------------------------------------------------------------

const _bannedGlyphs = ['✦', '✓', '›'];

/// The effective plain-text content of a [Text] widget, covering both the
/// plain `data` constructor and the rich `Text.rich` (`textSpan`) form.
String _effectiveText(Text widget) {
  if (widget.data != null) return widget.data!;
  return widget.textSpan?.toPlainText() ?? '';
}

void _expectNoDingbats(WidgetTester tester, String screenName) {
  final texts = tester.widgetList<Text>(find.byType(Text));
  expect(
    texts,
    isNotEmpty,
    reason: '$screenName rendered no Text widgets — harness is likely broken.',
  );
  for (final widget in texts) {
    final text = _effectiveText(widget);
    for (final glyph in _bannedGlyphs) {
      expect(
        text.contains(glyph),
        isFalse,
        reason: '$screenName renders banned dingbat "$glyph" in Text: "$text"',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Fakes (minimal — mirrors each screen's own golden-test harness)
// ---------------------------------------------------------------------------

class _UnauthenticatedAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.unauthenticated;
}

class _AuthenticatedAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.authenticated;
}

class _IdleAccountController extends AccountController {
  @override
  Future<void> build() async {}
}

class _FakeProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async {
    return Fresh(
      MeResponse(
        (b) => b
          ..id = 'user-dingbat-check'
          ..displayName = 'Dana Lee'
          ..locale = 'en'
          ..timezone = 'UTC'
          ..onboardingCompleted = true,
      ),
    );
  }

  @override
  Future<void> saveDisplayName(String name) async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('WelcomeScreen has no dingbat glyphs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lumenTheme(Brightness.light),
        home: const WelcomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoDingbats(tester, 'WelcomeScreen');
  });

  testWidgets('AccountScreen has no dingbat glyphs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStatusProvider.overrideWith(
            () => _UnauthenticatedAuthController(),
          ),
          accountControllerProvider.overrideWith(
            () => _IdleAccountController(),
          ),
        ],
        child: MaterialApp(
          theme: lumenTheme(Brightness.light),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoDingbats(tester, 'AccountScreen');
  });

  testWidgets('ProfileScreen has no dingbat glyphs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStatusProvider.overrideWith(() => _AuthenticatedAuthController()),
          profileControllerProvider.overrideWith(
            () => _FakeProfileController(),
          ),
        ],
        child: MaterialApp(
          theme: lumenTheme(Brightness.light),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoDingbats(tester, 'ProfileScreen');
  });

  testWidgets('PrivacyScreen has no dingbat glyphs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lumenTheme(Brightness.light),
        home: const PrivacyScreen(),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoDingbats(tester, 'PrivacyScreen');
  });

  testWidgets('HelpAboutScreen has no dingbat glyphs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lumenTheme(Brightness.light),
        home: const HelpAboutScreen(),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoDingbats(tester, 'HelpAboutScreen');
  });

  testWidgets('TabPlaceholderScreen has no dingbat glyphs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lumenTheme(Brightness.light),
        home: const TabPlaceholderScreen(heading: 'More isn\'t here yet'),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoDingbats(tester, 'TabPlaceholderScreen');
  });
}
