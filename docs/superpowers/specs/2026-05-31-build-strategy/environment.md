<!-- Companion reference to ../2026-05-31-build-strategy-design.md
     Produced by the build-strategy design workflow (2026-05-31). Faithful to docs/ARCHITECTURE.md.
     Note: this analysis predates final phase-number synthesis; phase IDs here are illustrative.
     The canonical phase numbering is in the main spec. -->

# Lumen — Environment & Prerequisites Plan (Windows 11 dev machine)

This is the Phase 0 prerequisite document. It defines what is installed, what to install and when, the tooling decisions, and a copy-paste "verify your environment" checklist a fresh session runs before starting any phase. It is faithful to `docs/ARCHITECTURE.md` (.NET 10, Caddy/Postgres/Keycloak/Vault/MinIO/ClamAV, Hangfire in-process, Swashbuckle OpenAPI, OIDC realm `lumen`, online-only Hive cache) and the walking-skeleton sequencing.

---

## 1. Inventory — what is installed today, and the backend dev loop

### 1.1 Verified present (checked on this machine)

| Tool | Required | Detected | Status |
|---|---|---|---|
| .NET SDK 10 | 10.0.x | `10.0.300` (and 9.0.314 side-by-side) | OK — build target |
| ASP.NET Core runtime 10 | 10.0.x | `Microsoft.AspNetCore.App 10.0.8` | OK |
| Docker Engine | 2x | `29.5.2`, Docker Desktop, daemon running | OK |
| Docker Compose | v2 | `v5.1.3` (Compose plugin) | OK — use `docker compose` (space), not `docker-compose` |
| Node.js | LTS | `v24.13.0` | OK (only used by the existing screen tooling; not required for backend) |
| npm | — | `11.6.2` | OK |
| Git | 2.x | `2.51.0.windows.2` | OK |
| `dotnet-ef` global tool | matched to EF major | `10.0.0` | OK — already installed |
| winget | — | `v1.28.240` | OK — preferred installer |
| Chocolatey | — | `2.6.0` | OK — fallback installer |

`.NET SDK 9.0.314` is also present. That is harmless side-by-side, but the solution must **pin .NET 10** via `global.json` so an accidental `dotnet build` never silently uses 9. Create this at the repo root in Phase 1:

```json
{
  "sdk": { "version": "10.0.300", "rollForward": "latestFeature" }
}
```

### 1.2 Missing / deliberately deferred

| Tool | Needed for | When to install |
|---|---|---|
| Flutter SDK + Dart | Flutter client | Section 2 — right before the first client session, NOT now |
| Android Studio + Android SDK + cmdline-tools | Android build/emulator, license acceptance | Section 2 — with Flutter |
| JDK (bundled with Android Studio) | Android toolchain | comes with Android Studio; `java` is currently NOT on PATH (expected) |
| `sops` + `age` | decrypting the `.env` secret file (`docs` §G) | Phase that introduces real secrets (LLM key, prod-ish config) — not for the dev-mode skeleton |
| OpenAPI→Dart generator | generating the typed client | Section 3.2 — first client session, alongside Flutter |
| `mkcert` (optional) | locally trusted TLS for Caddy | optional, Section 3.4 — Caddy's internal CA is the default |

Nothing on the backend critical path is missing. **The backend walking skeleton (Phase 0 + Phase 1) can start immediately.**

### 1.3 What the backend dev loop looks like TODAY

Two-terminal loop. No Flutter, no cloud, everything on `localhost`.

**Terminal A — infrastructure (incremental per phase):**
```powershell
# Phase 0 minimal infra only: Caddy + Postgres + Keycloak + Vault
docker compose -f deploy/docker-compose.yml up -d caddy postgres keycloak vault
docker compose -f deploy/docker-compose.yml ps
docker compose -f deploy/docker-compose.yml logs -f keycloak   # watch realm import
```
Later phases append services to the same compose file and bring up only the new ones:
- lab pipeline phase: `... up -d minio clamav`
- observability phase: the sidecar stack last.

**Terminal B — the API, hot-reload:**
```powershell
dotnet watch --project backend/src/Lumen.Api run
```
`dotnet watch` recompiles and restarts on save. The API talks to the containers over the Compose-published localhost ports.

**Migrations (when entities change):**
```powershell
dotnet ef migrations add <Name> --project backend/src/Lumen.Infrastructure --startup-project backend/src/Lumen.Api
dotnet ef database update --project backend/src/Lumen.Infrastructure --startup-project backend/src/Lumen.Api
```

**Tests (compose LiveStack — bring up the dev compose stack first; r13: the Testcontainers plan was cancelled, see plan §4):**
```powershell
docker compose -f deploy/docker-compose.yml up -d postgres vault vault-init keycloak
dotnet test backend/Lumen.slnx
```

**OpenAPI doc** is served by Swashbuckle at `https://localhost/swagger/v1/swagger.json` (via Caddy) or directly at the API's HTTP port; it is the input to the Dart generator later.

The dev loop does **not** need Flutter, MinIO, ClamAV, the LLM provider, FCM/APNs, or the observability sidecar until their respective phases. Keep the loop minimal.

---

## 2. Flutter SDK install for Windows — steps and the exact trigger

### 2.1 The trigger (do NOT do this now)

> **TRIGGER:** Install Flutter as the **first task inside the first client session** — i.e. immediately before wiring screens 1–14, which the architecture roadmap (`docs §H`, milestone 4) places **after** the backend onboarding + cycle + symptoms modules and their integration tests are green. Concretely: the first phase whose session kickoff prompt says "wire the Flutter client to the live `/onboarding/*` and `/me` endpoints." Until that kickoff fires, Flutter stays uninstalled.

Rationale: Flutter + Android Studio + SDK + emulator is a multi-GB, license-gated install that adds nothing to the backend walking skeleton or the deterministic-engine/lab phases. Installing it early only rots. The kickoff prompt for the first client phase must contain, as step 1, "Run the Flutter install from the Environment plan §2 and confirm `flutter doctor` is clean before writing any Dart."

### 2.2 Install steps (run only when the trigger fires)

Pin a specific stable Flutter version for reproducibility (do not float on `latest`). Use winget (already present) or the manual zip.

**Option A — winget (preferred):**
```powershell
winget install --id Flutter.Flutter -e --source winget
winget install --id Google.AndroidStudio -e --source winget
```

**Option B — manual zip (full control over location/version):**
```powershell
New-Item -ItemType Directory -Force C:\src | Out-Null
# Download the pinned stable SDK zip from docs.flutter.dev/release/archive, e.g.:
Invoke-WebRequest -Uri "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_<PINNED_VERSION>-stable.zip" -OutFile C:\src\flutter.zip
Expand-Archive C:\src\flutter.zip -DestinationPath C:\src
# -> C:\src\flutter\bin
```
Record the chosen version in the implementation plan and in a Flutter-side `pubspec.yaml` `environment.sdk` constraint so all client sessions match.

### 2.3 PATH

Add Flutter (and, if you use the manual Dart, its bin) to the **user** PATH so it survives reboots and new shells:
```powershell
$flutterBin = "C:\src\flutter\bin"   # or the winget install path
$userPath = [Environment]::GetEnvironmentVariable("Path","User")
if ($userPath -notlike "*$flutterBin*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$flutterBin", "User")
}
# Open a NEW terminal afterward; PATH changes do not affect the current process.
```

### 2.4 Android Studio, SDK, and license acceptance

1. Launch Android Studio once; complete the setup wizard (installs Android SDK, platform-tools, an SDK platform, build-tools).
2. Install the **Flutter** and **Dart** plugins in Android Studio (Settings → Plugins).
3. Point Flutter at the JDK that ships with Android Studio if `flutter doctor` complains:
   ```powershell
   flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
   ```
4. Accept all Android SDK licenses (interactive — answer `y`):
   ```powershell
   flutter doctor --android-licenses
   ```
5. For physical-device or release builds you may also need cmdline-tools; install via Android Studio SDK Manager (SDK Tools tab → "Android SDK Command-line Tools").

### 2.5 `flutter doctor` — the gate

```powershell
flutter --version          # confirm the pinned version
flutter doctor -v
```
The first client session may not write Dart until `flutter doctor` shows green checks for: **Flutter**, **Android toolchain** (with licenses accepted), and **Android Studio**. Windows-desktop and Chrome checks are optional for this product (the client targets Android/iOS). iOS toolchain requires macOS and is out of scope on this Windows machine — note it as a known red check, not a blocker, since iOS builds happen on a Mac/CI later.

---

## 3. Tooling decisions

### 3.1 .NET tools

| Tool | Decision | Notes |
|---|---|---|
| `dotnet-ef` (global) | **Yes — already installed (`10.0.0`)** | Migrations + DB update for Npgsql. Keep its major version aligned with the EF Core package major (10.x). Also pin `Microsoft.EntityFrameworkCore.Design` in `Lumen.Infrastructure` and prefer a **tool manifest** (`dotnet new tool-manifest` → `dotnet tool install dotnet-ef`) committed to the repo so every session uses the same version via `dotnet tool restore`, rather than relying on the global install. |
| Swashbuckle.AspNetCore | **Yes** | `docs §A` mandates "REST + OpenAPI (Swashbuckle) + generated Dart client." It produces the `swagger.json` the Dart generator consumes. Note: .NET 9/10 ship `Microsoft.AspNetCore.OpenApi` built-in, but the doc names Swashbuckle explicitly — use **Swashbuckle** as the source of truth and keep the Swagger UI for manual probing during the dev loop. Do not substitute it without amending `docs §A`. |
| `Microsoft.EntityFrameworkCore.Design` | Yes (package, not tool) | Required by `dotnet ef` at design time. |
| `dotnet format` | Yes (manifest tool) | Enforce style in CI; `docs` favors clean repo conventions. |
| `Testcontainers` (NuGet) | ~~Yes~~ **No (r13)** | Cancelled — integration tests run against the compose LiveStack locally and in CI (plan §4, 2026-07-06); the real Postgres/Vault/Keycloak come from `deploy/docker-compose.yml`. |
| `sops` + `age` | Defer | Only for the encrypted `.env` (`docs §G`). Not needed for dev-mode skeleton; install at the secrets-introducing phase via `winget install FiloSottile.age` and the sops release binary. |

### 3.2 OpenAPI → Dart client generator — choice and rationale

**Decision: use the official Dart/Flutter package `openapi_generator` (the dart-side wrapper around OpenAPI Generator), producing a `dio`-based typed client, driven from a committed config.**

Why this over alternatives:
- **`openapi_generator` / OpenAPI Generator (`dart-dio` generator):** mature, generates null-safe Dart models + a `dio` HTTP client, supports `oneOf`/enums/dates well, and integrates with `build_runner` so regeneration is a single `dart run build_runner build`. `dio` is the right HTTP layer for this product because it gives interceptors — needed for the Keycloak OIDC bearer token attach + 401-refresh flow (`docs §F`, 15-min access tokens, rotating refresh) and for the online-only cache strategy. It runs via the OpenAPI Generator JAR, but the JDK is already on the box once Android Studio is installed (Section 2), so no extra dependency.
- **Rejected `swagger_dart_code_generator`:** lighter but weaker on complex schemas (`oneOf`, discriminators) which the lab/hormone models use.
- **Rejected `chopper`/hand-written client:** defeats the "generated Dart client" decision in `docs §A`; hand-maintaining ~50 endpoints across 10 modules is error-prone.

Workflow (first client session and thereafter):
```powershell
# Backend running; export the contract
Invoke-WebRequest "https://localhost/swagger/v1/swagger.json" -OutFile client/openapi/lumen-openapi.json   # add -SkipCertificateCheck if using Caddy internal CA
# In the Flutter project, with openapi_generator configured against that file:
dart run build_runner build --delete-conflicting-outputs
```
Pin the OpenAPI Generator version in the Flutter config so regenerated clients are reproducible. The generated package lives under `client/` as a path dependency and is regenerated whenever the backend contract changes.

### 3.3 Vault — dev-mode now, closer-to-prod later

**Decision: Vault dev mode for the walking skeleton; a one-shot Transit-init script for the dev compose stack; full unseal/sops only near prod.**

- **Phase 0 / skeleton:** run `hashicorp/vault` in **dev mode** (`-dev`, `VAULT_DEV_ROOT_TOKEN_ID=root`). Dev mode is auto-unsealed and in-memory — perfect for exercising the spine (DEK provisioning, `encrypt`/`decrypt` against the Transit key). It is explicitly NOT for any persisted/real data.
  ```yaml
  # deploy/docker-compose.yml (skeleton)
  vault:
    image: hashicorp/vault
    command: server -dev -dev-root-token-id=root
    cap_add: [IPC_LOCK]
    ports: ["127.0.0.1:8200:8200"]   # localhost only, per docs §B
  ```
  A small init step enables Transit and creates the dev KEK (mirrors `lumen-prod-kek` naming with a `-dev` suffix to avoid confusion):
  ```powershell
  $env:VAULT_ADDR="http://127.0.0.1:8200"; $env:VAULT_TOKEN="root"
  vault secrets enable transit
  vault write -f transit/keys/lumen-dev-kek
  ```
  (Run via `docker compose exec vault sh -c "..."` if the `vault` CLI is not installed on the host — no host install needed for dev.)
- **Closer-to-prod (later phase):** switch to a non-dev Vault with a file/raft storage backend and document the **operator unseal procedure** (`docs §F` mandates documenting it; auto-unseal is an open question in `docs §I` — do NOT pick a mechanism here, just leave the manual unseal documented). The DEK custody model is server-held, not password-derived (`docs §A`), so background jobs unwrap via Transit regardless of dev/prod mode — the application code is identical across modes; only Vault's seal/storage changes. Keep the abstraction (`IUserCryptoContext`) unchanged.

### 3.4 Local TLS for Caddy

**Decision: rely on Caddy's built-in internal CA for local dev; do not use Let's Encrypt locally; optionally add `mkcert` only if a tool refuses Caddy's CA.**

- Production uses automatic Let's Encrypt (`docs §A`). That **cannot** work on `localhost` (no public DNS / ACME challenge), so locally use Caddy's `tls internal` (self-signed local CA, auto-trusted on first run by Caddy's `caddy trust` where possible):
  ```caddyfile
  # deploy/Caddyfile.local — used only in dev
  localhost {
    tls internal
    reverse_proxy api:8080
  }
  auth.localhost {
    tls internal
    reverse_proxy keycloak:8080
  }
  ```
  Keep the production Caddyfile (with real domains + Let's Encrypt) separate; select per environment. This satisfies the "Caddy routing" spine in the walking skeleton without public DNS.
- `curl`/PowerShell against `https://localhost` will warn on the cert. Use `-SkipCertificateCheck` (PowerShell 7) or `-k` (curl) in the verify checklist, OR install `mkcert` for a fully trusted local cert if a client (e.g. the Dart generator fetch, or the Flutter emulator) refuses the internal CA:
  ```powershell
  winget install --id FiloSottile.mkcert -e   # optional
  mkcert -install
  mkcert localhost
  ```
  Treat `mkcert` as optional polish, not a Phase 0 requirement.

### 3.5 Keycloak realm import locally

**Decision: import `deploy/keycloak/realm-lumen.json` at container start via `--import-realm`, Postgres-backed, admin bound to localhost.**

`docs §B/§G` specify Keycloak start mode, Postgres backing, realm `lumen`, realm import from `deploy/keycloak/realm-lumen.json`, and admin console bound to localhost. Local compose service:
```yaml
keycloak:
  image: quay.io/keycloak/keycloak
  command: start-dev --import-realm        # start-dev locally; "start" with hostname config in prod
  environment:
    KC_DB: postgres
    KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
    KC_DB_USERNAME: keycloak
    KC_DB_PASSWORD: keycloak
    KC_BOOTSTRAP_ADMIN_USERNAME: admin
    KC_BOOTSTRAP_ADMIN_PASSWORD: admin
  volumes:
    - ./deploy/keycloak:/opt/keycloak/data/import:ro
  ports:
    - "127.0.0.1:8080:8080"   # admin/localhost only, per docs §B
```
Notes for the realm file (authored in Phase 0): realm `lumen`, a confidential or public client for the Flutter app (PKCE, OIDC), the `lumen-admin` realm role (`docs §F` gates `/admin`), TOTP/MFA capability flagged, 15-min access / 30-day rotating refresh token lifetimes (`docs §F`). Re-import is idempotent at start; to force a refresh during dev, recreate the container. The walking-skeleton slice must prove **Keycloak admin user creation** from the API (`POST /onboarding/start` → admin REST), so the realm file must also define a service account / admin client the API uses for user provisioning.

---

## 4. "Verify your environment" checklist — commands a fresh session runs

Run this block at the **start of every phase**, before touching code. It is fast, read-only, and fails loud. PowerShell syntax (the project shell).

```powershell
# --- A. Core toolchain (all phases) ---
dotnet --version                         # expect 10.0.x  -> .NET 10
dotnet --list-sdks                        # expect a 10.0.x entry present
Test-Path .\global.json                   # expect True once Phase 1 pins the SDK
git --version                             # expect 2.x
docker version --format '{{.Server.Version}}'   # daemon must respond (Docker Desktop running)

# --- B. EF tooling (any phase that touches the DB) ---
dotnet ef --version                       # expect 10.0.x ; or: dotnet tool restore ; dotnet tool list
# If using a committed tool manifest:
# dotnet tool restore

# --- C. Dev infra reachable (phase-dependent: bring up only what the phase needs) ---
docker compose -f deploy/docker-compose.yml ps      # services for this phase show "running/healthy"
# Postgres:
docker compose -f deploy/docker-compose.yml exec -T postgres pg_isready -U postgres   # expect "accepting connections"
# Keycloak realm (skeleton onward):
Invoke-RestMethod "http://localhost:8080/realms/lumen/.well-known/openid-configuration" | Select-Object issuer
# Vault transit key (skeleton onward):
docker compose -f deploy/docker-compose.yml exec -T vault sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault read transit/keys/lumen-dev-kek'

# --- D. API health through Caddy (after Phase 0 brings up the empty api) ---
Invoke-RestMethod -SkipCertificateCheck "https://localhost/health"     # expect 200 / healthy
# OpenAPI contract present (Phase 1 onward):
Invoke-WebRequest -SkipCertificateCheck "https://localhost/swagger/v1/swagger.json" | Select-Object StatusCode

# --- E. Lab-pipeline phase only ---
docker compose -f deploy/docker-compose.yml exec -T clamav sh -lc 'clamdscan --version'
# MinIO buckets exist (lab-uploads, reports, avatars, exports, backups)

# --- F. FIRST CLIENT SESSION ONLY (after the Flutter trigger fires) ---
flutter --version                         # expect the pinned stable version
flutter doctor -v                         # Flutter + Android toolchain + Android Studio = green; licenses accepted
dart --version
# Dart client regenerates cleanly:
# dart run build_runner build --delete-conflicting-outputs
```

**Pass criteria by phase:**
- **Any phase:** A (core) + B (if DB involved) green.
- **Phase 0 (skeleton infra):** A + C (postgres, keycloak, vault) + D (`/health`) green. No MinIO/ClamAV/Flutter expected.
- **Lab phase:** add E green.
- **First client phase:** add F green — and this is the only phase where a red `flutter doctor` blocks work.
- **Observability phase:** sidecar stack reachable (added last per `docs §H`).

**If something is red:** do not improvise installs mid-phase. Stop, fix the prerequisite (re-run the relevant Section 2/3 install step), re-run the checklist, then proceed. The only tool expected to be absent before the client phase is Flutter/Dart/Java — that is by design, not a failure.

---

## Relevant file paths
- `C:\Proyectos\Endo\docs\ARCHITECTURE.md` — source of truth (read; this plan is faithful to §A/§B/§F/§G/§H/§I).
- `C:\Proyectos\Endo\CLAUDE.md` — product/design context.
- `C:\Proyectos\Endo\deploy\` — currently holds only `architecture.drawio`; Phase 0 adds `docker-compose.yml`, `Caddyfile` / `Caddyfile.local`, `keycloak/realm-lumen.json`, Postgres init SQL here.
- `C:\Proyectos\Endo\global.json` — to be created in Phase 1 to pin .NET 10 (currently absent; SDK 9.0.314 also installed, so the pin matters).
- `C:\Proyectos\Endo\backend\` — to be created (solution + `Lumen.Api`/`Application`/`Domain`/`Infrastructure`).
- `C:\Proyectos\Endo\client\` — to be created at the first client phase (Flutter app + generated OpenAPI Dart client).

## Key facts established
- Installed and ready: .NET SDK **10.0.300** (and 9.0.314 side-by-side — pin via `global.json`), ASP.NET Core 10.0.8, Docker **29.5.2** + Compose **v5.1.3** (daemon running), Node v24.13.0, Git 2.51, `dotnet-ef` **10.0.0** global, winget 1.28 + choco 2.6.
- Missing by design: Flutter, Dart, Java/JDK, Android Studio/SDK, sops/age, mkcert.
- Use `docker compose` (plugin), not `docker-compose`.
- Flutter trigger: install only at the start of the first client session (after backend milestone-4 onboarding/cycle/symptoms are green), never before.
