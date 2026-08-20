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
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/data/me_repository.dart';
import 'package:lumen/features/onboarding/presentation/onboarding_shell_screen.dart';
import 'package:lumen/shared/widgets/lumen_error_retry.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _MockMeRepository extends Mock implements MeRepository {}

class _FakeProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async => Fresh(_me());

  @override
  Future<void> saveDisplayName(String name) async {}
}

/// Screen 8, pinned to a settled Fresh view — P4b-T17 (R-19) made it the
/// authed landing screen this file's gate ultimately lands on, so a
/// successful `/me` read now has a dashboard's own reads (`GET
/// /cycle/calendar` x2) behind it too. Pinned settled for the same reason
/// `_FakeProfileController` is: this file's subject is the GATE, not the
/// dashboard's content.
class _SettledDashboard extends DashboardController {
  @override
  Future<CacheResult<DashboardView>> build() async => Fresh(
    DashboardView(
      today: DateTime(2026, 4, 20),
      displayName: 'Maya',
      todayPain: null,
      todayMood: null,
      yesterdayPain: null,
    ),
  );
}

MeResponse _me() => meResponseFixture(id: 'user-1');

/// Pumps the real app with an authenticated session whose `/me` read behaves
/// as [repo] dictates.
///
/// settle: false — the splash spinner animates forever, so settle never
/// arrives while the gate read is in flight.
Future<void> _pumpApp(WidgetTester tester, MeRepository repo) async {
  await pumpLumenApp(
    tester,
    settle: false,
    overrides: [
      ...lumenOverrides(),
      meRepositoryProvider.overrideWithValue(repo),
      profileControllerProvider.overrideWith(_FakeProfileController.new),
      dashboardControllerProvider.overrideWith(_SettledDashboard.new),
      greetingTimeOfDayProvider.overrideWithValue('Good morning'),
    ],
  );
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
      when(
        repo.getMe,
      ).thenAnswer((_) => Completer<CacheResult<MeResponse>>().future);

      await _pumpApp(tester, repo);

      // Before the bound: the existing indeterminate spinner.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      // After the bound: a designed, actionable state instead of a spinner
      // that never ends.
      await tester.pump(const Duration(seconds: 9));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      // The user is held, not guessed past: no onboarding, no dashboard
      // (the authed landing screen since R-19 — P4b-T17).
      expect(find.byType(OnboardingShellScreen), findsNothing);
      expect(find.byType(DashboardScreen), findsNothing);
    },
  );

  testWidgetsWithSemantics('the retry surface announces itself (liveRegion)', (
    tester,
  ) async {
    final repo = _MockMeRepository();
    when(
      repo.getMe,
    ).thenAnswer((_) => Completer<CacheResult<MeResponse>>().future);

    await _pumpApp(tester, repo);
    await tester.pump(const Duration(seconds: 9));

    expectLiveRegion(tester, 'Something went wrong. Please try again.');
    // …and it is the ONE whole-surface failure widget, not this layer's own
    // copy of it. T1 wrote `_GateUnavailableBody` as a verbatim copy of screen
    // 31's `_ErrorBody` precisely so that P4b-T5 would collapse both onto
    // `LumenErrorRetry`; without this line the copy could come back and every
    // other assertion in this file would still pass.
    expect(find.byType(LumenErrorRetry), findsOneWidget);
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
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The bound must not fire on a healthy start
  // -------------------------------------------------------------------------

  testWidgets('a prompt /me read never shows the retry surface', (
    tester,
  ) async {
    final repo = _MockMeRepository();
    when(repo.getMe).thenAnswer((_) async => Fresh(_me()));

    await _pumpApp(tester, repo);
    await tester.pump(const Duration(seconds: 30));

    expect(find.text('Try again'), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
  });
}
