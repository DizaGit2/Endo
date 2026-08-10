# P4a task breakdown

**Branch:** `phase/04a-logging-backend` · **Depends on:** P3c DONE · **Safety-critical:** no (but **T8 is ⚠**)
**Sources:** `ARCHITECTURE.md §A` (authoritative on any conflict) / `§C.1,§C.2,§C.3,§C.9` / `§D` / `§F` · `definitions.md` 2026-07-08 ratification block (lines 20–33; the per-module tables below it are stale provenance) · `lumen-build.md` §2 invariants + the P4a entry riders 1–7 + the r17 §4 row · `decision-sheet.md` D-02/D-08..D-14/B15/B16 · `clinical-asks.md` C-03/C-04/C-12 (**PO-interim, clinician-UNSIGNED**).

---

## Decisions taken at phase entry (2026-08-06)

**Confirmed by the PO** — these close OQ-1, OQ-2, OQ-6 and OQ-4/5/7/10 below; the breakdown already implements them:

| # | Decision | Consequence |
|---|---|---|
| OQ-1 | **Crypto-shred hard-deletes the new plaintext health rows** (option a), and T8 is treated as ⚠ (scoped `/code-review high`) | §D mandates plaintext for the P6 engine, so DEK deletion no longer makes this data unreadable — the §2 erasure invariant needed an explicit amendment. `§F` amended in T8; privacy-policy wording flagged for L-05/L-06 |
| OQ-2 | **Ship `cycle_tracking_pause_spans`** | §A:59's "paused spans excluded from estimators" is unsatisfiable with rider 2's three fields alone; without it every pause/resume between P4a and P6 is lost |
| OQ-6 | **`POST /symptoms` is a batch** (1–50, all-or-nothing, 201 with `items`) | D-09 makes one save inherently multi-row; the online-only client has no write queue. The 1–50 cap is a P4a invention (§G11) |
| OQ-4/5/7/10 | **Ship all four additive surfaces** — timezone/locale on `PATCH /me`; `DELETE /cycle/events/{id}`; phase-override storage + `GET /onboarding/state` + `POST /me/devices`; the condition-field write/read path | Each is additive and lands in the one phase that regenerates the Dart client anyway. All require the same-branch `ARCHITECTURE.md` amendments in §G13 |

**Resolved from the documents, no PO call needed:**

- **OQ-3 — sanity bounds are SOFT.** `clinical-asks.md:34` ("non-blocking sanity guard… never blocks save") and rider 7 ("never entry blockers (PO requirement)") are verbatim and decisive. Structural type-domain check only; no invented `1–365`/`1–90` tier. See §G7.
- **OQ-8 — the C-03/C-04 clinical numbers live in documentation only** (T22 STATUS + the `§A` P4a row). Plan §2 forbids hard-coded clinical magic numbers and §G6 keeps `ref_insight_rule` out of P4a, so there is no lawful code home for them this phase. No `Lumen.Domain.Clinical` namespace ships.
- **OQ-9 — `ref_hormone` deferred to P7b**; `HormoneCatalog.cs` constants ship now. Two of B16's five columns (`display_unit` → C-07, `category`) cannot be filled without unsigned or non-existent clinical values.

---

## Global constraints

*Every rule here binds every task. Reviewers: this is the attention lens — a diff that contradicts anything below is wrong regardless of how good it looks.*

### G1. Dispatch model — P4a is **strictly serial**

Exactly one task is in flight at a time; every task starts from a clean tree at the previous task's commit. Shared write targets that make parallelism unsafe: `Program.cs`, `LumenDbContext.cs`, `LumenDbContextModelSnapshot.cs`, `backend/contract/openapi.json`, `client/openapi/lumen.openapi.json`, `VocabularyTests.cs`, `ArchitectureTests.cs`, `GdprErasureBaselineTests.cs`, `PiiRedactionEnricher.cs`. Two concurrent agents produce a snapshot/contract conflict neither can resolve, and the contract conflict is invisible until CI's `openapi-contract` job.

### G2. TDD, and what "red" means here

Write the named tests first, watch them fail, then the production change. **In a statically-typed codebase the red phase is normally a COMPILE failure — that counts, and the compiler error is the evidence to paste.** Where the code under test already compiles (T3, T4, T7's arch fact, T8's enricher, T20's spine guard), a **runnable** red is required and the failing assertion output must be pasted. No task is done until `dotnet build backend/Lumen.slnx -warnaserror --nologo` and the relevant suites are green **with pasted output**.

### G3. Contract regeneration

`OpenApiSnapshotTests` compares the live document against `backend/contract/openapi.json`, so **every task that adds or changes an endpoint or DTO regenerates BOTH JSON snapshots in its own commit**:

```powershell
$env:LUMEN_OPENAPI_UPDATE = '1'; dotnet test backend/Lumen.slnx --filter "FullyQualifiedName~OpenApi" --nologo; Remove-Item Env:\LUMEN_OPENAPI_UPDATE
dotnet test backend/Lumen.slnx --filter "FullyQualifiedName~OpenApi" --nologo   # re-run WITHOUT the var: must pass
```

The two JSONs must stay byte-identical (`ci-client.yml` runs `cmp`). The **Dart client is regenerated exactly once, in T21**.

### G4. Migrations — **three, and only three**

`AddCycleAndSymptomTables` (T5), `AddCycleSettingsPauseSpansAndPreferences` (T6), `AddProfileConditionsBodyMetricsAndInsightSnapshot` (T7). **No task from T8 onward may add a migration or a `DbSet` — if one turns out to be needed, STOP and re-plan, because T8's erasure list and its security test are keyed to the T5–T7 table set.** Each migration commits `*.cs` + `*.Designer.cs` + the regenerated `LumenDbContextModelSnapshot.cs` (else `ModelSyncTests` fails with no DB attached). Apply before any LiveStack run — `dotnet ef` does not restore, so build first:

```powershell
dotnet build backend/src/Lumen.Infrastructure --nologo
dotnet ef database update --no-build --project backend/src/Lumen.Infrastructure --startup-project backend/src/Lumen.Infrastructure
```

### G5. Plan §2 invariants

Every `*_enc` column is AES-256-GCM through the request-scoped `IUserCryptoContext`; the DEK is never logged, persisted or cached beyond scope. `TimeProvider` only — RS0030 makes `DateTime.UtcNow` a **build error** under `backend/src`; capture one `now` per operation. Soft-delete everywhere except account deletion (crypto-shred, D-13). **Reference data is seeded via migration with `valid_from` + provenance and is the single source of truth; the engine reads `ref_insight_rule` params, never hard-coded magic numbers.** .NET 10 only. Online-only client.

### G6. P4a ships **ZERO clinical inference**

No phase math, no ovulation, no fertile window, no confidence/data-completeness computation, no auto-detect, no regularity tiering, no missing-data cards, no C-15 red-flag note, **no `ref_insight_rule`**, no matviews, no `RecomputeInsightSnapshotJob`. `user_insight_snapshot` gets a table with **zero rows**, `ComputedBy` defaulting to `'placeholder'`, and **no read endpoint** (build-guarded, T7). The cycle calendar reports `phase: { available: false, unavailableReason: "phase_engine_not_implemented" }` and **no day row carries a `phase`, `cycleDay` or `confidence` key**.

### G7. Two-tier bounds (rider 7 / `ARCHITECTURE.md:58` / C-03)

- **Observed data** (cycle events, day logs, symptoms) is **never** clinically validated.
- **Typed self-reports** (`avgCycleLengthDays`, `avgPeriodLengthDays`) get **only a structural type-domain check**: a positive integer that fits `smallint` (`<= 0` or `> 32767` → 400). Outside the **sanity band** (avg cycle 10–120 d, period 1–30 d) the value is **persisted** and a frozen non-blocking warning code is returned. DB CHECKs are `> 0` only.
- **There is no third tier.** `1–365` / `1–90` appeared in an earlier draft and are **invented** — they are not in any source and must not appear in DDL, validators, the contract or the Dart client.
- **Clinical bounds** (cycle 21–45 d, period 1–10 d, **mean** of last 6 in-bounds cycles, ≥3 cycles before overriding the self-report, `flow_intensity >= 2` period-qualifying, ≥3-day episode gap for auto-detect) are **clinician-UNSIGNED PO-interim values**. They have **no home in `backend/src` in P4a** — §G5 says they belong in `ref_insight_rule` seed rows, which P6 owns (§G6 bans them here). P4a records them **in the STATUS block and the `ARCHITECTURE.md §A` P4a row only**. The behavioural guard that they are not entry blockers is T14's test that `avgCycleLengthDays = 15` and `= 47` are both accepted and stored with the correct warning state.

### G8. Backdate floor is **`cycle_events`-only**

D-13 verbatim: *"No future dates for symptom/body/activity/lab entries (max = user-local today); `cycle_events` may backdate within a floor (account-creation − 2y)."* Therefore:

| Write | Rule |
|---|---|
| `POST /cycle/events`, `POST /onboarding/cycle` (`lastPeriodStart`) | `<= user-local today` **and** `>= BackdateFloor` |
| `POST /cycle/day/{date}`, `POST /checkin/quick`, `POST /symptoms`, `PUT /symptoms/{id}`, `POST /onboarding/baseline` (`dob`) | `<= user-local today` **only — no floor** |

`UserDayInfo.BackdateFloor` exists but its XML doc states it is cycle-events-only. Applying it elsewhere would reject legitimate historical logging D-13 permits.

### G9. Soft-delete unique-index regime (state it, don't reverse-engineer it)

- **Unfiltered unique index + revive-the-tombstone on upsert:** `cycle_events` `(UserId, Kind, OccurredOn)`, `cycle_day_logs` `(UserId, Day)`. Upserts look the row up with `IgnoreQueryFilters()` and clear `DeletedAt`; they never insert a second row.
- **Filtered unique index (`WHERE "DeletedAt" IS NULL`):** `body_metrics` `(UserId, Metric, MeasuredOn)` — the one deliberate exception, because the D-02 baseline step must be re-submittable after a delete. The rationale lives on the entity's XML doc.
- **This §G9 regime is about SOFT-DELETE TOMBSTONES only** *(clarified after T6's review, 2026-08-06)*. A partial unique index whose predicate is a **domain lifecycle** column rather than `DeletedAt` is a different concern and is NOT an exception to the rule above: `cycle_tracking_pause_spans (UserId) WHERE "EndedOn" IS NULL` (T6) enforces "at most one OPEN pause per user" on a table that has no `DeletedAt` at all. So a DB-level audit after T7 correctly finds **two** filtered unique indexes while §G9's tombstone inventory stays at exactly one.
- Every task that writes one of these tables cites the regime it is under.

### G10. Frozen vocabularies — exact members (`definitions.md:24-33`, the 2026-07-08 ratification block)

Transcribe these **verbatim**; do not consult the per-module tables further down `definitions.md` (stale). Append-only. Hard-coded as nested `static class` consts on the entity (§D: *"Enums hard-coded in code, not in DB"*), lowercase snake_case, no DB enum, no CHECK on membership.

| Set | Members |
|---|---|
| Symptom regions (9) | `lower_abdomen`, `pelvis`, `lower_back`, `legs`, `bowel_rectal`, `bladder`, `vaginal`, `chest_shoulder`, `unspecified` (default) |
| Sides (2) | **`front`, `back`** — NOT left/right (`ARCHITECTURE.md:37,:51,:184`; decision-sheet:61) |
| Pain types (6) | `cramping`, `sharp`, `burning`, `dull`, `stabbing`, `throbbing` (no `aching`) |
| Triggers (7) | `stress`, `intercourse`, `food`, `exercise`, `physical_strain`, `poor_sleep`, `weather` |
| Non-pain symptom catalog (20) | `bloating`, `nausea`, `fatigue`, `diarrhea`, `constipation`, `headache`, `dizziness`, `inflammation`, `water_retention`, `joint_pain`, `frequent_urination`, `frequent_bowel_movements`, `indigestion`, `depressed_mood`, `painful_intercourse`, `heavy_menstrual_flow`, `brain_fog`, `poor_concentration`, `food_sensitivity`, `acne` |
| Symptom codes (21) | `pain` + the 20 above |
| Intensity / pain | **0–10 (NRS-11)**, 0 is a valid datum (D-08) |
| Mood (1–4) | `low`, `tired`, `steady`, `bright` |
| Flow intensity (1–4) | `spotting`, `light`, `medium`, `heavy` |
| Cycle-event kinds (3) | `period_start`, `period_end`, `spotting` |
| Cycle phases (4) | `menstrual`, `follicular`, `ovulatory`, `luteal` — **codes only; P4a encodes no ordering and no dates** |
| Phase boundaries (2) | `start`, `end` |
| Regularity (3) | `regular`, `somewhat` (default), `irregular` |
| Pause reasons (5) | `pregnancy`, `hormonal_suppression`, `surgical`, `menopause`, `other` (C-12 / §A:59 — the r15 3-member list is superseded) |
| Goals (5) | `manage_symptoms`, `understand_hormones` (both default ON), `plan_fertility`, `prepare_appointments`, `just_curious` |
| Hormones (7) | `estradiol`, `progesterone`, `lh`, `fsh`, `testosterone`, `cortisol`, `glp1` — **charted default = all 7 ON** (D-14) |
| Notification categories (4) | `daily_checkin`, `phase_shift`, `period_prediction`, `medication_reminders` — seed **ON / ON / OFF / OFF** |
| Endo status (3) | `diagnosed`, `suspected`, `not_applicable` |
| Body-metric sources (3) | `manual` (default), `apple_health`, `google_fit` (§D:188) |
| Device platforms (2) | `ios`, `android` |
| Unit system (1, reserved) | `metric` (D-06 reserved column, no write path in P4a) |

Canonical **display labels** (i18n source strings, B16 / §A:61) live in one shared constants file and are never stored as data: `estradiol`→"Estrogen", `glp1`→"GLP-1", the other five = code capitalised; notification `phase_shift`→**"Phase shift"** (singular).

### G11. Values P4a **invents** (nothing else may be invented)

Recorded here and in the T22 STATUS block so a later phase does not mistake them for ratified: **windowed-read span ≤ 366 days** (`GET /cycle/calendar`, T13; `GET /symptoms`, T12 — T13 shipped the cap only on the calendar, then flagged in its report that `GET /symptoms` paged `items` but left `total`'s `COUNT(*)` unbounded over an arbitrary `from`/`to`, a defect closed in the same phase by hoisting the shared `Validation.ReadWindow.MaxDays`/`ValidationMessages.MaxWindowDays` both endpoints now use); `POST /symptoms` batch **1–50 entries**; `cycle_events.source` ∈ `{user, onboarding}`; `cycle_phase_overrides.source` ∈ `{user_correction}`; the structural positive-smallint domain of §G7. (`notes` ≤ 2000 chars and pagination 50/100 are D-13, not inventions; `push_token` ≤ 512 is the existing column.)

### G12. Cross-slice ownership (conflicts resolved once, here)

| Concern | Owner | Everyone else |
|---|---|---|
| D-12 user-local day | **T2** — `IUserDayResolver` (Application) + `UserDayResolver` (Infrastructure, singleton) + `IUserDayContext`/`UserDayContext` (Api, scoped) | consume it. The slice names `UserClock`/`UserDayCalculator` are dropped. |
| 400/404 **shape**, `ValidationProblemBuilder`, the **shared** message constants | **T3** | consume the shape; **endpoint-specific messages are defined in their own task and asserted verbatim there** |
| **404 body** — shipped by T3 as `Lumen.Api/Validation/NotFoundProblem.cs` (`NotFoundProblem.Result()` + `NotFoundProblem.Title`) | **T3** | **every task returning 404 MUST call `NotFoundProblem.Result()`** — never hand-write `TypedResults.Problem(statusCode: 404, …)`. Tenant isolation is **404, never 403** (403 confirms the id exists). T4 is the first caller (`GET /me`); T19 asserts the title verbatim across every resource. |
| Feature-folder DTO files `<Feature>/<Feature>Contracts.cs` | **T3** sets the convention | all endpoint tasks follow it. "DTOs at the bottom of `Program.cs`" is superseded — P4a adds ~45 records. **Schema-name rule (corrected after T4's review, 2026-08-06):** `AddSwaggerGen()` is bare — no `CustomSchemaIds` — so the OpenAPI schema id is `type.Name`, **independent of namespace**. Adding a `namespace` does NOT rename a schema (verified empirically: snapshot stayed byte-identical). The real hazard is a **short-type-name collision between two feature folders**, which throws a duplicate-schemaId error at document generation. So: keep DTO short names globally unique across all feature folders; the presence or absence of a `namespace` declaration is a style choice, not a contract guarantee. *(`OnboardingContracts.cs`'s header comment and the §A row still state the older, incorrect "namespace renames the schema" rationale — T22 corrects them.)* |
| Endpoint registration | `public static class XEndpoints { public static IEndpointRouteBuilder MapXEndpoints(this IEndpointRouteBuilder app) }`, called from `Program.cs`. **No `MapGroup`, no `.WithTags`, no `.WithName`** — a tag would split the generated Dart client out of `LumenApiApi` and break `client/lib/core/network/api_client.dart` + the two repositories. |
| `OnboardingEndpoints.cs` / `OnboardingContracts.cs` extraction | **T4** (pure move, spine tests as proof) | T16/T17/T18 add endpoints to the existing `MapOnboardingEndpoints()` |
| `CycleSettingsService` incl. `ApplyOnboardingCycleAsync` | **T14** | T18's `POST /onboarding/cycle` (B15) calls it, does not duplicate |
| `DeviceRegistrationService` | **T15** | T17's `/onboarding/notifications` reuses it — the **staging** half only (`StageRegistrationAsync`); `RegisterAsync` owns its own retry and must never be composed |
| Onboarding preference **read projections** (`ReadGoalsAsync`, `ReadHormonePrefsAsync`, `ReadNotificationPrefsAsync`) | **T17** | **T18 CONSUMES them and never re-derives a default.** They are the single place "a skipped step" is given a meaning; a second, independent restatement of the seed is exactly the drift they exist to prevent. Any backfill writes the entity constants, never literals. |
| `ConcurrencyRetry` helper | **T10** | T15 reuses it. **Unit-of-work rule, decided after T10's review (2026-08-10):** `ConcurrencyRetry`'s recovery is `ChangeTracker.Clear()`, which is a **whole-context** operation on a request-scoped `LumenDbContext` — so a caller that stages changes and then invokes a retried action has them **silently discarded**, with no exception and no failing test. Therefore: **a service method that a later task will COMPOSE must stage only — no `SaveChangesAsync`, no `Clear()`, no `ConcurrencyRetry` of its own.** The endpoint owns exactly one `ConcurrencyRetry` action wrapping the whole unit of work. This binds **T14** (`CycleSettingsService.ApplyOnboardingCycleAsync` must be composable, because **T18**'s `POST /onboarding/cycle` calls it while also writing a `cycle_events` row for `lastPeriodStart` — the exact compose-two-writes shape that breaks) and **T15**. Rejected alternative: making the helper detach only the failed action's entries instead of clearing the context. It would remove the hazard rather than warn about it and is now testable via T10's `LostRaceOnFirstSaveInterceptor` — but it changes production behaviour on five live write paths for a hazard the unit-of-work rule already eliminates. Revisit in P11 if the rule proves hard to hold. |
| Write semantics — **three rules, invisible in the generated Dart client** | **T9/T10** | `POST /cycle/events` = FULL UPSERT (omitted field CLEARS; single writer, small row). `POST /cycle/day/{date}` = **MERGE** (omitted field left unchanged; multi-writer row; no way to clear a field in P4a) — PO ruling 2026-08-10. `POST /checkin/quick` = partial by design (pain/mood only). **The deciding test is not the HTTP verb — it is how many surfaces write the row.** T11 decided `symptoms` = **FULL REPLACE** (id-addressed, single-writer, and *clearing is the affordance* — the classification fields are toggle chips, so merge would make `sharp` addable but never removable). **Consequence decided after T11's review (2026-08-10): the update is `PUT /symptoms/{id}`, NOT `PATCH`.** `POST` is semantically neutral so `POST`=upsert and `POST`=merge mislead nobody, but `PATCH` has a specific meaning that full replace *contradicts* — a client author who sends only the changed field gets silent data loss, so the verb is a safety affordance here. The alternative (keep `PATCH`, make it a true merge with explicit clears) needs a tri-state DTO the generated Dart client cannot express, so it is not a P4a option. **T12 owns the rename + the §C.3 amendment**; T21 regenerates the client once, so this is the last cheap moment. **T12 must also settle `side`:** screen 12 has no front/back control — its only path to `side` is a drill-in to screen 13 — so under full replace, editing a body-map-located row through screen 12 silently nulls `side` unless the client re-hydrates. State and TEST that client obligation, or scope the clear. **T22 owes all three rules as one table in `ARCHITECTURE.md §C`** — DTO XML docs do not survive into the generated client. |
| `CryptoShredJob` + `PiiRedactionEnricher` | **T8** (single ⚠ commit) | no other task edits the erasure path |
| Phase-wide tenant-isolation suite | **T19** | earlier tasks assert isolation only for their own resource |

### G13. Doc amendments that must land **in the same branch**, in the task that creates the thing

| Doc | Amendment | Task |
|---|---|---|
| `§A` | New P4a row: D-12 helper location; the P4a-wide 400/404 contract; the erasure change; sanity-bounds enforcement mode; **the C-03/C-04 PO-interim numbers recorded as P6 `ref_insight_rule` seed input, unsigned**; `rasrm_stage`/`diagnosed_on` write path | T22 (numbers), T2/T3/T8 (their own lines) |
| `§C.1` | add `POST /onboarding/cycle` (B15 — r17 flags the omission) and `GET /onboarding/state`; writes line gains `body_metrics`, `user_cycle_settings`, `user_goals`, `user_hormone_prefs`, `user_notification_prefs` | T18 (endpoints), T16/T17 (writes) |
| `§C.2` | add `DELETE /cycle/events/{id}`; Entities line gains `cycle_phase_overrides` | T9 |
| `§C.9` | add `POST /me/devices`; `PATCH /me` timezone/locale fields; ~~Entities line gains `user_cycle_settings`~~ **— the Entities line was DONE in T6 (its task text assigned it there); T14 MUST NOT repeat it** | T4 (`/me`) ✅, ~~T14~~ **T6 ✅** (entities), T15 (devices) |
| `§D` | `symptoms.occurred_on date`; `cycle_events.source`; `cycle_phase_overrides` (new, incl. its `source`); `user_cycle_settings`; `cycle_tracking_pause_spans`; `user_goals`; `user_hormone_prefs`; `user_notification_prefs`; `user_profile_enc` gains `endo_status_enc, rasrm_stage_enc, diagnosed_on_enc, height_cm_enc`; `body_metrics.measured_on` + its filtered unique key; `users.unit_system`; `user_insight_snapshot` corrections (`missing_data_cards_enc` is **`bytea`** not `jsonb`; `confidence` → `data_completeness`) | T5, T6, T7 |
| `§F` | erasure now physically deletes the plaintext clinical tables (§F:299's "unreadable, not deleted" predates them); flag privacy-policy wording for L-05/L-06 | T8 |
| `lumen-build.md` P5 entry | **strike `body_metrics`** from P5's task outline (r17: *"create it in P4a, strike from P5 in the phase branch"*) | T7 |

### G15. Coverage denominator — decided mid-phase after T9's review (2026-08-06)

P4a's exit criterion reads "global coverage ≥70%". **That is unreachable as literally written, and the arithmetic is settled, not a judgement call.** Measured across all three suites at T9:

| Scope | Lines | Coverage |
|---|---|---|
| All `backend/src` | 2663/6283 | **42.4%** |
| Migrations + `LumenDbContextModelSnapshot` | 809/4340 | 18.6% — **69.1% of all instrumented lines** |
| Excluding migrations/snapshot | 1854/1943 | **95.4%** |

§G4 freezes the migration denominator at 4,340 generated lines for the rest of the phase, while hand-written source sits at 95.4%. Break-even at 70% would require hand-written `backend/src` to grow from 1,943 lines to **~8,916 — 4.6×**. Eight more endpoint tasks of T9's size land the global figure near 50–55%.

**Decision: exclude `**/Migrations/**` and `LumenDbContextModelSnapshot.cs` from the coverage denominator; the ≥70% criterion is measured against hand-written `backend/src`.** This mirrors the client precedent exactly — P3a excluded `lib/api/**` + `*.g.dart` via the committed `client/tool/check_coverage.dart`, after a review caught a coverage-glob bug that under-excluded nested generated files and reported 58.6% against a true 97.60%. Generated code that no test authors and no reviewer reads does not belong in a quality gate.

**T20 owns implementing this**: apply the exclusion deterministically (by path, not a fragile glob — see the P3a bug), report BOTH figures in the STATUS block, and record the exclusion in the phase's exit-criteria tick so a later reader does not mistake 95% for whole-tree coverage.

### G14. Scope boundaries

Backend only — no Flutter screens (P4b); the regenerated Dart client is the only client-side artifact. `user_devices` already exists (migration `20260614150634`) — P4a owes only the upsert endpoint, **no migration for that table**. No labs, no reports, no notification dispatch, no medication catalog.

---

## Tasks

*22 tasks, strictly serial. **[UNIT]** needs no docker; **[LIVE]** needs `docker compose -f deploy/docker-compose.yml up -d postgres vault vault-init keycloak` plus migrations applied.*

---

### T1 — Provider & codegen spike (four unknowns settled before any schema is written)

- **Goal:** kill the four assumptions that would otherwise force a rewrite of an earlier task from a later one. All four are cheap to answer now and ruinous to answer at T21.
- **Tests first:** n/a — this is a throwaway spike on a scratch branch; nothing under `backend/src` or `client/` is committed.
- **Production changes:** none. Run the four probes:
  1. **`format: date` → Dart.** Add one `DateOnly` property to a scratch DTO, regen the contract, run the `client/lib/api/README.md` recipe + `dart run build_runner build --delete-conflicting-outputs`. Confirm it compiles as `Date`. (`client/lib/api/date_serializer.dart` exists and `..add(const DateSerializer())` is already at `client/lib/api/serializers.dart:33`, so this is expected to pass — but every P4a endpoint is date-keyed, so an unverified assumption here would rewrite T9–T18's DTOs and validators at the end of the phase.)
  2. **`List<string>` primitive collection.** Round-trips through `EnsureCreated()` on SQLite **and** produces `text[]` in an Npgsql migration.
  3. **Dialect-neutral CHECK.** `"Pain" >= 0 AND "Pain" <= 10` is created and enforced on both SQLite (`EnsureCreated`) and Postgres.
  4. **Filtered unique index.** `HasFilter("\"DeletedAt\" IS NULL\"")` is emitted **and enforced** by the SQLite provider (T6's "second open span rejected" and T7's "second live `weight_kg` blocked" assertions are meaningless otherwise).
- **LiveStack?** Postgres only (probes 2–4). No Keycloak/Vault needed.
- **Deliverable:** append a **"T1 spike verdicts"** block to the P4a STATUS section of `docs/superpowers/plans/lumen-build.md` with the four answers and, for any failure, the sanctioned fallback (probe 1 → `string` DTO properties + `DateOnly.ParseExact(…, "yyyy-MM-dd", CultureInfo.InvariantCulture)` applied uniformly to **every** P4a date field, decided **now**; probe 2 → `jsonb` + a `ValueComparer` converter and a same-branch `docs(arch)` note on §D's `pain_types[]`).
- **Commit:** `docs(plan): record the P4a provider and codegen spike verdicts`

---

### T2 — Shared user-local day helper (D-12)

- **Goal:** one helper decides "today", the backdate floor and day↔instant conversion from `users.timezone`, so no endpoint re-derives a day boundary. Nothing else in P4a can be validated correctly without it.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Time/UserDayResolverTests.cs` — `2026-08-06T22:30:00Z` → `2026-08-07` for `Europe/Madrid`; `2026-08-06T02:30:00Z` → `2026-08-05` for `America/Los_Angeles`; `Pacific/Kiritimati` (+14) and `Pacific/Niue` (−11) disagree on the same instant. DST: `Europe/Madrid` 2026-03-29 spring-forward still yields exactly one calendar day, `StartOfUserDay` never throws on the gap, fall-back ambiguity resolves to the **earliest** instant. `Unknown_timezone_falls_back_to_Europe_Madrid`; `Blank_timezone_falls_back_to_Europe_Madrid`; the log message contains neither the offending id nor a GUID.
  - `backend/tests/Lumen.UnitTests/Time/UserDayContextTests.cs` (SQLite + `FixedTimeProvider`) — **this is where the load-bearing behaviour lives**: a live user → populated `UserDayInfo`; a **soft-deleted** user → `null` (proving the query filter is honoured — no `IgnoreQueryFilters()` here); a missing user → `null`; two calls in one scope issue **one** query; `BackdateFloor` = the user-local day of `CreatedAt` minus 2 years incl. the 29-Feb clamp, computed in the user's tz not UTC.
  - Uses a hand-rolled `internal sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider` — **do not add a `FakeTimeProvider` package** (NuGet audit + `-warnaserror`).
- **Production changes**
  - `backend/src/Lumen.Application/Time/IUserDayResolver.cs` — `DateOnly TodayFor(string tz)`, `DateOnly ToUserDay(DateTimeOffset instant, string tz)`, `DateTimeOffset StartOfUserDay(DateOnly day, string tz)`, `DateTimeOffset EndOfUserDayExclusive(DateOnly day, string tz)`. BCL only (NetArchTest facts 3–4).
  - `backend/src/Lumen.Infrastructure/Time/UserDayResolver.cs` — `sealed class UserDayResolver(TimeProvider clock, ILogger<UserDayResolver> logger) : IUserDayResolver`; `ConcurrentDictionary<string,TimeZoneInfo>` cache; unknown/blank id → fall back to `Europe/Madrid` (the `User.Timezone` default) with a **PII-free** warning; `StartOfUserDay` handles `IsInvalidTime` (advance) and picks the earliest instant on ambiguity.
  - `backend/src/Lumen.Api/Time/IUserDayContext.cs` + `UserDayContext.cs` — request-scoped, memoises **one** `db.Users.AsNoTracking()` read per scope, returns `UserDayInfo?(UserId, Today, BackdateFloor, TimezoneId, NowUtc)`; `null` when the `sub` has no live `users` row ⇒ **every P4a endpoint returns 404** (this is the crypto-shredded-token contract). `BackdateFloor` XML doc states §G8: **cycle-events only**.
  - `Program.cs`: `AddSingleton<IUserDayResolver, UserDayResolver>();` `AddScoped<IUserDayContext, UserDayContext>();`
- **LiveStack?** No — **[UNIT]**.
- **Commit:** `feat(time): add the shared per-user day-boundary helper (D-12)`

---

### T3 — The P4a validation + ProblemDetails contract

- **Goal:** one 400 body, one 404 body, one shared message vocabulary, and malformed input can never surface as a 500.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Validation/ValidationProblemBuilderTests.cs` — two messages under one key aggregate into one array; camelCase keys survive; the `request` key; `Build()` shape; every **constant** asserted verbatim, and the **parameterised methods asserted at fixed arguments** (`Between(10, 120)` == `"value must be between 10 and 120"`, `MaxLength(2000)` == `"text exceeds the maximum length of 2000 characters"`).
  - `backend/tests/Lumen.UnitTests/Api/ProblemExceptionHandlerTests.cs` — `BadHttpRequestException` → **400** `application/problem+json` with `errors.request`, **not** 500; `DuplicateUserException` → 409 and `IdentityProviderException` → 502 unchanged; the 400 body does not contain the exception message.
- **Production changes**
  - `backend/src/Lumen.Api/Validation/ValidationMessages.cs` — `RequestDetail = "The request contained invalid data."` (the exact string the shipped `client/lib/core/error/error_mapper.dart` falls back to). **Shared constants:** `Required` = `value is required`, `NotAllowedValue` = `value is not one of the allowed values`, `NotNegative` = `value must be 0 or greater`, `FutureDate` = `date must not be in the future`, `BeforeFloor` = `date is before the earliest allowed date`, `NotAnIanaTimeZone` = `value is not a recognized IANA time zone`, `MalformedRequest` = `the request body or parameters could not be read`. **Parameterised methods** (not constants): `Between(min,max)`, `MaxLength(n)`.
  - **Ownership is the shape, not every string.** Endpoint-specific messages (`at least one of pain, mood or notes is required`, `cycleStartOn must match a logged period start`, `provide at least one baseline field`, `select at least one goal`, `pushToken and platform must be provided together`) are declared and asserted verbatim in their own task. No task invents a new error **body**.
  - `backend/src/Lumen.Api/Validation/ValidationProblemBuilder.cs` — accumulates `field → string[]`; **all** field errors collected before any write (validate-then-act); keys are the **camelCase JSON field name** (`avgCycleLengthDays`, `boundaries[0].occurredOn`), with `request` reserved for cross-field errors; `Build()` feeds `Results.ValidationProblem(errors, detail: ValidationMessages.RequestDetail)`.
  - `backend/src/Lumen.Api/ProblemExceptionHandler.cs` — new first arm `BadHttpRequestException => (400, "Validation failed.")` with `Extensions["errors"] = { ["request"] = [MalformedRequest] }`. **Never echo `exception.Message`** (it can quote request content — §F).
  - `Program.cs` — `builder.Services.Configure<RouteHandlerOptions>(o => o.ThrowOnBadRequest = true);`.
  - Convention in the commit body: 404 is always `TypedResults.Problem(statusCode: 404, title: "The requested resource was not found.")`, and **tenant isolation is 404, never 403** (403 would confirm the id exists).
- **LiveStack?** No — **[UNIT]**.
- **Commit:** `feat(api): add the P4a validation problem contract and stop binding failures becoming 500s`

---

### T4 — Align the spine to the P4a contract (r13), extract the onboarding feature folder, make `users.timezone` mutable

- **Goal:** discharge *"onboarding-validation ProblemDetails alignment (r13)"*, kill the untyped `{}` response schema, close the D-12 hole where a stale `users.timezone` mis-files every day-keyed write, and land the feature-folder move **here** — where the handler is already being rewritten line by line — instead of re-touching it in a later feature task.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Onboarding/OnboardingServiceTests.cs` — extend: every existing `Invalid` case also asserts `.Field`; new `Unknown_timezone_is_rejected` (`"Mars/Olympus"`), `Valid_iana_timezone_is_accepted`, **`Null_timezone_is_accepted`** and `Null_locale_is_accepted`.
  - `backend/tests/Lumen.IntegrationTests/OpenApiContractTests.cs` — `/onboarding/start` 200 is `$ref: OnboardingStartResponse` (not `{}`); its 400 references the validation-problem schema; `/me` documents 404. Both OpenAPI test classes re-run as proof the **move** changed nothing (path, `.AllowAnonymous()`, `.RequireRateLimiting("onboarding-start")` all preserved).
- **Production changes**
  - **Extraction (no behaviour change):** `backend/src/Lumen.Api/Onboarding/OnboardingEndpoints.cs` with `MapOnboardingEndpoints()`; `OnboardingStartRequest` moves verbatim into `Onboarding/OnboardingContracts.cs` (**no `namespace` declaration** — the global namespace and therefore the schema name must be preserved).
  - `Onboarding/OnboardingStartResult.cs` — `Invalid(string Error)` → `Invalid(string Field, string Error)`.
  - `Onboarding/OnboardingService.cs` — assign field keys. **The four existing message strings are GRANDFATHERED and stay byte-identical** (nine pinned `.Error.ShouldBe(...)` assertions read them verbatim): `"email and password are required"` → `request`; `"invalid email format"` → `email`; `"password must be between 12 and 128 characters"` → `password`; `"a field exceeds its maximum length"` → `request`. `ValidationMessages` governs every message introduced from T9 onward. **Add** IANA validation of `Timezone` → `timezone` / `NotAnIanaTimeZone`.
  - **Null/absent `Timezone` and `Locale` remain valid and fall back to the existing column defaults**; only a non-null value that `TimeZoneInfo.TryFindSystemTimeZoneById` rejects is a 400. Same rule on `PATCH /me`.
  - `Program.cs` — `/onboarding/start`: `Results.BadRequest(new { error })` → `Results.ValidationProblem(...)`, `.ProducesProblem(400)` → `.ProducesValidationProblem()`, `Results.Ok(new { userId })` → `Results.Ok(new OnboardingStartResponse(...))` + `.Produces<OnboardingStartResponse>(200)`. `GET /me`: bare `Results.NotFound()` → the T3 404 problem + `.ProducesProblem(404)`. `PATCH /me`: `UpdateMeRequest` gains optional `Timezone` (IANA) and `Locale` (BCP-47, ≤ 35 chars per the column).
  - Both JSON snapshots regenerated (§G3). `ARCHITECTURE.md §C.9` amended for the `PATCH /me` fields.
- **LiveStack?** No — **[UNIT]** + contract regen.
- **Commit:** `refactor(api): align onboarding-start and /me with the P4a problem contract (r13)`

---

### T5 — Cycle and symptom logging tables + migration 1/3

- **Goal:** the four observation tables, their frozen vocabularies and their indexes — nothing else. All cycle/symptom tables land here so T8 covers the phase's plaintext health data in one pass.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Persistence/SymptomSqliteModelTests.cs` — **first**: `EnsureCreated()` on SQLite, insert `PainTypes=["cramping","sharp"]` / `Triggers=["stress"]`, round-trip both. (T1 probe 2 already answered this; the test pins it.)
  - `backend/tests/Lumen.UnitTests/Persistence/CycleModelTests.cs` — CHECK enforcement (`Pain=11`, `Mood=5`, `Intensity=-1`, `FlowIntensity=5` each throw `DbUpdateException`; **`Pain=0` and `Intensity=0` succeed**); the unique indexes exist and are **unfiltered** on `cycle_events`/`cycle_day_logs` (§G9); **the onboarding-seed merge rule** (below) has its own case: a live `(UserId, period_start, D)` row exists ⇒ moving the onboarding row onto `D` adopts/revives that row rather than violating the index; a **tombstoned** row on `D` is revived, never duplicated.
  - `backend/tests/Lumen.UnitTests/Persistence/VocabularyTests.cs` — pins counts **and exact members** per §G10: 3 kinds, 2 sources, 4 flow levels, 4 moods, 21 symptom codes, 9 regions, 2 sides (**`front`/`back`**), 6 pain types, 7 triggers, 4 phases, 2 boundaries, 1 override source.
  - `ModelSyncTests` and every `OnboardingServiceTests` case stay green (they build the whole model on SQLite).
- **Production changes**
  - `Lumen.Domain/Entities/CycleEvent.cs` — `Id, UserId, Kind varchar(16), OccurredOn date, FlowIntensity smallint?, NotesEnc bytea?, Source varchar(16), CreatedAt, UpdatedAt, DeletedAt`. Nested `Kinds`, `Sources {user, onboarding}` (**P4a-proposed vocabulary, §G11**; `auto_detected` is deliberately **not** reserved — the enum is append-only, so pre-reserving an unsigned C-04 concept buys nothing), `FlowIntensityScale {Min=1,Max=4}` with an XML doc marking it **C-04 PO-interim, clinician sign-off pending**. **XML doc pins the onboarding-seed merge rule** consumed by T18: the seed row is found by `(UserId, Kind=period_start, Source=onboarding)` under `IgnoreQueryFilters()`; before moving it, look up `(UserId, Kind, targetDay)` under `IgnoreQueryFilters()` and, if a row exists, **adopt/revive it** (clear `DeletedAt`, keep its existing `Source` and `CreatedAt`) and retire the stale onboarding row — never two rows, never an index violation.
  - `CycleDayLog.cs` — `Id, UserId, Day date, Pain smallint?, Mood smallint?, Energy smallint?, Libido smallint?, NotesEnc, CreatedAt, UpdatedAt, DeletedAt`. `PainScale 0..10` (D-08; **0 is a real datum**), `MoodScale 1..4`. `Energy`/`Libido` exist per §D but are **reserved** (D-10 defers the scales): no CHECK, no DTO, no writer in P4a.
  - `Symptom.cs` — `Id, UserId, SymptomCode varchar(32), Intensity smallint, Region varchar(32) default 'unspecified', Side varchar(8)?, PainTypes List<string>, Triggers List<string>, OccurredAt timestamptz, OccurredOn date, NotesEnc, CreatedAt, UpdatedAt, DeletedAt` + the §G10 vocabularies verbatim. `OccurredOn` is the user-local day of `OccurredAt` computed at write time (D-12) — **never client-supplied**.
  - `CyclePhaseOverride.cs` — `Id, UserId, CycleStartOn date, Phase varchar(16), Boundary varchar(8), OccurredOn date, Source varchar(24), CreatedAt, UpdatedAt, DeletedAt`; `Phases` = the four §G10 codes (**codes only — P4a encodes no ordering; the C-01 band sequence is clinician-unsigned and belongs to P6**), `Boundaries {start, end}`, `Sources {user_correction}`. UNIQUE `(UserId, CycleStartOn, Phase, Boundary)` + index `(UserId, CycleStartOn)`. XML doc states the P6 consumption contract: P6 computes its C-01 bands, then replaces any computed boundary that has a live override row; overridden cycles are flagged for the C-05/C-09 confidence path. No column changes meaning at P6.
  - `LumenDbContext.cs` — 4 `DbSet`s + 4 `OnModelCreating` blocks. snake_case tables, **PascalCase columns** (no naming convention — do not introduce one). Indexes per §G9 plus `(UserId, OccurredOn)` on events and `(UserId, OccurredOn, OccurredAt)` on symptoms. `HasQueryFilter(x => x.DeletedAt == null)` on all four. CHECKs for the **frozen** scales only: `Pain 0..10`, `Mood 1..4`, `FlowIntensity 1..4`, `Intensity 0..10`; **no CHECK on Energy/Libido**, **no CHECK on vocabulary membership**. `PainTypes`/`Triggers`: `.IsRequired()` only — no `HasColumnType("text[]")` (the literal leaks into SQLite's `CREATE TABLE`), no DB default (`= []` in the CLR covers it).
  - Migration `AddCycleAndSymptomTables`. `ARCHITECTURE.md §D` amended: `symptoms.occurred_on`, `cycle_events.source`, `cycle_phase_overrides` (new table, incl. its P4a-proposed `source` vocabulary); `§C.2` Entities line gains `cycle_phase_overrides`.
- **LiveStack?** No — **[UNIT]**.
- **Commit:** `feat(domain): add cycle_events, cycle_day_logs, symptoms and cycle_phase_overrides`

---

### T6 — Cycle settings, pause spans and onboarding-preference tables + migration 2/3

- **Goal:** the settings/preferences storage that both the settings endpoints and four onboarding steps write.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Persistence/CycleSettingsModelTests.cs` — every DB default asserted individually; the structural CHECK rejects `0` and accepts `200` and `365` (**§G7 — there is no upper clinical bound in DDL**); the partial unique index rejects a second **open** span for one user but allows a second **closed** span.
  - `VocabularyTests` extended: 3 regularities, **5** pause reasons, 5 goals, 7 hormones, 4 categories, `DefaultSelected == [manage_symptoms, understand_hormones]`, `DefaultEnabled == [daily_checkin, phase_shift]`, and the **B16 label map** (`estradiol`→"Estrogen", `glp1`→"GLP-1", `phase_shift`→"Phase shift").
- **Production changes**
  - `UserCycleSettings.cs` — PK `UserId` (1:1 like `user_keys`/`user_profile_enc`; **not** columns on `users`, **not** on the all-ciphertext `user_profile_enc`). `AvgCycleLengthDays smallint NOT NULL default 28` (`definitions.md:71`), `AvgPeriodLengthDays smallint NULL` (**no default — screen 3 never collects it; do not invent 5**), `Regularity varchar(16) NOT NULL default 'somewhat'`, `PhasePredictionEnabled bool default true`, `AutoDetectPeriodStartEnabled bool default true`, `ShowFertilityWindowEnabled bool default false`, `TrackingPaused bool default false`, `PauseReason varchar(32) NULL`, `PausedSince date NULL`, `CreatedAt`, `UpdatedAt`. Nested `RegularityValues` + `PauseReasons` (the **five**-member C-12 set — `ARCHITECTURE.md:59` is authoritative; the r15 rider said 3). **No `DeletedAt`** (D-13 governs entries, not a per-user singleton). **No `first_day_of_week`** (D-05: derived from `users.locale` via ICU) and **no `regularity_variability_days`** (C-05 computed output, P6).
  - `CycleTrackingPauseSpan.cs` — `Id, UserId, Reason varchar(32), StartedOn date, EndedOn date?, CreatedAt, UpdatedAt`; index `(UserId, StartedOn)` + **partial UNIQUE on `UserId WHERE "EndedOn" IS NULL`** (at most one open pause). Required by `ARCHITECTURE.md:59` *"paused spans excluded from estimators"* — the three settings fields describe only the current pause, so without this table every pre-P6 span is lost forever (OQ-2).
  - `UserGoal.cs` / `UserHormonePref.cs` / `UserNotificationPref.cs` — `Id, UserId, <Code> varchar(32), <Selected|Charted|Enabled> bool, CreatedAt, UpdatedAt`, UNIQUE `(UserId, Code)`, cascade FK, **no `DeletedAt`** (a tombstone would block re-selecting). Codes per §G10.
  - `Lumen.Domain/Reference/HormoneCatalog.cs` — the **B16 shared constants file**: the 7 code↔display-label pairs, the 4 notification category codes and their canonical labels, and the CLAUDE.md hormone colour per code. **No `ref_hormone` table in P4a** — the remaining B16 columns (`display_unit`, `category`) depend on **C-07, which is clinician-UNSIGNED**, so seeding them here would bake unsigned clinical values into reference data (§G5/§G7). The deferral to P7b is recorded in T22 and in the `§A` P4a row (OQ-9).
  - **No `Lumen.Domain/Clinical/` namespace and no `CycleEstimatorParams.cs`.** §G7: those numbers have no lawful home in `backend/src` this phase.
  - `LumenDbContext.cs` — 5 `DbSet`s (name the settings one `CycleSettings`, not `UserCycleSettings`, to avoid property/type shadowing) + config. Structural CHECKs only: `"AvgCycleLengthDays" > 0`, `"AvgPeriodLengthDays" IS NULL OR "AvgPeriodLengthDays" > 0`. **No CHECK tying `PauseReason` to `TrackingPaused`** (resume must preserve the last reason).
  - Migration `AddCycleSettingsPauseSpansAndPreferences`. `§D` amended with the four new tables; `§C.9` Entities line gains `user_cycle_settings`.
- **LiveStack?** No — **[UNIT]**.
- **Commit:** `feat(domain): add cycle settings, pause spans and onboarding preference tables`

---

### T7 — Profile condition columns, `body_metrics`, the non-clinical insight-snapshot placeholder + migration 3/3

- **Goal:** the rider-4 profile bundle, the one metric row onboarding seeds, a snapshot table that cannot be mistaken for clinical output, and the D-06 reserved column.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Persistence/BodyMetricModelTests.cs` — the **filtered** unique index (§G9) blocks a second live `weight_kg` row on the same `MeasuredOn` but allows one after the first is tombstoned; `ComputedBy` defaults to `placeholder`; `DataCompleteness = 101` is rejected; `UnitSystem` defaults to `metric`.
  - `backend/tests/Lumen.UnitTests/Body/WeightEncodingTests.cs` — `60.4` round-trips through the canonical encoder under `es-ES`, `de-DE` and `en-US` `CurrentCulture` (the regression this helper exists to prevent).
  - `backend/tests/Lumen.UnitTests/Architecture/ArchitectureTests.cs` — **new 5th fact:** no `Lumen.Api` type may depend on `UserInsightSnapshot`. This is what makes "no read endpoint" (§G6) build-enforced. **Prove it red**: after the entity exists, temporarily reference it from a `Lumen.Api` file, watch the fact fail, revert — note the demonstration in the commit body. Add a companion assertion that `typeof(UserInsightSnapshot)` resolves, so a rename cannot leave a vacuously-green guard.
  - `backend/tests/Lumen.IntegrationTests/SchemaSmokeLiveTests.cs` **[LIVE]** — all **eleven** new tables are queryable in the live Postgres (`cycle_events`, `cycle_day_logs`, `symptoms`, `cycle_phase_overrides`, `user_cycle_settings`, `cycle_tracking_pause_spans`, `user_goals`, `user_hormone_prefs`, `user_notification_prefs`, `body_metrics`, `user_insight_snapshot`). `ModelSyncTests` passes with no DB, so an unapplied or broken migration otherwise surfaces only as opaque failures much later (and `user_insight_snapshot` has no endpoint at all — this is the **only** thing that proves it exists).
- **Production changes**
  - `UserProfileEnc.cs` — four new **encrypted** columns: `EndoStatusEnc`, `RasrmStageEnc`, `DiagnosedOnEnc`, `HeightCmEnc` (all `byte[]?`). Canonical plaintext documented per property: the endo-status code, `"1".."4"`, `"yyyy-MM"`, invariant-culture integer cm. Encrypted rather than plaintext because none is ever a SQL predicate/sort/aggregate (C-14: rASRM *"does NOT correlate with pain, never inferred"*), BMI can never be computed in SQL anyway (weight is already `body_metrics.ValueEnc`), and a new plaintext quasi-identifier would have to join the shred blanking list. Nested `EndoStatuses` constants. **No surgeries** (C-14, unsigned). **No weight here** (rider 4: one source of truth). **All four get a write path in T16** — no dead columns.
  - `BodyMetric.cs` — `Id, UserId, Metric varchar(24), ValueEnc bytea, Source varchar(16) default 'manual', MeasuredAt timestamptz, MeasuredOn date, CreatedAt, UpdatedAt, DeletedAt`; UNIQUE `(UserId, Metric, MeasuredOn)` **filtered on `DeletedAt IS NULL`** with the §G9 rationale on the entity. `Metrics` defines **only** `WeightKg = "weight_kg"` (freezing `body_fat_pct`/`waist_cm` would pre-empt D-15/P5); nested `Sources { Manual, AppleHealth, GoogleFit }` per §D:188 so P5's sync work has a committed value to write. One documented canonical encoder: `value.ToString(CultureInfo.InvariantCulture)` / `decimal.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture)`.
  - `UserInsightSnapshot.cs` — PK `UserId`; `CurrentPhase varchar(16)?` (validated against **the same four §G10 codes** — codes only, no ordering, no writer in P4a), `PhaseStart date?`, `DataCompleteness smallint?` CHECK 0..100 (§A/C-09 renames §D's `confidence`), `MissingDataCardsEnc bytea?` (**not `jsonb`** — §D:171 *"'Enc' columns are bytea"* wins; AES-GCM cannot live in `jsonb`), `ComputedBy varchar(24) NOT NULL default 'placeholder'`, `RefreshedAt?`, `CreatedAt`, `UpdatedAt`. **P4a inserts zero rows and exposes no read endpoint.**
  - `User.cs` — `UnitSystem varchar(8) NOT NULL default 'metric'` (**D-06 reserved**, no endpoint, no write path; a single-valued preference, so it is *not* a quasi-identifier and does **not** join the shred blanking list). Recorded as reserved in T22.
  - `LumenDbContext.cs` + migration `AddProfileConditionsBodyMetricsAndInsightSnapshot`.
  - **Docs:** `§D` gains the four `user_profile_enc` columns, `body_metrics.measured_on` + the filtered unique key, `users.unit_system`, and the snapshot corrections. **`docs/superpowers/plans/lumen-build.md`: strike `body_metrics` from P5's task outline and note it landed in P4a** (r17 instruction — otherwise P5 re-plans a shipped table).
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]** (schema smoke).
- **Commit:** `feat(domain): add profile condition columns, body_metrics and the placeholder insight snapshot`

---

### T8 ⚠ — Erasure completeness: crypto-shred deletes the new plaintext health rows; the PII enricher learns the new field names

- **Goal:** P4a is the first phase to persist **special-category health data in PLAINTEXT** (symptom codes/regions/intensities, flow intensity, pain/mood ordinals, `pause_reason='pregnancy'`, `goal_code='plan_fertility'`, metric codes). Deleting `user_keys` only makes *ciphertext* unreadable, and the cascade FKs never fire because the job **tombstones** the `users` row. Without this task `DELETE /me` leaves a fully readable symptom/cycle/pregnancy history in Postgres and in every nightly `pg_dump`.
- **⚠ Treatment:** this commit touches the P2 safety-critical erasure path — scoped `/code-review high`, called out for the human reviewer. See **OQ-1**.
- **Tests first**
  - `backend/tests/Lumen.SecurityTests/GdprErasureBaselineTests.cs` — after the job, **zero rows** for that user in every one of the eleven new tables (queried with `IgnoreQueryFilters()`); a note ciphertext written before the shred is undecryptable; `consent_records` and `admin_audit_log` survive. Duplicate any needed helper into `SecurityTestFixtures` — test projects must not reference each other.
  - `backend/tests/Lumen.UnitTests/Logging/PiiRedactionEnricherTests.cs` — one case per new name; a `RequestPath` property containing a date-keyed path is not emitted raw.
- **Production changes**
  - `Lumen.Infrastructure/Jobs/CryptoShredJob.cs` — inside the existing transaction, immediately after the `user_devices` delete (the precedent: plaintext rows are deleted, not made unreadable), `ExecuteDeleteAsync` for all eleven tables: `Symptoms`, `CycleDayLogs`, `CycleEvents`, `CyclePhaseOverrides`, `BodyMetrics` (**`IgnoreQueryFilters()` is mandatory on these five soft-deleted tables** or tombstoned entries survive erasure), then `UserInsightSnapshots`, `UserGoals`, `UserHormonePrefs`, `UserNotificationPrefs`, `CycleTrackingPauseSpans`, `CycleSettings`. §G4 guarantees this list is complete and stays complete.
  - `Lumen.Infrastructure/Logging/PiiRedactionEnricher.cs` — extend `SensitiveNames` with `notes`, `note`, `notesEnc`, `symptomCode`, `painTypes`, `triggers`, `region`, `side`, `intensity`, `pain`, `mood`, `energy`, `libido`, `flowIntensity`, `entries`, `endoStatus`, `rasrmStage`, `diagnosedOn`, `heightCm`, `weightKg`, `pauseReason`, `lastPeriodStart`, `goals`, plus the P3c deferrals now in scope: `token`, `refreshToken`, `idToken`, `authorization`, `secret`, `dek`.
  - `Program.cs` — `UseSerilogRequestLogging` gains `EnrichDiagnosticContext` logging the **route template** (`/cycle/day/{date}`), never the raw path (`/cycle/day/2026-08-06` is a health-adjacent fact). §F:303's "never log request bodies for cycle/symptoms/day-logs" stands unchanged.
  - `ARCHITECTURE.md §F` — record that erasure now physically deletes the plaintext clinical tables; flag the privacy-policy wording for L-05/L-06.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]** (security suite).
- **Commit:** `fix(security): erase P4a plaintext health rows on crypto-shred and redact their field names`

---

### T9 — Cycle events + phase corrections: `POST /cycle/events`, `DELETE /cycle/events/{id}`, `POST /cycle/phase-override`

- **Goal:** the write surface anchored on `cycle_events`, including the one row (`period_start`) whose corruption is unrecoverable and cross-phase. **Endpoints only — the tables landed in T5, and §G4 forbids a migration here.**
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Cycle/CycleEventServiceTests.cs` (SQLite + real `AesGcmFieldCipher` + fixed clock) — unknown kind; future date; **pre-floor date rejected (this is the one place §G8's floor applies)**; flow 0 and 5 rejected, null accepted on every kind; notes 2000 ok / 2001 rejected; same `(kind, day)` twice → **one** row with `CreatedAt` preserved and `UpdatedAt` advanced; a soft-deleted row is **revived**, not duplicated; delete then re-post creates/revives one row.
  - `backend/tests/Lumen.UnitTests/Cycle/CyclePhaseOverrideServiceTests.cs` — `cycleStartOn` with no live logged `period_start` → `cycleStartOn must match a logged period start`; a boundary before `cycleStartOn`, after today, or at/after the next logged `period_start` rejected; **out-of-order boundaries are ACCEPTED** (P4a encodes no phase ordering — §G10); duplicate `(phase, boundary)` rejected; empty `boundaries` soft-deletes the set; re-saving revives the **same `Id`**.
  - `backend/tests/Lumen.IntegrationTests/CycleEventsLiveTests.cs` **[LIVE]** — note stored as ciphertext (`Encoding.UTF8.GetString(row.NotesEnc!).ShouldNotContain("dolor")`, length ≥ 28) and re-post rotates the ciphertext; 400 is `application/problem+json` with the exact `errors.occurredOn` message; tenant isolation for **this resource** (B's `DELETE` on A's id → 404 **and** A's row still has `DeletedAt == null`); all three routes without a bearer → 401; a crypto-shredded user's token → 404.
  - **Coverage checkpoint (no gate):** run the §T20 coverage command and paste the number in the commit body. First of two trajectory data points.
- **Production changes**
  - `Lumen.Api/Cycle/{CycleEndpoints,CycleService,CycleResults,CycleContracts}.cs`.
  - `POST /cycle/events` — **upsert on `(UserId, Kind, OccurredOn)`** under the §G9 unfiltered-index regime: `IgnoreQueryFilters()` lookup that revives tombstones (two `period_start` rows on one day is nonsense; idempotency makes the online-only client's retry safe). Validation: `Kind` ∈ the 3 codes; `OccurredOn <= Today` **and `>= BackdateFloor`**; `FlowIntensity` 1–4 **optional for every kind** (no cross-field clinical rule — `flow >= 2` qualification is C-04/P6); `Notes.Trim() <= 2000`. `Source = user` on insert; an existing `onboarding` row keeps its provenance. 200 with the decrypted note echoed back.
  - `DELETE /cycle/events/{id}` — soft-delete (`DeletedAt`/`UpdatedAt`), 204; second call 404 (the filter hides the tombstone; P4b treats that as success). D-13 mandates the capability and §C.2 has no DELETE — amend §C.2 (OQ-5).
  - `POST /cycle/phase-override` — replace-the-set for one cycle; `boundaries: []` = "Reset to predicted" (soft-delete the set). Guards are **structural only**: `cycleStartOn` must match a live logged `period_start`; each `occurredOn >= cycleStartOn`, `<= today`, and `<` the next logged `period_start`; no duplicate `(phase, boundary)`. **No monotonicity guard** — the menstrual→follicular→ovulatory→luteal sequence is the C-01 band order, clinician-unsigned, and rejecting a user's correction on that basis would be a clinical entry blocker in a phase that ships none (§G6/§G7). **No recompute is triggered** — screen 14's "retrains the prediction model" copy is a P6 promise.
  - `CyclePhaseAvailability` constants: `phase_engine_not_implemented` (P4a-only), plus `tracking_paused` / `insufficient_data` / `no_period_logged` reserved for P6.
  - `§C.2` amended (DELETE + `cycle_phase_overrides`). Both JSON snapshots regenerated.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(cycle): add cycle event write/delete and phase-correction endpoints`

---

### T10 — Cycle day: `POST /cycle/day/{date}`, `POST /checkin/quick`, `GET /cycle/day/{date}`

- **Goal:** the D-11 one-row-per-day upsert, reached from both the day-detail screen and the quick check-in, plus the single-day read.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Cycle/CycleDayServiceTests.cs` — empty payload → `errors.request` = `at least one of pain, mood or notes is required`; pain −1/11 rejected, **0 accepted**; mood 0/5 rejected; notes 2000/2001; a second post leaves the unsupplied field unchanged; a soft-deleted day is revived (exactly one row via `IgnoreQueryFilters()`); **future date rejected; a date before the account-creation floor is ACCEPTED (§G8 — the floor is cycle-events-only)**.
  - `backend/tests/Lumen.UnitTests/Symptoms/QuickCheckinServiceTests.cs` — pain-only, mood-only, both accepted; **neither → 400**; a second call updates the same row (count stays 1); **`Symptoms.Count == 0` after a quick check-in** (the D-11 assertion); the day is the user-local day for a `Pacific/Auckland` user.
  - `backend/tests/Lumen.UnitTests/Api/ConcurrencyRetryTests.cs` — the helper retries **exactly once** when the delegate throws `DbUpdateException` wrapping `PostgresException { SqlState: "23505" }` then succeeds; does **not** retry on a second 23505; does not retry any other exception. (No DB needed — the delegate is a fake.)
  - `backend/tests/Lumen.IntegrationTests/CycleDayLiveTests.cs` **[LIVE]** — ciphertext at rest + rotation on re-post; `GET` round-trips the decrypted note; tomorrow → 400 `errors.date[0] == "date must not be in the future"`; tenant isolation for this resource; 401 without bearer.
- **Production changes**
  - `Lumen.Api/Cycle/CycleDayService.cs` + endpoints in `CycleEndpoints.cs`; `QuickCheckinRequest/Response` live in `Symptoms/SymptomContracts.cs` per §C.3 module ownership but write **only** `cycle_day_logs`.
  - `Lumen.Api/Persistence/ConcurrencyRetry.cs` — `Task<T> ExecuteAsync(Func<CancellationToken, Task<T>> action, CancellationToken ct)`; one retry on `DbUpdateException` whose inner is `PostgresException { SqlState: "23505" }`. Extracted as a helper **precisely so the retry is testable without provoking a live race** — untested defensive code is not acceptable here.
  - `POST /cycle/day/{date}` — upsert on `(UserId, Day)` under the §G9 unfiltered regime (`IgnoreQueryFilters()` lookup, revive, never duplicate), wrapped in `ConcurrencyRetry`. **Merge semantics: absent/`null` = leave unchanged**; `System.Text.Json` cannot distinguish absent from null and `built_value` omits nulls, so **P4a ships no way to clear an individual field** — which matches the screens (no clear affordance on 9 or 11). Validate `date <= Today`, `>= 1` of `{pain, mood, notes}`, `pain` 0–10, `mood` 1–4, notes ≤ 2000. Always **200** (an upsert has no actionable created/updated distinction and §C.2 exposes no `GET /cycle/day-log/{id}` for a `Location`).
  - `POST /checkin/quick` — **no date in the payload**: the day is `Today` for the user's timezone (screen 9 is "How's today?"; D-11 says repeat check-ins update *today's* value; `POST /cycle/day/{date}` already owns explicit dates). `{pain?, mood?}`, **≥ 1 required**. Writes **no `symptoms` row** (D-11 modified) and never touches `Energy`/`Libido`/`NotesEnc`.
  - `GET /cycle/day/{date}` — 200 with `log: null` and empty arrays when nothing is logged (**404 is reserved for "no such user"**); decrypts the day-log and event notes; includes that day's live phase overrides. No range validation on read.
  - Both JSON snapshots regenerated.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(cycle): add the day-log upsert, quick check-in and single-day read`

---

### T11 — Symptoms create: `POST /symptoms` (batch)

- **Goal:** the §C.3 write surface, with classification always optional and no clinical bound anywhere near it. This is where the pinned messages and the vocabulary rules are established.
- **Tests first** — `backend/tests/Lumen.UnitTests/Symptoms/SymptomServiceTests.cs`
  - One case per validation row with the message asserted **verbatim**; defaults applied (`symptomCode ??= "pain"`, `region ??= "unspecified"`); dedup + canonical reorder of `painTypes`/`triggers`; empty arrays stored as `{}` never `NULL`; `occurredAt` normalised to offset 0; `intensity` 0 accepted, −1/11 rejected, absent rejected; wrong-cased code rejected (`StringComparer.Ordinal`, no fixups); `40000` reaches the validator (request numbers are `int?` not `short?`); **a date before the account-creation floor is ACCEPTED, a future local day is rejected (§G8)**; batch of 51 rejected; **one invalid entry rejects the whole batch and writes nothing**.
- **Production changes**
  - `Lumen.Api/Symptoms/{SymptomEndpoints,SymptomService,SymptomResult,SymptomContracts}.cs`.
  - `POST /symptoms` — **batch** `{ "entries": [...] }`, **1–50 entries (P4a-invented structural limit, §G11)**, all-or-nothing in one `SaveChangesAsync`, **201** + `CreateSymptomsResponse`, no `Location`. D-09 makes one user action multi-row (screen 12's single "Save symptom" writes the pain row **plus one row per RELATED chip**; screen 13's "Save body map" writes one row per placed point) and the client has no write queue, so N requests per save would leave half-recorded episodes. See **OQ-6**.
  - Per-entry normalisation, in order: `symptomCode ??= "pain"`; `region ??= "unspecified"`; blank `side` → null; `painTypes`/`triggers` de-duplicated and re-ordered into canonical vocabulary order (so P6 never sees order/duplicate noise), `null` → `[]`; `occurredAt?.ToUniversalTime() ?? now` (**mandatory** — Npgsql throws on a non-zero offset for `timestamptz`); `occurredOn` derived via `IUserDayResolver`; notes trimmed, empty → null, else encrypted.
  - Validation: `intensity` **required**, 0–10; vocabulary membership ordinal; notes ≤ 2000; no future `occurredAt` at **local-day** granularity; **no backdate floor**. **No cross-field rules** — pain types/triggers are accepted on any code.
  - Both JSON snapshots regenerated.
- **LiveStack?** No — **[UNIT]** (the live surface lands with T12's reads).
- **Commit:** `feat(symptoms): add the batch symptom create endpoint`

---

### T12 — Symptoms read/update/delete: `GET /symptoms`, `PUT /symptoms/{id}`, `DELETE /symptoms/{id}`

- **Goal:** the rest of §C.3, consuming T11's validator unchanged.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Symptoms/SymptomServiceTests.cs` extended — PATCH clear-sentinels (`""` clears `side`/`notes`, `[]` clears an array, `null` = unchanged, arrays replace never merge); PATCH cannot reach `symptomCode` (absent from the request record); an all-null patch is a **200 no-op** that still bumps `UpdatedAt`; `limit`/`offset` out of range → 400, never silently clamped.
  - `backend/tests/Lumen.IntegrationTests/SymptomsLiveTests.cs` **[LIVE]** — batch of 3 → 201/3 items; `GET` newest-first; ciphertext at rest; PATCH rotates the note ciphertext and leaves `symptomCode` untouched; DELETE → 204, second → 404, row gone from `items` **and** from `total`; `limit=2`/`offset=2` paging is stable when three rows share one `OccurredAt`; tenant isolation for this resource; 401 on all four routes.
  - **Coverage checkpoint (no gate):** second trajectory data point pasted in the commit body.
- **Production changes**
  - `GET /symptoms?from&to&limit&offset` — `from`/`to` **required**, inclusive user-local dates converted to UTC instants; future `to` allowed (a month view spans forward); D-13 pagination `limit` default 50 / min 1 / max 100, `offset >= 0`; `ORDER BY OccurredAt DESC, Id DESC` (the `Id` tiebreak keeps offset paging stable when a body-map save writes N rows at one instant); `total` from a matching `CountAsync`.
  - `PUT /symptoms/{id}` (renamed from `PATCH` — see the §G12 write-semantics row; §C.3 amended in the same commit) — replaces `intensity, region, side, painTypes, triggers, occurredAt, notes`. An omitted field with an *unclassified* state is CLEARED; `intensity` and `occurredAt` have none and are therefore REQUIRED, so an edit can never fabricate an observation time. **`symptomCode` is immutable by construction**: re-coding a `bloating` row into `pain` rewrites a P6 series' identity; the user action is delete + create. Re-encryption uses a fresh nonce.
  - `DELETE /symptoms/{id}` — soft-delete only (`DeletedAt`), **204**; never `ExecuteDeleteAsync`. Second call **404**.
  - Both JSON snapshots regenerated.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(symptoms): add symptom list, patch and soft-delete endpoints`

---

### T13 — `GET /cycle/calendar`

- **Goal:** the bounded sparse aggregation that renders screens 8/10 — a distinct piece of work from the day upsert, and it counts rows in all three observation tables, so it lands after them.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Cycle/CycleCalendarServiceTests.cs` — default window is the user-local current month; `to < from` → 400; a 367-day window → 400 (**P4a-invented limit, §G11**); future days inside the window are returned; days with no data are absent (sparse); a directly-tombstoned row is excluded.
  - `backend/tests/Lumen.IntegrationTests/CycleCalendarLiveTests.cs` **[LIVE]** — counts across day logs + events + symptoms for one user; **no note plaintext appears anywhere in the response**; `phase.available == false` with `unavailableReason == "phase_engine_not_implemented"` **and the JSON key `phase` is absent from every day row**; `today` matches the onboarded timezone; tenant isolation; 401 without bearer.
- **Production changes**
  - `GET /cycle/calendar?from&to` in `CycleEndpoints.cs` + `CycleCalendarService.cs` — both params optional, defaulting to the user-local current month; `to >= from`; **window ≤ 366 days** (a bounded date window, not the D-13 50/100 offset page — record that reading). Sparse day rows (`date, pain, mood, hasNotes, eventCount, symptomCount`); **no `*_enc` column is decrypted here**. Carries `today`, `timezone`, and `phase: { available: false, unavailableReason }`. **No per-day `phase`, no `cycleDay`, no `confidence` anywhere in the P4a contract** — P4b renders the unavailable state.
  - Both JSON snapshots regenerated.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(cycle): add the calendar aggregation endpoint`

---

### T14 — `GET`/`PATCH /settings/cycle` incl. the pause state machine

- **Goal:** the §C.9 cycle-settings resource with the C-12 pause rider — and the phase's behavioural proof that clinical bounds never block entry.
- **Tests first** — `backend/tests/Lumen.UnitTests/CycleSettings/CycleSettingsServiceTests.cs`
  - Every default asserted and **nothing persisted** by GET; `[Theory]` over all **five** pause reasons for pause→resume; `pauseReason` with `trackingPaused:false` → 400; unknown reason (`"lactation"`) → 400; span opened / updated-in-place / closed; the three invariants; the `phasesUnavailable` 2×2 truth table.
  - **§G7 proof:** `avgCycleLengthDays = 15` → 200, stored, `warnings` **EMPTY** (outside the clinical 21–45 band but inside the sanity band); `= 47` → 200, stored, `warnings` empty; `= 200` → 200, **stored**, one `avg_cycle_length_out_of_sanity_band` warning; `= 365` → 200, stored, one warning; `= 0` and `= -1` → 400 (structural only); **no request is rejected for being outside 10–120 or 21–45**.
  - `ApplyOnboardingCycleAsync` has its **own** unit case here (creates-or-updates applying the T6 defaults for omitted values, no `PauseReason` side effects) so T18 only tests endpoint wiring.
  - **Paused ⇒ entry is never blocked** (C-12's other half, untested until now): with `trackingPaused = true`, a `POST /cycle/events`, a `POST /cycle/day/{date}`, a `POST /checkin/quick` and a `POST /symptoms` all still succeed and persist rows.
  - `backend/tests/Lumen.IntegrationTests/CycleSettingsLiveTests.cs` **[LIVE]** — only one open span survives a double pause; tenant isolation; 401 without bearer.
- **Production changes**
  - `Lumen.Api/CycleSettings/{CycleSettingsEndpoints,CycleSettingsService,CycleSettingsResult,CycleSettingsContracts}.cs`.
  - `GET /settings/cycle` — returns the T6 defaults **without persisting anything** when no row exists. Never 404 for "no row".
  - `PATCH /settings/cycle` — upsert (`FirstOrDefaultAsync` → create-or-update → one `SaveChangesAsync`), returns **200 + the full resource** (not 204 like `PATCH /me`, because the body carries the warnings and derived flags the online-only client would otherwise re-fetch). `null` = leave unchanged.
  - **`ApplyOnboardingCycleAsync(Guid userId, DateOnly lastPeriodStart, short? avgCycle, short? avgPeriod, string? regularity, DateTimeOffset now, CancellationToken ct)`** — creates-or-updates the row applying the T6 defaults (28 / null / `somewhat`) for omitted values; shared with T18; no `PauseReason` side effects.
  - **One derived, non-persisted, non-inferential boolean:** `phasesUnavailable = trackingPaused || !phasePredictionEnabled` — the explicit "phases unavailable" state `ARCHITECTURE.md:59` requires; a boolean OR of two stored flags, no engine. **`hormoneRangeInterpretationEnabled` is NOT emitted** — it encodes the clinician-unsigned C-12 pregnancy rule and its only consumers (P6/P7b hormone ranges) do not exist; P4a persists `trackingPaused`+`pauseReason`, which is all they need. Recorded as a deferral in T22.
  - **Pause state machine** — pausing requires a reason from the 5-member set (`errors.pauseReason = value is required` when absent) and opens a span; a reason change while paused updates the open span **in place**; resume closes it with `EndedOn = max(today, StartedOn)` and clears the triple; supplying `pauseReason`/`pausedSince` with `trackingPaused: false` → 400; resuming when not paused is an idempotent 200. **Resume is unconditional for every reason** — no gate, no confirmation. Invariants: `TrackingPaused == (PauseReason != null) == (PausedSince != null)`; ≤ 1 open span (also enforced by the partial index).
  - **Bounds (§G7):** structural 400 only (`<= 0` or `> 32767`); **non-blocking `warnings[]`** (frozen codes `avg_cycle_length_out_of_sanity_band`, `avg_period_length_out_of_sanity_band`) outside 10–120 / 1–30, computed on **both** GET and PATCH (screen 32 shows the hint on load). See **OQ-3**.
  - `§C.9` Entities line amended. Both JSON snapshots regenerated.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(settings): add cycle settings endpoints with the tracking-pause state machine`

---

### T15 — `POST /me/devices`

- **Goal:** the device-token upsert against the pre-existing table. Standalone, ~80 lines, and a **hard prerequisite for T17** — which is why it comes before it rather than bundled behind the settings work.
- **Tests first**
  - `backend/tests/Lumen.UnitTests/Devices/DeviceRegistrationServiceTests.cs` — unknown platform; blank / 513-char token; same token twice → **one** row with `LastSeenAt` advanced; a different token → two rows; the same token under two users → two rows.
  - `backend/tests/Lumen.IntegrationTests/DeviceRegistrationLiveTests.cs` **[LIVE]** — round-trip; tenant isolation; 401 without bearer; **the response body does not contain the token**.
- **Production changes**
  - `Lumen.Api/Devices/DeviceRegistrationService.cs` + `POST /me/devices` — upsert on the **existing** unique `(UserId, PushToken)`; found ⇒ `Platform` + `LastSeenAt = now`, else insert; 200 for both; wrapped in T10's `ConcurrencyRetry`. `platform` ∈ `{ios, android}`; `pushToken` 1–512 chars. **No migration** (`user_devices` exists since `20260614150634` — §G4/§G14). The **response never echoes the push token**. Push-token-at-rest encryption stays out of scope (an open P9a precondition).
  - `ARCHITECTURE.md §C.9` amended with `POST /me/devices` (OQ-7c). Both JSON snapshots regenerated.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(settings): add the device registration upsert endpoint`

---

### T16 — `POST /onboarding/baseline` + the profile-condition read path

- **Goal:** screen 4's fields land in their §A-mandated homes — three encrypted profile columns plus **one** `body_metrics.weight_kg` row (rider 4: no duplication) — and every rider-4 column gets both a writer and a reader, so P4a ships no unreachable storage.
- **Tests first** — `backend/tests/Lumen.UnitTests/Onboarding/OnboardingBaselineTests.cs` (SQLite + a hand-rolled `FakeUserCryptoContext` over the real `AesGcmFieldCipher` with a fixed 32-byte key)
  - All-null → `request` / `provide at least one baseline field`; future `dob` rejected, today accepted, **a `dob` decades before account creation accepted (§G8)**; `heightCm` 0 and −1 rejected; `weightKg` 60.44 rejected, 60.4 accepted; `"Diagnosed"` (wrong case) rejected, all three endo codes accepted; `rasrmStage` 0 and 5 rejected, 1–4 accepted, null accepted; `diagnosedOn` `"2023-13"` rejected, `"2023-08"` accepted, a future month rejected; **multiple bad fields produce all keys in one response**; ciphertext at rest (`HeightCmEnc` does not contain `"165"`); re-post rotates the ciphertext; a null field leaves the stored value intact; weight creates exactly one metric row and a same-day re-post keeps the count at 1 (§G9 filtered-index regime).
  - `MeResponse` round-trip: the five decrypted condition fields plus the latest live `weight_kg` come back on `GET /me` and are `null` before anything is written.
  - `backend/tests/Lumen.IntegrationTests/OnboardingBaselineLiveTests.cs` **[LIVE]** — end-to-end after `/onboarding/start` + login; `ValueEnc` does not contain the weight digits; tenant isolation; 401 without bearer.
- **Production changes**
  - `Lumen.Api/Onboarding/{OnboardingStepsService,OnboardingStepResult}.cs`; the endpoint is added to the **existing** `MapOnboardingEndpoints()` from T4.
  - Shared preconditions for every step endpoint: `.RequireAuthorization()`; user id **only** from `ICurrentUserAccessor`; missing/tombstoned `users` row → 404; accumulate all errors before any write; one `now` per request.
  - Fields: `dob` (not after user-local today), `heightCm` (> 0), `weightKg` (> 0, ≤ 1 decimal place), `endoStatus` ∈ the 3 codes, **`rasrmStage` (1–4, nullable)** and **`diagnosedOn` (`yyyy-MM`, not in the future)** — the last two close rider 4's storage-without-a-writer gap (screen 31 is the eventual edit surface but no phase owns its API). All null → 400 `request` (a no-op POST is a client bug; "skip" means not calling). **No age gate and no upper height/weight bound** — C-12 makes the population a design target, *"NOT a data-entry/age gate"*, and L-01 is unresolved. `null` field = leave unchanged.
  - Writes: create `user_profile_enc` if absent, then encrypt each supplied field with its canonical plaintext; when `weightKg` is supplied, **upsert** on `(UserId, "weight_kg", user-local day)` so D-02's re-submittable step never stacks duplicates. The response decrypts back for a round-trip proof.
  - **`MeResponse` gains** `dob`, `heightCm`, `endoStatus`, `rasrmStage`, `diagnosedOn`, `latestWeightKg` (all nullable, all decrypted per request) — otherwise everything this task writes is write-only for the rest of the phase and for the already-shipped screen 31.
  - `§C.1` writes line gains `body_metrics`. Both JSON snapshots regenerated.
  - Commit-body note for P4b: screen 4 collects **Age** but §A:60 fixes storage as **DOB** — the API takes `dob`; P4b must not synthesise a DOB from an age stepper.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(onboarding): add the baseline step with encrypted profile fields and weight seed`

---

### T17 — `POST /onboarding/goals`, `/hormones`, `/notifications`

- **Goal:** the three set-writers, each idempotent and each writing its **complete** row set so "provided" is never partial.
- **Tests first** — `backend/tests/Lumen.UnitTests/Onboarding/OnboardingPreferenceStepsTests.cs`
  - goals: null → `value is required`; `[]` → `select at least one goal`; unknown code → 400; a valid subset writes 5 rows with exactly the requested ones selected; duplicates still yield 5 rows.
  - hormones: null rejected; `[]` → success with 7 rows all `Charted=false`; unknown code → 400; all 7 accepted.
  - notifications: unknown category → 400; `[]` allowed; token without platform (and vice-versa) → `pushToken and platform must be provided together`; `platform="web"` rejected; 513-char token rejected; the token upsert inserts then updates (one row).
  - Each endpoint is idempotent (×3 → still exactly 5 / 7 / 4 rows) and callable **after** completion.
  - `backend/tests/Lumen.IntegrationTests/OnboardingPreferencesLiveTests.cs` **[LIVE]** — round-trip + a `user_devices` row after a notifications call with a token; tenant isolation.
- **Production changes** (all in the T4/T16 feature folder)
  - `/onboarding/goals` — `goals` required, **min 1** (D-14), unknown code → 400, duplicates de-duplicated silently, no max. Upserts all **5** rows with `Selected = requested.Contains(code)`. Response in frozen order.
  - `/onboarding/hormones` — `chartedHormones` required; **empty array allowed** (chart nothing); unknown code → 400. Upserts all **7** rows. Commit body records the load-bearing semantic: **hidden ≠ not-extracted** — `Charted=false` only hides the series; P7b still extracts every hormone.
  - `/onboarding/notifications` — `enabledCategories` required, empty allowed (mute everything), unknown category → 400. Upserts all **4** rows. Optional `pushToken` + `platform` must be supplied **together** and are delegated to T15's `DeviceRegistrationService` (§C.1 lists `user_devices` among onboarding's writes — screen 7's "Allow & finish"). Response carries `deviceRegistered`.
  - **Post-completion policy:** these three (and baseline) stay **callable after `/onboarding/complete`** — they are the same writes the settings screens will make, and the settings endpoints that would replace them do not ship for several phases (`/settings/hormones` → **P6**; `/settings/notifications` → **P9a**; `POST /me/export` → **P9b**), so 409-ing them would leave the data uneditable. Only `POST /onboarding/cycle` is 409'd after completion (T18).
  - `§C.1` writes line gains `user_goals`, `user_hormone_prefs`, `user_notification_prefs`. Both JSON snapshots regenerated.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(onboarding): add goals, hormones and notification preference steps`

---

### T18 — `POST /onboarding/cycle` (B15), `POST /onboarding/complete`, `GET /onboarding/state`

- **Goal:** close the D-02 state machine: seed the mandatory cycle data, stamp completion exactly once, and give P4b a single resume read.
- **Tests first** — `backend/tests/Lumen.UnitTests/Onboarding/OnboardingCompletionTests.cs`
  - cycle: missing/`default` date → `value is required`; tomorrow in the user's tz rejected while a `Pacific/Kiritimati` user's "UTC-future" date is accepted; **floor − 1 d rejected, the floor accepted (§G8 — this and `POST /cycle/events` are the only floored writes)**; omitted fields resolve to 28 / null / `somewhat`; `regularity="sometimes"` rejected; **`avgCycleLengthDays = 47` and `avgPeriodLengthDays = 12` are ACCEPTED and persisted** (§G7).
  - cycle re-post, **the two T5 merge-rule collisions**: (a) a re-post with a different date **moves** the single `Source=onboarding` `period_start` (`CycleEvents.Count == 1`); (b) the target date already holds a **live** `Source=user` row → that row is adopted (its `Source` and `CreatedAt` preserved), the stale onboarding row retired, still one row, **no unique-index violation and no 500**; (c) the target date holds a **tombstoned** row → revived, still one row.
  - complete: no `period_start` → `Conflict("onboarding_incomplete")`, `missingSteps == ["cycle"]`, stamp still null; with one → stamps once and backfills **exactly the four default sets**; does **not** overwrite user-supplied prefs; a second call returns the original timestamp with no duplicate rows.
  - state: all booleans false → true at the right moments; `missingMandatorySteps == ["cycle"]` before the seed.
  - `backend/tests/Lumen.IntegrationTests/OnboardingCompletionLiveTests.cs` **[LIVE]** — full happy path start→login→steps→complete with `GET /me.onboardingCompleted` flipping **exactly** at `/complete`; the skip path (start→cycle→complete) with the backfilled defaults asserted in the DB; `/complete` before `/onboarding/cycle` → 409 problem body; `/onboarding/cycle` after completion → 409; **the happy path leaves `user_insight_snapshot` EMPTY for that user** (the §G6 zero-rows exit criterion, actually asserted); cleanup in `finally` with `ExecuteDeleteAsync` in FK order (new tables → `user_profile_enc` → `consent_records` (**Restrict** FK) → `user_keys` → `users`).
- **Production changes**
  - `POST /onboarding/cycle` — `lastPeriodStart` **required** (`!= default(DateOnly)`, ≤ user-local today, ≥ backdate floor); `avgCycleLengthDays` defaults to **28**; `avgPeriodLengthDays` to **null**; `regularity` to **`somewhat`**. Writes `user_cycle_settings` via T14's `CycleSettingsService.ApplyOnboardingCycleAsync` (no duplicated logic) and upserts the single onboarding-seeded `period_start` **following the merge rule pinned on `CycleEvent` in T5**. `flowIntensity` stays **null** (onboarding never asks). 409 `onboarding_already_completed` after completion (moving the seeded anchor post-hoc is a data-integrity hazard; post-completion edits go through `POST /cycle/events` + `PATCH /settings/cycle`).
  - `POST /onboarding/complete` — no body. Mandatory set = a live `users` row **and ≥ 1 live `cycle_events` row with `Kind = period_start`** (checked on the *data*, so a user who logged a period through the cycle module also qualifies); missing → **409** `code=onboarding_incomplete`, `extensions.missingSteps = ["cycle"]`. Otherwise: **guarded claim** `Where(u => u.Id == userId && u.OnboardingCompletedAt == null).ExecuteUpdateAsync(...)` (the `CryptoShredJob` idiom) so concurrent calls stamp exactly once, then **backfill defaults for any table with zero rows** — **in the same transaction** as the stamp, so `GET /me` can never report `true` while defaults are missing. **Reconciled with T17 after its review (2026-08-10) — read this before writing the backfill:** T17 ships `ReadGoalsAsync` / `ReadHormonePrefsAsync` / `ReadNotificationPrefsAsync` in `OnboardingStepsService`, which apply the seed on the READ side, because a skipped step persists **no rows** and `Selected = false` records "was asked and said no" — a different fact from never having seen the question. Both mechanisms ship, and they are only coherent if they cannot disagree: **the backfill MUST write `UserGoal.DefaultSelected`, `UserHormonePref.DefaultCharted` and `UserNotificationPref.DefaultEnabled`, never re-stated literals** (an earlier revision of this line restated the seed as prose — 5 goals / 7 hormones / ON-ON-OFF-OFF — which is precisely the drift the constants exist to prevent). The division of labour: **before** completion the projections give absence its meaning, so `GET /onboarding/state` reads correctly on a partially-onboarded user; **at** completion the seed is materialised so the database becomes self-describing and no later consumer (P6, P9a) has to remember to apply a read-side default — a direct `SELECT` on `user_notification_prefs` returning zero rows would otherwise read as "all notifications off" and silently cost a user their daily check-in reminder. The accepted cost, stated rather than hidden: **the never-asked / said-no distinction does not survive completion**, and nothing after `/complete` may rely on it. `/complete` and `GET /onboarding/state` must call T17's three projections rather than re-deriving any default. `user_insight_snapshot` gets **no row** (§G6). A second call → **200** with the **original** `completedAt` and `alreadyCompleted: true`. Add a `// TODO(C-12)` beside the mandatory check for the amenorrhea branch, explicitly **not** in P4a.
  - `GET /onboarding/state` — additive read (§C.1 amendment, OQ-7b): per-step booleans + `completed`/`completedAt` + `missingMandatorySteps`.
  - `POST /onboarding/complete` remains the **only** writer of `users.OnboardingCompletedAt` in the backend — assert it.
  - `§C.1` gains `POST /onboarding/cycle` (the r17-flagged omission) and `GET /onboarding/state`. Both JSON snapshots regenerated.
- **LiveStack?** Yes — **[UNIT]** + **[LIVE]**.
- **Commit:** `feat(onboarding): add the cycle seed, completion gate and state endpoints`

---

### T19 — Phase-wide tenant-isolation suite

- **Goal:** the phase's headline exit criterion, as one auditable commit. It runs **after every endpoint exists** — an earlier consolidated file could only assert against routes that were not yet registered and would report a false green.
- **Tests first** (the whole task is tests)
  - `backend/tests/Lumen.IntegrationTests/TenantIsolationLiveTests.cs` **[LIVE]** — onboard users A and B. With B's token, walk **every** P4a resource: `POST/DELETE /cycle/events`, `POST /cycle/phase-override`, `GET/POST /cycle/day/{date}`, `POST /checkin/quick`, `GET /cycle/calendar`, `POST/GET/PATCH/DELETE /symptoms`, `GET/PATCH /settings/cycle`, `POST /me/devices`, and each of the six onboarding step endpoints. Assert: **404 (never 403)** on every id-addressed route holding A's id; empty/own-data-only on every range read; and that **A's rows are byte-unchanged afterwards** (including `DeletedAt == null`).
  - Crypto-level check (the `JobCryptoContextLiveTests` pattern): B's crypto context throws `CryptographicException` on a blob written by A.
  - Cleanup in `finally` for both users in FK order.
- **Production changes:** none expected. Any isolation hole found here is fixed in this commit with the failing test kept.
- **LiveStack?** Yes — **[LIVE]** only.
- **Commit:** `test(security): add the phase-wide tenant-isolation suite for P4a`

---

### T20 — OpenAPI spine hardening + backend coverage

- **Goal:** a drift guard a future regression cannot silently dodge, and an honest coverage number against a defensible denominator.
- **Tests first / evidence**
  - **This is not a TDD-red task.** By §G3 the contract is already current, so the new spine assertions pass on the first run. **Prove they bite instead:** temporarily delete one path from `backend/contract/openapi.json`, watch the test fail, revert — record the demonstration in the commit body.
  - `backend/tests/Lumen.IntegrationTests/OpenApiSnapshotTests.cs` — extend `AssertSpineEndpoints` with the P4a spine: `/onboarding/{baseline,goals,hormones,notifications,cycle,complete}` post, `/onboarding/state` get, `/cycle/calendar` get, `/cycle/day/{date}` get+post, `/cycle/events` post, `/cycle/events/{id}` delete, `/cycle/phase-override` post, `/checkin/quick` post, `/symptoms` get+post, `/symptoms/{id}` put+delete, `/settings/cycle` get+patch, `/me/devices` post; plus `components.schemas` contains the validation-problem schema and `OnboardingStartResponse`. Keep the existing `/onboarding/start`, `/health`, `/me` assertions intact.
- **Production changes**
  - **`backend/coverlet.runsettings` (new, committed)** — `ExcludeByFile` for `**/Persistence/Migrations/*.cs` and `**/LumenDbContextModelSnapshot.cs`. Without it the ≥70 % exit criterion is arithmetically unreachable: today ~49 % of `backend/src` is generated migration code, and P4a adds three more migrations covering eleven tables (each with a full `.Designer.cs` + a regenerated snapshot). `Migration.Up/Down` and `BuildTargetModel`/`BuildModel` are never executed by any test — LiveStack applies migrations out-of-process via `dotnet ef` — so they report 0 hits forever. **The stated denominator is `Lumen.Api` + `Lumen.Application` + `Lumen.Domain` + `Lumen.Infrastructure`, minus migrations and the model snapshot.**
  - Command, pasted verbatim into STATUS with its output:
    ```powershell
    dotnet test backend/Lumen.slnx --settings backend/coverlet.runsettings --collect:"XPlat Code Coverage" --nologo
    reportgenerator -reports:**/coverage.cobertura.xml -targetdir:artifacts/coverage -reporttypes:TextSummary
    ```
  - **Remediation step, planned in advance:** if the number lands below 70 %, extend — in this order — `CycleSettingsServiceTests`, `SymptomServiceTests`, `OnboardingStepsService` unit coverage, and `ValidationProblemBuilderTests`; these are the largest hand-written, least-covered surfaces. Do **not** loosen the denominator.
  - **Migration round-trip proof** (`ModelSyncTests` needs no DB and cannot detect a broken `Down()`): `dotnet ef migrations list`, then `dotnet ef database update 20260614172735_AddAdminAuditLogEntityIndex` and back to latest against the dev stack. Paste both outputs.
- **LiveStack?** Yes — **[LIVE]**. (The coverage run executes `Lumen.IntegrationTests` and `Lumen.SecurityTests`, both of which need the stack; labelling this task `[UNIT]` would send an agent into it without docker and make every LiveStack failure look like a regression.)
- **Commit:** `test(contract): harden the OpenAPI spine guard and record P4a backend coverage`

---

### T21 — Dart client regeneration + client verification

- **Goal:** the exit criterion "OpenAPI + Dart client regenerated in the same PR". Split from T20 because the two fail for entirely unrelated reasons and a mixed commit is unbisectable.
- **Tests first:** none new — the client suite is the test. `cmp backend/contract/openapi.json client/openapi/lumen.openapi.json` → exit 0 **before** regenerating.
- **Production changes**
  - Regenerate per `client/lib/api/README.md`. **`PUB_CACHE=C:\pub_cache` is mandatory** (the home path contains a space and breaks Dart native-asset hooks). **Preserve `client/lib/api/README.md`.** Then `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `flutter analyze`, `flutter test --coverage`, `dart run tool/check_coverage.dart` (≥ 60 %, excludes `lib/api/**`).
  - **Record the generated method names** in STATUS for P4b (no `.WithName`/`operationId` exists, so dart-dio derives them from path+verb — predicted `cycleCalendarGet`, `cycleDayDatePost`, `checkinQuickPost`, `symptomsPost`, `settingsCyclePatch`, `meDevicesPost`, …). The `format: date` → `Date` mapping was settled in **T1**; there is no fallback branch left to take here.
- **LiveStack?** No — client toolchain only.
- **Commit:** `chore(client): regenerate the Dart API client for P4a`

---

### T22 — Phase STATUS, exit criteria and ledger

- **Goal:** close the phase per the RUNBOOK.
- **Tests:** none — verification is the pasted output.
- **Production changes**
  - `docs/superpowers/plans/lumen-build.md` — fill the P4a **STATUS** block with **pasted** output: `dotnet build backend/Lumen.slnx -warnaserror`, all four suites (unit / integration LiveStack / security / OpenAPI), the coverage summary and its stated denominator, the migration round-trip, `cmp` exit 0, `flutter analyze` + `flutter test`. Tick each exit criterion with the evidence that proves it: onboarding completes · Cycle/Symptoms/settings-cycle pass integration + **tenant-isolation (T19)** + **encryption** tests · migrations clean (`HasPendingModelChanges == false` **plus** the round-trip) · **placeholder snapshot unmistakably non-clinical** (zero rows asserted in T18's live path, `ComputedBy='placeholder'`, the T7 NetArchTest fact that no `Lumen.Api` type reaches it, `phase.available=false`, no `phase` key on any day row) · OpenAPI + Dart regenerated in this PR · global coverage ≥ 70 %.
  - Record explicitly in STATUS:
    - **The C-03/C-04 PO-interim numbers** (cycle 21–45, period 1–10, window 6, **mean**, ≥3-cycle override, `flow >= 2`, ≥3-day gap) as **P6 `ref_insight_rule` seed input, clinician-UNSIGNED** — they are deliberately absent from `backend/src` (§G7). Mirror them into the `ARCHITECTURE.md §A` P4a row.
    - **The §G11 P4a-invented values** (calendar window ≤ 366 d, symptom batch 1–50, the two `source` vocabularies, the structural positive-smallint domain).
    - **The out-of-scope list**, so review does not read it as omission: phase/ovulation/fertile-window math, estimators, auto-detect, regularity tiers, confidence/data-completeness, missing-data cards, insights, `RecomputeInsightSnapshotJob`, matviews, C-15 red-flag note, energy/libido capture, per-field clearing on the day log, any clinical label on the wire, **`hormoneRangeInterpretationEnabled`** (deferred to P6/P7b), **the B16 `ref_hormone` table** (deferred to P7b pending C-07 — P4a ships the shared code↔label constants only), **`users.unit_system`** (D-06 reserved, no write path), **`/settings/hormones` → P6, `/settings/notifications` → P9a, `POST /me/export` → P9b**, and **push-token-at-rest encryption → P9a**.
    - The **generated Dart method names**, the **doc amendments made in-branch** (§G13), the **⚠ T8 review** result, and any OPEN QUESTION the PO has not answered.
  - Set the §1 ledger row for P4a to **NEEDS_REVIEW**, stamp the branch + PR, and stop.
- **LiveStack?** No — docs only.
- **Commit:** `docs(plan): P4a STATUS + ledger NEEDS_REVIEW`

---

## Open questions for the human

> Answer **OQ-1, OQ-3 and OQ-8 before T6/T8 run** — they change code written in those tasks. The rest have defensible defaults already baked in and need confirmation, not blocking.

**OQ-1 (BLOCKING T8) — Does crypto-shred physically delete the new PLAINTEXT health rows, and does that commit get the ⚠ deep-review treatment?**
`§F:298-299` describes erasure as "delete `user_keys`, empty push tokens, tombstone `users`" and justifies leaving rows in place because "ciphertext remains but is permanently unreadable" — an assumption that stops being true in P4a: `§D:182-184` mandates `symptom_code`, `region`, `side`, `pain_types[]`, `triggers[]`, `intensity`, `pain`, `mood`, `flow_intensity` and the dates as **plaintext** so they can be queried. Cascade FKs never fire (the job tombstones rather than deletes the user) and `users.email_hash` is deliberately retained, so the residue is pseudonymous — still personal data, still GDPR Art. 9. *Options:* (a) hard-delete every user-owned P4a row inside the existing transaction; (b) blank the plaintext columns in place; (c) encrypt the code/ordinal columns (kills every index and the whole P6 engine — contradicts §D:184); (d) defer to P9b.
**Recommendation: (a), and treat T8 as ⚠ (scoped `/code-review high`).** The precedent is in the same job — `user_devices` rows are deleted outright and `Locale`/`Timezone` are blanked *because* they are plain columns the DEK deletion cannot reach. D-13 says account deletion is hard and irreversible, never soft. (b) still leaks row counts, dates and per-user cardinality; (d) is worst — every account deleted between P4a and P9b leaves residue in `pg_dump` backups a later fix cannot recall. Cost: ~11 `ExecuteDeleteAsync` lines and one security test. **Also needs a legal touch:** §F:299 instructs the privacy policy to describe erasure as "unreadable, not deleted" (L-05/L-06).

**OQ-2 (confirm; default = ship it, T6) — Does P4a add the `cycle_tracking_pause_spans` history table, or only the three fields rider 2 names?**
The same `§A:59` row that specifies `tracking_paused`/`pause_reason`/`paused_since` also requires that "paused spans [are] excluded from estimators" — unsatisfiable with the triple alone, because resume clears `paused_since` and the span is gone forever. C-12 repeats it more strongly. Every user who pauses and resumes between P4a and P6 would silently poison the estimator — exactly the harm (a confidently wrong phase for a pregnant or suppressed user) the §A row exists to prevent.
**Recommendation: ship the table** (~30 lines of entity + config, zero extra migration cost; the partial unique index makes the pause/resume state machine enforceable in the DB rather than by convention). This exceeds the literal rider text, which is why it wants an explicit yes. If the answer is no, the STATUS block must record the accepted permanent data loss so P6 does not assume history exists.

**OQ-3 (BLOCKING T14) — Are the C-03 sanity bounds (avg cycle 10–120 d, period 1–30 d) HARD 400s or SOFT non-blocking warnings — and is there any numeric entry bound at all?**
The sources conflict on the first half: `§A:58` / rider 7 say "typed inputs get sanity bounds only", which reads as rejection; the same rider closes with "bounds are estimator-only, **never entry blockers** (PO requirement)", and `clinical-asks.md:34` defines the identical numbers as a "**Non-blocking sanity guard** (soft 'double-check?' hint, **never blocks save**)". On the second half the sources are silent — an earlier draft invented a `1–365` / `1–90` hard tier that appears in **no** source and would have baked invented numbers into DDL, the published contract and the Dart client.
**Recommendation: SOFT, and no invented tier.** Persist the value, return the frozen warning codes outside 10–120 / 1–30, and keep the DB CHECKs to `> 0`; reject only what cannot be a length at all (`<= 0`, or beyond `smallint`). Two sources say "never blocks save" in those exact words and they are the most specific and most recent (`clinical-asks.md` r16 2026-07-14; the r17 plan row 2026-08-06); §A:58 never says "rejects", so under §A precedence there is no true conflict. It also keeps the numbers in one API constants class P6 can lift into `ref_insight_rule` without a migration.

**OQ-4 (confirm; default = implemented in T4) — How does `users.timezone` change after `/onboarding/start`?**
D-12 makes every day boundary a function of `users.timezone`, but the only write path in the codebase is `OnboardingService.StartAsync`. A user who travels, emigrates, or onboarded on a device with a different tz gets legitimate "log today" writes rejected as future-dated, or check-ins filed under the wrong calendar day — precisely the corruption D-12 was adopted to prevent.
**Recommendation: add optional `Timezone` (IANA-validated) and `Locale` (BCP-47, ≤ 35 chars) to `PATCH /me`**, null/absent keeping today's defaults, and amend §C.9 in-branch. Two nullable fields on an endpoint that already exists and is already covered by `MePatchLiveTests`; strictly additive, in the one phase that regenerates the Dart client anyway. Rejected: letting the client send its own local date (hands a health-data day key to an untrusted client and voids D-12's purpose); deferring past P4b, the phase that ships the very check-in screen the bug breaks.

**OQ-5 (confirm; default = implemented in T9) — How does a user remove a wrongly-logged cycle entry?**
D-13 mandates soft-delete on individual entries and gap-register X11 flags delete-visibility as P4a-blocking — but §C.2 exposes no DELETE. With `POST /cycle/events` designed as an upsert on `(user, kind, occurred_on)`, a `period_start` logged on the wrong day is not just un-deletable, it is **un-movable** — and that row anchors `POST /cycle/phase-override` and every P6 cycle partition.
**Recommendation: ship `DELETE /cycle/events/{id}`** (soft-delete, 204, 404 on unknown/other-user) and amend §C.2. ~20 lines, no new entity, no migration, no new concept. Skip `DELETE /cycle/day/{date}` (out of §C.2; the day log is simply overwritten by the next upsert). Reject a `deleted: true` flag on the upsert body — undiscoverable in the generated client and in conflict with the merge semantics.

**OQ-6 (confirm; default = batch, T11) — Is `POST /symptoms` a single-entry create or a batch `{ "entries": [...] }`?**
No source states the request body; §C.3 gives only the path. D-09 makes one user action inherently multi-row (screen 12's single "Save symptom" writes the pain row **plus one row per RELATED chip**; screen 13's "Save body map" writes one row per placed point) and both screens expose exactly one save button. It is a codegen-visible contract P4b is built against and cannot be changed later without breaking the client.
**Recommendation: batch, 1–50 entries, all-or-nothing, 201 with `items`** (the 1–50 cap is a P4a invention and is labelled as such in STATUS). A single-entry POST turns one tap into up to 21 requests on a mobile network with no atomicity, and the client is online-only with no write queue — a mid-save drop leaves a half-recorded episode the user can neither see nor repair. Batch keeps the §C.3 path literally unchanged and degenerates to a one-element array. If the PO prefers single, only the DTO names and the `entries[i].` field prefix change.

**OQ-7 (confirm) — The three additive surfaces beyond the literal §C/§D text.**
(a) **`cycle_phase_overrides` + `POST /cycle/phase-override`** — the endpoint IS in §C.2 but §D defines no storage. **Ship** (T5/T9): the write is a user-asserted observation, needs no phase model, and deferring forces P6 to build storage + endpoint + client regen inside one safety-critical phase. It is the cleanest thing to strike if the phase runs long. (b) **`GET /onboarding/state`** — not in §C.1. **Ship** (T18): P4b's exit criteria require a resume guard and `MeResponse` carries only a boolean, so the alternative is P4b probing six endpoints. Strikeable with no other change. (c) **`POST /me/devices` path** — no document names one. **Use `POST /me/devices`** (T15): user-scoped like `/me`, callable both at onboarding and on every token refresh for the life of the install. All three need a same-branch `ARCHITECTURE.md` amendment (§G13).

**OQ-8 (BLOCKING T6) — Where do the C-03/C-04 clinical numbers live in P4a, given that the phase ships no `ref_insight_rule`?**
Rider 7 says the clinical bounds "live in estimator params flagged pending C-03/C-04 clinician sign-off", but plan §2 is explicit that reference data is "seeded via migration with `valid_from` + provenance" and that the engine "reads `ref_insight_rule` params, **never hard-coded magic numbers**" — and §G6 keeps `ref_insight_rule` out of P4a entirely. So there is no lawful code home for them this phase. An earlier draft put them in `backend/src/Lumen.Domain/Clinical/CycleEstimatorParams.cs`, which would bake clinician-unsigned values into a shipped assembly where a P6 session would find and reuse them instead of the seed rows.
**Recommendation: record them in documentation only** — the T22 STATUS block plus the `ARCHITECTURE.md §A` P4a row, marked "PO-interim, clinician-unsigned, P6 `ref_insight_rule` seed input" — and ship **no** `Lumen.Domain.Clinical` namespace. The guarantee that they are not entry blockers becomes **behavioural** (T14 asserts `avgCycleLengthDays = 15` and `= 47` are both stored) rather than structural, which is the stronger test anyway. Confirm you are content to lose the NetArchTest "nothing may reference the clinical params" guard, which becomes vacuous once the namespace does not exist.

**OQ-9 (confirm; default = defer, T6) — Does P4a create the B16 `ref_hormone` reference table, or only the shared code↔label constants?**
B16 mandates "one authoritative reference table {code, display_label, category, color, display_unit}" and the gap register says it is "needed at P4a for onboarding hormone-prefs persistence". But two of those five columns are not ratifiable today: `display_unit` depends on **C-07** (canonical unit whitelist — clinician-UNSIGNED) and `category` has no hormone-side definition at all (C-13's `{hormonal, pain, supplement, bleeding, metabolic}` is the *medication* enum). Seeding them would put invented/unsigned clinical values into reference data with a `valid_from`, which P7b would then have to supersede.
**Recommendation: defer the table to P7b; ship `Lumen.Domain/Reference/HormoneCatalog.cs` now** with the 7 code↔label pairs, the 4 notification category codes + the canonical "Phase shift" label, and the CLAUDE.md colour per code, pinned by `VocabularyTests`. That delivers B16's actual anti-drift purpose (one place the "Phase shifts" vs "Phase shift" and "estradiol"/"Estrogen" mappings live) at zero clinical risk, and P4a needs nothing else from the table — `user_hormone_prefs` stores codes.

**OQ-10 (confirm; default = implemented in T16) — Who writes and reads `rasrm_stage` and `diagnosed_on`?**
Rider 4 / §A:60 put both in `user_profile_enc`, so P4a must create the columns — but their natural edit surface is screen 31 (shipped in P3b) and no phase owns its API, so they would be unreachable storage. The same gap applies to reading anything the baseline step writes: `MeResponse` today carries only `Id, DisplayName, Locale, Timezone, OnboardingCompleted`.
**Recommendation: give them a write path on `POST /onboarding/baseline` (`rasrmStage` 1–4 nullable, `diagnosedOn` `yyyy-MM`) and a read path on `MeResponse`** (the five decrypted condition fields + latest live `weight_kg`), both in T16 with ciphertext and round-trip tests. The alternative — shipping two encrypted columns no caller can reach — costs the same migration and reads as an oversight in review. If you prefer to defer, the deferral and its owning phase must be named in T22's out-of-scope list and in the `§A` P4a row.

---

## Rejected critiques

**1. "Add `backend/tests/Lumen.UnitTests/Clinical/CycleEstimatorParamsTests.cs` asserting all eight constants verbatim plus `SignoffStatus == "po_interim_pending_clinician"`."**
Rejected as superseded. The critique's own CRITICAL finding deletes `CycleEstimatorParams.cs` from P4a (plan §2 forbids hard-coded clinical numbers; §G6 bans `ref_insight_rule` here). A test pinning the values of a file that must not exist cannot be written. The values are preserved instead in the T22 STATUS block and the `§A` P4a row, where P6 will read them as `ref_insight_rule` seed input — see **OQ-8**.

**2. CRITICAL fix sub-option: "If the PO insists they land in code now, they must be `ref_insight_rule` rows inserted by the T5 migration with `valid_from`, a provenance column and `signoff_status='po_interim_pending_clinician'`."**
Rejected. Creating `ref_insight_rule` in P4a contradicts §G6 (the phase ships no inference infrastructure) and would seed clinician-unsigned values as versioned reference data that P6 must immediately supersede with a second `valid_from` row — leaving a permanent, misleading history entry claiming the app once operated on those parameters. P6 owns the table and should seed it once, after sign-off. The documentation-only route (OQ-8) satisfies rider 7's "recorded pending sign-off" intent with no such residue.

**3. MINOR fix option: "drop the retry from both tasks and rely on the `IgnoreQueryFilters` lookup + upsert, noting the accepted rare-500 in STATUS."**
Rejected in favour of the same finding's other option. The diagnosis is right — untested defensive code catching a provider-specific exception is not acceptable — but deleting the retry puts a 500 on the double-tap path of the app's most-tapped endpoint (`POST /checkin/quick`), on an online-only client with no write queue. T10 instead extracts `ConcurrencyRetry.ExecuteAsync` into `Lumen.Api/Persistence/`, which is directly unit-testable with a fake delegate that throws `DbUpdateException`/`PostgresException{23505}` exactly once — no DB, no race, full coverage of the retry, and T15 reuses it.

**4. MINOR fix: "Add `rasrm_stage` / `diagnosed_on` have storage but no write path in P4a to T16's out-of-scope list."**
Rejected in favour of the CRITICAL twin's fix. Documenting a dead column is cheaper than filling it but leaves two encrypted columns no caller can reach and no phase owning them (screen 31 shipped in P3b; P4b's screen list does not include it). T16 gives both a validated write path on `POST /onboarding/baseline` and a read path on `MeResponse` for ~15 lines, in the task that already encrypts three sibling fields. See **OQ-10**.

**5. IMPORTANT fix option: "seed a `ref_hormone` reference table in T6's migration."**
Rejected in favour of the same finding's deferral option. Two of B16's five columns cannot be filled without inventing or importing unsigned clinical values (`display_unit` → C-07, clinician-unsigned; `category` → no hormone-side definition exists). §G5 requires reference data to be the single source of truth with provenance; a table half-populated with placeholders is worse than no table. `Lumen.Domain/Reference/HormoneCatalog.cs` delivers B16's anti-drift purpose now, and P7b creates the table alongside C-07 sign-off. See **OQ-9**.
