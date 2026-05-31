<!-- Companion reference to ../2026-05-31-build-strategy-design.md
     Produced by the build-strategy design workflow (2026-05-31). Faithful to docs/ARCHITECTURE.md.
     Note: this analysis predates final phase-number synthesis; phase IDs here are illustrative.
     The canonical phase numbering is in the main spec. -->

# Lumen — Testing & Verification Strategy

This document defines the **phase-aware** testing and verification strategy for the Lumen backend (.NET 10) and Flutter client. It is faithful to `docs/ARCHITECTURE.md` and the locked build decisions: walking-skeleton sequencing, incremental infra bring-up, plan-driven fresh sessions, online-only client cache, Keycloak OIDC, Vault Transit envelope encryption, crypto-shred erasure.

It is structured so a fresh Claude session executing one phase knows **exactly** what "tests pass" means before its checkpoint can be approved.

---

## 0. Principles & the test pyramid

### Guiding principles

1. **A phase is not "done" until its verification gate is green.** The gate is mechanical (a command exits 0), not a judgment call. The session kickoff prompt for each phase ends with "run `<gate command>`; paste the output; do not claim completion otherwise."
2. **Infra is incremental, so the test surface is incremental.** A phase's integration tests may only depend on infra services that phase has brought up. Phase 0 has Postgres + Keycloak + Vault; MinIO/ClamAV tests cannot exist until the lab phase. Testcontainers fixtures are added per-phase, never all at once.
3. **Safety-critical code is tested adversarially, with negative tests first.** The three safety-critical phases — crypto/erasure, lab-parse validation, inference engine — get executable proofs of the *failure* property (ciphertext unreadable, out-of-range value rejected), not just happy-path coverage.
4. **The OpenAPI spec is the contract.** Both the generated Dart client and the contract tests derive from the same committed `openapi.json`. The spec is a build artifact checked into the repo and diffed in CI.
5. **Tests are deterministic.** No live LLM calls in CI (record-replay). No wall-clock dependence (inject `TimeProvider`/`IClock`). No network egress in unit tests. Testcontainers handles all real infra locally and in CI.
6. **Evidence before assertions.** Every checkpoint review requires pasted command output (test counts, coverage delta, the actual ciphertext-vs-plaintext assertion result), not a summary.

### The pyramid (target proportions, not hard quotas)

```
                 /\
                /  \   E2E / live-API  (few; smoke only)
               /----\         Flutter integration_test against seeded backend
              /      \  Contract tests (OpenAPI <-> Dart client; schema drift)
             /--------\
            /          \  Integration tests (Testcontainers: real PG/KC/Vault/MinIO/ClamAV)
           /------------\        — the WIDE middle band; this is a CRUD + infra product
          /              \  Unit tests (domain rules, validators, crypto helpers, mappers)
         /----------------\        — the foundation; pure C#, no I/O
```

**Where things live:**

| Layer | Project / location | Depends on | Speed |
|---|---|---|---|
| Unit | `backend/tests/Lumen.Domain.Tests`, `Lumen.Application.Tests` | nothing (pure) | ms |
| Integration | `backend/tests/Lumen.Integration.Tests` | Testcontainers | seconds |
| Contract | `backend/tests/Lumen.Contract.Tests` + Dart `test/contract/` | committed `openapi.json` | seconds |
| Security/GDPR | `backend/tests/Lumen.Security.Tests` (integration-tier, real Vault/PG) | Testcontainers | seconds |
| Flutter unit/widget | `app/test/` | nothing / fakes | ms |
| Flutter golden | `app/test/golden/` | `flutter_test` | ms |
| Flutter integration | `app/integration_test/` | live API or `dart run` server | seconds |

**Project layout (backend test tree):**

```
backend/
  src/Lumen.Api | Lumen.Application | Lumen.Domain | Lumen.Infrastructure
  tests/
    Lumen.Domain.Tests/          # pure unit, xUnit
    Lumen.Application.Tests/     # use-case unit tests, fakes for ports
    Lumen.Integration.Tests/     # WebApplicationFactory + Testcontainers
    Lumen.Security.Tests/        # GDPR/crypto executable proofs
    Lumen.Contract.Tests/        # OpenAPI snapshot + schema validation
    Lumen.TestKit/               # shared: fixtures, container collections, builders, auth helper
```

`Lumen.TestKit` is a shared library (not a test project) holding Testcontainers collection fixtures, an object-mother/builder set, a Keycloak token minter, and a `IClock` fake. Every phase extends `TestKit` rather than copy-pasting fixtures.

---

## 1. Backend testing

### 1.1 Unit tests

**Framework:** xUnit + `Shouldly` (assertions) + `NSubstitute` (test doubles) + `Bogus` (data) + `Verify` (snapshot assertions for serialization/report fixtures). Pin major versions only per repo convention.

**What is a unit (no I/O, no container):**

- **Domain rules** — the deterministic inference engine: phase classification from `cycle_events`, confidence scoring, missing-data card generation (`ref_insight_rule`-driven). These are pure functions over in-memory fixtures. This is where the inference engine earns most of its coverage.
- **Validators** — lab-parse validation: `hormone_code` whitelist, per-hormone unit whitelist, physiological-range check with the 1.5× widening factor, `measured_on <= today` (clock injected). Each rule has a positive and at least two negative cases (just inside / just outside the widened band).
- **Mappers / DTO projections** — entity ↔ DTO, draft → result promotion shape.
- **Crypto helpers (algorithm-level)** — AES-256-GCM encrypt/decrypt round-trip, IV uniqueness, tamper detection (flip a ciphertext byte → auth tag failure). These test the *algorithm wrapper*; the Vault round-trip is an integration test (§1.2).
- **PII-scrubbing Serilog enricher** — feed log events with emails / `/users/{guid}`; assert the rendered output is redacted; assert that `labs`/`symptoms`/`me` request bodies never appear.
- **Quota arithmetic** — daily LLM quota counting logic (the DB read is faked).

**Determinism rule:** every place that reads "now" uses an injected `TimeProvider` (`FakeTimeProvider` from `Microsoft.Extensions.TimeProvider.Testing`). No `DateTime.UtcNow` in domain/application code — enforced by an architecture test (below).

**Architecture tests** (`NetArchTest` or `ArchUnitNET`, in `Lumen.Domain.Tests`): `Domain` has no dependency on `Infrastructure`/EF/Npgsql; `Application` depends only on `Domain` + port interfaces; controllers never reference `DbContext` directly; no `DateTime.Now`/`UtcNow` outside an `IClock` adapter. These guard the module boundaries described in §C of the architecture doc and run as ordinary unit tests.

### 1.2 Integration tests (Testcontainers)

**Framework:** `Testcontainers` (.NET) + `WebApplicationFactory<Program>` (booting the real DI graph, real EF Core, real middleware) + Respawn (fast per-test DB reset) + xUnit collection fixtures so containers boot once per assembly.

**Container fixtures (added incrementally, per phase):**

| Fixture | Image | Introduced in phase | Used for |
|---|---|---|---|
| `PostgresContainer` | `postgres:16` (with `pgcrypto`, `uuid-ossp`) | Phase 0 | every persistence test; EF migrations applied on boot |
| `KeycloakContainer` | `quay.io/keycloak/keycloak` + `realm-lumen.json` import | Phase 0 | real JWT issuance & validation, admin-API user creation |
| `VaultContainer` | `hashicorp/vault` dev mode, Transit enabled, `lumen-test-kek` created in init | Phase 0 | DEK wrap/unwrap, crypto-shred |
| `MinioContainer` | `quay.io/minio/minio` + buckets seeded | Lab phase | encrypted PDF store, export zips, report storage |
| `ClamavContainer` | `clamav/clamav` | Lab phase | INSTREAM scan; EICAR test string for the positive-detection path |

**Key design choices:**

- **Real Keycloak, not a mocked JWT.** Phase 0's whole point is to exercise the architectural spine. The `KeycloakContainer` imports `deploy/keycloak/realm-lumen.json`, and `TestKit` mints real tokens via the password or client-credentials grant. `WebApplicationFactory` is configured to point its JWT bearer authority at the container. This catches issuer/audience/role mapping bugs that a hand-rolled fake token hides. (A fast lane also offers a self-signed test JWT signer for the bulk of CRUD tests that don't care about Keycloak specifically; the *auth* tests use the real container.)
- **Real Vault, not a mock.** Build order milestone 3 explicitly calls for "round-tripping through a real Vault in Testcontainers." Honor it. The crypto context, DEK provisioning, and crypto-shred are all tested against a live Transit engine.
- **EF migrations are the schema under test.** The fixture runs `dbContext.Database.Migrate()` (or the migration bundle) on a fresh container — this verifies migrations apply cleanly and in order, every run. A separate test asserts there are **no pending model changes** (`dbContext.Database.HasPendingModelChanges()` is false) so a developer can never forget to add a migration.
- **Respawn between tests** resets data without re-booting containers (checkpoint reset of all tables except `__EFMigrationsHistory` and seeded `ref_*` tables).
- **One container set per test assembly**, shared via `[CollectionDefinition]`. Parallelism is per-collection; data isolation comes from Respawn + per-test `user_id`.

**What integration tests cover:**

- Every REST endpoint through the real pipeline: routing → auth → controller → application → EF → Postgres, with the response asserted against the DTO contract.
- Envelope encryption applied on write and decryption on read (the round trip, end to end, through Vault).
- Hangfire job execution: enqueue a job, run it inline (Hangfire's in-memory/inline mode or a real Postgres-storage instance), assert the persisted effect. `ParseLabJob`, `RecomputeInsightSnapshotJob`, `RefreshMatviewsJob`, `CryptoShredJob`, `BuildDataExportJob`.
- Materialized-view refresh: seed rows, trigger refresh job, assert `mv_*` content.
- Rate limiting: hammer an endpoint past the limit, assert 429 (see §3).
- Multipart upload path through ClamAV + MinIO (lab phase).

### 1.3 What "backend tests pass" means

A backend gate is green when, in CI on the phase branch:

1. `dotnet test` exits 0 with **zero skipped tests** that aren't explicitly `[Fact(Skip="reason+ticket")]`.
2. Coverage (Coverlet) meets the per-phase floor (§5 table). Coverage is a *floor that ratchets up*, never down — a phase may not lower the global threshold.
3. No new `[Skip]` without a linked open question/ticket.
4. The architecture tests pass (boundaries intact).
5. The OpenAPI snapshot test passes (spec didn't drift unintentionally; see §2).

---

## 2. Contract testing (OpenAPI ↔ generated Dart client)

The risk: backend changes a field, the Dart client silently keeps the old shape, and a real device 500s in production. We close this with a **single source of truth + drift detection on both sides**.

### 2.1 The contract artifact

- Swashbuckle generates `openapi.json`. A build target **emits it to `backend/contract/openapi.json`** at build time (via `Swashbuckle.AspNetCore.Cli` `dotnet swagger tofile`, run against the built API assembly — no running server needed).
- **This file is committed.** A CI step regenerates it and `git diff --exit-code`s. If the spec changed without the committed file being updated, CI fails with a clear message: "OpenAPI spec changed; regenerate and review `backend/contract/openapi.json`." This makes every contract change a reviewable, intentional diff.

### 2.2 Backend side — spec is correct & stable

In `Lumen.Contract.Tests`:

- **Snapshot test** (`Verify`): the generated spec is snapshotted; an unintended change fails the test with a readable diff. Intentional changes are approved by accepting the new snapshot in the same PR.
- **Spec validity test:** run the spec through an OpenAPI validator (`Microsoft.OpenApi` reader) to assert it parses and has no broken `$ref`s.
- **Round-trip example test:** for each endpoint with a documented example, deserialize the example into the real DTO type and assert it binds — catches spec/DTO divergence.
- **Breaking-change check (CI, informational→blocking):** `oasdiff` compares the PR's spec against `main`'s. Breaking changes (removed field, narrowed type, new required request field) fail the gate unless the PR is labeled `contract-breaking` (forces a human decision and a coordinated client bump).

### 2.3 Client side — generated Dart client matches the spec

- The Dart client is generated with `openapi-generator` (`dart-dio` or `dart` generator) from the **committed** `backend/contract/openapi.json` into `app/lib/api_client/` (generated code, checked in, regenerated by a `make gen-client` / `dart run build_runner` step).
- **Generation-drift test (CI):** regenerate the client from the committed spec into a temp dir and `diff` against the committed generated client. If they differ, CI fails: "Dart client is stale; regenerate from openapi.json." This guarantees the checked-in client always corresponds to the checked-in spec.
- **Contract round-trip test (Dart, `app/test/contract/`):** for each model, take the example payload from the spec, deserialize with the generated model's `fromJson`, re-serialize, and assert structural equality against the spec example. Catches generator quirks (nullable/enum/date handling).

### 2.4 The live cross-check (the real anti-drift gate)

The above proves *spec ↔ client*. To prove *server ↔ spec* at runtime, a small **provider verification** runs in the integration suite: a test hits each endpoint on the live `WebApplicationFactory` and validates the **response body against the endpoint's OpenAPI response schema** (JSON-schema validation of actual responses). If the server returns a shape the spec doesn't describe, this fails. Combined with §2.1's commit-diff, server, spec, and client cannot silently diverge:

```
server response  --validated-->  openapi.json  --generates-->  Dart client
   (§2.4)                            (§2.1 commit-diff)            (§2.3 drift test)
```

**Contract gate green** = committed spec matches generated spec (diff clean) + snapshot test passes + no unapproved breaking change + Dart client regen is clean + response-schema validation passes.

---

## 3. Security & GDPR verification (executable proofs)

These are the spine of "production-grade, GDPR posture." Each is an executable test, mostly integration-tier (real Vault + Postgres), living in `Lumen.Security.Tests`. They are written **negative-first**: prove the bad thing is impossible, not just that the good path works.

### 3.1 Prove envelope encryption at rest

**Claim:** user-owned `*_enc` columns and lab PDFs in MinIO are never stored as plaintext.

- **`EncryptedColumns_AreNotPlaintext`**: write a symptom with `notes_enc = "ovary pain left side"`; query the raw `bytea` directly via a second Npgsql connection (bypassing the EF value converter); assert the bytes do **not** contain the UTF-8 plaintext and **do** decrypt to it via the user's DEK. Repeated for every `*_enc` column listed in §D (parameterized over the column inventory so a new enc column without a test fails a coverage assertion).
- **`WrappedDek_IsNeverPlaintextKey`**: assert `user_keys.wrapped_dek` is not equal to the raw DEK and only decrypts via Vault Transit `decrypt/lumen-test-kek`.
- **`DekIsRequestScopedAndNotLeaked`**: assert `IUserCryptoContext` is registered scoped, that the plaintext DEK is cleared/zeroed after the request scope disposes, and that two concurrent requests for different users never see each other's DEK (parallel test).
- **`LabPdf_InMinio_IsCiphertext`** (lab phase): upload a PDF, fetch the raw object from MinIO, assert the bytes are not a valid PDF (no `%PDF` magic) and decrypt to the original with the DEK + stored IV.

### 3.2 Prove crypto-shred erasure makes ciphertext unreadable

**Claim:** `DELETE /me` → `CryptoShredJob` makes all the user's ciphertext permanently unreadable, even though rows remain.

- **`CryptoShred_MakesCiphertextUnreadable`** (the headline test):
  1. Seed a user with the full DEK, write encrypted rows across several tables, upload a lab PDF to MinIO.
  2. Read back through the normal path → assert plaintext recovers (control).
  3. Call `DELETE /me`; run `CryptoShredJob` to completion.
  4. Assert `user_keys` row is gone; Keycloak user is disabled; push tokens emptied; MinIO `{user_id}/` objects deleted; `users` row tombstoned but present (FK integrity); `admin_audit_log` has the erasure entry.
  5. **The proof:** attempt to decrypt the remaining ciphertext bytes — assert it is now impossible (no DEK, and Vault cannot help because the wrapped DEK is gone). Assert the decryption attempt throws/returns failure, not plaintext.
- **`CryptoShred_BackupCiphertext_AlsoUnreadable`**: simulate the backup scenario — keep a copy of the encrypted bytes taken *before* shred (as a backup would have), and prove they no longer decrypt after shred. This is the GDPR-defensible claim in §F about backups.
- **`CryptoShred_IsIdempotent`**: running the job twice does not error and does not resurrect anything.

### 3.3 Prove rate limits + LLM quota

- **`GlobalRateLimit_429sAfter60PerMinute`**: fire 61 requests in a window for one user; assert the 61st is 429 with the documented body; assert a different user is unaffected (per-user partitioning).
- **`LabUpload_429sAfter10PerDay`** and **`DoctorReport_429sAfter5PerDay`**: assert the ASP.NET limiter caps these endpoints (clock injected so "per day" is testable in seconds).
- **`LlmQuota_BlocksParse_FallsBackToManual`**: set `ref_insight_rule` quota to N; upload N+1 labs; assert the (N+1)th lab skips the LLM, is marked `status='needs_manual'`, increments no LLM cost, and triggers the fallback push. This proves the cost-control guardrail in §E step 4.
- **`LlmQuota_ResetsNextDay`**: advance the injected clock past midnight; assert quota refreshes.

### 3.4 Prove physiological-range validation on lab parse

This is the safety-critical guardrail (§E step 9). Tested at two tiers:

- **Unit (`Lumen.Application.Tests`)** — the validator in isolation, parameterized:
  - In-range value → accepted.
  - Value just **inside** the 1.5×-widened band → accepted but flagged for screen 20.
  - Value just **outside** the widened band → rejected.
  - Unknown `hormone_code` → rejected.
  - Unit not in the per-hormone whitelist → rejected.
  - `measured_on` in the future → rejected.
  - Garbage / non-JSON LLM output → whole parse rejected, lab → `needs_manual`, no draft persisted.
- **Integration (`Lumen.Security.Tests`, lab phase)** — feed `ParseLabJob` a **recorded** LLM response (record-replay; no live call) containing one valid and one out-of-range hormone; assert valid → draft persisted, out-of-range → lab `needs_manual`, and that **no out-of-range value ever reaches `lab_results`** even if the user later confirms (confirm endpoint re-validates server-side; never trust the client). The "confirm re-validates" test is itself a safety assertion.

**Record-replay for the LLM:** the LLM provider is behind an `ILlmClient` port. CI uses a `ReplayLlmClient` that returns fixtures keyed by input hash from `tests/fixtures/llm/`. Fixtures are captured once from the real provider (Anthropic/OpenAI, decision deferred per §I) and committed, scrubbed of any PII. No CI run ever calls a real LLM. A separate, manually-triggered "golden capture" workflow (not in the PR gate) refreshes fixtures against the live provider when the prompt changes.

### 3.5 Other security checks

- **`ProtectedEndpoint_Requires_Bearer`**: every non-`/auth`, non-`/health` route returns 401 without a token (parameterized over the route table from the OpenAPI spec, so a new unprotected endpoint fails).
- **`AdminRoutes_Require_lumen-admin_role`**: a valid token without the realm role gets 403 on `/admin/*`.
- **`Upload_RejectsNonPdf_AndOversize_AndBadMagicBytes`**: 422/413 paths; a `.pdf`-named file with wrong magic bytes is rejected.
- **`ClamAV_RejectsEicar`**: upload the EICAR test signature; assert 422, `labs_rejected_clamav_total` incremented, nothing written to MinIO.
- **`PiiScrubbing_InLogs`** (also unit, §1.1): integration-level assertion that a real request to a `me`/`labs` endpoint produces no plaintext PII in the captured Serilog sink.
- **(Periodic, not per-PR)** `dotnet list package --vulnerable` + Trivy scan of the `api` image in CI; fails on High/Critical CVEs.

---

## 4. Flutter testing

Flutter/Dart is installed in a later phase per the environment note; Flutter tests come online only from the phase that introduces the client. Until then, contract artifacts (§2) are exercised on the backend side only.

### 4.1 Unit & widget tests

- **Unit (`app/test/`):** repository/service layer over the generated API client (client mocked with `mocktail`/`http_mock_adapter`), JSON model round-trips (these overlap the contract tests in §2.3 and reuse the same spec examples), the **online-only cache** behavior: in-memory + Hive disk cache reads, cache invalidation, and — critically — the locked decision that **writes do NOT queue offline**: assert that a write while offline surfaces an error to the UI and does not enqueue.
- **Widget tests (`flutter_test`):** each screen's stateful behavior with a fake repository — loading, empty, error, and populated states for the data-bearing screens (dashboard, cycle calendar, hormone chart, lab confirm/screen 20, insights hub). Assert that error and empty states render (the doc's milestone 11 calls these out explicitly). Form screens (symptom form, body entry, add medication) get validation tests.

### 4.2 Golden tests for design-system theming

This is where the design system (CLAUDE.md tokens) gets verified visually and regression-protected.

- **Library:** `golden_toolkit` (or `alchemist` for CI-stable rendering) with `flutter_test` golden support.
- **Theme coverage:** every component and every screen is rendered in **both light ("soft warm") and dark ("witchy")** themes and snapshotted. A parameterized golden runner produces `<screen>_light.png` and `<screen>_dark.png`. This directly enforces the "both themes must be supported" rule.
- **Token assertions (non-pixel):** a `ThemeData`-level test asserts the actual token values match CLAUDE.md exactly — e.g. light accent `#C25A36`, dark accent `#E8A87C`, the four cycle-phase colors per theme, and the seven hard-coded hormone colors (which are **not** theme-switched — a test asserts estrogen stays `#C25A36` in both themes). This catches token drift without depending on fragile pixel diffs.
- **Typography golden:** assert only weights 400 and 500 are used and no ALL CAPS strings appear except where `TextTransform`/uppercase styling is intentional (section labels). A widget-tree lint test scans rendered text styles.
- **CI stability:** goldens are generated on a pinned platform/font setup (Alchemist's CI mode disables platform font shaping) so they don't flake across machines. Golden updates require `flutter test --update-goldens` and show up as reviewable PNG diffs in the PR.

### 4.3 Integration tests against a real API

- **`integration_test/`** drives the app against a **live backend** brought up by Testcontainers-equivalent / `docker compose` with a **seeded demo account** (the same seed used in milestone 11's end-to-end verification).
- Flows covered grow with phases: Phase 1 slice = **OIDC login via Keycloak → onboarding start → GET /me renders**. Later: full onboarding 1–7, log a symptom and see it on the calendar, upload a lab → confirm drafts → see it on the chart, generate a doctor report → download.
- Auth uses the **real Keycloak realm `lumen`** (OIDC code flow), proving the mobile auth decision end-to-end, not a stubbed token.
- These are smoke-level (few, high-value), per the pyramid. They run in CI against the compose stack on a schedule and on the client phases' PRs; they are not run on every backend-only PR (too slow), but the per-phase gate for client phases requires them green.

### 4.4 What "Flutter tests pass" means

`flutter analyze` clean (no warnings) + `flutter test` (unit + widget + golden) exits 0 with no golden diffs + `flutter test integration_test/` green against the seeded stack for client phases + the contract drift test (§2.3) clean.

---

## 5. CI pipeline & per-phase verification gates

### 5.1 CI pipeline outline (GitHub Actions)

Three workflows, matching §G ("a second workflow runs backend unit + integration tests"):

**`ci-backend.yml`** (on PR + push):
```
jobs:
  build-and-unit:        dotnet restore/build (warnings-as-errors); dotnet test unit projects; coverage gate
  contract:              regenerate openapi.json; git diff --exit-code; snapshot test; oasdiff vs main
  integration:           docker-in-docker; dotnet test Lumen.Integration.Tests + Lumen.Security.Tests
                         (Testcontainers pulls only the images this phase needs)
  security-scan:         dotnet list package --vulnerable; Trivy on built api image  (non-blocking until prod phase)
```

**`ci-client.yml`** (on PR touching `app/`, from the Flutter phase onward):
```
jobs:
  analyze-and-test:      flutter analyze; flutter test (unit/widget/golden)
  client-drift:          regenerate Dart client from committed openapi.json; diff --exit-code
  app-integration:       boot compose stack + seed; flutter test integration_test/   (client phases only)
```

**`cd.yml`** (manual / tag): build `api` image → push GHCR → SSH → `docker compose pull && up -d`. Gated behind both CI workflows green. Runs the monthly restore-drill smoke as a scheduled job.

Caching: NuGet, Testcontainers image layers (pre-pull in a setup step), and the Flutter pub/golden caches. Testcontainers image pulls are the main CI time cost; only pull what the touched phase needs.

### 5.2 Minimum verification gate per phase

Each phase's checkpoint cannot be approved until its gate command set exits 0 and the evidence is pasted. Deeper review (a second, adversarial pass on the negative tests) is required for the three **safety-critical** phases marked ⚠.

| Phase | Scope | Infra added | Minimum gate ("tests pass" =) | Coverage floor |
|---|---|---|---|---|
| **0 — Skeleton + infra** | Compose: Caddy+PG+Keycloak+Vault. Empty API `/health` 200. | PG, Keycloak, Vault | `docker compose up` healthchecks all green; `GET /health` → 200 through Caddy; Keycloak realm imports; Vault Transit key exists; **one smoke integration test** boots `WebApplicationFactory` against PG+KC+Vault. | n/a (skeleton) |
| **1 — Walking-skeleton vertical slice** | auth → Keycloak user create → Vault DEK provision → encrypted PG write → protected `GET /me` | (same) | Integration: real Keycloak token → `POST /onboarding/start` creates Keycloak user + `user_keys` row + encrypted profile; `GET /me` returns it; `EncryptedColumns_AreNotPlaintext` passes for profile columns; `ProtectedEndpoint_Requires_Bearer` passes; OpenAPI emitted + committed + snapshot green. | 60% spine |
| **2 — Crypto/erasure ⚠** | `IUserCryptoContext`, DEK lifecycle, crypto-shred | (same) | All of §3.1 + §3.2 green (envelope-at-rest + crypto-shred-unreadable + idempotent + backup-unreadable). DEK-request-scope + concurrency test green. **Deeper review.** | 85% crypto module |
| **3 — Onboarding+Cycle+Symptoms** | full REST for modules 1–3, migrations | (same) | All module endpoints pass integration tests; migrations apply on fresh container + no pending model changes; encrypted columns proven; rate-limit global test green; contract gate green. | ratchet ≥70% global |
| **4 — Inference engine ⚠** | phase/confidence/missing-data, snapshot + matview jobs | (same) | Golden-fixture unit tests for phase/confidence/missing-data pass (curated cycle scenarios → expected phase+confidence); `RecomputeInsightSnapshotJob`/`RefreshMatviewsJob` integration tests assert matview content; determinism (same input → same output, clock injected). **Deeper review.** | 90% inference rules |
| **5 — Labs + LLM parse ⚠** | upload→scan→encrypt store→parse→validate→confirm | + MinIO, ClamAV | All of §3.3 (quota) + §3.4 (range validation, record-replay) + ClamAV-EICAR + `LabPdf_InMinio_IsCiphertext` + confirm-re-validates green; no live LLM in CI. **Deeper review.** | 85% lab pipeline |
| **6 — Reports/QuestPDF** | doctor report job, download | (same) | `GenerateDoctorReportJob` integration test produces a PDF in MinIO; download endpoint returns it; report-quota (5/day) 429 test; `Verify` snapshot of report data model. | ratchet |
| **7 — Notifications** | FCM/APNs senders, device reg, nightly dispatch | (same) | Senders behind a port, faked in CI; device-registration endpoint tests; `NightlyNotificationDispatchJob` integration test (clock injected) asserts correct recipients selected. | ratchet |
| **8 — Admin module** | Razor CRUD, audit log, role gating, ref-data migrations | (same) | `AdminRoutes_Require_lumen-admin_role` green; every admin mutation writes `admin_audit_log` (integration test asserts before/after JSON); ref-data seed migrations apply. | ratchet |
| **9 — Flutter client (introduced)** | install Flutter; generate Dart client; screens wired per slice | (test stack) | `flutter analyze` clean; unit+widget+golden (light+dark) green; **client-drift test green**; online-only/no-offline-write test green; integration_test login→onboarding→/me against seeded stack green. | client ≥60%, ratchet |
| **10 — Observability sidecar** | Grafana/Loki/Prometheus, WireGuard | sidecar | Prometheus scrapes `/metrics`; alert rules unit-tested (`promtool test rules`); a synthetic metric trips a test alert; OTLP exporter emits spans (asserted via a test collector). | n/a (infra) |
| **11 — Polish / E2E** | full end-to-end on seeded demo account | full | Full `integration_test/` suite green across all wired screens incl. empty/error states; full backend suite green; contract gate green; security scans (now blocking) clean. | global ≥80% |

Notes on the table:

- **Coverage is a ratchet.** Each phase's CI reads the prior global floor and forbids regression. Safety-critical modules carry their own higher floors that never drop.
- **Infra is added only where the column says so**, honoring the incremental-bring-up decision. MinIO/ClamAV fixtures literally do not exist in the repo until Phase 5, so Testcontainers only pulls them from Phase 5 on.
- **"Deeper review" (⚠)** means the checkpoint reviewer re-runs the negative tests with a deliberately-broken implementation to confirm the test actually fails (mutation-style spot check) — e.g., comment out the range check and confirm `Value_JustOutside_Rejected` goes red. This proves the safety test has teeth, not just green-by-accident.

### 5.3 The universal gate (applies to every phase before its checkpoint)

A checkpoint is approvable only when **all** are true and the **command output is pasted as evidence**:

1. `dotnet build` with warnings-as-errors → 0 warnings.
2. `dotnet test` (all backend test projects relevant to this + prior phases) → 0 failures, 0 unexplained skips.
3. Coverage ≥ the ratcheted floor (and safety-module floors).
4. Contract gate green (spec committed & diff-clean, snapshot ok, no unapproved breaking change, Dart client regen clean).
5. Architecture tests green (module boundaries intact).
6. For client phases: `flutter analyze` clean + `flutter test` + golden (both themes) + integration_test green.
7. For ⚠ phases: the adversarial mutation spot-check confirms the safety test fails when the guard is removed.
8. The phase's `docker compose up` stack reaches healthy on a clean machine (the walking skeleton must actually walk).

If any item is red, the phase is not done. The session must fix it, not narrate around it.

---

## 6. Cross-cutting test infrastructure decisions

- **`Lumen.TestKit`** centralizes: Testcontainers collection fixtures (added per phase), a Keycloak token minter (real-token path + fast self-signed path), `FakeTimeProvider`, Respawn checkpoint config, object-mother builders for every entity, and the `ReplayLlmClient`. New phases extend it; they never re-invent fixtures.
- **Determinism enforced structurally:** `IClock`/`TimeProvider` injected everywhere; an architecture test bans `DateTime.UtcNow` in domain/app code; no test depends on real network or real LLM.
- **Fixtures are committed and scrubbed:** LLM record-replay fixtures, sample lab PDFs (synthetic, no real patient data), and golden PNGs all live in the repo. A README in `tests/fixtures/` states the no-real-PII rule.
- **Flaky-test policy:** a test that flakes is quarantined with a ticket within one session, not retried-until-green. Testcontainers + Respawn + injected clock remove the three usual flake sources up front.
- **The plan carries the gate.** Each phase entry in the living implementation plan ends with its exact gate command block and the "paste output before claiming done" instruction, so a fresh session inherits the verification contract without re-deriving it.

---

### Open items I did not invent answers for (flagged for plan time)
- **LLM provider (Anthropic vs OpenAI)** is deferred in §I; the `ILlmClient`/`ReplayLlmClient` seam makes the test strategy provider-agnostic, so this does not block any test work before Phase 5.
- **Golden-test library choice (`alchemist` vs `golden_toolkit`)** is a Phase 9 decision; both satisfy the light/dark + CI-stability requirement. Recommend `alchemist` for CI font-shaping stability.
- **Dart generator (`dart-dio` vs `dart`)** is a Phase 9 decision; the drift-detection mechanism (§2.3) works for either.

Relevant source files read: `C:\Proyectos\Endo\docs\ARCHITECTURE.md`, `C:\Proyectos\Endo\CLAUDE.md`. No implementation plan file exists yet (`docs/` contains only `ARCHITECTURE.md`); this strategy is written to be embedded into that plan's per-phase entries when it is created.
