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
import 'package:lumen/features/settings/presentation/privacy_screen.dart';
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
    // A `Failure` — what `MeRepository.getMe` actually throws. Until P4b-T26
    // this threw a plain `StateError`, because riverpod's `defaultRetry`
    // skips `error is Error` but retries a `Failure` behind
    // `AsyncLoading(retrying: true)`, and the error body never rendered. The
    // app-wide `lumenRetry` is what lets the honest shape work here.
    throw const TlsFailure();
  }
}

class _NetworkRequiredProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async =>
      const NetworkRequired<MeResponse>(NetworkFailure());
}

/// Loads fine; the write fails. The screen must keep the profile on screen and
/// tell the user to retry (online-only: nothing is queued).
class _SaveFailsProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async => Fresh(meResponseFixture());

  @override
  Future<void> saveDisplayName(String name) async {
    throw const ServerFailure();
  }
}

/// Records what the screen actually asked to be saved.
class _RecordingProfileController extends ProfileController {
  final saved = <String>[];

  @override
  Future<CacheResult<MeResponse>> build() async => Fresh(meResponseFixture());

  @override
  Future<void> saveDisplayName(String name) async => saved.add(name);
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

  // -------------------------------------------------------------------------
  // The edit dialog (P4b-T5 — previously untestable, see below)
  // -------------------------------------------------------------------------
  //
  // These four tests were impossible before T5. Opening `_showEditDialog`'s
  // AlertDialog and closing it — via Cancel, or via Save — crashed the harness:
  //
  //     A TextEditingController was used after being disposed.
  //     #2  ChangeNotifier.addListener
  //     #3  _MergingListenable.addListener
  //     #4  _AnimatedState.didUpdateWidget   (widgets/transitions.dart)
  //
  // The cause was lifetime, not the harness (P4b-T3 reproduced it identically
  // under the old hand-rolled `_wrap`): the controller was a local of
  // `_showEditDialog`, disposed in a `finally` that runs the moment
  // `showDialog`'s future completes — i.e. on `Navigator.pop`, while the
  // route's ~150 ms exit transition is still running and the TextField is
  // still rebuilding against it. T5 moved the controller into the State of the
  // dialog's own StatefulWidget, so it now outlives the transition.
  //
  // The save-failure SnackBar is the point of the exercise: it is a liveRegion
  // accessibility affordance that had ZERO coverage, because the only route to
  // it was through this dialog.

  testWidgetsWithSemantics('A failed save announces itself via a live region', (
    tester,
  ) async {
    await _pump(tester, _SaveFailsProfileController.new);

    await tester.tap(find.bySemanticsLabel('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit display name'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Maya Nueva');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expectLiveRegion(tester, 'Could not save your changes. Please try again.');
  });

  testWidgets('Saving a new name calls the controller with the trimmed text', (
    tester,
  ) async {
    final controller = _RecordingProfileController();
    await _pump(tester, () => controller);

    await tester.tap(find.bySemanticsLabel('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Maya Nueva  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(controller.saved, <String>['Maya Nueva']);
    // A successful save says nothing — the SnackBar is a failure affordance.
    expect(
      find.text('Could not save your changes. Please try again.'),
      findsNothing,
    );
  });

  testWidgets('Cancel closes the dialog without saving', (tester) async {
    // The plain-Cancel case is the one that reproduced the teardown crash on
    // otherwise unmodified code.
    final controller = _RecordingProfileController();
    await _pump(tester, () => controller);

    await tester.tap(find.bySemanticsLabel('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Discarded');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Edit display name'), findsNothing);
    expect(controller.saved, isEmpty);
  });

  testWidgets('Saving a blank name does not write it', (tester) async {
    final controller = _RecordingProfileController();
    await _pump(tester, () => controller);

    await tester.tap(find.bySemanticsLabel('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(controller.saved, isEmpty);
  });

  testWidgets('Forward-chevron dingbats are replaced by real Icons', (
    tester,
  ) async {
    await _pump(tester, _FreshProfileController.new);

    expectNoDingbats(tester, screen: 'ProfileScreen');
    // User card + Cycle settings row (P4b-T22a) + Privacy & security row
    // (P4b-T22c) + Sign out row.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
  });

  testWidgetsWithSemantics(
    'the Privacy & security row is a real button with an accessible name — '
    'it ships in the same commit as the route behind it (R-20, P4b-T22c), so '
    'unlike the user card above it there IS something to activate',
    (tester) async {
      await _pump(tester, _FreshProfileController.new);

      expectLabeledButton(
        tester,
        find.bySemanticsLabel(kPrivacyScreenTitle),
        kPrivacyScreenTitle,
      );
    },
  );

  testWidgets(
    'no decorative back chevron — fix round 1, M6 (P4b-T17): this screen '
    'is the More branch\'s ROOT since R-19, and a chevron implying "back" '
    'promises a destination that does not exist for a root',
    (tester) async {
      await _pump(tester, _FreshProfileController.new);

      expect(find.byIcon(Icons.chevron_left), findsNothing);
    },
  );
}
