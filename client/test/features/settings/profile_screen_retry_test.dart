// Widget tests — retry affordances on ProfileScreen error / NetworkRequired
// states (TDD — RED first, P3c-T11).
//
// Verifies that the "Try again" (generic error) and "Retry" (offline /
// NetworkRequired) buttons call ref.invalidate(profileControllerProvider),
// and that once the underlying fetch starts succeeding, tapping the button
// renders the loaded profile — the only way to recover today is leaving and
// re-entering the route (profileControllerProvider is autoDispose).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MeResponse _sampleMe() => MeResponse(
  (b) => b
    ..id = 'user-1'
    ..displayName = 'María'
    ..locale = 'es'
    ..timezone = 'Europe/Madrid'
    ..onboardingCompleted = true,
);

/// A [ProfileController] whose `build()` delegates to [_next] every time it
/// (re)builds. `ref.invalidate` disposes the current notifier and invokes the
/// `overrideWith` factory again to construct a fresh instance, so [_next]
/// (captured by reference from the test) is what lets a test script a
/// fail-then-succeed sequence across a retry.
class _ScriptedProfileController extends ProfileController {
  _ScriptedProfileController(this._next);
  final CacheResult<MeResponse> Function() _next;

  @override
  Future<CacheResult<MeResponse>> build() async => _next();
}

Widget _wrap(CacheResult<MeResponse> Function() next) {
  return ProviderScope(
    overrides: [
      profileControllerProvider.overrideWith(
        () => _ScriptedProfileController(next),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lumenTheme(Brightness.light),
      home: const ProfileScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets(
    'Error body shows "Try again"; tapping it retries and renders the '
    'profile once the fetch succeeds',
    (tester) async {
      var attempt = 0;
      await tester.pumpWidget(
        _wrap(() {
          attempt++;
          if (attempt == 1) {
            // A plain Error (not a Failure/Exception) so Riverpod's default
            // retry policy (ProviderContainer.defaultRetry — up to 10
            // automatic retries with backoff) does NOT kick in: it explicitly
            // skips retrying `error is Error`. That keeps this test's timing
            // deterministic instead of racing the retry timer.
            throw StateError('Simulated failure for test.');
          }
          return Fresh(_sampleMe());
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Profile & health'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Profile & health'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets(
    'NetworkRequired body shows "Retry"; tapping it retries and renders the '
    'profile once the fetch succeeds',
    (tester) async {
      var attempt = 0;
      await tester.pumpWidget(
        _wrap(() {
          attempt++;
          if (attempt == 1) {
            return const NetworkRequired<MeResponse>(NetworkFailure());
          }
          return Fresh(_sampleMe());
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Profile & health'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Profile & health'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    },
  );
}
