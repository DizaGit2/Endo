// ---------------------------------------------------------------------------
// harness.dart — one import for the Lumen test harness (P4b-T3)
// ---------------------------------------------------------------------------
//
//   import '../../support/harness.dart';
//
// gives you:
//
//   pumpApp / pumpRouterApp / pumpLumenApp   mounting a widget test
//   goldenApp / goldenTestLightAndDark        the 390x844 frame + light/dark
//   onboardingStepHost                        the shell frame around one step
//   lumenOverrides / FakeAuthController       the common provider scope
//   MockLumenApiApi + the four archetypes     success / network / 400 / pending
//   meResponseFixture, …                      DTO builders
//   testWidgetsWithSemantics + the matchers   the accessibility rules
//   expectRetryReissuesOneRequest             the designed-error-state trap
//
// The screen registry (`test/support/screen_registry.dart`) is deliberately
// NOT exported: it is enforcement machinery for `test/shared/
// screen_registry_test.dart`, not something a screen test should reach for.

export 'a11y_guard.dart';
export 'fake_api.dart';
export 'fixtures.dart';
export 'golden_app.dart';
export 'onboarding_step_host.dart';
export 'provider_overrides.dart';
export 'pump_app.dart';
export 'retry_trap.dart';
