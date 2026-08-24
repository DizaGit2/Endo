// ---------------------------------------------------------------------------
// pump_app.dart — the ONE way a Lumen widget test mounts something (P4b-T3)
// ---------------------------------------------------------------------------
//
// Before this file every test file hand-rolled its own `_wrap()` / `_buildApp()`
// / `_pumpApp()`. Thirteen P4b screens x ~3 test files each would have copied
// that ~40 more times, and each copy is a place where the theme, the provider
// scope or the settle strategy can quietly drift from the others.
//
// Three entry points, one per thing a test can mount:
//
//   * [pumpApp]       — a single screen under the real app theme. The default.
//   * [pumpRouterApp] — a route table under a `MaterialApp.router` (router and
//                       shell tests, which have no single "home" widget).
//   * [pumpLumenApp]  — the real [LumenApp], for tests whose subject IS the
//                       app wiring (splash gate, redirect end-to-end).
//
// All three return the [ProviderContainer] the tree is mounted against, so a
// test that needs to read provider state back does not have to switch to a
// different harness shape (the old `UncontrolledProviderScope` variant).
//
// Golden tests do NOT use this file — a golden has no `WidgetTester` at build
// time. See `golden_app.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app.dart';
import 'package:lumen/core/error/retry_policy.dart';
import 'package:lumen/core/theme/lumen_theme.dart';

import 'golden_app.dart';

// ---------------------------------------------------------------------------
// The surface
// ---------------------------------------------------------------------------

/// The logical surface every entry point here mounts against, and the same one
/// every golden is drawn at (P4b-T5d).
///
/// `flutter_test`'s default is 800x600 — a landscape desktop window. Under it
/// the shell's CTA sits below the fold, so a test that taps "Continue" taps
/// nothing and a `RenderFlex` that is fine on a phone can overflow; before this
/// existed each whole-shell test had to call `setSurfaceSize` itself, and
/// exactly one file in the repo did.
///
/// Built from [kGoldenWidth] and [kGoldenHeight] rather than repeating their
/// numbers, so "the widget tests run at the golden surface" is a fact the
/// compiler keeps rather than a comment that can rot.
const Size kTestSurfaceSize = Size(kGoldenWidth, kGoldenHeight);

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

/// Pumps [home] inside the real app theme and a Riverpod scope built from
/// [overrides].
///
/// [settle] pumps until no frames are scheduled. Pass `settle: false` for any
/// tree containing an indeterminate `CircularProgressIndicator` (it animates
/// forever, so "settle" never arrives) and drive the frames yourself.
///
/// [surfaceSize] defaults to [kTestSurfaceSize] and is restored in a tearDown;
/// pass another only for a test whose subject IS the layout at some other
/// size.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required Widget home,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
  ProviderContainer? container,
  bool settle = true,
  Size surfaceSize = kTestSurfaceSize,
}) {
  return _pumpScoped(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lumenTheme(brightness),
      home: home,
    ),
    overrides: overrides,
    container: container,
    settle: settle,
    surfaceSize: surfaceSize,
  );
}

/// Pumps a [routerConfig] (a `GoRouter`) inside the real app theme.
///
/// Used by tests whose subject is the route table or the shell chrome, where
/// there is no single `home` widget to hand to [pumpApp].
Future<ProviderContainer> pumpRouterApp(
  WidgetTester tester, {
  required RouterConfig<Object> routerConfig,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
  ProviderContainer? container,
  bool settle = true,
  Size surfaceSize = kTestSurfaceSize,
}) {
  return _pumpScoped(
    tester,
    MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: lumenTheme(brightness),
      routerConfig: routerConfig,
    ),
    overrides: overrides,
    container: container,
    settle: settle,
    surfaceSize: surfaceSize,
  );
}

/// Pumps the real [LumenApp] — its own router, its own theme.
///
/// Only for tests whose subject is the app wiring itself. A screen test should
/// use [pumpApp]: mounting the whole app drags the redirect, the gate read and
/// the splash animation into a test that is about one screen's widgets.
Future<ProviderContainer> pumpLumenApp(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  ProviderContainer? container,
  bool settle = true,
  Size surfaceSize = kTestSurfaceSize,
}) {
  return _pumpScoped(
    tester,
    const LumenApp(),
    overrides: overrides,
    container: container,
    settle: settle,
    surfaceSize: surfaceSize,
  );
}

// ---------------------------------------------------------------------------
// Core
// ---------------------------------------------------------------------------

/// Mounts [app] under a Riverpod container and pumps it.
///
/// The container is always explicit (`UncontrolledProviderScope`) rather than
/// owned by a `ProviderScope`, which is what lets every entry point return it.
/// A container created here is disposed by an `addTearDown`; a container passed
/// in belongs to the caller, who must dispose it.
///
/// The surface is set BEFORE the first pump — setting it afterwards lays the
/// tree out twice and hides an overflow that only the first layout would have
/// reported — and restored by a tearDown, because the binding is shared across
/// the tests in a file.
Future<ProviderContainer> _pumpScoped(
  WidgetTester tester,
  Widget app, {
  required List<Override> overrides,
  required ProviderContainer? container,
  required bool settle,
  required Size surfaceSize,
}) async {
  if (container != null && overrides.isNotEmpty) {
    throw ArgumentError(
      'Pass either `container` or `overrides`, not both — overrides given '
      'alongside a container would be silently ignored, which is exactly the '
      'kind of test that passes for the wrong reason.',
    );
  }

  // `retry: lumenRetry` — the SAME function `LumenRootScope` gives the
  // production container (P4b-T26). Without it a widget test runs on
  // riverpod's `defaultRetry`, which retries a thrown `Failure` ten times
  // while publishing `AsyncLoading(retrying: true)`; a screen test of a failed
  // read would then see a spinner the real app does not show, and a test that
  // wants the error body would have to throw an `Error` instead of the
  // `Failure` production throws — which is exactly what two files in this repo
  // had to do before this existed.
  //
  // **Both branches, not one.** The first cut of this applied the policy only
  // where the harness built the container, which left `container:` as an
  // unguarded way back to `defaultRetry` — a policy applied on one of two
  // branches is the same species of hole as a guard that cannot fail, and it
  // is the exact door this defect would have walked back through. A caller's
  // own container is checked rather than silently corrected, because
  // `ProviderContainer.retry` is final: there is no way to fix it here, and
  // quietly accepting it would put the difference somewhere nobody looks.
  if (container != null && !identical(container.retry, lumenRetry)) {
    throw ArgumentError(
      'The container passed here does not carry `retry: lumenRetry` '
      '(lib/core/error/retry_policy.dart) — the policy LumenRootScope gives '
      'the production container. Under riverpod 3.3.2\'s defaultRetry a build '
      'that threw a Failure is rebuilt ten times over ~38 s while publishing '
      'AsyncLoading(retrying: true), so this tree would show a spinner where '
      'the real app shows its error body. Build the container as '
      '`ProviderContainer(retry: lumenRetry, overrides: [...])`.',
    );
  }

  final scope =
      container ?? ProviderContainer(retry: lumenRetry, overrides: overrides);
  if (container == null) {
    addTearDown(scope.dispose);
  }

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(container: scope, child: app),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }

  return scope;
}
