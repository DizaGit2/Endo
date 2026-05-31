# Lumen — Build-Strategy Design

**Date:** 2026-05-31
**Status:** Approved design → ready for implementation planning
**Scope:** *How* to build Lumen (sequencing, session orchestration, testing, environment, client integration). It does **not** restate *what* to build — that is [`docs/ARCHITECTURE.md`](../../ARCHITECTURE.md), the single source of truth for topology, the 10-module catalogue, the data model, encryption, jobs, and GDPR posture. Read that first; this document assumes it.

This spec was produced in a design session that fanned out independent analyses (three phase-decomposition lenses + four cross-cutting designs), synthesized them into one roadmap, and adversarially audited the result (three lenses, 21 findings, **zero blockers**). The audit fixes are folded in below.

Companion analyses (committed alongside this spec, referenced throughout):
- [`2026-05-31-build-strategy/orchestration.md`](2026-05-31-build-strategy/orchestration.md) — session-orchestration mechanics, plan format, kickoff prompt, review protocol, git strategy, anti-drift.
- [`2026-05-31-build-strategy/testing.md`](2026-05-31-build-strategy/testing.md) — phase-aware testing & verification, the GDPR proof suite, contract gate, coverage ratchet, per-phase gates.
- [`2026-05-31-build-strategy/environment.md`](2026-05-31-build-strategy/environment.md) — Windows prerequisites, the Flutter-install trigger, tooling decisions, verify-environment checklist.
- [`2026-05-31-build-strategy/flutter.md`](2026-05-31-build-strategy/flutter.md) — Flutter project structure, OpenAPI→Dart pipeline, screen→endpoint→phase map, online-only cache, OIDC, theming.

---

## 1. Goal

Build a **production-grade .NET 10 backend and a production-grade Flutter client**, both to full rigor (real infra, tests, GDPR posture), faithful to the architecture doc. This is not a prototype; "done" means deployable to the EU VPS with the safety-critical machinery (envelope encryption, crypto-shred erasure, the inference engine, the LLM lab-parse pipeline) proven by executable tests.

## 2. Decisions locked in this session

| # | Decision | Note |
|---|---|---|
| D1 | **.NET 10** is the target framework | Architecture doc updated from .NET 8 (which is not installed; 9 and 10 are, and 9 is effectively EOL). `global.json` pins 10 so a build never silently uses the side-by-side SDK 9. |
| D2 | **Walking-skeleton, risk-retiring** sequencing | §3 below. |
| D3 | **Plan-driven fresh sessions** | One living plan in the repo; each fresh session executes exactly one phase; review checkpoint after each. Maps onto superpowers `writing-plans → executing-plans / subagent-driven-development`. |
| D4 | **LLM provider = Anthropic (Claude)** | Resolves `ARCHITECTURE.md §I`. EU endpoint + zero-retention DPA; behind an `ILlmClient` seam with a `ReplayLlmClient` so CI never calls the live API and the provider stays swappable. DPA due-diligence starts during P4–P6 so P7b isn't blocked. |
| D5 | **Lab PDF encryption is server-side** | Reconciles the `ARCHITECTURE.md §D` vs `§E` contradiction in favor of server-side AES-256-GCM with the user's DEK — consistent with the locked "server-held DEK, not password-derived" key-custody decision. The client never holds the DEK. |
| D6 | **Review cadence** | Checkpoint after every phase; the four safety-critical phases (P1, P2, P6, P7b) get a deeper `code-review`-skill pass plus an adversarial mutation spot-check. |
| D7 | **Flutter SDK installed at P3a**, never earlier | The first phase with client work. P0–P2 are fully verifiable by backend integration tests. |

## 3. Approach: risk-retiring walking skeleton

Stand up the **minimal** infra a first slice needs (Caddy + Postgres + Keycloak + Vault), then prove the **entire architectural spine end-to-end in one thin vertical slice**:

```
HTTPS → Caddy → Keycloak JWT validation → Keycloak admin user-create →
Vault Transit per-user DEK → AES-256-GCM envelope-encrypted Postgres write → decrypt on GET /me
```

Then immediately prove **crypto-shred erasure** while that crypto code is fresh and exactly one encrypted table exists (erasure is one-shot and irreversible — prove it before encrypted tables accumulate). Then thicken module by module. The two genuinely novel/dangerous pieces — the deterministic inference engine and the LLM lab-parse pipeline — are isolated into their own deeply-reviewed phases. Infra is added **only when a phase first needs it** (MinIO+ClamAV at labs; FCM/APNs at notifications; observability sidecar last).

**Why this over the alternatives** (the three decomposition lenses agreed on the spine; the audit confirmed it):
- *Infrastructure-first* front-loads MinIO/ClamAV/observability the first feature never touches and delays the "does it actually work end-to-end?" signal.
- *Module-by-module breadth* forces its very first module (Onboarding) to build the auth+encryption spine anyway — so it collapses into the skeleton, minus the intentionality of proving the cross-cutting risk first.
- The envelope-encryption and Keycloak-auth concerns touch *almost every* entity and endpoint; proving them in slice 1 means every later module inherits a validated pattern instead of retrofitting crypto into ten modules.

## 4. The phase roadmap

19 phases, ~30–35 fresh sessions. ⚠ = safety-critical (deep review). Each phase = one fresh session unless `sessions` says otherwise. `dependsOn` is the hard technical prerequisite.

> Phase IDs are canonical here. The companion analyses were written before final synthesis and use their own illustrative numbering — defer to this section.

### Era 0 — Foundation & spine

#### P0a — Compose stack + realm + health liveness  · 1 session · dependsOn: —
- **Goal:** smallest production-shaped stack the skeleton needs, healthy via one `docker compose up`.
- **Infra:** `caddy:2` (TLS via internal CA in dev, HTTP→HTTPS, HSTS, routes `api.localhost`→api and `auth.localhost`→keycloak); `postgres:16` (DBs `lumen`+`keycloak`; extensions `pgcrypto`,`uuid-ossp`,`pg_stat_statements`); `quay.io/keycloak/keycloak` (`start-dev --import-realm`, realm `lumen` from `deploy/keycloak/realm-lumen.json` with confidential `api` client, public mobile client, `lumen-admin` role, provisioning service account); `hashicorp/vault` (dev mode, Transit enabled, `lumen-dev-kek`). Placeholder `api` returning `/health` 200.
- **Exit:** all services healthy; `GET /health` 200 through Caddy over TLS; OIDC discovery reachable; Vault Transit key exists; both DBs+extensions present; `dotnet build` of empty solution on .NET 10 (`global.json` pins `10.0.300`). `/health/ready` is a **shallow TCP reachability** check only (no EF/Vault SDK yet — keeps P0 free of app logic; *audit fix V3-P0-minor*).

#### P0b — Living implementation plan document  · 1 session · dependsOn: P0a
- **Goal:** author `docs/superpowers/plans/lumen-build.md` — the single living plan (§0 orchestration rules, §1 status ledger, §2 architecture invariants, §3 phase catalogue with a per-phase kickoff prompt, §4 build-time decision log, §5 glossary of paths/commands). Format and templates: see [orchestration companion](2026-05-31-build-strategy/orchestration.md).
- **Exit:** plan exists; ledger has `NEXT PHASE TO RUN` + SHA stamp; §2 invariants pin the spine (Caddy→JWT→Vault DEK→encrypted Postgres; .NET 10; online-only; realm `lumen`; crypto-shred); every phase stub carries its kickoff prompt. (*Audit fix V3-P0-major: P0 split into P0a/P0b so neither overruns one session.*)

#### P1 ⚠ — Walking-skeleton spine: auth + envelope encryption  · 2 sessions · dependsOn: P0a, P0b
- **Goal:** replace the placeholder with the real solution and prove the whole spine end-to-end in one thin slice. The load-bearing `IUserCryptoContext` that every later encrypted table reuses must be correct and exhaustively tested before any breadth.
- **Entities:** `users`, `user_keys` (wrapped DEK — the crypto-shred anchor), `user_profile_enc`.
- **Modules/endpoints:** EF Core + Npgsql; first migration; Keycloak JWT bearer middleware (issuer/audience/realm-role mapping, `sub`→`user_id`); `VaultTransitClient` + Keycloak Admin API client; `IUserCryptoContext` (request-scoped DEK unwrap, per-field AES-256-GCM IVs); DEK provisioning (idempotent); `POST /onboarding/start`; `GET /me`, `PATCH /me`; Swashbuckle emitting `backend/contract/openapi.json` (committed); Serilog PII-scrubbing enricher; OTLP exporter (target stubbed); ASP.NET global rate limiter **enforced**.
- **Key tests:** full-spine Testcontainers test (real Postgres+Vault+Keycloak); `EncryptedColumns_AreNotPlaintext`; tenant isolation; DEK request-scoped + zeroed, concurrency-safe; tampered GCM tag fails; crypto-shred precondition (delete `user_keys` → undecryptable); architecture tests (NetArchTest); **real `429` global rate-limit test + an abuse test for `POST /onboarding/start`** (*audit fix V2-P1-major: the costliest privileged endpoint is born protected, not "scaffolded"*).
- **Exit:** spine green in one automated test; plaintext DEK never persisted/logged/cached beyond request; deep review passed; `ci-backend.yml` runs unit+integration on PR; 60% coverage floor on the spine; this slice documented as the reference pattern for all later encrypted modules.

#### P2 ⚠ — Crypto-shred erasure + Hangfire + job-scoped crypto  · 1 session · dependsOn: P1
- **Goal:** prove right-to-erasure now, while P1 crypto is fresh. Introduce Hangfire (Postgres storage) — the job runtime every later feature needs — validated by its first real job.
- **Entities:** `user_devices`, `admin_audit_log`.
- **Modules/endpoints:** `DELETE /me` (enqueue `CryptoShredJob`, disable Keycloak user, 202); Hangfire registered, dashboard gated to `lumen-admin`; `IJobCryptoContext` (job-scoped unwrap/use/discard); `CryptoShredJob` (delete `user_keys`, empty push tokens, tombstone `users`, **MinIO object delete structured as a tracked no-op until MinIO exists**, audit entry; idempotent).
- **Key tests:** the headline `CryptoShred_MakesCiphertextUnreadable`; backup-bytes-before-shred no longer decrypt; idempotent; Hangfire smoke; **job-scoped logging is PII/DEK-scrubbed** (*audit fix V2-P2-minor: don't defer job-log scrubbing to P12*); **`DELETE /me` enqueue-flood guard** (*audit fix V2-P1-major*).
- **Exit:** erasure provably unrecoverable; Hangfire operational; deep review passed (no path recovers a shredded user); crypto-module coverage floor 85%; `Lumen.Security.Tests` GDPR baseline established. **Tracked forward-reference:** the MinIO-deletion branch is *finalized and positively tested in P7a and re-verified in P9b* (*audit fix V1-P2-major / V2-P9-major — the original plan left this a permanent no-op*).

### Era 1 — Client foundation

#### P3a — Flutter foundation: toolchain + scaffold + theming + OpenAPI pipeline  · 2 sessions · dependsOn: P2
- **Goal:** all client foundation that has no endpoint dependency. (*Audit fix V3-P3-major: P3 split into P3a/P3b — the most over-scoped phase in the original.*)
- **Infra:** install Flutter/Dart SDK + Android Studio/SDK on Windows; `flutter doctor` green (iOS noted as macOS/CI-only). OpenAPI→Dart pipeline (`openapi_generator`, dio + built_value) + CI drift guard.
- **Client work:** feature-first app scaffold mirroring the 10 modules; GoRouter `StatefulShellRoute` 5-tab shell; Riverpod (code-gen); theming port — `LumenColors` ThemeExtension (light/dark exact tokens), fixed `HormonePalette`, light/dark `PhasePalette`, two font weights; `alchemist` golden harness; generate the Dart client from P1's committed spec; wire static screens 1, 36, 37.
- **Note:** D5 (server-side PDF encryption) is already resolved, so no client crypto-storage assumption is built wrong (*audit fix V2-P7-minor: resolve before client work, not at P7*).
- **Exit:** `flutter doctor` green recorded in plan; golden tests pass for static screens in both themes; `ThemeData` token assertions match CLAUDE.md exactly; OpenAPI pipeline + drift guard operational; client coverage floor 60%.

#### P3b — Client spine: OIDC + online-only cache + live screens  · 2 sessions · dependsOn: P3a, P1
- **Goal:** prove the client half of the spine end-to-end. (*Audit fix V3-P3-minor: P3's hard prerequisite is P1's endpoints + committed spec; P2 is a soft ordering dep.*)
- **Client work:** Keycloak OIDC (`flutter_appauth` Authorization Code + PKCE, realm `lumen`, scopes `openid profile offline_access`); tokens in Keychain/Keystore (`flutter_secure_storage`); Dio interceptor (bearer attach + single-flight 401 refresh + PII-safe logging); online-only `CachedQuery` (stale-while-revalidate reads, `NetworkRequired` empty state, **no offline write queue**); encrypted Hive boxes purged on logout/background-lock; wire screen 2 (account → OIDC + `POST /onboarding/start`) and screen 31 (profile → `GET /me`/`PATCH /me`).
- **Key tests:** integration_test login → `GET /me` renders decrypted profile; single-flight refresh; **Hive box ciphertext unreadable without the secure-storage key** (*audit fix V2-P3-minor: device-loss baseline*); online-only contract (a write while offline errors and does NOT enqueue).
- **Exit:** a real device logs in via Keycloak and renders the decrypted profile through Caddy — client half of the walking skeleton proven; generated client is the single source of API calls.

### Era 2 — Core logging breadth

#### P4a — Backend: onboarding completion + Cycle + Symptoms  · 3 sessions · dependsOn: P3b
- **Goal:** first wide band of user-owned encrypted CRUD reusing `IUserCryptoContext`. (*Audit fix V3-P4-major: split backend (P4a) from Flutter (P4b) along the natural test boundary.*)
- **Entities:** `cycle_events`, `cycle_day_logs`, `symptoms`, `user_insight_snapshot` (written as an **unmistakably non-clinical placeholder** until P6).
- **Endpoints:** onboarding `baseline`/`goals`/`hormones`/`notifications`/`complete`; Cycle `calendar`/`day`/`events`/`phase-override`; Symptoms `checkin/quick`/CRUD; `GET/PATCH /settings/cycle`; **a thin `user_devices` upsert endpoint** (table exists from P2) so onboarding notification-prefs has a real registration target (*audit fix V1-P4-minor*); migrations; OpenAPI + Dart client regenerated in the same PR.
- **Exit:** onboarding completes and sets `onboarding_completed_at`; all endpoints pass integration + tenant-isolation + encryption tests; migrations apply on a fresh container with no pending model changes; global coverage ratchets to ≥70%.

#### P4b — Flutter: core logging screens  · 2 sessions · dependsOn: P4a
- **Client work:** wire screens 3–14 and 32 (onboarding rest, dashboard with placeholder snapshot, cycle calendar/day/phase-correction-write, quick check-in bottom sheet, symptom form, body map region-enum + intensity); designed error/retry states on every write screen (9, 11, 12, 13).
- **Exit:** screens 3–14, 32 work against the live backend in both themes; dashboard placeholder is unmistakably non-clinical; golden + integration tests green; drift guard clean.

#### P5 — Body + Activity + Treatment  · 2 sessions · dependsOn: P4a
- **Goal:** low-risk CRUD breadth, no infra/inference dependency.
- **Entities:** `body_metrics`, `activity_entries`, `medications`, `medication_schedules`, `medication_logs`, `ref_medication` (**seeded via migration**; live-edit Admin UI lands in P10).
- **Endpoints:** Body `calendar`/`entry`; Activity `calendar`/`entry`; Treatment `medications` CRUD + `log` + `schedule` (reads `ref_medication`). Screens 22–27 wired with error/retry states.
- **Exit:** all three modules pass integration + authorization tests; encrypted columns ciphertext-only; schedules persisted in a form the P9a nightly job can read; screens 22–27 work in both themes.

### Era 3 — Clinical engines

#### P6 ⚠ — Inference engine + recurring jobs + matviews  · 2 sessions · dependsOn: P4a
- **Goal:** the first genuinely-novel clinical piece — deterministic C# rules for phase/confidence/missing-data, driven by `ref_insight_rule`, plus the three materialized views and debounced refresh jobs. Replaces the P4 placeholder snapshot with real computed values. **Hangfire is already running (from P2); this phase only adds recurring/debounced jobs** (*audit fix V3-P6-minor — don't re-bootstrap Hangfire*).
- **Entities:** `user_insight_snapshot` (now computed), `ref_insight_rule` (seeded), `mv_hormone_series_daily`, `mv_cycle_phase_summary`, `mv_insight_metrics`.
- **Endpoints:** the engine (`Lumen.Domain`, parameterized by `ref_insight_rule`, not hard-coded); `RecomputeInsightSnapshotJob` (on-write via domain events + nightly 08:00 Europe/Madrid, clock-injected); `RefreshMatviewsJob` (nightly + 60s debounced on-write); `GET /insights/confidence`, `/insights/missing-data`, `/hormones/{id}`. Screens 8 (real confidence ring), 14 (recomputed confidence), 15+landscape, 16, 20-base, 21, 33.
- **Key tests:** golden-fixture unit tests (regular/irregular/sparse/conflicting histories → expected phase/confidence/cards); determinism; debounce coalescing; **safe-failure framing — sparse/conflicting input yields an explicit low-confidence "not enough data" state, never a confident wrong phase, with non-clinical wording** (*audit fix V2-P6-minor*); hormone chart shows an explicit "no lab data yet" empty state until P7 populates `mv_hormone_series_daily` (*audit fix V1-P6-minor*).
- **Exit:** engine matches every golden fixture and is reproducible; matviews refresh nightly + on-write; deep review passed incl. mutation spot-check (break a rule → a golden test goes red); inference-rules coverage floor 90%.

#### P7a — Labs infra + upload + scan + encrypted store  · 2 sessions · dependsOn: P5, P6
- **Goal:** the second-scariest infra cluster, without the LLM yet. (*Audit fix V3-P7-major: split P7 into infra/upload (P7a) and parse/trust-boundary (P7b).*)
- **Infra:** `minio` (buckets `lab-uploads`,`reports`,`avatars`,`exports`,`backups`); `clamav` (INSTREAM, internal only).
- **Endpoints:** `POST /labs` (MIME + size ≤20MB + magic-byte validation → ClamAV INSTREAM scan → **server-side** AES-256-GCM DEK-encrypt → MinIO `lab-uploads/{user_id}/{lab_id}.pdf.enc` → quota check → enqueue parse); `GET /labs/{id}`; `labs` row lifecycle. **`INotificationDispatcher` port introduced as a no-op/log-only seam** so the parse job has something to call (*audit fix V1-P7-major*). **Finalize `CryptoShredJob` MinIO recursive delete of `{user_id}/`** now that objects exist, with a test that uploads an encrypted lab, runs erasure, and asserts the object is *gone* (*audit fix V1-P2-major / V2-P9-major*).
- **Key tests:** ClamAV rejects EICAR (422, counter incremented, nothing stored); magic-byte/MIME/size rejection; `LabPdf_InMinio_IsCiphertext`; crypto-shred object-deletion proof.
- **Exit:** a scanned, server-side-encrypted PDF lands in MinIO; EICAR rejected; erasure physically removes objects.

#### P7b ⚠ — LLM parse + validate + confirm  · 2 sessions · dependsOn: P7a
- **Goal:** the hardest module and the LLM trust boundary. **Ultra-effort review.**
- **Entities:** `lab_result_drafts`, `lab_results`, `ref_hormone_range` (seeded for all 7 hormones with unit whitelist + physiological ranges).
- **Endpoints:** `ParseLabJob` (decrypt → PdfPig text extract → **Anthropic** via `ILlmClient` with source-generated `System.Text.Json` schema + few-shot ES/EN → validate against `ref_hormone_range` whitelist + 1.5×-widened ranges + `measured_on ≤ today` → persist encrypted drafts → notify via the P7a port; 3 retries on transient 5xx, non-retryable → `needs_manual` + fallback push); `GET /labs/{id}/drafts`; `POST /labs/{id}/confirm` (transactional draft→`lab_results`, **server-side re-validation — never trust the client**, delete drafts); daily LLM quota. Screens 17, 18, 19, 20 (lab cards).
- **Key tests:** **record-replay** LLM (committed PII-scrubbed fixtures; CI never calls the live API); validation matrix (unknown code, bad unit, just-inside/just-outside the widened band, future date, garbage output → each → `needs_manual`, no draft); quota → `needs_manual` + fallback; confirm re-validates + rolls back on partial failure; mutation spot-check that the range guard has teeth.
- **Exit:** end-to-end upload → scan → encrypted store → parse → drafts → confirm → value on the hormone chart; no unvalidated value ever reaches `lab_results`; deep (ultra) review passed; lab-pipeline coverage floor 85%.

### Era 4 — Reports & comms

#### P8 — Reports: doctor report + insights hub  · 2 sessions · dependsOn: P5, P6, P7b
- (*Audit fix V1-P8-minor: P5 added to dependsOn explicitly — Reports reads Treatment.*)
- **Entities:** `reports`. **Endpoints:** `GET /insights/hub`; `POST /reports/doctor` → `GenerateDoctorReportJob` (QuestPDF/SkiaSharp, no headless Chromium, DEK-encrypted to MinIO `reports/`); `GET /reports/{id}`; `GET /reports/{id}/download` (owner-only stream). Rate limit 5/day. Screens 28, 29, 30 (in-app download only — no server-side sharing per `§A`).
- **Exit:** user generates and downloads a well-formed DEK-encrypted PDF; only owner can download; report stored ciphertext; screens 28–30 in both themes.

#### P9a — Notifications + nightly dispatch  · 2 sessions · dependsOn: P7b, P8
- **Infra:** FCM + APNs sender config (subprocessors; creds via sops `.env`); ES/EN i18n resource files.
- **Endpoints:** `NotificationDispatcher` (real FCM/APNs **behind the P7a port**, faked in CI); device register/refresh; `NightlyNotificationDispatchJob` (08:00 Europe/Madrid: medication reminders from P5 schedules + lab-ready hook from P7b + missing-data nudges). Screens 7 (push token), 34.
- **Key tests:** mocked FCM/APNs recipient selection + localized templates + TZ scheduling; device upsert unique on `(user_id, push_token)`; no PII in payloads.
- **Exit:** a device receives a real push from nightly dispatch and a med reminder; lab-ready push deep-links to screen 20.

#### P9b — GDPR data export  · 1–2 sessions · dependsOn: P9a
- (*Audit fix V3-P9-minor: export split from notifications — independent feature, own infra.*)
- **Endpoints:** `POST /me/export` → `BuildDataExportJob` (zip per-module JSON + decrypted original lab PDFs → MinIO `exports/` → 7-day signed URL emailed → lifecycle delete); email sender; off-site EU backup target wiring.
- **Key tests (export is the one place all decrypted PII concentrates — treat as high-blast-radius):** **per-user rate limit on export**; signed URL short-lived + **lifecycle deletion positively verified (not just creation)**; **export job's bulk-plaintext path is log-scrubbed**; re-verify erasure UX from the UI incl. **MinIO `exports/` deletion on crypto-shred** (decrypted zips are NOT protected by crypto-shred, so they must be physically deleted) (*audit fix V2-P9-major*). Consider step-up auth before export (recorded as a decision).
- **Exit:** export produces a downloadable zip that expires after 7 days; right-to-access (export) and right-to-erasure (re-verified) both work end-to-end; screen 35 in both themes.

### Era 5 — Ops & hardening

#### P10 — Admin reference-data module  · 1 session · dependsOn: P5, P6, P7b
- Razor pages under `/admin` gated by `lumen-admin`; live CRUD over `ref_hormone_range`/`ref_medication`/`ref_insight_rule` (already seeded by their consuming phases); `admin_audit_log` before/after on every mutation; internal reference-data read endpoints as the single source of truth.
- **Exit:** an admin edits reference data with every change audited; non-admins 403; edits propagate to lab-parse validation (P7b) and the inference engine (P6); cross-module consistency tested.

#### P11 — CI/CD + backups + secrets + prod hardening  · 2 sessions · dependsOn: P9b, P10
- GitHub Actions CD (build→GHCR→SSH deploy, gated behind both CI workflows); nightly `pg_dump` + `mc mirror` to off-site EU bucket + monthly restore drill (**proving shredded users stay unreadable after restore**); sops/age secrets injected at runtime only; **Vault auto-unseal resolved for prod** (closes `§I`); operator MFA; production Caddyfile (real domains, Let's Encrypt, HSTS, CSP, edge rate limits); Trivy + `dotnet list package --vulnerable` now blocking on High/Critical.
- **Exit:** a merge deploys to the VPS; nightly backups land off-site; restore drill green; auto-unseal so a restart doesn't hang sealed; reproducible deploy runbook.

#### P12a — Observability sidecar  · 2 sessions · dependsOn: P11
- (*Audit fix V3-P12-minor: infra work split from QA work.*)
- Sidecar VPS (prometheus, loki, promtail, grafana, alertmanager, node/postgres exporters; WireGuard; Grafana via Caddy subdomain w/ basic-auth); P1 OTLP exporter retargeted; dashboards (latency p50/p95/p99, error rate, Hangfire depth/failures, LLM cost/day, slow queries, backup status); alerts (5xx>1%, Hangfire failures, LLM cost>budget, disk>80%, backup>26h, WireGuard down); Loki ingestion PII-scrubbed.
- **Exit:** dashboards populated from real metrics; every alert verified to fire under a simulated condition; sidecar survives a main-VPS outage.

#### P12b — Final production-readiness pass  · 2 sessions · dependsOn: P12a
- Seeded demo account; walk all 37 screens + screen-15 landscape against the live backend in both themes with empty/error/online-failure states; full 5-tab nav + deep-link/push-tap; light/dark + sentence-case + no-emoji + two-weight audit vs CLAUDE.md; accessibility pass; load smoke test; final GDPR/security sign-off.
- **Exit:** every screen verified end-to-end in light+dark with correct states; full backend + Flutter suites green; security scans (now blocking) clean; system production-ready and demoable on a clean device; remaining `§I` items resolved or moved to a post-v1 backlog (product analytics, clinic SSO, Apple Health/Google Fit sync).

### Dependency shape (sanity)

`P0a→P0b→P1→P2→P3a→P3b→P4a→{P4b, P5, P6}`; `P7a` needs `P5+P6`; `P7b` needs `P7a`; `P8` needs `P5+P6+P7b`; `P9a` needs `P7b+P8`; `P9b` needs `P9a`; `P10` needs `P5+P6+P7b`; `P11` needs `P9b+P10`; `P12a` needs `P11`; `P12b` needs `P12a`. Acyclic; verified by the dependency-correctness audit.

## 5. Orchestration mechanics (summary — full detail in the [companion](2026-05-31-build-strategy/orchestration.md))

- **Execution model — per-phase orchestrator + subagents ("Model C"):** you run **one fresh Claude session per phase**. That session is the *orchestrator*: it executes the phase via **`subagent-driven-development`**, dispatching a fresh subagent per task (each with its own isolated context), running review subagents, and committing — so you do **not** paste anything per task. You paste the phase's 6-line kickoff prompt **once** to start the session, then review at the phase boundary. The fresh-session-per-phase boundary is deliberate: it bounds the orchestrator's context (better reliability across 19 phases) and *is* the human review gate. Within a phase you are hands-off except (a) genuinely interactive steps a subagent cannot perform — the Flutter SDK install + `flutter doctor --android-licenses` + Android Studio wizard in P3a — and (b) any decision the session surfaces as `BLOCKED`. The full step-by-step operating procedure for the person driving and reviewing the build is the **[build runbook](../RUNBOOK.md)**.
- **One living plan** at `docs/superpowers/plans/lumen-build.md`. A **status ledger at the top** is the *only* authority for "done"; an agent may write `NEEDS_REVIEW`, only the **human** writes `DONE`. The ledger carries `NEXT PHASE TO RUN` + a repo-HEAD SHA stamp (a cheap staleness detector).
- **A 6-line kickoff prompt** per phase (stored filled-in inside each phase) scopes reading to the plan phase + the specific `ARCHITECTURE.md §`s + CLAUDE.md, names the executor skill, pins ".NET 10 only", forbids starting other phases, and ends at `NEEDS_REVIEW` for the human checkpoint.
- **Three-layer progress:** step checkboxes (agent) → a per-phase `STATUS` block with **pasted command output, not prose** → ledger `DONE` (human). A partial session resumes purely from the repo (ledger + STATUS + git), never from chat history.
- **Git:** branch-per-phase off `main` in a worktree; Conventional Commits, one commit per task; one PR per phase whose body *is* the STATUS block; merge only after the checkpoint; tag `phase-NN`.
- **Maps onto superpowers:** `writing-plans` (authors the plan once up front) → per phase `using-git-worktrees` → `subagent-driven-development` (or `executing-plans` for imperative infra phases like P0a) → `code-review` (high for P1/P2/P6, ultra for P7b) → `finishing-a-development-branch`; `verification-before-completion` gates every `NEEDS_REVIEW` claim.
- **Anti-drift:** docs change in the same branch as the code that invalidates them; the plan *references* `ARCHITECTURE.md §` rather than pasting; resolved `§I` questions update both the architecture doc `§A` and the plan `§4` atomically; a 60-second drift scan at each checkpoint.

## 6. Testing & verification (summary — full detail in the [companion](2026-05-31-build-strategy/testing.md))

- **A phase is not done until its gate command exits 0 and the output is pasted.** Evidence before assertions.
- **Pyramid:** unit (pure domain rules, validators, crypto-algorithm wrapper, PII enricher) → integration (Testcontainers: real Postgres/Keycloak/Vault, +MinIO/ClamAV from P7a) → contract (OpenAPI↔Dart) → a few E2E smoke flows. Shared `Lumen.TestKit` holds fixtures, a Keycloak token minter, `FakeTimeProvider`, Respawn, and the `ReplayLlmClient`. Determinism is structural: `IClock`/`TimeProvider` everywhere, enforced by an architecture test; no live LLM, no network in unit tests.
- **GDPR proof suite** (`Lumen.Security.Tests`, negative-first): envelope-encryption-at-rest, crypto-shred-unreadable (incl. backup bytes + **MinIO object deletion** from P7a), rate limits + LLM quota, physiological-range validation, ClamAV-EICAR, PII-scrubbed logs (request *and* job paths).
- **Contract gate:** Swashbuckle emits `backend/contract/openapi.json` (committed); CI fails if the regenerated spec diffs, if the regenerated Dart client diffs, on an unapproved breaking change (`oasdiff`), or if a live response violates its response schema. Server, spec, and client cannot silently diverge.
- **Flutter:** `flutter analyze` clean + widget tests (loading/empty/error/populated) + **golden tests in both themes** (`alchemist`, CI-stable) + token-value assertions vs CLAUDE.md + integration_test against the seeded live stack for client phases.
- **Coverage ratchets** (never down): 60% spine → 85% crypto → 70% global → 90% inference → 85% lab → 80% global at P12b. Safety modules carry their own floors.

## 7. Environment & prerequisites (summary — full detail in the [companion](2026-05-31-build-strategy/environment.md))

- **Ready today:** .NET SDK 10.0.300 (and 9.0.314 side-by-side → pin via `global.json`), ASP.NET 10.0.8, Docker 29.5.2 + Compose v5.1.3 (daemon running), Node v24.13.0, Git 2.51, `dotnet-ef` 10.0.0 global, winget 1.28, choco 2.6. **The backend walking skeleton can start immediately.**
- **Missing by design:** Flutter/Dart/JDK/Android Studio (install at P3a — the trigger is the first client session, never earlier), sops/age (secrets phase), mkcert (optional).
- **Dev loop:** Terminal A `docker compose up -d` only the services this phase needs; Terminal B `dotnet watch`; migrations via `dotnet ef`; tests via Testcontainers (needs the Docker daemon, not the dev compose stack).
- **Tooling decisions:** Swashbuckle for OpenAPI (committed tool manifest), `openapi_generator` (dart-dio + built_value) for the client, Vault dev-mode locally / operator-unseal documented for prod, Caddy `tls internal` locally / Let's Encrypt in prod, Keycloak realm import via `--import-realm`.
- **Every phase starts with the read-only verify-environment checklist** (core toolchain + only the infra that phase needs); a red `flutter doctor` blocks only the client phases.

## 8. Flutter integration (summary — full detail in the [companion](2026-05-31-build-strategy/flutter.md))

- **Riverpod (code-gen) + GoRouter**, feature-first layout mirroring the 10 backend modules so a phase's client work stays in one folder.
- **OpenAPI→Dart** generated from the committed spec snapshot, regenerated once per endpoint-adding phase **in the same PR**, enforced by the CI drift guard.
- **Screen→endpoint→phase map** is the scheduling backbone (full table in the companion): a screen is wired only after its endpoints are integration-tested green. The skeleton already wires screens 1/2/31/36/37 through the *real* spine — the first demo is a live login, not a curl.
- **Online-only + encrypted Hive:** stale-while-revalidate reads, a `NetworkRequired` empty state, **writes never queue** (every write screen has a designed error/retry state); cache encrypted at rest, purged on logout/erasure.
- **Keycloak OIDC** via `flutter_appauth` + PKCE, tokens in Keychain/Keystore, single-flight refresh in a Dio interceptor, GoRouter auth+onboarding redirect guard.
- **Theming** ports CLAUDE.md tokens to a `LumenColors` ThemeExtension (light/dark), hormone colors as a fixed non-themed palette keyed off the wire `hormone_code`, phase colors as light/dark pairs, two font weights on the system stack; golden tests are the fidelity gate.
- **Interleave phase-by-phase** (not a parallel track): respects no-wiring-before-endpoints, keeps OpenAPI lockstep cheap, and makes each phase one coherent demoable reviewable unit.

## 9. Audit corrections folded in

The adversarial audit found **0 blockers**; structure was sound. All 21 findings are addressed above and tagged inline (`*audit fix …*`). The load-bearing ones:

1. **Crypto-shred MinIO deletion** was a permanent no-op (built in P2 against not-yet-existing MinIO, never finalized). Now finalized + positively tested in **P7a** and re-verified for the decrypted export zips in **P9b**. This was the one genuine GDPR-erasure hole.
2. **Rate limits** on `POST /onboarding/start` and `DELETE /me` are tested **at birth** (P1/P2), not "scaffolded then deferred".
3. **Data export** (the one place all decrypted PII concentrates) gets a per-user rate limit, log-scrubbing, and proven lifecycle deletion.
4. **Notification port** introduced as a no-op seam in P7a so `ParseLabJob` never calls a service that doesn't exist until P9a.
5. **Four over-scoped phases split** (P0, P3, P4, P7) plus two minor splits (P9, P12) so each phase is a credible single fresh session.
6. **Job-path PII/DEK log scrubbing** and **inference safe-failure framing** are tested where they're introduced, not deferred to P12.

## 10. Risks (carried into the plan's risk register)

- The four safety-critical phases carry the most irreversible risk — treat green tests skeptically; the mutation spot-check (break the guard, confirm the safety test goes red) is mandatory there.
- P4a (3 sessions) and P7b are the tightest; if P7b's record-replay harness or the LLM contracting slips, the `ILlmClient` seam keeps test work moving and P7b can split further.
- Online-only means a backend outage blocks writes — every write screen needs an explicit network-required state, re-verified in P12b.
- Reference-data edits in P10 can silently change safety-critical behavior (lab validation, inference) — full before/after audit logging + cross-module tests.
- Plaintext DEK must never leak into logs, matview/report/export jobs, or export zips — cross-cuts P1/P2/P6/P7/P8/P9 and gets a final security re-audit at P12b.

## 11. Decisions resolved / open questions

- **Resolved this session:** .NET 10 (D1); LLM provider = Anthropic (D4, closes `§I`); lab PDF encryption = server-side (D5, reconciles `§D`/`§E`). All three written back into `ARCHITECTURE.md`.
- **Resolved during the build, tracked in plan §4:** off-site backup provider (P9b/P11), Vault auto-unseal for prod (P11), notification copy/i18n (P9a), operator MFA + crash reporting (P11).
- **Deferred to post-v1 backlog:** product analytics, clinic SSO, Apple Health / Google Fit sync.

### 11.1 Missing business rules & definitions — the gap register

This architecture is a *technical* spec; it does not enumerate the actual product/clinical rules, enums, reference ranges, thresholds, or copy. An audit of the 37 screens against the docs found **~108 distinct gaps (27 blockers)**, captured in **[`gap-register.md`](2026-05-31-build-strategy/gap-register.md)** and tagged to the earliest phase that needs each. **Resolving a phase's blocker entries is a precondition for starting that phase** (wired into the [runbook](../RUNBOOK.md) §2–3). The blockers fall into four buckets:

- **Needs a clinical source (must NOT be invented):** cycle phase-boundary detection, ovulation estimation, cycle/period-length bounds, the confidence-score formula, the missing-data card catalog, insights-hub statistical methods + numeric thresholds, hormone reference ranges + per-hormone unit whitelist, the `ref_medication` catalog (drug/dose/ATC), endo staging vocabulary. Gate **P6** and **P7b** — commission during P3–P5 (there's slack) so neither stalls. Two clinical contradictions surfaced: the engine silently assumes a menstruating female of reproductive age, and **a user on a cycle-suppressing therapy the app itself tracks (e.g. Dienogest, in the screen examples) may have no detectable phases**.
- **Needs legal sign-off (lead time — start now):** GDPR consent capture + versioning at signup, **a minimum-age/eligibility gate** (none exists today, yet the app processes minors' special-category sexual/reproductive-health data — a hard blocker), the privacy policy + subprocessor disclosure + SCC-transfer language, Terms of Service, the medical disclaimer on the doctor-report PDF **and** an in-app "not medical advice" disclaimer, and data-retention periods. Gate **P1**, **P8**, **P9b**.
- **Spec-vs-UI contradictions (your call, cheap but blocking):** the pain/intensity scale (`1..5` in the docs vs **0–10 on every screen**) before **P4a**; report Link/Email sharing (screen 30) vs the locked "no server-side sharing" (`§A`) before **P8**; CSV export (screen 35) vs the JSON-zip-only `§F` before **P9b**; the Apple/Google social-login button before **P1**; the per-user-timezone-deferred decision vs screens that need user-local "today" before **P4a**; and the US-formatted English mockups (Sunday-first weeks, "8:00 AM", "60.4") vs an EU/Spanish-primary product (week-start, 24h clock, comma decimal) before **P3a**.
- **Formalize-from-screens (cheap wins — extract now):** the goal enum, the hormone code↔label table (`estradiol`/"Estrogen"), the symptom-region seed, mood labels, the body-metric and activity-type enums, medication category, report sections, and notification categories are all already concrete on the screens; extracting them now eliminates most of the P4a/P4b/P5 guess surface.

**Resolution artifacts** (in `2026-05-31-build-strategy/`): [`decision-sheet.md`](2026-05-31-build-strategy/decision-sheet.md) (the product contradictions/policy choices, each with a recommended default to approve), [`clinical-asks.md`](2026-05-31-build-strategy/clinical-asks.md) and [`legal-asks.md`](2026-05-31-build-strategy/legal-asks.md) (fill-in templates to hand a clinician / lawyer), and `definitions.md` (the extracted screen enums, ready to seed). Each phase's plan tasks treat its open gap-register blockers as preconditions.

## 12. Next step

Invoke the superpowers **`writing-plans`** skill to author `docs/superpowers/plans/lumen-build.md` — the living plan that turns each phase above into bite-sized TDD tasks with exact paths, code, verification commands, and an embedded kickoff prompt (each prompt naming `subagent-driven-development` as the executor, per the Model C execution model in §5), using the orchestration format in the [orchestration companion](2026-05-31-build-strategy/orchestration.md). Then execution proceeds one fresh session per phase, starting at **P0a**, driven and reviewed per the **[build runbook](../RUNBOOK.md)**.
