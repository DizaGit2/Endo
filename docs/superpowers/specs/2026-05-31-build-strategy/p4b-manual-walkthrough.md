# P4b — the manual on-device walkthrough (R-06 (ii))

**Who runs this:** a human, at **T25** (phase close). **Not** an implementer, and **not** CI.
**Where the result goes:** pasted into the P4b **STATUS** block in `docs/superpowers/plans/lumen-build.md`,
matching the P3b-T10 / P3c precedent.
**Written at:** P4b-T24, alongside `client/test/flows/` — the other half of R-06.

---

## 0. Why this exists, and what it is allowed to prove

R-06 amended this phase's `integration_test green` exit criterion. `client/integration_test/` holds only a
`.gitkeep`, there is no `integration_test` dev dependency, CI is `ubuntu-latest` with no emulator and no
compose stack, and **Keycloak's login runs in a Chrome Custom Tab that is not automatable**. The amendment
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
other than onboarding; `GET /me` errors (if you see the splash's retry surface here, **re-read Trap A**).

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
- **today's day view lists the symptom you logged**, with the note;
- the calendar cell for today carries its symptom marker.

**Failure:** the form stays on screen after a successful save (**tap Save exactly once and stop** — this
screen has previously shipped in a state where a second tap posted the batch again, and there is no delete);
the day view shows nothing; the note is attached to the wrong row.

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
