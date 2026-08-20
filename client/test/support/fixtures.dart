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
import 'package:lumen/api/model/cycle_calendar_day.dart';
import 'package:lumen/api/model/cycle_calendar_response.dart';
import 'package:lumen/api/model/cycle_day_log_response.dart';
import 'package:lumen/api/model/cycle_day_response.dart';
import 'package:lumen/api/model/cycle_event_response.dart';
import 'package:lumen/api/model/cycle_phase_availability_response.dart';
import 'package:lumen/api/model/cycle_settings_response.dart';
import 'package:lumen/api/model/date.dart';
import 'package:lumen/api/model/goal_selection.dart';
import 'package:lumen/api/model/goals_response.dart';
import 'package:lumen/api/model/hormone_prefs_response.dart';
import 'package:lumen/api/model/hormone_selection.dart';
import 'package:lumen/api/model/me_response.dart';
import 'package:lumen/api/model/notification_category_selection.dart';
import 'package:lumen/api/model/notification_prefs_response.dart';
import 'package:lumen/api/model/onboarding_complete_response.dart';
import 'package:lumen/api/model/onboarding_cycle_response.dart';
import 'package:lumen/api/model/onboarding_state_response.dart';
import 'package:lumen/api/model/phase_override_boundary.dart';
import 'package:lumen/api/model/quick_checkin_response.dart';
import 'package:lumen/api/model/symptom_list_response.dart';
import 'package:lumen/api/model/symptom_response.dart';

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
  Map<String, bool>? hormones,
  Map<String, bool>? notifications,
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
          : ListBuilder<GoalSelection>(goalSelections(goals))
      ..hormones = hormones == null
          ? null
          : ListBuilder<HormoneSelection>(hormoneSelections(hormones))
      ..notifications = notifications == null
          ? null
          : ListBuilder<NotificationCategorySelection>(
              notificationSelections(notifications),
            ),
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

// ---------------------------------------------------------------------------
// Hormones (P4b-T12)
// ---------------------------------------------------------------------------

/// The seven hormone codes in `HormoneCatalog.Codes.All` order, each with the
/// D-14 seed flag.
///
/// This is the list `OnboardingStepsService.ReadHormonePrefsAsync` answers for
/// a user who has never answered the step: **all seven ON**
/// (`UserHormonePref.DefaultCharted = HormoneCatalog.Codes.All`,
/// `UserHormonePref.cs:39`). It is a FIXTURE, not a client-side source of
/// truth - the screen renders whatever the response carries, and this map
/// exists so a test can state what the server would have said.
///
/// The keys are the WIRE codes. Two of them differ from the label screen 6
/// draws: `estradiol` shows as "Estrogen" and `glp1` as "GLP-1" (B16).
const Map<String, bool> kSeededHormones = <String, bool>{
  'estradiol': true,
  'progesterone': true,
  'lh': true,
  'fsh': true,
  'testosterone': true,
  'cortisol': true,
  'glp1': true,
};

/// [selections] as wire rows, in the map's insertion order.
///
/// Order is load-bearing on this endpoint: the response lists the COMPLETE
/// vocabulary in **frozen order** and the client renders that order rather than
/// one of its own, so a test that wants to prove it needs to be able to hand
/// over an order of its choosing.
List<HormoneSelection> hormoneSelections(Map<String, bool> selections) {
  return <HormoneSelection>[
    for (final MapEntry<String, bool> entry in selections.entries)
      HormoneSelection(
        (b) => b
          ..code = entry.key
          ..charted = entry.value,
      ),
  ];
}

/// `POST /onboarding/hormones`. The default is the answer a user who has never
/// answered the step gets back - every code, with the D-14 seed.
HormonePrefsResponse hormonePrefsResponseFixture([
  Map<String, bool>? selections,
]) {
  return HormonePrefsResponse(
    (b) => b
      ..hormones = ListBuilder<HormoneSelection>(
        hormoneSelections(selections ?? kSeededHormones),
      ),
  );
}

// ---------------------------------------------------------------------------
// Notifications (P4b-T13)
// ---------------------------------------------------------------------------

/// The four notification category codes in
/// `HormoneCatalog.NotificationCategories.All` order, each with the onboarding
/// seed.
///
/// This is the list `OnboardingStepsService.ReadNotificationPrefsAsync` answers
/// for a user who has never answered the step — `daily_checkin` and
/// `phase_shift` ON, the other two OFF
/// (`UserNotificationPref.DefaultEnabled`, `UserNotificationPref.cs:40-44`).
/// It is a FIXTURE, not a client-side source of truth: the screen renders
/// whatever the response carries, and this map exists so a test can state what
/// the server would have said.
///
/// The keys are the WIRE codes. `phase_shift` is **singular** — screen 7's
/// plural "Phase shifts" is display drift and the catalogue is the authority
/// (`HormoneCatalog.cs:85-108`).
const Map<String, bool> kSeededNotifications = <String, bool>{
  'daily_checkin': true,
  'phase_shift': true,
  'period_prediction': false,
  'medication_reminders': false,
};

/// [selections] as wire rows, in the map's insertion order.
///
/// Order is load-bearing on this endpoint: the response lists the COMPLETE
/// vocabulary in **frozen order** and the client renders that order rather than
/// one of its own, so a test that wants to prove it needs to be able to hand
/// over an order of its choosing.
List<NotificationCategorySelection> notificationSelections(
  Map<String, bool> selections,
) {
  return <NotificationCategorySelection>[
    for (final MapEntry<String, bool> entry in selections.entries)
      NotificationCategorySelection(
        (b) => b
          ..code = entry.key
          ..enabled = entry.value,
      ),
  ];
}

/// `POST /onboarding/notifications`. The default is the answer a user who has
/// never answered the step gets back — every code, with the onboarding seed —
/// and **no device registered**, which is the normal outcome of a request that
/// carried no push token (`OnboardingContracts.cs:290-293`).
NotificationPrefsResponse notificationPrefsResponseFixture([
  Map<String, bool>? selections,
  bool? deviceRegistered = false,
]) {
  return NotificationPrefsResponse(
    (b) => b
      ..categories = ListBuilder<NotificationCategorySelection>(
        notificationSelections(selections ?? kSeededNotifications),
      )
      ..deviceRegistered = deviceRegistered,
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

/// `GET /cycle/calendar`. P4b-T9 only ever reads `today` — the screen-3 month
/// anchor — so [days]/[from]/[to]/[phase] default to unset, which is also the
/// shape a brand-new account gets back. P4b-T14's windowed calendar read
/// (`CycleRepository.getCalendarMonth`) is what exercises the rest.
CycleCalendarResponse cycleCalendarFixture({
  Date? today,
  String? timezone = 'Europe/Madrid',
  Date? from,
  Date? to,
  List<CycleCalendarDay>? days,
  CyclePhaseAvailabilityResponse? phase,
}) {
  return CycleCalendarResponse((b) {
    b
      ..today = today ?? Date(2026, 4, 20)
      ..timezone = timezone
      ..from = from
      ..to = to;
    if (days != null) b.days.replace(days);
    if (phase != null) b.phase.replace(phase);
  });
}

/// One sparse row of `GET /cycle/calendar`'s `days` list
/// (`survey/decisions-and-vocabularies.md:450` and `survey/backend-
/// endpoints.md:517` — a day with nothing on it is absent from the list
/// entirely, never a zero-valued row; this fixture is for the days that DO
/// appear).
CycleCalendarDay cycleCalendarDayFixture({
  Date? date,
  int? pain,
  int? mood,
  bool? hasNotes = false,
  int? eventCount = 0,
  int? symptomCount = 0,
}) {
  return CycleCalendarDay(
    (b) => b
      ..date = date ?? Date(2026, 4, 20)
      ..pain = pain
      ..mood = mood
      ..hasNotes = hasNotes
      ..eventCount = eventCount
      ..symptomCount = symptomCount,
  );
}

/// `GET /cycle/day/{date}`. Defaults to an EMPTY day — `log: null`, `events`
/// and `phaseOverrides` unset — the 200 P4a returns for a day nobody has
/// logged anything on (never a 404, `survey/decisions-and-vocabularies.md:451`
/// and `survey/backend-endpoints.md:245`).
CycleDayResponse cycleDayFixture({
  Date? date,
  CycleDayLogResponse? log,
  List<CycleEventResponse>? events,
  List<PhaseOverrideBoundary>? phaseOverrides,
}) {
  return CycleDayResponse((b) {
    b.date = date ?? Date(2026, 4, 20);
    if (log != null) b.log.replace(log);
    if (events != null) b.events.replace(events);
    if (phaseOverrides != null) b.phaseOverrides.replace(phaseOverrides);
  });
}

/// One `cycle_day_logs` row, as `GET /cycle/day/{date}`'s `log` echoes it.
CycleDayLogResponse cycleDayLogFixture({
  Date? day,
  int? pain = 3,
  int? mood = 3,
  String? notes,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return CycleDayLogResponse(
    (b) => b
      ..day = day ?? Date(2026, 4, 20)
      ..pain = pain
      ..mood = mood
      ..notes = notes
      ..createdAt = createdAt ?? DateTime.utc(2026, 4, 20, 8)
      ..updatedAt = updatedAt ?? DateTime.utc(2026, 4, 20, 8),
  );
}

// ---------------------------------------------------------------------------
// Symptoms (P4b-T16) — no fixture existed before this task
// ---------------------------------------------------------------------------

/// One `symptoms` row, as `GET /symptoms` echoes it.
///
/// **`intensity` defaults to `3`, not `0` and not `null`** — deliberately, so
/// a test that wants the D-08 edge case (`intensity: 0` is a real datum, and
/// `null` is the only "not recorded") asks for it explicitly rather than
/// getting it by accident from an unset default. `painTypes`/`triggers`
/// default to EMPTY lists, never null (`SymptomService.cs:556-557`: "empty,
/// never NULL — keeping 'the user classified nothing' a single state").
SymptomResponse symptomResponseFixture({
  String? id = 'symptom-abc123',
  String? symptomCode = 'bloating',
  int? intensity = 3,
  String? region = 'lower_abdomen',
  String? side,
  List<String>? painTypes = const <String>[],
  List<String>? triggers = const <String>[],
  DateTime? occurredAt,
  Date? occurredOn,
  String? notes,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return SymptomResponse(
    (b) => b
      ..id = id
      ..symptomCode = symptomCode
      ..intensity = intensity
      ..region = region
      ..side = side
      ..painTypes = painTypes == null ? null : ListBuilder<String>(painTypes)
      ..triggers = triggers == null ? null : ListBuilder<String>(triggers)
      ..occurredAt = occurredAt ?? DateTime.utc(2026, 4, 20, 8)
      ..occurredOn = occurredOn ?? Date(2026, 4, 20)
      ..notes = notes
      ..createdAt = createdAt ?? DateTime.utc(2026, 4, 20, 8)
      ..updatedAt = updatedAt ?? DateTime.utc(2026, 4, 20, 8),
  );
}

/// `GET /symptoms`'s response envelope. Defaults to one row and a `total`
/// that MATCHES `items.length` — a test proving truncation is visible
/// (§R-18: `total` may exceed the returned page) overrides both explicitly.
SymptomListResponse symptomListResponseFixture({
  List<SymptomResponse>? items,
  int? total,
  int? limit = 100,
  int? offset = 0,
}) {
  final rows = items ?? <SymptomResponse>[symptomResponseFixture()];
  return SymptomListResponse(
    (b) => b
      ..items = ListBuilder<SymptomResponse>(rows)
      ..total = total ?? rows.length
      ..limit = limit
      ..offset = offset,
  );
}

/// `POST /checkin/quick`'s response — the STORED row, not an echo of the
/// request (`CycleDayService.cs:187`). [pain]/[mood] default to null, NOT to
/// 0 — a test that wants the response to actually carry a field must say so
/// explicitly, the same D-08 discipline the production code itself follows.
QuickCheckinResponse quickCheckinResponseFixture({
  Date? day,
  int? pain,
  int? mood,
  DateTime? updatedAt,
}) {
  return QuickCheckinResponse(
    (b) => b
      ..day = day ?? Date(2026, 4, 20)
      ..pain = pain
      ..mood = mood
      ..updatedAt = updatedAt ?? DateTime.utc(2026, 4, 20, 8),
  );
}

/// `POST /cycle/events`'s response, and one `cycle_events` row wherever else
/// one is needed (e.g. inside `CycleDayResponse.events`).
CycleEventResponse cycleEventFixture({
  String? id = 'event-abc123',
  String? kind = 'period_start',
  Date? occurredOn,
  int? flowIntensity,
  String? notes,
  String? source = 'user',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return CycleEventResponse(
    (b) => b
      ..id = id
      ..kind = kind
      ..occurredOn = occurredOn ?? Date(2026, 4, 20)
      ..flowIntensity = flowIntensity
      ..notes = notes
      ..source_ = source
      ..createdAt = createdAt ?? DateTime.utc(2026, 4, 20, 8)
      ..updatedAt = updatedAt ?? DateTime.utc(2026, 4, 20, 8),
  );
}
