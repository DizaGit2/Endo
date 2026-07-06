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
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';

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
