# P4b — the on-device E2E effort: where it stands after the complete walk

**Written 2026-08-25 (afternoon) at P4b 43/43 `NEEDS_REVIEW`; rewritten the same evening after the walk was run in
full.** The build plan ([`../../plans/lumen-build.md`](../../plans/lumen-build.md)) §1 ledger remains the authority
for what is done; this file is the authority for **where the E2E effort stands and how to restart it in one sitting**.

---

## 0. The goal, stated plainly

**End-to-end verification on the emulator is the goal — not a nice-to-have, and not something the flow suite
substitutes for.** That is a direction from the product owner (2026-08-25). Where R-06's three parts stand:

- **R-06 (i)** — the `test/flows/` suite. **Delivered** (23 tests). Useful, and **structurally incapable** of the
  class of defect E2E catches: it fakes at `LumenApiApi`, so it never learns whether an endpoint is even *mapped*,
  never runs a serializer, never runs Dio, never touches Hive, and asserts against a hand-written model of the
  server. **The full walk found two more defects of exactly that class (D1, D2) — both pinned as *correct* by
  existing tests.**
- **R-06 (ii)** — one manual on-device walk. **COMPLETE 2026-08-25, steps 1–9**, pasted into the P4b STATUS
  block; long form with evidence in [`p4b-manual-walkthrough.md`](p4b-manual-walkthrough.md) §3.1–3.7 and
  [`p4b-walk-evidence/`](p4b-walk-evidence/).
- **R-06 (iii)** — *"a real `integration_test/` harness deferred to its own task."* **Booked as P4c-T0 in plan
  r22 (proposed — the reviewer confirms or rejects at acceptance).** It runs first in P4c, needs no OAuth
  registration, and carries the D2 red test.

---

## 1. What is already true (do not re-establish this)

- **P4b is code-complete at 43/43 and sits at `NEEDS_REVIEW`.** Client **2286** tests, backend **1228**, analyze
  clean, coverage **97.16%**, contract byte-identical to `phase-04a`, CI green on both workflows. **All eight exit
  criteria now carry evidence** (r22); the reviewer still owes the four amendments, the D1/D2 ruling, and the
  bookings.
- **The emulator path works end to end and is automatable.** AVD **`lumen`**; the app builds, installs, runs,
  registers through Keycloak's Custom Tab (**drivable with `adb shell input tap` / `input text` — proven twice**),
  completes onboarding, logs, pauses/resumes, survives backgrounding and a cold restart with its stored session.
- **Steps 1–8 PASS; step 9 PASS on its second attempt** after the first attempt exposed D2. Screens 8–12, 31, 32
  were also seen in **dark** against live data (§3.6 of the walkthrough).
- **Two accounts have been used. Do not reuse either** (Trap A): `p4bwalk08251612@example.com` (16:12 partial
  run) and `p4bwalk08251630@example.com` (the complete run; onboarding completed, data logged on 2026-08-26 —
  Madrid's day, see D1).

---

## 2. The two defects the walk found — read these before touching auth or registration

Full text, citations and fix shapes: walkthrough §3.2; plan bookings **B-49 / B-50**. In one breath each:

- **D1 — the client never sends the device timezone (or locale) at `POST /onboarding/start`, and has no write
  path for them afterwards.** The server applies `Europe/Madrid`, D-12 derives every user-day from it, and the
  client deliberately takes "today" from the server — so on a Mexico City device at 16:39 the dashboard said
  *"Wednesday, August 26"* and the check-in and symptom rows were filed under a day the user had not reached. The
  one-row-per-day check-in upsert makes that **data loss**, not just a label. It is a ratified decision (D-12,
  2026-07-08) the P3b account screen never implemented; two suites pin the omission as correct. **Severity H.**
- **D2 — any transport failure during a token refresh signs the user out and purges the on-disk cache.**
  `AuthInterceptor._performRefresh` has a bare `catch (_)`; the proactive path reaches it on the app's own
  requests; access tokens live 900 s. Reproduced at 16:48:24 and again at 17:06:47 **with no user interaction**.
  Pinned as correct by `auth_interceptor_test.dart:464-497` (the P3a-T3 spec). **Severity H** (M arguable: no
  persisted data is lost — the session, the cache and any un-submitted form state are).

**Both are outside P4b's 13 screens and were found only against the live backend.** The reviewer rules: fix before
the P4b merge (D2 touches auth → RUNBOOK §8's review rule), or carry to P4c with T0's red test.

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

**Driving it without hands** (this is how all nine steps were run):

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb shell pm clear com.lumen.lumen                    # Step 1 needs a TRUE first launch
& $adb shell am start -n com.lumen.lumen/.MainActivity
& $adb shell "cmd uimode night yes"                      # Step 2
& $adb shell input tap <x> <y> ; & $adb shell input text "words%swith%sspaces"   # %s = space
& $adb shell screencap -p /sdcard/s.png ; & $adb pull /sdcard/s.png shot.png     # then LOOK at it
& $adb shell dumpsys activity activities | Select-String topResumedActivity
& $adb shell cmd connectivity airplane-mode enable       # Step 9 (…disable to restore)
& $adb shell am force-stop com.lumen.lumen               # Step 9.5
```

**Reading stored state through the API** (every PASS in the log is pixels *and* rows):
`powershell -File docs/superpowers/specs/2026-05-31-build-strategy/p4b-walk-evidence/api-readback.ps1 -Email <acct> -Password <pw> /me /onboarding/state /cycle/day/2026-08-26`

**Screenshots are 1080×2400.** If your viewer scales to 900×2000, multiply coordinates by **1.2**.
**Keycloak's Custom Tab is drivable** — that is the single most important practical fact for building (iii).

---

## 4. What to do next, in order

1. **The reviewer's acceptance ritual (RUNBOOK §8), which now has one more item:** accept or reject the four
   amendments (R-06 with (iii) booked as P4c-T0, R-08, R-21, R-22); **rule on D1 and D2** (fix before merge, or
   carry to P4c-T0); rule on the 51 bookings. Then merge, tag, advance the pointer.
2. **Build P4c-T0 first** — the harness: `integration_test` against the live compose stack; the Trap C route
   probe as its first assertion; the login leg through the Custom Tab; stored-state assertions via the API; the
   nine walk steps as the minimum scenario; **D2 as a red test before its fix**; retire `flow_harness.dart:8-9`'s
   "not automatable" comment. Its scope should also cover what the walk could not: the dashboard's *uncached*
   offline state, and onboarding screens 3–7 in dark against live data.
3. **Decide the system-back question** (walkthrough O10): on onboarding step 4, hardware back exits the app while
   the on-screen chevron steps back correctly. Product decision, still open.
4. **PO lines the walk raised:** where a symptom's note should be readable (B-51); whether screen 32 should
   pre-select the last pause reason (B-52); re-sync-on-start vs an editable timezone row on screen 31 (B-50).

---

## 5. Things that will waste your time if you do not know them

- **D2 will sign you out** if the app goes offline more than ~14.5 min after its last login/refresh — with no
  tap. Run step 9 on a fresh token, or expect welcome and re-login. It is a recorded defect, not a new finding.
- **"I already have an account" on the welcome screen goes to the account screen first**; the same link on the
  account screen is what opens the Custom Tab.
- **Keycloak may show the *previous* account** if Chrome still holds its SSO session (B-53): tap ↻ to switch.
- **`adb` is not on PATH.** `$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`.
- **`input text` needs `%s` for spaces**; take screenshots with `shell screencap` + `pull` — PowerShell's `>`
  mangles binary from `exec-out`.
- **`PUB_CACHE` must be quoted** (`$env:PUB_CACHE = 'C:\pub_cache'`). Unquoted in bash it mangles to
  `C:pub_cache`, the run dies at *"Failed to update packages"* — **and still exits 0**.
- **Windows PowerShell 5.1**, not 7. No `-SkipCertificateCheck`, no `\` line continuation, no inline
  `VAR=value cmd` prefix. **`python3` is not installed** (`python` is); parse JSON with `ConvertFrom-Json`.
- **Read the last line of every command, never the exit code.** Four separate false greens in this phase.
- **`/health` is not a build check.** Trap C.
- **Vault `-dev` loses its Transit engine on container recreate** while `ps` still says healthy. Trap B. Recover
  with `docker compose -f deploy/docker-compose.yml up vault-init`.
- **14 `user_keys` rows in the dev DB are permanently undecryptable** after the T20 incident. Always a fresh
  account. Trap A.
- **The API container logs in UTC; logcat and the status bar are local (UTC−6 here).** The server's user-day is
  Madrid's until D1 is fixed — do not mistake "August 26" at 16:39 for a clock problem.
