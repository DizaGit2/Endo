// ---------------------------------------------------------------------------
// fixtures.dart — DTO builders (P4b-T3)
// ---------------------------------------------------------------------------
//
// `built_value` DTOs are verbose to construct and every pre-T3 test file that
// needed one hand-built it inline — five separate copies of the same
// `MeResponse`, each with its own placeholder id, drifting independently.
//
// Rules for adding to this file:
//   * one builder per response, named `<dto>Fixture`;
//   * every argument optional with a sane default, so a test overrides only the
//     field it is actually about;
//   * defaults must be VALID — a fixture is also the reference for what the
//     contract permits;
//   * the dart-dio generator emits EVERY property as nullable (Swashbuckle
//     writes no `required` array), so a fixture that leaves a field null is a
//     legitimate shape the client must survive. Screens must null-check;
//     fixtures must be able to produce the null.
//
// Later P4b tasks add their own screen's DTOs here rather than inline.

import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';

/// `GET /me`. The shipped default is a fully-onboarded Spanish-locale user.
MeResponse meResponseFixture({
  String? id = 'user-abc123',
  String? displayName = 'María',
  String? locale = 'es',
  String? timezone = 'Europe/Madrid',
  bool? onboardingCompleted = true,
}) {
  return MeResponse(
    (b) => b
      ..id = id
      ..displayName = displayName
      ..locale = locale
      ..timezone = timezone
      ..onboardingCompleted = onboardingCompleted,
  );
}

/// `GET /onboarding/state`. The default is a flow with nothing filled in yet.
///
/// The list-valued properties (`goals`, `hormones`, `notifications`,
/// `missingMandatorySteps`) are deliberately left unset: they are nullable in
/// the generated client, and a screen that force-unwraps them is broken
/// against the real contract.
OnboardingStateResponse onboardingStateFixture({
  bool? completed = false,
  bool? baselineProvided = false,
  bool? cycleProvided = false,
  bool? goalsProvided = false,
  bool? hormonesProvided = false,
  bool? notificationsProvided = false,
  Date? lastPeriodStart,
  DateTime? completedAt,
}) {
  return OnboardingStateResponse(
    (b) => b
      ..completed = completed
      ..completedAt = completedAt
      ..baselineProvided = baselineProvided
      ..cycleProvided = cycleProvided
      ..goalsProvided = goalsProvided
      ..hormonesProvided = hormonesProvided
      ..notificationsProvided = notificationsProvided
      ..lastPeriodStart = lastPeriodStart,
  );
}

/// `POST /onboarding/complete`. The default is a first, successful completion.
OnboardingCompleteResponse onboardingCompleteFixture({
  DateTime? completedAt,
  bool? alreadyCompleted = false,
}) {
  return OnboardingCompleteResponse(
    (b) => b
      ..completedAt = completedAt ?? DateTime.utc(2026, 4, 6, 9, 30)
      ..alreadyCompleted = alreadyCompleted,
  );
}
