# P4b — the manual on-device walkthrough (R-06 (ii))

**Who runs this:** a human, at **T25** (phase close). **Not** an implementer, and **not** CI.
**Where the result goes:** pasted into the P4b **STATUS** block in `docs/superpowers/plans/lumen-build.md`,
matching the P3b-T10 / P3c precedent.
**Written at:** P4b-T24, alongside `client/test/flows/` — the other half of R-06.

---

## 0. Why this exists, and what it is allowed to prove

R-06 amended this phase's `integration_test green` exit criterion. `client/integration_test/` holds only a
`.gitkeep`, there is no `integration_test` dev dependency, CI is `ubuntu-latest` with no emulator and no
compose stack, and **Keycloak's login runs in a Chrome Custom Tab that was believed not automatable** —
disproved 2026-08-25: it is drivable with `adb shell input tap` / `input text` (§3.1, twice). The amendment
replaced that criterion with two things:

- **(i)** `client/test/flows/` — four multi-screen widget tests over a faked `LumenApiApi`, running in CI on
  every push. They mount `LumenRootScope` (the widget `main()` builds) with the real provider graph, real
  controllers, real repositories and the real cache policy, and assert **what reached the wire**.
- **(ii)** this walk — **one recorded pass on a real device against the live dev stack.**

So this document must cover **exactly what (i) cannot**, and nothing else. Re-checking here what a flow test
already asserts wastes the one expensive resource this phase has (a human, a device and a running stack) and
produces a record nobody can act on.

**What only this walk can establish:**

| # | Fact | Why no CI test can reach it |
|---|---|---|
| 1 | **The login leg works end to end** — register/sign-in through Keycloak's Custom Tab, tokens stored, `GET /me` authorised. | The Custom Tab is a system browser surface; `flutter_appauth` cannot be driven from a widget test, and CI has no Keycloak. |
| 2 | **The real serializers round-trip.** | Every flow test fakes at `LumenApiApi`, **above** `built_value` and Dio — no serializer runs. A field the generated client cannot encode is invisible to the whole suite. |
| 3 | **The real cache is an encrypted Hive box on disk.** | Flow tests substitute an in-memory store: same policy, no Hive, no secure-storage key, no disk. |
| 4 | **Real network conditions** — latency, a dropped connection mid-write, a genuinely slow read. | Fakes answer in a microtask. Every "in flight" state in CI is synthetic. |
| 5 | **The screens as pixels on a real panel**, in both themes, at the device's own text scale. | Goldens are 390×844 with text blocked out, on one host. |
| 6 | **The app survives backgrounding, rotation and a cold restart** with a stored session. | No lifecycle events in a widget test. |

Anything you observe that (i) *could* have caught is a **finding about the suite**, not about the app — write
it down, because it means a flow test is missing or wrong.

---

## 0.1 The shell every command below assumes

**Windows PowerShell 5.1** (`$PSVersionTable.PSVersion` measured here: **5.1.26100.9168**) — the shell
`CLAUDE.md` names as this project's primary. Every command in this document has been checked against it,
because a pre-flight step that dies on a parameter-binding error tells you nothing about whether the stack
is healthy. Three 5.1 rules shape what you will read below, and each has already broken a line here:

| 5.1 rule | what it means for this walk |
|---|---|
| **`\` is not a line continuation.** PowerShell's continuation character is a backtick. | Every command below is written on ONE line. If you copy a wrapped command out of some other document, join it first. |
| **`Invoke-RestMethod` has no `-SkipCertificateCheck`.** It arrived in PowerShell **6**; on 5.1 the line dies with a parameter-binding error before any request is made. | Nothing here probes an HTTPS endpoint. The API is published directly on `127.0.0.1:8085` (`docker-compose.yml`), which is also the port the app itself talks to — so the plain-HTTP probe is both the working one and the more faithful one. |
| **There is no inline `VAR=value cmd` prefix.** | Set `$env:PUB_CACHE` as its own statement before `flutter`. |

If you are running this from bash or WSL instead, the docker lines are unchanged and the two
`Invoke-RestMethod` lines become `curl`.

---

## 1. Before you touch the app — two traps that will cost you an hour each

Both have already happened on this project. Neither announces itself; both look like a P4b bug.

### Trap A — **use a freshly created account. Do not reuse one.**

**14 `user_keys` rows in the local dev DB are permanently undecryptable after the T20 incident.** Their
wrapped DEKs were encrypted under a KEK that no longer exists, so every read of their encrypted profile
fails server-side. If one of those accounts is a `@lumen.test` address and you sign in with it, **`GET /me`
fails and the app holds you on the splash's retry surface** — a failure with nothing whatsoever to do with
P4b, on the very first screen of the walk.

> **Rule: register a NEW account in step 3 of this walk, with an address you have not used before.** Do not
> sign in with a remembered one, and do not "just check whether the old one still works" — that check is how
> the hour goes.

### Trap B — **probe Vault before you trust `docker compose ps`.**

Vault runs in **dev mode** (`hashicorp/vault:1.18`, `-dev`), which is **in-memory**. A recreated container
comes back **healthy with no Transit engine and no key** — `docker compose ps` reports `running`, the
container answers, and every write that needs a DEK fails. The `vault-init` service that enables Transit is
`restart: "no"`, so it does not re-run by itself.

Probe it, and read the output rather than the exit code:

```powershell
docker compose -f deploy/docker-compose.yml exec -T vault sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault read transit/keys/lumen-dev-kek'
```

One line, deliberately: a `\` at the end of the first line is a line continuation in bash and **not** in
PowerShell 5.1, where it would run `... exec -T vault \` and fail on a container argument you never meant to
pass. The single quotes survive PowerShell unchanged, so the inner `VAR=value` prefixes reach `sh` intact.

- **Expected:** a key description with `latest_version 1` (or higher).
- **If it says the key does not exist**, recover before going further:

```powershell
docker compose -f deploy/docker-compose.yml up vault-init
```

then probe again. **Do not start the walk on an un-probed Vault.**

---

### Trap C — **`/health` cannot tell a healthy stack from a healthy STALE one.**

**Found the hard way on 2026-08-25**, during the first real run of this walk. Every pre-flight probe in §2
passed — `docker compose ps` healthy, `pg_isready` accepting, Keycloak's issuer resolving, and
`/health` returning `status : healthy`. Registration worked, Keycloak signed the account in, the Custom Tab
closed, the app resumed… and dead-ended on **"The requested resource was not found."**

The cause: **the running `api` container had been built on 2026-06-14** — P3a-era, predating the entire P4a
backend — and had been up for 13 hours reporting healthy the whole time. `GET /onboarding/state` returned
**404**, and the API log said why:

```
Request reached the end of the middleware pipeline without being handled by application code.
Request path: GET http://10.0.2.2:8085/onboarding/state, Response status code: 404
```

That is a **routing** 404, not a data one. The endpoint is mapped at `OnboardingEndpoints.cs:210`; it simply
did not exist in that image. **`/health` is served by `Program.cs` and answers identically on every build
ever made**, so it proves the container is *running* and proves nothing about *what is in it*.

**Probe the ROUTES, not the health check.** Add this to §2 and read every line:

```powershell
'/onboarding/state','/symptoms','/settings/cycle','/cycle/calendar','/me' | ForEach-Object {
  $c = try { (Invoke-WebRequest "http://localhost:8085$_" -UseBasicParsing).StatusCode }
       catch { $_.Exception.Response.StatusCode.value__ }
  '{0,-22} -> {1}' -f $_, $c
}
```

**Every line must print `401`** — mapped, and refusing you because you are not authenticated. **A `404`
means that endpoint is not in the running build** and the walk will fail somewhere downstream, usually in a
way that looks like an app bug. Recovery:

```powershell
docker compose -f deploy/docker-compose.yml up -d --build api
```

**Why this is worth its own trap.** No test in the repo can catch it. The `test/flows/` suite fakes at
`LumenApiApi`, so it never learns whether an endpoint is *mapped*; the backend integration tests exercise
the API **in-process**, not the container. Only a real client against a real container finds it — which is
the entire argument for this walk existing.

---

### Known defect D2 — **the app signs you out if it goes offline more than ~15 minutes after its last login/refresh.**

**Found by the 2026-08-25 walk (§3.2 D2), reproduced twice, open until fixed.** The realm's access token lives
900 s; a token refresh that fails on *transport* (airplane mode, a dead Wi-Fi) is treated as a revoked session,
the token store and the on-disk cache are purged, and you are on the welcome screen. It fires on the app's own
requests, with no tap. **For this walk:** run step 9 within ~14 minutes of a login, or sign in again first;
if you find yourself on welcome mid-step-9, that is D2, not a new finding — record it and re-login.

---

## 2. Bring the stack up and prove it is answering

Run each command and **read its output** — an exit code of 0 is not the assertion here.

```powershell
docker compose -f deploy/docker-compose.yml up -d
docker compose -f deploy/docker-compose.yml ps                    # every service running/healthy
docker compose -f deploy/docker-compose.yml exec -T postgres pg_isready -U postgres
```

```powershell
Invoke-RestMethod "http://localhost:8080/realms/lumen/.well-known/openid-configuration" | Select-Object issuer
Invoke-RestMethod "http://localhost:8085/health"
```

- The first prints the realm's `issuer`. If it errors, Keycloak is not up and **step 3 cannot run**.
- The second must print `status : healthy` — that is `Program.cs`'s `/health`, returning
  `{ "status": "healthy" }`.

**Why `8085` and not `https://localhost`.** Compose publishes the API directly on `127.0.0.1:8085`
(`docker-compose.yml`: `"127.0.0.1:8085:8080"`), and that is the port the app itself is built against —
the `--dart-define` default is `10.0.2.2:8085`, which is the same publication seen from the emulator. So
this probe answers the question the walk actually has ("can the app's API be reached?") rather than Caddy's,
and it needs no TLS bypass — which matters, because `Invoke-RestMethod -SkipCertificateCheck` **does not
exist in Windows PowerShell 5.1** and would fail here before sending anything. Caddy's `https://localhost`
is worth a look only if you are debugging Caddy; nothing else in this walk goes through it.

…and Trap B's Vault probe, which is part of this list and not optional.

**Build and install the app.** From `client` — `$env:PUB_CACHE` is its own statement, because PowerShell has
no inline `VAR=value cmd` prefix:

```powershell
$env:PUB_CACHE = 'C:\pub_cache'
Set-Location C:\Proyectos\Endo\client
flutter devices                                    # find the id you want to run on
flutter run -d <device-id>
```

- **Android emulator:** the two `--dart-define` defaults already target it (`10.0.2.2:8085` /
  `10.0.2.2:8080`) — pass nothing at all.
- **Real device:** `10.0.2.2` is an emulator-only alias, so both defines must be overridden with the host's
  **LAN IP**. Find it with `Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike
  '127.*' }` (or `ipconfig`), then, on ONE line:

```powershell
flutter run -d <device-id> --dart-define=LUMEN_API_BASE=http://<lan-ip>:8085 --dart-define=LUMEN_OIDC_ISSUER=http://<lan-ip>:8080/realms/lumen
```

  The device must be on the same network as the host, and Windows Firewall must allow inbound 8085/8080 —
  a device that cannot reach either port looks exactly like a broken app on step 1.

**Record:** the device (model + OS version), whether it is an emulator or physical, the two `--dart-define`
values you used, and the commit SHA you built from.

---

## 3. The walk

Nine steps. Each names **what to do**, **what to observe**, and **what counts as a failure**. Observe *all* of
what a step lists before moving on — half of these facts disappear the moment you navigate away.

### Step 1 — Cold start, signed out

**Do:** launch the app on a device with **no stored session**. If this device has run Lumen before, clear it
first — the session lives in `FlutterSecureStorage`, which survives a reinstall-over on some Android
versions, so prefer clearing app data outright:

```powershell
adb shell pm clear com.lumen.lumen      # or: Settings > Apps > Lumen > Storage > Clear data
```

(`adb shell pm list packages | Select-String lumen` if you are unsure of the id.) Signing out from inside the
app is **not** equivalent — this step is about what a first-ever launch does.

**Observe:** the splash appears and gives way to the **welcome** screen. It does **not** sit spinning, and it
does **not** flash the dashboard.

**Failure:** a spinner that never resolves; any authenticated screen; a crash.

---

### Step 2 — The theme, on a real panel

**Do:** flip the device to dark mode and back, on this screen.

**Observe:** both themes render with the Lumen palette — warm sand in light, deep plum in dark. No white
flash, no black-on-black text, no Material default blue anywhere.

**Failure:** any control that becomes unreadable in one theme; a colour that belongs to neither palette.

---

### Step 3 — Register a NEW account (Trap A)

**Do:** tap through to the account screen and **register a fresh account** — an email address you have never
used on this stack.

**Observe:**
- the Chrome **Custom Tab** opens on Keycloak's own page (this is the leg CI cannot automate);
- after registering, the tab closes and the app resumes **by itself**;
- you land in **onboarding**, on **step 3 of 7 · Cycle** — not on the dashboard, and not back on welcome.

**Failure:** the Custom Tab does not open, or closes without returning to the app; the app lands anywhere
other than onboarding; `GET /me` errors. **If you see the splash's retry surface here, it is Trap A or Trap C, and they look identical from the app.** Tell them apart from the API log, not the screen: `docker compose -f deploy/docker-compose.yml logs api --tail 40`. A **200 on `/me` followed by a 404 on `/onboarding/state`** is **Trap C** (stale build) — that exact pair is what the 2026-08-25 run hit. A **failing `/me`** is Trap A (reused account).

**Record:** the account address you created. T25's STATUS entry needs it so a later session does not reuse it.

---

### Step 4 — Onboarding, all the way through

**Do:** complete every step, in order: pick a last-period date on **screen 3**; answer or skip **screen 4**;
choose goals on **screen 5** that are **not** the two pre-selected ones; change the charted set on **screen 6**;
finish on **screen 7**.

**Observe at each step:**
- the eyebrow counts correctly (`Step N of 7`) and the dots track it;
- **the back chevron returns you to the previous step with your own answers still on it** — walk back from
  step 5 to step 4 and forward again at least once, and check that what you chose is what you see;
- pressing Continue on a step you have already answered does **not** revert anything.

**Failure:** any step that comes back showing the *pre-save* values (this is the T8b data-loss shape — a full
replace step will then write those values back over what the server stored). Note precisely **which** step and
**what** it showed.

---

### Step 5 — Out the other side

**Do:** finish onboarding.

**Observe:** you land on the **dashboard** immediately, without a second sign-in, without a visible reload,
and without bouncing back into the flow.

**Failure:** being returned to onboarding; a spinner longer than a second or so; the greeting showing a raw
`null`.

---

### Step 6 — Quick check-in, and the screen behind it

**Do:** on the dashboard, tap the **Mood** quick-log tile. Set a pain value of **0** (zero is a real answer,
not "not recorded") and a mood. Save.

**Observe:**
- the sheet closes;
- the **dashboard behind it now shows what you entered** — "Pain today · 0 / 10", the mood word — and no
  longer says "Not logged today";
- opening the sheet again shows an **empty** form, not your previous answer.

**Failure:** the card still says "Not logged today", or shows a different number from the one you entered.
That is the refresh seam, and it is exactly what a user would see as "my check-in did not save".

---

### Step 7 — Log a symptom, and check the day view

**Do:** from the dashboard, tap the **Symptom** quick-log tile. Choose a location, a pain level, a pain type,
one related symptom **with** its own intensity, and type a note. Save.

Then go to the **Cycle** tab, open **today**, and look.

**Observe:**
- saving returns you to the **dashboard** with the bottom nav still there;
- **today's day view lists the symptom you logged** — its region/type chips and its intensity, plus the
  related symptom with its own intensity. **The day view does not render a symptom's own note; that is by
  design** (`day_detail_screen.dart`'s chips come from region/painTypes/triggers *"ONLY — never a symptom's
  own `notes`"*), so verify the note **through the API** (`GET /symptoms?from=…&to=…` — `notes` sits on the
  batch's **first** entry, `symptom_batch_assembler.dart`), not on screen. Do not be misled by the day view's
  own NOTE card: that is the **day-log** note from "Edit pain, mood and note" (`POST /cycle/day`), a
  different field. *(Corrected 2026-08-25 — the earlier wording "with the note" described a surface that
  never existed.)*
- the calendar cell for today carries its symptom marker.

**Failure:** the form stays on screen after a successful save (**tap Save exactly once and stop** — this
screen has previously shipped in a state where a second tap posted the batch again, and there is no delete);
the day view shows nothing; the API shows the note on the wrong row.

---

### Step 8 — Pause and resume, twice

**Do:** **More → Cycle settings**. Choose a pause reason and **Pause tracking**. Then **Resume tracking**.
Then pause again **with a different reason**, and resume again.

**Observe:**
- while unpaused with no reason chosen, the Pause control is **disabled** and says why;
- pausing flips the card to **Paused** and shows the reason as a read-only row;
- **resume is always available** — including from `Pregnancy` — with no confirmation and no second question;
- **the second pause, with a different reason, succeeds.** This is the one that matters: the server keeps the
  previous reason on the row after a resume, so this request is the one that would be rejected if the client
  echoed it back.
- leaving the screen returns you to **Profile**, still inside the More tab, nav bar intact.

**Failure:** the second pause fails with a validation error (that is the echo defect, live); resume being
gated on anything; the card claiming Paused when the request failed.

---

### Step 9 — Offline, backgrounding and a cold restart

**Do, in this order:**
1. Turn the device's network **off**. Open the Cycle tab and the dashboard.
2. With the network still off, try a quick check-in and **save**.
3. Turn the network back **on** and use the retry control on screen.
4. Background the app, wait ten seconds, return to it.
5. Force-quit and cold-start it.

**Observe:**
1. Every read screen shows its **designed** offline/error state with a retry control — **not an endless
   spinner**, and not a blank screen.
2. The write fails with a **visible message**, the sheet **stays open**, and **your answer is still on it**.
3. The retry succeeds and the value appears.
4. The app returns to the screen you left, with its state.
5. The cold start lands you **straight on the dashboard** — the stored session is used, and you are not asked
   to sign in again.

**Failure:** any spinner that outlives the failure (this is the shape P4b-T26 removed — a read failure used to
spin for ~38 seconds behind ten silent retries); a lost answer after a failed write; being signed out by a
restart.

---

## 3.1 Walk log — 2026-08-25 (COMPLETE, steps 1–9)

**Run by:** the E2E session — adb-driven, every step observed from screenshots, the API container log and
API read-backs — on the `lumen` AVD, against `HEAD 330dd4c` (docs-only over `0313271`; client/backend source
unchanged since `be7b3d4` / `b6fc4b0`, both 2026-08-24). 16:28–16:57 local (UTC−6), plus a 17:06 re-run
of D2. **The findings below were adversarially reviewed by nine independent agents (code path, evidence
and timeline, severity/fix-shape, suite claims, completeness) before being written here**; every citation
was re-verified at HEAD.

**Environment:** `emulator-5554` (AVD `lumen`, `sdk_gphone64_x86_64`, Android 15 / API 35, 1080×2400,
device timezone `America/Mexico_City`, device locale en-US; Chrome 124.0.6367.219 provides the Custom Tab); `com.lumen.lumen` 1.0.0 debug, installed 16:10
from branch source; `--dart-define` values: the defaults, `LUMEN_API_BASE=http://10.0.2.2:8085` and
`LUMEN_OIDC_ISSUER=http://10.0.2.2:8080/realms/lumen`; `lumen-api:latest` built 16:15 the same day.
**Run windows:** 16:28–16:57 (steps 1–9), 17:06:45–17:07:07 (D2 re-run, §3.5), 17:13–17:17 (dark pass, §3.6).
**Pre-flight at 16:28 (22:28 UTC), pasted, not paraphrased:**

```
/onboarding/state      -> 401        # Trap C — every line 401 = mapped and refusing an anonymous caller
/symptoms              -> 401
/settings/cycle        -> 401
/cycle/calendar        -> 401
/me                    -> 401
latest_version            1          # Trap B — vault read transit/keys/lumen-dev-kek (filtered to these two keys)
name                      lumen-dev-kek
http://localhost:8080/realms/lumen   # issuer
{"status":"healthy"}                 # /health
/var/run/postgresql:5432 - accepting connections
```

**Account created: `p4bwalk08251630@example.com`** (display name Valentina, password `WalkP4b-2026!`,
userId `557030dd-a3a7-42ff-a014-cface4149d3b`). **Do not reuse it** (Trap A) — nor
`p4bwalk08251612@example.com` (Carolina) from the 16:12 run. That earlier run (steps 1–4 only) is
**superseded by this log**; the one thing it found that this log does not repeat — the stale `api`
container — lives on as Trap C in §1. Stored state was read back after every write through the API
(password grant on the confidential `api` client, exactly as `TestFixtures.GetUserTokenAsync` does), so each
PASS below is pixels **and** rows; the bodies are archived in `p4b-walk-evidence/api-readbacks.md`, and the
extra `GET`s in the container log 6–7 s after each write are those probes, not the app.

| Step | Result | Evidence |
|---|---|---|
| **1 — Cold start, signed out** | **PASS** | `pm clear` → launch: Android's system splash (2 s) → **welcome** (fully drawn at +4.6 s per logcat; captured at 6 s). No hanging spinner, no dashboard flash, no crash. *Cosmetic:* the system splash is Flutter's template logo on white — the launcher icon is not Lumen-branded (O1). |
| **2 — Theme on a real panel** | **PASS** | `cmd uimode night yes/no` on welcome: dark = deep plum-black ground, cream ink, moonlit-gold Begin, sage eyebrow; light = warm sand. No Material blue, no black-on-black, no white flash. A second dark pass over the live dashboard, calendar, day view, profile and cycle settings is recorded in §3.6. |
| **3 — Register a NEW account** | **PASS, two observations** | Begin → screen 2 → `POST /onboarding/start 200`. The Custom Tab opened on Keycloak's own page (`CustomTabActivity` top-resumed) — **pre-filled with the PREVIOUS walk's account and "Please re-authenticate to continue"**, because Chrome's Keycloak SSO cookie survives `pm clear` and the app sends `prompt=login` with no `login_hint` (O2). Keycloak's ↻ restart gave a clean form; after sign-in the tab **closed by itself** and `MainActivity` resumed within 2 s, landing on **Step 3 of 7 · Cycle**. The API log shows the Trap C pair both 200 — `GET /me` then `GET /onboarding/state` — plus `/settings/cycle` and `/cycle/calendar` prefetched (O3). **`/me` read back `locale es-ES, timezone Europe/Madrid`** (archived; also visible on screen 31 later) **on a device in `America/Mexico_City` — finding D1, first seen here.** |
| **4 — Onboarding, all the way through** | **PASS** | Screen 3: 12 Aug, both defaults changed (28→**26**, Somewhat→**Regular**) → API `lastPeriodStart 2026-08-12, avgCycleLengthDays 26, regularity regular`. Screen 4: DOB via the Material picker (14 Aug 1996), 165 cm, 60 kg, Diagnosed → API `dob 1996-08-14, heightCm 165, latestWeightKg 60.0, endoStatus diagnosed`. Screen 5: **both pre-selected goals deselected**, *Prepare for appointments* + *Just curious* chosen → API exactly that. **Chevron 5→4:** DOB `14/8/1996`, 165, `60,0`, Diagnosed all present; **forward 4→5→6:** goals as chosen (the re-entry captures are byte-identical to the pre-save ones). Continue on the **unchanged** step 4 issued no write (`GET /me` only); Continue on step 5 re-posted the identical set; the server changed nothing either way (O5). Eyebrow `Step N of 7` and dots correct on every step; screen 3 has no chevron, 4–7 do; future dates greyed; Continue disabled until a date. Screen 6: Cortisol + GLP-1 off → API `charted false` for both. Screen 7: Period prediction on; **Allow & finish** → `POST /onboarding/notifications 200` → `POST /onboarding/complete 200`. No pre-save value anywhere — the T8b shape is absent. |
| **5 — Out the other side** | **PASS (with D1 visible)** | At 1 s screen 7 still showed its button in the in-flight spinner state (both POSTs in flight); the dashboard was drawn between 1 and 2.5 s (`GET /me` → `GET /cycle/calendar ×2` at 22:39:17–18) — inside the script's "a second or so"; no second sign-in, no reload, no bounce into the flow; greeting "Good afternoon, Valentina" (no raw null); the phase card shows the designed "Cycle phases aren't available yet" state. **But the header date read "Wednesday, August 26" on a device showing Tuesday 25 August, 16:39** — the server's `today` is `2026-08-26` in `Europe/Madrid`. The app is internally consistent (client "today" comes from the server by design, D-12); the *stored timezone* is wrong. See D1. |
| **6 — Quick check-in** | **PASS** | Mood tile → sheet (Save disabled until a choice). Pain **0** + Steady → Save: `POST /checkin/quick 200` then one `GET /cycle/calendar`; **the sheet closed and the dashboard read "Pain today 0 / 10" and "Steady" within 0.7 s** — no "Not logged today". Re-opened sheet: empty form, Save disabled. API: `/cycle/day/2026-08-26` = `pain 0, mood 3` (zero stored as a real answer); `/cycle/day/2026-08-25` = `log null` — filed under the Madrid day (D1 again). |
| **7 — Log a symptom, check the day view** | **PASS — and the script's old "with the note" was wrong** | Symptom tile → screen 12. Pain 6, Pelvis, Cramping, Nausea (Save correctly blocked with *"set an intensity for every selected symptom"* until Nausea = 4), a 22-character note. **One tap on Save → exactly one `POST /symptoms 201`** (a two-item batch: pain/pelvis/cramping/6 with the note, nausea/4; both `occurredOn 2026-08-26`), back on the **dashboard with the bottom nav**. Cycle tab: **26 outlined as today with a marker**, 12 marked (the onboarding period start). Day view 26: **Pain 6/10 · Pelvis · Cramping, Nausea 4/10**, plus Pain & mood 0/10 · Steady (`GET /cycle/day/{date}` + `GET /symptoms`). The note is on the **pain** row (`cf9c999f…`, `notes: "E2E walk note 08251630"`) and `null` on the nausea row — the right row — and, by design, not on the day view (script corrected above; O6). |
| **8 — Pause and resume, twice** | **PASS** | More → Profile & health (its read-only rows show `es-ES` / `Europe/Madrid` — D1 on the panel) → Cycle settings, which round-trips onboarding's **26 days / Regular**. With no reason: Pause **disabled** with *"Choose a reason to pause."* **Pregnancy → Pause** → `PATCH 200` → card **Paused**, *Reason: Pregnancy* read-only, **Resume available with no confirmation**. **Resume** → `PATCH 200` → `trackingPaused false` while the server **keeps `pauseReason "pregnancy"`** — the exact state the echo defect needs. **Hormonal suppression → Pause → `PATCH 200`, `pauseReason hormonal_suppression`** — the second pause with a different reason **succeeded; the echo defect is not live.** Resume → `PATCH 200`. Chevron → **Profile & health, still in the More tab, nav bar intact.** Four PATCHes, four 200s; no client re-GET after a PATCH (the response is adopted — the `GET /settings/cycle` 6–7 s after each one in the container log is the read-back probe). After a resume the previously-used reason chip stays **selected** and Pause is already enabled (O7). |
| **9 — Offline, backgrounding, cold restart** | **FIRST ATTEMPT FAIL (D2) → second attempt PASS 9.1–9.5** | **First attempt (16:47):** airplane mode on. The Cycle tab came back on its still-mounted day view (the shell is an `indexedStack`; no request was issued, so cache hit and retained widget state cannot be told apart here) and Home kept its loaded state; neither spun. To reach a read that had to go to the network I stepped the calendar to July (16:48:24) — **and the app was on the WELCOME screen.** Logcat: `E/AppAuth Network error when retrieving discovery document … ConnectException: Failed to connect to /10.0.2.2:8080`; **no API request was dispatched**. The access token issued ≈16:32:40 had expired ≈16:47:40 (`accessTokenLifespan 900`); the interceptor's **proactive** refresh fired inside `onRequest`, AppAuth could not fetch the discovery document offline, and `_performRefresh`'s catch-all **cleared the token store, fired `onAuthLost`, and purged the cache** (proven by code — `auth_controller.dart:120` → `hive_boot.dart:181`). **Finding D2**, re-run deterministically in §3.5. Recovery: network on → *I already have an account* → Keycloak re-auth (correct account pre-filled) → password → `GET /me` → dashboard, no onboarding bounce. **Second attempt (fresh token, 16:51):** **9.1** airplane on → Cycle tab → the designed state **"No network connection or request timed out." + Try again** within 2 s — the dashboard had re-cached August and July at 16:51:26, but the calendar's three-window read (`cycle_calendar_controller.dart:253-260`) also needs September, which was uncached, and fails whole on it: exactly one `GET /cycle/calendar` went out (16:51:55) and failed; Home kept its state. *Qualification:* 9.1's PASS is the Cycle tab's; the **dashboard's own uncached offline state was never observed** (it held warm state in both attempts). **9.2** pain 3 + Tired → Save → within 1 s an inline banner *"No network connection or request timed out."*, **sheet still open, 3 and Tired still selected, button now "Try again"**; the frame was unchanged for 25 s — no spinner outlived the failure. **9.3** network on → Try again → sheet closed ≤1 s → dashboard **"3 / 10 · Tired"**; API day row `pain 3, mood 2, updatedAt 22:53:49` (same row upserted, `createdAt` unchanged). **9.4** HOME → launcher, 10 s, relaunch → *"current task has been brought to the front"* (not recreated) → same dashboard, same state. **9.5** `am force-stop` (pid gone) → cold start → new process → **dashboard at 5 s, no sign-in**, and the only request on the wire was `GET /cycle/calendar` (the server-today read): the profile and the month grid came from the **on-disk Hive cache** across a process kill (inferred from the absence of `GET /me` and month reads on the wire; that the box is `HiveAesCipher`-encrypted is code, `hive_boot.dart:86-88`) — fact 3 of §0, seen on device for the first time. *Qualification:* this cold start ran on a 3-minute-old token; a cold start ≥ ~14.5 min after the last token issue **while offline** would hit D2 instead (every cold start makes the uncached server-today read), so 9.5 is a PASS conditional on token age or connectivity until D2 is fixed. *(A thin lime border framed the app window after that adb-launched cold start and persisted; no overlay window explains it — recorded as an unexplained cosmetic artefact of the launch path, content and behaviour unaffected.)* |

## 3.2 Findings — defects

Both are cross-layer; neither is reachable by `test/flows/` or by the backend suites, and **both are
"the defect is the specification": the tests that touch them pin the wrong behaviour as correct.**

**D1 — The client never sends the device timezone or locale at registration, so every user registered
through the app lives on Madrid's calendar day — a ratified decision the client did not implement.**
`AccountController.register()` calls `startOnboarding(email:, password:, displayName:)` and nothing else
(`account_controller.dart:69-75`; its only caller `account_screen.dart:57-64`), although the repository
accepts `locale`/`timezone` (`onboarding_repository.dart:93-107`) and `account_validation.dart:67-69` even
records that *"screen 2 sends `null` for all of them"*. `OnboardingService.cs:59-60` then applies its code
defaults `es-ES` / `Europe/Madrid` (the `User` entity initialisers, `User.cs:12-13`; there is no DB-level
default), and D-12's `UserDayContext`/`UserDayResolver` derive the user's day from that column for **every**
day-keyed read and write: `POST /checkin/quick` upserts the row at `day.Today` (`CycleDayService.cs:175`),
`POST /symptoms` sets `occurredOn = ToUserDay(occurredAt, day.TimezoneId)` (`SymptomService.cs:526`),
`GET /cycle/calendar` windows and reports `today` (`CycleCalendarService.cs:77,151`), and the client
deliberately takes "today" from that response (`server_today.dart`, D-12). On this device at 16:39 local the
app's day was already **26 August**; the check-in and both symptom rows are filed under a date the user had
not reached, and the dashboard header disagreed with the phone's own clock. **The user cannot fix it:**
`PATCH /me` validates and stores `timezone`/`locale` (`Program.cs:400-449`), but the client's
`MeRepository.updateMe` sends only `displayName` (`me_repository.dart:77-86`) and screen 31 renders both as
read-only `_InfoRow`s (`profile_screen.dart:166-168`, no `onTap`) — there is no write path at all. **It was
specified and not built:** `ARCHITECTURE.md:40` (D-12: `users.timezone` *"captured at
`/onboarding/start`"*), `decision-sheet.md:75-76` (*"Capture `users.timezone` from device at
`/onboarding/start`"*, ✅ approved 2026-07-08), D-03 (*"`users.locale` defaults from device"*),
`gap-register.md:335,559`, and `p4a-task-breakdown.md` OQ-4 (`:606-608`), which added `PATCH /me` precisely
for the user who *"onboarded on a device with a different tz"* — the server half shipped in P4a, the client
half never did (origin P3b-T7, screen 2; a carried defect, not a P4b regression). **Severity H, and it is
data loss, not only mis-labelling:** `cycle_day_logs` is one upsert row per day (D-11), so an evening
check-in filed under D+1 is silently overwritten by the next morning's check-in (the MERGE at
`CycleDayService.cs:175ff`). The wrong day is in force ~7–8 h of every day in Mexico City, ~4–10 h across the
Americas; users east of Madrid file post-midnight entries under *yesterday*; even the Canary Islands get a
one-hour window; and D-12-driven notification scheduling will inherit the same clock once P9a ships.
**Invisible to every suite, and pinned by two of them:** no flow covers `POST /onboarding/start`;
`account_controller_test.dart:114-121` verifies the call with `locale`/`timezone` implicitly null; the live
backend tests send `Europe/Madrid` — exclusively — and `OnboardingServiceTests.cs:230-260` asserts that an
absent timezone *becomes* `Europe/Madrid`. **Fix shape (client, screen 2; recommend a review-born fix before
the P4b merge, or the first assertion of P4c-T0):** send the device IANA zone at registration via a platform
lookup (a package such as `flutter_timezone` or a `MethodChannel` — `DateTime.now()` is build-guarded under
`lib/` by `formatting_guard_test.dart`, and `timeZoneName` is an abbreviation, not an IANA id) and the device
locale from `deviceLocaleProvider` / `readDeviceLocale()` (`locale_provider.dart:94-103`, hyphenated BCP-47),
**not** `localeProvider` (profile-first once `/me` is adopted); grow `MeRepository.updateMe` a `timezone`
parameter; then a PO line between (i) re-syncing `users.timezone` from the device on app start via
`PATCH /me` when it differs (no UI; consistent with D-07's device-only stance and OQ-4's travel case) and
(ii) an editable row on screen 31 (the mockup `Screens/screen_31_profile.html` has no locale/timezone rows,
so that is a design addition); and a flow assertion that `POST /onboarding/start` carries `timezone`.

**D2 — Any refresh failure other than an authoritative OAuth rejection signs the user out and purges the
on-disk cache; reproduced twice, the second time with no user interaction at all.**
`auth_interceptor.dart:196-209` `_performRefresh` wraps `_refresh(refreshToken)` in a bare `catch (_)` and on
**any** exception calls `_store.clear()`, then `_onAuthLost()`. Both entry points funnel into it: the
**proactive** `onRequest` path (fires when the stored expiry is within 30 s or already past, `:66,82-87`) and
the reactive 401 path (`:134`). `OidcClient.refresh()` (`oidc_client.dart:172-186`) passes `issuer:` rather
than the explicit `serviceConfiguration:` that `endSession()` uses (`:197-201`), so `flutter_appauth`
fetches the discovery document first — offline that is a `ConnectException` before any token-endpoint verdict
exists (passing explicit endpoints would remove that round-trip but **not** the defect: the token POST fails
identically). `onAuthLost` → `AuthController.logout()` (`dio_provider.dart:249-254` →
`auth_controller.dart:101-125`) → `cacheStoreProvider.purge()` → `hive_boot.dart:181` `_box.clear()` on the
`HiveAesCipher` box (the purge itself is deliberate privacy design and must stay; only *when* logout fires is
wrong) → `AuthStatus.unauthenticated` → the router sends everything to welcome (`app_router.dart:95-99`).
Because the store is cleared *before* `onAuthLost`, `logout()` finds no id token and skips RP-initiated
end-session — the sign-out is local-only and the Keycloak SSO session survives (which is why re-login
pre-filled the correct account). **What happened on device (both runs):** the realm's `accessTokenLifespan`
is **900 s** (`realm-lumen.json:10`; confirmed on a live token: `expires_in 900`, JWT `exp−iat = 900`;
refresh tokens live 30 days, `:11-12`, so the refresh would have succeeded online). Run 1: token issued
≈16:32:40 (Custom-Tab redirect 16:32:40.6, first `GET /me` 16:32:41.8), expiry ≈16:47:40, proactive window
open from ≈16:47:10; airplane mode on at 16:47:17; the first request that had to reach the network (the July
calendar, 16:48:24) entered `onRequest`, the proactive refresh fired, AppAuth logged `Network error when
retrieving discovery document … ConnectException: Failed to connect to /10.0.2.2:8080`, and the app was on
the welcome screen — **no API request was dispatched** (no `[Dio ▶]` line, because `PiiSafeLogInterceptor`
sits after `AuthInterceptor`, `dio_provider.dart:257-260`, and `handler.reject` short-circuits it; the
container log is silent 22:46:46→22:51:27). Run 2 (§3.5): the same error **before any tap**, on the app's own
request. **Scope:** any request that must go to the network when the stored expiry is within 30 s or past —
i.e. from ~14.5 min after the last token issue/refresh, including the uncached `GET /cycle/calendar` every
cold start makes (`server_today.dart`, seen at 16:54:32) — while the refresh cannot complete: offline, DNS,
timeout, Keycloak down or 5xx, or a malformed token response (`oidc_client.dart:216-227`) all land in the
same catch. Opening the app after ≥15 min idle on a flaky connection is the everyday trigger. **Severity H
(M is arguable):** no *persisted* data is lost and the failure is fail-closed; what is lost is the session
(password again in a Custom Tab, `prompt=login`), the entire on-disk cache, and any un-submitted form state
(a screen-12 note, an open sheet) because of the router redirect — on the network conditions a health
tracker is used in. **Pinned as specified, not as a slip:** `auth_interceptor_test.dart:464-497` throws a
generic `Exception('Token server down')` at the refresh seam and asserts `store.clear()`, `onAuthLost` and an
`AuthFailure` reaching the caller (`:483-491` — the assertion the fix will flip); the production `catch (_)`
at `:205` is what extends that to network and discovery failures; sibling `:499-517` pins the
no-refresh-token branch; all implementing the P3a-T3 task spec (*"on refresh failure clear tokens + signal
logout"*, `lumen-build.md:367`). So the fix amends a task spec and its test, not a §A decision; D-03/D-05/D-12
and the online-only cache row (`ARCHITECTURE.md:23`) are untouched. No test anywhere in `client/test`
distinguishes a network error during refresh from an `invalid_grant`. **Fix shape (auth; RUNBOOK §8's
"anything touching auth" review rule applies; owner P4c, or a review-born fix before the P4b merge):**
classify in `AppAuthOidcClient.refresh()` — catch `FlutterAppAuthPlatformException` and read
`platformErrorDetails.error`: `invalid_grant` / `invalid_client` / `unauthorized_client` ⇒ auth lost; a null
`error` with code `discovery_failed`/`token_failed` (AppAuth-Android network/general errors, incl.
`SERVER_ERROR`) ⇒ transient; unknown ⇒ keep tokens (Android values come from `FlutterAppauthPlugin.java
createErrorMap`; iOS surfaces different domain/codes and needs its own mapping) — throw two typed exceptions
the interceptor discriminates; on the transient branch keep the tokens and reject with a `DioException` of
**`type: DioExceptionType.connectionError`** (or rethrow the original transport exception) — **not**
`error: NetworkFailure(), type: unknown`, because `mapDioException` (`error_mapper.dart:91-146`) switches on
`e.type` and maps `unknown` → `UnknownFailure` without unwrapping `e.error`, which would show the generic
error instead of the "No network connection" state the screens already render (proven in 9.1/9.2); refresh
again on the next request; re-pin both branches with tests, and make the expired-token-offline scenario a red
test in the R-06 (iii) harness before the fix lands.

## 3.3 Observations (record, not defects — some need a PO line)

- **O1** System splash / launcher icon are Flutter's template (white + Flutter logo). Cosmetic; polish phase.
- **O2** Login leg in a browser holding another user's *live* Keycloak SSO session (Chrome's cookie jar, not
  the app's — `pm clear` does not touch it): the app sends `prompt=login` (`oidc_client.dart:166`, deliberate
  — no silent SSO reuse on a shared device) and no `loginHint`, so a brand-new registration is shown the
  *previous* user's re-auth prompt until ↻ is tapped. **Do not book this as a `login_hint` one-liner:** under
  `prompt=login` with a live session Keycloak pins the username to that session regardless of the hint; the
  robust options are an ephemeral Custom Tab session or accepting the ↻ path and documenting it — verify
  against Keycloak first. Registration also asks for the password twice (screen 2, then Keycloak) — a
  separate UX observation. Both belong with the login leg (P4c).
- **O3** Right after login, screen 3 reads `/cycle/calendar` once for the server's `today` (its date picker
  opens on the right month by design, `server_today.dart:91`) and `/settings/cycle`; not a prefetch. Harmless.
- **O4** Number/date formatting follows the *profile* locale (`es-ES`): weight re-renders as `60,0`, DOB as
  `14/8/1996`, on an en-US device — consistent with D-05 given D1, and it corrects itself with D1. (The
  dashboard's date line is hard-coded English, `lumen_formats.dart:179-202`, so it is unaffected either way.)
- **O5** Re-Continue on an unchanged step sends nothing on screen 4 but re-posts on screen 5 (full replace,
  identical). Neither loses data.
- **O6** A **symptom's** note is stored (API confirms; the batch assembler attaches it to the batch's first
  entry, `symptom_batch_assembler.dart:83-118`) but has **no read surface on any shipped screen**: the day
  view's `_SymptomRow` never reads `symptom.notes` (`day_detail_screen.dart:97-127, 604-656`), and its NOTE
  card is the *day-log* note from "Edit pain, mood and note" — a different field; period-event notes are
  drawn too. The absence app-wide is a consequence of scope (the mockup draws no symptom note; the symptom
  edit surface was cut at T20), not a stated product decision — hence a PO question: where should it be
  readable? (Script step 7 corrected above.)
- **O7** After a resume, screen 32 keeps the last reason chip selected and Pause enabled — **documented
  design in both layers** (`CycleSettingsService.cs:414-416,440-443` quoting `ARCHITECTURE.md` §D: *"resume
  … preserves the reason so the next pause can pre-select it"*; `cycle_settings_controller.dart:317-329,
  516-522`). The PO line is whether the pre-selection is wanted, not whether it is a bug.
- **O8** Offline, a read whose cache entry exists is served — `Fresh` (no request) inside the 5-min TTL,
  `Stale` after the failed request outside it (`cached_query.dart:113-118, 195-208`); the designed error
  state appears when any constituent read has no entry — the calendar fans out to three months and fails
  whole if one is uncached — or when the server-today read is required. With an expired access token the
  proactive refresh runs *before* any of that (D2), so the `Stale` fallback is never reached offline once
  the token has aged.
- **O9** "Good afternoon" (device clock, waived) next to "Wednesday, August 26" (server day) — incoherent
  only because of D1.
- **O10** Hardware/system back on onboarding step 4 exits to the launcher (carried from the 16:12 run; not
  re-tested here — this account is past onboarding). Product decision, still open.
- **O11** The Cycle tab keeps its navigation stack across tab switches (day view restored). Good.
- **O12** Dashboard load issues `GET /cycle/calendar` twice, concurrently — the current and the previous
  month (`dashboard_controller.dart:209-210`); the server-today read happened once at login and is
  keepAlive-pinned for the session. By design. Minor.
- **O13** `[Dio ▶] GET /cycle/day/<redacted>` — the client log redacts the date path segment. Good.

## 3.4 Findings about the suite (R-06 (i)) — evidence for the reviewer's amendment decision

1. **No flow covers registration** (`POST /onboarding/start`; `FlowWorld` starts `authenticated`,
   `flow_harness.dart:243`), so D1's missing fields could never have been asserted there — and the one unit
   test that sees the call pins them as null (`account_controller_test.dart:114-121`). A one-line wire
   assertion would have caught it.
2. **The interceptor test pins D2's behaviour as correct** (`auth_interceptor_test.dart:464-497`, via the
   `AuthFailure` assertion at `:483-491`), and nothing in `client/test` distinguishes a network error during
   refresh from an `invalid_grant`. The suite is green *because* the defect is the specification.
3. **The walk script itself was wrong about step 7** ("with the note"); the day view never shows symptom notes.
4. **Only the walk exercises the end-to-end paths.** Cold-start-with-session and Hive reopen-from-disk have
   unit-level tests (`auth_controller_test.dart:86-97`, `hive_boot_test.dart:349-419`), but nothing crosses a
   process boundary, uses the real secure-storage key, or drives the Custom Tab — and `flow_harness.dart:8-9`
   still says the Custom Tab *"is not automatable"*, which this walk disproved twice. That comment belongs to
   R-06 (iii)'s first commit.
5. **The backend suite pins the Madrid default rather than testing a non-Madrid registration:** every live
   test that persists a user sends `Europe/Madrid`, exclusively (`TestFixtures.cs:32`, `SpineLiveTests.cs:39`,
   …), and `OnboardingServiceTests.cs:230-260` asserts absent ⇒ Madrid. The backend behaviour D1 depends on
   is specified and green; the defect is the client's omission (and the product choice of a Madrid default),
   which no backend test can observe.

## 3.5 D2 — deterministic re-run (background job, 17:06:45–17:07:07 local)

Setup: token issued at the 16:51 re-login (`accessTokenLifespan 900` ⇒ expiry ≈ 17:06:25); app idle on the
dashboard since the 16:54 cold start (last request on the wire `GET /cycle/calendar` at 22:54:34 UTC); no
user interaction between 16:57 and 17:06:45.

| local | what | evidence |
|---|---|---|
| 17:06:45.7 | capture: dashboard "3 / 10 · Tired", `MainActivity` (ActivityRecord `e42911f`) | `60_d2_before.png` |
| 17:06:46 | airplane mode ON (`airplane_mode_on=1`, `Active default network: none`) | `repro-d2.txt` |
| **17:06:47.6** | **`E/AppAuth Network error when retrieving discovery document` / `java.net.ConnectException: Failed to connect to /10.0.2.2:8080`** — **before any tap**, and no `[Dio ▶]` line (the auth interceptor rejects before the logger sees the request) | logcat |
| 17:06:49–51 | the Cycle-tab tap and the prev-month tap both landed on the **welcome screen already** (captures 61/62 byte-identical) | `61_d2_cycle_tab.png`, `62_d2_after_july_2s.png` |
| 17:07:02 | still welcome; same ActivityRecord (no recreation) | `62_d2_after_july_10s.png` |
| 17:07:07 | network back; still welcome (signed out) | `63_d2_network_back.png` |

Reading: reproduced deterministically on the second token. The request that entered the interceptor at
17:06:47 was issued by the app itself — there is **no timer or polling anywhere in `client/lib`** (grepped),
so the likely path is a rebuild-driven refetch after the 5-minute cache TTL (expired 16:59:34); the exact
trigger is **not identified** and does not change the finding. Consequence for severity: **no user action is
needed for it to happen** — but it is not guaranteed without one. *Precision added by the 18:36–18:39 video
takes:* an app left idle on the dashboard with an expired token and airplane mode on did **not** sign out in
two 9-second takes (nothing issued a request), and **did** sign out within two seconds on the first
network-bound action (calendar, previous month — `E/AppAuth … ConnectException` at 18:38:44.98). So the
rule is: **the first request that must reach the network while the token is past its window signs the user
out, whether the user made it or a background refetch did.**

## 3.6 Second theme pass — the live screens in dark

The script's step 2 flips the theme on welcome only, and the header exit criterion says *"in both themes"*
against the live backend — so after the D2 re-run I signed the same account back in and flipped the device to
dark on the **live** screens (17:17): dashboard (screen 8), calendar (10), day view (11), profile (31), cycle
settings (32), the check-in sheet (9) and the symptom form (12) — `72_dark_dashboard.png` …
`78_dark_symptom_form.png`. **PASS:** every one renders the documented dark palette (deep plum ground, cream
ink, moonlit-gold accents and selected states, sage section labels), with live data (3 / 10 · Tired, the
26th outlined, the symptom rows, `Europe/Madrid` on the profile), nothing unreadable and no Material
default anywhere; flipping back to light restored the warm-sand palette (`79_light_symptom_form.png`).
Onboarding screens 3–7 could not be revisited on a completed account; they rest on their committed dark
goldens. **The header criterion is therefore met on device for screens 8–12, 31, 32 and by goldens for 3–7.**

## 3.7 Evidence archive

`p4b-walk-evidence/` (next to this file) holds the API read-backs (`api-readbacks.md`), the API container
log for the session window (`api-log-utc.txt`, UTC), the filtered logcat (`logcat-local.txt`, UTC−6), the D2
re-run log (`repro-d2.txt`) and the load-bearing screenshots named above. The full 95-capture set stayed in
the session scratchpad; nothing in the record depends on a capture that is not archived.

---

## 4. What to write into STATUS

Paste a block with, at minimum:

- **date, commit SHA, device/OS, emulator-or-physical, and the two `--dart-define` values**;
- the **Vault probe output** (Trap B) and the account address you created (Trap A);
- **one line per step, 1–9**, saying PASS or what you actually saw — screenshots for anything visual;
- **every deviation, however small**, including cosmetic ones: this is the only pass on real hardware this
  phase gets, and "I noticed but it seemed minor" is how a finding disappears;
- **anything this walk found that a `test/flows/` test should have caught.** That is a finding about the
  suite and belongs in the reviewer's R-06 decision, because it is evidence about whether the amendment was
  honoured.

**If a step cannot be performed at all** — no device, the stack will not come up, Keycloak will not register —
**record that as an unexecuted step rather than a pass.** R-06 (ii) is one of two halves of an amended exit
criterion, and a reviewer accepting the amendment needs to know which halves actually ran.
