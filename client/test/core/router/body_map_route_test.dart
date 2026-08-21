// The production route for screen 13 (P4b-T21b): `/symptoms/body-map`, and
// the ONE affordance that reaches it.
//
// TDD (RED first). R-20 — an affordance ships in the same commit as its
// destination — is what this file exists to prove, against the REAL production
// route table rather than a probe of one:
//
//   * `/symptoms/body-map` is a KNOWN location (no second edit anywhere:
//     `lumenRouteRedirect` derives that from GoRouter's own matcher), and it
//     renders OUTSIDE the tab shell — no bottom nav, exactly like
//     `/symptoms/new`;
//   * screen 12's body-map affordance PUSHES it, so popping returns to screen
//     12 with every answer still on it — the deciding property, since a `go`
//     would tear the form down and take the user's unsent selections with it;
//   * the DEEP-LINK case (R11): a cold link to `/symptoms/body-map` has
//     nothing to pop back to, so `Done` goes to `/symptoms/new` rather than
//     calling `context.pop()` on the root of the stack, which throws.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/symptoms/application/symptom_form.dart';
import 'package:lumen/features/symptoms/presentation/body_map_screen.dart';
import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

import '../../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _SettledOnboarding extends OnboardingFlowController {
  @override
  AsyncValue<OnboardingFlow> build() => AsyncValue<OnboardingFlow>.data(
    OnboardingFlow(step: OnboardingStep.cycle, state: onboardingStateFixture()),
  );
}

class _FreshDashboard extends DashboardController {
  @override
  Future<CacheResult<DashboardView>> build() async => Fresh(
    DashboardView(
      today: DateTime(2026, 4, 20),
      displayName: 'Maya',
      todayPain: null,
      todayMood: null,
      yesterdayPain: null,
      phaseUnavailableReason: null,
    ),
  );
}

/// Pumps the REAL production route table at [initialLocation], wired to the
/// REAL production redirect.
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
    overrides: <Override>[
      ...lumenOverrides(),
      onboardingFlowControllerProvider.overrideWith(_SettledOnboarding.new),
      dashboardControllerProvider.overrideWith(_FreshDashboard.new),
      greetingTimeOfDayProvider.overrideWithValue('Good morning'),
    ],
  );
}

/// Scrolls [finder] to the middle of the viewport, then taps it. Screen 12 is
/// several viewports tall and the body-map affordance is its LAST element.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // The route itself
  // -------------------------------------------------------------------------

  group('/symptoms/body-map', () {
    testWidgets('is a KNOWN location — a direct deep link lands on screen 13 '
        'rather than being swallowed by the unknown-location fallback', (
      tester,
    ) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.symptomsBodyMap,
      );

      expect(find.byType(BodyMapScreen), findsOneWidget);
      expect(
        find.byType(DashboardScreen),
        findsNothing,
        reason:
            'an UNREGISTERED path would redirect to Routes.home — that is '
            'what makes this assertion able to fail',
      );
    });

    testWidgets('renders OUTSIDE the tab shell — no bottom nav', (
      tester,
    ) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.symptomsBodyMap,
      );

      expect(
        find.byType(LumenBottomNav),
        findsNothing,
        reason:
            'the mockup draws no bottom nav: this is a task flow you enter '
            'and leave, the same shape /symptoms/new has',
      );
    });

    testWidgets(
      'positive control: the shell DOES render a bottom nav on a tab route',
      (tester) async {
        await _pumpProductionRouter(tester, initialLocation: Routes.home);

        expect(
          find.byType(LumenBottomNav),
          findsOneWidget,
          reason:
              'if this finds nothing, the "no bottom nav" assertion above '
              'proves nothing — this is what makes it a real guard',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // R11 — the deep-link case, ruled in code rather than by accident
  // -------------------------------------------------------------------------

  group('the deep-link case (R11)', () {
    testWidgets('Done goes to /symptoms/new when there is nothing to pop — a '
        'cold link has no screen 12 underneath it, and context.pop() on the '
        'root of the stack throws', (tester) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.symptomsBodyMap,
      );

      await _tap(tester, find.text(kBodyMapDoneLabel));

      expect(find.byType(SymptomFormScreen), findsOneWidget);
      expect(find.byType(BodyMapScreen), findsNothing);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'a bare context.pop() here asserts "there is nothing to pop" and '
            'the screen would be a dead end',
      );
    });

    testWidgets('a point placed on a COLD LINK survives the hand-off to '
        'screen 12 — the form is autoDispose and there is no screen 12 '
        'underneath a deep link to hold it open', (tester) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.symptomsBodyMap,
      );

      await _tap(tester, find.text('Pelvis'));
      await _tap(
        tester,
        find.descendant(
          of: find.byKey(bodyMapIntensityKey('pelvis')),
          matching: find.text('5'),
        ),
      );
      await _tap(tester, find.text(kBodyMapDoneLabel));

      // Screen 12 renders the empty-batch block reason when it has NOTHING —
      // no pain row, no related chip and no body-map point. Its absence, and
      // a live Save CTA, is how a body-map point makes itself visible on a
      // screen that never draws the points themselves.
      expect(find.byType(SymptomFormScreen), findsOneWidget);
      expect(find.text(kSymptomNothingSelectedMessage), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, kSymptomFormSaveLabel),
            )
            .onPressed,
        isNotNull,
        reason:
            'the point reached SymptomForm.bodyMapPoints and stayed there '
            'across the go() — a form that had autoDisposed between the two '
            'screens would rebuild empty and block the save',
      );
    });
  });

  // -------------------------------------------------------------------------
  // R-20 — screen 12's affordance, against the real table
  // -------------------------------------------------------------------------

  group('screen 12\'s body-map affordance', () {
    testWidgets('opens screen 13', (tester) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.symptomsNew,
      );

      await _tap(tester, find.byKey(kSymptomBodyMapKey));

      expect(find.byType(BodyMapScreen), findsOneWidget);
    });

    testWidgets('PUSHES it — popping returns to screen 12, which is still '
        'there underneath with its form intact', (tester) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.symptomsNew,
      );

      await _tap(tester, find.byKey(kSymptomBodyMapKey));
      expect(find.byType(BodyMapScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(BodyMapScreen), findsNothing);
      expect(
        find.byType(SymptomFormScreen),
        findsOneWidget,
        reason:
            'a `go` would have REPLACED screen 12, tearing down the '
            'autoDispose form and taking every unsent selection with it',
      );
    });
  });
}
