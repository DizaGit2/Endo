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
//     calling `context.pop()` on the root of the stack, which throws;
//   * and BOTH of screen 12's exits surviving the root state that hand-off
//     creates — the chevron (fix round 1) and the post-save exit (fix round
//     2), the second of which is not only a crash: the write has already
//     committed when it throws, so the screen stays up with a live CTA and
//     the next tap POSTs the same all-or-nothing batch again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lumen/api/model/create_symptoms_request.dart';
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
      phaseUnavailableReason: null,
    ),
  );
}

/// Pumps the REAL production route table at [initialLocation], wired to the
/// REAL production redirect.
///
/// [api] is for the two tests that SAVE. Passing one also pins a
/// `cacheStore` — `sessionTodayProvider`, which `SymptomFormController.submit`
/// reads before it POSTs, goes through `cachedRead`, and the real
/// `cacheStoreProvider` throws when it is read un-overridden.
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

/// Scrolls [finder] to the middle of the viewport, then taps it. Screen 12 is
/// several viewports tall and the body-map affordance is its LAST element.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps stop [stop] on the intensity scale keyed [key].
Future<void> _tapStop(WidgetTester tester, Key key, int stop) => _tap(
  tester,
  find.descendant(of: find.byKey(key), matching: find.text('$stop')),
);

/// Stubs the two calls a successful save makes, in order: the R12
/// server-confirmed "today" that `SymptomFormController.submit` reads first,
/// then the batch POST itself.
void _stubSuccessfulSave(MockLumenApiApi api) {
  when(
    () => api.cycleCalendarGet(from: null, to: null),
  ).thenAnswer(apiSuccess(cycleCalendarFixture()));
  when(
    () => api.symptomsPost(
      createSymptomsRequest: any(named: 'createSymptomsRequest'),
    ),
  ).thenAnswer(apiSuccess(createSymptomsResponseFixture(), statusCode: 201));
}

/// Asserts that exactly [count] batches reached the server.
void _expectBatchesPosted(MockLumenApiApi api, int count) {
  verify(
    () => api.symptomsPost(
      createSymptomsRequest: any(named: 'createSymptomsRequest'),
    ),
  ).called(count);
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      CreateSymptomsRequest((b) => b.entries.replace(const [])),
    );
  });

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

      // ONE TAP FURTHER, and it is the tap that matters. `go` REPLACES, so
      // screen 12 has arrived as the ROOT of the stack — an assertion that
      // stopped at the hand-off would be green while the very next thing the
      // user touches throws `GoError: There is nothing to pop`. The hand-off
      // is an answer to R11 only if the screen it hands to is not itself a
      // dead end.
      await _tap(tester, find.byIcon(Icons.chevron_left));

      expect(
        tester.takeException(),
        isNull,
        reason:
            'screen 12\'s chevron is the SAME canPop-guarded shape as screen '
            '13\'s _leave; a bare context.pop() on a replaced root throws',
      );
      expect(
        find.byType(DashboardScreen),
        findsOneWidget,
        reason:
            'with nothing to pop, screen 12 goes to Routes.home — the '
            'authenticated default the redirect already sends every signed-in '
            'user to',
      );
      expect(find.byType(SymptomFormScreen), findsNothing);
    });

    testWidgets('the same dead end on the PRE-EXISTING path is closed too — a '
        'cold link straight to /symptoms/new has nothing under it either, and '
        'threw identically before this guard', (tester) async {
      await _pumpProductionRouter(tester, initialLocation: Routes.symptomsNew);

      await _tap(tester, find.byIcon(Icons.chevron_left));

      expect(tester.takeException(), isNull);
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    // The positive control for the same guard — that it did NOT flatten the
    // ordinary path into a `go` — lives where the pushed stack already exists:
    // `symptom_form_screen_semantics_test.dart`'s "the back affordance pops
    // without saving", whose host route is `/host` and whose router registers
    // no `/home` at all, so a `go(Routes.home)` there could not land on it.

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
  // The POST-SAVE exit on the same rootless stack (fix round 2)
  // -------------------------------------------------------------------------
  //
  // The chevron is not screen 12's only exit, and it is not the primary one.
  // `Save` popped bare until now, on a stack where `pop` throws — and unlike
  // the chevron, that exit runs AFTER the write has committed. A throw there
  // leaves the screen mounted with every selection intact and `submitting`
  // back to `false`, so the CTA is live again and the next tap POSTs the
  // same all-or-nothing batch a second time. The server has no idempotency
  // key for this endpoint and the client has no re-submit guard, so a count
  // of 2 here is a duplicate day of symptoms, not a retried request.
  //
  // Which is why these tests assert the COUNT and not merely that nothing
  // threw: `takeException(), isNull` alone would go green the day someone
  // swallowed the GoError, with the duplicate still one tap away.

  group('the post-save exit on a rootless stack', () {
    testWidgets('a successful save LEAVES screen 12 after the cold-link '
        'hand-off, and the batch reaches the server exactly ONCE', (
      tester,
    ) async {
      final api = MockLumenApiApi();
      _stubSuccessfulSave(api);

      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.symptomsBodyMap,
        api: api,
      );

      // The state this task deliberately creates: `Done` `go`es, and `go`
      // REPLACES, so screen 12 arrives as the ROOT of the stack.
      await _tap(tester, find.text(kBodyMapDoneLabel));
      expect(find.byType(SymptomFormScreen), findsOneWidget);

      await _tapStop(tester, kSymptomPainIntensityKey, 4);
      await _tap(tester, find.text(kSymptomFormSaveLabel));

      expect(
        tester.takeException(),
        isNull,
        reason:
            'a bare context.pop() here throws GoError: There is nothing to '
            'pop — with the batch already written',
      );

      // The second tap, ATTEMPTED rather than assumed, and asserted BEFORE
      // where the user ended up. On the fixed build the CTA is not in the
      // tree and this is a no-op; on the broken build it is the tap a user
      // makes when the app appears to have done nothing, and it takes the
      // count to 2. Ordered first so the failure lands on the NUMBER the
      // defect is about: a build that merely SWALLOWED the GoError would
      // clear the assertion above and still duplicate the batch here.
      final ctaAfterSave = find.text(kSymptomFormSaveLabel);
      if (ctaAfterSave.evaluate().isNotEmpty) {
        await _tap(tester, ctaAfterSave);
      }
      _expectBatchesPosted(api, 1);

      expect(
        find.byType(SymptomFormScreen),
        findsNothing,
        reason:
            'leaving is what closes the duplicate: a screen 12 still on '
            'screen is a second Save away from a second batch',
      );
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('the same is true of the PRE-EXISTING cold link straight to '
        '/symptoms/new — it threw identically, and duplicated identically', (
      tester,
    ) async {
      final api = MockLumenApiApi();
      _stubSuccessfulSave(api);

      await _pumpProductionRouter(
        tester,
        initialLocation: Routes.symptomsNew,
        api: api,
      );

      await _tapStop(tester, kSymptomPainIntensityKey, 4);
      await _tap(tester, find.text(kSymptomFormSaveLabel));

      expect(tester.takeException(), isNull);

      final ctaAfterSave = find.text(kSymptomFormSaveLabel);
      if (ctaAfterSave.evaluate().isNotEmpty) {
        await _tap(tester, ctaAfterSave);
      }
      _expectBatchesPosted(api, 1);

      expect(find.byType(SymptomFormScreen), findsNothing);
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    // The POSITIVE CONTROL for this exit — that the guard did not flatten an
    // ordinary PUSHED save into a `go(Routes.home)` — is
    // `symptom_form_screen_semantics_test.dart`'s "a successful save pops the
    // screen", whose host router registers no `Routes.home` at all.
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
