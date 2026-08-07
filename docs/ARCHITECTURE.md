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
| D-12 helper location + the P4a error contract (P4a, 2026-08-06) | The one shared day-boundary helper D-12 mandates ships as `IUserDayResolver` (`Lumen.Application/Time`, BCL-only) + `UserDayResolver` (`Lumen.Infrastructure/Time`, **singleton**; `TimeZoneInfo` cache; unknown/blank id → falls back to the `users.timezone` default `Europe/Madrid` with a **PII-free** warning that names neither the id nor the user; spring-forward gap → advance to the first instant that exists; fall-back ambiguity → **earliest** instant) + `IUserDayContext`/`UserDayContext` (`Lumen.Api/Time`, **scoped**, one memoised `users` read per request → `UserDayInfo(UserId, Today, BackdateFloor, TimezoneId, NowUtc)`). `UserDayContext` **honours the `User` soft-delete query filter** — a crypto-shredded user resolves to `null`, which every P4a endpoint turns into **404**; that is what makes an erased user's still-valid JWT inert. `UserDayInfo.BackdateFloor` (user-local creation day − 2 y) is **`cycle_events`-only** per D-13; all other dated writes are capped by `Today` alone. **One 400 and one 404 for the whole phase (T3).** The 400 is `application/problem+json` carrying `errors: { <camelCase JSON field name>: [messages] }` plus `detail` = "The request contained invalid data." — the exact fallback string in the shipped `client/lib/core/error/error_mapper.dart`. It is built by `ValidationProblemBuilder` (`Lumen.Api/Validation`), which collects **every** field error before any write (validate-then-act), passes keys through verbatim so indexed paths like `boundaries[0].occurredOn` survive, and reserves the key `request` for cross-field errors. Cross-cutting messages are constants on `ValidationMessages`; endpoint-specific messages are declared and asserted in their own task, and no endpoint invents a new error *body*. `RouteHandlerOptions.ThrowOnBadRequest` is now **explicitly on in every environment** and `ProblemExceptionHandler` maps `BadHttpRequestException` onto that same envelope (`errors.request`), **never echoing `exception.Message`** — a binding failure message quotes the value that failed to bind, which here is health data (§F). Malformed input can therefore no longer surface as a 500 (the old Development behaviour) or as a bodyless 400 (the old Production behaviour). `ThrowOnBadRequest` is pinned by a test that reads `IOptions<RouteHandlerOptions>` off a host built in **Production** — the framework default is `IsDevelopment()`, so a Development-only harness cannot see the line at all. Request logging (`UseSerilogRequestLogging`) sits **outside** `UseExceptionHandler` so it reports the status the client actually received; nested inside it, Serilog's exception path hard-coded 500, and a malformed body was logged at **Error** as "responded 500" with a stack trace quoting the value that failed to bind. The alarm now lives in `ProblemExceptionHandler`, which logs **5xx only** at Error with the exception attached, and 4xx not at all. The 404 body is **code, not a convention**: every task returning 404 calls `NotFoundProblem.Result()` (`Lumen.Api/Validation/NotFoundProblem.cs`, `title` = `NotFoundProblem.Title` = "The requested resource was not found.") — hand-writing `TypedResults.Problem(statusCode: 404, …)` is out, so one typo can no longer fork the "one 404 body" claim. **Tenant isolation returns 404, never 403.** Feature DTOs live in `<Feature>/<Feature>Contracts.cs` with **no `namespace`**, keeping the global namespace the generated Dart client expects. **The spine was retrofitted onto that contract (T4):** `POST /onboarding/start` now answers a named `OnboardingStartResponse` (it returned an anonymous object, which Swashbuckle emits as the untyped `{}` schema the generated Dart client cannot bind to anything) and rejects through `ValidationProblemBuilder`; its four pre-existing messages are **grandfathered byte-identical** and gain only a field key each (`request` / `email` / `password` / `request`). `GET /me` and `PATCH /me` answer `NotFoundProblem.Result()` when the soft-delete-filtered `users` row is gone, so an erased account's still-valid JWT is inert across the whole spine. **`users.timezone` and `users.locale` become mutable through `PATCH /me`**, and BOTH write paths now validate the zone with `TimeZoneInfo.TryFindSystemTimeZoneById` rather than by length: a length-only check let a garbage id persist, and because D-12 resolves the user's day on every request, `UserDayResolver` would emit its PII-free fallback warning once per request for the life of the account — putting the field on `PATCH /me` would have handed that lever to the user. Absent or blank `timezone`/`locale` stay valid on both paths (column defaults at create, unchanged at patch); `locale` is additionally capped at the column's 35 characters and checked for BCP-47 well-formedness through the BCL's own culture-name rules, never an invented pattern. The onboarding routes moved verbatim into `Lumen.Api/Onboarding/OnboardingEndpoints.cs` + `OnboardingContracts.cs`, with the route, `.AllowAnonymous()` and `.RequireRateLimiting("onboarding-start")` pinned by an `EndpointDataSource` metadata test because the OpenAPI document cannot see the last two. | No endpoint may re-derive a day boundary: a wrong "today" silently corrupts day-keyed rows for any non-CET user, and two endpoints disagreeing about it is worse than either being wrong alone. The error body is codegen-visible — it reaches the Flutter client through the OpenAPI contract, where `error_mapper.dart` already parses `detail` and `errors` into a typed `ValidationFailure` — so a per-endpoint 400 shape would fragment client failure handling across twenty endpoints and could not be unwound cheaply; and a 403 on another tenant's row would itself confirm that the id exists. |
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
- **Inbound:** `GET /cycle/calendar?from&to`, `GET /cycle/day/{date}`, `POST /cycle/day/{date}`, `POST /cycle/events`, `POST /cycle/phase-override`.
- **Outbound:** Symptoms (read-only), Hormones (read-only for phase-correction hints).
- **Jobs:** `RecomputeInsightSnapshotJob` (per-user, triggered on-write + nightly).

### 3. Symptoms (screens 9, 12, 13)
- **Entities:** `symptoms`.
- **Inbound:** `POST /checkin/quick`, `GET /symptoms?from&to`, `POST /symptoms`, `PATCH /symptoms/{id}`, `DELETE /symptoms/{id}`.
- **Outbound:** none.
- **Jobs:** none.

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
- **Entities:** writes to `user_profile_enc`, `users` (`locale`, `timezone` — P4a/T4), `user_devices`, `user_keys` (on erasure).
- **Inbound:** `GET /me`, `PATCH /me`, `GET /settings/cycle`, `PATCH /settings/cycle`, `GET /settings/hormones`, `PATCH /settings/hormones`, `GET /settings/notifications`, `PATCH /settings/notifications`, `POST /me/export`, `DELETE /me`.
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

- **`users`** — `id` mirrors the Keycloak subject, `email_hash` (for lookup without plaintext), `locale`, `timezone`, `onboarding_completed_at`.
- **`user_keys`** — `user_id unique`, `wrapped_dek bytea`, `key_version int`, `vault_key_name text`. **Deleting this row performs crypto-shred.**
- **`user_profile_enc`** — `display_name_enc`, `dob_enc`, `bio_enc`.
- **`user_devices`** — `platform` (`ios`/`android`), `push_token`, `last_seen_at`, unique on `(user_id, push_token)`.

### Cycle & symptoms

- **`cycle_events`** — `kind` (`period_start`/`period_end`/`spotting`), `occurred_on date`, `flow_intensity smallint null` (1–4 {spotting, light, medium, heavy} — interim, pending C-04), `notes_enc null`, **`source` (`user`/`onboarding`) — a P4a-proposed vocabulary, not in the 2026-07-08 ratification block**; it exists so the onboarding cycle seed (B15) can be found and moved later without guessing which row it was. `auto_detected` is deliberately not reserved: the set is append-only, so pre-reserving an unsigned C-04 concept buys nothing. Unique on `(user_id, kind, occurred_on)`, **unfiltered** — a tombstone keeps occupying the key, so upserts revive it under `IgnoreQueryFilters()` rather than inserting a second row. **Onboarding-seed merge rule** (pinned on the entity's XML doc, consumed by `POST /onboarding/cycle`): before moving the `source = onboarding` seed row onto a target day, look the target key up ignoring the soft-delete filter and, if a row exists live or tombstoned, **adopt/revive it** — clear `deleted_at`, keep its own `source` and `created_at` — then retire the stale seed row. Never two rows, never an index violation.
- **`cycle_day_logs`** — one per `(user_id, day)`: `pain smallint 0..10 null` (headline pain, D-11 2026-07-08), `mood smallint 1..4`, `energy smallint`, `libido smallint`, `notes_enc`. `energy`/`libido` are **reserved columns with no writer and no CHECK** in P4a — D-10 defers both scales, and the columns exist so the deferred scales land without a migration. Unique on `(user_id, day)`, **unfiltered**, same revive-the-tombstone rule as `cycle_events`.
- **`symptoms`** — `symptom_code` (pain | 20-member non-pain catalog), `region` enum (8 + `unspecified`) + `side` (`front`/`back`, null), `pain_types[]`, `triggers[]`, `intensity smallint 0..10` (D-08 2026-07-08), `occurred_at timestamptz`, **`occurred_on date`**, `notes_enc`. Enums hard-coded in code, not in DB (frozen sets: definitions.md ratification 2026-07-08). **`occurred_on` is the user-local day of `occurred_at`, computed at write time through `IUserDayContext` (D-12) and never client-supplied**; it exists so calendar and range reads are a day-keyed index scan (`(user_id, occurred_on, occurred_at)`) instead of a per-row timezone conversion. It is capped by the user's local today with **no backdate floor** — the floor is `cycle_events`-only (D-13).
- **`cycle_phase_overrides`** *(new, P4a)* — one user correction to one phase boundary of one cycle (screen 14): `cycle_start_on date`, `phase` (`menstrual`/`follicular`/`ovulatory`/`luteal`), `boundary` (`start`/`end`), `occurred_on date`, **`source` (`user_correction`) — a P4a-proposed vocabulary, not ratified**; one member today because P4a has one writer, and the set is append-only so P6 can add its own. Unique on `(user_id, cycle_start_on, phase, boundary)` (**unfiltered**) + index `(user_id, cycle_start_on)`. **P4a stores; it does not interpret** — the four phase codes carry no ordering, no durations and no dates, because the C-01 band sequence is a clinician-UNSIGNED PO-interim value that belongs to P6. **P6 consumption contract:** P6 computes its C-01 bands, then replaces any computed boundary that has a live override row for the same `(cycle_start_on, phase, boundary)`, and flags such a cycle for the C-05/C-09 confidence path. No column changes meaning at P6.

All four tables above carry `created_at`, `updated_at` and a `deleted_at` soft-delete marker (D-13) excluded from every read by an EF query filter; account deletion **hard-deletes** them (§F). Physically they are snake_case tables with **PascalCase column identifiers** and no naming convention — the CHECK literals double-quote the real identifiers, so any column rename silently invalidates them on both Postgres and SQLite. CHECK constraints cover the **frozen numeric scales only** (`pain 0..10`, `mood 1..4`, `flow_intensity 1..4`, `intensity 0..10`); there is deliberately **no CHECK on vocabulary membership**, since the sets are append-only and a DB enum would make every new member a migration.

### Body & activity

- **`body_metrics`** — `metric` enum (`weight_kg`, `waist_cm`, etc.), `value_enc`, `source` (`manual`/`apple_health`/`google_fit`), `measured_at`.
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
- **`user_insight_snapshot`** — one per user: `current_phase`, `phase_start`, `confidence smallint`, `missing_data_cards_enc jsonb`, `refreshed_at`.

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
- The job: deletes `user_keys` row, empties push tokens, tombstones the `users` row (keep id for FK integrity), deletes MinIO objects under `{user_id}/`, writes an entry to `admin_audit_log`.
- Ciphertext remains in row-level tables but is permanently unreadable. Backups containing encrypted blobs are also unreadable for that user from the moment the DEK row is gone. Document this in the privacy policy.

### Logging

- Serilog with a PII-scrubbing enricher: redact emails, user IDs in URLs (`/users/{guid}` → `/users/{sha256-short}`), never log request bodies for `labs`, `symptoms`, `cycle_day_logs`, `body_metrics`, or any `me`/`settings` endpoint.
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
