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

import 'package:built_collection/built_collection.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
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

/// `GET /settings/cycle`. The default is the row-less answer the server gives a
/// user who has never saved: the T6 defaults with `createdAt`/`updatedAt` null,
/// which is the ONLY signal that no row exists.
CycleSettingsResponse cycleSettingsFixture({
  int? avgCycleLengthDays = 28,
  int? avgPeriodLengthDays,
  String? regularity = 'somewhat',
  bool? phasePredictionEnabled = true,
  bool? autoDetectPeriodStartEnabled = true,
  bool? showFertilityWindowEnabled = false,
  bool? trackingPaused = false,
  String? pauseReason,
  Date? pausedSince,
  bool? phasesUnavailable = false,
  List<String>? warnings,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return CycleSettingsResponse(
    (b) => b
      ..avgCycleLengthDays = avgCycleLengthDays
      ..avgPeriodLengthDays = avgPeriodLengthDays
      ..regularity = regularity
      ..phasePredictionEnabled = phasePredictionEnabled
      ..autoDetectPeriodStartEnabled = autoDetectPeriodStartEnabled
      ..showFertilityWindowEnabled = showFertilityWindowEnabled
      ..trackingPaused = trackingPaused
      ..pauseReason = pauseReason
      ..pausedSince = pausedSince
      ..phasesUnavailable = phasesUnavailable
      ..warnings = warnings == null ? null : (ListBuilder<String>(warnings))
      ..createdAt = createdAt
      ..updatedAt = updatedAt,
  );
}

/// `POST /onboarding/cycle`. The default echoes a save that stored the T6
/// defaults and warned about nothing.
///
/// The response ECHOES the resolved values, which is how the screen learns the
/// `28` the user never typed — so `warnings` defaults to an empty list rather
/// than to null, matching a server that computed the band and found nothing.
OnboardingCycleResponse onboardingCycleFixture({
  Date? lastPeriodStart,
  int? avgCycleLengthDays = 28,
  int? avgPeriodLengthDays,
  String? regularity = 'somewhat',
  List<String>? warnings = const <String>[],
}) {
  return OnboardingCycleResponse(
    (b) => b
      ..lastPeriodStart = lastPeriodStart ?? Date(2026, 4, 6)
      ..avgCycleLengthDays = avgCycleLengthDays
      ..avgPeriodLengthDays = avgPeriodLengthDays
      ..regularity = regularity
      ..warnings = warnings == null ? null : (ListBuilder<String>(warnings)),
  );
}

/// `GET /cycle/calendar`. Only `today` is ever read by P4b-T9 — the screen-3
/// month anchor — so the day list is left unset, which is also the shape a
/// brand-new account gets back.
CycleCalendarResponse cycleCalendarFixture({
  Date? today,
  String? timezone = 'Europe/Madrid',
}) {
  return CycleCalendarResponse(
    (b) => b
      ..today = today ?? Date(2026, 4, 20)
      ..timezone = timezone,
  );
}
