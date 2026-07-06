# Lumen — Product Decision Sheet (resolve the contradictions & policy choices)

> Companion to the [gap register](gap-register.md). These are the **product-owner decisions** — not clinical facts, not on-screen — that the build needs. Each has my **recommended default** so you can mostly just confirm. Mark each `✅ approved` or write your change in the **Decision** line. Resolved decisions get copied into `ARCHITECTURE.md §A` and the living plan's §4. Ordered by the phase they block.
>
> Legend: 🔴 blocks the phase · 🟠 strong default, low risk to accept.
>
> **Adopted 2026-06-01 (defaults, to unblock P1):** password policy, consent capture, and default locale (**D-03**) = their recommended defaults. The first two predate the current numbering and are recorded as **D-24/D-25** at the end of this sheet — the plan's old "D-01/D-02" labels for them were renumbered in r13 (this sheet's D-01/D-02 are social-login and onboarding-complete). Implemented as versioned/nullable so legal can tighten without a migration.

---

## Before P1 (auth/identity spine)

### D-01 🔴 Apple/Google social login — in or out for v1?
**Conflict:** Screen 2 shows an "Apple · Google" button; the architecture lists only Keycloak email/password.
**Options:** (a) v1 email/password only, remove/disable the buttons (or "coming soon"); (b) wire Keycloak identity brokering now (Apple "Hide My Email" relay handling, account-linking on `email_hash`, +2 subprocessors in the privacy policy).
**Recommended default:** (a) — defer social login to phase 2. Removes 2 subprocessors and Apple-review complexity from v1.
**Decision:** ​_______________________________________________

### D-02 🔴 "Onboarding complete" criteria — what's mandatory vs skippable?
**Conflict:** `onboarding_completed_at` exists but nothing defines what sets it; screens imply skippability ("Not now", "Edit anytime").
**Recommended default:** Mandatory = account created + last-period date (needed to seed the cycle). Baseline / goals / hormone-prefs / notifications all **skippable** with sane defaults; the dashboard tolerates missing data.
**Decision:** ​_______________________________________________

### D-03 🟠 Primary locale
**Conflict:** Architecture says "Spanish and English at minimum"; every mockup is English; hosting is EU-only.
**Recommended default:** **es-ES primary**, English second. `users.locale` defaults from device, falls back to es-ES. (English on-screen copy becomes a *translation target*, not the master — see D-12.)
**Decision:** ​_______________________________________________

### D-04 🟠 MFA / email verification for end users
**Recommended default:** TOTP MFA **optional** (off by default; device Face-ID app-lock covers casual security); **email verification required** with a grace window (account usable immediately, nagged until verified). Password reset uses Keycloak's flow with reassurance copy that **data is not lost on reset** (DEK is server-held, not password-derived).
**Decision:** ​_______________________________________________

---

## Before P3a (Flutter foundation — locale/format/units are baked in here)

### D-05 🔴 Locale conventions: week-start, date/time format, decimal separator
**Conflict:** Mockups use **US conventions** (Sunday-first calendars `S M T W T F S`, "8:00 AM", "60.4 kg") but the product is EU/Spanish-primary.
**Recommended default:** Drive all of it from `users.locale` via ICU formatting. For es-ES: **Monday-first** weeks, **24-hour** clock, **comma** decimal. Treat the US-formatted mockups as English artifacts, not the spec. **API payloads are always locale-neutral** (period decimal, ISO dates); format/parse only at the client.
**Decision:** ✅ approved 2026-06-14 — locale-driven (es-ES default), Monday-first / 24-hour / comma, ICU; API stays locale-neutral. Mockup US formats are English artifacts.

### D-06 🟠 Units — metric only?
**Recommended default:** **Metric-only v1** (kg / cm / %). Reserve a `users.unit_system` enum (default `metric`) so a future imperial *display* toggle needs no migration. (Every body screen is already metric; zero imperial terms found across all 38 screens.)
**Decision:** ✅ approved 2026-06-14 — metric-only v1 (kg / cm / %); reserve `users.unit_system` enum (default `metric`) for a future imperial *display* toggle (no migration).

### D-07 🟠 Client-only privacy features scope (analytics / device-backup / app-lock / language picker)
**Recommended default:** No analytics v1 (hide the screen-36 toggle); **iCloud/Google device-backup toggle out of scope** (contradicts online-only server model — hide it); Face-ID app-lock + app-switcher blur **in** (client-only, cheap); **no in-app language selector** v1 (device locale only). Also: **correct the inaccurate "Health info stays on your device" copy** (screen 31) — data is server-stored/encrypted and lab text goes to Anthropic (legal item L-06).
**Decision:** ✅ approved 2026-06-14 — lean scope: no analytics (hide screen-36 toggle); no device-backup toggle (online-only model); biometric app-lock + app-switcher blur IN; no in-app language picker (device locale only); correct the screen-31 copy (see L-03).

---

## Before P4a (Cycle + Symptoms backend — schema-shaping)

### D-08 🔴 Pain / symptom intensity scale: 1–5 or 0–10?
**Conflict:** Architecture + CLAUDE.md say `intensity 1..5`; **every screen shows 0–10** ("3/10", body-map "7", "Avg 0–9").
**Recommended default:** **0–10** (match the screens). Apply the same scale to non-pain symptoms (bloating/nausea show "5/10"). Update `ARCHITECTURE.md §D/§A` + CLAUDE.md; confirm whether 0 is a valid logged value (recommend yes = "none today").
**Decision:** ​_______________________________________________

### D-09 🔴 Symptom data shape: TYPE / TRIGGERS / RELATED / region / body-map
**Conflict:** Screen 12 collects pain TYPE (Cramping/Sharp/Burning/Dull), TRIGGERS (Stress/Intercourse/Food), RELATED (Bloating/Nausea/Fatigue), and LOCATION; screen 13 places multi-point body-map taps with front/back + per-point intensity — but `symptoms` has columns for none of it.
**Recommended default:** Store structured: `pain_types[]`, `triggers[]` (keep `intercourse` — clinically meaningful as dyspareunia), `region` enum + `side` (front/back), `intensity`. RELATED items become their own symptom rows (they carry their own intensity, e.g. "Bloating 5/10"). Body-map taps **snap to nearest region** (one row per region+side+intensity); **no raw x/y coords v1**. Add an `unspecified` region member so quick-check-in pain (no location UI) can be stored.
**Decision:** ​_______________________________________________

### D-10 🔴 Mood / energy / libido modeling
**Conflict:** `cycle_day_logs` has separate `mood`/`energy`/`libido` smallints; screen 9 shows only a 4-way "Mood" grid (Low/Tired/Steady/Bright) where "Tired" is really energy; libido appears on no screen.
**Recommended default:** Quick check-in writes **mood** as ordinal 1–4 {low, tired, steady, bright} (formalize the 4 labels). Capture **energy** and **libido** on the *full* day form (not quick check-in), both optional; define their scales when that form is specced. Don't populate `energy` from the mood grid.
**Decision:** ​_______________________________________________

### D-11 🔴 Quick check-in vs full form — payloads & what each writes
**Recommended default:** Quick check-in = `{pain 0–10, mood 1–4}` → writes pain to `symptoms` (region=`unspecified`) + mood to `cycle_day_logs` (upsert one-per-day). Full symptom form writes a `symptoms` row with region/type/triggers/intensity (append, many-per-day). Write both request schemas into `ARCHITECTURE.md`.
**Decision:** ​_______________________________________________

### D-12 🔴 Per-user timezone & the "today" rule
**Conflict:** Architecture defers per-user TZ (single 08:00 Europe/Madrid job); screens need user-local "today"/"Day X of Y"/"this week".
**Recommended default:** Capture `users.timezone` from device at `/onboarding/start`; use it for **all** day-boundary computation now (one shared helper). Keep the nightly Madrid job only as a batch fan-out trigger, but evaluate per-user local times inside it. Revise the `§A` scheduling row to match. (This also unblocks notifications D-19.)
**Decision:** ​_______________________________________________

### D-13 🟠 Shared data rules: soft-delete visibility, pagination, future-dating, notes limits
**Recommended default:** Soft-delete via `deleted_at`; **all reads/matviews/reports/export exclude soft-deleted rows**. List endpoints paginate (limit/offset, max page 100). **No future dates** for symptom/body/activity/lab entries (max = user-local today); `cycle_events` may backdate within a floor (account-creation − 2y). `notes_enc` max 2000 chars, never sent to the LLM, truncated in PDFs. State once in `§C`.
**Decision:** ​_______________________________________________

### D-14 🟠 Goal selection cardinality & hormone-default conflict
**Recommended default:** Goals multi-select, **min 1, no max** (the 2 pre-selected are a real default). Resolve the onboarding-vs-settings hormone-default conflict (screen 6 all 7 ON, FSH on; screen 33 Testosterone+GLP-1+FSH off) by: **all 7 extracted from labs regardless**; "tracked"/charted defaults = the 5 shown on screen 33 (hidden ≠ not-extracted).
**Decision:** ​_______________________________________________

---

## Before P5 (Body + Activity + Treatment)

### D-15 🟠 Body/activity field shapes (energy-after, body-feel tags, upsert)
**Recommended default:** Add `activity_entries.energy_after smallint` (0–10, optional, slider default 7); add `body_feel_tags[]` to a body entry (Bloated/Light/Heavy/Tender); body entry upserts **one row per metric** sharing `measured_at`, by day. BMI is **derived** (weight/height²), never stored. Metric enum = {weight_kg, body_fat_pct, waist_cm}; activity_type = {walk, yoga, strength, run, swim, pilates, other}; activity intensity 1–3 {gentle, moderate, intense}.
**Decision:** ​_______________________________________________

### D-16 🔴 Medication: catalog link, frequency "Cyclical", logging, effectiveness
**Conflict:** `medications` references `ref_medication`, but screen 27 free-texts names and supports non-drug items ("Heating pad"); "Cyclical" frequency has no defined meaning; **no screen shows a take/skip/snooze action**; a per-med "N/10" appears with no field.
**Recommended default:** `medications.ref_medication_id` **nullable** + always-stored `name_enc` (free-text first, optional catalog match for ATC/dose hints); non-drug relief items live in the same table with a `category`. Frequency v1 = **{daily, as_needed}**; **defer "Cyclical" to phase 2** (or define it as "given on cycle days X–Y" if you want it now). Add a **log action** somewhere in the med UI; `status` {taken, skipped, snoozed}; snooze default 15 min, max 3; "skipped" explicit-only. **N/10 = user-entered effectiveness rating (1–10)**, prompted "after 2 weeks". `cron_like` grammar = `daily@HH:MM` / `weekly:<days>@HH:MM` / `interval:<n>d@HH:MM`.
**Decision:** ​_______________________________________________

---

## Before P7a / P7b (labs)

### D-17 🟠 Storage quota model
**Recommended default:** The "28 MB of 200 MB" (screen 35) is **informational only** v1 — compute actual bytes, no hard cap, no enforcement. (Revisit if abuse appears.)
**Decision:** ​_______________________________________________

### D-18 🟠 Lab failure-state UX + `rejection_reason` codes
**Recommended default:** Enumerate `rejection_reason` = {virus, too_large, not_pdf, no_text_extracted, quota_exceeded, parse_failed} with a user-facing message + retry/manual-entry CTA for each. The **"scanned-image PDF has no extractable text"** case is the most common real failure (no OCR by design) — give it explicit copy. Define the screen state for each.
**Decision:** ​_______________________________________________

---

## Before P8 / P9a / P9b

### D-19 🔴 Notification scheduling model (architectural)
**Conflict:** Screens imply per-user, per-category local send times (8 PM check-in, 8 AM med, 2-days-before-period) + quiet hours — incompatible with a single 08:00-Madrid job.
**Recommended default:** Upgrade dispatch to a **frequent tick** (e.g. every 15 min) that evaluates each user's local time + quiet hours (depends on D-12); keep the nightly job only for non-time-critical batch work. If you'd rather minimize v1 scope: ship a **single daily batched digest** and make the per-time UI display-only (worse UX). Recommend the tick.
**Decision:** ​_______________________________________________

### D-20 🔴 Doctor-report sharing: Link / Email
**Conflict:** Screen 30 offers "Link" (30-day expiry) + "Email"; architecture `§A` locks **"no server-side sharing, no signed URLs."**
**Recommended default:** **PDF download only** v1 — grey out Link/Email, drop the "expires in 30 days" copy (matches the locked decision). If Email is wanted, route through the **OS share sheet** (no server SMTP subprocessor). Defer server-side links to phase 2.
**Decision:** ​_______________________________________________

### D-21 🔴 Data export: CSV + delivery channel
**Conflict:** Screen 35 offers JSON **and** CSV with direct in-app download; `§F` specifies JSON+PDF zip via 7-day emailed signed URL only.
**Recommended default:** Ship the **JSON+PDF zip via signed URL** per architecture; **defer CSV to phase 2** (or, if wanted now, define its per-domain column schema). Reconcile the screen.
**Decision:** ​_______________________________________________

### D-22 🟠 Report specifics (range, sections, identity header, retention)
**Recommended default:** Range enum {one_month, three_months(default), six_months, all}, rolling-window ending at generation ("all" = earliest data → today). Sections {cycle, hormones, symptoms, body_map, medication, activity}. Patient header **anonymized by default** ("PATIENT · N CYCLES") with an opt-in to include name/DOB. `reports.expires_at` = generated_at + 30 days; MinIO lifecycle deletes the object then. Empty sections render a heading + "No data recorded in this period."
**Decision:** ​_______________________________________________

---

## Eligibility (clinical-flavored but a product call) — affects P4a / P7b

### D-23 🔴 v1 eligible population & sex capture
**Conflict:** No screen captures sex; the cycle engine + hormone ranges assume a menstruating female of reproductive age; a user on a **cycle-suppressing therapy the app tracks (Dienogest)** may have no detectable phases.
**Recommended default:** v1 = **menstruating individuals of reproductive age**; **don't capture a sex field** (seed only `female`/`any` hormone ranges); detect "no clear cycle" (e.g. on continuous hormonal suppression, peri/post-menopause, pregnancy) and **degrade gracefully** to a low-confidence / "cycle phases unavailable" state rather than showing a wrong phase. Confirm with the clinical advisor (clinical-ask C-12).
**Decision:** ​_______________________________________________

---

## Adopted pre-P1 (recorded r13 — these predate the numbering above)

### D-24 🔴 Password policy (end users)
**Recommended default:** min 12 / max 128 chars, any Unicode, block breached passwords, no forced rotation. Keycloak enforces what it can natively; server-side validation mirrors the 12–128 bounds.
**Decision:** ✅ adopted 2026-06-01 (implemented in P1: server-side 12–128 validation + realm policy; realm raised to `length(12) and maxLength(128) and notUsername and notEmail` in P3c; breached-password blocking = P11, needs a Keycloak provider).

### D-25 🔴 Consent capture at onboarding
**Recommended default:** `POST /onboarding/start` persists a versioned consent record (policy version string + timestamp); text/version can be a placeholder until legal L-01/L-02 land, but the field exists from day one.
**Decision:** ✅ adopted 2026-06-01 (implemented in P1: `consent_records` row written at onboarding; FK survives crypto-shred as legal proof).

---

### How to use
Fill each **Decision** line (or just `✅` to accept the default). I'll then (1) update `ARCHITECTURE.md §A` + the gap register status, and (2) make sure each phase's plan tasks reflect the resolved value. Anything left blank stays a blocker for its phase. **IDs are append-only — never renumber existing decisions** (cross-references live in the plan, STATUS blocks, and `ARCHITECTURE.md §A`).
