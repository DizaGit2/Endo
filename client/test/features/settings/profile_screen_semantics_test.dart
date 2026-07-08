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
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/auth/token_store.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/cache/hive_boot.dart';
import 'package:lumen/core/error/failure.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Sample data + fakes
// ---------------------------------------------------------------------------

MeResponse _sampleMe() => MeResponse(
  (b) => b
    ..id = 'user-abc123'
    ..displayName = 'María'
    ..locale = 'es'
    ..timezone = 'Europe/Madrid'
    ..onboardingCompleted = true,
);

class _FakeAuthController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.authenticated;
}

class _FreshProfileController extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async => Fresh(_sampleMe());

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

class _MockTokenStore extends Mock implements TokenStore {}

class _MockCacheStore extends Mock implements CacheStore {}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _wrap(ProfileController Function() controller) => ProviderScope(
  overrides: [
    authStatusProvider.overrideWith(() => _FakeAuthController()),
    profileControllerProvider.overrideWith(controller),
  ],
  child: MaterialApp(
    theme: lumenTheme(Brightness.light),
    home: const ProfileScreen(),
  ),
);

void main() {
  testWidgets('Loading state: spinner has a semanticsLabel', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(_PendingProfileController.new));
    await tester.pump();

    expect(find.bySemanticsLabel('Loading profile'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Edit button exposes button semantics with label "Edit"', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(_FreshProfileController.new));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Edit'), findsOneWidget);
    final data = tester.getSemantics(find.bySemanticsLabel('Edit'));
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets(
    'Edit button carries a tap action assistive tech can actually invoke '
    '(excludeSemantics:true on the wrapping Semantics node hides the '
    "GestureDetector's onTap from the tree unless Semantics itself is given "
    'one)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(_FreshProfileController.new));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.bySemanticsLabel('Edit'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason:
            'The button-flagged, labeled node has no tap action — a screen '
            'reader\'s "activate" gesture has nothing to invoke.',
      );

      // Drive it exactly as assistive tech would: dispatch
      // SemanticsAction.tap through the semantics tree (NOT a raw pointer
      // tap on the GestureDetector underneath). This throws a StateError if
      // the node doesn't support the action, which is precisely the bug
      // this test guards against.
      tester.semantics.tap(find.semantics.byLabel('Edit'));
      await tester.pump();

      expect(find.text('Edit display name'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('Sign out row exposes button semantics with label "Sign out"', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(_FreshProfileController.new));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Sign out'), findsOneWidget);
    final data = tester.getSemantics(find.bySemanticsLabel('Sign out'));
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets(
    'Sign out row carries a tap action that actually invokes logout() '
    '(excludeSemantics:true on the wrapping Semantics node hides the '
    "GestureDetector's onTap from the tree unless Semantics itself is given "
    'one)',
    (tester) async {
      final handle = tester.ensureSemantics();

      // Real AuthController.logout() (only build() is faked above) reads
      // TokenStore/CacheStore via ref — stub them with trivial mocks so the
      // async chain resolves deterministically in one microtask hop each,
      // instead of depending on platform-channel/MissingPluginException
      // timing from the real FlutterSecureStorage-backed TokenStore.
      final store = _MockTokenStore();
      final cache = _MockCacheStore();
      when(() => store.readIdToken()).thenAnswer((_) async => null);
      when(() => store.clear()).thenAnswer((_) async {});
      when(() => cache.purge()).thenAnswer((_) async => 0);

      final container = ProviderContainer(
        overrides: [
          authStatusProvider.overrideWith(() => _FakeAuthController()),
          profileControllerProvider.overrideWith(_FreshProfileController.new),
          tokenStoreProvider.overrideWithValue(store),
          cacheStoreProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: lumenTheme(Brightness.light),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.bySemanticsLabel('Sign out'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason:
            'The button-flagged, labeled node has no tap action — a screen '
            'reader\'s "activate" gesture has nothing to invoke.',
      );

      // Drive it for real: dispatch SemanticsAction.tap (assistive tech),
      // not a raw pointer tap, and confirm logout() actually ran by
      // observing the resulting AuthStatus transition.
      tester.semantics.tap(find.semantics.byLabel('Sign out'));
      await tester.pumpAndSettle();

      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
      verify(() => store.clear()).called(1);
      handle.dispose();
    },
  );

  testWidgets(
    'Display name row merges label + value into one unit; Edit stays a '
    'separate button',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(_FreshProfileController.new));
      await tester.pumpAndSettle();

      final rowData = tester.getSemantics(find.text('Display name'));
      expect(rowData.label, contains('Display name'));
      expect(rowData.label, contains('María'));
      expect(rowData.flagsCollection.isButton, isFalse);

      // Edit remains independently actionable within the merged row.
      final editData = tester.getSemantics(find.bySemanticsLabel('Edit'));
      expect(editData.flagsCollection.isButton, isTrue);
      handle.dispose();
    },
  );

  testWidgets(
    'User card merges into one informational unit and is NOT exposed as a '
    'button (no onTap exists today)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(_FreshProfileController.new));
      await tester.pumpAndSettle();

      final data = tester.getSemantics(find.text('user-abc123'));
      expect(data.label, contains('user-abc123'));
      expect(data.label, contains('María'));
      expect(data.flagsCollection.isButton, isFalse);
      handle.dispose();
    },
  );

  testWidgets('Error body message announces via a live region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(_ErrorProfileController.new));
    await tester.pumpAndSettle();

    const message = 'Something went wrong. Please try again.';
    expect(find.text(message), findsOneWidget);
    final data = tester.getSemantics(find.text(message));
    expect(data.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('NetworkRequired body message announces via a live region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(_NetworkRequiredProfileController.new));
    await tester.pumpAndSettle();

    const message = 'Connect to load your profile';
    expect(find.text(message), findsOneWidget);
    final data = tester.getSemantics(find.text(message));
    expect(data.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  // NOTE: no automated test drives the edit dialog's save-failure SnackBar
  // (the third liveRegion target: "profile inline edit error"). Investigated
  // during this task: opening _showEditDialog's AlertDialog and closing it —
  // via Cancel, via Save with unchanged text, or via Save with a real
  // save-failure — ALL crash the widget-test harness with "Tried to build
  // dirty widget in the wrong build scope" / "AnimatedDefaultTextStyle" (the
  // labelText floating-label animation on the dialog's TextField racing the
  // AlertDialog route's teardown). This reproduces on an entirely unmodified
  // Cancel tap, so it is a pre-existing test-environment issue in
  // _showEditDialog's dialog lifecycle, not something introduced by or
  // specific to this task's changes. The production fix (wrapping the
  // SnackBar's Text in `Semantics(liveRegion: true, ...)`) is applied
  // regardless — see profile_screen.dart's `_showEditDialog` — it just isn't
  // covered by an automated interaction test here. Fixing the underlying
  // dialog/test-harness issue is a separate, pre-existing concern.

  testWidgets('Forward-chevron dingbats are replaced by real Icons', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_FreshProfileController.new));
    await tester.pumpAndSettle();

    // User card + Sign out row.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });
}
