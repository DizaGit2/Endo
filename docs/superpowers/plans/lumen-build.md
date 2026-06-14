# Lumen Build — Living Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use **superpowers:subagent-driven-development** (recommended) or superpowers:executing-plans to implement ONE phase per session. Steps use checkbox (`- [ ]`) syntax. Read §0 before touching anything. The human drives & reviews per [`../RUNBOOK.md`](../RUNBOOK.md).

**Goal:** Build a production-grade .NET 10 backend + Flutter client for Lumen (endometriosis tracker), faithful to [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md), via a risk-retiring walking skeleton across 19 phases.

**Architecture:** Caddy → Keycloak JWT → Vault Transit per-user DEK → AES-256-GCM envelope-encrypted Postgres, Hangfire jobs, MinIO/ClamAV labs, deterministic inference engine, Anthropic lab parsing. One fresh session per phase (Model C); each session dispatches subagents per task and stops at `NEEDS_REVIEW`.

**Tech Stack:** .NET 10, ASP.NET Core, EF Core + Npgsql, Keycloak, HashiCorp Vault (Transit), MinIO, ClamAV, Hangfire, Swashbuckle, QuestPDF, Docker Compose, Caddy; Flutter (Riverpod + GoRouter, flutter_appauth, dio + built_value, Hive), openapi_generator (P3a uses the `openapi-generator-cli` JAR `dart-dio` directly — the Dart `openapi_generator` build package is incompatible with this `source_gen`/`built_value_generator` set; see P3a STATUS).

**Companion docs (read as referenced):** spec [`../specs/2026-05-31-build-strategy-design.md`](../specs/2026-05-31-build-strategy-design.md) · gap register [`../specs/2026-05-31-build-strategy/gap-register.md`](../specs/2026-05-31-build-strategy/gap-register.md) · decision sheet [`../specs/2026-05-31-build-strategy/decision-sheet.md`](../specs/2026-05-31-build-strategy/decision-sheet.md) · definitions [`../specs/2026-05-31-build-strategy/definitions.md`](../specs/2026-05-31-build-strategy/definitions.md) · clinical-asks / legal-asks (same folder) · orchestration / testing / environment / flutter companions (same specs folder).

---

## §0 How to use this plan

1. **One phase per session.** Open a fresh session, read §1 ledger → `NEXT PHASE TO RUN`. Confirm its `dependsOn` are `DONE`.
2. **Clear the phase's gaps first.** Each §3 phase lists **Preconditions (resolve before starting)** — open gap-register blockers, decisions (decision-sheet), and definitions it needs. If any is unresolved, do **not** start; resolve it (record in `ARCHITECTURE.md §A` + §4 here) or pick a phase whose gaps are clear. A session must never invent a clinical or legal value.
3. **Paste the phase's Kickoff prompt** (in its §3 entry) as the first message. Execute via `subagent-driven-development`: a subagent per task, strict TDD, one commit per task.
4. **Verify, don't narrate.** Run each task's commands; a phase is done only when its Exit criteria are proven with pasted output (`verification-before-completion`).
5. **Stop at NEEDS_REVIEW.** Fill the phase's `STATUS` block (pasted command output), set the ledger row to `NEEDS_REVIEW`, open the phase PR, stop. The human reviews (deep review for ⚠ phases), then flips the row to `DONE`.
6. **Anti-drift.** Docs change in the same branch as the code that invalidates them; this plan *references* `ARCHITECTURE.md §` rather than pasting; if you rename a type/path a later phase's tasks mention, fix that task text in the same `docs(plan)` commit; stamp the ledger SHA.

### Kickoff prompt template (each phase stores its filled copy)
```text
You are executing ONE phase of the Lumen build. Phase: {ID} — {Name}.
Read first, in order: docs/superpowers/plans/lumen-build.md (§0, §1, §2, §5, and phase {ID} only),
then docs/ARCHITECTURE.md ({the § refs in this phase}), then CLAUDE.md, then this phase's Preconditions.
Working agreement: execute via superpowers:subagent-driven-development; strict TDD; one commit per task;
obey §2 invariants and §0 anti-drift; .NET 10 only; never invent a clinical/legal value (if one is missing
and unresolved, write BLOCKED in STATUS and stop). Branch: phase/{NN}-{slug} off the build branch.
When done: fill the phase STATUS block with PASTED verification output, tick proven exit criteria,
set the §1 ledger row to NEEDS_REVIEW, and STOP for human review.
```

---

## §1 Status ledger  (the ONLY authority for "done")

**NEXT PHASE TO RUN: P3a (NEEDS_REVIEW — awaiting human acceptance), then P3b.**  (P0a, P1, P2 DONE+merged. **P3a built 2026-06-14** on `phase/03a-client-foundation`: Flutter foundation + theming + OpenAPI dio/built_value client + CI drift guard + static screens 1/36/37; **106 client + 3 backend OpenAPI tests green; coverage 97.60%**. STATUS filled; final whole-phase review run. On human acceptance: merge, tag `phase-03a`, advance NEXT to **P3b** (client OIDC + cache + screens 2/31).)
**Plan revision:** r9   **Repo HEAD when ledger last updated:** `phase/03a-client-foundation` (P3a NEEDS_REVIEW; main at `4a888bf`)

| Phase | Name | Status | Branch | PR | Verified by | Notes |
|---|---|---|---|---|---|---|
| P0a | Compose stack + realm + health | DONE | phase/00a-infra | tag `phase-00a` | 2026-05-31 | merged to main |
| P0b | This living plan | DONE | design/build-strategy | 2026-05-31 | — | = this document |
| P1 ⚠ | Auth + envelope-encryption spine | DONE | phase/01-spine | tag `phase-01` | 2026-06-02 | merged to main; 23 tests; security review + /code-review high both clean |
| P2 ⚠ | Crypto-shred + Hangfire | DONE | phase/02-shred | [#1](https://github.com/DizaGit2/Endo/pull/1) | 2026-06-14 | merged to main, tag `phase-02`; 57 tests; multi-agent /review + all fixes applied |
| P3a | Flutter foundation + theming + OpenAPI pipeline | NEEDS_REVIEW | phase/03a-client-foundation | — | 2026-06-14 | T1–T10 done; 106 client + 3 OpenAPI tests; cov 97.60%; awaiting human review |
| P3b | Client OIDC + cache + screens 2/31 | TODO | — | — | — | |
| P4a | Backend Onboarding-rest + Cycle + Symptoms | TODO | — | — | — | needs definitions + D-08..D-14 |
| P4b | Flutter screens 3–14, 32 | TODO | — | — | — | |
| P5 | Body + Activity + Treatment | TODO | — | — | — | needs D-15/D-16 |
| P6 ⚠ | Inference engine + matviews + insights | TODO | — | — | — | needs clinical-asks C-01..C-11 |
| P7a | Labs infra + upload + scan + store | TODO | — | — | — | finalize crypto-shred MinIO delete |
| P7b ⚠ | LLM (Anthropic) parse + validate + confirm | TODO | — | — | — | needs C-06/C-07; ultra review |
| P8 | Reports (QuestPDF) | TODO | — | — | — | needs D-20/D-22, L-04 |
| P9a | Notifications + nightly dispatch | TODO | — | — | — | needs D-19 |
| P9b | GDPR export | TODO | — | — | — | needs D-21, L-05..L-07 |
| P10 | Admin reference-data | TODO | — | — | — | |
| P11 | CI/CD + backups + prod hardening | TODO | — | — | — | §I infra decisions |
| P12a | Observability sidecar | TODO | — | — | — | |
| P12b | Final production-readiness pass | TODO | — | — | — | 38-screen walk |

Status values: TODO · IN_PROGRESS · BLOCKED · NEEDS_REVIEW · DONE.
Safety-critical (deep review): **P1, P2, P6, P7b**.

---

## §2 Architecture invariants  (the immutable spine — do not contradict without a human-approved `ARCHITECTURE.md §A` change)

- Request path: **HTTPS → Caddy → Keycloak JWT validation → controller → application → EF → Postgres**. Only Caddy is public.
- **Per-user envelope encryption:** every `*_enc` column is AES-256-GCM with a per-field IV, using a per-user DEK that is generated server-side, wrapped by the Vault Transit KEK, and stored in `user_keys.wrapped_dek`. The plaintext DEK is unwrapped via `IUserCryptoContext` (request-scoped) or `IJobCryptoContext` (job-scoped) and **never persisted, never logged, never cached beyond that scope**.
- **DEK is server-held, NOT password-derived** (background jobs decrypt while the user is offline). Lab PDFs are encrypted **server-side** (decision D5). The client never holds the DEK.
- **Erasure = crypto-shred:** deleting `user_keys` makes all the user's ciphertext permanently unreadable; object-storage objects under `{user_id}/` are also physically deleted.
- **.NET 10** (pinned via `global.json`). **Online-only client** (reads cache in Hive, writes never queue). Keycloak realm **`lumen`**.
- **Determinism:** `IClock`/`TimeProvider` everywhere (enforced by an architecture test); no live LLM in CI (record-replay); no `DateTime.UtcNow` in domain/app code.
- **Reference data** (`ref_hormone_range`, `ref_medication`, `ref_insight_rule`) is seeded via migration with `valid_from` + provenance, and is the single source of truth; the inference engine reads `ref_insight_rule` params, never hard-coded magic numbers.

---

## §3 Phase catalogue

> Each phase: **Preconditions** (resolve first) · **Kickoff prompt** · **Verify commands** · **Exit criteria** · **Tasks** · **STATUS**. P0a/P1/P2 carry full task breakdowns; P3a–P12b carry their task outline and are detailed to bite-sized TDD at phase entry (anti-drift). Full per-phase scope is in spec §4.

---

### Phase P0a — Compose stack + realm + health liveness

- **Status:** TODO · **Safety-critical:** no · **Depends on:** — · **Branch:** `phase/00a-infra`
- **Goal:** one `docker compose up` brings Caddy + Postgres + Keycloak + Vault healthy, with an empty .NET 10 `api` answering `GET /health` 200 through Caddy over TLS.
- **Architecture refs:** §B (topology), §G (deploy), environment companion.
- **Screens:** none.
- **Preconditions (resolve before starting):** none clinical/legal. Confirm the **Caddyfile uses two local hostnames** (`api.localhost`, `auth.localhost`) or the simpler single-host form per environment companion §3.4. No gap-register blockers gate P0a.

**Kickoff prompt**
```text
You are executing ONE phase of the Lumen build. Phase: P0a — Compose stack + realm + health.
Read first: docs/superpowers/plans/lumen-build.md (§0,§1,§2,§5, phase P0a), docs/ARCHITECTURE.md (§B,§G),
docs/superpowers/specs/2026-05-31-build-strategy/environment.md, CLAUDE.md.
Execute via superpowers:executing-plans (infra is imperative shell, not unit TDD). .NET 10 only.
Branch phase/00a-infra off the build branch. Verify with the commands in this phase; paste output.
Set the ledger to NEEDS_REVIEW and STOP.
```

**Verify commands**
```powershell
docker compose -f deploy/docker-compose.yml up -d
docker compose -f deploy/docker-compose.yml ps                              # all healthy
Invoke-RestMethod -SkipCertificateCheck https://localhost/health            # 200 healthy
Invoke-RestMethod "http://localhost:8080/realms/lumen/.well-known/openid-configuration" | Select issuer
docker compose -f deploy/docker-compose.yml exec -T vault sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault read transit/keys/lumen-dev-kek'
docker compose -f deploy/docker-compose.yml exec -T postgres psql -U postgres -c "\l" # lumen + keycloak DBs
dotnet build   # empty solution builds on .NET 10
```

**Exit criteria**
- [ ] `docker compose up` → Caddy+Postgres+Keycloak+Vault+api all healthy.
- [ ] `GET /health` 200 through Caddy over TLS; `/health/ready` = shallow TCP reachability of Postgres+Vault (no app logic).
- [ ] Realm `lumen` imported (confidential `api` client, public mobile client, `lumen-admin` role, provisioning service account); OIDC discovery reachable.
- [ ] Vault Transit `lumen-dev-kek` exists; both DBs + extensions (`pgcrypto`,`uuid-ossp`,`pg_stat_statements`) present.
- [ ] `global.json` pins `10.0.300`; empty `Lumen.slnx` (Api/Application/Domain/Infrastructure) builds.

**Tasks**
- [ ] **T1 — Repo skeleton & SDK pin.** Create `global.json` (`{ "sdk": { "version": "10.0.300", "rollForward": "latestFeature" } }`); `dotnet new sln -n Lumen` under `backend/`; create the 4 projects (`Lumen.Api` web, `Lumen.Application`/`Lumen.Domain`/`Lumen.Infrastructure` classlib) + add to sln. Verify `dotnet build`. Commit `chore(infra): solution skeleton + .NET 10 pin`.
- [ ] **T2 — Postgres init.** `deploy/postgres/init.sql` creates `lumen` + `keycloak` DBs and the 3 extensions on `lumen`. Commit `chore(infra): postgres init`.
- [ ] **T3 — Keycloak realm.** `deploy/keycloak/realm-lumen.json` (realm `lumen`; confidential `api` client; public `mobile` client with PKCE + redirect `com.lumen.app:/oauth2redirect`; `lumen-admin` realm role; a service account on the `api` client with `realm-management` roles for user provisioning; 15-min access / 30-day refresh; password policy from decision D-01 default). Commit `chore(infra): keycloak realm lumen`.
- [ ] **T4 — Vault init.** `deploy/vault/init.sh` enables Transit + creates `lumen-dev-kek` (run once via compose). Commit `chore(infra): vault transit init`.
- [ ] **T5 — Caddyfile (local).** `deploy/Caddyfile.local` (`tls internal`, HTTP→HTTPS, HSTS, route to `api:8080` and `/auth`→`keycloak:8080`). Commit `chore(infra): caddy local`.
- [ ] **T6 — Minimal API.** `Lumen.Api/Program.cs`: Serilog console; `GET /health` (200) + `GET /health/ready` (TCP-reach Postgres+Vault); Swashbuckle wired (empty). Commit `feat(api): health endpoints`.
- [ ] **T7 — Compose.** `deploy/docker-compose.yml` (caddy, postgres, keycloak, vault, api) with healthchecks + localhost-only binds for vault/keycloak-admin. Bring up; run all Verify commands; paste output. Commit `chore(infra): docker compose stack`.

**STATUS**
- **State:** NEEDS_REVIEW  ·  **Branch:** `phase/00a-infra` (commits `5cddf2f` + port-remap)  ·  **Tasks:** T1–T7 done (7/7)
- **Exit criteria proven (pasted):**
  ```
  $ docker compose -f deploy/docker-compose.yml ps
  lumen-api-1        Up (healthy)      lumen-postgres-1   Up (healthy)
  lumen-caddy-1      Up                lumen-keycloak-1   Up               lumen-vault-1   Up
  $ curl -ksS https://localhost/health            -> {"status":"healthy"}
  $ curl -ksS https://localhost/health/ready      -> {"status":"ready","dependencies":{"postgres":true,"vault":true}}
  $ vault read transit/keys/lumen-dev-kek         -> key exists (allow_plaintext_backup ... )
  $ psql -tc "SELECT datname ... ('lumen','keycloak')"   -> keycloak, lumen
  $ psql -d lumen -tc "SELECT extname ..."        -> pgcrypto, uuid-ossp, pg_stat_statements
  $ curl .../realms/lumen/.well-known/openid-configuration  -> "issuer":"http://localhost:8080/realms/lumen"
  $ dotnet build backend/Lumen.slnx               -> Build succeeded, 0 Warning(s), 0 Error(s)
  ```
- **Deviations from plan (also fixed in this plan):**
  - .NET 10 emits `Lumen.slnx` (XML solution), not `Lumen.sln`.
  - Added `backend/NuGet.config` (pin nuget.org) — a machine-level private feed 401'd restores; also makes CI reproducible.
  - Host Postgres port remapped 5432→55432 (host 5432 in use); in-container comms unchanged.
  - caddy/keycloak/vault have no in-container healthcheck (images lack shell tools) — verified externally; api+postgres report compose-healthy.
  - Keycloak realm service-account-for-provisioning roles deferred to P1 (audit V3-P0-major); realm imports with api(confidential)+mobile(PKCE)+`lumen-admin`.
- **For reviewer:** stack is up now — re-run the Verify commands; `docker compose -f deploy/docker-compose.yml down` to stop. On acceptance, flip P0a→DONE and advance NEXT to P1.

---

### Phase P0b — This living plan  *(satisfied by this document)*

- **Status:** DONE-ON-COMMIT. This phase = authoring `docs/superpowers/plans/lumen-build.md` (this file). Mark `DONE` in the ledger when this plan is committed. No build session needed.

---

### Phase P1 ⚠ — Auth + envelope-encryption spine

- **Status:** TODO · **Safety-critical: YES (deep review)** · **Depends on:** P0a · **Branch:** `phase/01-spine`
- **Goal:** prove the whole spine in one slice — `POST /onboarding/start` (Keycloak admin user-create → Vault DEK provision → encrypted `user_profile_enc` write) + JWT-guarded `GET /me`/`PATCH /me`. Build the load-bearing `IUserCryptoContext` correctly and test it exhaustively before any breadth.
- **Architecture refs:** §C.1, §F (encryption/key custody/logging), §E (not yet — labs later).
- **Screens:** none wired here (client spine is P3b).
- **Preconditions:** **D-01** (password policy), **D-02** (consent capture — the `POST /onboarding/start` body must persist a consent record; legal L-01/L-02 text can be a placeholder version string now but the *field* must exist), **D-03** (default locale for `users.locale`), **D-05/D-12** (store `users.timezone` + `locale` from the request), **L-01** (age gate — if the consent/age fields aren't decided, persist them as nullable now and tighten at L-time, but record the decision). If consent/age design is unresolved, implement the columns and a versioned consent row; do not skip them.

**Kickoff prompt**
```text
You are executing ONE phase of the Lumen build. Phase: P1 — Auth + envelope-encryption spine (SAFETY-CRITICAL).
Read first: docs/superpowers/plans/lumen-build.md (§0,§1,§2,§5, phase P1), docs/ARCHITECTURE.md (§C.1,§F),
this phase's Preconditions + decision-sheet D-01/D-02/D-03/D-05/D-12, CLAUDE.md.
Execute via superpowers:subagent-driven-development; strict TDD; one commit per task; .NET 10 only.
The DEK rules in §2 are inviolable: server-held, request-scoped, never logged/persisted/over-cached.
Branch phase/01-spine. Stop at NEEDS_REVIEW with pasted proof; this phase gets a deep code-review.
```

**Verify commands**
```powershell
cd backend; dotnet test --nologo            # all green incl. Testcontainers spine test
# the spine integration test proves: token -> POST /onboarding/start -> user_keys + encrypted profile -> GET /me decrypts
```

**Exit criteria**
- [ ] One automated Testcontainers test (real Postgres+Vault+Keycloak) proves the full spine end-to-end.
- [ ] `EncryptedColumns_AreNotPlaintext` for profile columns; tenant isolation (user B can't read A); tampered-GCM-tag fails; DEK request-scoped + zeroed + concurrency-safe.
- [ ] `GET /me` 401 without bearer; wrong realm/audience → 401.
- [ ] **Real global 429 rate-limit test** + an abuse test for `POST /onboarding/start` (audit fix).
- [ ] Crypto-shred precondition: deleting `user_keys` makes the profile undecryptable (negative test).
- [ ] OpenAPI emitted to `backend/contract/openapi.json` (committed) + snapshot test; NetArchTest boundaries green; coverage ≥60% on the spine.
- [ ] **Deep review passed** (code-review high) over crypto helper, key custody, DEK lifetime, JWT validation, PII logging vs §F.

**Tasks** (bite-sized TDD; subagent writes the code red→green→commit)
- [ ] **T1 — EF + first migration.** `users`, `user_keys`, `user_profile_enc` entities + `Lumen.Infrastructure` DbContext + initial migration. Test: migration applies on a fresh Testcontainers Postgres; `HasPendingModelChanges()` false.
- [ ] **T2 — VaultTransitClient.** Wrap/unwrap against `lumen-dev-kek`. Test (real Vault container): wrap a 256-bit DEK → unwrap → equal; wrapped ≠ raw.
- [ ] **T3 — Field crypto helper.** AES-256-GCM per-field IV encrypt/decrypt for `bytea`. Tests: round-trip; distinct IVs; tampered tag throws.
- [ ] **T4 — IUserCryptoContext (request-scoped).** Unwrap DEK once per request, expose field-encrypt; dispose/zero at scope end. Tests: registered scoped; two concurrent different-user requests never share a DEK; DEK not retained after scope.
- [ ] **T5 — DEK provisioning service.** Generate DEK, wrap, persist `user_keys` (idempotent per user). Test: second call doesn't duplicate.
- [ ] **T6 — Keycloak JWT middleware.** Bearer validation (issuer/audience/realm-role map, `sub`→`user_id`). Tests: valid token 200; missing/wrong-realm/wrong-audience → 401.
- [ ] **T7 — Keycloak Admin API client.** Create user via admin REST using the service account. Test (Keycloak container): creates a user; `user.id` == subject.
- [ ] **T8 — POST /onboarding/start.** Orchestrate: admin user-create → DEK provision → encrypted `user_profile_enc` write → persist consent record + `locale`/`timezone`. Test: rows created, profile is ciphertext in raw SQL.
- [ ] **T9 — GET/PATCH /me.** Decrypt + return; update. Tests: 200 decrypted; tenant isolation; 401 unauth.
- [ ] **T10 — Cross-cutting.** Serilog PII-scrubbing enricher (redact emails, `/users/{guid}`, never log me/onboarding bodies); ASP.NET global rate limiter (60/min/user). Tests: enricher redacts; 61st request → 429; onboarding-start abuse test.
- [ ] **T11 — OpenAPI + arch tests.** Emit + commit `backend/contract/openapi.json`; Verify snapshot; NetArchTest (Domain has no Infra/EF; no `DateTime.UtcNow` outside `IClock`). 
- [ ] **T12 — Spine integration test + CI.** The end-to-end Testcontainers test; `ci-backend.yml` (unit + integration). Paste the green run into STATUS.

**STATUS**
- **State:** NEEDS_REVIEW  ·  **Branch:** `phase/01-spine`  ·  build warnings-clean  ·  **23/23 tests green** (17 unit + 6 integration)  ·  `/code-review high` clean (all 6 findings applied)
- **Tasks done:** **T1** EF entities + migration · **T2** Vault wrap/unwrap · **T3** AES-256-GCM cipher (9 unit tests) · **T4** request-scoped `UserCryptoContext` · **T5** DEK provisioning · **T6** Keycloak JWT auth + `CurrentUserAccessor` · **T7** Keycloak admin user-create (scoped service account) · **T8** `POST /onboarding/start` · **T9** `GET/PATCH /me`. **Walking-skeleton spine proven end-to-end.** Crypto-shred precondition proven.
- **Verification (pasted):**
  ```
  $ dotnet test backend/Lumen.slnx   -> UnitTests:        Passed! Failed: 0, Passed: 9
                                        IntegrationTests: Passed! Failed: 0, Passed: 3
  # SpineLiveTests (WebApplicationFactory + live Keycloak :8080 + Vault :8200 + Postgres :55432):
  #   POST /onboarding/start (Keycloak user -> Vault DEK -> encrypted profile) -> 200
  #   GET /me sans token -> 401 ; password-grant login -> GET /me -> 200, displayName decrypted
  #   raw display_name_enc bytea is ciphertext ("María" absent)
  # CryptoEnvelopeLiveTests: envelope round-trip + crypto-shred precondition (delete user_keys -> undecryptable)
  $ dotnet build backend/Lumen.slnx  -> 0 Warning(s), 0 Error(s)
  ```
- **T10, T11 done** (rate limiter + PII enricher + NetArchTest + OpenAPI test). **Deep security review done** (→ [`../specs/2026-05-31-build-strategy/p1-security-review.md`](../specs/2026-05-31-build-strategy/p1-security-review.md)): crypto core + tenant isolation **SOUND**; perimeter blockers found.
- **Security fixes landed:** ProblemDetails error handling (no stack leak) · PII GUID redaction + no user-id in exceptions · server-side password (12–128) + email/field validation · fail-closed dev-secret guard · interim `azp` token guard · RS256 + 30s clock-skew · DEK-provision idempotency · **M1** `/onboarding/start` EF transaction + Keycloak orphan compensation (typed 409/502; dup-email→409 test) · **M3** `UseForwardedHeaders` (real client IP behind Caddy) · **realm** brute-force + password policy + least-privilege service account · **FK migration** (schema-backed crypto-shred) + column max-lengths.
- **T12 done:** `ci-backend.yml` (build+unit; integration job brings up the compose infra, migrates, runs integration tests). **P1 is ready for review/merge.** *Deferred to P3a (documented, lower value pre-Dart-client):* committed `openapi.json` snapshot + drift guard, and full Testcontainers conversion (compose-in-CI already gives isolated integration runs).
- **For reviewer:** stack is up; `dotnet test backend/Lumen.slnx` → 23 green. **Two review passes done:** the deep adversarial security review (`p1-security-review.md`, must-fixes resolved) **and** `/code-review high` (41 candidates → 10 findings → all 6 distinct issues fixed: PII-enricher recursion, email normalization, consent-FK retain, HTTPS-metadata gate, service-account-token reject, Vault-outside-transaction). On acceptance: merge `phase/01-spine`, tag `phase-01`, advance NEXT to P3a. **P11 release-blockers** (audience mapper, Vault AppRole/sops secrets, prod TLS) tracked in the review doc.
- **Deferred to P11 (tracked prod release-blockers):** full JWT audience mapper; Vault AppRole + sops secrets (no static root token); `RequireHttpsMetadata` env-gate; prod TLS/AllowedHosts. Medium items (per-user AAD/Vault-context binding, enumeration oracle) tracked in the review doc.
- **Note:** integration tests target the live dev stack (`[Trait Category=LiveStack]`); T12 swaps to Testcontainers for CI.
- **Deviations:** EF pinned 10.0.4 (Npgsql provider) for warnings-clean; unit tests consolidated in `Lumen.UnitTests` (per-layer split deferred).
- **Resume:** `git checkout phase/01-spine`; confirm `dotnet test backend/Lumen.slnx` green, then continue at T2 (Vault — the dev stack on `localhost:8200` is available for the round-trip).

---

### Phase P2 ⚠ — Crypto-shred erasure + Hangfire

- **Status:** TODO · **Safety-critical: YES** · **Depends on:** P1 · **Branch:** `phase/02-shred`
- **Goal:** prove right-to-erasure while crypto is fresh; introduce Hangfire (Postgres storage) + `IJobCryptoContext`, validated by `CryptoShredJob`.
- **Architecture refs:** §F (erasure), §C (jobs).
- **Preconditions:** none new clinical/legal (consent/age fields exist from P1). Note the **MinIO-delete branch is a tracked no-op here, finalized in P7a** (do not mark erasure "complete" for objects yet).

**Kickoff prompt**
```text
Phase: P2 — Crypto-shred + Hangfire (SAFETY-CRITICAL). Read §0/§1/§2/§5 + phase P2 + ARCHITECTURE §F.
subagent-driven-development; strict TDD; .NET 10. Branch phase/02-shred. Deep review. Stop at NEEDS_REVIEW.
```

**Exit criteria**
- [ ] `DELETE /me` 202 → `CryptoShredJob` makes ciphertext provably unreadable; Keycloak user disabled; `users` tombstoned; push tokens emptied; `admin_audit_log` entry; idempotent.
- [ ] Backup-bytes-before-shred no longer decrypt; **job-scoped logs PII/DEK-scrubbed**; `DELETE /me` enqueue-flood guard.
- [ ] Hangfire on Postgres storage, dashboard gated to `lumen-admin`; crypto-module coverage ≥85%; **deep review passed**.

**Tasks (outline — detail at phase entry):** `user_devices` + `admin_audit_log` entities/migration → Hangfire registration (Postgres storage, gated dashboard) → `IJobCryptoContext` → `CryptoShredJob` (delete `user_keys`, empty tokens, tombstone user, MinIO-delete no-op TODO, audit entry; idempotent) → `DELETE /me` (enqueue + disable + 202) → the `Lumen.Security.Tests` GDPR baseline (unreadable + backup-unreadable + idempotent + job-log-scrubbed) → deep review.

**STATUS**
- **State:** DONE (merged to main 2026-06-14, tag `phase-02`)  ·  **Branch:** `phase/02-shred`  ·  **PR:** [#1](https://github.com/DizaGit2/Endo/pull/1)  ·  build warnings-clean (`-warnaserror`)  ·  **57 tests green** (25 unit + 27 integration + 5 GDPR security)  ·  per-task two-stage review (spec + quality) + final whole-phase deep review + adversarial multi-agent `/review` (9-dimension, 30 agents) — **all confirmed findings applied** (2 important + minors/nits; 2 findings refuted as false-positives)
- **Tasks done** (each = one `feat`/`test` commit + one `refactor` review-fix commit; executed via `subagent-driven-development`):
  - **T1** `UserDevice` + `AdminAuditLog` entities + EF config + migration `AddUserDevicesAndAuditLog` (snake_case tables, PascalCase columns; `admin_audit_log` has **no** user-FK so it survives the tombstone). Added `ModelSyncTests` (unit drift guard) + shared `TestFixtures`.
  - **T2** Hangfire (Postgres storage) + `AddHangfireServer` (gated off in tests via `Hangfire:EnableServer`) + `/hangfire` dashboard gated to realm role `lumen-admin` (`HangfireDashboardAuthorizationFilter`, deny-by-default, never throws, unit-tested ×7). Pinned `Newtonsoft.Json` 13.0.4 to override Hangfire's vulnerable transitive 11.0.1 (NU1903).
  - **T3** `IJobCryptoContext` + `IJobCryptoContextFactory` (Application) / `JobCryptoContext` + `JobCryptoContextFactory` (Infra, scoped) — job-scoped DEK custody, an intentional mirror of `UserCryptoContext` (unwrap-once, zeroed on dispose, tenant-isolated).
  - **T4** `CryptoShredJob`: atomic guarded tombstone-claim (`ExecuteUpdate WHERE DeletedAt==null`) → delete `user_keys` (the crypto-shred) → delete `user_devices` → exactly one `admin_audit_log` row; idempotent + race-safe (single audit row without relying on Hangfire serialization); PII/DEK-free logs; deterministic via injected `TimeProvider`. MinIO delete = explicit `TODO(P7a)` no-op; `EmailHash` retained (deferred decision) — both documented, **not** claimed erased.
  - **T5** `DELETE /me` (auth) → enqueue `CryptoShredJob` → `IKeycloakAdmin.DisableUserAsync` → 202; already-tombstoned flood guard (idempotent DELETE). Order per §F: enqueue → disable → 202.
  - **T6** `Lumen.SecurityTests` GDPR baseline (ciphertext-unreadable-after-shred · backup-bytes-unreadable · idempotent-single-audit · job-logs-PII-scrubbed via the **real** `PiiRedactionEnricher`) + CI step (`if: always()`) + `DisableTestParallelization` on the live-stack assemblies.
- **Verification (pasted):**
  ```
  $ dotnet build backend/Lumen.slnx -warnaserror   -> 0 Warning(s), 0 Error(s)
  $ dotnet test backend/tests/Lumen.UnitTests        -> Passed!  Failed: 0, Passed: 25
  $ dotnet test backend/tests/Lumen.IntegrationTests -> Passed!  Failed: 0, Passed: 23
  $ dotnet test backend/tests/Lumen.SecurityTests    -> Passed!  Failed: 0, Passed:  4
  ```
- **Erasure-completeness ledger (P2):** DELETED → `user_keys` (the shred — renders all ciphertext permanently unreadable), `user_devices`. TOMBSTONED → `users` (`DeletedAt`; id + `EmailHash` kept for FK integrity / deferred re-registration decision). RETAINED-as-undecryptable → `user_profile_enc`. RETAINED by design → `consent_records` (legal proof, no plaintext PII), `admin_audit_log` (+1 erasure row, bare user GUID, no user-FK). DEFERRED (NOT done) → MinIO `{user_id}/` objects → **P7a**.
- **Deviations / notes (anti-drift):** the GDPR test project is named **`Lumen.SecurityTests`** (this outline said `Lumen.Security.Tests`). `IJobCryptoContext` is established now but the shred job never decrypts (it only deletes keys); the abstraction is proven by its own round-trip + tenant-isolation tests for later jobs (P6/P7b/P9b). Live-stack integration/security tests run **serialized** (`DisableTestParallelization`) to avoid WebApplicationFactory cold-start contention against the shared Keycloak/Vault — re-run cleanly if a transient 502 appears under cross-assembly parallelism.
- **`/review` pass (commits `7030938`..`d1e4047`) — confirmed findings fixed, including the two earlier-flagged seams:** (1) the **502/Keycloak-disable seam is resolved** — `DELETE /me` now re-attempts the (idempotent) disable on the already-tombstoned branch, so a transient disable failure self-heals on retry instead of leaving a shredded-but-loginable account. (My earlier "mitigated by the tombstone guard" framing was **wrong** — the guard had been *dropping* the disable.) (2) the **residual post-erasure footprint is reduced** — `Locale`/`Timezone` are now blanked on shred; only the bare user GUID, the documented `EmailHash`, undecryptable ciphertext, consent proof, one audit row, and the deferred-to-P7a MinIO objects remain. Other fixes: non-vacuous PII-log-scrub test (+ negative control), `(EntityId, Action)` audit index, concurrency-race + real Hangfire enqueue→execute tests, explicit `[AutomaticRetry]`, accurate OpenAPI 202/401, and nits (`volatile` DEK, sequential-use docs, test hygiene). Two findings were **refuted** as false-positives by adversarial verification (an "idempotency guard racy" claim already accurately documented; a CI `if:` change whose suggested fix was semantically wrong). Two read-only verifier agents confirmed **no regression** to erasure/DEK-custody/idempotency/§F-order.
- **Accepted & merged 2026-06-14** (human authorized the merge on the strength of the layered review above — per-task two-stage + final deep + 9-dimension adversarial `/review` with all confirmed findings applied). Merged to `main`, tagged `phase-02`, PR #1 closed. **NEXT = P3a.**

---

### Phase P3a — Flutter foundation + theming + OpenAPI pipeline

- **Status:** IN_PROGRESS (started 2026-06-14) · **Depends on:** P2 · **Branch:** `phase/03a-client-foundation`
- **Goal:** install Flutter; scaffold the app; port the design tokens; stand up the OpenAPI→Dart pipeline + CI drift guard; wire static screens 1/36/37.
- **Preconditions:** ✅ **CLEARED 2026-06-14.** Flutter/Android installed — `flutter doctor` green (Flutter 3.44.1 stable, Dart 3.12.1, Android SDK 36.1.0, VS 2026, Chrome, 3 devices; "No issues found"). Decisions **D-03** (es-ES primary, 2026-06-01) + **D-05** (locale-driven ICU formatting, es-ES default; API locale-neutral) + **D-06** (metric-only v1, reserve `users.unit_system` enum) + **D-07** (lean client-privacy scope) **approved** — see decision-sheet.md & `ARCHITECTURE.md §A`. **L-03** screen-31 trust copy drafted v0 (ES+EN, pending DPO sign-off) — see legal-asks.md. Definitions: hormone/phase palettes (already in CLAUDE.md). **Phase is unblocked to start.**
- **Kickoff prompt:** standard, pointing at flutter companion + CLAUDE.md tokens; **step 1 = run the Flutter install and confirm `flutter doctor` before any Dart.**
- **Exit criteria:** `flutter doctor` green recorded; golden tests (light+dark) pass for static screens; `ThemeData` token assertions match CLAUDE.md; OpenAPI→Dart pipeline + CI drift guard operational; client coverage ≥60%.
- **Tasks (bite-sized TDD; one commit each; via `subagent-driven-development`, detailed at phase entry 2026-06-14):**
  - [x] **T1 — Scaffold + deps + lints** (imperative shell). `flutter create` at `client/` (org `com.lumen`, project `lumen`, `--platforms=android,ios,web`); feature-first dirs per flutter companion §1.2; pubspec deps (flutter_riverpod, riverpod_annotation, go_router, dio, built_value, built_collection, flutter_appauth, flutter_secure_storage, hive, hive_flutter, intl) + dev (build_runner, riverpod_generator, built_value_generator, openapi_generator[_annotations], alchemist, flutter_lints, mocktail); `analysis_options.yaml`. Verify `flutter pub get` + `flutter analyze` (0 issues) + `flutter test`.
  - [x] **T2 — `LumenColors` ThemeExtension** (TDD). Test exact light+dark hex for all 10 tokens (incl. border `0x1F` alpha) + lerp/copyWith. `core/theme/lumen_tokens.dart` (values per flutter companion §5.1 / CLAUDE.md).
  - [x] **T3 — Hormone + phase palettes** (TDD). `HormonePalette.forCode` (7 codes + `estradiol`/`estrogen` alias + muted fallback) exact; `PhasePalette` 4 phases light/dark exact. `core/theme/{hormone_palette,phase_palette}.dart`.
  - [x] **T4 — ThemeData builders + typography** (TDD). `lumenTheme(Brightness)`: `LumenColors` attached; `ColorScheme` derived (primary=accent, surface, etc.); `TextTheme` uses **only** `FontWeight.w400`/`w500` (assert); system font stack; section-label widget the only uppercase. `core/theme/lumen_theme.dart`.
  - [x] **T5 — Locale formatting + units (D-05/D-06)** (TDD). `core/formatters/lumen_formats.dart` via `intl`: week-start, date, 24-h time, comma decimal driven by locale; es-ES default vs en-US contrast test. `UnitSystem` enum (default `metric`) + kg/cm formatters (metric-only v1, enum reserved).
  - [x] **T6 — Golden harness + `LumenScaffold`**. `flutter_test_config.dart` (alchemist: deterministic font, no real shadows); `shared/widgets/lumen_scaffold.dart` (themed bg, 5-tab bottom-nav stub, theme toggle affordance); smoke golden light+dark.
  - [x] **T7 — Static screens 1/36/37 + goldens** (golden-TDD). Port welcome (1), privacy (36 — per **D-07**: no analytics toggle; warrant-canary placeholder L-08; accurate data-handling stance), help_about (37). Light+dark golden each.
  - [x] **T8 — OpenAPI snapshot + Dart client**. Emit P1+P2 spec → `backend/contract/openapi.json` (P1-deferred deliverable) via Swashbuckle CLI (`dotnet swagger tofile`; fallback: boot compose + `curl /swagger/v1/swagger.json`); pin to `client/openapi/lumen.openapi.json`; openapi_generator (dio + built_value) → `client/lib/api/`; `flutter analyze` clean; smoke import test. JDK at `C:\Program Files\Android\Android Studio\jbr`. Commit spec + config + generated together.
  - [x] **T9 — `ci-client.yml` + OpenAPI drift guard**. GH Actions: pub get → analyze → test (goldens) → coverage; drift guard regenerates the spec from the backend and `diff`s vs the committed snapshot, failing on drift.
  - [x] **T10 — Coverage ≥60% + wrap**. `flutter test --coverage`; record proof; fill STATUS; set ledger NEEDS_REVIEW.

**STATUS**
- **State:** NEEDS_REVIEW (2026-06-14) · **Branch:** `phase/03a-client-foundation` · **106 client tests + 3 backend OpenAPI tests green · coverage 97.60%** (hand-written; generated `lib/api/**` + `*.g.dart` excluded) · build/analyze clean. Executed via `subagent-driven-development` (implementer + spec + quality review per task; review fixes applied).
- **Precondition proof — `flutter doctor` GREEN (2026-06-14):**
  ```
  [✓] Flutter (Channel stable, 3.44.1, on Windows 11 Pro 25H2, locale en-US)
  [✓] Windows Version (11 Pro 64-bit, 25H2)
  [✓] Android toolchain - Android SDK 36.1.0
  [✓] Chrome - develop for the web
  [✓] Visual Studio - Visual Studio Professional 2026 18.6.0
  [✓] Connected device (3 available)
  [✓] Network resources
  • No issues found!
  ```
  Dart 3.12.1 · JDK (Android Studio jbr) OpenJDK 21.0.10 at `C:\Program Files\Android\Android Studio\jbr`.
- **Tasks done (T1–T10, each = feat/test commit + a review-fix commit where the two-stage review found issues):**
  - **T1** Flutter scaffold (`client/`, org `com.lumen`, android/ios/web), feature-first dirs, deps (riverpod, go_router, dio, built_value, flutter_appauth, secure_storage, hive, intl + codegen/test devs), lints. *(Two-stage review: gitignore/`description` nits fixed.)*
  - **T2** `LumenColors` ThemeExtension — all 10 light+dark tokens (border `0x1F` alpha), copyWith/lerp. *(Spec review independently re-derived all 20 hex from CLAUDE.md — exact.)*
  - **T3** `HormonePalette` (7 codes + estradiol alias + muted fallback) + `PhasePalette` (4 phases light/dark). *(All values verified vs CLAUDE.md.)*
  - **T4** `lumenTheme(Brightness)` — M3 ColorScheme from tokens, two-weights-only typography guard, app shell (`LumenApp`), counter demo removed. *(Review's WCAG finding was independently recomputed and REJECTED: real contrast 4.27/3.43 light, 6.71/5.71 dark — at/above large-text AA; on-colors are design-faithful, a11y stays the P12 gate. Extension test widened to all 10 fields; weight-normaliser doc corrected.)*
  - **T5** `LumenFormats` (D-05 locale-driven date/24h-time/comma-decimal + first-day-of-week; D-06 metric-only + reserved `UnitSystem` enum). *(Review fix: a latent `firstDayOfWeek` bug — en_GB/en_AU/bare-en were mis-classified Sunday-first — corrected to en_US-only; `initializeDateFormatting` breadcrumb for P3b.)*
  - **T6** Alchemist golden harness (`flutter_test_config.dart`, CI-mode: text obscured + shadows off → OS-independent/deterministic) + `LumenScaffold` + `LumenBottomNav` (5-tab stub) + smoke golden. *(Determinism re-confirmed across runs; `dart_test.yaml` golden tag declared.)*
  - **T7** Static screens **1 welcome, 36 privacy, 37 help/about** ported from `Screens/*.html` + light/dark goldens; `LumenSectionLabel`; `WelcomeScreen` wired as home. **D-07 applied** (privacy analytics toggle omitted). *(Review fixes: ALL-CAPS literal → `LumenSectionLabel` transform; primary CTA → enabled `FilledButton` with token `onPrimary`; dark-mode toggle made visible; goldens regenerated.)*
  - **T8** OpenAPI pipeline: `backend/contract/openapi.json` emitted via an in-process env-gated snapshot/drift test (no docker), pinned byte-identical to `client/openapi/lumen.openapi.json`; **Dart dio+built_value client generated into `client/lib/api/`** (committed) + smoke test round-tripping a `built_value` DTO. **Deviation:** the `openapi_generator` Dart package is incompatible here (`source_gen` <=2 vs built_value_generator needing >=3), so generation uses the **openapi-generator-cli JAR 7.11.0** (`dart-dio`) — documented with regen command in `client/lib/api/README.md`. *(Review confirmed snapshot==live and the generated client compiles via `flutter test`.)*
  - **T9** `.github/workflows/ci-client.yml` (pub get → spec-sync byte check → analyze → test+coverage gate) + `openapi-contract` no-docker drift job in `ci-backend.yml` (asserts live backend == committed snapshot == pinned client spec). *(Review caught a CRITICAL coverage-glob bug: `*/lib/api/*` under-excluded nested generated files, reporting 58.6% vs the true 97.60%. Replaced the lcov-glob gate with a deterministic `client/tool/check_coverage.dart` that excludes `lib/api/**` + `*.g.dart` by path.)*
  - **T10** Verification + wrap (this block).
- **Verification (pasted, 2026-06-14):**
  ```
  client (PUB_CACHE=C:\pub_cache):
    flutter analyze            -> No issues found!
    flutter test --coverage    -> 00:03 +106: All tests passed!   (incl. 8 golden scenarios light+dark)
    dart run tool/check_coverage.dart -> 366/375 = 97.60% (19 generated files excluded); GATE PASS >= 60%
  backend (no docker):
    dotnet test --filter ~OpenApi -> Passed!  Failed: 0, Passed: 3   (snapshot==live==pinned client spec)
  ```
- **Exit criteria — all met:** `flutter doctor` green recorded ✓ · light+dark goldens pass for the static screens (welcome/privacy/help + LumenScaffold) ✓ · `ThemeData`/token assertions match CLAUDE.md ✓ · OpenAPI→Dart pipeline + CI drift guard operational ✓ · client coverage ≥60% (97.60%) ✓.
- **Deviations / dev-notes (anti-drift):**
  - **PUB_CACHE:** the home path has a space which breaks Dart native-asset build hooks (objective_c via flutter_appauth); all local flutter/dart runs use `PUB_CACHE=C:\pub_cache` (backslash). If "Building native assets failed / hook.dill not found" appears, `flutter clean; flutter pub get` resets `.dart_tool`. CI (Linux) is unaffected (no space in path).
  - **OpenAPI generator = JAR, not the Dart package** (see T8); CI/regen needs Java + the JAR (download per `client/lib/api/README.md`). The committed client is the source of truth; CI verifies drift + compile, it does not regenerate.
  - **Coverage gate** is a committed Dart script (not lcov) — deterministic across lcov versions.
  - `flutter_appauth`/`flutter_secure_storage`/`hive` are wired as deps but their real use is **P3b** (OIDC + cache); `initializeDateFormatting` startup wiring is a P3b breadcrumb in `main.dart`.
  - Deferred non-blocking polish (tracked): toggle slide-animation + `_NavRow`/`_SettingsNavRow` dedup → when settings interactivity/next settings screen land; `LumenApiApi` double-word generator class name (deterministic output).
- **For reviewer:** `git checkout phase/03a-client-foundation`; client checks `cd client; $env:PUB_CACHE='C:\pub_cache'; flutter analyze; flutter test --coverage; dart run tool/check_coverage.dart`; drift `dotnet test backend/Lumen.slnx --filter ~OpenApi`. A final whole-phase review was run after T10. On acceptance: merge `phase/03a-client-foundation`, tag `phase-03a`, advance NEXT to **P3b** (client OIDC + cache + screens 2/31).

---

### Phase P3b — Client OIDC + online-only cache + screens 2/31

- **Status:** TODO · **Depends on:** P3a (+ P1 endpoints) · **Branch:** `phase/03b-client-spine`
- **Goal:** prove the client half of the spine — login via Keycloak renders decrypted `GET /me`.
- **Preconditions:** D-07 (app-lock scope), L-03 (corrected privacy copy). Hard prereq is **P1** endpoints + committed spec (P2 is soft ordering).
- **Exit criteria:** real device logs in (PKCE) → `POST /onboarding/start` → screen 31 shows decrypted `GET /me`; tokens in Keychain/Keystore; **Hive box unreadable without the secure-storage key**; online-only write-errors-don't-queue test; goldens both themes.
- **Tasks (outline):** flutter_appauth PKCE against realm `lumen` → secure token storage → Dio interceptor (bearer + single-flight 401 refresh + PII-safe logging) → `CachedQuery` online-only + encrypted Hive → GoRouter auth/onboarding guard → wire screen 2 (account→OIDC+onboarding/start) + screen 31 (profile) → integration_test + Hive-at-rest test. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P4a — Backend: Onboarding-rest + Cycle + Symptoms

- **Status:** TODO · **Depends on:** P3b · **Branch:** `phase/04a-logging-backend`
- **Goal:** first wide band of encrypted CRUD reusing `IUserCryptoContext`; onboarding completion; Cycle + Symptoms modules; non-clinical placeholder snapshot.
- **Preconditions (MUST resolve — this is the dense product-decision phase):** decisions **D-08** (intensity scale 0–10 vs 1–5), **D-09** (symptom type/triggers/related/region/body-map shape), **D-10** (mood/energy/libido), **D-11** (quick vs full payloads), **D-12** (timezone/today), **D-13** (soft-delete/pagination/future-dating/notes), **D-14** (goals + hormone-default), **B15** (cycle-setup endpoint home), **B16** (hormone code↔label). Definitions: goal enum, region seed, mood labels, hormone code-label table (from `definitions.md`). Clinical: **C-03/C-04 bounds** can use documented defaults from decision-sheet/clinical-asks but flag for sign-off.
- **Exit criteria:** onboarding completes; Cycle/Symptoms/settings-cycle endpoints pass integration + tenant-isolation + encryption tests; migrations clean; placeholder snapshot unmistakably non-clinical; OpenAPI + Dart client regenerated in the same PR; global coverage ≥70%.
- **Tasks (outline):** entities/migrations (`cycle_events`, `cycle_day_logs`, `symptoms`, `user_insight_snapshot` placeholder, `user_devices` upsert endpoint) → onboarding `baseline/goals/hormones/notifications/complete` (+ cycle-setup home) → Cycle endpoints → Symptoms endpoints (quick + full, region/type/triggers per D-09) → settings/cycle → validation (intensity bounds per D-08, enum membership, calendar windows, onboarding state machine) → OpenAPI+Dart regen. *(Detailed at phase entry, once D-08..D-14 are resolved.)*

**STATUS** _(empty)_

---

### Phase P4b — Flutter: screens 3–14, 32

- **Status:** TODO · **Depends on:** P4a · **Branch:** `phase/04b-logging-client`
- **Preconditions:** P4a endpoints green + regenerated client; decision D-14 (goal→dashboard mapping may stay ungated v1).
- **Exit criteria:** screens 3–14, 32 work against the live backend in both themes; designed error/retry states on write screens 9/11/12/13; goldens + integration_test green; drift guard clean.
- **Tasks (outline):** onboarding screens 3–7 (resume guard) → dashboard/calendar/day-detail/phase-correction → quick check-in bottom sheet → symptom form + body map (snap-to-region per D-09) → cycle settings → goldens + integration. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P5 — Body + Activity + Treatment

- **Status:** TODO · **Depends on:** P4a · **Branch:** `phase/05-body-activity-treatment`
- **Preconditions:** decisions **D-15** (body/activity field shapes), **D-16** (medication catalog link/frequency/logging/effectiveness). Definitions: metric/activity/medication-category enums (`definitions.md`). Clinical **C-13** (`ref_medication` seed) can start as free-text (D-16) but the curated catalog must precede launch.
- **Exit criteria:** Body/Activity/Treatment CRUD pass integration + authorization; encrypted columns ciphertext-only; schedules persisted in a P9a-readable form; screens 22–27 both themes; client regenerated.
- **Tasks (outline):** entities/migrations (body_metrics, activity_entries, medications + schedules + logs, `ref_medication` seed) → Body/Activity/Treatment endpoints → validation → screens 22–27 → regen. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P6 ⚠ — Inference engine + matviews + insights

- **Status:** TODO · **Safety-critical: YES** · **Depends on:** P4a · **Branch:** `phase/06-inference`
- **Preconditions (clinical — MUST be signed off before starting):** clinical-asks **C-01..C-05** (phase/ovulation/estimator/spotting/regularity), **C-09** (confidence formula), **C-10** (missing-data catalog), **C-11** (insights methods/thresholds/claim copy), **B31** (`ref_insight_rule` registry), **C-12** (eligible population / suppression handling), and **L-04** (in-app disclaimer copy). Hangfire already runs (from P2) — only ADD recurring/debounced jobs.
- **Exit criteria:** engine matches golden fixtures + reproducible; rules from `ref_insight_rule` not hard-coded; **safe-failure framing** (sparse input → explicit low-confidence, never a confident wrong phase); matviews refresh nightly + debounced on-write; deep review + mutation spot-check; inference coverage ≥90%; screens 8/15/16/20-base/21/33.
- **Tasks (outline):** engine (phase/confidence/missing-data, param-driven) → `ref_insight_rule` + matviews migrations → `RecomputeInsightSnapshotJob` + `RefreshMatviewsJob` (debounced) → insights endpoints → golden-fixture + determinism + safe-failure tests → screens. *(Detailed at phase entry, once clinical sign-off lands.)*

**STATUS** _(empty)_

---

### Phase P7a — Labs infra + upload + scan + encrypted store

- **Status:** TODO · **Depends on:** P5, P6 · **Branch:** `phase/07a-labs-infra`
- **Preconditions:** decision **D-17** (quota model), **D-18** (failure-state UX + `rejection_reason` codes). Adds MinIO + ClamAV to compose.
- **Exit criteria:** scanned, **server-side-encrypted** PDF lands in MinIO; EICAR rejected (422 + counter, nothing stored); magic-byte/MIME/size validation; **`CryptoShredJob` MinIO recursive delete finalized + tested** (erasure physically removes objects); `INotificationDispatcher` no-op port added.
- **Tasks (outline):** compose minio+clamav → `POST /labs` (validate → ClamAV INSTREAM → DEK-encrypt → MinIO store → quota → enqueue) → `labs` lifecycle → finalize crypto-shred object delete + test → notification port stub. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P7b ⚠ — LLM (Anthropic) parse + validate + confirm

- **Status:** TODO · **Safety-critical: YES (ultra review)** · **Depends on:** P7a · **Branch:** `phase/07b-lab-parse`
- **Preconditions (clinical — MUST be signed off):** clinical-asks **C-06** (hormone reference ranges), **C-07** (unit whitelist + conversions), **C-08** (GLP-1), **B37/D-23** (sex/eligibility for range selection). Provider = Anthropic (D4); start the DPA during P4–P6.
- **Exit criteria:** end-to-end upload→scan→store→parse→drafts→confirm→chart; every LLM output passes strict JSON schema + unit whitelist + physiological-range + server-side confirm re-validation; record-replay (no live LLM in CI); `ref_hormone_range` seeded; ultra review; lab coverage ≥85%; screens 17–20.
- **Tasks (outline):** `ILlmClient`/`ReplayLlmClient` → `lab_result_drafts`/`lab_results`/`ref_hormone_range` migrations → `ParseLabJob` (decrypt→PdfPig→Anthropic strict-JSON→validate→drafts→notify) → `confirm` (transactional, server-side re-validate) → quota → validation matrix + record-replay tests → screens. *(Detailed at phase entry, once ranges signed off.)*

**STATUS** _(empty)_

---

### Phase P8 — Reports (QuestPDF)

- **Status:** TODO · **Depends on:** P5, P6, P7b · **Branch:** `phase/08-reports`
- **Preconditions:** decisions **D-20** (Link/Email sharing), **D-22** (range/sections/identity/retention); legal **L-04** (report disclaimer). Definitions: report sections + range enums (`definitions.md`).
- **Exit criteria:** owner-only DEK-encrypted QuestPDF report download; insights hub from matviews; rate limit 5/day; screens 28–30; no server-side sharing surface (per D-20 default).
- **Tasks (outline):** `reports` entity → `GET /insights/hub` → `POST /reports/doctor` + `GenerateDoctorReportJob` (QuestPDF, DEK-encrypt, MinIO) → `GET /reports/{id}/download` (owner-only) → screens. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P9a — Notifications + nightly dispatch

- **Status:** TODO · **Depends on:** P7b, P8 · **Branch:** `phase/09a-notifications`
- **Preconditions:** decision **D-19** (scheduling model — the dispatch-architecture call); full bilingual push copy (legal/product). Swaps the P7a notification no-op for real FCM/APNs.
- **Exit criteria:** device receives real push from nightly dispatch + med reminder; lab-ready push deep-links to screen 20; i18n ES/EN; per-user-local timing (per D-19/D-12).
- **Tasks (outline):** FCM/APNs senders behind the port → device register/refresh → `NightlyNotificationDispatchJob` (per-user local time + quiet hours) → i18n resources → Flutter push + deep-link → screens 7/34. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P9b — GDPR export

- **Status:** TODO · **Depends on:** P9a · **Branch:** `phase/09b-export`
- **Preconditions:** decision **D-21** (CSV + delivery channel); legal **L-05/L-06/L-07** (privacy policy, ToS, retention/deletion UX).
- **Exit criteria:** export zip (JSON + decrypted lab PDFs) via 7-day signed URL; **per-user export rate limit**; **lifecycle deletion verified**; **export path log-scrubbed**; **MinIO `exports/` deletion on crypto-shred verified**; erasure UX re-verified from the UI; screen 35.
- **Tasks (outline):** `BuildDataExportJob` → email/signed-URL → rate limit + log-scrub + lifecycle tests → re-verify erasure incl. exports deletion → screen 35. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P10 — Admin reference-data

- **Status:** TODO · **Depends on:** P5, P6, P7b · **Branch:** `phase/10-admin`
- **Preconditions:** seed-provenance/versioning contract (gap **X13**) set when ref tables were seeded.
- **Exit criteria:** `lumen-admin` Razor CRUD over `ref_hormone_range`/`ref_medication`/`ref_insight_rule` with `admin_audit_log` before/after; non-admin 403; edits propagate to P6/P7b; cross-module tests.
- **Tasks (outline):** Razor `/admin` (role-gated) → CRUD + audit writer → internal read endpoints → cross-module consistency tests. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P11 — CI/CD + backups + prod hardening

- **Status:** TODO · **Depends on:** P9b, P10 · **Branch:** `phase/11-cicd-prod`
- **Preconditions:** §I infra decisions (gap **X19**): off-site backup provider, **Vault auto-unseal for prod**, operator MFA, crash reporting.
- **Exit criteria:** PR runs tests; merge deploys to VPS; nightly off-site backups + monthly restore drill (proves shredded users stay unreadable); secrets sops-only; auto-unseal; prod Caddyfile (Let's Encrypt, HSTS, CSP, edge limits); Trivy/vuln scans blocking.
- **Tasks (outline):** GitHub Actions CD → backup scripts + restore drill → sops/age secrets → Vault prod unseal → prod Caddyfile → security scans. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P12a — Observability sidecar

- **Status:** TODO · **Depends on:** P11 · **Branch:** `phase/12a-observability`
- **Exit criteria:** sidecar (prometheus/loki/promtail/grafana/alertmanager/exporters + WireGuard) live; P1 OTLP retargeted; dashboards populated; every alert verified to fire under simulation; Loki PII-scrubbed; survives a main-VPS outage.
- **Tasks (outline):** sidecar compose → WireGuard → dashboards → alert rules + simulated fires → Loki ingestion + scrub check. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

### Phase P12b — Final production-readiness pass

- **Status:** TODO · **Depends on:** P12a · **Branch:** `phase/12b-readiness`
- **Exit criteria:** seeded demo account; all 37 screens + screen-15 landscape walked end-to-end in light+dark with empty/error/online-failure states; a11y pass; load smoke; full suites green; security scans (blocking) clean; final GDPR/security sign-off; remaining §I items resolved or backlogged.
- **Tasks (outline):** demo seed → 38-screen both-theme walk → a11y + casing/no-emoji/two-weight audit → load smoke → final GDPR/security review. *(Detailed at phase entry.)*

**STATUS** _(empty)_

---

## §4 Decision log (build-time)

| Date | Decision | Where recorded |
|---|---|---|
| 2026-05-31 | .NET 10 (was .NET 8) | ARCHITECTURE §B; spec D1 |
| 2026-05-31 | LLM provider = Anthropic (Claude) | ARCHITECTURE §A/§I; spec D4 |
| 2026-05-31 | Lab PDF encryption = server-side | ARCHITECTURE §D/§E; spec D5 |
| 2026-06-01 | D-01 password policy (min 12, Unicode, block-breached, no forced rotation), D-02 consent record (versioned, written at /onboarding/start), D-03 locale es-ES primary (device fallback) — adopted as defaults for P1 | decision-sheet.md; ARCHITECTURE §A on P1 merge |
| 2026-06-14 | **D-05** locale/formatting (ICU, es-ES default; API locale-neutral), **D-06** metric-only (+ `users.unit_system` enum), **D-07** lean client-privacy scope — approved (recommended defaults) to unblock P3a; **L-03** screen-31 trust copy drafted v0 (pending DPO sign-off) | decision-sheet.md; legal-asks.md (L-03); `ARCHITECTURE.md §A` |
| _pending_ | Product decisions D-04, D-08…D-23 | decision-sheet.md → record on approval |
| _pending_ | Clinical sign-offs C-01…C-15 | clinical-asks.md → record on receipt |
| _pending_ | Legal items L-01…L-09 | legal-asks.md → record on receipt |
| _pending_ | §I infra (backup provider, Vault auto-unseal, operator MFA, crash reporting) | resolve at P0a/P11/P12b |

---

## §5 Glossary of paths & commands

| Thing | Value |
|---|---|
| Build branch | `design/build-strategy` (or `main` if merged) |
| Backend | `backend/` (`Lumen.Api`/`Application`/`Domain`/`Infrastructure` + `tests/`) |
| Client | `client/` (created P3a) |
| Infra | `deploy/` (`docker-compose.yml`, `Caddyfile.local`, `keycloak/realm-lumen.json`, `postgres/init.sql`, `vault/init.sh`) |
| OpenAPI contract | `backend/contract/openapi.json` (committed) |
| Bring up infra | `docker compose -f deploy/docker-compose.yml up -d <services>` |
| Tests | `cd backend; dotnet test --nologo` (Testcontainers needs the Docker daemon) |
| Migrations | `dotnet ef migrations add <Name> --project backend/src/Lumen.Infrastructure --startup-project backend/src/Lumen.Api` |
| Verify env | environment companion §4 checklist |
| Local ports | Caddy 80/443; Postgres host 55432→5432 (host 5432 was taken); Keycloak 8080 (localhost); Vault 8200 (localhost); MinIO (P7a) |
