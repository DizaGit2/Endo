// Tests for the splash's bounded wait + retry surface (P4b-T1, review fix 1).
//
// TDD (RED first). P4b-T1 moved the `/me` read that decides the onboarding gate
// OFF a screen that has a designed retry state (screen 31) and ONTO the splash,
// which had only an indeterminate spinner. An authenticated user with a
// flaky-but-not-dead network therefore watched that spinner for as long as Dio
// took to give up (connect 15 s / receive 20 s, `dio_provider.dart`), with no
// cancel and no retry.
//
// The redirect's behaviour is unchanged and correct — it must not re-fetch and
// must not guess (brief requirement 6). What was missing is a designed failure
// surface for the hold itself: the gate read is bounded, and exceeding the
// bound turns the spinner into the same error + retry affordance screen 31 uses.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/app.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _MockMeRepository extends Mock implements MeRepository {}

class _AuthenticatedController extends AuthController {
  @override
  AuthStatus build() {
    initialized = Future<void>.value();
    return AuthStatus.authenticated;
  }
}

class _FakeProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async => Fresh(_me());

  @override
  Future<void> saveDisplayName(String name) async {}
}

MeResponse _me() {
  return MeResponse(
    (b) => b
      ..id = 'user-1'
      ..displayName = 'María'
      ..locale = 'es'
      ..timezone = 'Europe/Madrid'
      ..onboardingCompleted = true,
  );
}

/// Pumps the real app with an authenticated session whose `/me` read behaves
/// as [repo] dictates.
Future<void> _pumpApp(WidgetTester tester, MeRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStatusProvider.overrideWith(_AuthenticatedController.new),
        meRepositoryProvider.overrideWithValue(repo),
        profileControllerProvider.overrideWith(_FakeProfileController.new),
      ],
      child: const LumenApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  // -------------------------------------------------------------------------
  // The wait is bounded
  // -------------------------------------------------------------------------

  testWidgets(
    'a /me read that never answers shows the spinner, then the retry surface '
    'once the bound elapses',
    (tester) async {
      final repo = _MockMeRepository();
      when(repo.getMe).thenAnswer((_) => Completer<CacheResult<MeResponse>>().future);

      await _pumpApp(tester, repo);

      // Before the bound: the existing indeterminate spinner.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      // After the bound: a designed, actionable state instead of a spinner
      // that never ends.
      await tester.pump(const Duration(seconds: 9));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // The user is held, not guessed past: no onboarding, no profile.
      expect(find.text('Set up Lumen'), findsNothing);
      expect(find.byType(ProfileScreen), findsNothing);
    },
  );

  testWidgets('the retry surface announces itself (liveRegion)', (tester) async {
    final handle = tester.ensureSemantics();
    final repo = _MockMeRepository();
    when(repo.getMe).thenAnswer((_) => Completer<CacheResult<MeResponse>>().future);

    await _pumpApp(tester, repo);
    await tester.pump(const Duration(seconds: 9));

    final data = tester.getSemantics(
      find.text('Something went wrong. Please try again.'),
    );
    expect(data.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  // -------------------------------------------------------------------------
  // Retry actually re-triggers the read
  // -------------------------------------------------------------------------

  testWidgets('tapping retry re-runs the /me read and lets the user through', (
    tester,
  ) async {
    final repo = _MockMeRepository();
    var calls = 0;
    when(repo.getMe).thenAnswer((_) {
      calls++;
      // First attempt hangs; the retry succeeds.
      return calls == 1
          ? Completer<CacheResult<MeResponse>>().future
          : Future<CacheResult<MeResponse>>.value(Fresh(_me()));
    });

    await _pumpApp(tester, repo);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(calls, 2);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The bound must not fire on a healthy start
  // -------------------------------------------------------------------------

  testWidgets('a prompt /me read never shows the retry surface', (tester) async {
    final repo = _MockMeRepository();
    when(repo.getMe).thenAnswer((_) async => Fresh(_me()));

    await _pumpApp(tester, repo);
    await tester.pump(const Duration(seconds: 30));

    expect(find.text('Try again'), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
