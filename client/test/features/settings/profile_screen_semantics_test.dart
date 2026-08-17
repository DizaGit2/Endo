// Semantics tests — ProfileScreen (P3c-T13, house a11y pattern).
//
// TDD (RED first): before this task, ProfileScreen had bare GestureDetector
// tap targets (Edit, Sign out) with no button semantics, an unlabeled loading
// spinner, error bodies a screen reader never hears about, and label/value
// rows that read as three disconnected fragments instead of one unit. All are
// fixed in profile_screen.dart.
//
// The user-card row (avatar + name + id) has NO onTap in this codebase today
// (a mockup-fidelity chevron with nothing wired behind it) — it is treated as
// an informational MergeSemantics unit, NOT a button; marking it button:true
// with no action would be a real a11y regression (announces "button", taps
// do nothing). The isButton:false assertion below is a deliberate regression
// guard for that decision, not an oversight.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Controller archetypes (the four states of a data-driven screen)
// ---------------------------------------------------------------------------

class _FreshProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async => Fresh(meResponseFixture());

  @override
  Future<void> saveDisplayName(String name) async {}
}

/// Never resolves — keeps the provider in AsyncLoading for the whole test.
class _PendingProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() =>
      Completer<CacheResult<MeResponse>>().future;
}

class _ErrorProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async {
    // A plain Error (not a Failure/Exception) so Riverpod's default retry
    // policy doesn't kick in — see profile_screen_retry_test.dart for the
    // same trick.
    throw StateError('Simulated failure for test.');
  }
}

class _NetworkRequiredProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async =>
      const NetworkRequired<MeResponse>(NetworkFailure());
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester,
  ProfileController Function() controller, {
  bool settle = true,
}) {
  return pumpApp(
    tester,
    home: const ProfileScreen(),
    settle: settle,
    overrides: [
      ...lumenOverrides(),
      profileControllerProvider.overrideWith(controller),
    ],
  );
}

void main() {
  testWidgetsWithSemantics('Loading state: spinner has a semanticsLabel', (
    tester,
  ) async {
    // settle: false — the spinner animates forever, so settle never arrives.
    await _pump(tester, _PendingProfileController.new, settle: false);

    expectLabeledSpinner(tester, 'Loading profile');
  });

  testWidgetsWithSemantics(
    'Edit button exposes button semantics with label "Edit"',
    (tester) async {
      await _pump(tester, _FreshProfileController.new);

      expect(find.bySemanticsLabel('Edit'), findsOneWidget);
      expectLabeledButton(tester, find.bySemanticsLabel('Edit'), 'Edit');
    },
  );

  testWidgetsWithSemantics(
    'Edit button carries a tap action assistive tech can actually invoke '
    '(excludeSemantics:true on the wrapping Semantics node hides the '
    "GestureDetector's onTap from the tree unless Semantics itself is given "
    'one)',
    (tester) async {
      await _pump(tester, _FreshProfileController.new);

      // expectLabeledButton asserts the tap ACTION exists; this test also
      // drives it exactly as assistive tech would — dispatching
      // SemanticsAction.tap through the semantics tree (NOT a raw pointer tap
      // on the GestureDetector underneath), which throws a StateError if the
      // node does not support the action.
      expectLabeledButton(tester, find.bySemanticsLabel('Edit'), 'Edit');

      tester.semantics.tap(find.semantics.byLabel('Edit'));
      await tester.pump();

      expect(find.text('Edit display name'), findsOneWidget);
    },
  );

  testWidgetsWithSemantics(
    'Sign out row exposes button semantics with label "Sign out"',
    (tester) async {
      await _pump(tester, _FreshProfileController.new);

      expect(find.bySemanticsLabel('Sign out'), findsOneWidget);
      expectLabeledButton(
        tester,
        find.bySemanticsLabel('Sign out'),
        'Sign out',
      );
    },
  );

  testWidgetsWithSemantics(
    'Sign out row carries a tap action that actually invokes logout() '
    '(excludeSemantics:true on the wrapping Semantics node hides the '
    "GestureDetector's onTap from the tree unless Semantics itself is given "
    'one)',
    (tester) async {
      // Real AuthController.logout() (only build() is faked by
      // lumenOverrides) reads TokenStore/CacheStore via ref — stub them so
      // the async chain resolves deterministically in one microtask hop each,
      // instead of depending on platform-channel/MissingPluginException
      // timing from the real FlutterSecureStorage-backed TokenStore.
      final store = emptyTokenStore();
      final cache = emptyCacheStore();

      final container = ProviderContainer(
        overrides: [
          ...lumenOverrides(cacheStore: cache, tokenStore: store),
          profileControllerProvider.overrideWith(_FreshProfileController.new),
        ],
      );
      addTearDown(container.dispose);

      await pumpApp(tester, home: const ProfileScreen(), container: container);

      expectLabeledButton(
        tester,
        find.bySemanticsLabel('Sign out'),
        'Sign out',
      );

      // Drive it for real: dispatch SemanticsAction.tap (assistive tech),
      // not a raw pointer tap, and confirm logout() actually ran by
      // observing the resulting AuthStatus transition.
      tester.semantics.tap(find.semantics.byLabel('Sign out'));
      await tester.pumpAndSettle();

      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
      verify(() => store.clear()).called(1);
    },
  );

  testWidgetsWithSemantics(
    'Display name row merges label + value into one unit; Edit stays a '
    'separate button',
    (tester) async {
      await _pump(tester, _FreshProfileController.new);

      expectNotAButton(
        tester,
        find.text('Display name'),
        merged: const ['Display name', 'María'],
      );

      // Edit remains independently actionable within the merged row.
      expectLabeledButton(tester, find.bySemanticsLabel('Edit'), 'Edit');
    },
  );

  testWidgetsWithSemantics(
    'User card merges into one informational unit and is NOT exposed as a '
    'button (no onTap exists today)',
    (tester) async {
      await _pump(tester, _FreshProfileController.new);

      expectNotAButton(
        tester,
        find.text('user-abc123'),
        merged: const ['user-abc123', 'María'],
      );
    },
  );

  testWidgetsWithSemantics('Error body message announces via a live region', (
    tester,
  ) async {
    await _pump(tester, _ErrorProfileController.new);

    expectLiveRegion(tester, 'Something went wrong. Please try again.');
  });

  testWidgetsWithSemantics(
    'NetworkRequired body message announces via a live region',
    (tester) async {
      await _pump(tester, _NetworkRequiredProfileController.new);

      expectLiveRegion(tester, 'Connect to load your profile');
    },
  );

  // NOTE: no automated test drives the edit dialog's save-failure SnackBar
  // (the third liveRegion target: "profile inline edit error"). Opening
  // _showEditDialog's AlertDialog and closing it — via Cancel, via Save with
  // unchanged text, or via Save with a real save-failure — crashes the test.
  //
  // P4b-T3 ran the two harnesses side by side (identical steps, one via
  // pumpApp, one via the old hand-rolled ProviderScope+MaterialApp `_wrap`)
  // and got the SAME failure from both, so the shared harness is not the
  // cause. It also surfaced the FIRST error, which the P3c note did not have:
  //
  //     A TextEditingController was used after being disposed.
  //     #2  ChangeNotifier.addListener
  //     #3  _MergingListenable.addListener
  //     #4  _AnimatedState.didUpdateWidget   (widgets/transitions.dart)
  //
  // "Tried to build dirty widget in the wrong build scope" is the cascade, not
  // the bug. The bug is lifetime: `_showEditDialog` disposes its local
  // TextEditingController in a `finally` that runs the moment
  // `showDialog`'s future completes — i.e. on `Navigator.pop`, while the
  // dialog's EXIT transition is still running. The TextField's
  // InputDecorator re-subscribes its floating-label AnimatedBuilder to a
  // merged listenable that includes that controller during the exit frames,
  // by which time it is disposed.
  //
  // Left alone deliberately (out of scope for T3, and T5 is expected to move
  // this flow onto LumenBottomSheet anyway). The fix, when someone takes it:
  // outlive the route with the controller — dispose it after the transition
  // completes, or hold it in the State of a StatefulWidget that IS the dialog
  // content. See profile_screen.dart's `_showEditDialog` and its TODO(P4b).

  testWidgets('Forward-chevron dingbats are replaced by real Icons', (
    tester,
  ) async {
    await _pump(tester, _FreshProfileController.new);

    expectNoDingbats(tester, screen: 'ProfileScreen');
    // User card + Sign out row.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });
}
