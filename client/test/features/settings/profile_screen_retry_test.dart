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
          // A `Failure` — the shape `MeRepository.getMe` actually throws for
          // every non-transient error (`cachedRead`'s `_resolveFailure`
          // rethrows auth/validation/not-found/TLS/unknown, and answers
          // Stale/NetworkRequired for the other two).
          //
          // Until P4b-T26 this line threw a `StateError` instead, for one
          // reason: riverpod's `defaultRetry` skips `error is Error` but
          // retries a `Failure` ten times with backoff, publishing
          // `AsyncLoading(retrying: true)` — which `AsyncValue.when` routes
          // to `loading`, so the error body this test is named after never
          // rendered. **The test was green because it threw something the
          // app does not throw.** `lumenRetry` is what makes the honest
          // shape work here, and swapping it back reddens this test.
          throw const TlsFailure();
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
