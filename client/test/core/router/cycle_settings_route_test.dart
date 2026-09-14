// The production route for screen 32 (P4b-T22a): `/more/cycle`, reached two
// ways — a tap on screen 31's `Cycle settings` row, and a direct deep link.
//
// What this file proves that no other file proves:
//
//  * **R-19's second half, in production.** The ruling says *"T22a then pushes
//    screen 32 inside that branch"*. A route registered top-level would render
//    screen 32 over the whole app and throw the More branch's history away, and
//    every OTHER assertion about it would still pass — so the branch membership
//    is asserted directly, through the selected tab index and the surviving nav
//    bar (T22c's own m-test shape).
//  * **R-20 — the affordance and its destination in one commit.** Screen 32 is
//    the only surface in the app that can set `avgPeriodLengthDays`; a route
//    with no row is that field reachable by nobody.
//  * **R-02 against a second child of the same branch.** The redirect derives
//    `isKnownLocation` from GoRouter's own matcher, so registering the
//    `GoRoute` is the whole job — a deep link landing ON screen 32 is what
//    proves there is no literal path set to update.
//
// The FORM behaviour behind screen 32 lives in
// `test/features/settings/cycle_settings_screen_semantics_test.dart`; this file
// is only about reaching the screen and leaving it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/settings/application/cycle_settings_controller.dart';
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/cycle_settings_screen.dart';
import 'package:lumen/features/settings/presentation/profile_screen.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../../support/harness.dart';

class _SettledProfile extends ProfileController {
  @override
  Future<CacheResult<MeResponse>> build() async =>
      Fresh(meResponseFixture(id: 'user-1'));

  @override
  Future<void> saveDisplayName(String name) async {}
}

/// Screen 32's controller, settled, with no repository behind it — this file's
/// subject is the route, not the read.
class _SettledCycleSettings extends CycleSettingsController {
  @override
  Future<CycleSettingsForm> build() async =>
      CycleSettingsForm.seededFrom(cycleSettingsFixture(avgCycleLengthDays: 29));

  @override
  Future<bool> submit() async => throw StateError('not used by this file');
}

/// Pumps the REAL production route table at [initialLocation], wired to the
/// REAL production redirect, with both screens' reads pinned settled.
Future<void> _pumpProductionRouter(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: lumenRoutes(),
    redirect: (_, state) => lumenRouteRedirect(
      state,
      status: AuthStatus.authenticated,
      onboarding: OnboardingStatus.completed,
    ),
  );
  addTearDown(router.dispose);

  await pumpRouterApp(
    tester,
    routerConfig: router,
    overrides: [
      ...lumenOverrides(cacheStore: emptyCacheStore()),
      profileControllerProvider.overrideWith(_SettledProfile.new),
      cycleSettingsControllerProvider.overrideWith(_SettledCycleSettings.new),
    ],
  );
}

String _location(WidgetTester tester, Type screen) =>
    GoRouterState.of(tester.element(find.byType(screen))).uri.path;

void main() {
  group('the path constant', () {
    test(
      'screen 32 lives INSIDE the More branch — its path is built from '
      'Routes.more, so the branch root and the child cannot drift apart',
      () {
        expect(Routes.cycleSettings, startsWith('${Routes.more}/'));
        expect(
          Routes.cycleSettings,
          '${Routes.more}/${Routes.cycleSettingsSegment}',
        );
      },
    );

    test(
      'it is NOT the Cycle tab — two different places that share a word',
      () {
        expect(Routes.cycleSettings, isNot(Routes.cycle));
        expect(Routes.cycleSettings, isNot(startsWith('${Routes.cycle}/')));
      },
    );
  });

  group('R-02 — the child route, verified against production', () {
    testWidgets(
      'a direct deep link to /more/cycle is recognised as a KNOWN location '
      'and renders screen 32 — no redirect to Home',
      (tester) async {
        await _pumpProductionRouter(
          tester,
          initialLocation: Routes.cycleSettings,
        );

        expect(find.byType(CycleSettingsScreen), findsOneWidget);
        expect(find.byType(DashboardScreen), findsNothing);
      },
    );

    testWidgets(
      'the More tab stays selected and the bottom nav survives — screen 32 '
      'is a CHILD of the More branch, not a top-level route',
      (tester) async {
        await _pumpProductionRouter(
          tester,
          initialLocation: Routes.cycleSettings,
        );

        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.selectedIndex, 4);
        expect(find.byType(LumenBottomNav), findsOneWidget);
      },
    );
  });

  group('the entry affordance and the route, together (R-20)', () {
    testWidgetsWithSemantics(
      'screen 31 offers a Cycle settings row that announces itself as a '
      'button with that name',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.more);

        expectLabeledButton(
          tester,
          find.bySemanticsLabel(kCycleSettingsRowLabel),
          kCycleSettingsRowLabel,
        );
      },
    );

    testWidgets(
      'the row is named `Cycle settings`, not the destination\'s own title — '
      'the bottom nav already announces a destination called `Cycle`, and '
      'two controls with one name is a screen-reader problem',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.more);

        expect(find.text(kCycleSettingsRowLabel), findsOneWidget);
        // The nav destination is the only other `Cycle` on screen 31.
        expect(find.text(kCycleSettingsScreenTitle), findsOneWidget);
      },
    );

    testWidgets('tapping it navigates to screen 32, at /more/cycle', (
      tester,
    ) async {
      await _pumpProductionRouter(tester, initialLocation: Routes.more);
      expect(find.byType(CycleSettingsScreen), findsNothing);

      await tester.tap(find.text(kCycleSettingsRowLabel));
      await tester.pumpAndSettle();

      expect(find.byType(CycleSettingsScreen), findsOneWidget);
      expect(_location(tester, CycleSettingsScreen), Routes.cycleSettings);
    });

    testWidgets(
      'the back chevron pops back to screen 31 — a pushed route inside the '
      'More branch, not a replacement of it',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.more);
        await tester.tap(find.text(kCycleSettingsRowLabel));
        await tester.pumpAndSettle();
        expect(find.byType(CycleSettingsScreen), findsOneWidget);

        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();

        expect(find.byType(CycleSettingsScreen), findsNothing);
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(_location(tester, ProfileScreen), Routes.more);
      },
    );

    testWidgets(
      'the chevron leaves screen 32 for the branch root on a COLD deep link '
      'too — it pins WHERE leaving lands, not that `_leaveCycleSettings`\'s '
      '`canPop` guard is doing the work. It is not: this task mutated the '
      'whole body to a bare `context.pop()` and the suite stayed green, '
      'because a child route of a shell branch has its branch root beneath it '
      'even on a cold link (P4b-T21b\'s probe C). See the function\'s dartdoc.',
      (tester) async {
        await _pumpProductionRouter(
          tester,
          initialLocation: Routes.cycleSettings,
        );

        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();

        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(_location(tester, ProfileScreen), Routes.more);
      },
    );
  });

  group('the two settings leaves are siblings, not a chain', () {
    testWidgets(
      'screen 31 offers BOTH rows, and each has its own chevron — the '
      'Privacy row did not move and the Cycle row did not replace it',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.more);

        expect(find.text(kCycleSettingsRowLabel), findsOneWidget);
        expect(find.text('Privacy & security'), findsOneWidget);
        // User card + cycle settings + privacy + sign out.
        expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
      },
    );
  });
}
