# Lumen — Gap Register (business rules & definitions to resolve before each phase)

> **Produced 2026-05-31** by a domain-by-domain audit of the 37 screen HTML files against `docs/ARCHITECTURE.md` and `CLAUDE.md` (10 domain auditors + completeness critic). Companion to [`../2026-05-31-build-strategy-design.md`](../2026-05-31-build-strategy-design.md) and the [build runbook](../../RUNBOOK.md).
>
> **How to use this:** before starting any phase, resolve that phase's **BLOCKER** entries (a session must not invent clinically/legally loaded values). Items are tagged with the earliest phase that needs them and a resolution route: `formalize-from-screens` (extract now, cheap), `decide-now-with-default`, `needs-product-owner-decision`, `needs-clinical-source`, `needs-legal-source`. Part 1 is the per-domain consolidated inventory (~88 gaps); Part 2 is the cross-cutting additions (X1–X20) the per-domain pass under-covered — including the **age/eligibility gate** and the **locale-convention** cluster. Record resolutions in `ARCHITECTURE.md §A` and the living plan's §4 decision log as they land.

---

# Part 1 — Consolidated per-domain gap inventory

# Lumen — Consolidated Gap Inventory (Missing Business Rules & Definitions)

**Source:** 10 domain audits cross-checked against `docs/ARCHITECTURE.md`, `CLAUDE.md`, and the 37 screen HTML files.
**Purpose:** Surface every product/clinical/domain fact a developer needs but that is not yet specified, tagged to the earliest build phase that needs it, with a resolution path. Overlapping items deduped into single canonical entries.

---

## 1. Executive summary

The 10 audits surfaced **~130 raw gap items**. After deduplication (many items recur across domains — the confidence formula appears in 3 audits, phase detection in 3, the intensity-scale conflict in 3, the report Link/Email sharing contradiction in 2, consent capture in 2), this consolidates to **88 distinct gaps**:

- **26 BLOCKERS** — must be resolved before their phase can start. They cluster heavily at **P1** (auth/legal foundations), **P4a** (the data-shape contradictions), and **P6** (the entire clinical inference engine).
- **41 MAJOR** — resolve-before-or-stub; safe to start the phase with a documented default but wrong if guessed silently.
- **21 MINOR** — defaultable, mostly copy/i18n/UX detail.

### The 5 most important things to resolve first (all clinically- or legally-loaded)

1. **The clinical inference engine spec (P6) — the single biggest risk surface.** Phase-boundary detection, ovulation estimation, cycle/period-length estimators, the 0–100 confidence formula + per-factor curves, the missing-data card catalog, the insights-hub statistical methods, and lab phase-coverage all converge on **one undefined deterministic ruleset** stored in `ref_insight_rule`. ARCHITECTURE says "deterministic C# rules" but enumerates *no* rule, weight, threshold, or boundary. Every phase-colored UI, every confidence %, every insight string, and the doctor report all read from this. **This must NOT be guessed by an implementer** — it needs an authoritative clinical source plus product-owner sign-off. It can be sourced during P3–P5 but must be locked before P6.

2. **Hormone reference ranges + unit whitelist (P7b).** `ref_hormone_range` low/high values per hormone/sex/phase, and the per-hormone accepted-unit whitelist with conversion factors, **appear nowhere** (no screen shows a numeric range). The LLM parse validation, the 1.5× widening, and the screen-19 needs-review flag are all impossible without them. Endocrine reference intervals must come from a clinical source, not invention.

3. **The intensity-scale contradiction (P4a) — a direct spec-vs-UI conflict.** ARCHITECTURE + CLAUDE.md say `symptoms.intensity smallint 1..5`; **every screen shows 0–10** (pain "3/10", body-map slider "7"). Picking wrong forces a schema migration plus client rework and corrupts all P6 pain-by-phase math. Must be decided before any symptom write is built.

4. **Auth + legal foundations (P1).** Password policy (Keycloak realm config), GDPR consent capture at signup (no consent gate exists on any screen, yet the app processes special-category health data), the privacy policy + subprocessor disclosure, MFA decision, and Apple/Google social-login scope. These block the very first build phase and several need legal sign-off, which has lead time.

5. **The data-shape gaps where the UI collects fields the schema can't store (P4a/P5).** Symptom TYPE/TRIGGERS/RELATED chips, body-map per-point coordinates + front/back side, the "How does your body feel?" tags, activity "energy after", medication category/effectiveness-rating/"N/10" — the UI captures these but `ARCHITECTURE.md §D` has no column for them. Each needs a model decision before the module is built or the data is silently dropped.

---

## 2. BLOCKERS BY PHASE

These MUST be resolved before the listed phase starts. Ordered P1 → P9b.

### P1 — Auth + encryption spine

**B1. Password policy (Keycloak realm).**
*Why:* P1 configures `realm-lumen.json`; the client must validate and surface rules. A weak default on a medical app is a compliance risk.
*Screens imply:* Screen 2 shows a bare password field (`••••••••`), no strength meter, no confirm field, no rules text. Nothing specifies length/complexity.
*Resolution:* **decide-now-with-default** — adopt a concrete baseline (suggest min 12 chars, allow all Unicode, no forced rotation, block top breached passwords), encode as the realm password-policy string. Product-owner confirms minimum.

**B2. GDPR consent capture & versioning at signup.**
*Why:* GDPR Art. 9 processing of health data requires an explicit lawful-basis/consent record. No consent checkbox exists on any onboarding screen, and the data model has no consent entity. `POST /onboarding/start` must persist consent (policy version, timestamp).
*Screens imply:* Screen 2 has Name/Email/Password + Continue only; subhead "Your data is encrypted and yours alone." Terms/Privacy appear only as post-hoc links on screen 37. No "I agree" gate anywhere.
*Resolution:* **needs-legal-source** (required consents + text) **+ decide-now** — add a consent gate on screen 2 and a consent-record table (policy version, timestamp, locale). Must precede P1.

**B3. Social login (Apple/Google) scope & account-linking.**
*Why:* Screen 2 prominently offers "Apple · Google". P1/P3b must either wire Keycloak identity brokering (with Apple "Hide My Email" relay handling, account-linking against `email_hash`, DEK provisioning for brokered identities) or the button is dead. Apple/Google are not in the ARCHITECTURE subprocessor list.
*Screens imply:* Screen 2 button labelled exactly "Apple · Google" under "or continue with". ARCHITECTURE mentions only Keycloak email/password + future clinic SSO.
*Resolution:* **needs-product-owner-decision** — confirm in/out for v1 (if in: Keycloak IdP config + Apple/Google OAuth app registration + privacy-policy subprocessor entries; Apple required if Google offered on iOS). Default recommendation: defer, email/password only.

**B4. Definition of "onboarding complete" + mandatory vs skippable steps.**
*Why:* `POST /onboarding/complete` and the auth/routing gate must know what sets `users.onboarding_completed_at`. Guessing "all 7 required" may wrongly block users; the dashboard must tolerate missing cycle/baseline data if steps are skippable.
*Screens imply:* Screen 1 "Begin" vs "I already have an account"; screen 7 "Not now" (skip notifications); screen 4 "Edit anytime" implies optionality. ARCHITECTURE has the field but no completion criteria.
*Resolution:* **needs-product-owner-decision** — recommend mandatory = account + last-period date; baseline/goals/hormones/notifications skippable with defaults. Update ARCHITECTURE.

**B5. Default/primary locale for `users.locale`.**
*Why:* Every later notification/report/copy decision inherits this base; `POST /onboarding/start` must populate it. ARCHITECTURE says "Spanish and English at minimum" but never states which is primary or the default. No enum, no default in the data model.
*Screens imply:* All UI copy is English-only; no language selector exists on any screen. So EN is the *design* language but the *product* primary locale is unconfirmed (ES requirement comes only from ARCHITECTURE §I, and hosting is EU-only).
*Resolution:* **needs-product-owner-decision** — pick primary locale (likely es-ES given EU hosting + endo-community positioning), define `users.locale` enum, default-from-device-with-fallback. Lock in ARCHITECTURE §A.

> *Note:* MFA/TOTP requirement (severity major, not blocker per the auth audit) and email-verification flow also land at P1 — see Major section. They are decision-needed at P1 but the realm can ship with a documented default, so they're not hard blockers.

---

### P4a — Backend Onboarding-rest + Cycle + Symptoms

**B6. Pain/intensity scale: 0–10 vs 1–5 (THE contradiction).** *(deduped across symptoms + inference + cycle audits)*
*Why:* Direct spec-vs-UI conflict. `symptoms.intensity smallint 1..5` (ARCHITECTURE §D, §A body-map decision, CLAUDE.md) vs **every screen** showing 0–10. Wrong choice = schema migration + client rework + corrupted P6 pain math. Also must reconcile with `cycle_day_logs.mood/energy/libido` scales and the insights-hub "Avg 0–9" axis.
*Screens imply:* Quick check-in pain row 0–9 buttons, "None"/"Worst"; body-map slider "7"/70%; dashboard "Pain today 3/10"; day-detail "Pelvic pain 3/10", "Bloating 5/10"; insights-hub "Pain by phase · Avg 0–9".
*Resolution:* **needs-product-owner-decision** — screens strongly imply 0–10 for pain. Then update ARCHITECTURE §D/§A and CLAUDE.md to the chosen range, document min/max and whether 0 is valid, and confirm whether non-pain symptoms (bloating/nausea) share the same scale (day-detail "5/10" implies yes).

**B7. Symptom region enum (canonical codes + labels).**
*Why:* `symptoms.region` is the primary storage dimension, day-detail rendering key, and the body-map heatmap reconstruction contract. §A/§D say "fixed region enum, hard-coded in code" but list **no members**. Invented codes become breaking migrations.
*Screens imply:* Symptom form (12) LOCATION chips: "Lower abdomen", "Pelvis", "Lower back", "Legs" — the only concrete region labels anywhere. Body map (13) has tappable points but no named regions in markup.
*Resolution:* **formalize-from-screens** for the 4 shown as a seed, then **needs-product-owner-decision** for the FULL set (the 4 read as illustrative, not exhaustive for endo — likely also bowel/rectal, bladder, vaginal, chest/diaphragm, shoulder for referred pain). Reconcile symptom-form LOCATION chips with body-map tappable regions into one shared enum.

**B8. `symptoms.region` nullability / "unspecified" member.**
*Why:* The quick check-in records pain with no location control. If `region` is NOT NULL with no "unspecified" member, quick-logged pain cannot be stored — a hard constraint every insert path depends on.
*Screens imply:* Quick check-in (9) saves a pain value with zero location UI; symptom form (12) has no "none" option.
*Resolution:* **decide-now-with-default** — add an explicit `unspecified`/`general` enum member (keeps heatmap logic total) or make `region` nullable. Record in §D.

**B9. Body-map storage contract: snap-to-region vs raw coordinates, plus `side`.**
*Why:* §A says heatmap "reconstructs coordinates client-side" from the fixed region enum (implies snap-to-region), but screen 13 lets users place precise multi-point taps with per-point intensity, front/back toggle, and zoom. `symptoms` has no x/y, no side column. Either the contract or the schema is missing.
*Screens imply:* Body map: "Front"/"Back" toggle, "3 points placed", three SVG circles at distinct cx/cy with varying radius/opacity, per-point "INTENSITY AT SELECTED POINT" = 7, zoom 100–300%.
*Resolution:* **decide-now-with-default + needs-product-owner-decision** — default: snap each tap to nearest region centroid, one `symptoms` row per (region, side, intensity), add a `side` field ('front'/'back'). If precise coordinates are a real product requirement, add normalized x,y columns. Update §D and the §A body-map decision either way.

**B10. Symptom TYPE / quality taxonomy + storage.**
*Why:* Form captures pain quality but `symptoms` has no column for it. Folds silently into notes (losing P6 queryability) unless a structured field is decided.
*Screens imply:* Symptom form TYPE chips: "Cramping", "Sharp", "Burning", "Dull" (multi-select).
*Resolution:* **needs-product-owner-decision** on the canonical list (4 shown = starter set), then **formalize** — add a `pain_types` array/junction to the symptoms contract and §D, or explicitly decide it folds into notes.

**B11. Mood scale: ordered enum + int↔label mapping (`cycle_day_logs.mood`).**
*Why:* Stored as smallint but screens show 4 labeled glyphs with no numbers. Guessing order/count breaks data consistency and the P6 mood trend.
*Screens imply:* Quick check-in mood grid: "Low" (◔), "Tired" (◐), "Steady" (◑), "Bright" (●) — glyph progression implies ordinal.
*Resolution:* **formalize-from-screens** for the 4 labels, **needs-product-owner-decision** to lock the ordinal mapping (e.g. Low=1…Bright=4). Note "Tired" reads more like energy than mood — see B12.

**B12. Energy scale + its separation from mood.**
*Why:* `cycle_day_logs.energy` is a distinct smallint, but the quick check-in shows only a "Mood" control whose options include "Tired" (an energy concept). Can't tell whether energy is captured by a distinct control (absent on screen 9) or conflated with mood — determines whether `energy` is even populated.
*Screens imply:* Dashboard "Energy / Low / Typical for phase"; day-detail "Tired · steady mood" (energy=Tired, mood=steady); quick check-in has NO separate energy control.
*Resolution:* **needs-product-owner-decision** — resolve the mood/energy modeling (is the grid actually energy? split into two controls?), define energy's ordered labels + int mapping, and specify which screen writes `energy`.

**B13. Quick check-in payload + what it writes.**
*Why:* `POST /checkin/quick` and `POST /symptoms` are separate endpoints with no defined payloads. The boundary between quick (9) and full (12) determines required fields and whether a quick check-in writes a `symptoms` row, a `cycle_day_logs` row, or both.
*Screens imply:* Quick check-in captures exactly Pain (0–10) + Mood (4-way); subtitle "15 seconds. Add detail later." Full form captures Location/Type/Triggers/Related.
*Resolution:* **formalize-from-screens** — quick = {pain 0–10, mood} writing pain to `symptoms` (region=unspecified per B8) and mood to `cycle_day_logs`; then **needs-product-owner-decision** to confirm and write both request schemas into ARCHITECTURE.

**B14. Goal enum (codes + labels).**
*Why:* `POST /onboarding/goals` must persist a defined set; the dashboard/missing-data logic keys off goals ("Shapes your dashboard"). Free strings orphan on relabel.
*Screens imply:* Screen 5 lists exactly 5: "Manage symptoms", "Understand my hormones", "Plan for fertility", "Prepare for appointments", "Just curious" (first two pre-selected), each with a description.
*Resolution:* **formalize-from-screens** — freeze these 5 as a code-level enum (e.g. `manage_symptoms`, `understand_hormones`, `plan_fertility`, `prepare_appointments`, `just_curious`) with screen labels/descriptions as seed copy. Product-owner confirms static vs admin-editable.

**B15. Screen-3 cycle-setup has no home endpoint.**
*Why:* The Onboarding module lists start/baseline/goals/hormones/notifications/complete but **no `/onboarding/cycle`**, yet screen 3 (Step 3 of 7) collects last-period date, avg cycle length, regularity. P4a cannot persist this without deciding where it goes; P6 phase detection depends on the seed.
*Screens imply:* Screen 3 collects last-period-start (Apr 6, period band days 3–8), avg length chips 26–30 (28 selected), regularity Regular/Somewhat/Irregular.
*Resolution:* **decide-now-with-default** — fold into `/baseline` or add `POST /onboarding/cycle`; persist last-period as a `cycle_events` period_start row + avg length + regularity on cycle settings. Update ARCHITECTURE.

**B16. Hormone `hormone_code` enum + label reconciliation (Estrogen vs estradiol).** *(deduped across hormones + onboarding audits)*
*Why:* The code is a literal string in the LLM strict-JSON schema, the validation whitelist, three DB tables (`lab_result_drafts`, `lab_results`, `ref_hormone_range`), and the matview key. The schema uses `estradiol` but every screen displays "Estrogen"; if code is `estradiol` while seed/UI use "estrogen", validation rejects every estrogen result and the chart key won't join. Same risk for GLP-1/`glp1`. Needed at P4a for onboarding hormone-prefs persistence.
*Screens imply:* Screens 6/16/17/19/33 all display "Estrogen" and "GLP-1"; ARCHITECTURE §E schema uses `estradiol`/`glp1`. Other 6 match.
*Resolution:* **decide-now-with-default / formalize** — adopt code `estradiol` (clinically correct analyte) with display label "Estrogen"; create one authoritative hormone reference table `{code, display_label, category, color, display_unit}` mapping Estrogen→estradiol, GLP-1→glp1. Document in §E and a shared constants file.

---

### P5 — Body + Activity + Treatment

**B17. `body_metrics.metric` enum (closed set) + BMI derived-vs-stored.**
*Why:* §D defines `metric enum (weight_kg, waist_cm, etc.)` — `etc.` is undefined. The DB enum, `POST /body/entry` validation, form fields, and calendar selector chips all diverge without the closed set.
*Screens imply:* Calendar (22) chips "Weight", "BMI", "Body fat"; entry form (23) collects WEIGHT "60.4 kg", BODY FAT "24.1 %", WAIST "71 cm". BMI appears only as a view, never an input → derived from weight + profile height.
*Resolution:* **formalize-from-screens** — enum {weight_kg, body_fat_pct, waist_cm}; BMI = computed read-model (weight_kg / height_m²), not stored. Product-owner confirms the closed set before adding any metric.

**B18. Canonical unit per metric + metric-only (no imperial).**
*Why:* `value_enc` is a single encrypted scalar with no unit column, so the canonical storage unit must be fixed before any write. ARCHITECTURE never states whether lbs/inches are supported.
*Screens imply:* Every body screen is metric-only (kg/cm/%); grep across all 38 screens found zero imperial terms; no unit-toggle control anywhere.
*Resolution:* **decide-now-with-default** — store weight_kg (kg), waist_cm (cm), body_fat_pct (0–100%); ship metric-only v1. Flag as ASSUMPTION (imperial display is a common later request).

**B19. "How does your body feel?" tag set + storage (no field exists).**
*Why:* Screen 23 collects body-feel tags but `body_metrics` has only metric/value/source/measured_at — **no column** for them. Cannot persist what the form collects without a model decision.
*Screens imply:* Screen 23 chips: "Bloated", "Light", "Heavy", "Tender" (multi-select, Bloated+Tender shown).
*Resolution:* **needs-product-owner-decision** — confirm the closed list and a storage shape (recommend `body_feel_tags` jsonb/varchar[] on the entry). Decide whether tags attach to a body entry or are mini-symptoms.

**B20. `activity_entries.activity_type` enum.**
*Why:* §D lists the column with no values; `POST /activity/entry` validation, chip UI, and per-type rollups all need it.
*Screens imply:* Screen 25 TYPE chips: "Walk", "Yoga", "Strength", "Run", "Swim", "Pilates", "Other" (exactly 7).
*Resolution:* **formalize-from-screens** — enum {walk, yoga, strength, run, swim, pilates, other}; **needs-product-owner-decision** only on whether "Other" captures free-text (would need an extra label column).

**B21. `activity_entries.intensity` ordinal mapping.**
*Why:* smallint with no mapping; client and server disagree on what intensity=2 means.
*Screens imply:* Screen 25 INTENSITY chips: "Gentle", "Moderate", "Intense".
*Resolution:* **formalize-from-screens** — smallint 1..3 {1=gentle, 2=moderate, 3=intense}. Document that this differs from symptoms' scale.

**B22. Activity "energy after" field (no field exists).**
*Why:* Screen 25 collects "Energy after" and screen 24 aggregates "Avg energy 7.2/10" — must be stored and rolled up, but `activity_entries` (§D) has no such field.
*Screens imply:* Screen 25 "ENERGY AFTER — 7/10" slider at 70%; screen 24 "Avg energy 7.2/10".
*Resolution:* **formalize-from-screens** — add `energy_after smallint` (confirm 0–10 vs 1–10) to `activity_entries`; slider default at 7 suggests optional/pre-filled. Confirm required-ness with product owner.

**B23. `ref_medication` seed catalog (clinically loaded).**
*Why:* §D defines `ref_medication(name, form, typical_dose, atc_code)` and P10 must ship a seed migration, but no catalog content exists. `typical_dose` and `atc_code` are clinical; guessing risks surfacing wrong doses in a medical app. `add_medication` (P5) has no catalog to autocomplete against.
*Screens imply:* Screen 26 shows real names+doses ("Dienogest 2 mg", "Naproxen 500 mg", "Magnesium glycinate 400 mg") + non-drug "Heating pad 20 min"; screen 27 example "Turmeric capsule 500 mg". Illustrative, not a sourced catalog; ATC codes appear nowhere.
*Resolution:* **needs-clinical-source** — product owner + clinical advisor provide a vetted starter catalog (drug, form, dose ranges, ATC) for endo treatment, seeded via P10 migration. To avoid blocking P5, treat `ref_medication` link as optional/free-text initially (see B24), but the curated seed must precede launch.

**B24. Medication: free-text vs catalog link.**
*Why:* §D says `medications` references `ref_medication`, but screen 27 collects free-text and supports non-pharmacological items ("Heating pad"). Shapes the table columns and `POST /medications` contract.
*Screens imply:* Screen 27 NAME is free-typed; no picker/autocomplete shown; "Heating pad" is a non-drug relief method.
*Resolution:* **formalize / decide-now-with-default** — `medications.ref_medication_id` nullable + `name_enc` always stored; optional catalog match for ATC/dose hints. Confirm non-drug relief items belong in the same table.

**B25. Medication FREQUENCY enum + "Cyclical" semantics + `cron_like`.**
*Why:* Frequency drives whether/how a schedule is created. "Cyclical" (e.g. take during certain cycle phases/days) has no meaning, parameters, or `cron_like` encoding. `PUT /medications/{id}/schedule` (P5) and the P9a dispatcher can't be built correctly without it. The `cron_like` "simple pattern" grammar itself is undefined.
*Screens imply:* Screen 27 FREQUENCY: "Daily", "Cyclical", "As needed" (Daily selected). Screen 26 groups only DAILY / AS NEEDED — "Cyclical" has no display behavior. Time-of-day labels "morning"/"night" + a single "REMIND ME 8:00 AM".
*Resolution:* **needs-product-owner-decision** for "Cyclical" meaning/parameters/display + **decide-now-with-default** for the `cron_like` grammar (e.g. daily@HH:MM, weekly day-list, interval-days; derive "morning"/"night" from reminder_time bucket). Confirm whether multiple daily times are needed in v1.

**B26. `medication_logs.status` behavior (taken/skipped/snoozed) + where the user logs it.**
*Why:* §D enumerates the status enum but not its behavior. "snoozed" implies a follow-up reminder (delay, max snoozes, re-fire) P9a must build; "skipped" vs no-log affects adherence math. `POST /medications/{id}/log` needs to know which statuses the client sends and with what payload — and **no screen shows a take/skip/snooze action at all**.
*Screens imply:* Screens 26/27 show no log action; statuses come solely from ARCHITECTURE.
*Resolution:* **needs-product-owner-decision** — define each status' trigger + payload (snoozed requires `snooze_until`; default snooze 15 min, max 3; is "skipped" explicit-only or auto-derived from missed reminders?). Critically, confirm **where** in the UI the user performs taken/skipped/snoozed (the screen is missing).

**B27. Per-medication "N/10" ratio meaning (effectiveness vs adherence).**
*Why:* Screen 26 displays a bar + "N/10" per medication but the model has no field for it. Ambiguous whether it's adherence, an effectiveness rating, or other. Reports (P8) and the insight card depend on it.
*Screens imply:* "Dienogest 8/10", "Naproxen 7/10", "Heating pad 9/10" + insight "Heating pad is your highest-rated relief"; screen 27 "Rate effectiveness after 2 weeks of use" → strongly implies **effectiveness rating (1–10)**.
*Resolution:* **formalize / needs-product-owner-decision** — adopt N/10 as a user-entered effectiveness rating; add a field/table; define the window/aggregation and bar-color rule (daily=sage, as-needed=accent). Confirm whether adherence is also tracked separately.

---

### P6 — Inference engine + matviews + insights

This is the densest blocker cluster. All of these read from or feed `ref_insight_rule` and the matviews.

**B28. Phase-detection algorithm (the 4 boundaries).** *(deduped across cycle + inference audits)*
*Why:* Core of the Cycle module. `RecomputeInsightSnapshotJob`, `mv_cycle_phase_summary`, calendar coloring (10), day-detail chip (11), dashboard hero (8), confidence input, lab phase-coverage, body/activity phase bands — **all** depend on it. ARCHITECTURE says "deterministic C# rules" but specifies no rule. Clinically loaded (follicular/ovulatory/luteal boundaries).
*Screens imply:* Calendar (10) colors a 28-day cycle: menstrual days 3–7, follicular 8–13, ovulatory 14–16, luteal 17–30; dashboard "Luteal phase · Day 22 of 28". These are **illustrative layouts**, not stated rules.
*Resolution:* **needs-clinical-source** — define boundaries from an authoritative source (e.g. luteal = fixed ~14d back-counted from next predicted period; ovulatory window centered on estimated ovulation; menstrual = period_start..period_end; follicular = period_end..ovulation), product-owner sign-off, encode as `ref_insight_rule` params (not hard-coded magic numbers).

**B29. Ovulation estimation method + ovulatory-window width.**
*Why:* Ovulation day anchors the ovulatory phase and the follicular/luteal split. Screen 14 lets the user edit "OVULATION START · Day 14", proving the engine computes it.
*Screens imply:* Screen 14 "EDITING — OVULATION START · Day 14" stepper; calendar shows a 3-day ovulatory band (14,15,16). Whether ovulation = next-period − fixed luteal length (back-count) vs round(length/2) (forward) is not stated; the 3-day width is illustrative.
*Resolution:* **needs-clinical-source** — specify back-count vs midpoint, fixed window width (ovulation ± N), confirm clinically, store constants in `ref_insight_rule`.

**B30. Confidence score formula + per-factor curves + projection.** *(deduped across cycle + hormones + inference audits — appeared in all 3)*
*Why:* A single 0–100 integer in `user_insight_snapshot.confidence`, displayed on screens 8/10 (62%), 20, 21 (32%). Named deliverable of the P6 confidence engine. ARCHITECTURE calls it a "deterministic C# rule" but enumerates **no inputs, weights, scale, or curves**. The projection ("projected 78%") needs a defined target state + the same formula. Clinically/trust loaded.
*Screens imply:* Screen 21 lists 4 factors with illustrative points: "Cycle history (3 cycles) +18%", "Lab studies (1 of 4 phases) +8%", "Daily check-ins (12 days) +6%", "Body-map points (Not started) +0%" → 32%. Screen 20 "32% → projected 78% with full coverage". Numbers look illustrative.
*Resolution:* **needs-product-owner-decision (with clinical review)** — the 4 factors are a strong starting taxonomy; product owner/clinical set the actual point contributions, per-factor curves (linear/capped/stepped), and combination rule. Define "full coverage" (screens imply 4/4 lab phases) for the projection. Seed all weights into `ref_insight_rule.params` so Admin (P10) can edit without redeploy. Verify the screen-21 example numbers are consistent or relabel as illustrative.

**B31. `ref_insight_rule` taxonomy (the `rule_code` registry + per-code params schema).**
*Why:* The single tuning table for the whole inference engine; Admin (P10) CRUDs it. Only one `rule_code` is hinted (LLM daily quota = 10). The P6 engine reads these rows; P10 builds the Admin forms. Without the enumerated codes + param schema, neither can be built. This is the serialization of all the formulas/thresholds below.
*Screens imply:* Nothing names rule_codes; ARCHITECTURE §E only references the LLM quota.
*Resolution:* **needs-product-owner-decision** — define the `rule_code` registry + per-code param schema as the P6 spec is written (confidence weights, phase-boundary params, coverage thresholds, missing-data triggers, insight thresholds, LLM quota). Migration seeds initial rows; Admin edits them.

**B32. Missing-data card catalog (types, triggers, priority, copy, CTAs).**
*Why:* `user_insight_snapshot.missing_data_cards_enc` is jsonb with no schema; `GET /insights/missing-data` and screen 20 render them; `RecomputeInsightSnapshotJob` decides which to emit. Without the catalog, an implementer invents triggers and copy for a clinical app.
*Screens imply:* Only ONE card shown fully (screen 20): tag "Build confidence", title "First study saved", body, "Phase coverage 1/4", "32% → projected 78%", CTA "Add follicular study" / "Maybe later". Studies-library implies a per-phase card ("No ovulatory studies — uploading one boosts confidence"). No other card types enumerated.
*Resolution:* **formalize-from-screens** for the lab-coverage card (screen 20 gives full copy + CTA), then **needs-product-owner-decision** to enumerate the rest (log more cycles, start check-ins, start body map — implied by the 4 confidence factors but never shown) with copy + triggers. Seed as `ref_insight_rule` rows.

**B33. Lab phase-coverage definition + per-lab phase assignment.**
*Why:* Both the confidence "Lab studies 1 of 4 phases" factor and the coverage card depend on assigning each lab to a cycle phase. Studies-library groups by phase, implying automatic assignment from the study date. The mapping rule (study date → phase via the user's cycle) and "covered" definition must be specified. Cross-depends on B28.
*Screens imply:* Studies-library (17): Menstrual·2, Follicular·3, Ovulatory·0, Luteal·2, each study showing a date. Screen 20 "Phase coverage 1/4". Screen 18 user assigns "Cycle phase when taken", auto-detected from sample date.
*Resolution:* **decide-now-with-default** — assign each lab to the phase its `measured_on` falls in (per B28); "covered" = ≥1 confirmed `lab_result` in that phase; lab phase = user-assigned screen-18 value (auto-detected, editable). Seed thresholds in `ref_insight_rule`.

**B34. Insights-hub catalog (metric_codes, statistical method, min-data gates).**
*Why:* `GET /insights/hub` + `mv_insight_metrics` drive screen 28, which shows specific correlation insights with hard numbers, but there's no spec of which insights exist, how each is computed, or the minimum cycles/points before showing. Can't build the matview rollups or the endpoint without the `metric_code` list and per-metric method.
*Screens imply:* Screen 28: "From 3 cycles · updated today"; "Strongest link — Pain peaks 2 days before your period — 87% of cycles"; "Pain by phase" (M 7.2, F 2.1, O 1.4); "Activity vs pain — 30+ min movement → 22% less pain"; "Mood vs estrogen — low-mood days cluster when estrogen drops below 120 pg/mL". All illustrative.
*Resolution:* **needs-product-owner-decision** for the insight-type catalog + copy templates **+ needs-clinical-source** for the statistical method and min-data gates (correlation vs averages, significance/sample gating). Map each to a `metric_code` + `ref_insight_rule` threshold. Soften causal-sounding wording ("22% less pain") — needs product/legal review.

> *Note:* The individual insight rules (Strongest-link strength metric, Activity-vs-pain 30-min threshold, Mood-vs-estrogen 120 pg/mL threshold, the dashboard daily phase-insight copy "gentle movement may help", and the body/activity green-card endo claims like "common with endo") are all **major** sub-items under B34 — each needs clinical sourcing for any numeric threshold or health claim before P6 surfaces it. See Major section.

---

### P7b — LLM lab parse + validate + confirm

**B35. Hormone reference ranges (`ref_hormone_range.low/high` per hormone/sex/phase).**
*Why:* §E step 9 + §D require numeric low/high per (hormone_code, sex, phase_applicability, unit). **No screen shows any numeric range.** Without them the LLM validation has nothing to widen/compare against, and the screen-19 needs-review flag can't be computed. An implementer must NOT invent endocrine intervals.
*Screens imply:* Nothing. Screen 16 chart y-axis 0–300 for Estrogen is illustrative.
*Resolution:* **needs-clinical-source** — endocrinologist/lab-authoritative intervals for all 7 analytes by sex and cycle phase, in the canonical unit. Seed `ref_hormone_range` via migration with `valid_from`. Product-owner signs off; Admin (P10) maintains.

**B36. Per-hormone unit whitelist + conversions + exact casing.**
*Why:* §E step 9 requires "unit must be in the whitelist for that hormone." Without the actual list, validation rejects valid labs or accepts garbage. Labs report the same hormone in different units (estradiol pg/mL vs pmol/L), so a single-unit whitelist rejects conversions. Casing mismatch ("pg/mL" screens vs "pg/ml" schema) silently misses.
*Screens imply:* Screen 33 display units: Estrogen pg/mL, Progesterone ng/mL, LH mIU/mL, FSH mIU/mL, Testosterone ng/dL, Cortisol μg/dL, GLP-1 pmol/L. Screen 19 parsed units match.
*Resolution:* **needs-clinical-source** for accepted alternate units + conversion factors per hormone (**formalize-from-screens** for the 7 canonical display units on screen 33). Pin exact unit-string casing in one place.

**B37. Sex/gender field for range selection — where captured.**
*Why:* `ref_hormone_range` is keyed by sex; §E validation needs the user's sex to pick the row (testosterone especially differs sharply). No hormone/onboarding screen captures sex. The endo focus implies female, but the sex column implies multi-sex support.
*Screens imply:* No screen captures sex.
*Resolution:* **needs-product-owner-decision** — confirm v1 = female-only (sex constant, seed only 'female'/'any') vs capture sex at onboarding. Pin where sex comes from for range resolution.

**B38. Email-verification gate.** *(P1-or-P7b depending on strictness; listed as major)* — see Major.

---

### P8 — Reports

**B39. Clinical/medical disclaimer on every doctor-report PDF.**
*Why:* The PDF is a document a clinician reads; without a disclaimer it could be misread as a diagnostic record (legal exposure). Hard requirement for a GDPR health-wellness product.
*Screens imply:* Neither screen 29 nor 30 shows any disclaimer; PDF mock header is just "Lumen Report / PATIENT · 3 CYCLES".
*Resolution:* **needs-legal-source** — product owner + legal draft the exact disclaimer (ES/EN) as report-template copy in the QuestPDF footer/first page. Do not let an implementer write it.

**B40. Report date-range options + semantics.**
*Why:* `POST /reports/doctor` must interpret a range. Rolling-N-months-ending-today vs cycle-anchored changes every query window and the PDF date header.
*Screens imply:* Screen 29 chips "1 mo", "3 mo" (selected), "6 mo", "All"; screen 30 resolved range "Jan 10 – Apr 10, 2026" → implies a rolling window ending at generation.
*Resolution:* **formalize-from-screens** for the 4 options; **decide-now-with-default** for anchoring (rolling today−N months; "All" = earliest data → today). Encode as enum {one_month, three_months, six_months, all}.

**B41. Report sections taxonomy + request mapping.**
*Why:* The request payload and the QuestPDF section-renderer dispatch need the authoritative section list.
*Screens imply:* Screen 29 INCLUDE: "Cycle history", "Hormone labs (7)", "Pain & symptoms", "Body-map points", "Medication log", "Activity log" (note "(7)" = live lab count).
*Resolution:* **formalize-from-screens** — enum {cycle, hormones, symptoms, body_map, medication, activity}; request carries selected sections + range enum + the dynamic "(N)" count rule.

**B42. Report Link/Email sharing CONTRADICTION.** *(deduped across reports + auth-legal audits)*
*Why:* Direct spec conflict. ARCHITECTURE §A: "In-app PDF download… No server-side sharing endpoint, no signed URLs." Screen 30 offers "Link" (with 30-day expiry) and "Email". `reports.expires_at` exists, hinting link/expiry was anticipated. An implementer either builds an unspecified sharing endpoint (violating the decision) or ships dead buttons (violating the screen). Has privacy implications (who can access shared health data).
*Screens imply:* Screen 30 SHARE AS: "PDF" (selected), "Link" (∞), "Email" (✉); footer "Read-only · link expires in 30 days".
*Resolution:* **needs-product-owner-decision** — (a) MVP = PDF download only, grey out Link/Email, drop the 30-day copy (matches locked architecture); or (b) build a signed-URL link endpoint + auth/expiry + privacy-policy entry + update §A. For Email specifically: route through the OS share sheet rather than a server-side SMTP subprocessor. Default recommendation: (a).

---

### P9b — GDPR export + legal

**B43. Data-export contents/format CONTRADICTION (CSV + download channel).**
*Why:* `BuildDataExportJob` (P9b). Screen 35 offers BOTH a JSON "Full data archive" AND a "Spreadsheet export · CSV", with direct in-app download (⇓). ARCHITECTURE §F specifies only a JSON+PDF zip emailed via 7-day signed URL — no CSV, no direct download. Two contradictory specs.
*Screens imply:* Screen 35 EXPORT: "Full data archive — JSON · everything" (⇓) and "Spreadsheet export — CSV · readable" (⇓); footer "Exports include lab PDFs."
*Resolution:* **needs-product-owner-decision** — decide whether CSV ships v1 (define its column schema per domain) or drop it; decide download UX (emailed signed URL per architecture vs in-app download). Update §F.

**B44. Privacy policy + subprocessor list (actual content).**
*Why:* Screens 36/37 link to a privacy policy; ARCHITECTURE lists subprocessors and GDPR posture but **no policy prose**. The app must ship a real privacy policy before any public/beta launch — legal text that cannot be invented by a developer.
*Screens imply:* Screen 37 LEGAL links (Privacy policy, Terms, OSS licenses) with no content; screen 36 "Lumen has never received a data request"; ARCHITECTURE §F gives the subprocessor table intent.
*Resolution:* **needs-legal-source** — legal/DPO authors the policy (special-category health data, GDPR Arts. 9/13, subprocessor table, Anthropic US SCC transfer, crypto-shred erasure) + Terms of Service. Surface before P9b/launch.

---

## 3. MAJOR (resolve-before-or-stub) — grouped by phase

Safe to start the phase with a documented default; wrong if silently guessed.

### P1
- **MFA/TOTP requirement for end users** — listed as Keycloak capability, no onboarding enrollment screen exists. Decide optional-off-by-default (Face ID app-lock covers device security) vs required. **needs-product-owner-decision.**
- **Email-verification flow + gating + email copy** — screen 2 goes straight to step 3; no "verify your email" screen. Decide whether a fresh account is usable immediately. **decide-now-with-default** (verify-email required action + grace window).
- **Account recovery / forgot-password + data-recovery messaging** — no reset screen; crucially, the DEK is server-held (not password-derived) so a reset must NOT lose data and copy must say so. **decide-now-with-default** (Keycloak reset-credentials flow + reassurance copy).
- **GDPR consent text + lawful basis** — the legal half of B2. **needs-legal-source.**

### P3a / P3b (Flutter foundation + early screens)
- **i18n storage/strategy decision (Flutter gen_l10n .arb + backend .resx)** — must be wired into P3a foundation or every P3b/P4b screen needs rework. ARCHITECTURE defers to milestone 8 but client wiring is needed at P3a. **decide-now-with-default.**
- **"Health info stays on your device" copy is materially inaccurate** (screen 31) — data is server-stored/server-encrypted, lab text goes to Anthropic. Privacy/trust risk; rewrite before P3b screens ship. **needs-legal-source + formalize.**
- **iCloud/Google device-backup toggle scope** (screen 35, shown ON) — contradicts the online-only, server-side model. Confirm out-of-scope-for-v1 or scope it (with privacy-policy entry). **needs-product-owner-decision.**
- **"Anonymous analytics" toggle** (screen 36) — ARCHITECTURE defers PostHog vs none. Decide no-analytics-v1 (hide toggle) vs PostHog (opt-in default OFF + privacy entry). **needs-product-owner-decision.**
- **App-lock/biometric scope** (Face ID, app-switcher blur, disguised "Notes" icon) — client-only, undefined in ARCHITECTURE; defaults + disguised-icon feasibility. **decide-now-with-default.**
- **Session-expired re-auth UX / sign-out-all-devices** — no screen covers it. **decide-now-with-default** (silent refresh; defer sign-out-all to phase 2).

### P4a
- **Cycle/period-length + next-period estimator** (mean vs median, window size, outlier handling) — drives "Day X of Y", luteal back-counting, `mv_cycle_phase_summary`. Screen 32 footer "Predictions retrain after every 3 logged cycles" implies a 3-cycle min-history gate. **decide-now-with-default** (e.g. median of last 6 valid cycles, ≥3 cycles before overriding the screen-3 seed).
- **Valid cycle/period-length bounds** (min/max for validation + outlier rejection) — screen-3 chips only 26–30 but real cycles 21–45. **needs-clinical-source** (e.g. cycle 21–45, period 1–10 days).
- **Variability/regularity definition** + screen-3 self-report → numeric mapping + "±4d" meaning (screen 32 "Irregular ±4d"). **decide-now-with-default** (stddev of recent lengths + threshold bands).
- **"retrain" reconciliation** — screens 14/32 say "retrain the prediction model" / "retrain after every 3 cycles" vs ARCHITECTURE's "deterministic C# rules, no ML." Confirm "retrain" = recompute averages, reword copy. **decide-now-with-default.**
- **`cycle_events.flow_intensity` scale** (smallint, no domain) — no screen shows a flow picker. **decide-now-with-default** (1=spotting,2=light,3=medium,4=heavy).
- **What screen-3/screen-4 persist + seed semantics** (which UI control → which column; does last-period create a `cycle_events` period_start). **formalize-from-screens.**
- **Baseline field set/units/ranges/required-ness** (Age/Height/Weight/endo-status; DOB-vs-age mismatch since model stores `dob_enc`). **decide-now-with-default** (store DOB, metric-only, define ranges, mark optional).
- **Profile editable-fields catalogue** (screen 31: display name, email, age, height, weight, endo status "stage II", diagnosed date, "1 laparoscopy") — `user_profile_enc` only has display_name/dob/bio. Map each field to an entity/column, encrypted vs plaintext. **formalize-from-screens** (+ clinical vocab below).
- **Endo status/staging/surgery controlled vocabulary** (screens 4/31: "Diagnosed/Suspected,undiagnosed/Not applicable", "stage II", "1 laparoscopy") — confirm rASRM I–IV staging + surgery-type list with a clinical reviewer. **needs-clinical-source** for staging/surgery; **formalize** the 3 status values.
- **Symptom TRIGGERS taxonomy + storage** (chips Stress/Intercourse/Food; no field) — intercourse/dyspareunia is a meaningful clinical tag. **needs-product-owner-decision** + formalize.
- **Symptom RELATED taxonomy + entry model** (Bloating/Nausea/Fatigue; do they become their own intensity-bearing rows? — day-detail shows Bloating "5/10"). Clarify the full symptom-type catalog (pain vs non-pain). **needs-product-owner-decision.**
- **`cycle_day_logs.libido` scale + capture location** — column exists, appears on no screen. **needs-product-owner-decision** (confirm v1 inclusion; likely full day form, not quick check-in).
- **Symptom multiplicity/upsert rules** — `cycle_day_logs` one-per-day (UPSERT) vs symptoms many-per-day (append); how a repeat quick check-in's pain is treated. **decide-now-with-default.**
- **`occurred_at` granularity + timezone bucketing** (no time picker; day-centric UI; "After lunch" tag) — bucket to calendar day via `users.timezone`. **decide-now-with-default.**
- **Body-map per-point → rows + intensity sourcing for the form path** (form 12 has no intensity control; intensity comes from quick check-in/body map). **decide-now-with-default.**
- **Goal selection cardinality** (min 1? max? are the 2 pre-selected a real default?). **decide-now-with-default** (multi-select, min 1, no max).
- **Onboarding resumable-state machine** (per-step commit vs commit-on-complete; resume after abandonment) — discrete endpoints imply per-step persistence but no `onboarding_step` field. **decide-now-with-default.**
- **Avg cycle length allowed range** beyond the 26–30 chips (storage/validation 21–45). **needs-clinical-source.**
- **Regularity enum effect** (does it modulate confidence?). **decide-now-with-default + needs-clinical-source.**
- **Default-charted hormones + min-selection** (onboarding screen 6 all 7 ON vs settings screen 33 Testosterone+GLP-1 OFF, and FSH ON in 6 / OFF in 33 — a default conflict). Rule: "hidden hormones still get extracted." **formalize + needs-product-owner-decision** to resolve the onboarding-vs-settings default.
- **Notification category taxonomy + onboarding defaults** (screens 7/34 overlap but differ; label drift "Phase shifts" vs "Phase shift"; lab-ready and missing-data not in either toggle list). **formalize-from-screens** (adopt screen-34 grouping, normalize labels) — *deduped across onboarding + notifications audits.*
- **Locale/timezone capture mechanism** (device-derived at `/onboarding/start` vs explicit pick; no screen collects either). **decide-now-with-default.**

### P4b
- **Goal → dashboard/insight/missing-data mapping** ("Shapes your dashboard" but no concrete binding shown). **needs-product-owner-decision** (or ship goals stored but ungated, refine in P6).
- **Hormone category labels** (Sex/Pituitary/Androgen/Stress/Metabolic — screen 6) as static display metadata. **formalize-from-screens.**
- **Calendar day-marker dots** (screen 10 dots on days 16/19/20, no legend) — define as "day has a logged entry." **formalize-from-screens.**
- **Language-selector surface** (no language row on screens 31/34/37) — confirm device-locale-only (no in-app selector) or add a row. **needs-product-owner-decision.**

### P5
- **Body metric precision/decimal scale** (weight 0.1 kg / 0.2-kg stepper, body fat 0.1%, waist whole cm). **formalize-from-screens.**
- **Body metric valid ranges** (typo/abuse guards, e.g. weight 20–300 kg). **decide-now-with-default** (ASSUMPTION).
- **Body entry cardinality/upsert** (one form saves weight+bodyfat+waist+tags; per-metric rows sharing measured_at; upsert-by-day). **decide-now-with-default.**
- **`activity_entries.duration_min` range/increment** (screen 25 "45 min"; calendar sums "4h 20m"). **decide-now-with-default** (1–1440 min).
- **GET /body/calendar + GET /activity/calendar contract** (month window, metric selector param, returned aggregates: current, cycle-Δ, sessions, total/weekly duration, avg energy, per-phase bars). **formalize-from-screens.**
- **Medication FORM enum** (screen 27 "Capsule"; non-pill "Heating pad") — starter enum + free-text "other". **decide-now-with-default.**
- **Medication CATEGORY enum** (Hormonal/Pain/Supplement; no column in §D). **formalize-from-screens** (add `medications.category`).
- **"active" vs "as-needed" counting** (screen 26 "4 active · 2 as-needed" but only 2 daily shown — doesn't reconcile; screen 34 "2 active"). **decide-now-with-default** (active = active=true AND (end_on null OR ≥today)).
- **start_on/end_on capture + discontinue flow** (screen 27 collects neither; no stop/edit screen exists). **decide-now-with-default** (start_on=today, discontinue sets active=false/end_on=today) — flag missing UI.
- **PRN logging fields** (as-needed trigger "pain"/"cramps", dose-per-event) — for adherence/reports. **decide-now-with-default** (med-level indication v1).
- **Body/activity → cycle-phase overlay + per-phase rollups** (calendars band by phase; insights "+1 kg in luteal", "move 2x more in follicular") — reuse cycle inference output; define aggregations + matview shape. **needs-product-owner-decision** (ties to P6). *Listed at P5 because the contract is needed, computed in P6.*

### P6 (major sub-items; the blockers are B28–B34)
- **Confidence projection target + display bands/nudge thresholds** (is 62% "medium"? hide-below threshold?). **decide-now-with-default / needs-product-owner-decision.**
- **Phase-override semantics + confidence effect** (screen 14 — pin one boundary or the whole cycle? expiry? survives nightly recompute? does it raise/lower confidence?). "retrain" copy must reconcile with deterministic engine. **decide-now-with-default / needs-product-owner-decision** — *deduped across cycle + inference audits.*
- **Period-vs-spotting auto-detection** (screen 32 "Auto-detect period start" ON; when does spotting/flow become a `period_start`?). Clinically loaded. **needs-clinical-source.**
- **Cold-start behavior** (<3 cycles: seed-driven projection at low confidence; empty states for confidence/insights-hub/dashboard). **decide-now-with-default** — *deduped across cycle + inference.*
- **"Next phase to add" recommendation logic** (CTA "Add follicular study"). **decide-now-with-default** (first uncovered phase in cycle order).
- **Per-lab phase auto-detection from sample date** (screen 18; fallback when history insufficient). Reuse B28. **decide-now-with-default.** *(P7a needs the assignment; P6 needs coverage.)*
- **Insight sub-rules** (Strongest-link strength metric + ranking; Activity-vs-pain 30-min threshold + "22% less pain" method; Mood-vs-estrogen 120 pg/mL threshold + low-mood definition; dashboard daily phase-insight "gentle movement may help"; body/activity green-card endo claims "common with endo"). Any numeric threshold or health claim is clinically loaded. **needs-clinical-source** for methods/thresholds/claims; **decide-now** for non-clinical cutoffs stored in `ref_insight_rule`.
- **Pain-by-phase aggregation** (which symptoms = "pain"; averaging method; "Avg 0–9" axis vs the canonical scale from B6). **needs-product-owner-decision.**
- **Dashboard summary-card logic** (pain Δ vs yesterday; "typical for phase" baseline). **decide-now-with-default.**
- **RecomputeInsightSnapshotJob trigger scope** (which writes count: period, symptom, check-in, lab confirm, body-map, activity, phase-override) + "updated today" staleness. **decide-now-with-default** (all trigger debounced recompute).
- **Medication effectiveness-rating capture flow** (screen 27 "Rate after 2 weeks" → implies a scheduled prompt; scale, cadence, storage). **needs-product-owner-decision** (P9a prompt).

### P7a
- **Lab `label`/source field + hormone-summary semantics** (studies-library "Quest panel · Mar 4 — Estrogen, FSH, LH" / "7 hormones"; `labs` table has no name/source column). **formalize + decide-now** (add `labs.label`).
- **Storage-quota model** (screen 35 "28 MB of 200 MB" — real cap? what counts? over-limit behavior? usage endpoint?). ARCHITECTURE has no per-user quota. **decide-now-with-default** (treat as informational, compute actual bytes, no hard cap v1).

### P7b
- **`phase_applicability` enum + range-row resolution order** (sex + assigned-phase exact match → fall back to 'any' → skip-but-flag). **decide-now-with-default.**
- **Strict LLM JSON schema field set** (ref_low/ref_high nullable? per-result `llm_confidence` — `lab_result_drafts` has it but the schema sketch omits it; multiple dates; partial values like "6.?"). **formalize + decide-now** (add the confidence field to §E).
- **1.5× widening math** (widen each bound? interval? behavior at ref_low=0; reject vs flag). **decide-now-with-default** (widened_low=ref_low/1.5 floored at 0, widened_high=ref_high×1.5; outside → needs-review, don't reject the whole lab; worked example in §E).
- **GLP-1 inclusion + range + lab aliases** (metabolic peptide, rarely on hormone panels; pmol/L). **needs-clinical-source.**
- **`measured_on`/sample-date precedence** (user screen-18 date vs LLM-extracted date; bounds; future-date handling). **decide-now-with-default** (user date authoritative; LLM is cross-check).
- **Lab-ready notification toggle/category + ES copy** (not in any screen toggle list; only EN string in §E). **decide-now-with-default** (always-on transactional).
- **Email-verification gate** (if enforced at API access). **decide-now-with-default.**

### P8
- **PDF layout/section order + header/footer + per-section content spec** (QuestPDF is code-as-layout; screen 30 thumbnail + screen 28 insights are the only references). **formalize-from-screens.**
- **Empty-section behavior** (omit vs "No data recorded in this period" vs block). **decide-now-with-default** (render heading + empty-state line).
- **Patient/identity header rules** (screen 30 shows only "PATIENT · 3 CYCLES" — anonymized; real clinician use needs name/DOB; encrypted fields; consent). **needs-product-owner-decision.**
- **Report hormone formatting + ref-range display** (chips "E 248" / "P 1.2" with no units/ranges; clinician needs value+unit+ref-range+out-of-range flag). **formalize + needs-clinical-source** (ranges from B35).
- **Whether the report repeats screen-28 correlation claims** ("estrogen below 120 pg/mL", "22% less pain") in a clinician document — clinically loaded. **needs-clinical-source.**
- **Report PDF encryption + download decryption** (mirror §E lab encryption; `reports/{user_id}/{report_id}.pdf.enc`; GET /reports/{id}/download decrypts in-request). **formalize/architecture** (make explicit so P8 doesn't store plaintext).
- **Report retention/expiry** (`reports.expires_at` nullable, no default; "link expires in 30 days" target ambiguous; MinIO lifecycle for the reports bucket; GDPR minimization). **decide-now-with-default** (30-day object retention).
- **Report-localization** (QuestPDF static strings ES/EN; needs the same resource files as notifications, earlier than milestone 8). **decide-now-with-default.**
- **Summary-statistics source/rounding** (avg cycle length, phase confidence %, lab count, pain avg) — computed by P6, formatted by P8. **formalize** (ensure P6 exposes via matviews/snapshot).
- **Report generation async UX + 5/day limit copy + idempotency** (screen 29 single button; `reports.status` pending/ready/failed; over-limit message; dedupe identical requests). **decide-now-with-default.**

### P9a (Notifications)
- **Scheduling-model reconciliation (THE notifications blocker — listed major per audit, but a hard contradiction).** Per-user/per-category send times (8 PM check-in, 8 AM med, 2-days-before period) + quiet hours, all user-local, are incompatible with the single 08:00 Europe/Madrid Hangfire job. `users.timezone` exists but §A defers per-user TZ. **needs-product-owner-decision** — upgrade dispatch to a frequent tick evaluating per-user local time + quiet hours, OR reduce v1 to a single batched send and make the shown times display-only. *This effectively blocks P9a; treat as a blocker.* — *deduped across notifications + medications audits.*
- **Per-notification trigger rules + timing** (daily check-in 20:00 editable; period-prediction 2-day lead; phase-shift de-dup + interaction with phase-override; medication per-schedule timing; missing-data push vs in-app). **formalize-from-screens** for the timings; the predicted-period date depends on P6.
- **Quiet hours suppress-vs-defer semantics + per-category applicability + default window** (22:00–07:00 editable; do transactional lab-ready bypass?). **decide-now-with-default.**
- **Full bilingual push copy (title+body+interpolation) for every type** — only lab-ready has an EN string; no ES anywhere. P9a "templates" cannot ship without strings. **needs-product-owner-decision.** *(Blocker-grade for shipping P9a copy.)*
- **Server-side vs client-side localization of push bodies** (render from `users.locale` vs send loc-key/loc-args). **decide-now-with-default** (server-side from `users.locale`).
- **Notification de-dup/batching/per-day volume cap** ("Soft nudges only", "never marketing" — but no numeric cap). **decide-now-with-default.**
- **Per-medication reminder enable/disable vs global toggle precedence** (screen 34 master + screen 27 per-med time; where the per-med flag lives). **decide-now-with-default.**
- **Medication-reminder timezone basis + quiet-hours interaction** (a "night" dose could fall in quiet hours; suppress/defer/exempt?). **decide-now-with-default** (ties to scheduling-model decision).
- **OS push-permission + "Allow & finish"/"Not now" semantics** (does "Not now" persist prefs? deny path? token registration timing in `user_devices`). **decide-now-with-default.**

### P9b
- **Data retention periods per category + account-deletion UX** (inactive-account purge, log retention, backup crypto-shred propagation, export-zip 7-day; delete-confirm flow — re-auth? typed confirmation? grace period?). **decide-now-with-default + needs-legal-source.**
- **Terms of Service + OSS license attribution + support channel + help content** (screen 37 links, no content). **needs-legal-source** (Terms) **+ decide-now** (support channel) **+ formalize** (auto-generate OSS attribution).

---

## 4. MINOR (defaultable / copy)

Brief — safe to default and refine later.

- **Endo-status enum downstream effect** (likely no v1 computational effect beyond storage) — P4a.
- **Fertility-window definition** (screen 32 toggle, default off; ~6 days ending on ovulation if kept) — P6.
- **`body_metrics.source` / `activity_entries.source` enum + default** (reserve {manual, apple_health, google_fit}, default 'manual') — P5.
- **Dose unit handling** (free-text dose_enc; unit hint list mg/mcg/ml/IU/min) — P5.
- **Custom-medication de-dup vs shared catalog** (v1: per-user free-text, no global enrichment) — P5.
- **Doctor-report "Medication log" section contents** (default OFF) — P8.
- **Report default range + default sections** (3 mo; cycle/hormones/symptoms/body-map ON) — P8.
- **Page-count estimate algorithm** ("Estimated N pages" heuristic) — P8.
- **Height/weight at baseline → body_metrics seed row** — P4a.
- **Notification med-reminder actions/snooze-from-push** (defer action buttons to phase 2; deep-link to log screen) — P9a.
- **Onboarding/notification copy strings + ES translations** (treat on-screen EN as source-of-truth resource files) — P3b/P4b.
- **Symptom/check-in copy strings (None/Worst anchors, mood labels) as i18n source** — P4b.
- **Quick-check-in intensity anchors beyond None/Worst** + shared-scale-for-non-pain confirmation — P4a.
- **Warrant-canary statement** ("never received a data request" — legal owns accuracy/update process) — P9b.
- **"Anonymous analytics" toggle default** (if no analytics, hide it) — P3b (also major above).
- **Notification consent/default toggles + quiet-hours seed** (formalize screen 7/34 exactly) — P9a.

---

## 5. RESOLUTION ROUTING

Every gap bucketed by **how** it must be resolved.

### (a) FORMALIZE-FROM-SCREENS — cheap wins, extractable now

The answer is already on screen; just write it down. **Do these first — they unblock cheaply and reduce the guess surface.**

- Goal enum (5 values + descriptions) — screen 5
- Hormone reference table `{code, label, category, color, display_unit}` + Estrogen→estradiol / GLP-1→glp1 mapping — screens 6/33 + §E (codes); the 7 display units — screen 33; hormone colors — screen 33/CLAUDE.md; categories — screen 6
- Symptom region seed (4 LOCATION chips) — screen 12 *(then PO confirms full set)*
- Mood labels/glyphs (4) — screen 9 *(then PO locks ordinal mapping)*
- `body_metrics.metric` enum {weight_kg, body_fat_pct, waist_cm} + BMI-derived — screens 22/23
- Body metric precision (0.1 kg etc.) — screen 23
- `activity_type` enum (7) + `intensity` 1..3 + `energy_after` — screen 25
- Body/activity calendar response shape — screens 22/24
- Medication CATEGORY enum {hormonal, pain, supplement} — screen 27
- Medication N/10 = effectiveness rating — screens 26/27
- Report sections enum (6) + range options (4) + defaults — screen 29
- PDF layout/section/summary-stat spec — screens 30/28
- Notification category taxonomy + onboarding defaults + quiet-hours window — screens 7/34
- Profile editable-fields catalogue mapping — screen 31
- Calendar day-marker dots = has-logs flag — screen 10
- `*_source` enum defaults — §D
- Onboarding/report/notification EN copy → resource files (source-of-truth)

### (b) NEEDS-CLINICAL-SOURCE — must NOT be guessed; name the source

Medical reference data/rules. **Source type in brackets.** These gate P6/P7b and must be locked before those phases.

- Phase-boundary detection rules (B28) — *[gynecology/reproductive-endocrinology reference; luteal-length convention]*
- Ovulation estimation + window width (B29) — *[same]*
- Period-vs-spotting auto-detection thresholds — *[same]*
- Valid cycle/period-length bounds (21–45 / 1–10) + avg-length storage range — *[clinical reference / standard literature]*
- Regularity → confidence effect (if any) — *[clinical advisor]*
- Hormone reference ranges per hormone/sex/phase (B35) — *[endocrinologist or accredited lab reference intervals]*
- Per-hormone unit whitelist + conversion factors (B36) — *[lab/endocrinology unit standards]*
- GLP-1 range + units + lab aliases — *[metabolic/endocrinology source]*
- Endo staging (rASRM I–IV) + surgery-type vocabulary — *[clinical reviewer]*
- Insight statistical methods + min-data gates + numeric thresholds (Strongest-link, Activity-vs-pain 30-min/22%, Mood-vs-estrogen 120 pg/mL) (B34) — *[clinical + biostatistics review]*
- Endo-claim copy ("common with endo", "gentle movement may help") + report correlation claims — *[clinical sign-off on patient- and clinician-facing health statements]*
- Report hormone ref-range display (formatting formalize, ranges clinical) — *[same as B35]*

### (c) NEEDS-PRODUCT-OWNER-DECISION — the user must choose

Product policy, not a clinical fact and not on-screen.

- Confidence formula factors/weights/curves + projection target + display bands (B30) *(with clinical review)*
- `ref_insight_rule` rule_code registry + param schema (B31)
- Missing-data card catalog beyond the lab-coverage card (B32)
- Insights-hub catalog + copy templates (B34)
- Intensity scale 0–10 vs 1–5 (B6)
- Full symptom region set; symptom TYPE/TRIGGERS/RELATED lists + entry model (B7, B10, P4a majors)
- Mood/energy modeling + libido v1 inclusion (B12, P4a)
- Body-feel tag list + storage (B19)
- Sex capture / female-only v1 (B37)
- Medication: Cyclical semantics, status behavior + log location, effectiveness flow (B25, B26, effectiveness)
- Goal → dashboard mapping (P4b)
- Onboarding-vs-settings default hormone conflict (P4a)
- Body/activity phase rollups + aggregation formulas (P5/P6)
- Social login scope (B3); MFA requirement (P1); onboarding-complete criteria (B4); primary locale (B5)
- Report Link/Email sharing (B42); patient-identity header; report correlation inclusion
- Data-export CSV + delivery channel (B43)
- Storage quota model (P7a)
- iCloud backup scope; analytics toggle; language-selector surface (P3b)
- Full bilingual push copy + missing-data-push-vs-in-app (P9a)
- Scheduling-model reconciliation (P9a — the dispatch redesign vs degrade-to-batched call)
- Report async UX + over-limit + idempotency (P8)

### (d) NEEDS-LEGAL-SOURCE — privacy/consent/retention

- GDPR consent capture text + lawful basis + versioning at signup (B2)
- Privacy policy + subprocessor disclosure + SCC transfer language (B44)
- Terms of Service (P9b)
- Clinical/medical disclaimer on the doctor report (B39)
- Data retention periods per category + delete-confirmation UX (P9b)
- "Health info stays on your device" copy correction (P3b)
- Email-share subprocessor/consent (if Email share kept) (B42)
- Warrant-canary handling (P9b)

---

## 6. Recommendation — when to resolve what

**Resolve the early-phase definitions now, in parallel with P0/P1, because they are cheap and on-critical-path.** Do the (a) formalize-from-screens extractions immediately — they are nearly free and eliminate most of the guess surface for P4a/P4b/P5 (region/mood/metric/activity/medication/notification enums, the hormone code↔label table, goal enum, report sections). In the same pass, get the **legal/(d) and P1 product decisions started** — password policy, consent capture + privacy policy + Terms, MFA, social-login scope, and the "data stays on device" copy correction — because legal text has lead time and these block the very first build phase. Settle the **intensity-scale contradiction (B6) before P4a** since it touches schema + client + P6 math, and decide the data-shape gaps (symptom TYPE/TRIGGERS/RELATED, body-feel tags, activity energy-after, medication category/effectiveness/status) before their P4a/P5 modules so the UI's fields actually have a home.

**The clinical engine and hormone reference data — the (b) needs-clinical-source items — are the long-lead, highest-risk bucket and should be commissioned during P3–P5 but MUST be signed off before their phase:** phase-boundary/ovulation/estimator rules, the confidence formula + curves, the missing-data catalog, and the insights-hub methods before **P6**; the hormone reference ranges + unit whitelist + GLP-1 + sex-resolution before **P7b**. Start the clinical-advisor engagement and the `ref_insight_rule`/`ref_hormone_range` seed-data work early (P3–P5 has slack) so neither P6 nor P7b stalls waiting on a clinician. Defer the genuinely later contradictions to just before their phase — the **report Link/Email sharing (B42)** and **CSV export (B43)** decisions before P8/P9b, the **notification scheduling-model reconciliation** before P9a (but flag it now since it may force a dispatch-architecture change), and the **privacy policy + retention + Terms** before P9b/launch. Net: front-load the screen-formalization and legal/P1 decisions this week; lock the clinical sourcing by end of P5; treat everything else as resolve-at-phase-entry with the documented defaults above.


---

# Part 2 — Cross-cutting additions (completeness critic)

# Completeness Critique — Missing Business-Rule/Definition Gaps

The consolidated inventory (88 gaps) is strong on per-module domain rules. But it is organized by domain/module, and as a result it systematically under-covers **cross-cutting rules that no single domain owns**. Below are concrete additions, using the inventory's field schema. I group them by axis and end with a verdict on which axes are genuinely complete.

## A. Units & measurement system

**X1. Global units policy + the imperial-display question as a PRODUCT decision, not a per-module assumption.**
- whyNeeded: B18 (body) and B22 (activity) each independently default to "metric-only, flag as ASSUMPTION." But this is one cross-cutting product/market decision (EU + likely-Spanish ⇒ metric is safe, but US-format dates on screens hint at a US-leaning design source — see C1). It also governs baseline height/weight (screen 4), profile (screen 31), report rendering (P8), and export CSV column units (B43). Deciding it per-module risks one module shipping a unit toggle and others not. There is no `unit_system` field on `users` and no `value_enc` unit column, so if imperial is ever wanted it is a schema change across Body, Activity, Profile, and Reports at once.
- neededBeforePhase: P3a (theming/foundation owns the formatting layer + a possible `unit_system` preference) so P4a/P5/P8 inherit it
- severity: major
- recommendedResolution: needs-product-owner-decision — make ONE explicit decision "metric-only v1, no imperial toggle" and record it in ARCHITECTURE §A as a locked row; add a reserved `users.unit_system` enum default `metric` so a later imperial display needs no migration. Replace the three scattered per-module ASSUMPTIONs with this single reference.

## B. Date / time / timezone & week-start conventions (LARGELY MISSING from inventory)

The inventory touches timezone only narrowly (occurred_at bucketing B-major in P4a; notification scheduling P9a). It misses the formatting/convention layer entirely.

**X2. Week-start convention (Sunday vs Monday).**
- whyNeeded: Screen 10 and screen 3 calendars render the weekday header as `S M T W T F S` — **Sunday-first** (US convention). The product is EU-only and likely Spanish-primary, where **Monday-first** is the norm (ISO-8601 / es-ES). Every calendar grid (screens 3, 10, 22, 24), the cycle-day mapping, and any "this week" rollup (screen 24 "This week 2h 10m") depend on which day starts the week. An implementer copying the screen ships Sunday-first to EU users. This is not owned by cycle, body, or activity alone — it is a global locale convention.
- neededBeforePhase: P3a (the date/calendar widget layer is built once in the Flutter foundation)
- severity: major
- recommendedResolution: needs-product-owner-decision — pin week-start to locale (Monday for es-ES/en-GB) and correct the screen mockups, OR keep Sunday-first as an explicit choice. Drive it from `users.locale`; document in ARCHITECTURE §A. Also defines "week" boundaries for the screen-24 weekly-duration rollup.

**X3. Date and time display format + 12h vs 24h clock.**
- whyNeeded: Screens use US-style long dates ("Thursday, April 9", "April 7", "April 2026") and **12-hour clocks** ("8:00 AM", "8:00 PM", "10 PM – 7 AM"). EU/Spanish convention is "9 de abril", DD/MM, and a 24-hour clock ("20:00", "22:00–07:00"). This affects every screen with a date/time, the doctor-report PDF date header (B40 resolves the range but not its format), notification copy ("2 days before"), and quiet-hours display. P8's "Jan 10 – Apr 10, 2026" header format is undefined for ES. The inventory's B40 only resolves range *semantics*, not *formatting*.
- neededBeforePhase: P3a (formatting layer); affects P8 report header and P9a notification copy
- severity: major
- recommendedResolution: decide-now-with-default — format all dates/times via `users.locale` (ICU `intl`); default es-ES ⇒ 24h clock + "d 'de' MMMM" dates. Treat the on-screen US formats as English-mockup artifacts, not the spec. Record the canonical format rule once.

**X4. Authoritative "today"/day-boundary rule and timezone source — promoted to a shared cross-module rule.**
- whyNeeded: The inventory has a P4a-major item for symptom `occurred_at` bucketing and a separate P4a-minor for locale/TZ capture, but the *same* day-boundary rule silently governs Cycle ("Day 22 of 28"), the body/activity daily upsert (B-items in P5), medication "due today" (B25/P9a), the "updated today" insight staleness (P6), report ranges (P8), and export. There is no single definition of "what calendar day is it for this user, and in which timezone." `users.timezone` exists but §A defers per-user TZ, while the nightly job is fixed to Europe/Madrid — so "today" for a non-Madrid user is undefined across ALL these reads.
- neededBeforePhase: P4a (first day-bucketed write); blocks correct behavior in P5/P6/P8/P9a
- severity: major
- recommendedResolution: decide-now-with-default — define one helper: user-local calendar day computed from `users.timezone` (captured from device at `/onboarding/start`, default Europe/Madrid), used uniformly for all day-bucketing, "today," and "this week." This is the single dependency the P9a scheduling-model decision and the symptom-bucketing item both inherit; state it once rather than re-deriving per module.

## C. Language / locale defaults

**X5. (Cross-check) Primary locale is captured (B5) but the EN-mockup-vs-ES-product mismatch is not flagged as a content-audit obligation.**
- whyNeeded: B5 resolves the *default locale value*. But the inventory treats all on-screen English copy as the canonical "source-of-truth resource strings" (Resolution Routing (a), and the minor i18n items). If the product primary is es-ES, then English copy is a *translation target*, not the source — and the US date/time/week-start conventions baked into the mockups (X2/X3) are wrong, not canonical. The inventory's instruction to "lock the on-screen English into resource files as source" would propagate US conventions into the ES product. Someone must own a one-time copy/convention audit.
- neededBeforePhase: P3b (before screens are wired and strings frozen)
- severity: minor
- recommendedResolution: formalize + needs-product-owner-decision — after B5 picks the primary locale, audit the mockups for locale-bound conventions (date order, clock, week-start, decimal separator — see X6) and treat English strings as one locale among two, not the master. Fold into the i18n strategy decision (P3a).

**X6. Decimal/number separator and input parsing (NOT in inventory).**
- whyNeeded: Spanish/EU locale uses a **comma decimal separator** ("60,4 kg", "24,1 %") and period thousands; the screens show period decimals ("60.4 kg", "24.1 %", body fat "24.1", weight stepper 0.2). This affects every numeric *input* (body metrics B17/X-precision, dose value, lab values on screen 19, activity duration) and *display*. An es-ES user typing "60,4" must parse correctly; the server stores a canonical numeric. No rule exists for input locale parsing vs canonical storage.
- neededBeforePhase: P3a (input formatting/parsing layer) / P4a (first numeric write validation)
- severity: major
- recommendedResolution: decide-now-with-default — store all numerics canonically (period decimal, no grouping) in the API contract; parse/format at the client per `users.locale`. State that API payloads are always locale-neutral. Prevents silent corruption of body/lab/dose values for ES users.

## D. Age / eligibility constraints (ENTIRELY MISSING from inventory)

**X7. Minimum age / age-of-eligibility gate and parental-consent posture.**
- whyNeeded: This is a **special-category health-data** app processing menstrual/sexual-health data (libido, intercourse triggers, fertility). GDPR sets the digital-consent age at 16 (Member States may lower to 13; Spain = 14). There is **no age gate anywhere** in onboarding (verified: no "over 18 / must be / guardian / minimum age" copy in any screen; screen 4 collects age "29 yrs" purely to personalize ranges, with no eligibility check). Without a defined minimum age and a block/parental-consent path, the app may unlawfully process a minor's special-category data. This is a hard legal/compliance gap that blocks the consent design at P1.
- neededBeforePhase: P1 (consent capture B2 must encode the age gate)
- severity: blocker
- recommendedResolution: needs-legal-source + needs-product-owner-decision — legal/DPO sets the minimum age (likely 16+, or the per-Member-State age with parental-consent flow) and whether DOB (screen 4) gates account creation. Add an age-eligibility check at signup tied to `dob_enc`/consent. This is distinct from B2 (which captures consent but never mentions age).

**X8. Clinical-population eligibility & sex assumption interaction.**
- whyNeeded: B37 asks where sex is captured and proposes "female-only v1." But "female-only" as an eligibility *constraint* (vs a range-selection key) is undefined: does the app refuse/handle non-female users, trans/intersex users, or post-menopausal/pregnant users (whose cycle inference is invalid)? Cycle phase detection (B28) and hormone ranges (B35) silently assume a menstruating female of reproductive age. No screen states the eligible population.
- neededBeforePhase: P4a (cycle model) / P7b (range selection)
- severity: major
- recommendedResolution: needs-product-owner-decision (with clinical input) — define the v1 target population explicitly (e.g., "menstruating individuals of reproductive age"), how the cycle engine and confidence behave for out-of-population users (pregnant, peri/post-menopausal, hormonal-contraception suppressing ovulation — note screen 26 "Dienogest" *suppresses* cycles, directly breaking phase detection), and reconcile with the sex-capture decision. The contraceptive-suppression case is a concrete clinical contradiction the inventory missed: a user on the very hormonal therapy the app tracks may have no detectable phases.

## E. Shared validation bounds & data-shape rules

**X9. Global notes/free-text field constraints (max length, sanitization, encryption) shared across modules.**
- whyNeeded: `notes_enc` appears on cycle_events, cycle_day_logs, symptoms, activity_entries, and bio_enc on profile. No max length, no validation, no rule about whether notes are searchable (they are encrypted ⇒ not server-searchable). An implementer picks an arbitrary limit per module. Also affects export size (B43 storage quota), report rendering (does a 5000-char note break the PDF layout?), and the LLM (must notes ever be sent to Anthropic? §F says never — but that constraint isn't expressed as a validation rule).
- neededBeforePhase: P4a (first notes field)
- severity: minor
- recommendedResolution: decide-now-with-default — one shared rule: notes max N chars (e.g. 2000), trimmed, stored encrypted, never sent to LLM, rendered truncated in PDF. Apply uniformly.

**X10. Shared timestamp/`occurred_at` future-date & backdating policy across ALL user-dated entries.**
- whyNeeded: The inventory handles measured_on bounds for labs (P7b minor) and symptom occurred_at granularity (P4a). But backdating/future-dating is a shared rule for cycle_events.occurred_on, symptoms.occurred_at, body_metrics.measured_at, activity_entries.occurred_at, and medication start_on/end_on. Can a user log a period_start for next week? A weight for 1990? This affects estimator outlier handling (P4a cycle bounds), matview windows, and report ranges. Undefined per-entity ⇒ inconsistent validation.
- neededBeforePhase: P4a
- severity: major
- recommendedResolution: decide-now-with-default — one rule: no future dates for symptom/body/activity/lab entries (today's local day is max); cycle_events may be backdated within a sane floor; define a global earliest-floor (e.g., account creation minus N years). State once, reference from each module.

**X11. ID, pagination, and soft-delete (`deleted_at`) semantics as a shared API contract.**
- whyNeeded: §D says all user tables have `deleted_at` but no module spec says whether DELETE is soft or hard, whether soft-deleted rows are excluded from matviews/insights/reports/export, or how list endpoints paginate (GET /symptoms?from&to, GET /cycle/calendar, studies-library, medications). Soft-deleted symptoms silently skewing P6 pain-by-phase, or appearing in a doctor report, is a correctness bug spanning every read. The inventory's symptom-multiplicity item (P4a) touches upsert but not delete-visibility or pagination.
- neededBeforePhase: P4a (first list + delete endpoints)
- severity: major
- recommendedResolution: decide-now-with-default — define globally: soft-delete via `deleted_at`, all reads/matviews/reports/export exclude soft-deleted rows; pagination convention (cursor or limit/offset + max page size) for all list endpoints. One shared contract in ARCHITECTURE §C.

## F. Enum value stability / versioning & seed-data provenance

**X12. Enum stability/versioning policy and the in-code-vs-DB-vs-reference-data split.**
- whyNeeded: The inventory defines ~20 enums (region, goals, hormone_code, metric, activity_type, intensity, mood, notification categories, report sections, medication category/form/frequency/status, etc.) but never states the **governance rule**: which enums are hard-coded in C# (region is, per §D), which are DB enums (migration to change), and which are admin-editable reference data (ref_*). §D says "region enum is hard-coded in code, not in DB" but goals/notification-categories/medication-category have no such ruling. This determines whether adding a value is a redeploy, a migration, or an Admin (P10) edit — and whether stored historical values survive a relabel. Without it, every formalize-from-screens enum is built with an unknown change-management cost.
- neededBeforePhase: P4a (first enums committed) — and shapes P10 Admin scope
- severity: major
- recommendedResolution: decide-now-with-default — classify each enum into {compile-time constant, DB enum, admin reference-data} with a stability contract (stored values are stable codes never reused; labels are i18n keys that may change). Record the classification table once; it governs P10's Admin surface.

**X13. Seed-data provenance, versioning, and `valid_from`/`valid_to` semantics for clinical reference rows.**
- whyNeeded: The inventory correctly routes ref_hormone_range, ref_medication, ref_insight_rule, and phase/confidence rules to needs-clinical-source. But it does not require **provenance metadata**: which clinical source each `ref_hormone_range` row came from, citation, who signed off, and how `valid_from`/`valid_to` (already columns in §D) version a range change without corrupting historically-validated labs. A lab validated in March against range v1 must not retroactively flip to "needs review" when an admin edits the range in June. This is a clinical-audit obligation (§A "Clinical safety requires live edits + audit trail") that the inventory's per-row sourcing items don't make explicit.
- neededBeforePhase: P10 (Admin reference-data) — but the schema/contract must be set when ref tables are first seeded (P6/P7b)
- severity: major
- recommendedResolution: needs-clinical-source + formalize — every seeded clinical row carries source citation + sign-off (store in `admin_audit_log` or a provenance column); define that lab validation pins the range version effective at `measured_on`/parse time via `valid_from`/`valid_to`, so range edits are non-retroactive. Resolves the otherwise-undefined meaning of the existing valid_from/valid_to columns.

## G. Accessibility & clinical-disclaimer obligations

**X14. Accessibility baseline (WCAG) as a build requirement.**
- whyNeeded: The inventory has zero accessibility items. A health app for a chronic-pain population (users may have impaired dexterity/vision during flares) needs an a11y baseline: the body-map tap target (screen 13, fine-grained SVG points) and the 0–10 pain slider (screen 9) are accessibility-hostile without alternatives; color-only encoding of cycle phases (screens 8/10) and hormone series (screen 16) fails color-blind users; screen-reader labels for all the icon-only controls (theme toggle, mood glyphs ◔◐◑●, nav). No WCAG target is set, so P3b/P4b build inaccessible UI by default and retrofitting is expensive.
- neededBeforePhase: P3a (foundation/theming sets contrast tokens, focus, text-scaling) and P3b (first real screens)
- severity: major
- recommendedResolution: decide-now-with-default — adopt WCAG 2.1 AA as the target; require non-color cues for phase/hormone encoding, semantic labels for icon controls and mood glyphs, a keyboard/screen-reader path for body-map point entry, and Dynamic Type / text-scaling support. State once in ARCHITECTURE; verify in the P11 polish pass.

**X15. In-app medical disclaimer / "not medical advice" obligation BEYOND the doctor report.**
- whyNeeded: B39 covers the disclaimer on the *PDF report*. But the app itself makes patient-facing health claims and suggestions in normal use — dashboard "gentle movement may help today" (screen 8), body/activity green cards "common with endo" (screens 22–25), insights "30+ min movement → 22% less pain" / "estrogen below 120 pg/mL" (screen 28), confidence "predictions." These are surfaced *in-app*, not just in the PDF, and need a standing "informational, not medical advice / consult a clinician" disclaimer and an emergency-symptoms safety note (severe pain guidance). The inventory routes the *content* of these claims to clinical sourcing (B34) but never requires the *disclaimer wrapper* around the live app surfaces.
- neededBeforePhase: P6 (when insights/suggestions first render) — disclaimer copy authored with B44/B39
- severity: major
- recommendedResolution: needs-legal-source — legal authors a persistent in-app disclaimer (where: onboarding + insights hub + dashboard insight) plus a red-flag/"seek care" safety note for severe symptoms. Bundle with the B39/B44 legal-copy work; do not let an implementer ship health suggestions without it.

**X16. Crisis / red-flag symptom handling rule.**
- whyNeeded: Endometriosis tracking will capture extreme pain (10/10) and symptoms that can indicate emergencies (e.g., acute severe pain, heavy bleeding). The app has no defined behavior when a user logs an extreme value — silently charting "10/10 pain" without any "if this is an emergency, seek care" affordance is a clinical-safety gap for a medical app. No screen shows any such handling.
- neededBeforePhase: P4a (symptom logging) — copy authored with X15
- severity: minor
- recommendedResolution: needs-clinical-source — clinical advisor defines whether/which logged values trigger an in-app safety message (non-diagnostic, "this isn't an emergency service; seek care if…"); product owner places it. Keep deterministic and non-alarmist.

## H. ARCHITECTURE §H/§I and §D implications the inventory under-covers

**X17. The §A "Per-user TZ deferred" decision directly contradicts SIX screen behaviors — flag as an architecture-decision revision, not just a P9a notification gap.**
- whyNeeded: The inventory flags the scheduling-model contradiction under P9a (notifications). But the single-08:00-Madrid-job + "per-user TZ deferred" decision (§A) actually breaks: notification times (X4/P9a), "today"/"Day X of Y" for non-Madrid users (X4), "updated today" staleness, the daily-check-in 8 PM reminder, AND the report/"this week" boundaries. It is an **architecture decision** that needs revising before P4a, not a P9a-local fix. The inventory under-scopes it as notification-only.
- neededBeforePhase: P4a (day-boundary correctness) — well before P9a
- severity: major
- recommendedResolution: needs-product-owner-decision — revisit the §A scheduling/TZ row: capture `users.timezone` at onboarding and use it for ALL day-boundary computation now (cheap); keep the nightly Madrid job only for batch fan-out but evaluate per-user local times. Update §A so the decision matches the screens.

**X18. §D `email_hash` lookup vs Keycloak as the identity source of truth — duplicate-account & email-change rule.**
- whyNeeded: §D has `users.email_hash` "for lookup without plaintext," and screen 31 shows an editable email. But the rule for email uniqueness (is email_hash unique? what happens when a user changes email in Keycloak vs the app? does Apple "Hide My Email" relay produce a stable hash — ties to B3?) is undefined. An email change must update the hash and stay consistent with Keycloak; a collision must be handled. The inventory's B-items touch social-login linking but not the email-change/uniqueness contract on the app side.
- neededBeforePhase: P1 (identity spine) / P4a (PATCH /me email)
- severity: major
- recommendedResolution: decide-now-with-default — Keycloak is the email source of truth; app stores `email_hash` for lookup only, updated via a Keycloak event/webhook or on next login; enforce uniqueness; define the email-change flow (re-verification). Reconcile with B3 social-login linking.

**X19. §I unresolved infra decisions (off-site backup provider, Vault auto-unseal, operator MFA, crash reporting) tagged to no build phase in the inventory.**
- whyNeeded: The inventory is product/clinical-focused and explicitly omits §I infra items, but two of them are **build-blocking** and belong in the gap register so they aren't forgotten: off-site backup provider + Vault auto-unseal are "needed at milestone 1" (P0a/P11), and operator MFA is "needed before first production deploy" (P11). Crash reporting is needed "for the first beta" (P12b). These are decisions, not just config, and currently live only in §I prose.
- neededBeforePhase: P0a/P11 (backup provider, Vault unseal, operator MFA); P12b (crash reporting)
- severity: major
- recommendedResolution: needs-product-owner-decision — surface the four §I infra decisions in the gap register with their milestone tags so P0a/P11/P12b don't stall. (Backup provider + Vault auto-unseal block the compose stack; operator MFA blocks prod cutover.)

**X20. ClamAV-rejected and parse-rejected lab UX + `rejection_reason` copy (NOT in inventory).**
- whyNeeded: §E step 2 rejects infected PDFs with 422 and §D `labs.status` includes `rejected` with `rejection_reason`. But no screen shows the rejected/needs-manual/virus-found state, and no copy exists for it. P7a/P7b must render what the user sees when upload fails AV, exceeds 20 MB, isn't a real PDF, or has no extractable text (a photo-of-paper PDF — common, and §A says "no image OCR"). The inventory covers the *happy-path* confirm (screen 19/20) but not the failure surfaces, which are guaranteed to occur.
- neededBeforePhase: P7a
- severity: major
- recommendedResolution: formalize + decide-now-with-default — enumerate `rejection_reason` codes (virus, too_large, not_pdf, no_text_extracted, quota_exceeded, parse_failed) with bilingual user-facing copy and the retry/manual-entry CTA; define the screen state for each. The "scanned-image PDF has no text" case is the most common real failure given the no-OCR decision and needs explicit handling.

## Axes that ARE genuinely covered (no additions needed)

- **Lab-parse pipeline mechanics** (schema, widening math, unit whitelist, ranges, confidence field, phase-coverage): thoroughly covered by B16/B35/B36/B33 and P7b majors. My only addition is the *failure-state UX* (X20).
- **Confidence/phase/missing-data inference rules**: exhaustively covered (B28–B34); correctly routed to clinical source + ref_insight_rule.
- **GDPR consent/privacy-policy/export contradictions**: well covered (B2/B42/B43/B44). My additions are the *age gate* (X7) and *in-app disclaimer* (X15), which the consent items don't reach.
- **Per-module enum extraction from screens**: complete; my additions are the *governance/stability layer* (X12) on top, not the enum values themselves.
- **Notification copy/scheduling/quiet-hours**: well covered for P9a; my addition (X17) only re-scopes the TZ contradiction earlier and broader.

## Priority of the additions

- **Blocker:** X7 (age-eligibility gate — legal, blocks P1 consent design).
- **Major, front-load with P3a foundation:** X1 (units policy), X2 (week-start), X3 (date/time format), X6 (decimal separator), X4 (shared day-boundary), X14 (accessibility), X11 (soft-delete/pagination), X10 (date-range validation), X12 (enum governance) — these are foundation/contract decisions that get expensive to retrofit once screens and writes exist.
- **Major, phase-entry:** X8 (eligible population + contraceptive-suppression clinical contradiction, P4a/P7b), X13 (clinical seed provenance/versioning, P6/P7b/P10), X15 (in-app disclaimer, P6), X17 (TZ architecture revision, P4a), X18 (email/identity contract, P1), X19 (§I infra decisions, P0a/P11), X20 (lab failure-state UX, P7a).
- **Minor:** X5 (locale copy audit), X9 (notes constraints), X16 (red-flag handling).

The single most important miss is **X7 (age/eligibility)** — a medical app processing minors' special-category sexual/reproductive-health data with no age gate is a hard legal blocker that the consent item (B2) does not cover. The most pervasive misses are the **locale-convention cluster (X2/X3/X6) and the shared day-boundary rule (X4/X17)**: the inventory treats the US-formatted English mockups as canonical source-of-truth, which would ship US date/time/week-start conventions into an EU, likely-Spanish-primary product.
