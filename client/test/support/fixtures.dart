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
import 'package:lumen/api/model/baseline_response.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/goal_selection.dart';
import 'package:lumen/api/model/goals_response.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';

/// `GET /me`. The shipped default is a fully-onboarded Spanish-locale user.
///
/// **The six baseline keys default to null** (`diagnosedOn`, `dob`,
/// `endoStatus`, `heightCm`, `latestWeightKg`, `rasrmStage` — P4a spliced them
/// in, §C.0.2). That is the honest default: D-02 makes screen 4 skippable, so
/// "not answered" is the shape most accounts have, and the P3b-era Hive cache
/// carries none of them.
MeResponse meResponseFixture({
  String? id = 'user-abc123',
  String? displayName = 'María',
  String? locale = 'es',
  String? timezone = 'Europe/Madrid',
  bool? onboardingCompleted = true,
  Date? dob,
  int? heightCm,
  double? latestWeightKg,
  String? endoStatus,
  int? rasrmStage,
  String? diagnosedOn,
}) {
  return MeResponse(
    (b) => b
      ..id = id
      ..displayName = displayName
      ..locale = locale
      ..timezone = timezone
      ..onboardingCompleted = onboardingCompleted
      ..dob = dob
      ..heightCm = heightCm
      ..latestWeightKg = latestWeightKg
      ..endoStatus = endoStatus
      ..rasrmStage = rasrmStage
      ..diagnosedOn = diagnosedOn,
  );
}

/// `POST /onboarding/baseline`. The default is the answer a user who has
/// answered nothing gets back — plus one month string, deliberately.
///
/// The response is the server's RE-READ of the stored row, not an echo of the
/// request, so a fixture that returns nothing is what a first save of one field
/// legitimately looks like for the other five. Note `latestWeightKg` — the
/// response names the weight differently from the request's `weightKg`, because
/// it comes from the latest live `body_metrics` row rather than from the
/// profile.
///
/// **`diagnosedOn` defaults to a real `yyyy-MM` string** rather than to null.
/// It is a `String?` and NOT a `Date?` because the generated `DateSerializer`
/// calls `DateTime.parse`, which throws on `"2026-08"` (§C.0.2) — and every
/// consumer of a successful save maps this response by hand. A hand-parse
/// added there would throw inside `submit`'s try, be swallowed by its
/// `catch (_)` and surface as a generic banner; with the default null, no test
/// could ever redden. So every save in every test carries the string that would
/// break it.
BaselineResponse baselineFixture({
  Date? dob,
  int? heightCm,
  double? latestWeightKg,
  String? endoStatus,
  int? rasrmStage,
  String? diagnosedOn = '2026-08',
}) {
  return BaselineResponse(
    (b) => b
      ..dob = dob
      ..heightCm = heightCm
      ..latestWeightKg = latestWeightKg
      ..endoStatus = endoStatus
      ..rasrmStage = rasrmStage
      ..diagnosedOn = diagnosedOn,
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
  Map<String, bool>? goals,
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
      ..lastPeriodStart = lastPeriodStart
      // Left unset by default, with the other three lists: they are nullable
      // in the generated client and a screen that force-unwraps one is broken
      // against the real contract.
      ..goals = goals == null
          ? null
          : ListBuilder<GoalSelection>(goalSelections(goals)),
  );
}

// ---------------------------------------------------------------------------
// Goals (P4b-T11)
// ---------------------------------------------------------------------------

/// The five ratified goal codes in `UserGoal.Codes.All` order, each with the
/// D-14 seed flag.
///
/// This is the list `OnboardingStepsService.ReadGoalsAsync` answers for a user
/// who has never answered the step — the first two ON, the rest OFF
/// (`UserGoal.cs:37-38,44-54`). It is a FIXTURE, not a client-side source of
/// truth: the screen renders whatever the response carries, and this map exists
/// so a test can state what the server would have said.
const Map<String, bool> kSeededGoals = <String, bool>{
  'manage_symptoms': true,
  'understand_hormones': true,
  'plan_fertility': false,
  'prepare_appointments': false,
  'just_curious': false,
};

/// [selections] as wire rows, in the map's insertion order.
///
/// Order is load-bearing on this endpoint: the response lists the COMPLETE
/// vocabulary in **frozen order** and the client renders that order rather than
/// one of its own, so a test that wants to prove it needs to be able to hand
/// over an order of its choosing.
List<GoalSelection> goalSelections(Map<String, bool> selections) {
  return <GoalSelection>[
    for (final MapEntry<String, bool> entry in selections.entries)
      GoalSelection(
        (b) => b
          ..code = entry.key
          ..selected = entry.value,
      ),
  ];
}

/// `POST /onboarding/goals`. The default is the answer a user who has never
/// answered the step gets back — every code, with the D-14 seed.
GoalsResponse goalsResponseFixture([Map<String, bool>? selections]) {
  return GoalsResponse(
    (b) => b
      ..goals = ListBuilder<GoalSelection>(
        goalSelections(selections ?? kSeededGoals),
      ),
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
