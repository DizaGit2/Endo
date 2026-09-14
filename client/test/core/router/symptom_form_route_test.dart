// The production route for screen 12 (P4b-T20b): `/symptoms/new`, and the
// TWO affordances that reach it.
//
// TDD (RED first). R-20 — an affordance ships in the same commit as its
// destination — is what this file exists to prove, against the REAL
// production route table rather than a probe of one:
//
//   * `/symptoms/new` is a KNOWN location (no second edit anywhere:
//     `lumenRouteRedirect` derives that from GoRouter's own matcher), and it
//     renders OUTSIDE the tab shell — no bottom nav;
//   * A2 — the dashboard's Symptom quick-log tile PUSHES it, so popping
//     returns to the Home branch rather than replacing it;
//   * A1 — screen 9's "+ Add details" SAVES THE CHECK-IN FIRST (R-13) and
//     only then opens screen 12 — and does NOT navigate when that save
//     fails, because leaving would silently discard the check-in the user
//     just entered.
//
// The plan's third affordance (screen 11's "Edit") is deliberately absent:
// T19 cut `PUT`, so screen 12 is create-only, and an Edit control opening an
// empty create form would be worse than the inert control R-10 removes,
// because it looks like it worked. Booked for P6.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/quick_checkin_request.dart';
import 'package:lumen/api/model/quick_checkin_response.dart';
import 'package:lumen/core/auth/auth_controller.dart';
import 'package:lumen/core/cache/cached_query.dart';
import 'package:lumen/core/router/app_router.dart';
import 'package:lumen/core/router/routes.dart';
import 'package:lumen/core/time/greeting_clock.dart';
import 'package:lumen/features/checkin/presentation/quick_checkin_screen.dart';
import 'package:lumen/features/home/application/dashboard_controller.dart';
import 'package:lumen/features/home/presentation/dashboard_screen.dart';
import 'package:lumen/features/onboarding/application/onboarding_flow_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_status_controller.dart';
import 'package:lumen/features/onboarding/application/onboarding_step.dart';
import 'package:lumen/features/symptoms/presentation/symptom_form_screen.dart';
import 'package:lumen/shared/widgets/lumen_bottom_sheet.dart';
import 'package:lumen/shared/widgets/lumen_error_banner.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';
import 'package:mocktail/mocktail.dart';

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
      phaseAvailable: null,
      phaseUnavailableReason: null,
    ),
  );
}

/// Pumps the REAL production route table at [initialLocation], wired to the
/// REAL production redirect.
Future<void> _pumpProductionRouter(
  WidgetTester tester, {
  required String initialLocation,
  MockLumenApiApi? api,
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
      ...lumenOverrides(
        api: api,
        cacheStore: api == null ? null : emptyCacheStore(),
      ),
      onboardingFlowControllerProvider.overrideWith(_SettledOnboarding.new),
      dashboardControllerProvider.overrideWith(_FreshDashboard.new),
      greetingTimeOfDayProvider.overrideWithValue('Good morning'),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
    registerFallbackValue(QuickCheckinRequest((b) => b..pain = 0));
  });

  // -------------------------------------------------------------------------
  // The route itself
  // -------------------------------------------------------------------------

  group('/symptoms/new', () {
    testWidgets('is a KNOWN location — a direct deep link lands on screen 12 '
        'rather than being swallowed by the unknown-location fallback', (
      tester,
    ) async {
      await _pumpProductionRouter(tester, initialLocation: Routes.symptomsNew);

      expect(find.byType(SymptomFormScreen), findsOneWidget);
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
      await _pumpProductionRouter(tester, initialLocation: Routes.symptomsNew);

      expect(
        find.byType(LumenBottomNav),
        findsNothing,
        reason:
            'the mockup draws no bottom nav: this is a task flow you enter '
            'and leave, the same shape /onboarding and /account have',
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
  // A2 — the dashboard's Symptom quick-log tile (R-20)
  // -------------------------------------------------------------------------

  group('A2 — the dashboard Symptom tile', () {
    testWidgets('opens screen 12', (tester) async {
      await _pumpProductionRouter(tester, initialLocation: Routes.home);

      await tester.tap(find.text('Symptom'));
      await tester.pumpAndSettle();

      expect(find.byType(SymptomFormScreen), findsOneWidget);
    });

    testWidgets('PUSHES it — popping returns to the Home branch, which is '
        'still there underneath', (tester) async {
      await _pumpProductionRouter(tester, initialLocation: Routes.home);

      await tester.tap(find.text('Symptom'));
      await tester.pumpAndSettle();
      expect(find.byType(SymptomFormScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(SymptomFormScreen), findsNothing);
      expect(
        find.byType(DashboardScreen),
        findsOneWidget,
        reason:
            'a `go` rather than a `push` would have replaced the branch, so '
            'there would be nothing to come back to',
      );
    });
  });

  // -------------------------------------------------------------------------
  // A1 — screen 9's "+ Add details" (R-13 + R-20)
  // -------------------------------------------------------------------------

  group('A1 — screen 9\'s "+ Add details"', () {
    late MockLumenApiApi api;

    setUp(() {
      api = MockLumenApiApi();
      when(
        () => api.cycleCalendarGet(from: null, to: null),
      ).thenAnswer(apiSuccess(cycleCalendarFixture()));
    });

    /// Opens the dashboard, taps the Mood tile to raise screen 9's sheet, and
    /// touches the pain scale so there is a check-in to save.
    Future<void> openSheetWithAnAnswer(WidgetTester tester) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.home,
        api: api,
      );

      await tester.tap(find.text('Mood'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickCheckinScreen), findsOneWidget);

      await tester.tap(find.text('4'));
      await tester.pump();
    }

    testWidgets('saves the check-in FIRST, then opens screen 12 with an empty '
        'form', (tester) async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(apiSuccess(quickCheckinResponseFixture(pain: 4)));

      await openSheetWithAnAnswer(tester);

      await tester.tap(find.text(kQuickCheckinAddDetailsLabel));
      await tester.pumpAndSettle();

      verify(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).called(1);
      expect(find.byType(SymptomFormScreen), findsOneWidget);
      expect(
        find.byType(LumenBottomSheet),
        findsNothing,
        reason:
            'the sheet must be dismissed before screen 12 is pushed, or it '
            'stays live underneath a full-screen route',
      );
    });

    testWidgets('does NOT navigate when the save FAILS — the user stays on '
        'screen 9 with the banner and the same-button retry', (tester) async {
      when(
        () => api.checkinQuickPost(
          quickCheckinRequest: any(named: 'quickCheckinRequest'),
        ),
      ).thenAnswer(
        apiValidationProblem<QuickCheckinResponse>(
          fields: <String, List<String>>{
            'request': <String>['at least one of pain or mood is required'],
          },
        ),
      );

      await openSheetWithAnAnswer(tester);

      await tester.tap(find.text(kQuickCheckinAddDetailsLabel));
      await tester.pumpAndSettle();

      expect(
        find.byType(SymptomFormScreen),
        findsNothing,
        reason:
            'navigating away here would silently discard the check-in the '
            'user just entered — the endpoint has no clear affordance and '
            'nothing would say the answer was lost',
      );
      expect(find.byType(QuickCheckinScreen), findsOneWidget);
      expect(find.byType(LumenErrorBanner), findsOneWidget);
      expect(find.text(kQuickCheckinRetryLabel), findsOneWidget);
    });

    testWidgets('is inert until there is something to save — the same gate '
        'the Save CTA is under', (tester) async {
      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.home,
        api: api,
      );

      await tester.tap(find.text('Mood'));
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text(kQuickCheckinAddDetailsLabel),
          matching: find.byType(TextButton),
        ),
      );
      expect(
        button.onPressed,
        isNull,
        reason:
            '"+ Add details" always SAVES first (R-13), so it offers itself '
            'only when there is a check-in to save; the dashboard\'s own '
            'Symptom tile is the route to screen 12 with no check-in',
      );
    });
  });
}
