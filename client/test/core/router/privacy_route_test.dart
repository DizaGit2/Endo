// The production route for screen 36 (P4b-T22c): `/more/privacy`, reached two
// ways — a tap on screen 31's Privacy & security row, and a direct deep link.
//
// TDD (RED first). Before this task screen 36 was registered in NO route table
// at all, so `DELETE /me` — which works end to end on the server — was
// reachable by nobody, behind a screen that advertises it.
//
// What this file proves that no other file proves:
//
//  * **R-02 against a CHILD route of a shell branch, in production.** The
//    redirect derives `isKnownLocation` from GoRouter's own matcher
//    (`state.error == null`), never from a hand-maintained literal set — there
//    is no `_knownPaths` symbol anywhere in this package, and registering the
//    `GoRoute` is the whole job. A deep link to `/more/privacy` landing ON
//    screen 36 is what proves it: had the derivation been a literal set, this
//    location would be unknown and the redirect would send it to `/home`.
//  * **R-20 — the affordance and its destination in one commit.** The row on
//    screen 31 and the route it points at are asserted together, so neither
//    half can ship alone: without the route the tap goes nowhere, and without
//    the row the route is another address no user can reach.
//
// The erasure BEHAVIOUR behind screen 36 lives in
// `test/features/settings/privacy_screen_erasure_test.dart`; this file is only
// about reaching the screen and leaving it.

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
import 'package:lumen/features/settings/application/profile_controller.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';
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

/// Pumps the REAL production route table at [initialLocation], wired to the
/// REAL production redirect, with screen 31's read pinned settled.
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
    ],
  );
}

String _location(WidgetTester tester, Type screen) =>
    GoRouterState.of(tester.element(find.byType(screen))).uri.path;

void main() {
  group('the path constant', () {
    test('screen 36 lives INSIDE the More branch — its path is built from '
        'Routes.more, so the branch root and the child cannot drift '
        'apart', () {
      expect(Routes.privacy, startsWith('${Routes.more}/'));
      expect(Routes.privacy, '${Routes.more}/${Routes.privacySegment}');
    });
  });

  group('R-02 — the child route, verified against production', () {
    testWidgets('a direct deep link to /more/privacy is recognised as a KNOWN '
        'location and renders screen 36 — no redirect to Home, and no second '
        'edit anywhere but the route table', (tester) async {
      await _pumpProductionRouter(tester, initialLocation: Routes.privacy);

      expect(find.byType(PrivacyScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets(
      'the More tab stays selected and the bottom nav survives — screen 36 '
      'is a CHILD of the More branch, not a top-level route and not the '
      'unmatched-location fallback',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.privacy);

        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.selectedIndex, 4);
        expect(find.byType(LumenBottomNav), findsOneWidget);
      },
    );
  });

  group('the entry affordance and the route, together (R-20)', () {
    testWidgetsWithSemantics(
      'screen 31 offers a Privacy & security row that announces itself as a '
      'button with that name',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.more);

        expectLabeledButton(
          tester,
          find.bySemanticsLabel(kPrivacyScreenTitle),
          kPrivacyScreenTitle,
        );
      },
    );

    testWidgets('tapping it navigates to screen 36, at /more/privacy', (
      tester,
    ) async {
      await _pumpProductionRouter(tester, initialLocation: Routes.more);
      expect(find.byType(PrivacyScreen), findsNothing);

      await tester.tap(find.text(kPrivacyScreenTitle));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyScreen), findsOneWidget);
      expect(_location(tester, PrivacyScreen), Routes.privacy);
    });

    testWidgets(
      'the back chevron pops back to screen 31 — a pushed route inside the '
      'More branch, not a replacement of it',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.more);
        await tester.tap(find.text(kPrivacyScreenTitle));
        await tester.pumpAndSettle();
        expect(find.byType(PrivacyScreen), findsOneWidget);

        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();

        expect(find.byType(PrivacyScreen), findsNothing);
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(_location(tester, ProfileScreen), Routes.more);
      },
    );
  });
}
