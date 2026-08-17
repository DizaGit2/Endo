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
import 'package:lumen/core/theme/lumen_theme.dart';

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

/// Pumps [home] inside the real app theme and a Riverpod scope built from
/// [overrides].
///
/// [settle] pumps until no frames are scheduled. Pass `settle: false` for any
/// tree containing an indeterminate `CircularProgressIndicator` (it animates
/// forever, so "settle" never arrives) and drive the frames yourself.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required Widget home,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
  ProviderContainer? container,
  bool settle = true,
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
}) {
  return _pumpScoped(
    tester,
    const LumenApp(),
    overrides: overrides,
    container: container,
    settle: settle,
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
Future<ProviderContainer> _pumpScoped(
  WidgetTester tester,
  Widget app, {
  required List<Override> overrides,
  required ProviderContainer? container,
  required bool settle,
}) async {
  if (container != null && overrides.isNotEmpty) {
    throw ArgumentError(
      'Pass either `container` or `overrides`, not both — overrides given '
      'alongside a container would be silently ignored, which is exactly the '
      'kind of test that passes for the wrong reason.',
    );
  }

  final scope = container ?? ProviderContainer(overrides: overrides);
  if (container == null) {
    addTearDown(scope.dispose);
  }

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
