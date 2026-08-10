<!-- Companion reference to ../2026-05-31-build-strategy-design.md
     Produced by the build-strategy design workflow (2026-05-31). Faithful to docs/ARCHITECTURE.md.
     Note: this analysis predates final phase-number synthesis; phase IDs here are illustrative.
     The canonical phase numbering is in the main spec. -->

# Lumen — Flutter Client Integration Strategy

This document defines how the Flutter client is built, how it stays in lockstep with the .NET 10 backend, and how its work interleaves with the plan-driven backend phases. It is faithful to `docs/ARCHITECTURE.md` (single source of truth) and the design system in `CLAUDE.md`. Where it touches a locked decision (online-only + Hive, Keycloak OIDC, walking-skeleton sequencing, plan-driven fresh sessions), it conforms — it does not relitigate.

A note on numbering: `CLAUDE.md` and `ARCHITECTURE.md` both speak of "37 screens" but the inventory plus the screen 15 landscape variant yields 38 files. This document treats screens 1–37 as the logical screen set and screen 15-landscape as a render variant of screen 15, not a separate integration target.

---

## 0. Guiding principles

- **The OpenAPI document is the contract.** The Flutter client never hand-writes a DTO that the backend also owns. Every wire type comes from generated Dart. If the generated client and a screen disagree, the screen adapts or the backend contract changes — never a silent divergence.
- **A screen may not be wired before its endpoints exist and are integration-tested green.** This is the central scheduling constraint and it is what makes the interleave decision (§6) work.
- **Online-only is a feature, not a gap.** Per the locked decision and ARCHITECTURE.md §A ("Reads need network; writes do not queue"), Hive is a *read cache and a UI-state store*, never a write-ahead log. The client is honest about this: it shows network-required states rather than faking optimistic offline writes it cannot reconcile.
- **The mockups are the acceptance spec for visual fidelity.** The 37 HTML screens with their exact tokens are reproduced 1:1 in Flutter theming. Milestone 11 in ARCHITECTURE.md ("Flutter polish pass... every screen verified end-to-end") is the visual-fidelity gate.

---

## 1. Flutter project structure and state management

### 1.1 Recommended state management: Riverpod (v2, code-gen) + GoRouter

**Choice: `flutter_riverpod` + `riverpod_generator` for state; `go_router` for navigation.**

Justification (brief, against the alternatives):

- **Why Riverpod over Bloc.** This app is overwhelmingly CRUD-over-REST with a clear async-data lifecycle (loading → data → error → refresh) on nearly every screen. Riverpod's `AsyncNotifier`/`FutureProvider` model that lifecycle natively and compose cleanly with the generated API client. Bloc would force a hand-written event/state class pair per screen for what is, in 80% of screens, "fetch this, show it, let the user edit it." Riverpod is less ceremony for the same rigor.
- **Why Riverpod over plain Provider/`ChangeNotifier`.** Compile-safe dependency graph, no `BuildContext` coupling for reads (critical for the crypto/auth/cache layers that live below the widget tree), trivial override-for-test, and automatic disposal. The online-only cache layer (§4) needs providers that can be invalidated on demand (`ref.invalidate`) to force a network refresh — Riverpod makes that a one-liner.
- **Why code-gen (`@riverpod`).** Removes provider-type boilerplate and keeps provider signatures honest as the API client regenerates. A `@riverpod` provider that returns a generated DTO breaks at compile time if the DTO shape changes — exactly the lockstep signal we want.
- **Why GoRouter.** The app has a 5-tab bottom-nav shell (Home / Cycle / Hormones / Body / More per CLAUDE.md) plus deep modal/sheet flows (screen 9 bottom sheet, screen 20 bottom sheet) and a linear onboarding stack (1→7). `StatefulShellRoute` models the persistent-tab + nested-stack topology directly, and typed routes give compile-checked navigation. It also gives us a single place to enforce the auth redirect guard (§4.4).

### 1.2 Project layout (feature-first, mirroring the 10 backend modules)

The folder structure deliberately mirrors ARCHITECTURE.md §C's ten bounded contexts so a developer reasoning about "the Cycle module" sees the same word on both sides of the wire.

```
client/                                  (Flutter app root, sibling to backend/ and deploy/)
  pubspec.yaml
  build.yaml                             # build_runner config: riverpod + openapi client
  openapi/
    lumen.openapi.json                   # pinned snapshot pulled from the backend (see §2)
    openapi-config.yaml                   # generator config
  lib/
    main.dart
    app.dart                             # MaterialApp.router, theme wiring
    core/
      theme/
        lumen_tokens.dart                # design-system tokens, light + dark (see §5)
        lumen_theme.dart                 # ThemeData builders from tokens
        hormone_palette.dart             # fixed hormone colors (not theme-switched)
        phase_palette.dart               # cycle-phase colors, light/dark pairs
      router/
        app_router.dart                  # GoRouter + StatefulShellRoute
        routes.dart                      # typed route definitions
      auth/
        auth_controller.dart             # OIDC login/logout/refresh (flutter_appauth)
        token_store.dart                 # secure storage of tokens
        auth_interceptor.dart            # Dio interceptor: bearer + 401 refresh
      network/
        api_client.dart                  # configured generated client + Dio
        dio_provider.dart
      cache/
        hive_boot.dart                   # Hive init, box registration, adapters
        cached_query.dart                # generic online-only cache wrapper (see §4)
      error/
        failure.dart                     # typed failures: network/auth/validation/server
        error_mapper.dart                # maps DioException + problem+json -> Failure
    api/                                  # GENERATED — do not hand-edit
      lumen_api/                          # output of the OpenAPI generator
    features/
      onboarding/                        # screens 1–7   -> Onboarding module
      home/                              # screen 8       -> Cycle (dashboard read)
      checkin/                           # screen 9       -> Symptoms (quick)
      cycle/                             # screens 10,11,14 -> Cycle
      symptoms/                          # screens 12,13  -> Symptoms
      hormones/                          # screens 15,16,17 -> Hormones (series/detail/library)
      labs/                              # screens 18,19,20,21 -> Hormones (lab pipeline)
      body/                              # screens 22,23  -> Body
      activity/                          # screens 24,25  -> Activity
      treatment/                         # screens 26,27  -> Treatment
      reports/                           # screens 28,29,30 -> Reports
      settings/                          # screens 31–37  -> Settings
    shared/
      widgets/                           # phone-frame-faithful shared widgets
      formatters/                        # date/locale (Europe/Madrid default per doc)
  test/
    theme/                               # golden tests vs the HTML mockups
    features/                            # widget + controller tests per feature
  integration_test/                      # end-to-end vs seeded backend (milestone 11)
```

Each `features/<module>/` folder uses a small, consistent internal shape:

```
features/cycle/
  data/      cycle_repository.dart       # wraps generated API + Hive cache, returns domain types
  domain/    cycle_models.dart           # thin view models (only where a screen needs derived state)
  application/ cycle_providers.dart      # @riverpod AsyncNotifiers
  presentation/ cycle_calendar_screen.dart, day_detail_screen.dart, ...
```

Rationale for feature-first over layer-first: each backend phase delivers a *vertical* set of endpoints for one module, and each Claude session executes one phase. Feature-first means a phase's client work is confined to one folder, minimizing merge surface across the plan-driven fresh sessions.

---

## 2. OpenAPI → Dart client generation pipeline

### 2.1 Tooling

- **Backend side:** Swashbuckle (already a locked decision, ARCHITECTURE.md §A) serves `/swagger/v1/swagger.json`. The backend is configured to emit **OpenAPI 3.0** (not 3.1) because the Dart generators are most reliable against 3.0.
- **Client side:** **`openapi_generator` (the `openapitools`-backed Dart/Flutter package)** with the **`dio` + `built_value`** library option.
  - Chosen over `swagger_dart_code_generator` because the OpenAPI Tools generator handles polymorphism, `oneOf`/`allOf`, and nullable semantics more faithfully — and the lab-parse drafts (ARCHITECTURE.md §E JSON schema, `oneOf` on `hormone_code`) plus `problem+json` errors exercise exactly those features.
  - `dio` is chosen as the HTTP layer because we need request/response interceptors for the bearer token, 401-triggered refresh, and PII-safe logging (§4.4) — `dio`'s interceptor model is the cleanest fit.
  - `built_value` gives immutable, equatable DTOs that play well with Riverpod's value-equality-based rebuild avoidance.

### 2.2 The lockstep mechanism

The single hardest failure mode in a generated-client project is silent drift between the running backend and the committed client. We prevent it with a **pinned snapshot + CI guard**, not "regenerate whenever someone remembers."

**Where the spec lives:** `client/openapi/lumen.openapi.json` is a *committed snapshot*. It is the contract the committed Dart client was generated from. It is never edited by hand.

**How it regenerates (three triggers, in order of authority):**

1. **At the end of every backend phase that adds or changes endpoints.** This is a mandatory step in that phase's plan checklist (see §6). The phase session runs the backend, exports the live OpenAPI doc, diffs it against the committed snapshot, regenerates the Dart client, and commits both together in the same PR. The contract and its consumer move as one commit.
2. **A CI drift guard on every backend PR.** A GitHub Actions job (sibling to the existing test workflow in ARCHITECTURE.md §G) boots the API, fetches its live OpenAPI doc, and `diff`s it against `client/openapi/lumen.openapi.json`. **If they differ, the job fails** with a message: "OpenAPI changed but the committed snapshot/client was not regenerated." This makes drift impossible to merge.
3. **A `client/build.yaml` + a `melos`/script target `regen-api`** so a developer can locally reproduce step 1 deterministically: `dart run build_runner build` after dropping in a fresh spec.

**Export command (run by the phase session, against the locally-running API):**

```bash
# from a phase session, with the api container up on the compose network
curl -s http://localhost:8080/swagger/v1/swagger.json -o client/openapi/lumen.openapi.json
cd client && dart run build_runner build --delete-conflicting-outputs
```

**Versioning discipline:** the API is served under `/v1` (ARCHITECTURE.md routes are unversioned in the doc; we add an `ASSUMPTION:`-flagged `/v1` prefix to the route table when the API skeleton phase lands, so the client never has to guess at a breaking-change strategy). Breaking changes bump to `/v2` and the client keeps the old generated client until migrated.

**What the generated client does *not* own:** auth (handled by `flutter_appauth`, §4), the Hive cache wrapper, theming, and routing. Generation is purely the typed transport + DTOs.

### 2.3 Hand-off contract for fidelity

Because each fresh Claude session executes one phase, the regeneration step is written into the phase's session-kickoff prompt verbatim. A phase is not "done" until: backend endpoints green → OpenAPI snapshot updated → Dart client regenerated → client compiles → the phase's screens wired. The review checkpoint after the phase verifies the snapshot in the PR matches the live API (it re-runs the drift guard).

---

## 3. Screen → module → endpoint → backend-phase mapping

This is the scheduling backbone. The **Phase** column refers to the backend build phases (the walking-skeleton sequencing from the locked decisions, expressed against ARCHITECTURE.md §H milestones). Client work for a screen **starts only after the listed phase's endpoints are integration-tested green**.

Phase legend (walking-skeleton order; infra brought up incrementally):

- **P0** — minimal infra only (Caddy + Postgres + Keycloak + Vault), empty `api` `/health` 200.
- **P1 (walking skeleton)** — the thin vertical slice: Caddy routing → Keycloak JWT validation → Keycloak admin user creation → Vault Transit per-user DEK → envelope-encrypted Postgres write → protected `GET /me`. Exercises `POST /onboarding/start` + `GET /me`.
- **P2** — Vault crypto helper hardened (`IUserCryptoContext`, field-encrypt helpers, Testcontainers Vault round-trip). No new screens; thickens P1's spine.
- **P3** — Onboarding (remaining endpoints) + Cycle + Symptoms modules.
- **P4** — Hangfire + materialized views + deterministic inference engine (phase / confidence / missing-data).
- **P5** — Labs + LLM parse pipeline (adds MinIO + ClamAV + LLM provider).
- **P6** — Body + Activity modules.
- **P7** — Treatment module.
- **P8** — Reports / QuestPDF.
- **P9** — Notifications (FCM/APNs + nightly dispatch).
- **P10** — Admin module (no mobile screens; reference data the client reads indirectly).
- **P11** — Observability sidecar (no client work).
- **P12** — Flutter polish + full end-to-end verification pass (ARCHITECTURE.md milestone 11).

> Note on ordering vs ARCHITECTURE.md §H: §H bundles Body/Activity/Treatment implicitly and lists Reports before Notifications. The walking-skeleton refinement splits the infra-light CRUD modules (Body P6, Activity P6, Treatment P7) ahead of Reports (P8) because Reports *reads from* Cycle/Hormones/Symptoms/Treatment (ARCHITECTURE.md §C module 8 "Outbound") and should be wired last among feature modules. This is a sequencing refinement, not a contradiction.

| # | Screen | Section | Backend module (§C) | Primary endpoints (§C/§D) | Phase the endpoints land | Client wiring phase |
|---|---|---|---|---|---|---|
| 1 | welcome | Onboarding | — (static) | none | — | P1 (skeleton, no API) |
| 2 | account | Onboarding | Onboarding + Keycloak | OIDC login + `POST /onboarding/start` | P1 | P1 |
| 3 | cycle_setup | Onboarding | Onboarding | `POST /onboarding/baseline` | P3 | P3 |
| 4 | baseline | Onboarding | Onboarding | `POST /onboarding/baseline` | P3 | P3 |
| 5 | goals | Onboarding | Onboarding | `POST /onboarding/goals` | P3 | P3 |
| 6 | hormones (onb.) | Onboarding | Onboarding | `POST /onboarding/hormones` | P3 | P3 |
| 7 | notifications (onb.) | Onboarding | Onboarding | `POST /onboarding/notifications`, `POST /onboarding/complete` | P3 (stub) / P9 (real prefs) | P3 wire form, P9 wire push token |
| 8 | dashboard | Home/logging | Cycle (+ insight snapshot) | `GET /cycle/calendar`, `user_insight_snapshot` via `GET /insights/...` | P3 (calendar) + P4 (confidence ring, insight card) | P3 partial, P4 complete |
| 9 | quick_checkin | Home/logging | Symptoms | `POST /checkin/quick` | P3 | P3 |
| 10 | cycle_calendar | Home/logging | Cycle | `GET /cycle/calendar?from&to` | P3 | P3 |
| 11 | day_detail | Home/logging | Cycle | `GET /cycle/day/{date}`, `POST /cycle/day/{date}`, `POST /cycle/events` | P3 | P3 |
| 12 | symptom_form | Home/logging | Symptoms | `POST /symptoms`, `PUT /symptoms/{id}`, `DELETE /symptoms/{id}` | P3 | P3 |
| 13 | body_map | Home/logging | Symptoms | `POST /symptoms` (region enum + intensity 1–5) | P3 | P3 |
| 14 | phase_correction | Home/logging | Cycle | `POST /cycle/phase-override` | P3 (write) + P4 (shows recomputed confidence) | P3 write, P4 confidence display |
| 15 | hormone_chart (+L) | Hormones | Hormones | `GET /hormones/series?hormone&from&to` (mv_hormone_series_daily) | P4 (matview) | P4 |
| 16 | hormone_detail | Hormones | Hormones | `GET /hormones/{id}` | P4 | P4 |
| 17 | studies_library | Hormones | Hormones | `GET /labs/{id}` list, `GET /hormones/...` | P5 (labs list) | P5 |
| 18 | upload_study | Hormones (labs) | Hormones | `POST /labs` (multipart, client-side DEK encrypt) | P5 | P5 |
| 19 | ocr_confirm | Hormones (labs) | Hormones | `GET /labs/{id}/drafts`, `POST /labs/{id}/confirm` | P5 | P5 |
| 20 | missing_data | Hormones (labs) | Hormones | `GET /insights/missing-data` | P4 (engine) + P5 (lab-driven cards) | P4 base, P5 lab cards |
| 21 | confidence_explainer | Hormones | Hormones | `GET /insights/confidence` | P4 | P4 |
| 22 | body_calendar | Body/activity | Body | `GET /body/calendar` | P6 | P6 |
| 23 | body_entry | Body/activity | Body | `POST /body/entry`, `GET /body/entry/{id}` | P6 | P6 |
| 24 | activity_calendar | Body/activity | Activity | `GET /activity/calendar` | P6 | P6 |
| 25 | activity_entry | Body/activity | Activity | `POST /activity/entry` | P6 | P6 |
| 26 | medication_log | Treatment | Treatment | `GET /medications`, `POST /medications/{id}/log` | P7 | P7 |
| 27 | add_medication | Treatment | Treatment | `POST /medications`, `GET/PUT /medications/{id}/schedule` | P7 | P7 |
| 28 | insights_hub | Reports | Reports | `GET /insights/hub` (mv_insight_metrics, mv_cycle_phase_summary) | P8 (reads P4 matviews) | P8 |
| 29 | doctor_report | Reports | Reports | `POST /reports/doctor`, `GET /reports/{id}` | P8 | P8 |
| 30 | share_preview | Reports | Reports | `GET /reports/{id}/download` | P8 | P8 |
| 31 | profile | Settings | Settings | `GET /me`, `PATCH /me` | P1 (`GET /me`) / P3 (`PATCH`) | P1 read, P3 edit |
| 32 | cycle_settings | Settings | Settings | `GET/PATCH /settings/cycle` | P3 | P3 |
| 33 | hormone_prefs | Settings | Settings | `GET/PATCH /settings/hormones` | P4 | P4 |
| 34 | notifications (settings) | Settings | Settings | `GET/PATCH /settings/notifications` | P9 | P9 |
| 35 | data_export | Settings | Settings | `POST /me/export` (BuildDataExportJob) | P8/P9 (job infra) | P9 |
| 36 | privacy | Settings | Settings | static + subprocessor list (§F) | — | P1 (static) |
| 37 | help_about | Settings | Settings | static | — | P1 (static) |

**Observations that drive the plan:**

- **P1 (walking skeleton) already wires real screens:** screen 1 (welcome, static), screen 2 (account → OIDC + `POST /onboarding/start`), screen 31 (profile, `GET /me` only), screens 36/37 (static). This is deliberate — the skeleton proves the full spine *through the actual client*, not a curl. The first end-to-end demo is a real login that creates a Keycloak user, provisions a Vault DEK, writes an envelope-encrypted row, and renders `GET /me` on screen 31.
- **The two safety-critical engines gate their screens:** the deterministic inference engine (P4) gates screens 15, 16, 20, 21 and the confidence ring on screen 8; the lab-parse pipeline (P5) gates screens 17–20. These are the phases that get the *deeper* review checkpoint per the locked decision, and on the client side these are exactly the screens where the user is making clinical interpretations — they get the most rigorous widget/golden tests.
- **No client screen depends on the Admin module (P10) or Observability (P11).** Admin reference data (`ref_hormone_range`, `ref_medication`) is consumed by the client *indirectly* via the Hormones/Treatment endpoints, so it must be *seeded* (migration in P4/P7) before those screens render correctly, but there is no Admin UI in the client.

---

## 4. Online-only + Hive cache, and Keycloak OIDC mobile auth

### 4.1 The cache contract (online-only, honest about it)

Per the locked decision and ARCHITECTURE.md §A: **in-memory + Hive disk cache; reads need network; writes do NOT queue offline.** The implementation makes this explicit rather than fudging it:

- **In-memory layer = Riverpod provider state.** Already free: a `FutureProvider`/`AsyncNotifier` holds the last fetched value for the session.
- **Hive disk layer = a read-through, stale-allowed cache** keyed by endpoint + params. It exists to (a) make cold app starts paint instantly with last-known data and (b) survive process death, *not* to enable offline use.

A generic wrapper enforces the contract:

```
core/cache/cached_query.dart
  CachedQuery<T>:
    - read(): 
        1. if a fresh-enough Hive entry exists, emit it immediately (stale-while-revalidate)
        2. always attempt a network fetch
        3. on success: write-through to Hive, emit fresh value
        4. on network failure WITH a cached value: emit cached value + a "stale, offline" banner flag
        5. on network failure WITHOUT a cached value: emit a NetworkRequired failure (the screen shows the network-required empty state)
    - ttl per query (e.g. cycle calendar 5 min, hormone series 1 h, /me 1 h, static ref data 24 h)
```

- **Writes never touch the queue path.** A `POST`/`PATCH`/`DELETE` goes straight to the network. On success, the wrapper **invalidates the affected Hive keys and `ref.invalidate`s the dependent providers** so the next read re-fetches. On failure, the UI surfaces a retryable error inline (e.g. screen 12 symptom save) — it does **not** persist a pending write. This is the literal meaning of "writes do not queue."
- **Hive boxes:**
  - `box_cache` — JSON-serialized API responses keyed by `method:path:querystring`, each with `fetchedAt`. Values are the generated DTOs serialized via their `built_value` serializers (one Hive `TypeAdapter` that delegates to the built_value `Serializers`, so we don't hand-write an adapter per DTO).
  - `box_ui` — non-sensitive UI state (selected hormone chips on screen 15, last-viewed tab, theme override).
  - **No box stores tokens** (those live in secure storage, §4.3) and **no box stores decrypted health PII beyond its TTL** — cache entries for `symptoms`, `cycle_day_logs`, `body_metrics`, `labs` get short TTLs and are **purged on logout and on app background-to-locked**, matching the server's PII-minimization posture (ARCHITECTURE.md §F logging rules). Hive is opened with an encryption key (`Hive.openBox(..., encryptionCipher: HiveAesCipher(key))`) where the key is held in secure storage, so at-rest cache is encrypted on device.

### 4.2 Keycloak OIDC mobile auth — `flutter_appauth` + PKCE

- **Library: `flutter_appauth`** (AppAuth, the OIDC-certified native SDK wrapper) with the **Authorization Code flow + PKCE**. This is the locked "Keycloak OIDC (realm `lumen`)" decision realized correctly for a public mobile client: no client secret on device, PKCE protects the code exchange.
- **Discovery:** the client uses Keycloak's discovery document at `https://auth.lumen.example/realms/lumen/.well-known/openid-configuration` (Caddy proxies `/auth` per ARCHITECTURE.md §B/§G). `flutter_appauth` reads endpoints from discovery so the client never hard-codes token/authorize URLs.
- **Redirect:** a custom scheme `com.lumen.app:/oauth2redirect` registered on Android (intent-filter) and iOS (URL type), matching a Keycloak redirect URI in the realm config (`deploy/keycloak/realm-lumen.json`).
- **Scopes:** `openid profile offline_access` (the `offline_access` scope is required to receive the 30-day refresh token per ARCHITECTURE.md §F).
- **Account creation:** per ARCHITECTURE.md §C module 1, the *backend* creates the Keycloak user via the admin API during `POST /onboarding/start`. So the client flow on screen 2 is: collect credentials/registration intent → call `POST /onboarding/start` (which provisions the Keycloak user + Vault DEK) → then run the `flutter_appauth` login against Keycloak to obtain tokens. (For straight returning-user login, the client goes directly to the AppAuth flow.) This ordering is wired and proven in P1.

### 4.3 Token storage

- **`flutter_secure_storage`** — Keychain (iOS, `first_unlock_this_device` accessibility) and Keystore-backed EncryptedSharedPreferences (Android). This satisfies ARCHITECTURE.md §F "Flutter stores tokens in Keychain/Keystore."
- Stored items: `access_token`, `refresh_token`, `id_token`, `access_token_expiry`. Nothing else security-sensitive lives here.
- On logout / crypto-shred (screen 35 / `DELETE /me`): clear secure storage, purge all Hive boxes, and call the AppAuth end-session endpoint.

### 4.4 Refresh and the request pipeline

Access tokens are 15 min, refresh tokens 30 days rotated-on-use (ARCHITECTURE.md §F). Handled in a Dio interceptor so the generated client stays oblivious:

```
core/auth/auth_interceptor.dart
  onRequest:
    - if access_token within 30s of expiry -> proactively refresh (single-flight)
    - attach Authorization: Bearer <access_token>
  onError (401):
    - single-flight refresh via flutter_appauth token endpoint with refresh_token
    - on success: persist rotated tokens, retry the original request once
    - on refresh failure (invalid_grant / expired): clear tokens, purge cache,
      and the GoRouter auth guard redirects to screen 1/2 (login)
  logging:
    - a PII-safe Dio LogInterceptor mirroring the server's Serilog scrubbing:
      never log Authorization, never log bodies for labs/symptoms/cycle_day/body/me/settings
```

- **Single-flight refresh:** a `Completer`-guarded refresh ensures that a burst of 401s (common when several providers fire on a screen mount) triggers exactly one refresh, and all queued requests await it.
- **Router guard:** `go_router`'s `redirect` consults an `authStateProvider`. Unauthenticated → onboarding/login stack. Authenticated but `onboarding_completed_at` null (from `GET /me`) → resume onboarding at the right step (screens 3–7). Authenticated + onboarded → tab shell at screen 8.

---

## 5. Design-system tokens → Flutter theming (faithful reproduction of the mockups)

The mockups encode their tokens two ways (Pattern A: CSS attribute selectors in `<style>`; Pattern B: inline `--var` on the root div) but the *values* are identical and match CLAUDE.md exactly. We port the **values**, and the theme-switch mechanism becomes Flutter's `ThemeMode` + a `Theme` with light/dark `ColorScheme` + a custom `ThemeExtension` for the tokens that don't fit Material's `ColorScheme` (sage, accent-soft, surfaces, input, the muted ink).

### 5.1 Token model — a `ThemeExtension`

Material's `ColorScheme` does not have slots for "sage," "accent soft," "muted ink," or "input." So the canonical token surface is a custom `ThemeExtension<LumenColors>`, with the standard Material `ColorScheme` derived from it (so Material widgets — `TextField`, `Switch`, dialogs — also pick up the palette).

```dart
// core/theme/lumen_tokens.dart
@immutable
class LumenColors extends ThemeExtension<LumenColors> {
  final Color bg;        // --b
  final Color surface;   // --f
  final Color ink;       // --ink
  final Color muted;     // --mut
  final Color accent;    // --ac
  final Color accentSoft;// --acs
  final Color sage;      // --sg
  final Color sageSoft;  // --sgs
  final Color border;    // --bd
  final Color input;     // --in
  // copyWith + lerp implemented for smooth theme transitions
}

const lumenLight = LumenColors(
  bg:        Color(0xFFF1EFE8),
  surface:   Color(0xFFFFFCF7),
  ink:       Color(0xFF3B2A20),
  muted:     Color(0xFF8A6F5E),
  accent:    Color(0xFFC25A36),
  accentSoft:Color(0xFFF3D9CC),
  sage:      Color(0xFF7B8F6B),
  sageSoft:  Color(0xFFE4EADD),
  border:    Color(0x1F3B2A20), // rgba(59,42,32,.12) -> 0x1F alpha
  input:     Color(0xFFFAF6EF),
);

const lumenDark = LumenColors(
  bg:        Color(0xFF1A1220),
  surface:   Color(0xFF241830),
  ink:       Color(0xFFF2E4D4),
  muted:     Color(0xFFA99BB8),
  accent:    Color(0xFFE8A87C),
  accentSoft:Color(0xFF3A2438),
  sage:      Color(0xFF9BAE85),
  sageSoft:  Color(0xFF28321F),
  border:    Color(0x1FF2E4D4), // rgba(242,228,212,.12)
  input:     Color(0xFF1F1428),
);
```

### 5.2 Hormone colors — fixed, NOT theme-switched

CLAUDE.md is explicit that hormone colors are hard-coded and do not switch with theme. So they live in a plain `abstract final class`, never in the `ThemeExtension`:

```dart
// core/theme/hormone_palette.dart
abstract final class HormonePalette {
  static const estrogen     = Color(0xFFC25A36);
  static const progesterone = Color(0xFF7B8F6B);
  static const lh           = Color(0xFFD4537E);
  static const fsh          = Color(0xFF378ADD);
  static const testosterone = Color(0xFFBA7517);
  static const cortisol     = Color(0xFF7F77DD);
  static const glp1         = Color(0xFF1D9E75);

  static Color forCode(String hormoneCode) => switch (hormoneCode) {
    'estradiol' || 'estrogen' => estrogen,
    'progesterone' => progesterone,
    'lh' => lh, 'fsh' => fsh,
    'testosterone' => testosterone, 'cortisol' => cortisol,
    'glp1' => glp1,
    _ => /* fallback muted */ const Color(0xFF8A6F5E),
  };
}
```

This `forCode` switch is keyed on the **same `hormone_code` enum the LLM JSON schema uses** (ARCHITECTURE.md §E), so chart series colors on screens 15/16 map directly off the wire value with no client-side lookup table to drift.

### 5.3 Cycle-phase colors — light/dark pairs

These *do* switch with theme (CLAUDE.md lists light/dark values), so they're a small pair resolved by brightness:

```dart
// core/theme/phase_palette.dart
abstract final class PhasePalette {
  static Color menstrual(Brightness b) => b == Brightness.light ? const Color(0xFFF3D9CC) : const Color(0xFF4A1B0C);
  static Color follicular(Brightness b) => b == Brightness.light ? const Color(0xFFFAEEDA) : const Color(0xFF412402);
  static Color ovulatory(Brightness b) => b == Brightness.light ? const Color(0xFFE4EADD) : const Color(0xFF28321F);
  static Color luteal(Brightness b) => b == Brightness.light ? const Color(0xFFEEEDFE) : const Color(0xFF26215C);
}
```

Used on screens 8 (hero phase band), 10 (calendar day backgrounds), 15 (the phase rect overlays seen in the SVG).

### 5.4 Typography — two weights only, system stack

CLAUDE.md mandates exactly weights 400 and 500 and a system sans-serif stack. In Flutter:

- **No custom font.** Use the platform default (San Francisco on iOS, Roboto on Android) which matches the mockups' `-apple-system, "Segoe UI", Roboto` intent. Do not bundle a font — that would diverge from "system sans-serif stack."
- A `TextTheme` built from the mockups' observed sizes (e.g. 11px uppercase section labels `letter-spacing` ~1.5, 18–22px medium headings, 9–11px muted captions). **Only `FontWeight.w400` and `FontWeight.w500` appear** — a lint/golden test asserts no other weight is used.
- Section labels use `letterSpacing` + `text-transform: uppercase` equivalent (uppercase the string at render or via a `LumenSectionLabel` widget). Sentence case everywhere else — no `.toUpperCase()` outside section labels.

### 5.5 The phone frame and shared chrome

The mockups render inside a 300px frame with 36px radius and a top-right circular theme toggle. In the real app this frame *is* the device, so the frame border itself is dropped, but the **internal spacing, radii (cards 10–18px, chips 12px), and the toggle affordance** are reproduced. A `LumenScaffold` shared widget provides: themed background (`bg`), the 5-tab bottom nav (Home/Cycle/Hormones/Body/More per CLAUDE.md), and the theme toggle. The bottom-sheet screens (9, 20) use `showModalBottomSheet` with the `--ovl`/`rgba(0,0,0,.35)` scrim matching ARCHITECTURE.md/CLAUDE.md.

### 5.6 Fidelity enforcement — golden tests against the mockups

Visual fidelity is not left to eyeballing. In `test/theme/` we add **golden tests** per screen (or per key widget) and, in the P12 polish phase, a side-by-side review against the rendered HTML mockups (served via the existing `contact_sheet.html`). Both light and dark goldens are captured, since both themes are a hard requirement (CLAUDE.md "Both light and dark theme must be supported"). A golden mismatch fails CI. This makes "reproduce the 37 mockups faithfully" a checkable gate rather than a hope.

---

## 6. Recommendation: interleave phase-by-phase (not a parallel track)

**Recommendation: the Flutter client interleaves phase-by-phase with the backend, executed by the same plan-driven fresh sessions — NOT a separate parallel track.** With one structural exception: a small set of **client-foundation tasks** are front-loaded as their own short phase once Flutter is installed.

### 6.1 Why interleave (the core argument)

1. **It is the only ordering that respects the hard constraint.** A screen cannot be wired before its endpoints exist and are green (§3). A parallel client track would spend most of its time blocked on, or mocking, endpoints that don't exist yet — and mocks are exactly the drift risk §2 exists to eliminate. Interleaving means every client task in a phase consumes a freshly-generated, real, tested contract from the same phase.
2. **It keeps the OpenAPI lockstep cheap.** Regeneration happens once per phase, in the same PR that adds the endpoints (§2.2). A parallel track would force continuous re-syncing against a moving backend — more regenerations, more conflict, more chances to ship a stale client.
3. **It fits the walking-skeleton philosophy.** The locked sequencing is "prove the whole spine end-to-end, then thicken module by module." The spine is only *proven* if a real client logs in through Keycloak and renders `GET /me`. So P1 must include client work by definition. Each subsequent thickening (a module's endpoints) naturally carries its screens. The client is not a layer bolted on at the end — it is the demonstration that each slice works.
4. **It matches the orchestration model.** One living plan, fresh session per phase, review checkpoint after each. A phase that delivers "Cycle + Symptoms endpoints AND screens 8–14 wired" is a single coherent reviewable unit with one demoable outcome ("log a symptom on a real device, see it persist encrypted"). A parallel track would double the number of in-flight sessions touching shared artifacts (the OpenAPI snapshot, the router, the theme), increasing merge and review overhead — the opposite of what the plan-driven model optimizes for.
5. **The three safety-critical phases get coherent deep review.** The inference engine (P4) and lab pipeline (P5) are reviewed deeply on the backend *and* the screens that surface their output (15/16/20/21, 17–20) are wired in the same phase — so the deep review covers the full slice the user actually sees, not a backend in isolation that a later client phase might misrepresent.

### 6.2 The one exception: a front-loaded "client foundation" phase

There is a body of client work that has **no endpoint dependency** and would otherwise be repeated awkwardly inside P1. Carve it into a dedicated short phase, **P1c (client foundation)**, scheduled immediately after P1's backend spine is green and Flutter is installed (Flutter install is the deliberate later task noted in the environment constraints — P1c is where it happens):

- Flutter SDK install + project scaffold (§1.2 structure).
- Theming port (§5): tokens, hormone/phase palettes, typography, `LumenScaffold`, the golden-test harness — **all of this is mockup-driven and needs no backend.**
- The OpenAPI generation pipeline wiring (§2): generator config, `build.yaml`, the CI drift guard, first generation against P1's spec.
- Auth plumbing (§4): `flutter_appauth` + PKCE against the `lumen` realm, secure token storage, the Dio interceptor + single-flight refresh, the GoRouter auth guard.
- The cache wrapper (§4.1): `CachedQuery`, Hive boot, encrypted boxes.
- Wire the P1 screens: 1 (welcome), 2 (account → real OIDC + `POST /onboarding/start`), 31 (profile → `GET /me`), 36/37 (static).

After P1c, every backend feature phase (P3, P4, P5, P6, P7, P8, P9) carries its screen-wiring as the back half of the same phase, against that phase's freshly regenerated client. The final P12 polish phase verifies all 37 screens end-to-end against a seeded demo account (ARCHITECTURE.md milestone 11), including empty/error/network-required states.

### 6.3 What each phase's session-kickoff prompt must include (client side)

So that fresh sessions stay consistent, every feature phase's kickoff prompt (which already points at the plan phase + ARCHITECTURE.md + CLAUDE.md per the locked orchestration) adds these client clauses:

- "After backend endpoints are integration-tested green: export the live OpenAPI doc to `client/openapi/lumen.openapi.json`, run `build_runner`, commit spec + generated client together."
- "Wire screens [list] from CLAUDE.md inventory; reproduce tokens via `core/theme`; add light+dark golden tests; verify the network-required and error states (online-only contract)."
- "Do not hand-write any DTO the backend owns. Do not add an offline write queue."
- "Run the OpenAPI drift guard locally before opening the PR."

### 6.4 Resulting interleaved phase schedule (client column)

| Phase | Backend deliverable | Client deliverable |
|---|---|---|
| P0 | Minimal infra (Caddy/PG/Keycloak/Vault), `/health` | — |
| P1 | Walking-skeleton spine: OIDC → admin user → Vault DEK → enc write → `GET /me` | — (proven via curl/integration test) |
| **P1c** | — | **Flutter install + scaffold + theming + auth + cache + OpenAPI pipeline; wire screens 1, 2, 31, 36, 37** |
| P2 | Crypto helper hardening | — |
| P3 | Onboarding (rest) + Cycle + Symptoms | Screens 3–14, 32 |
| P4 (deep review) | Hangfire + matviews + inference engine | Screens 15, 16, 20(base), 21, 33; complete screen 8 confidence/insight; screen 14 confidence display |
| P5 (deep review) | Labs + LLM parse pipeline (+MinIO/ClamAV/LLM) | Screens 17, 18, 19, 20(lab cards) |
| P6 | Body + Activity | Screens 22–25 |
| P7 | Treatment | Screens 26, 27 |
| P8 | Reports / QuestPDF | Screens 28, 29, 30 |
| P9 (deep review of crypto-shred/export) | Notifications + data export + crypto-shred | Screens 7(push token), 34, 35 |
| P10 | Admin module (+ ref-data seeds) | — (no client UI; ref data already seeded earlier where needed) |
| P11 | Observability sidecar | — |
| P12 | — | Full-fidelity polish + end-to-end verification of all 37 screens, both themes, empty/error/network-required states |

---

## 7. Risks and mitigations specific to the client

- **OpenAPI drift** → committed snapshot + CI drift guard that fails the backend PR (§2.2). This is the single most important client-integrity control.
- **Online-only UX gaps** → because writes don't queue, every write screen (9, 11, 12, 13, 18, 19, 23, 25, 26, 27) must have a designed error/retry state; this is an explicit acceptance item in each phase and re-verified in P12. The `CachedQuery` `NetworkRequired` state gives reads a consistent empty-state path.
- **Lab upload encryption** (screen 18) → the PDF is encrypted *client-side with the user's DEK* before upload (ARCHITECTURE.md §D `labs`, §E step 3 says API encrypts; the doc has both phrasings — flag this as an `ASSUMPTION:` to resolve in P5: confirm whether DEK-encryption happens client-side or server-side. The client design supports either; if client-side, the client needs a way to obtain/use the DEK, which has key-custody implications that P5's deep review must settle).
- **Theme fidelity regressions** → golden tests in both themes, gated in CI (§5.6).
- **Token-refresh thundering herd** on screen mount → single-flight refresh in the Dio interceptor (§4.4).

---

## 8. Summary

- **State/nav:** Riverpod (code-gen) + GoRouter, feature-first layout mirroring the 10 backend modules.
- **Contract:** OpenAPI Tools generator (dio + built_value); committed spec snapshot regenerated once per feature phase in the same PR, enforced by a CI drift guard.
- **Mapping:** all 37 screens mapped to module → endpoint → backend phase; client wiring of a screen never precedes its tested endpoints (§3 table). P1 walking skeleton already wires screens 1/2/31/36/37 through the real spine.
- **Cache/auth:** online-only Hive read cache (stale-while-revalidate, no write queue, encrypted at rest, purged on logout); Keycloak OIDC via `flutter_appauth` + PKCE against realm `lumen`, tokens in Keychain/Keystore, single-flight refresh in a Dio interceptor, GoRouter auth guard.
- **Theming:** CLAUDE.md tokens ported to a `LumenColors` ThemeExtension (light/dark), hormone colors as a fixed non-themed palette keyed off the wire `hormone_code`, phase colors as light/dark pairs, two font weights on the system stack, golden tests as the fidelity gate.
- **Sequencing:** interleave phase-by-phase via the same plan-driven fresh sessions, with one front-loaded P1c "client foundation" phase (Flutter install, theming, auth, cache, OpenAPI pipeline). Not a parallel track — that would fight the no-wiring-before-endpoints constraint, multiply OpenAPI re-syncs, and break the one-phase-per-session review model.

Relevant files referenced: `C:\Proyectos\Endo\docs\ARCHITECTURE.md`, `C:\Proyectos\Endo\CLAUDE.md`, `C:\Proyectos\Endo\Screens\screen_08_dashboard.html` (Pattern A token reference), `C:\Proyectos\Endo\Screens\screen_15_hormone_chart.html` (Pattern B token reference + hormone/phase colors in the SVG).
