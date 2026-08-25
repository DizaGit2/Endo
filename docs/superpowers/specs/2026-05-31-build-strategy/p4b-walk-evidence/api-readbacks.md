# API read-backs — verbatim tool output from `api.ps1` (password grant on the confidential `api` client), local time in headings

## 16:33:39 — before the screen-3 save
GET /me → 200
{"id":"557030dd-a3a7-42ff-a014-cface4149d3b","displayName":"Valentina","locale":"es-ES","timezone":"Europe/Madrid","onboardingCompleted":false,"dob":null,"heightCm":null,"endoStatus":null,"rasrmStage":null,"diagnosedOn":null,"latestWeightKg":null}
GET /onboarding/state → 200
{"completed":false,"completedAt":null,"missingMandatorySteps":["cycle"],"cycleProvided":false,"baselineProvided":false,"goalsProvided":false,"hormonesProvided":false,"notificationsProvided":false,"lastPeriodStart":null,"goals":[{"code":"manage_symptoms","selected":true},{"code":"understand_hormones","selected":true},{"code":"plan_fertility","selected":false},{"code":"prepare_appointments","selected":false},{"code":"just_curious","selected":false}],"hormones":[{"code":"estradiol","charted":true},{"code":"progesterone","charted":true},{"code":"lh","charted":true},{"code":"fsh","charted":true},{"code":"testosterone","charted":true},{"code":"cortisol","charted":true},{"code":"glp1","charted":true}],"notifications":[{"code":"daily_checkin","enabled":true},{"code":"phase_shift","enabled":true},{"code":"period_prediction","enabled":false},{"code":"medication_reminders","enabled":false}]}

## 16:33:49 — after the screen-3 save (12 Aug / 26 / Regular)
GET /onboarding/state → 200  (…"missingMandatorySteps":[],"cycleProvided":true,…"lastPeriodStart":"2026-08-12",… rest unchanged)
GET /settings/cycle → 200
{"avgCycleLengthDays":26,"avgPeriodLengthDays":null,"regularity":"regular","phasePredictionEnabled":true,"autoDetectPeriodStartEnabled":true,"showFertilityWindowEnabled":false,"trackingPaused":false,"pauseReason":null,"pausedSince":null,"phasesUnavailable":false,"warnings":[],"createdAt":"2026-08-25T22:33:42.463846+00:00","updatedAt":"2026-08-25T22:33:42.463846+00:00"}

## 16:36:46 — after the screen-4 save
GET /me → 200
{"id":"557030dd-a3a7-42ff-a014-cface4149d3b","displayName":"Valentina","locale":"es-ES","timezone":"Europe/Madrid","onboardingCompleted":false,"dob":"1996-08-14","heightCm":165,"endoStatus":"diagnosed","rasrmStage":null,"diagnosedOn":null,"latestWeightKg":60.0}
GET /onboarding/state → 200  (…"cycleProvided":true,"baselineProvided":true,"goalsProvided":false,…)

## 16:37:29 — after the screen-5 save (both defaults deselected)
GET /onboarding/state → 200
{"completed":false,"completedAt":null,"missingMandatorySteps":[],"cycleProvided":true,"baselineProvided":true,"goalsProvided":true,"hormonesProvided":false,"notificationsProvided":false,"lastPeriodStart":"2026-08-12","goals":[{"code":"manage_symptoms","selected":false},{"code":"understand_hormones","selected":false},{"code":"plan_fertility","selected":false},{"code":"prepare_appointments","selected":true},{"code":"just_curious","selected":true}],"hormones":[…all 7 charted true…],"notifications":[…unchanged…]}

## 16:38:00 — after chevron 5→4 and Continue ×2 (re-entry)
GET /me → 200  (identical to 16:36:46)
GET /onboarding/state → 200  (identical to 16:37:29)

## 16:38:29 — after the screen-6 save
GET /onboarding/state → 200  (…"hormonesProvided":true,…"hormones":[{"code":"estradiol","charted":true},{"code":"progesterone","charted":true},{"code":"lh","charted":true},{"code":"fsh","charted":true},{"code":"testosterone","charted":true},{"code":"cortisol","charted":false},{"code":"glp1","charted":false}],…)

## 16:39:28 — after Allow & finish
GET /onboarding/state → 200
{"completed":true,"completedAt":"2026-08-25T22:39:17.417722+00:00","missingMandatorySteps":[],"cycleProvided":true,"baselineProvided":true,"goalsProvided":true,"hormonesProvided":true,"notificationsProvided":true,"lastPeriodStart":"2026-08-12","goals":[…prepare_appointments,just_curious true…],"hormones":[…cortisol,glp1 false…],"notifications":[{"code":"daily_checkin","enabled":true},{"code":"phase_shift","enabled":true},{"code":"period_prediction","enabled":true},{"code":"medication_reminders","enabled":false}]}
GET /me → 200  (…"onboardingCompleted":true,"dob":"1996-08-14","heightCm":165,"endoStatus":"diagnosed",…"latestWeightKg":60.0)

## 16:39:4x — server today
GET /cycle/calendar → 200  today=2026-08-26 timezone=Europe/Madrid from=2026-08-01 to=2026-08-31 (properties: from, to, today, timezone, phase, days)

## 16:40:49 — after the quick check-in (pain 0, Steady)
GET /cycle/day/2026-08-26 → 200
{"date":"2026-08-26","log":{"day":"2026-08-26","pain":0,"mood":3,"notes":null,"createdAt":"2026-08-25T22:40:41.7196+00:00","updatedAt":"2026-08-25T22:40:41.7196+00:00"},"events":[],"phaseOverrides":[]}
GET /cycle/day/2026-08-25 → 200
{"date":"2026-08-25","log":null,"events":[],"phaseOverrides":[]}

## 16:43:05 — after the symptom save
GET /symptoms?from=2026-08-24&to=2026-08-27 → 200
{"items":[{"id":"cf9c999f-cd69-47fe-bcb2-d70c29555a04","symptomCode":"pain","intensity":6,"region":"pelvis","side":null,"painTypes":["cramping"],"triggers":[],"occurredAt":"2026-08-25T22:42:43.198303+00:00","occurredOn":"2026-08-26","notes":"E2E walk note 08251630","createdAt":"2026-08-25T22:42:43.198303+00:00","updatedAt":"2026-08-25T22:42:43.198303+00:00"},{"id":"a879623f-7816-4693-8d6f-a3947a6d4d99","symptomCode":"nausea","intensity":4,"region":"unspecified","side":null,"painTypes":[],"triggers":[],"occurredAt":"2026-08-25T22:42:43.198303+00:00","occurredOn":"2026-08-26","notes":null,"createdAt":"2026-08-25T22:42:43.198303+00:00","updatedAt":"2026-08-25T22:42:43.198303+00:00"}],"total":2,"limit":50,"offset":0}

## Step 8 — /settings/cycle after each PATCH
16:45:15 after pause 1: {"…","trackingPaused":true,"pauseReason":"pregnancy","pausedSince":"2026-08-26","phasesUnavailable":true,…"updatedAt":"2026-08-25T22:45:08.143358+00:00"}
16:45:44 after resume 1: {"…","trackingPaused":false,"pauseReason":"pregnancy","pausedSince":null,"phasesUnavailable":false,…"updatedAt":"2026-08-25T22:45:37.591758+00:00"}
16:46:24 after pause 2: {"…","trackingPaused":true,"pauseReason":"hormonal_suppression","pausedSince":"2026-08-26","phasesUnavailable":true,…"updatedAt":"2026-08-25T22:46:17.203089+00:00"}
16:46:46 after resume 2: {"…","trackingPaused":false,"pauseReason":"hormonal_suppression","pausedSince":null,"phasesUnavailable":false,…"updatedAt":"2026-08-25T22:46:40.037721+00:00"}
(avgCycleLengthDays 26 / regularity regular unchanged throughout)

## 16:53:5x — after the offline-then-retry check-in (pain 3, Tired)
GET /cycle/day/2026-08-26 → 200
{"date":"2026-08-26","log":{"day":"2026-08-26","pain":3,"mood":2,"notes":null,"createdAt":"2026-08-25T22:40:41.7196+00:00","updatedAt":"2026-08-25T22:53:49.73054+00:00"},"events":[],"phaseOverrides":[]}
