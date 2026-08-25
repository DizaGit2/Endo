# P4b — resuming the on-device E2E effort

**Written 2026-08-25, at P4b 43/43 `NEEDS_REVIEW`, HEAD `0313271` on `phase/04b-logging-client`.**
**Read this first if you are picking up the emulator work.** The build plan
([`../../plans/lumen-build.md`](../../plans/lumen-build.md)) §1 ledger remains the authority for what is
done; this file is the authority for **where the E2E effort stands and how to restart it in one sitting**.

---

## 0. The goal, stated plainly

**End-to-end verification on the emulator is the goal — not a nice-to-have, and not something the flow
suite substitutes for.** That is a direction from the product owner (2026-08-25) and it changes the
standing of R-06:

- **R-06 (i)** — the `test/flows/` suite. **Delivered** (23 tests). Useful, and **structurally incapable**
  of the class of defect E2E catches: it fakes at `LumenApiApi`, so it never learns whether an endpoint is
  even *mapped*, never runs a serializer, never runs Dio, never touches Hive, and asserts against a
  **hand-written model of the server**.
- **R-06 (ii)** — one manual on-device walk. **Partially performed** (steps 1–4, see below).
- **R-06 (iii)** — *"a real `integration_test/` harness deferred to its own task."* **This is now the
  target, not a deferral.** It is still booked by no task anywhere; booking it is the next planning act.

**The 2026-08-25 run earned that reframing on its first attempt** — see §2.

---

## 1. What is already true (do not re-establish this)

- **P4b is code-complete at 43/43 and sits at `NEEDS_REVIEW`.** Client **2286** tests, backend **1228**,
  analyze clean, coverage **97.16%**, contract byte-identical to `phase-04a`, CI green on both workflows.
- **The emulator path works end to end.** An AVD named **`lumen`** exists; the app builds, installs, runs,
  registers an account through Keycloak's Custom Tab, and reaches onboarding.
- **Steps 1–4 of the manual walk PASS**, including the T8b persistence check. Full log with evidence:
  [`p4b-manual-walkthrough.md`](p4b-manual-walkthrough.md) §3.1.
- **The account `p4bwalk08251612@example.com` has been used. Do not reuse it** (Trap A).

---

## 2. The finding that justifies the goal — read this before writing any harness

The first real E2E attempt failed, and **no test in the repository could have caught why.**

Every pre-flight probe passed: `docker compose ps` healthy, `pg_isready` accepting, Keycloak's issuer
resolving, `/health` returning `status : healthy`. Registration succeeded, Keycloak authenticated, the
Custom Tab closed, the app resumed — and dead-ended on *"The requested resource was not found."*

**The `api` container had been built on 2026-06-14** — P3a-era, predating the whole P4a backend — and had
been up 13 hours reporting healthy. `GET /onboarding/state` returned **404** with
*"Request reached the end of the middleware pipeline without being handled by application code"*: a
**routing** 404. The endpoint is mapped at `OnboardingEndpoints.cs:210`; it was not in that image.

**Why nothing caught it, and why that is the argument for E2E:**
- the **flow suite** fakes at `LumenApiApi` — it cannot observe whether a route exists;
- the **backend integration tests** exercise the API **in-process**, not the container;
- **`/health` answers identically on every build ever made**, so it proves the container is *running* and
  nothing about *what is in it*.

**It is now Trap C** in the walkthrough, with a routing-provenance probe that would have caught it in five
seconds. **Any harness built for R-06 (iii) must run that probe first**, or it will inherit the same blind
spot with a green badge on top.

---

## 3. Restarting in one sitting — the exact sequence

```powershell
# 1. Stack, and prove it is the RIGHT build (Trap C)
docker compose -f deploy/docker-compose.yml up -d
docker compose -f deploy/docker-compose.yml exec -T vault sh -lc 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault read transit/keys/lumen-dev-kek'   # Trap B
'/onboarding/state','/symptoms','/settings/cycle','/cycle/calendar','/me' | ForEach-Object {
  $c = try { (Invoke-WebRequest "http://localhost:8085$_" -UseBasicParsing).StatusCode }
       catch { $_.Exception.Response.StatusCode.value__ }
  '{0,-22} -> {1}' -f $_, $c }        # EVERY line must be 401. A 404 => rebuild:
# docker compose -f deploy/docker-compose.yml up -d --build api

# 2. Emulator
flutter emulators --launch lumen
# adb lives at $env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe (not on PATH)

# 3. App
$env:PUB_CACHE = 'C:\pub_cache'
Set-Location C:\Proyectos\Endo\client
flutter run -d emulator-5554          # emulator defaults are correct; pass no --dart-define
```

**Driving it without hands** (this is how steps 1–4 were run, and it works):

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb shell pm clear com.lumen.lumen                    # Step 1 needs a TRUE first launch
& $adb shell am start -n com.lumen.lumen/.MainActivity
& $adb shell "cmd uimode night yes"                      # Step 2
& $adb shell input tap <x> <y> ; & $adb shell input text "..."
& $adb exec-out screencap -p > shot.png                  # then LOOK at it
& $adb shell dumpsys activity activities | Select-String topResumedActivity
```

**Screenshots are 1080×2400.** If your viewer scales to 900×2000, multiply coordinates by **1.2**.
**Keycloak's Custom Tab is drivable** with `input tap` / `input text` — it is not the blocker R-06
originally assumed, and that is the single most important practical discovery for building (iii).

---

## 4. What to do next, in order

1. **Finish the manual walk — steps 5–9.** Out the other side; quick check-in; log a symptom; pause/resume
   twice; offline + backgrounding + cold restart. **Use a fresh account.** Paste the completed result into
   the P4b STATUS block; **a partial walk must not be pasted as if it satisfied R-06 (ii)**, which is why
   §3.1 of the walkthrough holds the partial log instead.
2. **Book R-06 (iii) as a real task** with an owner and a phase. It is the goal; it is currently booked
   nowhere. Suggested shape, from what the 2026-08-25 run proved:
   - `integration_test/` driven by `flutter drive` / `integration_test` against the **live compose stack**;
   - **the routing-provenance probe as its first assertion**, so a stale container fails loudly instead of
     producing a mystery;
   - the login leg **included**, since the Custom Tab turned out to be automatable — this is the leg the
     flow suite can never cover and the one most worth having;
   - assertions on **stored state via the API**, not only on widgets, so it catches what the flow suite's
     server-model cannot.
3. **Decide the system-back question** (walkthrough §3.1): on onboarding step 4, hardware back exits the
   app while the on-screen chevron steps back correctly. Product decision, not obviously a defect.
4. **Then** the phase-acceptance ritual (RUNBOOK §8) — merge, tag, advance the pointer. **Not before the
   walk is complete**, since it is a stated exit criterion.

---

## 5. Things that will waste your time if you do not know them

- **`adb` is not on PATH.** `$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`.
- **`PUB_CACHE` must be quoted** (`$env:PUB_CACHE = 'C:\pub_cache'`). Unquoted in bash it mangles to
  `C:pub_cache`, the run dies at *"Failed to update packages"* — **and still exits 0**.
- **Windows PowerShell 5.1**, not 7. No `-SkipCertificateCheck`, no `\` line continuation, no inline
  `VAR=value cmd` prefix. All three broke this script before they were fixed.
- **Read the last line of every command, never the exit code.** That rule has caught three separate false
  greens in this phase.
- **`/health` is not a build check.** Trap C.
- **Vault `-dev` loses its Transit engine on container recreate** while `ps` still says healthy; ~96 backend
  integration tests go red through `OnboardAndLoginAsync`. Trap B. Recover with
  `docker compose -f deploy/docker-compose.yml up vault-init`.
- **14 `user_keys` rows in the dev DB are permanently undecryptable** after the T20 incident. Always a fresh
  account. Trap A.
