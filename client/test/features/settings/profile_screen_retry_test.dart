// Widget tests — retry affordances on ProfileScreen error / NetworkRequired
// states (TDD — RED first, P3c-T11).
//
// Verifies that the "Try again" (generic error) and "Retry" (offline /
// NetworkRequired) buttons call ref.invalidate(profileControllerProvider),
// and that once the underlying fetch starts succeeding, tapping the button
// renders the loaded profile — the only way to recover today is leaving and
// re-entering the route (profileControllerProvider is autoDispose).
//
// Both use `expectRetryReissuesOneRequest` (test/support/retry_trap.dart),
// which additionally pins the two things a hand-written retry test tends to
// omit: that the affordance is a real, labelled button, and that a tap
// re-issues EXACTLY ONE read rather than none or two.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

Future<void> _pump(
  WidgetTester tester,
  CacheResult<MeResponse> Function() next,
) {
  return pumpApp(
    tester,
    home: const ProfileScreen(),
    overrides: [
      ...lumenOverrides(),
      profileControllerProvider.overrideWith(
        () => _ScriptedProfileController(next),
      ),
    ],
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
      await _pump(tester, () {
        attempt++;
        if (attempt == 1) {
          // A plain Error (not a Failure/Exception) so Riverpod's default
          // retry policy (ProviderContainer.defaultRetry — up to 10
          // automatic retries with backoff) does NOT kick in: it explicitly
          // skips retrying `error is Error`. That keeps this test's timing
          // deterministic instead of racing the retry timer.
          throw StateError('Simulated failure for test.');
        }
        return Fresh(meResponseFixture(id: 'user-1'));
      });

      expect(find.text('Profile & health'), findsNothing);

      await expectRetryReissuesOneRequest(
        tester,
        label: 'Try again',
        requestCount: () => attempt,
      );

      expect(find.text('Profile & health'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets(
    'NetworkRequired body shows "Retry"; tapping it retries and renders the '
    'profile once the fetch succeeds',
    (tester) async {
      var attempt = 0;
      await _pump(tester, () {
        attempt++;
        if (attempt == 1) {
          return const NetworkRequired<MeResponse>(NetworkFailure());
        }
        return Fresh(meResponseFixture(id: 'user-1'));
      });

      expect(find.text('Profile & health'), findsNothing);

      await expectRetryReissuesOneRequest(
        tester,
        label: 'Retry',
        requestCount: () => attempt,
      );

      expect(find.text('Profile & health'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    },
  );
}
