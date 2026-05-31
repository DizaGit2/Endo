<!-- Companion to ../2026-05-31-build-strategy-design.md, the gap register, and the living plan (../../plans/lumen-build.md). Produced 2026-05-31 by the definitions-extraction workflow. -->

# Lumen — Enum / Seed / i18n Definitions (extracted from screen mockups)

> **EXTRACTED VERBATIM FROM SCREEN MOCKUPS** — codes are stable wire/DB values, labels are i18n source strings (likely **es-ES primary**, English shown). Items flagged **illustrative-confirm-with-PO** are starter sets, **NOT exhaustive** — product owner confirms the full set before the enum is frozen.

## Critical code-vs-label mappings (read first)

Two hormone definitions have a **stable DB/wire code that differs from the on-screen display label**. The code comes from `ARCHITECTURE.md §E` JSON schema (line 245), which is authoritative for persistence; the label is the exact on-screen string. Use the code on the wire/DB, render the label in the UI.

| DB/wire code (ARCHITECTURE §E) | On-screen display label (screens 6 & 33) | Note |
|--------------------------------|-------------------------------------------|------|
| `estradiol`                    | **Estrogen**                              | schema says `estradiol`, every screen says "Estrogen" |
| `glp1`                         | **GLP-1**                                 | schema says `glp1`, screens (and CLAUDE.md color list) say "GLP-1" |

The other five hormones (`progesterone`, `lh`, `fsh`, `testosterone`, `cortisol`) have code == label-lowercased; no mismatch.

## Conventions used in this document

- **kind**: the shape of the definition — `enum`, `ordinal_scale`, `code_label_table`, `seed_table_shape`, or `copy_strings`.
- **neededByPhase**: the build phase / endpoint that consumes it (per `ARCHITECTURE.md` build order).
- **completeness**: `exhaustive-from-screen` (full set visibly shown) or `illustrative-confirm-with-PO` (reads as a starter set — confirm with PO before freezing).
- **Code** = stable lowercase snake_case wire/DB value. **Label** = exact on-screen string (i18n source). **Extra** = ordinal, default state, units, color, or mapping notes.
- Decorative `✦` glyph and separators (`·`, `–`, `Δ`) are NOT part of translatable strings.

---

# Module: Onboarding

## Goal — `enum`
- **neededByPhase**: P4 (Onboarding) — `POST /onboarding/goals`; shapes dashboard
- **sourceScreens**: `screen_05_goals`
- **completeness**: exhaustive-from-screen (Step 5 of 7, full list shown)

| code | label | extra |
|------|-------|-------|
| `manage_symptoms` | Manage symptoms | sub: "Find pain & flare patterns"; glyph `✦`; **default ON** (`g on`); ord 1 |
| `understand_hormones` | Understand my hormones | sub: "Compare labs to baseline"; glyph `◐`; **default ON** (`g on`); ord 2 |
| `plan_fertility` | Plan for fertility | sub: "Track ovulation windows"; glyph `♡`; default off; ord 3 |
| `prepare_appointments` | Prepare for appointments | sub: "Doctor-ready reports"; glyph `↗`; default off; ord 4 |
| `just_curious` | Just curious | sub: "Learn my own rhythm"; glyph `✿`; default off; ord 5 |

Multi-select ("Pick all that fit. Shapes your dashboard."). Only the first two default ON. Each row = title (`.gt`) + sub-description (`.gd`), both i18n strings. Codes are newly proposed (snake_case of labels); `ARCHITECTURE §C` maps the endpoint but does not enumerate goal codes.

## Cycle setup — average cycle length chips — `ordinal_scale`
- **neededByPhase**: P4 — onboarding step 3 (screen 3); writes cycle baseline
- **sourceScreens**: `screen_03_cycle_setup`
- **completeness**: illustrative-confirm-with-PO (quick-pick chips over an integer day field, not a closed enum)

| code | label | extra |
|------|-------|-------|
| `len_26` | 26 | days |
| `len_27` | 27 | days |
| `len_28` | 28 | days; **default** selected (`on`) |
| `len_29` | 29 | days |
| `len_30` | 30 | days |

Label: "Average cycle length". Underlying field is an integer day count; settings screen 32 confirms arbitrary values ("29 days"). Confirm out-of-chip entry is allowed (almost certainly yes).

## Cycle setup — regularity — `enum`
- **neededByPhase**: P4 — onboarding step 3 (screen 3) regularity selector
- **sourceScreens**: `screen_03_cycle_setup`
- **completeness**: exhaustive-from-screen (closed 3-chip row)

| code | label | extra |
|------|-------|-------|
| `regular` | Regular | chip |
| `somewhat` | Somewhat | chip; **default** selected (`on`) |
| `irregular` | Irregular | chip |

Label: "Regularity". Settings screen 32 renders regularity as "Irregular ±4d" — stored model is likely this enum bucket **plus** a numeric ±days variability. Confirm how onboarding "Somewhat" maps to the settings display with PO.

## Copy strings — onboarding screens 3 / 5 / 6 / 7 — `copy_strings`
- **neededByPhase**: P4 onboarding i18n; P8 i18n; P11 Flutter polish
- **completeness**: exhaustive-from-screen

| code | label | source | extra |
|------|-------|--------|-------|
| `s3.step_tag` | Step 3 of 7 · Cycle | screen 3 | step tag (middot U+00B7) |
| `s3.heading` | When did your last period start? | screen 3 | h1 |
| `s3.subhead` | We'll predict your phases from here. | screen 3 | subhead |
| `s3.label_avg_length` | Average cycle length | screen 3 | field label |
| `s3.label_regularity` | Regularity | screen 3 | field label |
| `s3.cta_continue` | Continue | screen 3 | primary button |
| `s5.step_tag` | Step 5 of 7 · Goals | screen 5 | section tag (uppercased via CSS) |
| `s5.title` | What brings you here? | screen 5 | h1 |
| `s5.subtitle` | Pick all that fit. Shapes your dashboard. | screen 5 | subhead `.sb` |
| `s5.cta_continue` | Continue | screen 5 | primary button |
| `s6.step_tag` | Step 6 of 7 · Hormones | screen 6 | section tag |
| `s6.title` | Which to chart? | screen 6 | h1 |
| `s6.subtitle` | Defaults shown. Tweak now or in settings. | screen 6 | subhead `.sb` |
| `s6.cta_continue` | Continue | screen 6 | primary button |
| `s7.step_tag` | Step 7 of 7 · Reminders | screen 7 | section tag (middot) |
| `s7.title` | Stay in tune | screen 7 | h1 |
| `s7.subtitle` | Soft nudges only. Mute anytime. | screen 7 | subtitle |
| `s7.primary_cta` | Allow & finish | screen 7 | requests OS push + completes onboarding |
| `s7.skip_cta` | Not now | screen 7 | secondary/skip |

Onboarding is confirmed **7 steps** (step tags + 7-dot progress indicator). `April 2026` on screen 3 is a sample calendar header, not a translatable string.

---

# Module: Hormones & Labs

> All hormone tables below share the same canonical 7-member set, identical membership/order across screen 6 (onboarding picker), screen 33 (settings), and `ARCHITECTURE §E` JSON schema. **Re-read the code-vs-label banner at the top** before using `estradiol`/`glp1`.

## HormoneCode (canonical hormone set) — `code_label_table`
- **neededByPhase**: P6 (labs + LLM parse) and P4 (onboarding selection); seeds `ref_hormone_range.hormone_code`, used in `lab_result_drafts.hormone_code` and the LLM JSON schema
- **sourceScreens**: `screen_06_hormones`, `screen_33_hormone_prefs`, `ARCHITECTURE.md §E`
- **completeness**: exhaustive-from-screen (the 7 charted in v1)

| code | label | extra |
|------|-------|-------|
| `estradiol` | **Estrogen** | ⚠ code-vs-label mismatch (schema `estradiol`); swatch `#C25A36` |
| `progesterone` | Progesterone | code == §E; swatch `#7B8F6B` |
| `lh` | LH | code == §E; swatch `#D4537E` |
| `fsh` | FSH | code == §E; swatch `#378ADD` |
| `testosterone` | Testosterone | code == §E; swatch `#BA7517` |
| `cortisol` | Cortisol | code == §E; swatch `#7F77DD` |
| `glp1` | **GLP-1** | ⚠ code-vs-label mismatch (schema `glp1`); swatch `#1D9E75` |

Codes from `ARCHITECTURE §E` (line 245, authoritative); labels are exact on-screen strings. Swatch hex colors are hard-coded (not theme-switched). `§E` line 226 notes hidden hormones can still appear in labs, but only these 7 codes are enumerated in the schema.

## HormoneCategory (presentation grouping) — `enum`
- **neededByPhase**: P4/P6 — grouping label next to each hormone on the onboarding chart picker
- **sourceScreens**: `screen_06_hormones` (screen 33 does NOT show categories)
- **completeness**: exhaustive-from-screen (5 categories cover all 7 hormones)

| code | label | extra (members) |
|------|-------|-----------------|
| `sex` | Sex | Estrogen (`estradiol`), Progesterone |
| `pituitary` | Pituitary | LH, FSH |
| `androgen` | Androgen | Testosterone |
| `stress` | Stress | Cortisol |
| `metabolic` | Metabolic | GLP-1 (`glp1`) |

Appears inline (`.cat` span) per hormone row on screen 6 only. Not present in `ARCHITECTURE.md` — derived solely from screen 6. Codes are snake_case of labels.

## HormoneChartDefaultSelection (onboarding default) — `code_label_table`
- **neededByPhase**: P4 (Onboarding) — default "which to chart" written via `POST /onboarding/hormones`
- **sourceScreens**: `screen_06_hormones`
- **completeness**: exhaustive-from-screen

**All 7 rows carry `r on` → every hormone is toggled ON by default at onboarding** (`estradiol`, `progesterone`, `lh`, `fsh`, `testosterone`, `cortisol`, `glp1` all default ON). Screen 6 copy: "Which to chart? / Defaults shown. Tweak now or in settings."

> ⚠ **Default-state conflict** with settings screen 33 (next two tables), where 3 are OFF. The onboarding "all-on" vs the settings "mixed" state must be reconciled with PO — onboarding is plausibly the true initial default; screen 33 may be a populated user state.

## HormoneDisplayUnit (per-hormone display unit) — `code_label_table`
- **neededByPhase**: P6 — relates to `ref_hormone_range.unit` and the `§E` unit whitelist
- **sourceScreens**: `screen_33_hormone_prefs`
- **completeness**: exhaustive-from-screen

| code | label | unit (exact on-screen casing) |
|------|-------|-------------------------------|
| `estradiol` | Estrogen | `pg/mL` |
| `progesterone` | Progesterone | `ng/mL` |
| `lh` | LH | `mIU/mL` |
| `fsh` | FSH | `mIU/mL` |
| `testosterone` | Testosterone | `ng/dL` |
| `cortisol` | Cortisol | `μg/dL` (micro sign U+03BC) |
| `glp1` | GLP-1 | `pmol/L` |

Shown as the `.mut` sub-line under each hormone name on screen 33. **Casing mismatch** vs the `§E` unit whitelist examples (lowercase `pg/ml`, `ng/ml`, `mIU/ml`, `nmol/l`, line 246) — screen uses capital `mL`/`dL`/`L`. These are DISPLAY units; the canonical whitelist lives in `ref_hormone_range` (admin module authoritative) — reconcile casing with PO/admin seed. Not necessarily the only acceptable lab unit.

## HormoneDisplaySettingDefault (settings visibility) — `code_label_table`
- **neededByPhase**: P9 (Settings) — `GET/PATCH /settings/hormones` default visibility
- **sourceScreens**: `screen_33_hormone_prefs`
- **completeness**: exhaustive-from-screen

| code | label | toggle state |
|------|-------|--------------|
| `estradiol` | Estrogen | **ON** — visible on charts |
| `progesterone` | Progesterone | **ON** |
| `lh` | LH | **ON** |
| `fsh` | FSH | **OFF** — hidden (name in muted color) |
| `testosterone` | Testosterone | **OFF** — hidden (name in muted color) |
| `cortisol` | Cortisol | **ON** |
| `glp1` | GLP-1 | **OFF** — hidden (name in muted color) |

Screen 33 "Hormone display / Toggle which hormones appear on charts": 4 ON (Estrogen, Progesterone, LH, Cortisol), 3 OFF (FSH, Testosterone, GLP-1). OFF rows also render the hormone name in muted text. **Conflicts with the all-ON onboarding default (screen 6)** — surface to PO. Semantics: ON ⇒ appears on charts; OFF ⇒ hidden but **still extracted from labs** (see footer note below).

## Copy strings — hormone screens 6 / 33 — `copy_strings`
- **neededByPhase**: P4 onboarding i18n; P9 settings i18n; P11 Flutter polish
- **completeness**: exhaustive-from-screen

| code | label | source | extra |
|------|-------|--------|-------|
| `s33.section_tag` | Settings | screen 33 | section tag (uppercased via CSS) |
| `s33.title` | Hormone display | screen 33 | h1 |
| `s33.subtitle` | Toggle which hormones appear on charts | screen 33 | subhead `.mut` |
| `s33.footer_note` | Hidden hormones still get extracted from labs | screen 33 | sage-soft info banner, `✦` prefix |

(Onboarding screen 6 copy is in the Onboarding module table above.) The footer note is **load-bearing product logic**: turning a hormone OFF hides it from charts but lab parsing still extracts its values (consistent with the `§E` lab-parse pipeline persisting all known `hormone_code`s).

---

# Module: Symptoms & Check-in

## PainLevel — `ordinal_scale`
- **neededByPhase**: P4 (Onboarding + Cycle + Symptoms; `POST /checkin/quick`, `POST /symptoms`)
- **sourceScreens**: `screen_09_quick_checkin`
- **completeness**: exhaustive-from-screen

Section label "Pain level". **TEN buttons valued 0–9 (range 0–9, NOT 0–10).** Codes `pain_0` … `pain_9`. End anchors: left = **None**, right = **Worst** (i18n strings). Mock shows `3` selected.

> ⚠ `ARCHITECTURE §D` defines `symptoms.intensity` as smallint 1..5 (body-map). That is a **different field** from this 0–9 quick-checkin pain scale, which has no explicit column — confirm a separate `pain_level` field with PO. (See also the three-way numeric scale conflict noted under BodyMapIntensity.)

## Mood — `enum`
- **neededByPhase**: P4 (Symptoms; `POST /checkin/quick`). ⚠ `ARCHITECTURE` stores mood on `cycle_day_logs.mood` smallint (Cycle module) — confirm owning module with PO.
- **sourceScreens**: `screen_09_quick_checkin`
- **completeness**: exhaustive-from-screen (exactly 4, 4-col grid)

| code | label | extra |
|------|-------|-------|
| `low` | Low | glyph `◔`; ord 0 (leftmost) |
| `tired` | Tired | glyph `◐`; ord 1; selected in mock |
| `steady` | Steady | glyph `◑`; ord 2 |
| `bright` | Bright | glyph `●`; ord 3 (rightmost) |

Glyphs are progressively-filled circles (decorative, ascending order). Likely maps to smallint ordinals 0–3 (or 1–4) on `cycle_day_logs.mood` — confirm numeric mapping with PO.

## symptoms.region.location — `enum`
- **neededByPhase**: P4 (Symptoms; `POST /symptoms` region enum, hard-coded in code per `§D`)
- **sourceScreens**: `screen_12_symptom_form`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `lower_abdomen` | Lower abdomen | selected in mock |
| `pelvis` | Pelvis | |
| `lower_back` | Lower back | |
| `legs` | Legs | |

Section label "LOCATION". Four chips — likely a starter set (endo regions commonly include bowel/bladder/rectal/shoulder). `§D` says `symptoms.region` is an enum hard-coded in code; `§A` locks "Fixed region enum + intensity 1-5" for the body-map. Reconcile this chip list with the body-map region enum with PO.

## symptoms.type — `enum`
- **neededByPhase**: P4 (Symptoms; `POST /symptoms`)
- **sourceScreens**: `screen_12_symptom_form`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `cramping` | Cramping | selected in mock |
| `sharp` | Sharp | |
| `burning` | Burning | |
| `dull` | Dull | |

Section label "TYPE" (pain quality). Reads as illustrative (commonly extended: stabbing, throbbing, aching, shooting). **No `type` column in `§D` symptoms table** (only region, intensity, occurred_at, notes_enc) — confirm whether `type` is a new column/enum or folded into notes.

## symptoms.triggers — `enum`
- **neededByPhase**: P4 (Symptoms; `POST /symptoms`)
- **sourceScreens**: `screen_12_symptom_form`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `stress` | Stress | |
| `intercourse` | Intercourse | selected in mock |
| `food` | Food | |

Section label "TRIGGERS". Multi-select; only 3 chips — strongly illustrative (typically exercise, bowel movement, urination, sleep, alcohol …). No `triggers` column in `§D` — confirm storage shape (enum/array column vs notes).

## symptoms.related — `enum`
- **neededByPhase**: P4 (Symptoms; `POST /symptoms`)
- **sourceScreens**: `screen_12_symptom_form`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `bloating` | Bloating | selected in mock |
| `nausea` | Nausea | |
| `fatigue` | Fatigue | |

Section label "RELATED" (accompanying symptoms). Multi-select; only 3 chips — illustrative (commonly diarrhea, constipation, headache, dizziness, painful urination/bowel). No `related` column in `§D` — confirm storage with PO.

## BodyMapView — `enum`
- **neededByPhase**: P4 (Symptoms; body-map capture feeding `symptoms.region` per `§A`)
- **sourceScreens**: `screen_13_body_map`
- **completeness**: exhaustive-from-screen (2-way segmented toggle)

| code | label | extra |
|------|-------|-------|
| `front` | Front | ord 0 (left); selected in mock |
| `back` | Back | ord 1 (right) |

Section label "Body map"; title "Tap where it hurts"; helper "3 points placed". Front/Back is the **side dimension** over the fixed region enum (`§A`: "Heatmap rendering reconstructs coordinates client-side").

## BodyMapIntensity — `ordinal_scale`
- **neededByPhase**: P4 (Symptoms; `symptoms.intensity` smallint 1..5 per `§D`)
- **sourceScreens**: `screen_13_body_map`
- **completeness**: illustrative-confirm-with-PO (full scale NOT shown)

Section label "INTENSITY AT SELECTED POINT". Continuous-looking slider (70% fill) with numeric readout **`7`**. No discrete 1–5 step labels and no anchor words rendered.

> ⚠ **Three-way numeric scale conflict to resolve with PO:** body-map readout = `7` here, but `§D`/`§A` lock `symptoms.intensity` to smallint **1..5** (authoritative for body_map / symptoms.intensity); meanwhile the screen-09 pain scale is **0..9**. These three numeric scales are inconsistent on their face — confirm the canonical intensity domain and how displayed values map.

## Copy strings — symptom/check-in screens 9 / 12 / 13 — `copy_strings`
- **neededByPhase**: P4 (Symptoms UI / i18n); P11 Flutter polish
- **completeness**: exhaustive-from-screen

| code | label | source | extra |
|------|-------|--------|-------|
| `s9.tag_daily_checkin` | Daily check-in | screen 9 | eyebrow (uppercase) |
| `s9.heading` | How's today? | screen 9 | sheet heading |
| `s9.sub` | 15 seconds. Add detail later. | screen 9 | subheading |
| `s9.label_pain_level` | Pain level | screen 9 | section label |
| `s9.label_mood` | Mood | screen 9 | section label |
| `s9.pain_anchor_none` | None | screen 9 | pain low anchor |
| `s9.pain_anchor_worst` | Worst | screen 9 | pain high anchor |
| `s9.btn_save` | Save check-in | screen 9 | primary button |
| `s9.btn_add_details` | + Add details | screen 9 | secondary/link button |
| `s12.tag_log_symptom` | Log symptom | screen 12 | eyebrow (uppercase) |
| `s12.heading` | Pain details | screen 12 | heading |
| `s12.label_location` | LOCATION | screen 12 | section label (i18n source likely "Location") |
| `s12.label_type` | TYPE | screen 12 | section label (likely "Type") |
| `s12.label_triggers` | TRIGGERS | screen 12 | section label (likely "Triggers") |
| `s12.label_related` | RELATED | screen 12 | section label (likely "Related") |
| `s12.hint_body_map` | ✦ Tap body map for precise location | screen 12 | sage hint; `✦` decorative |
| `s12.btn_save` | Save symptom | screen 12 | primary button |
| `s13.tag_body_map` | Body map | screen 13 | eyebrow (uppercase) |
| `s13.heading` | Tap where it hurts | screen 13 | heading |
| `s13.toggle_front` | Front | screen 13 | side toggle |
| `s13.toggle_back` | Back | screen 13 | side toggle |
| `s13.label_intensity` | INTENSITY AT SELECTED POINT | screen 13 | section label (uppercase) |
| `s13.hint_zoom` | ✦ Pinch or use +/− to zoom into a region | screen 13 | sage hint; `✦` decorative; minus = U+2212 |
| `s13.btn_save` | Save body map | screen 13 | primary button |

Section labels render uppercase via CSS; i18n source should be sentence case per CLAUDE.md (confirm). **Dynamic/sample values — do NOT extract as fixed strings:** `Good morning, Maya`, `Luteal · Day 22` (screen 9); `3 points placed`, `100%` (screen 13).

---

# Module: Body & Activity

## BodyMetric — `enum`
- **neededByPhase**: P4 (Body module, screens 22–23)
- **sourceScreens**: `screen_23_body_entry`, `screen_22_body_calendar`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `weight` | WEIGHT | unit kg; example 60.4 kg; 1 decimal; `§D` `body_metrics.metric` → `weight_kg` |
| `body_fat` | BODY FAT | unit %; example 24.1 %; 1 decimal |
| `waist` | WAIST | unit cm; example 71 cm; integer; `§D` → `waist_cm` |
| `bmi` | BMI | calendar chip only (screen 22); **derived** — no input field on screen 23 |

Screen 23 entry form shows WEIGHT / BODY FAT / WAIST; screen 22 calendar offers Weight / BMI / Body fat view chips. `§D` uses **suffixed codes** (`weight_kg`, `waist_cm`, "etc.") — the "etc." is non-exhaustive, so `body_fat`/`bmi` codes must be confirmed with PO. (DB code vs label note: schema suffixes units onto the code, e.g. `weight_kg` vs label "Weight".)

## BodyWeightStepper — `seed_table_shape`
- **neededByPhase**: P4 (Body entry UI, screen 23)
- **sourceScreens**: `screen_23_body_entry`
- **completeness**: exhaustive-from-screen (rendered ticks are literal)

| code | label | extra |
|------|-------|-------|
| `step` | 0.2 | weight increment (kg); ticks 59.8 / 60.0 / 60.2 / **60.4** / 60.6 / 60.8 |
| `precision` | 1 decimal | weight as 60.4 kg |
| `unit` | kg | weight unit (screens 22 & 23) |

Horizontal stepper centered on 60.4 (accent). BODY FAT = 1 decimal (24.1 %); WAIST = integer (71 cm). Only rendered tick values are literal; per-metric range/step confirm with PO.

## BodyMetricUnit — `code_label_table`
- **neededByPhase**: P4 (Body module)
- **sourceScreens**: `screen_22_body_calendar`, `screen_23_body_entry`
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `kg` | kg | weight (60.4 kg, +1.4 kg) |
| `percent` | % | body fat (24.1 %) |
| `cm` | cm | waist (71 cm) |

Units hard-paired to each metric. **No metric/imperial toggle shown** — metric (kg/cm) is the only system rendered.

## BodyFeelTag — `enum`
- **neededByPhase**: P4 (Body entry, screen 23)
- **sourceScreens**: `screen_23_body_entry`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `bloated` | Bloated | active/selected in mock |
| `light` | Light | |
| `heavy` | Heavy | |
| `tender` | Tender | active/selected in mock |

Section label "HOW DOES YOUR BODY FEEL?". Multi-select (Bloated + Tender both active). Only 4 chips fit — illustrative; confirm full vocabulary with PO. **No column in `§D`** (`body_metrics` has metric/value_enc/source/measured_at) — storage shape (tags array vs separate table) is a PO/implementation decision.

## BodyCalendarChip — `enum`
- **neededByPhase**: P4 (Body calendar, screen 22)
- **sourceScreens**: `screen_22_body_calendar`
- **completeness**: exhaustive-from-screen (view selector subset of BodyMetric)

| code | label | extra |
|------|-------|-------|
| `weight` | Weight | active chip; → BodyMetric.weight |
| `bmi` | BMI | inactive; → BodyMetric.bmi (derived) |
| `body_fat` | Body fat | inactive; → BodyMetric.body_fat |

Chart-overlay view selectors ("Weight & BMI / Overlaid on cycle phases"). Not a separate enum — the chart-view subset of BodyMetric. Phase-background labels on chart: **Mens, Foll, Ovul, Luteal** (abbreviations of the four cycle phases).

## ActivityType — `enum`
- **neededByPhase**: P4 (Activity module, screen 25)
- **sourceScreens**: `screen_25_activity_entry`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `walk` | Walk | |
| `yoga` | Yoga | selected/active |
| `strength` | Strength | |
| `run` | Run | |
| `swim` | Swim | |
| `pilates` | Pilates | |
| `other` | Other | catch-all |

Section label "TYPE"; single-select. The explicit **`other`** catch-all signals a curated starter list — confirm full vocabulary with PO. Maps to `§D` `activity_entries.activity_type` (column exists; no enum values defined — these codes are the proposed seed).

## ActivityIntensity — `ordinal_scale`
- **neededByPhase**: P4 (Activity entry, screen 25)
- **sourceScreens**: `screen_25_activity_entry`
- **completeness**: exhaustive-from-screen (full 3-step row)

| code | label | extra |
|------|-------|-------|
| `gentle` | Gentle | ord 1 |
| `moderate` | Moderate | ord 2; selected/active |
| `intense` | Intense | ord 3 |

Section label "INTENSITY"; single-select. Maps to `§D` `activity_entries.intensity` (smallint) → Gentle/Moderate/Intense = 1/2/3 (or 0-based per PO).

## ActivityEnergyAfter — `ordinal_scale`
- **neededByPhase**: P4 (Activity entry, screen 25)
- **sourceScreens**: `screen_25_activity_entry`
- **completeness**: exhaustive-from-screen (0–10 scale shown)

| code | label | extra |
|------|-------|-------|
| `scale_min` | 0 | implied slider minimum |
| `scale_max` | 10 | section label "ENERGY AFTER — 7/10"; bar 70% |
| `sample_value` | 7 | current value (accent) |
| `step` | 1 | integer step (from "7 / 10") |

Section label literally "ENERGY AFTER — 7/10"; 0–10 integer slider. Screen 24 corroborates (Avg energy "7.2 / 10"). Slider min not printed (0 inferred) — confirm 0–10 vs 1–10 with PO. **No DB column in `§D`** `activity_entries` (only activity_type/duration_min/intensity/source/occurred_at/notes_enc) → energy-after needs a **new column**; flag for implementer.

## ActivityDuration — `seed_table_shape`
- **neededByPhase**: P4 (Activity entry, screen 25)
- **sourceScreens**: `screen_25_activity_entry`
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `unit` | min | duration unit; example 45 min |
| `sample_value` | 45 | current value (accent) |

Section label "DURATION". Maps to `§D` `activity_entries.duration_min` (integer minutes). No step/range printed — granularity confirm with PO; only "45 min" is literal.

## Copy & aggregates — body/activity calendars 22 / 24 — `copy_strings`
- **neededByPhase**: P4 (Body & Activity calendars)
- **completeness**: exhaustive-from-screen

| code | label | source | extra |
|------|-------|--------|-------|
| `s22.section_label` | Body | screen 22 | uppercase eyebrow |
| `s22.title` | Weight & BMI | screen 22 | title |
| `s22.subtitle` | Overlaid on cycle phases | screen 22 | subtitle |
| `s22.stat_current` | Current | screen 22 | stat tile (value 60.4 kg) |
| `s22.stat_cycle_delta` | Cycle Δ | screen 22 | stat tile (value +1.4 kg); literal Greek delta |
| `s22.insight` | ✦ You retain ~1 kg in luteal — common with endo | screen 22 | sage insight; `✦` decorative |
| `s22.cta` | Log today's weight | screen 22 | primary button |
| `s24.section_label` | Activity | screen 24 | uppercase eyebrow |
| `s24.title` | Movement | screen 24 | title |
| `s24.summary_line` | 7 sessions · 4h 20m | screen 24 | month summary (dynamic) |
| `s24.stat_this_week` | This week | screen 24 | stat tile (value 2h 10m) |
| `s24.stat_avg_energy` | Avg energy | screen 24 | stat tile (value "7.2 / 10"); corroborates 0–10 energy scale |
| `s24.insight` | ✦ You move 2× more in follicular than menstrual | screen 24 | sage insight; `✦` decorative |
| `s24.cta` | Log a session | screen 24 | primary button |

Stat values (60.4 kg, +1.4 kg, 7 sessions, 2h 10m, 7.2 / 10) are sample data, not enum values. Activity chart y-axis = minutes (ticks 0/30/60/90) over the four cycle-phase bands (Mens/Foll/Ovul/Luteal).

---

# Module: Treatment

## MedicationFrequency — `enum`
- **neededByPhase**: P4 (Treatment, screens 26–27)
- **sourceScreens**: `screen_27_add_medication`
- **completeness**: exhaustive-from-screen (closed segmented row)

| code | label | extra |
|------|-------|-------|
| `daily` | Daily | ord 0; selected in mock; drives DAILY group (screen 26) |
| `cyclical` | Cyclical | ord 1 |
| `as_needed` | As needed | ord 2; drives AS NEEDED group (screen 26) |

FREQUENCY chip group. Maps to `medication_schedules.cron_like` (cyclical = cycle-phase-based dosing). `as_needed` = the PRN bucket.

## MedicationCategory — `enum`
- **neededByPhase**: P4 (Treatment, screen 27)
- **sourceScreens**: `screen_27_add_medication`
- **completeness**: exhaustive-from-screen (closed segmented row)

| code | label | extra |
|------|-------|-------|
| `hormonal` | Hormonal | ord 0 |
| `pain` | Pain | ord 1 |
| `supplement` | Supplement | ord 2; selected in mock (example "Turmeric capsule") |

CATEGORY chip group. **Not a column in `§D` `ref_medication`** (which has name/form/typical_dose/atc_code) — category is an added classification; confirm whether it persists on the medication or is derived. PO should confirm this exact 3-item set is final (endo treatment often adds GI/GLP-1 buckets).

## MedicationForm — `enum`
- **neededByPhase**: P4 (Treatment, screen 27)
- **sourceScreens**: `screen_27_add_medication`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `capsule` | Capsule | only FORM value shown (filled single-select for example med) |

Maps to `§D` `ref_medication.form`. Full set (tablet, capsule, patch, gel, IUD/device, injection, suppository, liquid, non-pharmacological aid …) is NOT on screen — define with PO. Only `Capsule` is evidenced.

## MedicationGroup (list grouping) — `enum`
- **neededByPhase**: P4 (Treatment, screen 26 list grouping)
- **sourceScreens**: `screen_26_medication_log`
- **completeness**: exhaustive-from-screen (exactly 2 section headers)

| code | label | extra |
|------|-------|-------|
| `daily` | DAILY | section header; groups scheduled meds (sage `--sg` bars) |
| `as_needed` | AS NEEDED | section header; groups PRN meds (accent `--ac` bars) |

2-way derived view over MedicationFrequency (Daily + Cyclical → DAILY; As needed → AS NEEDED). Displayed uppercase via CSS; i18n source should be sentence case ("Daily" / "As needed").

## MedicationEffectiveness — `ordinal_scale`
- **neededByPhase**: P4 (Treatment, screen 26 display)
- **sourceScreens**: `screen_26_medication_log`
- **completeness**: exhaustive-from-screen (scale 1–10)

| code | label | extra |
|------|-------|-------|
| `effectiveness_rating` | N/10 | user-rated integer out of 10; bar fill = value/10 |
| (example) | 8/10 | Dienogest; 80% bar; sage (DAILY) |
| (example) | 6/10 | Magnesium glycinate; 60%; sage (DAILY) |
| (example) | 7/10 | Naproxen; 70%; accent (AS NEEDED) |
| (example) | 9/10 | Heating pad; 90%; accent (AS NEEDED) |

Only example values 6/7/8/9 appear; ceiling 10 implied by "/10". Screen 27 entry-timing copy: "Rate effectiveness after 2 weeks of use". **Not in `§D`** (no effectiveness column) — flag adding a field (e.g. smallint 1..10).

## MedicationTimeOfDay — `enum`
- **neededByPhase**: P4 (Treatment, screen 26 per-med dosing label)
- **sourceScreens**: `screen_26_medication_log`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `morning` | morning | "Dienogest — 2 mg · morning" |
| `night` | night | "Magnesium glycinate — 400 mg · night" |

Coarse qualitative slot in the DAILY dose meta line. Only 2 evidenced (full set likely morning/midday/evening/night/bedtime). Distinct from the explicit reminder clock time (screen 27). Maps loosely to `medication_schedules.reminder_time` — confirm whether time-of-day is a separate enum or derived.

## MedicationPrnTrigger — `enum`
- **neededByPhase**: P4 (Treatment, screen 26 as-needed indication)
- **sourceScreens**: `screen_26_medication_log`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `pain` | pain | "Naproxen — 500 mg · pain" |
| `cramps` | cramps | "Heating pad — 20 min · cramps" |

For AS NEEDED entries the meta line's second segment is an indication/trigger word. Only 2 shown — illustrative. **Not in `§D`.** May overlap symptom region/type vocabulary — consider reusing the symptom taxonomy.

## MedicationUnit — `enum`
- **neededByPhase**: P4 (Treatment, screens 26–27 dose display)
- **sourceScreens**: `screen_26_medication_log`, `screen_27_add_medication`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `mg` | mg | dose unit (screen 27 "500 mg"; screen 26 "2 mg"/"400 mg"/"500 mg") |
| `min` | min | duration for non-drug aid: "Heating pad — 20 min · cramps" |

`mg` is the only pharmacological dose unit shown; `min` appears as a duration for the non-drug "Heating pad". Full unit set not enumerated. Confirms the treatment model must accept **non-pharmacological** therapies. Dose persists as `§D` `ref_medication.typical_dose` / `medications.dose_enc`.

## MedicationReminderTime — `copy_strings`
- **neededByPhase**: P4 (Treatment, screen 27)
- **sourceScreens**: `screen_27_add_medication`
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `remind_me_label` | REMIND ME | field label (uppercase); maps to `medication_schedules.reminder_time` |
| `reminder_time_example` | 8:00 AM | example clock time; 12-hour AM/PM; chevron `›` opens picker |

Explicit clock-time reminder, distinct from qualitative morning/night labels (screen 26). Note `§A` fixes global nightly dispatch at 08:00 Europe/Madrid — confirm how per-med `reminder_time` interacts with that single nightly job (likely stored but v1 dispatch is coarse).

## MedicationLogStatus — `enum` (ARCHITECTURE-only; not on screen)
- **neededByPhase**: P4 (Treatment, `medication_logs`)
- **sourceScreens**: `ARCHITECTURE.md §D`
- **completeness**: exhaustive-from-screen (i.e. complete per architecture; **no on-screen UI**)

| code | label | extra |
|------|-------|-------|
| `taken` | *(not on screen)* | `medication_logs.status` enum |
| `skipped` | *(not on screen)* | `medication_logs.status` enum |
| `snoozed` | *(not on screen)* | `medication_logs.status` enum |

`§D` Treatment `medication_logs.status` = taken/skipped/snoozed. **None surfaced on screens 26/27** (no take/skip/snooze action UI). i18n labels undefined by screens — must be authored. Flag: the logging interaction has **no mockup in scope** — confirm UX with PO.

## ExampleMedications (demo seed) — `seed_table_shape`
- **neededByPhase**: P4 / P9 (Admin `ref_medication` seed; demo account)
- **sourceScreens**: `screen_26_medication_log`, `screen_27_add_medication`
- **completeness**: illustrative-confirm-with-PO (DEMO data, not a clinical catalog)

| code | label | extra |
|------|-------|-------|
| `dienogest` | Dienogest | DAILY; 2 mg; morning; 8/10; category hormonal (implied) |
| `magnesium_glycinate` | Magnesium glycinate | DAILY; 400 mg; night; 6/10; category supplement (implied) |
| `naproxen` | Naproxen | AS NEEDED; 500 mg; trigger pain; 7/10; category pain (implied NSAID) |
| `heating_pad` | Heating pad | AS NEEDED; 20 min; trigger cramps; 9/10; **non-pharmacological** (no drug dose / no `atc_code`) |
| `turmeric_capsule` | Turmeric capsule | screen 27 example; 500 mg; form Capsule; category Supplement; freq Daily; reminder 8:00 AM |

Demo/example only. Useful as (a) demo-account seed (P9/P11) and (b) shape sample for `ref_medication` (name/form/typical_dose/atc_code). "Heating pad" (no `atc_code`, duration not mg dose) confirms the model must tolerate non-drug therapies.

**Treatment copy strings:** screen 26 header "Medications", summary "4 active · 2 as-needed", insight "✦ Heating pad is your highest-rated relief". Screen 27 header "New treatment" / "Add to regimen"; submit button "Add to regimen"; insight "✦ Rate effectiveness after 2 weeks of use".

---

# Module: Reports

## ReportIncludeSection — `enum`
- **neededByPhase**: P7 (Reports / QuestPDF; `POST /reports/doctor` body, `GenerateDoctorReportJob`)
- **sourceScreens**: `screen_29_doctor_report`
- **completeness**: exhaustive-from-screen (full on/off toggle list)

| code | label | extra |
|------|-------|-------|
| `cycle_history` | Cycle history | ord 1; **default ON** |
| `hormone_labs` | Hormone labs ({count}) | ord 2; default ON; "(7)" is a dynamic count — parameterize |
| `pain_symptoms` | Pain & symptoms | ord 3; default ON |
| `body_map_points` | Body-map points | ord 4; default ON |
| `medication_log` | Medication log | ord 5; **default OFF** |
| `activity_log` | Activity log | ord 6; **default OFF** |

"Build a summary" INCLUDE list. Default-on: first four; default-off: Medication log, Activity log. The `(7)` matches the 7 hormones — render as `Hormone labs ({count})`, do NOT bake into the i18n string. `§C.8` backs Reports (`reports` table, `POST /reports/doctor`) but defines no include-flag codes — codes above are new candidates.

## ReportDateRange — `enum`
- **neededByPhase**: P7 (Reports; `POST /reports/doctor` body)
- **sourceScreens**: `screen_29_doctor_report`
- **completeness**: exhaustive-from-screen (full chip set)

| code | label | extra |
|------|-------|-------|
| `1_month` | 1 mo | ord 1; ~1 month |
| `3_months` | 3 mo | ord 2; ~3 months; **SELECTED (default)** |
| `6_months` | 6 mo | ord 3; ~6 months |
| `all` | All | ord 4; entire history |

"DATE RANGE" single-select; "3 mo" default. Codes lead with a digit — for C# identifiers consider aliases (OneMonth/ThreeMonths/SixMonths/All) while keeping wire codes as above. Screen 30 confirms "3 mo" resolves to "Jan 10 – Apr 10, 2026".

## ReportShareAs — `enum`
- **neededByPhase**: P7 (Reports; share/download action on screen 30)
- **sourceScreens**: `screen_30_share_preview`
- **completeness**: exhaustive-from-screen (full option row)

| code | label | extra |
|------|-------|-------|
| `pdf` | PDF | ord 1; icon `⇓`; **SELECTED (default)**; CTA "Download PDF" |
| `link` | Link | ord 2; icon `∞` |
| `email` | Email | ord 3; icon `✉` |

"SHARE AS" single-select; PDF default.

> ⚠ **Architecture conflict (confirm with PO):** `§A` "Report sharing" decision = "In-app PDF download, user forwards via their own channels — No server-side sharing endpoint, no signed URLs." This **contradicts** the Link and Email options here, and screen-30's "link expires in 30 days" implies a server-hosted link. Only `GET /reports/{id}/download` exists. Confirm whether Link/Email are deferred (PDF-only in v1) or the architecture decision is revisited.

## report.metadata.shape — `seed_table_shape`
- **neededByPhase**: P7 (Reports; `reports` entity + QuestPDF template fields)
- **sourceScreens**: `screen_29_doctor_report`, `screen_30_share_preview`
- **completeness**: illustrative-confirm-with-PO (implied by labels, not an explicit enum)

| code | label | extra |
|------|-------|-------|
| `page_count` | 6 pages | dynamic; "Estimated 6 pages" / "· 6 pages" / "1/6" → PDF page total |
| `date_range_resolved` | Jan 10 – Apr 10, 2026 | dynamic; resolved from ReportDateRange |
| `read_only_flag` | read-only PDF / Read-only | output is read-only (not a user toggle) |
| `link_expiry_days` | link expires in 30 days | dynamic 30-day expiry → `reports.expires_at` (`§D`) — see sharing conflict |

`§D` `reports` table backs these: `minio_key`, `generated_at`, `expires_at` (matches "30 days"), `status` (pending/ready/failed). "Report ready" eyebrow ⇒ `status='ready'`. Tension: `expires_at` + Link/Email vs `§A` download-only decision.

## Copy strings — report screens 29 / 30 — `copy_strings`
- **neededByPhase**: P7 (Reports) + i18n (ES/EN per `§I`)
- **completeness**: exhaustive-from-screen

| code | label | source | extra |
|------|-------|--------|-------|
| `s29.eyebrow` | Doctor report | screen 29 | uppercase eyebrow (store "Doctor report") |
| `s29.title` | Build a summary | screen 29 | h1 |
| `s29.date_range_section` | DATE RANGE | screen 29 | section label (store "Date range") |
| `s29.include_section` | INCLUDE | screen 29 | section label (store "Include") |
| `s29.estimate_note` | ✦ Estimated {pages} pages · read-only PDF | screen 29 | sage note; "6" dynamic; `✦` decorative |
| `s29.generate_cta` | Generate report | screen 29 | primary button |
| `s30.eyebrow` | Report ready | screen 30 | uppercase eyebrow |
| `s30.title` | Share preview | screen 30 | h1 |
| `s30.subtitle` | {startDate} – {endDate}, {year} · {pages} pages | screen 30 | fully dynamic subtitle |
| `s30.share_as_section` | SHARE AS | screen 30 | section label |
| `s30.expiry_note` | ✦ Read-only · link expires in {days} days | screen 30 | sage note; "30" dynamic; `✦` decorative |
| `s30.download_cta` | Download PDF | screen 30 | primary button |
| `s30.preview_page_indicator` | {current}/{total} | screen 30 | "1/6" preview overlay (dynamic) |

**QuestPDF report-template headings to reuse** (rendered inside the mock PDF preview): doc title **"Lumen Report"**; section tags **PATIENT · 3 CYCLES** ("3 CYCLES" dynamic), **HORMONES**, **PAIN**. Subtitle, page indicator, and patient/cycle counts are all dynamic — parameterize, do not hard-code.

---

# Module: Notifications

## NotificationCategory — `code_label_table`
- **neededByPhase**: P8 (Notifications, build order #8); prefs also written in P4 onboarding via `POST /onboarding/notifications`
- **sourceScreens**: `screen_07_notifications`, `screen_34_notifications`
- **completeness**: exhaustive-from-screen (exactly these 4 on both screens)

| code | label | extra |
|------|-------|-------|
| `daily_checkin` | Daily check-in | s7 "Log symptoms each evening"; s34 group DAILY, detail "8:00 PM"; default ON both |
| `phase_shift` | **Phase shift** *(see drift)* | ⚠ **label drift**: s7 "Phase shifts" (plural, "When you enter a new phase") vs s34 "Phase shift" (singular, "When phase changes"). Recommend canonical "Phase shift" per latest settings screen — confirm with PO |
| `period_prediction` | Period prediction | ⚠ **state + copy drift**: s7 "Two days before your period" default **OFF**; s34 "2 days before" default **ON** |
| `medication_reminders` | Medication reminders | ⚠ **state drift**: s7 "Once you log a treatment" default **OFF**; s34 detail "2 active" default **ON** ("2 active" is dynamic) |

Both screens show exactly these 4 (exhaustive). Codes are PROPOSED (`ARCHITECTURE` defines no category codes; `§I` defers notification copy to milestone 8). Screen 7 = onboarding (flat list); screen 34 = settings (grouped). **Default-state reconciliation needed** — see NotificationDefaultState_Onboarding below for the authoritative initial state.

## NotificationCategoryGroup — `enum` (settings layout only)
- **neededByPhase**: P8 (settings notifications grouping)
- **sourceScreens**: `screen_34_notifications` (NOT on onboarding screen 7)
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `daily` | DAILY | contains `daily_checkin` + `medication_reminders` |
| `cycle_events` | CYCLE EVENTS | contains `period_prediction` + `phase_shift` |
| `quiet_hours` | QUIET HOURS | contains the quiet-hours window row (not a toggle category) |

Grouping exists only on settings screen 34; onboarding screen 7 is a single ungrouped list. Headers are uppercase in HTML already. Group assignment is part of settings layout, not a property of the category.

## NotificationDefaultState_Onboarding — `code_label_table` (authoritative initial seed)
- **neededByPhase**: P4 onboarding (initial notification prefs seed) / P8
- **sourceScreens**: `screen_07_notifications`
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `daily_checkin` | on | `n on` |
| `phase_shift` | on | `n on` |
| `period_prediction` | off | `n` |
| `medication_reminders` | off | `n` |

Literal default toggle states on the onboarding screen — the **authoritative source for initial seed values** (`.n.on` = enabled, `.n` = disabled). Settings screen 34 shows all four ON (`var(--ac)` on every toggle) — confirm with PO whether that is a populated/sample state vs a different default.

## QuietHoursWindow — `copy_strings`
- **neededByPhase**: P8 (quiet-hours suppression) / `PATCH /settings/notifications`
- **sourceScreens**: `screen_34_notifications` (settings-only)
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `quiet_hours_window` | 10 PM – 7 AM | en-dash `–` with spaces; start 22:00, end 07:00; tappable (`›`) editable picker |
| `quiet_hours_header` | QUIET HOURS | section header |

No quiet-hours on onboarding screen 7. `ARCHITECTURE` does not specify quiet-hours storage; `§A` pins dispatch to 08:00 Europe/Madrid (per-user TZ deferred) — quiet-hours-vs-dispatch interaction needs reconciliation.

## Copy strings — notification screens 7 / 34 — `copy_strings`
- **neededByPhase**: P8 notifications copy / i18n (`§I` milestone 8)
- **completeness**: exhaustive-from-screen (for these two screens; PUSH message templates are separate)

| code | label | source | extra |
|------|-------|--------|-------|
| `s7.step_tag` | Step 7 of 7 · Reminders | screen 7 | section tag (middot) |
| `s7.title` | Stay in tune | screen 7 | h1 |
| `s7.subtitle` | Soft nudges only. Mute anytime. | screen 7 | subtitle |
| `s7.primary_cta` | Allow & finish | screen 7 | requests OS push + completes onboarding |
| `s7.skip_cta` | Not now | screen 7 | secondary/skip |
| `s34.section_tag` | Settings | screen 34 | top section tag |
| `s34.title` | Notifications | screen 34 | page title |
| `s34.footer` | Lumen never sends marketing or promotional pings | screen 34 | footer reassurance; leading `✦` decorative |

(Screen 7 onboarding copy is duplicated in the Onboarding module table — see note in Dedup section.) Final PUSH message templates (e.g. "Your lab is ready to review" from `§E`) are separate and not on these screens.

---

# Module: Profile, Cycle Settings & Condition

## profile.baselineFields — `code_label_table`
- **neededByPhase**: P4 (Onboarding/Settings) — backs `GET /me`, `PATCH /me`, screens 4 baseline + 31 profile
- **sourceScreens**: `screen_31_profile`
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `age` | Age | value 32; integer years |
| `height` | Height | value 165 cm; unit cm |
| `weight` | Weight | value 60.4 kg; unit kg, 1 decimal |

Section "BASELINE". **Schema gap:** `§` models `user_profile_enc` as `display_name_enc`/`dob_enc`/`bio_enc` only — no age/height/weight columns. `dob_enc` implies age is derived; height/weight have no documented home. Confirm whether height/weight live in `user_profile_enc` (new columns) or `body_metrics` (`weight_kg` already exists) with PO.

## profile.identityFields — `code_label_table`
- **neededByPhase**: P4 — account header card on screen 31
- **sourceScreens**: `screen_31_profile`
- **completeness**: exhaustive-from-screen

| code | label (sample) | extra |
|------|----------------|-------|
| `display_name` | Sara R. | → `user_profile_enc.display_name_enc` |
| `email` | sara@email.com | → `users.email_hash` lookup; sample only |
| `avatar_initials` | SR | derived initials; not stored |

Tappable card (chevron `›`) → account edit. Values are sample data; codes are field identifiers.

## profile.conditionFields — `code_label_table`
- **neededByPhase**: P4 — CONDITION section on screen 31; clinical metadata
- **sourceScreens**: `screen_31_profile`
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `endo_status` | Endo status | value "Diagnosed · stage II" (status + staging) |
| `diagnosed_on` | Diagnosed | value "Aug 2023"; month-year |
| `surgeries` | Surgeries | value "1 laparoscopy"; count + procedure |

Section "CONDITION". **Definite schema gap:** `ARCHITECTURE` models no endo-condition fields. Likely belong in `user_profile_enc` (encrypted) per the on-screen health-data privacy note. Raise with PO.

## EndoDiagnosisStatus — `enum`
- **neededByPhase**: P4 — drives `endo_status`; C# enum candidate
- **sourceScreens**: `screen_31_profile`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `diagnosed` | Diagnosed | only status shown ("Diagnosed · stage II") |

Full enum (e.g. suspected / self-reported / undiagnosed) NOT on screen — confirm full set with PO. Treat as a starter.

## EndoClinicalStage — `ordinal_scale`
- **neededByPhase**: P4 — staging sub-value of `endo_status`
- **sourceScreens**: `screen_31_profile`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `stage_2` | stage II | ord 2; only stage shown |

Only "stage II" appears. Endometriosis is clinically staged I–IV (rASRM). **DO NOT invent stages I/III/IV** — per task rule, clinical staging values are out of scope. Confirm canonical staging scale (rASRM I–IV vs other) with PO/clinician. UI uses Roman numerals; code uses arabic for stability.

## cycleSettings.yourPattern — `code_label_table`
- **neededByPhase**: P4 — `GET/PATCH /settings/cycle`, screen 32 "YOUR PATTERN"
- **sourceScreens**: `screen_32_cycle_settings`
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `avg_cycle_length` | Avg cycle length | value "29 days"; integer days |
| `avg_period_length` | Avg period length | value "5 days"; integer days |
| `regularity` | Regularity | value "Irregular ±4d"; enum bucket + numeric variability (days) |

"Irregular ±4d" confirms regularity = bucket label + ±variability days. Drives phase prediction; maps to `PATCH /settings/cycle`.

## cycleSettings.predictionToggles — `enum`
- **neededByPhase**: P4 — boolean settings under "PREDICTIONS" on screen 32
- **sourceScreens**: `screen_32_cycle_settings`
- **completeness**: exhaustive-from-screen

| code | label | extra |
|------|-------|-------|
| `phase_prediction` | Phase prediction | **ON** by default (accent track) |
| `auto_detect_period_start` | Auto-detect period start | **ON** by default |
| `show_fertility_window` | Show fertility window | **OFF** by default (muted track) |

Section "PREDICTIONS". Each is a stored boolean preference; default states read from CSS toggle styling.

## cycleSettings.firstDayOfWeek — `enum`
- **neededByPhase**: P4 — display preference under "DISPLAY" on screen 32
- **sourceScreens**: `screen_32_cycle_settings`
- **completeness**: illustrative-confirm-with-PO

| code | label | extra |
|------|-------|-------|
| `monday` | Monday | current value, shown "Monday ›" (drill-in picker) |

Field "First day of week"; section "DISPLAY". Only "Monday" shown; full option set (Sunday/Saturday/etc.) NOT enumerated. Likely candidates sunday/monday/saturday — **do not assume**; confirm with PO.

## Copy strings — profile/cycle settings screens 31 / 32 — `copy_strings`
- **neededByPhase**: P4 + i18n milestone 8
- **completeness**: exhaustive-from-screen

| code | label | source | extra |
|------|-------|--------|-------|
| `s31.settings_tag` | Settings | screen 31 | section tag (uppercase via CSS) |
| `s31.title` | Profile & health | screen 31 | title |
| `s31.section_baseline` | BASELINE | screen 31 | section label |
| `s31.section_condition` | CONDITION | screen 31 | section label |
| `s31.label_age` | Age | screen 31 | field label |
| `s31.label_height` | Height | screen 31 | field label |
| `s31.label_weight` | Weight | screen 31 | field label |
| `s31.label_endo_status` | Endo status | screen 31 | field label |
| `s31.label_diagnosed` | Diagnosed | screen 31 | field label |
| `s31.label_surgeries` | Surgeries | screen 31 | field label |
| `s31.footer_privacy` | ✦ Health info stays on your device unless you export | screen 31 | sage footer; `✦` decorative |
| `s32.settings_tag` | Settings | screen 32 | section tag |
| `s32.title` | Cycle | screen 32 | title |
| `s32.section_your_pattern` | YOUR PATTERN | screen 32 | section label |
| `s32.section_predictions` | PREDICTIONS | screen 32 | section label |
| `s32.section_display` | DISPLAY | screen 32 | section label |
| `s32.footer_retrain` | ✦ Predictions retrain after every 3 logged cycles | screen 32 | sage footer; `✦` decorative |

**Product rules embedded in footers:** privacy ("Health info stays on your device unless you export" — reinforces encrypted `user_profile_enc` + GDPR export, `§F`); retrain cadence ("Predictions retrain after every 3 logged cycles" — capture for the inference engine). Values like "32", "165 cm", "Diagnosed · stage II", "April 2026" are user/sample data, not strings.

---

# Appendix A — Cross-cutting conflicts to resolve with PO (consolidated)

| # | Conflict | Screens / source | Recommendation |
|---|----------|------------------|----------------|
| 1 | **`estradiol` code vs "Estrogen" label** | screens 6/33 vs `§E` | Use code `estradiol`, label "Estrogen" |
| 2 | **`glp1` code vs "GLP-1" label** | screens 6/33 vs `§E` | Use code `glp1`, label "GLP-1" |
| 3 | Hormone default visibility: **all 7 ON (onboarding, s6)** vs **4 ON / 3 OFF (settings, s33)** | s6 vs s33 | Onboarding likely the true default; s33 may be a populated state — confirm |
| 4 | Hormone unit casing: screen `pg/mL`/`dL`/`L` vs `§E` whitelist `pg/ml`/lowercase | s33 vs `§E` | Admin `ref_hormone_range` is authoritative — reconcile casing |
| 5 | **Three numeric pain/intensity scales:** pain 0–9 (s9), body-map readout 7 (s13), `symptoms.intensity` 1–5 (`§D`) | s9, s13, `§D` | `§D` 1–5 authoritative for `symptoms.intensity`; quick-checkin pain (0–9) likely a separate field — confirm |
| 6 | Mood owning module: Symptoms UI vs `cycle_day_logs.mood` (`§D`) | s9 vs `§D` | Confirm owning module + numeric mapping (0–3 vs 1–4) |
| 7 | Notification label drift: **"Phase shifts" (s7)** vs **"Phase shift" (s34)** | s7 vs s34 | Recommend "Phase shift" (singular) |
| 8 | Notification default-state drift (period_prediction, medication_reminders OFF in s7 vs ON in s34) | s7 vs s34 | Onboarding (s7) is authoritative initial seed |
| 9 | **Report sharing:** Link/Email + 30-day link (s30) vs `§A` "no server-side sharing, no signed URLs" | s30 vs `§A` | Confirm Link/Email deferred (PDF-only v1) or revisit `§A` |
| 10 | Schema gaps with no column: report `effectiveness` (s26), activity `energy-after` (s25), body-feel tags (s23), symptom `type`/`triggers`/`related` (s12), profile `height`/`weight`/condition fields (s31) | various | Add columns / confirm storage shape with PO |
| 11 | `medication_logs.status` (taken/skipped/snoozed) has **no mockup** | `§D` only | Author logging UX + i18n labels with PO |

# Appendix B — Deduplication notes

- **Onboarding screen 7 copy** appears in both the Onboarding module (referenced) and the Notifications module copy table. It is rendered once with full detail in the **Notifications** module copy table (`s7.*`); the Onboarding module references it. Treat as a single string set keyed `s7.*`.
- **Hormone 7-member set** is referenced by five definitions (HormoneCode, HormoneCategory, HormoneChartDefaultSelection, HormoneDisplayUnit, HormoneDisplaySettingDefault). Membership/order are identical across all five; only the per-row "extra" (color / category / default / unit / toggle) differs. The canonical code↔label pairing lives in **HormoneCode**; the others reuse it.
- **BodyCalendarChip** (Weight/BMI/Body fat) is the chart-view subset of **BodyMetric**, not an independent enum — codes map 1:1 (`weight`, `bmi`, `body_fat`).
- **MedicationGroup** (DAILY / AS NEEDED) is a 2-way derived view over **MedicationFrequency**, not a stored field.
- **Section labels** (LOCATION, TYPE, DATE RANGE, YOUR PATTERN, etc.) render uppercase via CSS `text-transform`; i18n source strings should be stored sentence-case per CLAUDE.md and uppercased in the view layer.
