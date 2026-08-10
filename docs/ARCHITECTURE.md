# Lumen — Architecture (handoff document)

This document is the single source of truth for building the Lumen backend and Flutter integration. It was produced in an architecture-design session before any code was written. A future implementation session should be able to build the whole system from this file without re-interviewing the user. Where a future session disagrees with something here, update this file as part of the same change.

Read [CLAUDE.md](../CLAUDE.md) for product context and the design system. This document assumes that context.

Companion file: [deploy/architecture.drawio](../deploy/architecture.drawio) — editable diagram covering topology, lab-parse sequence, module map, and encryption flow.

---

## A. Decisions log

Every architectural choice made in the design session. Each row stands alone.

| Area | Decision | Rationale |
|---|---|---|
| Compliance | GDPR only (EU), no HIPAA in v1 | Consumer-wellness positioning; clinic path is a phase-2 concern. Strictest subset still informs backups, subprocessors, logging. |
| Hosting | Self-hosted VPS, EU region | Privacy posture, cost control, no cloud lock-in. |
| Deployment topology | Single main VPS via Docker Compose + small observability sidecar VPS | Simplicity for MVP scale. Sidecar survives main-VPS outages so you can see them. |
| Reverse proxy / TLS | Caddy with automatic Let's Encrypt | Zero-config TLS, HTTP→HTTPS redirect, HSTS. |
| Identity | Self-hosted Keycloak, Postgres-backed, realm `lumen` | OIDC/OAuth, MFA (TOTP), future clinic SSO. |
| API style | REST + OpenAPI (Swashbuckle) + generated Dart client | Standard, debuggable, cache-friendly, CRUD-heavy product. |
| Client cache model | Online-only with in-memory + Hive disk cache | Offline-first deliberately punted. Reads need network; writes do not queue. |
| Push notifications | FCM (Android) + APNs (iOS) direct from API | Standard, free. FCM is a GDPR subprocessor; list it in the privacy policy. |
| LLM provider | Anthropic (Claude) with signed DPA + zero-retention flag, EU endpoint | Best structured-extraction quality. US transfer covered by SCCs. Chosen over OpenAI in build-strategy session 2026-05-31; abstracted behind `ILlmClient` so it remains swappable. |
| Lab OCR strategy | PDF text extraction (PdfPig) → LLM parse → strict JSON schema → user confirm on screen 20 | No image OCR. User always confirms before values persist. |
| Inference engine | Deterministic C# rules for phase / confidence / missing-data | Auditable, cheap, no ML ops, good enough for v1. |
| Jobs runtime | Hangfire in-process inside the .NET API | Simple deploy. Move to a dedicated worker service if CPU contention appears. |
| Object storage | MinIO, S3-compatible, self-hosted | Portable via S3 SDK, GDPR-clean. |
| Encryption at rest | Per-user envelope encryption: DEK wrapped by a KEK held in Vault Transit | Backups without Vault are useless. Clean right-to-erasure. |
| Key custody | Server-held DEK, KEK in Vault. **Not** password-derived | Background jobs must decrypt user data while the user is offline (lab parse, nightly recompute, notifications). |
| Erasure model | Crypto-shred: destroy the `user_keys` row; ciphertext rows become permanently unreadable | GDPR-defensible, trivial to implement, one-shot. |
| Backups | `pg_dump` nightly to off-site EU S3; MinIO `mc mirror` to same bucket | RPO 24 h acceptable for MVP. |
| Aggregations | Postgres materialized views refreshed by Hangfire (nightly + on-write, debounced) | Pure SQL, fast reads for dashboards. |
| PDF reports | QuestPDF (.NET native, SkiaSharp-backed) | No headless Chromium needed on the server. |
| Reference data management | Admin module (Razor pages inside the API project) with `admin_audit_log` | Clinical safety requires live edits + audit trail. |
| Body-map data model (rev. D-08/D-09, 2026-07-08) | Fixed region enum (+ `side` front/back) + intensity **0–10**; taps snap to nearest region, no raw x/y v1 | Queryable, simple. Heatmap rendering reconstructs coordinates client-side. 0–10 = NRS-11, one scale everywhere (supersedes the original 1–5). |
| Activity data source | Manual entry in v1. Apple Health + Google Fit sync in phase 2 | Ship faster. |
| Report sharing | In-app PDF download, user forwards via their own channels | No server-side sharing endpoint, no signed URLs, no audit of who received the report. |
| Scheduling (rev. D-12, 2026-07-08) | The nightly 08:00-Madrid Hangfire job survives only as a batch fan-out trigger; **all** day-boundary logic ("today", Day X of Y, validation windows) uses per-user IANA `users.timezone` (captured at `/onboarding/start`) via one shared helper | A wrong "today" corrupts day-keyed data for any non-CET user; also the prerequisite for per-user notification times (D-19). |
| Rate limiting | ASP.NET built-in rate limiter middleware + per-user daily LLM-call quota enforced in DB | Protects LLM cost and prevents trivial abuse. |
| LLM guardrails | Strict JSON schema + unit whitelist + physiological range validation + mandatory user confirm | Lab parsing is safety-critical; rejected parses fall back to manual entry. |
| Observability | Grafana + Loki + Prometheus on a separate sidecar VPS | No subprocessor, survives main-VPS outage. |
| Client locale/formatting (D-05, 2026-06-14) | Week-start, date/time, decimals formatted from `users.locale` via ICU (es-ES default: Monday-first, 24-hour, comma). API payloads stay locale-neutral (ISO dates, period decimal); format/parse only on the client | EU/es-ES-primary product, EU-only hosting. The US-formatted mockups (Sunday-first, AM/PM, period decimal) are English artifacts, not the spec. |
| Units (D-06, 2026-06-14) | Metric-only v1 (kg / cm / %). Reserve `users.unit_system` enum (default `metric`) for a future imperial *display* toggle | All 38 screens already metric; the enum avoids a later migration. |
| Client privacy scope (D-07, 2026-06-14) | No analytics v1 (hide screen-36 toggle); no iCloud/Google device-backup toggle; biometric app-lock + app-switcher blur in; no in-app language picker (device locale only); correct the inaccurate screen-31 "stays on your device" copy | Cheap client-only privacy wins; drop features that contradict the online-only server model or misstate data handling (see L-03). |
| Social login (D-01 reopened, 2026-07-08) | Apple + Google login IN for v1 via Keycloak identity brokering — new phase **P4c** after P4b (account-linking on `email_hash`, DEK provisioning for brokered identities, screen-2 buttons return). Apple/Google OAuth app registrations + legal L-09 are long-lead, started now | PO call, reversing the earlier defer-default; P3b's email/password-only state stands until P4c ships. |
| Onboarding completion (D-02, 2026-07-08) | Mandatory = account + last-period date; baseline/goals/hormones/notifications skippable with defaults; per-step persistence; `/onboarding/complete` validates the mandatory set and stamps `onboarding_completed_at`. Amenorrhea users need a future alternate path (no last-period gate) — see the C-12 rider | Last-period seeds the cycle engine; skippability matches the screens ("Not now", "Edit anytime"). |
| End-user MFA / email verification (D-04, 2026-07-08) | TOTP optional (off by default); email verification required with a grace window (usable immediately, nagged until verified); Keycloak reset flow + "your data is not lost on reset" copy | DEK is server-held, so a password reset never loses data; biometric app-lock covers casual device security. |
| Symptom/pain intensity scale (D-08, 2026-07-08) | **0–10 (NRS-11) everywhere** — quick check-in, full form, body map, non-pain symptoms; 0 is a valid logged value ("none today") | Clinical-standard scale feeding P6 math and clinician-facing reports; matches every "N/10" readout; screen-9's ten-button 0–9 row is a mockup artifact (P4b fixes). |
| Symptom data shape (D-09, 2026-07-08) | `symptoms` rows carry `region` (8 + `unspecified`) + `side` (front/back) + `pain_types[]` (6) + `triggers[]` (7) + `intensity 0–10`; RELATED chips become their own rows from a 20-member non-pain catalog; classification is **always optional** (only intensity + date required). Vocab tables frozen in definitions.md (2026-07-08); clinician review flagged with C-14 | Pain stays classifiable by localization/type/intensity/trigger for P6 analytics without burdening quick logging. |
| Mood / energy / libido (D-10, 2026-07-08) | Quick check-in writes mood 1–4 {low, tired, steady, bright} only; energy + libido are optional fields on the future full day form; never derived from the mood grid | "Tired" stays a mood answer; the 15-second check-in promise holds. |
| Check-in payloads (D-11, 2026-07-08) | `cycle_day_logs` (one per day, upsert) gains `pain smallint 0..10`: quick check-in = {pain?, mood?} ≥1 required, upserting the day's **headline pain** + mood; the full form/body map append classified `symptoms` rows (many per day) | One clean daily pain series for P6 plus unlimited classified episodes; repeat quick check-ins just update today's value. |
| Shared data rules (D-13, 2026-07-08) | Soft-delete `deleted_at` on individual entries, excluded from all reads/matviews/reports/exports; pagination limit/offset default 50 max 100; no future-dated entries (user-local today per D-12); `cycle_events` backdate floor = account-creation − 2 y; `notes_enc` ≤ 2000 chars, never sent to the LLM, truncated in PDFs. **Account deletion stays crypto-shred — never soft** | Stated once for every module P4a onward. |
| Goals & hormone defaults (D-14, 2026-07-08) | Goals: 5 frozen codes, multi-select, min 1, no max, first two default ON. Hormones: all 7 always extracted from labs; **charted default = all 7 ON** (screen 33's 4-ON state is a populated sample, not spec) | Screen 6 "Defaults shown" is the authoritative initial state; hidden ≠ not-extracted. |
| Cycle-setup endpoint (B15, 2026-07-08) | Dedicated `POST /onboarding/cycle`: last-period → `cycle_events` period_start row; avg length + regularity → cycle settings | 1:1 step↔endpoint keeps onboarding resume trivial; the mandatory cycle seed stays out of the skippable `/baseline`. |
| Hormone code↔label (B16, 2026-07-08) | Wire/DB codes `estradiol`/`glp1` (§E authoritative); display labels "Estrogen"/"GLP-1"; one authoritative reference table {code, display_label, category, color, display_unit}; screen-33 unit casing is display-only (canonical whitelist casing pinned at P7b/C-07) | Clinically-correct analyte codes keep LLM validation and chart joins stable. |
| Cycle bounds & estimator (interim 2026-07-08; firmed 2026-07-14) | **Two-tier rule:** observed events are never clinically validated; typed inputs get sanity bounds only (avg cycle 10–120 d, period 1–30 d); clinical bounds (cycle 21–45 d, period 1–10 d) gate ONLY estimator inclusion + prediction confidence — **mean** of last 6 in-bounds cycles (**PO decision 2026-07-14 — median was the researched recommendation; PO override**), ≥3 cycles before overriding the self-report; out-of-bounds cycles excluded from averages; `flow_intensity` 1–4 {spotting, light, medium, heavy}, period-qualifying at flow ≥2, auto-detect `period_start` on a ≥3-day episode gap. **C-03/C-04 now PO-interim filled 2026-07-14; clinician sign-off pending**; **bounds are estimator-only, never entry blockers (PO requirement)** | Endo cycles are irregular by nature; rejecting real observations at entry would be clinically wrong. Mean computed only over in-bounds cycles so gross outliers are already excluded. |
| Cycle-tracking pause (PO rider 2026-07-08; extended 2026-07-14) | Cycle settings gain `tracking_paused` + `pause_reason` **{pregnancy, hormonal_suppression, surgical, menopause, other}** (PO-extended 2026-07-14) + `paused_since` (P4a ships fields + endpoint). While paused: no predictions, an explicit "phases unavailable" state, paused spans excluded from estimators, and **resume is user-controlled & always available for every reason** (resume = fresh cycle start, no pre/post merge). For `pause_reason=pregnancy`, hormone-range interpretation is **disabled entirely** (labs still loggable; non-pregnant ranges NOT substituted). Engine semantics finalized at P6 under C-12 (PO-interim filled 2026-07-14) | Pregnancy/suppression/surgical/menopause users must never see a confidently wrong phase or poison their averages; pregnant users must not have normal labs flagged against non-pregnant ranges. |
| Profile & condition fields (session, 2026-07-08) | `user_profile_enc` gains `endo_status` {diagnosed, suspected, not_applicable}, nullable `rasrm_stage` 1–4 (rendered I–IV; values pending C-14), `diagnosed_on` (month-year), `height_cm`; DOB stored, age derived; onboarding weight seeds a `body_metrics.weight_kg` row (no duplication); surgeries vocabulary deferred to C-14 | Screen-4/31 fields get storage homes; weight keeps one source of truth. |
| Notification categories & seed (session, 2026-07-08) | Categories {daily_checkin, phase_shift, period_prediction, medication_reminders}; canonical label "Phase shift" (singular); initial seed from onboarding screen 7: ON/ON/OFF/OFF (screen 34's all-ON is a populated sample) | `POST /onboarding/notifications` needs deterministic defaults; keeps the "soft nudges only" promise. |
| D-12 helper location + the P4a error contract + the erasure change + the cycle write surface (P4a, 2026-08-06) | The one shared day-boundary helper D-12 mandates ships as `IUserDayResolver` (`Lumen.Application/Time`, BCL-only) + `UserDayResolver` (`Lumen.Infrastructure/Time`, **singleton**; `TimeZoneInfo` cache; unknown/blank id → falls back to the `users.timezone` default `Europe/Madrid` with a **PII-free** warning that names neither the id nor the user; spring-forward gap → advance to the first instant that exists; fall-back ambiguity → **earliest** instant) + `IUserDayContext`/`UserDayContext` (`Lumen.Api/Time`, **scoped**, one memoised `users` read per request → `UserDayInfo(UserId, Today, BackdateFloor, TimezoneId, NowUtc)`). `UserDayContext` **honours the `User` soft-delete query filter** — a crypto-shredded user resolves to `null`, which every P4a endpoint turns into **404**; that is what makes an erased user's still-valid JWT inert. `UserDayInfo.BackdateFloor` (user-local creation day − 2 y) is **`cycle_events`-only** per D-13; all other dated writes are capped by `Today` alone. **One 400 and one 404 for the whole phase (T3).** The 400 is `application/problem+json` carrying `errors: { <camelCase JSON field name>: [messages] }` plus `detail` = "The request contained invalid data." — the exact fallback string in the shipped `client/lib/core/error/error_mapper.dart`. It is built by `ValidationProblemBuilder` (`Lumen.Api/Validation`), which collects **every** field error before any write (validate-then-act), passes keys through verbatim so indexed paths like `boundaries[0].occurredOn` survive, and reserves the key `request` for cross-field errors. Cross-cutting messages are constants on `ValidationMessages`; endpoint-specific messages are declared and asserted in their own task, and no endpoint invents a new error *body*. `RouteHandlerOptions.ThrowOnBadRequest` is now **explicitly on in every environment** and `ProblemExceptionHandler` maps `BadHttpRequestException` onto that same envelope (`errors.request`), **never echoing `exception.Message`** — a binding failure message quotes the value that failed to bind, which here is health data (§F). Malformed input can therefore no longer surface as a 500 (the old Development behaviour) or as a bodyless 400 (the old Production behaviour). `ThrowOnBadRequest` is pinned by a test that reads `IOptions<RouteHandlerOptions>` off a host built in **Production** — the framework default is `IsDevelopment()`, so a Development-only harness cannot see the line at all. Request logging (`UseSerilogRequestLogging`) sits **outside** `UseExceptionHandler` so it reports the status the client actually received; nested inside it, Serilog's exception path hard-coded 500, and a malformed body was logged at **Error** as "responded 500" with a stack trace quoting the value that failed to bind. The alarm now lives in `ProblemExceptionHandler`, which logs **5xx only** at Error with the exception attached, and 4xx not at all. The 404 body is **code, not a convention**: every task returning 404 calls `NotFoundProblem.Result()` (`Lumen.Api/Validation/NotFoundProblem.cs`, `title` = `NotFoundProblem.Title` = "The requested resource was not found.") — hand-writing `TypedResults.Problem(statusCode: 404, …)` is out, so one typo can no longer fork the "one 404 body" claim. **Tenant isolation returns 404, never 403.** Feature DTOs live in `<Feature>/<Feature>Contracts.cs` with **no `namespace`**, keeping the global namespace the generated Dart client expects. **The spine was retrofitted onto that contract (T4):** `POST /onboarding/start` now answers a named `OnboardingStartResponse` (it returned an anonymous object, which Swashbuckle emits as the untyped `{}` schema the generated Dart client cannot bind to anything) and rejects through `ValidationProblemBuilder`; its four pre-existing messages are **grandfathered byte-identical** and gain only a field key each (`request` / `email` / `password` / `request`). `GET /me` and `PATCH /me` answer `NotFoundProblem.Result()` when the soft-delete-filtered `users` row is gone, so an erased account's still-valid JWT is inert across the whole spine. **`users.timezone` and `users.locale` become mutable through `PATCH /me`**, and BOTH write paths now validate the zone with `TimeZoneInfo.TryFindSystemTimeZoneById` rather than by length: a length-only check let a garbage id persist, and because D-12 resolves the user's day on every request, `UserDayResolver` would emit its PII-free fallback warning once per request for the life of the account — putting the field on `PATCH /me` would have handed that lever to the user. Absent or blank `timezone`/`locale` stay valid on both paths (column defaults at create, unchanged at patch); `locale` is additionally capped at the column's 35 characters and checked for BCP-47 well-formedness through the BCL's own culture-name rules, never an invented pattern. The onboarding routes moved verbatim into `Lumen.Api/Onboarding/OnboardingEndpoints.cs` + `OnboardingContracts.cs`, with the route, `.AllowAnonymous()` and `.RequireRateLimiting("onboarding-start")` pinned by an `EndpointDataSource` metadata test because the OpenAPI document cannot see the last two. **Erasure changes shape in this phase (T8, ⚠).** P4a is the first phase to persist special-category health data in **plaintext** — §D mandates it so the P6 engine can query it — so deleting `user_keys` no longer makes that data unreadable, and the `ON DELETE CASCADE` FKs never fire because the job **tombstones** the `users` row. `CryptoShredJob` therefore **physically deletes** all eleven P4a tables inside the shred transaction, with **`IgnoreQueryFilters()` on the five soft-deletable ones** (`cycle_events`, `cycle_day_logs`, `symptoms`, `cycle_phase_overrides`, `body_metrics`) — without it every tombstoned row survives erasure, invisible to the reads that would otherwise reveal it. `consent_records`, `admin_audit_log`, `user_profile_enc` and `users.email_hash` are retained by design (§F — four retentions, not three). Completeness is **derived from the EF model, not a hand list**: `GdprErasurePlaintextCompletenessTests` enumerates every entity type carrying a `UserId` and fails by name when one is neither erased nor documented as retained, derives the soft-deletable subset from `DeletedAt` and asserts set-equality, and proves a **tombstone existed before** the erasure and none after — so a P5+ table cannot leak silently and the `IgnoreQueryFilters()` requirement is guarded rather than described. That guard covers user-owned **tables** only; the `users` row's own columns have no `UserId` and are hand-audited. The retained audit trail is asserted against a **prior** non-`crypto_shred` row, because counting only the row the job writes for itself is a guard that cannot fail. Request logging switches to the **route template** (`/cycle/day/{date}`), `Microsoft.AspNetCore.**Hosting**` alone is overridden to Warning (the whole-tree form also silenced the auth diagnostics, including the P3c perimeter guard's only output, for zero benefit), and `PiiRedactionEnricher` redacts `RequestPath` plus every P4a health field name — **enforced by reflection over the eleven entity types**, after the first version of that claim shipped while missing 27 column names including `reason`, the column that actually holds `pause_reason = 'pregnancy'`. **MinIO object erasure is NOT implemented** (`TODO(P7a)`; nothing writes objects before P7a). **The privacy-policy wording is now wrong and is flagged for L-05/L-06** with **three** blockers (see §F): the erasure description, the **unbounded** backup horizon (§G defines nightly dumps but no expiry), and `email_hash` retention permanently blocking re-registration. **The cycle write surface lands next (T9)** — the first feature endpoints of the phase, and the shape the eight endpoint tasks after them copy: `POST /cycle/events` (200 `CycleEventResponse`), **`DELETE /cycle/events/{id}` (204, new — §C.2 amended in the same branch under OQ-5)** and `POST /cycle/phase-override` (200 `PhaseOverridesResponse`), all in `Lumen.Api/Cycle/{CycleEndpoints,CycleService,CycleResults,CycleContracts}.cs`, all `RequireAuthorization()`, none carrying a `MapGroup`/`WithTags`/`WithName`. **`POST /cycle/events` is an UPSERT on `(UserId, Kind, OccurredOn)`, not an append** — two `period_start` rows on one day is a state the P6 estimator has no sane reading of, and idempotency is what makes the online-only client's retry safe; `Source = user` on insert while an existing `onboarding` row **keeps its provenance**, which is what T18's merge rule depends on. **`DELETE` is a SOFT delete** (D-13): `DeletedAt`/`UpdatedAt` stamped, 204, and a second call is 404 because the query filter hides the tombstone (P4b treats that as success). **§G9 tombstone revival is implemented on BOTH tables, and `cycle_phase_overrides` is the one the T5 handoff note omitted:** its unique index on `(UserId, CycleStartOn, Phase, Boundary)` is unfiltered too, so a user who resets a correction and then re-corrects the same boundary hits a 23505 unless the row is revived in place — both revivals are proven against real Postgres, not only Sqlite. **§G8's backdate floor is enforced here and only here** (`occurredOn <= Today` **and** `>= BackdateFloor`); no other P4a write may copy the second half. **Zero clinical inference (§G6/§G7):** `flowIntensity` 1–4 is optional on **every** kind (the "flow ≥ 2 is period-qualifying" rule is C-04, clinician-UNSIGNED, and belongs to P6's `ref_insight_rule`); `POST /cycle/phase-override` records a user-asserted observation with **structural guards only** — `cycleStartOn` must match one of the caller's own live logged `period_start` rows, and each boundary must fall on/after it, on/before today, and strictly before the next logged `period_start` — with **no monotonicity guard** (menstrual→follicular→ovulatory→luteal is the C-01 band order, unsigned, and refusing a user's own correction on that basis would be the clinical entry blocker rider 7 forbids) and **no recompute** (screen 14's "retrains the prediction model" copy is a P6 promise). Phase corrections are **replace-the-set for one cycle**: `boundaries: []` is "Reset to predicted" and soft-deletes them all, while an **absent** `boundaries` is a 400, not a reset — an omitted field must never silently destroy the user's corrections. Endpoint-owned wire strings live on `CycleValidationMessages` (`must match a logged period start`, `date must not be before the cycle start`, `date must be before the next logged period start`, `this phase and boundary appears more than once`) and follow the T3 style of never naming their own field, since the `errors` map key already does. `CyclePhaseAvailability` declares the four unavailability codes now — `phase_engine_not_implemented` (P4a's only possible answer) plus `tracking_paused`/`insufficient_data`/`no_period_logged` **reserved for P6**; all four are §G11 inventions. **They are backend constants and are NOT exported to Dart** (corrected after T13's review): what lets P6 emit a new one without regenerating the T21 client is that `CyclePhaseAvailabilityResponse.unavailableReason` **exists** as a plain nullable string, so a new code is a change of value on a field the client already binds. The field therefore **must not carry a `[DefaultValue]`** — openapi-generator's dart-dio/built_value output turns a schema `default` into a builder default and skips explicit nulls on deserialize, so a documented default would make the generated client unable to observe `unavailableReason: null` at all and it would keep reporting the P4a code after P6 shipped. **The `IUserDayContext`-null → 404 check runs FIRST in every handler, before validation**, and is a security control rather than politeness: a crypto-shred tombstones `users` but the account's JWT stays cryptographically valid until it expires (disabling the Keycloak user does not revoke an issued token) and a child INSERT's FK share-lock does not conflict with the shred job's UPDATE, so there is **no other write fence** — an in-flight request would otherwise re-create plaintext health rows for an erased user. Proven live: a shredded user's token gets 404 from all three routes and re-creates nothing. Finally, the schema-id rule was re-verified empirically here — `Lumen.Api/Cycle/CycleContracts.cs` **does** declare a `namespace` and the emitted schema ids are still the bare type names (`LogCycleEventRequest`, `CycleEventResponse`, `SavePhaseOverridesRequest`, `PhaseOverrideInput`, `PhaseOverridesResponse`, `PhaseOverrideBoundary`), confirming §G12's correction that the id is `type.Name` and namespace-independent; the real hazard is a short-name collision across feature folders, and the "no `namespace`" sentence earlier in this row is the stale rationale T22 is scheduled to fix. **P4a therefore ships TWO write rules, and which one applies is decided by how many surfaces write the row, not by the verb (T10, corrected 2026-08-10).** `POST /cycle/events` is a **FULL UPSERT**: the body describes the row's desired final state, so an omitted `flowIntensity` or `notes` **clears** it — safe because `cycle_events` is a small single-writer row that one screen always submits whole, and clearing is the only way a user takes a flow level back off. `POST /cycle/day/{date}` **MERGES**: an absent or null `pain`/`mood`/`notes` **leaves the stored value unchanged** and only a supplied value writes, because `cycle_day_logs` is a **multi-writer** row — the quick check-in writes pain+mood, the day-detail form writes pain, mood and the note, and D-10's `energy`/`libido` land on the same row later. Full-upsert there would mean any screen that posted without re-sending every field silently destroyed what the user entered on another screen; it is the same wipe `POST /checkin/quick` was already special-cased to avoid, so merging makes the two consistent rather than leaving one endpoint as the exception. **The accepted cost is that P4a exposes no way to CLEAR an individual day-log field** — `int?`/`string?` on a positional record cannot distinguish absent from explicit-null under `System.Text.Json` and `built_value` omits nulls, so both meanings need an `Optional<T>` in the generated Dart client; screens 9 and 11 offer no clear affordance, and a documented limitation the user can see beats a cross-surface wipe they cannot. **D-08 gets sharper, not softer, under merge:** `pain: 0` is a SUPPLIED datum and overwrites a stored 8, so both paths merge through one `MergeScales` helper written with `is { }` and never a falsiness test — a `?? row.Pain` over a truthiness check looks identical and drops every pain-free day out of the series P6 reads. The 200 body echoes the STORED row, decrypting the existing `notes_enc` when the request did not carry one, since reporting `notes: null` would render the day as note-less on the very screen that wrote the note. The distinction is **invisible in the generated Dart client** (both DTOs are nullable members on a `built_value` class), so it is written on both DTOs in `CycleContracts.cs` side by side and proven on the wire by a live test that posts genuinely-absent JSON properties. **The push-device upsert lands next to it (T15), and it is the phase's smallest endpoint and its one deliberate cross-tenant write.** `POST /me/devices` sits in `Lumen.Api/Devices/{DeviceEndpoints,DeviceRegistrationService,DeviceResult,DeviceContracts}.cs`, `RequireAuthorization()`, no `MapGroup`/`WithTags`/`WithName`, and adds **no migration and no `DbSet`** — `user_devices` has carried both since `20260614150634` (§G4/§G14). It is an **UPSERT on that table's pre-existing unique `(UserId, PushToken)`**: found ⇒ `Platform` and `LastSeenAt = now` move and `CreatedAt` does not, else insert — **200 on both paths**, because a client that re-registers on every push-token refresh for the life of an install does nothing differently on the first one, and §C.9 exposes no `GET /me/devices/{id}` for a `Location` header to point at. **§G9 does not apply here at all**: `user_devices` has no `DeletedAt` column and no query filter, so there is no tombstone to revive and **no `IgnoreQueryFilters()` on this path** — erasure hard-deletes these rows (§F/T8). The write runs inside T10's `ConcurrencyRetry` (§G12), and this is the P4a endpoint **most likely to race with itself**: two app processes waking together — a notification tap during a cold start — both miss the lookup and both insert, and the loser gets a `23505` on an index the user cannot see. **§G12's unit-of-work rule is honoured by splitting the service in two, exactly as T14 split `CycleSettingsService`:** `StageRegistrationAsync` **STAGES ONLY** — no `SaveChangesAsync`, no `ChangeTracker.Clear()`, no retry of its own — so T17's `POST /onboarding/notifications` can compose it with the four `user_notification_prefs` rows inside ONE retried action, while `RegisterAsync` owns the single retry for the standalone endpoint and **must never be composed** (its `Clear()` is whole-context and would silently discard a caller's staged writes). Both halves are pinned by mutation-verified guards rather than documented: one test stages a preference row, calls the staging method and fails if a save or a clear appears in it; another replays T17's exact compose-then-save-once shape. **A push token names ONE account, so registering it DETACHES it from every other user.** The index is `(UserId, PushToken)`, so the database is perfectly happy to hold one token on two rows — and that state is not hypothetical: a phone handed on, or an app reinstalled under a different account, keeps the same FCM/APNs registration token, because a token addresses the app *install* and not the account. Leaving the old row behind means P9a delivers *"your period is predicted to start tomorrow"* to a handset somebody else is now signed in on — a disclosure of special-category data to the wrong person. The usual provider mechanism does not rescue it (FCM reports `NotRegistered` only for an *invalid* token, and in a handover the token is perfectly valid) and **P4a ships no unregister endpoint at all**, so a stale row would be permanent until P9a. The detach is a **tracked** delete staged into the same unit of work, never `ExecuteDeleteAsync` — which would commit outside the caller's transaction and unregister the other user's device even if the composed write then failed. **Its cost is stated rather than hidden:** anyone holding a victim's push token can unregister their device — bounded, because the token is high-entropy, is never logged, is never echoed in a response and reaches nobody but the client and the provider, and **self-healing**, because the victim's app re-registers on its next launch. It costs a notification, not data, and the 404 fence runs first so an erased token cannot pull the lever at all. **What it obliges P9a to do:** a token now names one account *in practice*, but the index still does not *enforce* it (two users registering concurrently can interleave), so the dispatcher must tolerate more than one row per token and prefer the most recent `last_seen_at` — and P9a owns the proper fix this endpoint cannot ship, an unregister call on sign-out plus deletion on the provider's `NotRegistered`. **T19 must read this as the one endpoint that writes across tenants on purpose**; its isolation guarantee here is narrower and precise — a caller can never read or modify another user's device, and can only remove a row whose token it demonstrably holds. **§F on the token itself:** `push_token` is PII, so there is **no `pushToken` member on `RegisterDeviceResponse`** (the caller already holds it; echoing it would put it in client logs, proxy traces and every support HAR file) and the contract test fails if one is added back. `PiiRedactionEnricher` already redacts the name — but T8's completeness theory is derived over the **eleven P4a entity types and deliberately EXCLUDES `UserDevice`** (it predates P4a), so that coverage is hand-maintained and name-based, and T15 pins it with a test naming the DTO spelling. Nothing in the device path logs at all, and the staging guards never quote the token in an exception message (the enricher walks log properties, not exception messages). Push-token-at-rest encryption stays **out of scope** — an open P9a precondition. Finally, `push_token`'s **512** is the existing column's width and §G11 says so explicitly; it now lives once, as `UserDevice.PushTokenMaxLength`, consumed by both the EF configuration and the validator whose wire string states it (*"text exceeds the maximum length of 512 characters"*), so the two cannot drift. | No endpoint may re-derive a day boundary: a wrong "today" silently corrupts day-keyed rows for any non-CET user, and two endpoints disagreeing about it is worse than either being wrong alone. The error body is codegen-visible — it reaches the Flutter client through the OpenAPI contract, where `error_mapper.dart` already parses `detail` and `errors` into a typed `ValidationFailure` — so a per-endpoint 400 shape would fragment client failure handling across twenty endpoints and could not be unwound cheaply; and a 403 on another tenant's row would itself confirm that the id exists. |
| Clinical asks C-01…C-15 (PO-interim, r16 session 2026-07-14) | All 15 clinically-loaded values filled with **PO-interim** defaults from a cited-research + adversarial-review pass (`clinical-asks.md`); **clinician sign-offs still pending** — reviewer doc = `clinical-signoff-pack.md`. Highlights: C-01 4-band phases (`Ov = next_period_start − 14`); C-02 back-count ovulation ±2 d + fertile-window overlay (**PO chose to include**, −5…0, mandatory non-contraceptive disclaimer); C-05 regularity (≤7 / 8–14 / ≥15 d + confidence multipliers); C-06 Mayo phase-specific ranges; C-07 unit whitelist (cortisol canonical µg/dL); C-08 GLP-1 **deferred** as a hormone, agonist drugs → med log; C-09 renamed **data-completeness** score (labs 40 / cycles 30 / check-ins 20 / body 10); C-10 4 missing-data cards; C-11 insights (Spearman, gate n≥10 & \|ρ\|≥0.30, non-causal wording + footer, mood_vs_estrogen reframed); C-13 catalog + category enum **{hormonal, pain, supplement, bleeding, metabolic}**; C-14 rASRM I–IV + surgery vocab, `depressed_mood`→"low mood", `heavy_menstrual_flow` independent HMB flag; C-15 non-blocking red-flag safety note (6 triggers, verbatim footer). | Unblocks P6/P7b design; **nothing ships until clinician-signed**. Every bound gates estimator/confidence only — never data entry. Two PO overrides of the researched default flagged for the clinician: C-03 (mean vs median), C-02 (fertile-window included). |

---

## B. Topology

Single primary VPS runs the application stack. A second, smaller VPS runs observability. Both live in the same EU region; the sidecar scrapes the main node over WireGuard.

### Services (main VPS)

| Service | Image | Public? | Notes |
|---|---|---|---|
| `caddy` | `caddy:2` | Yes (80, 443) | TLS termination, reverse proxy, IP-based rate limit, HSTS |
| `api` | built from `backend/` | Internal (behind Caddy) | .NET 10, Hangfire in-process, OpenTelemetry OTLP exporter |
| `postgres` | `postgres:16` | Internal | Two databases: `lumen`, `keycloak`. Extensions `pgcrypto`, `uuid-ossp`, `pg_stat_statements` |
| `keycloak` | `quay.io/keycloak/keycloak` | Via Caddy at `/auth` | Admin console bound to localhost only |
| `vault` | `hashicorp/vault` | Localhost only (reached by `api` over Compose network) | Transit engine enabled; auto-unseal mechanism deferred (§I) |
| `minio` | `quay.io/minio/minio` | Internal | Buckets: `lab-uploads`, `reports`, `avatars`, `exports`, `backups`. Console on localhost only |
| `clamav` | `clamav/clamav` | Internal | Scans every uploaded PDF before MinIO persistence |

### Services (sidecar VPS)

`prometheus`, `loki`, `promtail`, `grafana`, `alertmanager`, `node_exporter`. Grafana published via Caddy on a separate subdomain with basic-auth.

### Network & ports

- Only Caddy ports 80/443 are reachable from the public internet.
- `keycloak` admin, `vault`, `minio` console are bound to `127.0.0.1` inside the compose file; reach them via SSH tunnel.
- Sidecar reaches the main VPS over a WireGuard interface; nothing else is exposed.
- All inter-service traffic stays on the Compose bridge network.

### External dependencies (subprocessors)

- **FCM + APNs** — push delivery.
- **Anthropic (Claude)** — LLM parse calls over HTTPS. Signed DPA, zero-retention flag set.
- **Off-site backup provider** (Scaleway or Hetzner Object Storage) — holds `pg_dump` and MinIO mirrors.

All three must appear in the privacy policy and in §F below.

---

## C. Module catalogue

Ten bounded contexts inside the .NET API. Each module is a folder under `backend/src/Lumen.Application/` and `backend/src/Lumen.Domain/` with a matching feature folder under `backend/src/Lumen.Api/Controllers/`.

### 1. Onboarding (screens 1–7)
- **Entities:** none owned; writes to `users`, `user_profile_enc`, `cycle_events` (baseline), `user_devices` (push token), notification prefs.
- **Inbound:** `POST /onboarding/start`, `POST /onboarding/baseline`, `POST /onboarding/goals`, `POST /onboarding/hormones`, `POST /onboarding/notifications`, `POST /onboarding/complete`.
- **Outbound:** Keycloak (user creation via admin API), Vault (DEK provisioning).
- **Jobs:** none.

### 2. Cycle (screens 8, 10, 11, 14)
- **Entities:** `cycle_events`, `cycle_day_logs`, `cycle_phase_overrides`, `user_insight_snapshot`.
- **Inbound:** `GET /cycle/calendar?from&to`, `GET /cycle/day/{date}`, `POST /cycle/day/{date}`, `POST /cycle/events`, `DELETE /cycle/events/{id}`, `POST /cycle/phase-override`.
- **Outbound:** Symptoms (read-only), Hormones (read-only for phase-correction hints).
- **Jobs:** `RecomputeInsightSnapshotJob` (per-user, triggered on-write + nightly).

### 3. Symptoms (screens 9, 12, 13)
- **Entities:** `symptoms`.
- **Inbound:** `POST /checkin/quick`, `GET /symptoms?from&to&limit&offset`, `POST /symptoms`, `PUT /symptoms/{id}`, `DELETE /symptoms/{id}`.
- **Outbound:** none.
- **Jobs:** none.
- **Amended P4a-T12 (2026-08-10) — the update verb is `PUT`, not `PATCH`.** A `symptoms` row is **full replace**: it is id-addressed and single-writer, and *clearing is the affordance* — the classification fields are toggle chips, so a merge would make a pain type addable but never removable. `POST` is semantically neutral, so `POST` = upsert and `POST` = merge elsewhere in §C mislead nobody; `PATCH` is not, and its defined meaning is exactly what full replace contradicts — a client author sending only the changed field would get silent data loss. Keeping `PATCH` as a true merge with explicit clears was rejected: it needs a tri-state DTO the generated `built_value` Dart client cannot express. **The verb is a safety affordance, not a naming preference.**
  - **`PUT` field rules.** A field with an *unclassified* state is **cleared** when omitted (`region` → `unspecified`, `side` → null, `painTypes`/`triggers` → empty, `notes` → null). A field with **no** unclassified state is **required**: `intensity` and `occurredAt`. Requiring `occurredAt` is what stops an edit from re-dating a transcribed historical entry to the edit's clock. `symptomCode` is **absent from the request DTO entirely** — re-coding a row rewrites a P6 series' identity, so the user action is delete + create.
  - **Client obligation (P4b).** Because the body is the row's whole desired state, the client must re-hydrate the row and send every field back. The sharp edge is `side`: screen 12 (`symptom_form`) has **no front/back control** — its only path to a side is a drill-in to screen 13 (`body_map`) — so a body-map-located row edited from screen 12 loses its side unless screen 12 echoes back the value it was given. `GET /symptoms`, `POST /symptoms` and `PUT /symptoms/{id}` all return `side`, so the duty is cheap to meet. Exempting `side` from the clear was rejected: it would make one field on a full-replace DTO silently merge, invisibly on the wire and in the generated client, and leave `side` settable but never un-settable.
- **`GET /symptoms` reads a user-local day window** (`from`/`to` both required and inclusive, matched on `occurred_on`). A **future `to` is allowed** here and only here — every write is capped by today (§G8), but a month view spans forward. **The window is capped at ≤366 days** (§G11, defect fix landed after T13 — the same cap and the same wire message `GET /cycle/calendar` uses, shared via `Validation.ReadWindow.MaxDays`/`ValidationMessages.MaxWindowDays`): T12 originally paged `items` (D-13's `limit` default 50 / min 1 / max 100, `offset >= 0`, out of range → **400, never a silent clamp**) but left `total`'s `COUNT(*)` unbounded, so a wide-open range was a full-table count per request on an authenticated endpoint. Ordered `occurred_at DESC, id DESC`; the id tiebreak keeps offset paging stable because D-09 makes one body-map save write N rows at a single instant. `total` counts live matching rows only — tombstones are absent from `items` and from `total` alike.

### 4. Hormones (screens 15–21)
- **Entities:** `labs`, `lab_result_drafts`, `lab_results`.
- **Inbound:** `GET /hormones/series?hormone&from&to`, `GET /hormones/{id}`, `POST /labs` (multipart), `GET /labs/{id}`, `GET /labs/{id}/drafts`, `POST /labs/{id}/confirm`, `GET /insights/confidence`, `GET /insights/missing-data`.
- **Outbound:** MinIO, ClamAV, Vault, LLM provider.
- **Jobs:** `ParseLabJob` (per-lab), `RefreshHormoneSeriesMatviewJob` (nightly + debounced on-write).

### 5. Body (screens 22–23)
- **Entities:** `body_metrics`.
- **Inbound:** `GET /body/calendar`, `POST /body/entry`, `GET /body/entry/{id}`.
- **Outbound:** none in v1; phase 2 consumes Apple Health / Google Fit batches.
- **Jobs:** none.

### 6. Activity (screens 24–25)
- **Entities:** `activity_entries`.
- **Inbound:** `GET /activity/calendar`, `POST /activity/entry`.
- **Outbound:** none in v1.
- **Jobs:** none.

### 7. Treatment (screens 26–27)
- **Entities:** `medications` (ref), `medication_schedules`, `medication_logs`.
- **Inbound:** `GET /medications`, `POST /medications`, `POST /medications/{id}/log`, `GET /medications/{id}/schedule`, `PUT /medications/{id}/schedule`.
- **Outbound:** Admin (medication catalog read).
- **Jobs:** participates in the nightly dispatch job (see Settings / Notifications).

### 8. Reports (screens 28–30)
- **Entities:** `reports`.
- **Inbound:** `GET /insights/hub`, `POST /reports/doctor`, `GET /reports/{id}`, `GET /reports/{id}/download`.
- **Outbound:** Hormones (read), Cycle (read), Symptoms (read), Treatment (read), MinIO (write), Vault.
- **Jobs:** `GenerateDoctorReportJob` (per-request).

### 9. Settings (screens 31–37)
- **Entities:** writes to `user_profile_enc`, `users` (`locale`, `timezone` — P4a/T4), `user_cycle_settings` (P4a/T6), `user_devices`, `user_keys` (on erasure).
- **Inbound:** `GET /me`, `PATCH /me`, `POST /me/devices`, `GET /settings/cycle`, `PATCH /settings/cycle`, `GET /settings/hormones`, `PATCH /settings/hormones`, `GET /settings/notifications`, `PATCH /settings/notifications`, `POST /me/export`, `DELETE /me`.
- **`POST /me/devices` (P4a/T15):** push-token registration, called by the client on first launch and on **every token refresh for the life of the install**. Body is `{ platform, pushToken }` — `platform` ∈ {`ios`, `android`}, `pushToken` 1–512 chars (the pre-existing column width, **not a P4a invention**), both required, trimmed before they are measured. It is an **UPSERT on the pre-existing unique `(UserId, PushToken)`** — found ⇒ `platform` + `last_seen_at` move, else insert — and answers **200 either way**: an upsert has no actionable created/updated distinction for a caller that re-registers on every refresh, and §C.9 exposes no `GET /me/devices/{id}` for a `Location` header. **The 200 body never carries the token** (`{ deviceId, platform, lastSeenAt, createdAt }`); an unknown platform, a blank token or an overlength one is the shared 400 and writes nothing; a missing `users` row is the shared 404, decided before validation. **Registering a token DETACHES it from every other account** — see the P4a row in §A. **No migration** (`user_devices` since `20260614150634`), and push-token-at-rest encryption stays out of scope (an open P9a precondition).
- **`PATCH /me` fields (P4a/T4):** `displayName` (encrypted at rest), `locale` (BCP-47, ≤ 35 chars — D-05), `timezone` (IANA zone id — D-12). All three optional; `null`/blank means *leave unchanged*, never *reset to default*. A `timezone` that `TimeZoneInfo` cannot resolve, or a malformed/overlength `locale`, is a 400 in the shared validation-problem body and writes nothing; a missing `users` row is the shared 404.
- **Outbound:** Keycloak (password reset trigger), Vault (crypto-shred).
- **Jobs:** `BuildDataExportJob`, `CryptoShredJob`, `NightlyNotificationDispatchJob`.

### 10. Admin (no mobile screens)
- **Entities:** `ref_hormone_range`, `ref_medication`, `ref_insight_rule`, `admin_audit_log`.
- **Inbound:** Razor-pages CRUD under `/admin`, gated by Keycloak realm role `lumen-admin`. Internal REST endpoints for reference-data reads consumed by other modules.
- **Outbound:** audit log write on every mutation.
- **Jobs:** none.

---

## D. Data model

All user-owned tables have `id uuid primary key`, `user_id uuid`, `created_at timestamptz`, `updated_at timestamptz`, and `deleted_at timestamptz null` unless noted. "Enc" columns are `bytea`, encrypted with the per-user DEK before insert.

### Core

- **`users`** — `id` mirrors the Keycloak subject, `email_hash` (for lookup without plaintext), `locale`, `timezone`, `onboarding_completed_at`, **`unit_system varchar(8) NOT NULL default 'metric'`** *(P4a/T7 — the D-06 reserved column of §A:45; **no endpoint and no write path**, it exists so a future imperial **display** toggle lands without a migration. Single-valued today, so it is not a quasi-identifier and does **not** join the §F shred blanking list; it never changes what is stored, only how a future client renders it.)*
- **`user_keys`** — `user_id unique`, `wrapped_dek bytea`, `key_version int`, `vault_key_name text`. **Deleting this row performs crypto-shred.**
- **`user_profile_enc`** — `display_name_enc`, `dob_enc`, `bio_enc`, and the rider-4 condition bundle *(added P4a/T7, write path in T16)*: **`endo_status_enc`** (canonical plaintext = one of `diagnosed`/`suspected`/`not_applicable`), **`rasrm_stage_enc`** (plaintext `"1"`–`"4"`, rendered I–IV; nullable and independent of `endo_status` — a diagnosed user often does not know their stage), **`diagnosed_on_enc`** (plaintext `"yyyy-MM"` — month precision, which is what screens 4/31 collect), **`height_cm_enc`** (invariant-culture integer cm, D-06 metric-only). All four are `bytea` and nullable (D-02 makes every step after account + last period skippable). **Encrypted rather than plaintext** because none is ever a SQL predicate, sort or aggregate: C-14 is explicit that rASRM *"does NOT correlate with pain, never inferred"*, the diagnosis month is display-only, and BMI could not be computed in SQL anyway since weight lives in `body_metrics.value_enc`, already encrypted — while a new plaintext quasi-identifier would have to join the §F shred blanking list. The 1–4 rASRM range therefore **cannot be a DB CHECK** and is enforced by the T16 writer. **No weight column** (rider 4 — onboarding seeds `body_metrics.weight_kg` so weight has one source of truth) and **no surgeries column** (C-14, clinician-UNSIGNED, deferred).
- **`user_devices`** — `platform` (`ios`/`android`), `push_token`, `last_seen_at`, unique on `(user_id, push_token)`.

### Cycle & symptoms

- **`cycle_events`** — `kind` (`period_start`/`period_end`/`spotting`), `occurred_on date`, `flow_intensity smallint null` (1–4 {spotting, light, medium, heavy} — interim, pending C-04), `notes_enc null`, **`source` (`user`/`onboarding`) — a P4a-proposed vocabulary, not in the 2026-07-08 ratification block**; it exists so the onboarding cycle seed (B15) can be found and moved later without guessing which row it was. `auto_detected` is deliberately not reserved: the set is append-only, so pre-reserving an unsigned C-04 concept buys nothing. Unique on `(user_id, kind, occurred_on)`, **unfiltered** — a tombstone keeps occupying the key, so upserts revive it under `IgnoreQueryFilters()` rather than inserting a second row. **Onboarding-seed merge rule** (pinned on the entity's XML doc, consumed by `POST /onboarding/cycle`): before moving the `source = onboarding` seed row onto a target day, look the target key up ignoring the soft-delete filter and, if a row exists live or tombstoned, **adopt/revive it** — clear `deleted_at`, keep its own `source` and `created_at` — then retire the stale seed row. Never two rows, never an index violation.
- **`cycle_day_logs`** — one per `(user_id, day)`: `pain smallint 0..10 null` (headline pain, D-11 2026-07-08), `mood smallint 1..4`, `energy smallint`, `libido smallint`, `notes_enc`. `energy`/`libido` are **reserved columns with no writer and no CHECK** in P4a — D-10 defers both scales, and the columns exist so the deferred scales land without a migration. Unique on `(user_id, day)`, **unfiltered**, same revive-the-tombstone rule as `cycle_events`.
- **`symptoms`** — `symptom_code` (pain | 20-member non-pain catalog), `region` enum (8 + `unspecified`) + `side` (`front`/`back`, null), `pain_types[]`, `triggers[]`, `intensity smallint 0..10` (D-08 2026-07-08), `occurred_at timestamptz`, **`occurred_on date`**, `notes_enc`. Enums hard-coded in code, not in DB (frozen sets: definitions.md ratification 2026-07-08). **`occurred_on` is the user-local day of `occurred_at`, computed at write time through `IUserDayContext` (D-12) and never client-supplied**; it exists so calendar and range reads are a day-keyed index scan (`(user_id, occurred_on, occurred_at)`) instead of a per-row timezone conversion. It is capped by the user's local today with **no backdate floor** — the floor is `cycle_events`-only (D-13).
- **`cycle_phase_overrides`** *(new, P4a)* — one user correction to one phase boundary of one cycle (screen 14): `cycle_start_on date`, `phase` (`menstrual`/`follicular`/`ovulatory`/`luteal`), `boundary` (`start`/`end`), `occurred_on date`, **`source` (`user_correction`) — a P4a-proposed vocabulary, not ratified**; one member today because P4a has one writer, and the set is append-only so P6 can add its own. Unique on `(user_id, cycle_start_on, phase, boundary)` (**unfiltered**) + index `(user_id, cycle_start_on)`. **P4a stores; it does not interpret** — the four phase codes carry no ordering, no durations and no dates, because the C-01 band sequence is a clinician-UNSIGNED PO-interim value that belongs to P6. **P6 consumption contract:** P6 computes its C-01 bands, then replaces any computed boundary that has a live override row for the same `(cycle_start_on, phase, boundary)`, and flags such a cycle for the C-05/C-09 confidence path. No column changes meaning at P6.

All four tables above carry `created_at`, `updated_at` and a `deleted_at` soft-delete marker (D-13) excluded from every read by an EF query filter; account deletion **hard-deletes** them (§F). Physically they are snake_case tables with **PascalCase column identifiers** and no naming convention — the CHECK literals double-quote the real identifiers, so any column rename silently invalidates them on both Postgres and SQLite. CHECK constraints cover the **frozen numeric scales only** (`pain 0..10`, `mood 1..4`, `flow_intensity 1..4`, `intensity 0..10`); there is deliberately **no CHECK on vocabulary membership**, since the sets are append-only and a DB enum would make every new member a migration.

### Settings & preferences *(new, P4a)*

- **`user_cycle_settings`** — **one row per user, PK = `user_id`** (1:1 like `user_keys`/`user_profile_enc`; deliberately **not** columns on `users`, which is the identity/spine row read on every request, and **not** on the all-ciphertext `user_profile_enc`, because every column here is a SQL predicate/sort/aggregate input for the P6 estimator and must stay plaintext). Columns: `avg_cycle_length_days smallint NOT NULL default 28` (definitions.md:71), `avg_period_length_days smallint NULL` (**no default** — onboarding screen 3 never collects it, so any seeded value would be a self-report the user never made), `regularity varchar(16) NOT NULL default 'somewhat'` {regular, somewhat, irregular}, `phase_prediction_enabled bool default true`, `auto_detect_period_start_enabled bool default true`, `show_fertility_window_enabled bool default false` (the C-02 overlay is clinician-UNSIGNED and carries a mandatory non-contraceptive disclaimer, so it is opt-in), `tracking_paused bool default false`, `pause_reason varchar(32) NULL`, `paused_since date NULL`. **`pause_reason` has FIVE members** — `pregnancy`, `hormonal_suppression`, `surgical`, `menopause`, `other` (C-12, PO-extended 2026-07-14; §A:59 is authoritative and the earlier three-member list is superseded). **No `deleted_at`** (D-13's soft-delete governs individual *entries*; this is a per-user singleton and a tombstone would strand the primary key) and **no `first_day_of_week`** (D-05 derives it from `users.locale` via ICU) and **no `regularity_variability_days`** (a C-05 computed output owned by P6). CHECKs are **structural only** — `avg_cycle_length_days > 0` and `avg_period_length_days IS NULL OR > 0`; the sanity band (avg cycle 10–120 d, period 1–30 d) is a **non-blocking endpoint warning** and the clinical bounds (21–45 / 1–10) are clinician-UNSIGNED estimator gates, so **neither appears in DDL** — bounds never block entry. There is deliberately **no CHECK tying `pause_reason` to `tracking_paused`**: resume clears the flag and the date but preserves the reason so the next pause can pre-select it.
- **`cycle_tracking_pause_spans`** *(P4a)* — the pause **history**: `reason varchar(32)` (the same five-member set), `started_on date`, `ended_on date null` (null = still paused). Index `(user_id, started_on)` + a **partial UNIQUE on `user_id WHERE ended_on IS NULL`**, so a user can have at most one *open* pause and any number of closed ones. Required by §A:59's *"paused spans excluded from estimators"*: the three fields on `user_cycle_settings` describe only the **current** pause, and resume clears `paused_since`, so without this table every pause/resume between P4a and P6 is lost forever and silently poisons the estimator. **P4a stores; it does not interpret** — exclusion, overlap handling and the "resume = fresh cycle start" rule are P6's and read these rows. The index predicate is a **domain lifecycle column, not a soft-delete marker**: this table has no `deleted_at`, so it is outside the soft-delete unique-index regime (whose one filtered case is `body_metrics`).
- **`user_goals`** / **`user_hormone_prefs`** / **`user_notification_prefs`** — one row per user per code, each `{ id, user_id, <goal|hormone|category>_code varchar(32), <selected|charted|enabled> bool, created_at, updated_at }` with UNIQUE `(user_id, code)` and a cascade FK. Deselecting flips the boolean; **the row stays and there is no `deleted_at`**, because a tombstone would keep occupying the unique key and block re-selecting the same goal/hormone/category. Seeds: goals = the 5 D-14 codes with `manage_symptoms` + `understand_hormones` ON; hormones = **all 7 charted ON** (D-14; screen 33's four-ON state is a populated sample) — *charted ≠ extracted*, since all seven are always extracted from labs; notification categories = the 4 codes seeded **ON / ON / OFF / OFF** per onboarding screen 7, which is authoritative over screen 34's all-ON rendering.

The five tables above carry `created_at` and `updated_at` and — uniquely among the P4a tables — **no `deleted_at` at all**; account deletion **hard-deletes** them (§F). Same physical conventions as the cycle tables (snake_case table names, PascalCase column identifiers, no naming convention). Enums stay **hard-coded in code, not in the DB**: no DB enum type and no CHECK on vocabulary membership. The B16 code↔label mapping ships as constants (`Lumen.Domain/Reference/HormoneCatalog.cs`: the 7 hormone codes with display labels "Estrogen"/"GLP-1"/… and their CLAUDE.md chart colours, plus the 4 notification categories with canonical labels including the **singular "Phase shift"**); labels are i18n source strings and are never stored as data. **`ref_hormone` is deferred to P7b** — two of B16's five columns (`display_unit`, `category`) depend on C-07/C-13, which are clinician-UNSIGNED, and §G5 makes reference data the engine's single source of truth, so seeding them now would bake unsigned clinical values into it.

### Body & activity

- **`body_metrics`** *(created P4a/T7 — **not P5**, because rider 4 requires the onboarding weight seed; P5 extends the module)* — `metric varchar(24)` (**`weight_kg` only in P4a**: the full set is an open decision, D-15, owned by P5, and freezing `body_fat_pct`/`waist_cm` now would pre-empt it — the vocabulary is append-only and carries no CHECK, so P5 adds members without a migration), `value_enc bytea NOT NULL`, `source varchar(16) NOT NULL default 'manual'` (`manual`/`apple_health`/`google_fit` — the two sync sources ship as committed values so P5's HealthKit/Google Fit work writes an already-frozen code), `measured_at timestamptz`, **`measured_on date`** (the user-local day of `measured_at`, computed at write time through `IUserDayContext` (D-12) and never client-supplied; it is part of the unique key, so it must be a stored column rather than a per-row timezone conversion. Capped by the user's local today with **no backdate floor** — the floor is `cycle_events`-only, D-13). Unique on `(user_id, metric, measured_on)` **filtered `WHERE deleted_at IS NULL`** — the **one deliberate soft-delete exception**, because the D-02 baseline step must stay re-submittable after a delete; under an unfiltered key the tombstone would keep occupying it and the re-submit would fail on a row the user believes they deleted. The accepted trade-off is several tombstones per day per metric, invisible to every read and hard-deleted by §F on erasure. **No units column**: D-06 is metric-only for v1 and the unit is part of the metric code; `users.unit_system` is a reserved *display* preference and never changes what is stored. `value_enc` is AES-GCM ciphertext of a **string**, so the plaintext form is the column's real contract — there is exactly one canonical encoder (invariant-culture `ToString`/`Parse` with `NumberStyles.Float`), because a culture-sensitive round-trip silently reads 60.4 kg as 604 kg under `de-DE`.
- **`activity_entries`** — `activity_type`, `duration_min`, `intensity smallint`, `source`, `occurred_at`, `notes_enc`.

### Treatment

- **`medications`** — reference to `ref_medication`; `dose_enc`, `start_on date`, `end_on date null`, `active bool`.
- **`medication_schedules`** — `medication_id`, `cron_like text` (simple pattern), `reminder_time time`.
- **`medication_logs`** — `medication_id`, `status` (`taken`/`skipped`/`snoozed`), `taken_at timestamptz`.

### Labs

- **`labs`** — `minio_key text`, `uploaded_at`, `status` enum (`uploaded`/`scanning`/`parsing`/`needs_manual`/`confirmed`/`rejected`), `rejection_reason text null`. The PDF in MinIO is encrypted **server-side** by the API with the per-user DEK (AES-256-GCM), consistent with §E step 3 and the server-held-DEK key custody decision. (Reconciled 2026-05-31: an earlier "client-side" wording here contradicted §E and the locked "DEK is server-held, not password-derived" decision; the client never holds the DEK.)
- **`lab_result_drafts`** — one per hormone found: `lab_id`, `hormone_code text`, `value_enc`, `unit_enc`, `ref_low_enc`, `ref_high_enc`, `measured_on date`, `llm_confidence numeric`.
- **`lab_results`** — promoted-from-draft rows after user confirm. Same shape minus `llm_confidence`.

### Reports & insights

- **`reports`** — `minio_key`, `generated_at`, `expires_at null`, `status` (`pending`/`ready`/`failed`).
- **`user_insight_snapshot`** — one per user, PK = `user_id`: `current_phase varchar(16) null` (one of the four ratified phase codes — **codes only**, no ordering, no durations and no dates, since the C-01 band sequence is clinician-UNSIGNED and belongs to P6), `phase_start date null`, **`data_completeness smallint null` CHECK 0..100** *(**corrected P4a/T7**: this column was called `confidence`; **C-09 renamed the concept to data-completeness**. The CHECK pins the percentage **shape** only — the labs/cycles/check-ins/body weighting is a PO-interim, clinician-UNSIGNED value owned by P6)*, **`missing_data_cards_enc bytea null`** *(**corrected P4a/T7**: this said `jsonb`, which contradicts the rule at the top of §D that every "Enc" column is `bytea` holding AES-GCM ciphertext — ciphertext cannot live in a `jsonb` column, and §D:173 wins)*, `computed_by varchar(24) NOT NULL default 'placeholder'`, `refreshed_at timestamptz null`, `created_at`, `updated_at`. **No `deleted_at`**: every column is *derived output*, not a user entry, so D-13's soft-delete does not apply and a tombstone would strand the primary key; account deletion hard-deletes the row (§F).
  - **The table ships in P4a as a PLACEHOLDER and nothing more.** P4a ships zero clinical inference: it **inserts no rows**, exposes **no read endpoint**, and runs no `RecomputeInsightSnapshotJob`, no matview and no `ref_insight_rule`. `computed_by` defaults to `'placeholder'` so any row that ever appears announces that nothing computed it, and the "no read endpoint" half is **build-enforced** by an architecture test asserting that no `Lumen.Api` type may depend on the entity. It exists now only so P6 needs no additional migration. P6 lifts the guard when the engine ships.

### Admin / reference

- **`admin_audit_log`** — `actor_id`, `action text`, `entity_type`, `entity_id`, `before jsonb`, `after jsonb`, `at timestamptz`. No `user_id`.
- **`ref_hormone_range`** — `hormone_code`, `sex`, `phase_applicability`, `unit`, `low numeric`, `high numeric`, `valid_from`, `valid_to null`.
- **`ref_medication`** — `name`, `form`, `typical_dose`, `atc_code`.
- **`ref_insight_rule`** — `rule_code`, `params jsonb`, `active bool`.

### Materialized views

- **`mv_hormone_series_daily`** — `(user_id, hormone_code, day)` with `value`, `unit`. Drives screen 15 chart.
- **`mv_cycle_phase_summary`** — `(user_id, phase, month)` with `avg_length_days`, `variability`. Drives screens 8 and 28.
- **`mv_insight_metrics`** — `(user_id, metric_code, window)` with numeric rollups for screen 28 insights hub.

All three refreshed by the `RefreshMatviewsJob` nightly, plus a debounced on-write per-user refresh fired by domain events (60 s debounce).

---

## E. Lab-parse pipeline

Triggered when a user uploads a PDF on screen 19. Runs asynchronously; the user sees screen 20 later when the draft is ready.

### Sequence

1. **Upload.** `POST /labs` (multipart). API validates MIME (`application/pdf`), size (≤ 20 MB), magic bytes.
2. **Virus scan.** API streams the upload through ClamAV (INSTREAM). Infected files are rejected with 422; metrics counter `labs_rejected_clamav_total` incremented.
3. **Encrypted store.** API generates a per-file IV, encrypts the bytes with the user's DEK (AES-256-GCM), uploads the ciphertext to MinIO `lab-uploads/{user_id}/{lab_id}.pdf.enc`. Inserts `labs` row with `status='parsing'`.
4. **Quota check.** If the user has already used their daily LLM quota (default 10, stored in `ref_insight_rule.params`), skip LLM, mark `status='needs_manual'`, push notification.
5. **Enqueue `ParseLabJob(lab_id)`** in Hangfire.
6. **Job: fetch + decrypt.** Pull ciphertext from MinIO, decrypt with DEK.
7. **Job: text extract.** Run PdfPig to extract text content with layout hints.
8. **Job: LLM call.** Send text to the chosen provider with:
   - System prompt describing the task and the JSON schema.
   - Few-shot examples of well-formed Spanish/English lab reports.
   - `response_format` / `tools` constraining output to JSON.
9. **Job: validate.** Parse JSON with a source-generated `System.Text.Json` context. For each extracted hormone:
   - `hormone_code` must be in the known list.
   - `unit` must be in the whitelist for that hormone.
   - `value` must be within the physiological range sourced from `ref_hormone_range` (widened by 50 % to avoid false negatives).
   - `measured_on` must parse as a date ≤ today.
10. **Job: persist drafts.** Insert `lab_result_drafts` rows (encrypted). Update `labs.status='needs_manual'` if any hormone failed validation, otherwise `'parsing'` → ready-for-review marker is the presence of drafts.
11. **Job: notify.** Enqueue a push via `NotificationDispatcher` ("Your lab is ready to review").
12. **User confirm.** On screen 20 the user edits or accepts drafts. `POST /labs/{id}/confirm` promotes drafts to `lab_results` inside a single transaction and sets `labs.status='confirmed'`. Drafts are deleted.

### Retry policy

- Hangfire retries the job 3 times with exponential backoff on transient failures (LLM 5xx, network timeouts).
- A non-retryable error (schema violation that can't be fixed by retrying, quota exhausted mid-run) marks the lab `status='needs_manual'` and sends a fallback push.

### JSON schema shape

```json
{
  "measured_on": "YYYY-MM-DD",
  "results": [
    {
      "hormone_code": "estradiol" | "progesterone" | "lh" | "fsh" | "testosterone" | "cortisol" | "glp1",
      "value": 0.0,
      "unit": "pg/ml" | "ng/ml" | "mIU/ml" | "nmol/l" | "...",
      "ref_low": 0.0,
      "ref_high": 0.0
    }
  ]
}
```

### Unit whitelist

Per-hormone whitelist lives in `ref_hormone_range` keyed by `hormone_code`. The admin module is the only place it can change. A migration seeds the initial list.

### Physiological ranges

Also in `ref_hormone_range`. The admin module is authoritative. LLM parse validation uses these rows with a 1.5× widening factor to avoid rejecting legitimate outlier values; the UI still flags them on screen 20.

---

## F. Security & GDPR posture

### Vault & encryption

- **Transit engine** enabled on Vault. One named key per environment (`lumen-prod-kek`).
- On user creation, API generates a 256-bit DEK locally, encrypts it via Vault Transit `encrypt/lumen-prod-kek`, stores the returned ciphertext in `user_keys.wrapped_dek`.
- On each request that touches encrypted data, API asks Vault `decrypt/lumen-prod-kek` once and caches the plaintext DEK in a request-scoped service (`IUserCryptoContext`). Never cached longer than the request.
- Background jobs run with the same abstraction: the job loads the wrapped DEK, unwraps, uses the DEK for the duration of the job, and discards it.
- **Auto-unseal mechanism deferred** (§I). For the MVP, document the operator unseal procedure.
- Vault admin UI is bound to `127.0.0.1` and reached via `ssh -L`.

### Erasure

- Right-to-erasure hits `DELETE /me`.
- API (a) enqueues `CryptoShredJob(user_id)`, (b) disables the Keycloak user, (c) responds 202.
- The job: deletes `user_keys` row, empties push tokens, **physically deletes every plaintext row the user owns** (see below), blanks the residual non-encrypted quasi-identifiers `users.locale`/`users.timezone`, tombstones the `users` row (keep id for FK integrity), deletes MinIO objects under `{user_id}/` **(NOT IMPLEMENTED — TODO(P7a); `CryptoShredJob` carries the TODO and object erasure is not yet complete. Nothing writes to MinIO before P7a, so no object exists to orphan today — but the claim must not be quoted as shipped behaviour)**, writes an entry to `admin_audit_log`.
- Ciphertext remains in row-level tables but is permanently unreadable. Backups containing encrypted blobs are also unreadable for that user from the moment the DEK row is gone. Document this in the privacy policy.
- **Erasure is no longer crypto-shred alone (amended P4a/T8, 2026-08-06).** The bullet above — "ciphertext remains but is permanently unreadable" — predates the P4a tables and describes only the `*_enc` columns. §D **mandates plaintext** for the cycle/symptom/settings/body columns so the P6 inference engine can query them in SQL, and destroying the DEK does nothing whatsoever to a plaintext column. The FKs do not save us either: all eleven P4a tables carry `user_id … ON DELETE CASCADE`, but the job **tombstones** the `users` row rather than deleting it, so **the cascade never fires**. `CryptoShredJob` therefore issues an explicit delete for each of the eleven — `symptoms`, `cycle_day_logs`, `cycle_events`, `cycle_phase_overrides`, `body_metrics` (the five soft-deletable ones **under `IgnoreQueryFilters()`**, or tombstoned rows — several per `(metric, day)` in `body_metrics` by design — survive erasure invisibly), then `user_insight_snapshot`, `user_goals`, `user_hormone_prefs`, `user_notification_prefs`, `cycle_tracking_pause_spans`, `user_cycle_settings` — inside the same transaction as the shred. The plan-§2 invariant now reads: **crypto-shred for ciphertext, physical delete for plaintext.**
  - **Retained on purpose, and not to be "fixed":** `consent_records` (consent proof, GDPR Art. 7(1) accountability), `admin_audit_log` (no user FK; it holds the erasure record itself), `user_profile_enc` (ciphertext only, already unreadable) and — **the fourth retention, easy to miss** — **`users.email_hash`**. The tombstoned `users` row keeps its Vault-Transit HMAC of the address: `users.locale`/`users.timezone` are blanked as residual non-encrypted quasi-identifiers, and `email_hash` is exactly that class of value, but it is deliberately NOT cleared because **whether erasure frees the address for re-registration is an unresolved product decision**. As shipped, it does not: the column's UNIQUE index means the erased address can never be used to sign up again. That is a defensible anti-abuse posture and an indefensible surprise if the privacy policy does not say it, so it is part of the L-05/L-06 flag below.
  - Completeness is not maintained by hand: `Lumen.SecurityTests.GdprErasurePlaintextCompletenessTests` enumerates every entity type carrying a `UserId` **from the EF model** and fails by name if one is neither erased nor listed as deliberately retained, so a later phase adding a user-owned table cannot silently leak it. The same suite derives the soft-deletable subset (`UserId` **and** `DeletedAt`) and asserts set-equality, then proves each of those tables held a **tombstoned** row before the erasure and none after — the `IgnoreQueryFilters()` requirement, guarded rather than described. **Scope limit, stated so no one over-reads the guarantee:** that guard covers user-owned **TABLES** — those with a `UserId` column. The `users` row's own columns are outside it (`User` has `Id`, not `UserId`, so `users` is never enumerated) and are **hand-audited**: `locale`/`timezone` blanked, `email_hash` retained per the bullet above.
  - **⚠ Privacy-policy wording — flagged for L-05/L-06.** Three things legal must fix, not one:
    1. **The erasure description is wrong.** The policy text drafted against the old bullet says erased data "remains encrypted and unreadable". That is now **wrong for the health data users care most about**: symptom, cycle, body-metric and preference rows are **deleted outright**, while only the encrypted fields (display name, DOB, bio, condition bundle, metric values, notes) are rendered unreadable. Legal must restate erasure as *deletion of the health record plus destruction of the key for everything encrypted*.
    2. **The backup horizon is currently UNBOUNDED — a blocker, not a footnote.** Crypto-shred used to cover backups for free (a `pg_dump` of ciphertext is useless once the DEK is gone). For the plaintext tables it does not: a nightly dump taken before the erasure still contains that user's readable symptom, cycle and pregnancy-pause history. §G "Backups" defines the nightly `pg_dump -Fc`, the `mc mirror` to the off-site EU bucket and a monthly restore drill, but **no expiry, no object-lifecycle rule and therefore no retention window at all** — so today the honest statement is that those dumps are kept indefinitely. Setting the window is a business decision (this document must not invent one); until it is set and implemented as a lifecycle rule, the policy cannot truthfully bound how long erased health data survives in backups. **L-05/L-06 blocker #2.**
    3. **`users.email_hash` is retained and blocks re-registration.** See the retention bullet above. The policy must either state that the address cannot be reused after erasure, or the product decision must go the other way and the column be cleared. **L-05/L-06 blocker #3.**

### Logging

- Serilog with a PII-scrubbing enricher: redact emails, user IDs in URLs (`/users/{guid}` → `/users/{sha256-short}`), never log request bodies for `labs`, `symptoms`, `cycle_day_logs`, `body_metrics`, or any `me`/`settings` endpoint.
- **Route template, never the raw path (P4a/T8).** `/cycle/day/2026-08-06` is itself a health-adjacent fact — it asserts this user logged something on that day — so `UseSerilogRequestLogging` emits the route template `/cycle/day/{date}` (set as `RouteTemplate` from `EnrichDiagnosticContext`; unmatched requests log the constant `(unrouted)`), and `PiiRedactionEnricher` redacts the `RequestPath` property outright because Serilog's middleware attaches it whatever the message template says. **`Microsoft.AspNetCore.Hosting` — and only that subtree — is additionally overridden to Warning**: its diagnostics logged the raw URL three times per request at Information ("Request starting/finished …/cycle/day/2026-08-06", plus the unhandled-request line), inside rendered strings under generic property names no enricher can match reliably. The override was first written as the whole `Microsoft.AspNetCore` tree, which **also silenced every authentication and authorization diagnostic** — including the only output the P3c token perimeter guard ever produces — for **zero** additional benefit here. Both forms were measured against a running API: each leaves **zero** occurrences of `2026-08-06` in the log; only the narrow one keeps the auth-failure lines (10 vs 0 in the A/B run). Microsoft.IdentityModel already replaces token PII in those messages with `[PII of type '…' is hidden…]`. `Microsoft.Hosting.Lifetime` is a separate category, so startup/shutdown lines are unaffected. All three lines that make the zero-date claim true — the message template, the `EnrichDiagnosticContext` that sets `RouteTemplate`, and this override — are pinned by `Lumen.IntegrationTests.RequestLoggingPipelineTests`, which drives the real pipeline and filters captured events through the **host's own `ILoggerFactory`** so the assertion is made against the shipped configuration rather than a copy of it. The enricher's name list covers every P4a field that can carry a special-category value — completeness is **enforced by reflection over the eleven P4a entity types** (`PiiRedactionEnricherTests`), which requires every column to be either redacted by name or explicitly allow-listed as benign, so the claim cannot drift from the schema again. The ordinal names (`intensity`, `pain`, `mood`, `flowIntensity`) matter most, since no value-shape heuristic can tell a pain score from a page size. **Accepted cost of name-based redaction:** `reason` is redacted because it is the `cycle_tracking_pause_spans` column that holds `pregnancy`, which also blanks ASP.NET Core's "Authorization failed. {Reason}" — a false positive on one framework line, taken deliberately over a false negative on a pregnancy record (the JwtBearer failure line still carries the real cause). **Known gap:** the enricher walks `logEvent.Properties` only, never `logEvent.Exception`, so an exception *message* still reaches sinks unredacted — tracked for P11 log shipping.
- Log level INFO in production; DEBUG off by default.
- Logs ship to Loki on the sidecar VPS.

### Transport & auth

- TLS 1.2+ only, HSTS max-age 6 months, strict CSP on Caddy responses.
- Keycloak issues JWT access tokens (15 min) and refresh tokens (30 days, rotated on use). Flutter stores tokens in Keychain/Keystore.
- `/auth/*` proxied to Keycloak. All other API routes require `Authorization: Bearer`.
- Admin routes require realm role `lumen-admin`.

### Uploads

- ClamAV INSTREAM scan before persistence.
- Max 20 MB, `application/pdf` only, magic-byte verification.

### Rate limiting & abuse

- ASP.NET rate limiter: global 60 req/min/user; `POST /labs` 10/day/user; `POST /reports/doctor` 5/day/user.
- LLM daily quota enforced separately in DB (`ref_insight_rule` default 10 parses/user/day).

### Subprocessor list (for the privacy policy)

- **FCM / Google** — Android push delivery.
- **APNs / Apple** — iOS push delivery.
- **Anthropic (Claude)** — LLM parsing of lab reports. DPA signed. Zero-retention flag set. Never sends unencrypted symptom/cycle data.
- **Off-site backup provider (Scaleway or Hetzner)** — encrypted Postgres dumps + MinIO mirror. EU region.

### Data export

- `POST /me/export` enqueues `BuildDataExportJob` which zips:
  - `profile.json`, `cycle.json`, `symptoms.json`, `hormones.json`, `body.json`, `activity.json`, `medications.json`, `reports.json` (metadata).
  - Every original lab PDF (decrypted) in `labs/` inside the zip.
- Zip is placed in MinIO `exports/` and a 7-day signed URL emailed to the user. Lifecycle rule deletes after 7 days.

---

## G. Deployment & ops

### `deploy/docker-compose.yml` services

1. `caddy` — `caddy:2`, mounts `./Caddyfile`, ports 80/443.
2. `api` — built locally from `backend/`, depends on `postgres`, `vault`, `minio`, `clamav`, `keycloak`. Env from sops-decrypted file.
3. `postgres` — `postgres:16`, volume `./data/postgres`, two databases bootstrapped via init SQL.
4. `keycloak` — `quay.io/keycloak/keycloak`, mode `start`, Postgres-backed, realm import from `deploy/keycloak/realm-lumen.json`.
5. `vault` — `hashicorp/vault`, Transit engine enabled at first boot via a one-shot init script (see §I for auto-unseal).
6. `minio` — `quay.io/minio/minio`, console bound to `127.0.0.1`, buckets created by an init container.
7. `clamav` — `clamav/clamav`, TCP 3310 on the internal network only.

### `deploy/Caddyfile` outline

```
api.lumen.example {
  reverse_proxy api:8080
  encode gzip zstd
  header Strict-Transport-Security "max-age=15552000"
  rate_limit { ... }
}

auth.lumen.example {
  reverse_proxy keycloak:8080
}

grafana.lumen.example {
  basicauth { ... }
  reverse_proxy sidecar:3000
}
```

### Backups

- Nightly cron on the main VPS: `pg_dump -Fc` of both databases → write to MinIO `backups/postgres/{yyyy-mm-dd}.dump`.
- MinIO `mc mirror` pushes `backups/` and `lab-uploads/` to off-site EU bucket.
- Monthly automated restore drill: a second-tier cron spins a scratch Postgres, restores last night's dump, runs `SELECT count(*)` smoke checks, alerts on failure.

### Secrets

- `.env` file encrypted with `sops` (age key held by operator). Decrypted at deploy time only.
- Runtime secrets (DB password, Keycloak admin password, LLM API key) injected into the Compose stack via `docker compose --env-file`.

### CI/CD

- GitHub Actions workflow: build `api` image → push to GHCR → SSH to main VPS → `docker compose pull && docker compose up -d`.
- A second workflow runs backend unit + integration tests on every PR (compose LiveStack: CI brings up the real Postgres/Keycloak/Vault services from `deploy/docker-compose.yml` — the canonical strategy per plan §4, 2026-07-06; not Testcontainers, and Vault is real, not mocked).

### Observability sidecar

- Scrapes: `api` (.NET OpenTelemetry + Hangfire metrics), `postgres_exporter`, `node_exporter`, `minio`, `caddy`.
- Dashboards: API latency p50/p95/p99, error rate, Hangfire queue depth and failure count, LLM cost/day, Postgres slow queries, disk, Keycloak logins, backup status.
- Alerts: API 5xx > 1 %, Hangfire failed jobs > 5 / h, LLM daily cost > configured budget, disk > 80 %, backup job not run in > 26 h, Postgres connections > 80 % of max, sidecar-to-main WireGuard down.

---

## H. Build order (roadmap for future sessions)

Work through these milestones in order. Each milestone is a shippable PR.

1. **Compose stack up.** `deploy/docker-compose.yml` brings up Postgres, Keycloak, Vault (initialised + Transit enabled), MinIO (buckets seeded), Caddy, ClamAV, plus an empty `api` that responds 200 on `/health`.
2. **.NET API skeleton.** Create `backend/Lumen.sln` with `Lumen.Api`, `Lumen.Application`, `Lumen.Domain`, `Lumen.Infrastructure`. Wire EF Core + Npgsql, Keycloak JWT bearer auth, Swashbuckle, global error handling, Serilog with the PII enricher, OpenTelemetry OTLP exporter.
3. **Vault crypto helper.** `IUserCryptoContext` request-scoped service; DEK provisioning on user creation; field-encrypt helpers for `bytea` columns; unit tests round-tripping through a real Vault in Testcontainers.
4. **Onboarding + Cycle + Symptoms modules.** Full REST endpoints, EF entities, migrations, integration tests. Flutter wires screens 1–14.
5. **Hangfire + materialized views + confidence engine.** Register Hangfire (Postgres storage), implement `RecomputeInsightSnapshotJob` and `RefreshMatviewsJob`, domain rules for phase / confidence / missing-data, tests with golden fixtures.
6. **Labs + LLM parse pipeline.** Upload endpoint, ClamAV scan, MinIO encrypted store, `ParseLabJob`, JSON-schema validation, quota enforcement, confirm endpoint. Record-replay tests for the LLM. Flutter wires screens 18–21.
7. **Reports / QuestPDF.** `GenerateDoctorReportJob`, chart rendering, download endpoint. Flutter wires screens 28–30.
8. **Notifications.** FCM + APNs senders, device registration, `NightlyNotificationDispatchJob`, templates.
9. **Admin module.** Razor-pages CRUD, audit log, realm-role gating, reference-data migrations.
10. **Observability sidecar.** Dashboards, alerts, WireGuard link.
11. **Flutter polish pass.** Every screen verified end-to-end against live backend with a seeded demo account; empty/error/offline states checked.

---

## I. Open questions deferred to implementation time

A future session should resolve each of these before or during the milestone that needs them.

- **Exact LLM provider.** ~~Anthropic vs OpenAI.~~ **RESOLVED 2026-05-31: Anthropic (Claude).** Chosen for structured-extraction fidelity and EU-endpoint + zero-retention DPA availability; integrated behind `ILlmClient` with a `ReplayLlmClient` so CI never calls the live API and the provider stays swappable. DPA/contracting due-diligence to start during P4–P6 so P7b is not blocked.
- **Off-site backup provider.** Scaleway Object Storage vs Hetzner Object Storage. Both are EU. Needed at milestone 1 (for the mirror target) but MVP-acceptable to defer until the first real data lands.
- **Vault auto-unseal mechanism.** Cloud KMS (requires a cloud dependency), Shamir with operator-held shards (manual but no dependency), or Transit unseal via a second Vault. Needed at milestone 1.
- **Operator MFA method.** Keycloak admin access and the VPS SSH login both need MFA. YubiKey? TOTP? Needed before the first production deploy.
- **Notification copy and i18n strategy.** Spanish and English at minimum. Static resource files vs a translation management service. Needed at milestone 8.
- **Product analytics.** PostHog self-hosted vs none in v1. Impacts privacy policy. Needed before public launch.
- **Crash reporting.** Self-hosted Sentry vs none. Needed for the first beta.
- **Clinic SSO roadmap.** Keycloak identity-brokering settings for hospital IdPs. Not for v1 but shapes the realm config so future migrations are cheap.

---

## Writing conventions for this document

When future sessions amend this file:

- Use second-person imperative ("Store the DEK...", not "We store the DEK...").
- Flag every new assumption with `ASSUMPTION:` inline so reviewers can challenge it.
- Keep decisions atomic — one row, one rationale, in §A.
- Update §A when a decision changes; do not leave stale rationales behind.
- Reference screens by number from [CLAUDE.md](../CLAUDE.md), not by file path or HTML.
- Pin library major versions only unless a specific patch is known.
- Respect the repo conventions from [CLAUDE.md](../CLAUDE.md): plain files, no emoji, sentence case, EU hosting.
