# Lumen — Clinical Sourcing Asks (for a clinician / reproductive endocrinologist + biostatistician)

> These are the **clinically-loaded definitions an engineer must not invent.** Each is a fill-in template: the clinical reviewer supplies the values + a source citation + a sign-off; the engineer encodes them as `ref_*` seed data and `ref_insight_rule` parameters (never hard-coded). **Start this engagement during P3–P5** — it has lead time and gates P6 (inference engine) and P7b (lab parsing).
>
> For every row: **Source** = citation (guideline/literature/lab standard) and **Signed off by / date**. Reference data is versioned via `valid_from`/`valid_to` so edits never retroactively invalidate historical labs (a lab is validated against the range effective at its `measured_on`).
>
> Context: target population is **menstruating individuals of reproductive age** (see decision D-23); the app tracks endometriosis, so some users are on cycle-suppressing therapy — see C-12.

> **STATUS 2026-07-14 (r16 decision session):** All 15 items below now carry **PO-interim values** (approved by the product owner as working defaults, from a cited-research + adversarial-review pass) — **clinician sign-offs still PENDING (zero clinical sign-offs).** The clean reviewer document is **[`clinical-signoff-pack.md`](./clinical-signoff-pack.md)** — send that to the clinician. Each PO-interim value gates estimator inclusion / prediction confidence only; per the HARD PRINCIPLE no bound ever blocks data entry. **Two PO overrides of the researched default to flag for the clinician: C-03 (mean, not median) and C-02 (fertile-window overlay included).**

---

## A. Cycle phase model — gates P4a (calendar) & P6 (engine)

### C-01 Phase-boundary rules (the 4 phases)
Define how each phase is computed from logged `period_start`/`period_end` events + estimated ovulation. Deterministic — no ML. `Ov` (estimated ovulation) = `next_period_start − 14` (14-day luteal length as the stable back-count anchor).

| Phase | Starts when | Ends when | Notes |
|---|---|---|---|
| Menstrual | `period_start` (P0) | `period_end` (Pe) | from logged bleeding events only |
| Follicular | `period_end + 1` | `Ov − 3` (day before ovulatory band) | variable-length; collapses to 0 in short cycles (clamp, never negative) |
| Ovulatory | `Ov − 2` | `Ov + 1` | a=2, b=1 → 4-day band. Fertile-window overlay (Ov−5…0) is a **separate** informational overlay (per C-02), not this band |
| Luteal | `Ov + 2` | `next_period_start − 1` | luteal length convention = **14 days** (the ovulation back-count anchor; displayed luteal band ≈12 d) |

No ovulation estimate (irregular / cycle-suppressed): classify **Menstrual only** from logs; other 3 = `unknown`, low confidence. Bounds gate confidence/estimator inclusion ONLY — never data entry.
**Source:** Reed & Carr, *The Normal Menstrual Cycle* (Endotext/NCBI NBK279054, 2018); ACOG fertility-awareness guidance; Wilcox, Weinberg & Baird (BMJ 2000 / NEJM 1995). **Signed off / date:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-01).**

### C-02 Ovulation estimation
Method: **back-count from predicted next period by fixed luteal length (14 d)** (chosen over forward midpoint `round(cycle_len/2)`, which is only correct at a 28-day cycle). `estimated_ovulation = predicted_next_period_start − 14`  ⇔  `ovulation_day_index = estimated_cycle_length − 14`. `LUTEAL_LENGTH_DAYS = 14` — versioned config constant. **Ovulatory window width: ovulation ± 2 days** (feeds C-01 a/b).
**Fertile-window overlay — INCLUDED in v1 (PO decision; researched recommendation was to omit):** rendered as **ovulation −5 … 0** (6-day Wilcox interval ending on the day of ovulation), **informational only, with a mandatory non-contraceptive disclaimer** ("not for pregnancy prevention or timed conception"). Ovulation estimated only when the C-03 estimator is confident and the user is not in a C-12 no-cycle/suppression state; low confidence hides/widens the band and **never blocks logging**.
**Source:** ACOG *Fertility Awareness-Based Methods*; Wilcox BMJ 2000 / NEJM 1995; ASRM *Optimizing Natural Fertility* (2022). **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending** — clinician asked to confirm the fertile-window overlay is acceptable for this population.

### C-03 Cycle- & period-length estimators + valid bounds
Estimator: **MEAN** cycle & period length **(PO decision; researched recommendation + adversarial review favored MEDIAN for endo outlier-robustness — flagged for clinician)** over the last **6** completed cycles; **min 3 completed cycles** before the computed estimate overrides the onboarding self-report. **Clinical inclusion bounds** (gate estimator inclusion + confidence only): **cycle 21–45 d, period 1–10 d** — any out-of-bounds cycle/period is excluded from the estimator and reduces confidence but is always logged & shown (so the mean is computed only over in-bounds cycles). **Non-blocking sanity guard** (soft "double-check?" hint, never blocks save): avg cycle 10–120 d, period 1–30 d.
> **Two-tier rule (in force):** observed events are **never** clinically validated; typed inputs get sanity bounds only. Clinical bounds gate ONLY estimator inclusion + prediction confidence. **Bounds must never block data entry** (endo cycles are irregular by nature).
**Source:** FIGO 2018 (Munro et al., normal frequency 24–38 d, duration ≤8 d) widened toward ACOG (~90% of cycles 21–45 d); ESHRE 2022 (irregularity caveat). **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-03).**

### C-04 Period vs spotting; auto-detect `period_start`
`flow_intensity` scale (1–4): **1 = spotting** (bleeding not large enough to require sanitary protection — FIGO 2018), **2 = light**, **3 = medium**, **4 = heavy** (soaks protection ≤1–2 h and/or clots ≥25 mm — HMB marker, see C-15). Stored smallint 1–4.
**Period-qualifying threshold:** a day is menstrual bleeding iff `flow_intensity ≥ 2`; spotting (1) alone is not period-qualifying. **Auto-detect `period_start`** (deterministic) = the first `flow ≥ 2` day that opens a NEW episode, i.e. separated from the most recent prior `flow ≥ 2` day by a bleeding-free interval of **≥ 3 days** (endo-tolerant default; configurable 2–3). Contiguous leading spotting attaches to the episode as premenstrual spotting, but Day 1 = first `flow ≥ 2` day. Spotting never auto-creates a period; on suppression, breakthrough spotting stays silent; **manual override always wins**; detection never blocks or mutates a raw log.
> **Interim in force:** `flow_intensity` 1–4 {1 spotting, 2 light, 3 medium, 4 heavy}. Period-vs-spotting auto-detection now defined above (PO-interim).
**Source:** FIGO 2018 (Munro et al.); Clue tracking conventions; Higham PBAC (1990). **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-04).**

### C-05 Regularity definition
Metric = **shortest-to-longest cycle-length range** over the last 6 cycles (min 3 completed cycle-lengths). Tiers: **Regular ≤ 7 d** (FIGO), **Somewhat irregular 8–14 d** *(product-defined)*, **Irregular ≥ 15 d** *(product-defined)*. Flat ≤7 d ceiling in v1 (FIGO age-banding to ≤9 d for ages 18–25 & 42–45 deferred to v2). < 3 cycles = "insufficient data" (no label); cycle-suppressed = "not applicable".
**Does regularity modulate the confidence score? YES** — multiplier on prediction confidence + forecast-window half-width: Regular ×1.0 (±2 d) · Somewhat ×0.7 (±4 d) · Irregular ×0.4 (±7 d) · insufficient/suppressed → prediction suppressed, range-only. Modulation is display/estimator-side ONLY; it never blocks data entry. No reassuring copy attached to "somewhat irregular".
**Source:** FIGO 2018 (Munro et al., regularity = shortest-to-longest variation ≤7 d ages 26–41); ACOG CO 651. *(The 8–14/≥15 d cutoffs and the ×multipliers are product design, not guideline-derived.)* **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-05).**

---

## B. Hormones & labs — gates P7b

### C-06 Hormone reference ranges (`ref_hormone_range`)
Source of record: **Mayo Clinic Laboratories** (assay noted per analyte). Units = app canonical units. mIU/mL ≡ IU/L for LH/FSH. Ranges are **assay-dependent** and gate estimator inclusion + confidence only — never data entry; **not applied when cycle phase is unknown/suppressed**.

| hormone_code | phase / condition | low | high | unit | assay |
|---|---|---|---|---|---|
| estradiol | menstrual / early-follicular | 25 | 120 | pg/mL | immunoassay (ESTS) |
| estradiol | follicular | 25 | 120 | pg/mL | immunoassay (ESTS) |
| estradiol | ovulatory / mid-cycle peak | 30 | 520 | pg/mL | immunoassay (ESTS) |
| estradiol | luteal | 35 | 250 | pg/mL | immunoassay (ESTS) |
| progesterone | follicular | 0 | 0.89 | ng/mL | PGSN |
| progesterone | luteal | 1.8 | 24 | ng/mL | PGSN |
| lh | follicular | 1.8 | 11.8 | mIU/mL | LH |
| lh | mid-cycle peak | 7.6 | 89.1 | mIU/mL | LH |
| lh | luteal | 0.6 | 14.0 | mIU/mL | LH |
| fsh | follicular | 3.03 | 8.08 | mIU/mL | FSH |
| fsh | mid-cycle peak | 2.55 | 16.69 | mIU/mL | FSH |
| fsh | luteal | 1.38 | 5.47 | mIU/mL | FSH |
| testosterone (total) | female ≥19y | 8 | 60 | ng/dL | TTST (LC-MS/MS) |
| cortisol | A.M. (7–9 a.m.) | 7 | 25 | µg/dL | CORT |
| cortisol | P.M. (3–5 p.m.) | 2 | 14 | µg/dL | CORT |
| glp1 | — | — (no reference band — see C-08) | | pmol/L | — |

Estradiol low-phase lower bounds set to 25 pg/mL (immunoassay reporting floor). Testosterone total-only in v1. Each row seeded with assay provenance + `valid_from` + version.
**Signed off / date:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-06).**

### C-07 Per-hormone accepted-unit whitelist + conversions
Conversion factors are molecular-weight-derived (or WHO potency for LH/FSH), assay-independent. Casing normative: litre uppercase `L`; micro = MICRO SIGN `µ` (U+00B5). Input aliases (`mcg/dL`, `ug/dL`, lowercase) normalise before the factor is applied. Unrecognized unit → logged + flagged, excluded from estimator only (never blocks entry).

| hormone_code | canonical unit | accepted alt units | conversion to canonical |
|---|---|---|---|
| estradiol | pg/mL | pmol/L; ng/L | pmol/L × 0.2724 (÷3.671); ng/L × 1 |
| progesterone | ng/mL | nmol/L; µg/L | nmol/L × 0.3145 (÷3.180); µg/L × 1 |
| lh | IU/L | mIU/mL | × 1 (identical, WHO potency unit) |
| fsh | IU/L | mIU/mL | × 1 (identical, WHO potency unit) |
| testosterone | ng/dL | nmol/L; ng/mL | nmol/L × 28.84 (÷0.03467); ng/mL × 100 |
| cortisol | µg/dL | nmol/L | nmol/L × 0.03625 (÷27.59) |
| glp1 | pmol/L | pg/mL | pg/mL × 0.3032 (÷3.299) |

Cortisol canonical = µg/dL (PO decision; consistent with the other steroid mass units). Compute with full-precision factors; retain original (value, unit) pair for provenance.
**Source:** AMA Manual of Style 11th ed. §18; PubChem MWs; WHO International Standards (LH/FSH). **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-07).**

### C-08 GLP-1 specifics
**DECISION (PO-interim): DEFER endogenous GLP-1** as a reference-banded / estimator hormone in v1 — not on standard panels, no validated clinical reference interval, special pre-analytics (DPP-4 inhibitor + chilled), no endo interpretation. Keep it **log-only** (value shown verbatim, "no standardized reference range", no flag, no estimator/confidence participation). Canonical unit if ever stored = **pmol/L, active/intact** form. **GLP-1 receptor-agonist MEDICATIONS route to the medication log** (C-13), not the hormone chart. Re-include later only when (a) a clinician defines a concrete endo/metabolic use-case AND (b) a major reference lab publishes a standardized assay + validated reference interval.
**Source:** Bak et al. (Diabetes Obes Metab 2014); WHO ATC/DDD (A10BJ). **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-08).**

---

## C. Inference outputs — gates P6 (with product owner on weights)

### C-09 Data-completeness score (0–100)
Named a **"data-completeness" index** (PO decision), **not** a calibrated prediction probability or validated clinical instrument. Additive, four capped per-factor contributions, clamped [0,100]:

| factor | max points | curve | notes |
|---|---|---|---|
| Lab phase coverage (of 4) | 40 | linear per phase | 10 pts × distinct phases with ≥1 confirmed lab |
| Cycle history (n complete cycles) | 30 | stepped, diminishing | 0/8/15/22/26/28/30 for 0…≥6 cycles |
| Daily check-ins (n days) | 20 | linear capped | round(20 × min(d,28)/28), trailing 28-day window |
| Body-map points | 10 | linear capped | 2 × min(entries,5) |

"Full coverage" = all four at max. **Display bands:** Low 0–39 · Medium 40–69 · High 70–100. Below 20 → suppress the numeric phase prediction, show a range. **Cycle-suppressed users:** waive the 30 cycle-history points, renormalize the remaining 70→100. Score gates prediction display only, never data entry.
**Source:** Clue (3-cycle threshold); Bull et al. *npj Digital Medicine* 2019; Li et al. **JAMIA** 2022;29(1):3–11. *(Weights are a product+clinical judgment; no regularity term — hence the "data-completeness" naming.)* **Sign-off (clinical + product):** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-09).**

### C-10 Missing-data card catalog
Four `ref_insight_rule` rows, foundational-/lowest-effort-first priority. Engine evaluates all, keeps qualifying cards, sorts by `priority` asc, surfaces the top card (screen 8/20); full ranked list on screen 21. Copy plain-language, encouraging, never pathologizing.

| priority | card_code (rule_code) | trigger | title / body / CTA |
|---|---|---|---|
| 10 | start_checkins (`missing_data.checkins`) | <3 check-ins in last 14 d | **Try a daily check-in** — "A quick daily check-in — how you feel, your energy, any symptoms — helps Lumen learn your patterns over time. It only takes a moment." · Start a check-in / Maybe later |
| 20 | log_more_cycles (`missing_data.cycles`) | <3 confirmed cycles | **Keep logging your cycles** — "Everyone's cycle is different. Logging a few cycles helps Lumen learn your unique rhythm and time its predictions to you." · Log today / Maybe later |
| 30 | start_body_map (`missing_data.body_map`) | 0 body-map points | **Map where you feel it** — "Marking where symptoms show up adds detail to your picture and can make your patterns and reports clearer." · Open body map / Maybe later |
| 40 | lab_phase_coverage (`missing_data.lab_coverage`) | <4 phases lab-confirmed | **Sharpen your hormone picture** — "Lumen learns your hormones phase by phase. Adding a study from each phase helps your predictions get more accurate." · Add {next_uncovered_phase} study / Maybe later |

Every card dismissible ("Maybe later" snoozes 7 days). Suppress `log_more_cycles` + `lab_phase_coverage` while cycle-tracking is paused (C-12) **or** when an active cycle-suppressing medication is logged. No causal/health-outcome claims.
**Source (copy-tone):** CDC Clear Communication Index; NHS content standard. Thresholds inherit from C-03/C-09. **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-10).**

### C-11 Insights-hub methods + thresholds + claim wording
**Shared rules (seed once as global `ref_insight_rule` params):**
- **"Pain" = daily worst (max) NRS 0–10** across endo pain symptoms (dysmenorrhea, non-menstrual pelvic pain, deep & superficial dyspareunia, dyschezia, low-back); exclude nausea/fatigue/mood/bloating/headache. Display scale 0–10.
- **Methods:** Spearman ρ (ordinal, outlier-robust — never Pearson); phase-stratified means; two-group mean-difference.
- **Global surfacing gate:** n ≥ 10 paired (prefer ≥20) **and** |ρ| ≥ 0.30 (a **product noise-floor, not a "meaningful" threshold**), or ≥~15% group diff. Never show p-values.
- **Wording (Haber 2022 ladder):** allowed = *associated with / linked to / tends to / clusters with / in your logs*; forbidden = *causes / reduces / improves / prevents / effect / triggers*. Persistent footer: *"Patterns in your own data — associations, not medical advice or proof of cause."*

| insight_code | method | min data | numeric threshold | approved copy template |
|---|---|---|---|---|
| strongest_link | per-cycle offset of peak-pain day from `period_start`; median offset + % consistency | ≥3 cycles, each ≥1 pain log | show only if consistency ≥60% | "In your logs, pain has tended to peak about {N} days before your period — in {X}% of tracked cycles." *(branch wording for offset ≤0: "around the start of / during the first days of your period")* |
| pain_by_phase | mean of daily worst-pain NRS by phase | ≥3 pain-days per phase | — | "Your average pain by cycle phase, from your logs." |
| activity_vs_pain | two-group mean-difference, activity day D → pain D+1 (lag), ≥30 min split (illustrative anchor, not "dosing") | ≥10 days; ≥5/group | ≥30 min | "In your logs, days after 30+ min of movement have had {X}% lower average pain — an association in your data, not proof movement lowers pain." |
| mood_vs_estrogen | **drop the absolute pg/mL cutoff**; default = % low-mood days by phase; **gated to non-suppressed users**; estrogen mechanism lives in the explainer, not the card | ≥3 cycles w/ mood logs, ≥3 eligible days/phase | none | "In your logs, lower-mood days have tended to cluster in your late-luteal and menstrual phases." |

**Source:** Schober 2018 (Spearman use); Haber et al. AJE 2022 + FTC 2023; ESHRE/ASRM pain scoring; Schmidt JAMA Psychiatry 2015 (estrogen withdrawal, not level). **Sign-off (clinical + biostatistics):** **PO-interim 2026-07-14; clinician + biostatistician sign-off pending (see clinical-signoff-pack.md C-11).**

---

## D. Catalogs & population

### C-12 Eligible population & cycle-suppression handling
**v1 population:** menstruating individuals of reproductive age — a **design target, NOT a data-entry/age gate** (any minimum-age rule is a separate legal/consent decision); phenotype-driven, gender-inclusive; no upper age cutoff.
**No-detectable-cycle handling:** one **user-controlled cycle-tracking pause** with **`pause_reason` {pregnancy, hormonal_suppression, surgical, menopause, other}** *(PO-extended enum)*. While paused: no phase predictions, explicit "phases unavailable" state, paused spans excluded from ALL estimators, **entry never blocked** (spotting still logs). **Resume is user-controlled and always available for every pause reason** *(PO)*; resume = fresh cycle start (no pre/post merge). The engine may *suggest* a pause but never auto-pauses silently. **Amenorrhea alternate onboarding branch** (reason → therapy/start-date → still-bleeding? → optional last-period → confirm) replaces the mandatory last-period date (D-02).
> **Safety rule:** for `pause_reason = pregnancy`, hormone-range interpretation is **disabled entirely** (labs still loggable) — non-pregnant "any-phase" ranges are **not** substituted. The suggest-pause copy must never suppress a C-15 red-flag.
**Source:** ESHRE 2022 & NICE NG73 (first-line hormonal therapy suppresses ovulation/menstruation); dienogest amenorrhea cohort (ENVISIOeN, Reprod Sci 2022 — normal bleeding 85.8%→17.5%, amenorrhea 3.5%→70.8% by month 24; Asian cohort — directional); WHO/ACOG menopause. **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-12).**

### C-13 `ref_medication` starter catalog (endometriosis)
Doses are *typical*, not prescriptive. Pick-list only — never gates logging; free-text "other" always available. All ATC codes verified against the WHO ATC/DDD Index (2025/26). Category enum (PO-extended): **{hormonal, pain, supplement, bleeding, metabolic}**.

| name | form | typical dose (range) | ATC code | category |
|---|---|---|---|---|
| Dienogest | tablet | 2 mg once daily, continuous | G03DB08 | hormonal |
| COC (levonorgestrel + ethinylestradiol) | tablet | EE 20–35 µg + LNG 100–150 µg daily; often continuous | G03AA07 | hormonal |
| Norethisterone acetate | tablet | 5 mg/day (2.5–15) | G03DC02 | hormonal |
| Medroxyprogesterone acetate | tablet / depot | oral 10 mg 1–3×/day; depot 104 mg SC / 150 mg IM q3mo | G03DA02 | hormonal |
| Levonorgestrel IUD (LNG-IUS) | IUD | 52 mg, ~20 µg/day, up to 5–8 y | G02BA03 | hormonal |
| Leuprorelin (leuprolide) | depot inj | 3.75 mg monthly / 11.25 mg q3mo; ≤6 mo w/o add-back | L02AE02 | hormonal |
| Goserelin | SC implant | 3.6 mg monthly / 10.8 mg q3mo; ≤6 mo w/o add-back | L02AE03 | hormonal |
| Elagolix | tablet | 150 mg QD, or 200 mg BID (≤6 mo) | H01CC03 | hormonal |
| Relugolix combination | tablet | relugolix 40 + estradiol 1 + NETA 0.5 mg, one tablet daily | H01CC54 | hormonal |
| Danazol | capsule | 200–800 mg/day divided (androgenic SEs) | G03XA01 | hormonal |
| Letrozole | tablet | 2.5 mg once daily (off-label; with a progestin/OCP) | L02BG04 | hormonal |
| Drospirenone-only pill | tablet | 4 mg once daily (24/4 or continuous) | G03AC10 | hormonal |
| Naproxen | tablet | 250–500 mg BID (max ~1000–1250 mg/day) | M01AE02 | pain |
| Ibuprofen | tablet | 400 mg q6–8h (OTC max 1200; Rx max ~2400–3200, region-dependent) | M01AE01 | pain |
| Paracetamol (acetaminophen) | tablet | 500–1000 mg q4–6h (max 3–4 g/day) | N02BE01 | pain |
| Tranexamic acid | tablet | 1–1.3 g TID during menses (≤~4 days/cycle) | B02AA02 | bleeding |
| Omega-3 (EPA+DHA) | capsule | ~1–2 g/day | C10AX06 | supplement |
| Vitamin D3 (colecalciferol) | tablet/drops | 800–2000 IU/day | A11CC05 | supplement |
| Magnesium | tablet | ~200–400 mg elemental/day | A12CC10 | supplement |
| Semaglutide | inj/tablet | per product | A10BJ06 | metabolic |
| Dulaglutide | injection | per product | A10BJ05 | metabolic |
| Liraglutide | injection | per product | A10BJ02 | metabolic |
| Exenatide | injection | per product | A10BJ01 | metabolic |
| Lixisenatide | injection | per product | A10BJ03 | metabolic |
| Tirzepatide | injection | per product | A10BX16 | metabolic |

GLP-1 agonists (metabolic) included per the C-08 routing decision. Seed each row with `valid_from` + source + `version`.
**Source:** WHO ATC/DDD Index (2025/26); ESHRE 2022; NICE NG73/NG88; product labels (Visanne, Lupron, Orilissa, Ryeqo). **Signed off / date:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-13).**

### C-14 Endometriosis staging & surgery vocabulary
**Staging: rASRM I–IV** — Stage I *minimal* (1–5), II *mild* (6–15), III *moderate* (16–40), IV *severe* (>40). **User-entered, nullable, never inferred; does NOT correlate with pain** (no "higher stage = worse" copy; pin canonical labels in code so they aren't changed to the erroneous "extensive"). **#Enzian** (Keckstein 2021) = complementary deep-endo system, **deferred to v2** (optional free text).
**Surgery-type controlled list** (codes, multi-select, + `other`): `diagnostic_laparoscopy`, `excision`, `ablation` (ablation/fulguration), `endometrioma_cystectomy`, `adhesiolysis`, `hysterectomy`, `oophorectomy`, `bowel_resection`, `ureterolysis`. Keep excision vs ablation distinct. Surgical *approach* (laparoscopic/open/robotic/VATS) = separate optional field, deferred v2.
**PO logging-vocab review:** keep `chest_shoulder` (thoracic/diaphragmatic endo is real — catamenial chest pain, phrenic-nerve referred shoulder pain); display `depressed_mood` as **"low mood"** (not a screener); triggers `physical_strain`/`poor_sleep`/`weather` = co-occurrence, never causation (constraint on C-11 copy); **`heavy_menstrual_flow` = an independent user-facing HMB flag** (FIGO term), NOT double-counted vs `flow_intensity=4`; its red-flag threshold is authored jointly with C-15.
**Source:** ASRM revised classification 1996/1997 (Fertil Steril 67:817–21); ESHRE 2022; Keckstein #Enzian 2021; FIGO 2018; thoracic-endo (Nezhat 2024). **Sign-off:** **PO-interim 2026-07-14; clinician sign-off pending (see clinical-signoff-pack.md C-14).**

### C-15 Red-flag / crisis symptom guidance (safety)
**DECISION: YES** — surface a **passive, non-diagnostic, NON-BLOCKING** safety note shown *after* the entry saves; calm/neutral tone (no alarm chrome, no diagnosis), dismissible, at most once per triggering entry, never names a condition. **SAFETY-CRITICAL — requires clinician + legal (L-04) sign-off before shipping.**

**Fixed safety-netting footer (verbatim, appended to every note):**
> Lumen isn't a medical or emergency service and can't assess your symptoms. If you're worried, contact your doctor or urgent care — and if it feels like an emergency, call your local emergency number right away.

**Triggers + opener wording:**
1. **Top-of-scale pain (10/10):** "You logged pain at the very top of the scale. Pain this severe — especially if it's sudden, or the worst you've ever felt — is worth getting checked soon."
2. **Very heavy bleeding** (highest flow option, or soaking ≥1 pad/tampon per hour for ≥2 h, or clots larger than a coin ≈2.5 cm): "You logged very heavy bleeding. Soaking through a pad or tampon every hour for a couple of hours in a row, or passing clots bigger than a coin, is worth getting checked."
3. **Fever ≥38.0 °C (100.4 °F) + pelvic pain:** "You logged a fever together with pelvic pain. That combination is worth getting checked promptly."
4. **Fainting / near-faint:** "You logged feeling faint or passing out. That's worth getting checked, especially alongside pain or heavy bleeding."
5. **Severe pain + pregnancy not excluded:** "You logged severe pain and there's a chance you could be pregnant. If you are pregnant, sudden or one-sided pain can be an emergency and needs to be checked urgently."
6. **Unable to urinate / pass stool:** "You logged being unable to pass urine (or stool). This can be serious — please get it checked right away."

Fever fires at the lower 38.0 °C cutoff (the PID *urgent* marker is 38.3 °C/101 °F). Footer stays locale-agnostic; keep the "≈2.5 cm" clot size in every locale.
**Source:** ACOG (HMB/AUB/PID FAQs); NHS/Mayo (ectopic); NIDDK (urinary retention); Mayo (bowel obstruction); NICE NG12 + BJGP (safety-netting). **Sign-off:** **PO-interim 2026-07-14; clinician + legal (L-04) sign-off pending (see clinical-signoff-pack.md C-15).**

### C-16 Body-map front/back membership (OPEN — no PO-interim value)
**NEW 2026-08-21, raised by P4b-T21 (screen 13, the body map). This is the only row in this document with no PO-interim value: the product owner deliberately declined to invent one.**

Screen 13 asks the user to mark **where** the pain is on a body silhouette. Each placed point stores an anatomical `region` **and** a `side` — `front` or `back`. The 8 regions are ratified (C-14 vocab review); **`side` is not**: no source anywhere assigns a region to a view.

**Why this cannot be a design decision.** `side` is defined as *anatomical* in three shipped sources (`Symptom.cs`, `symptoms_repository.dart`, `ARCHITECTURE.md §37/§51`), the app **never displays it back**, and v1 has no edit or delete for a symptom row — so a wrong value is **written once, invisible, and uncorrectable**. `ARCHITECTURE.md:37` names the P6/P7 **heatmap** as the consumer that will act on it, so drawing `lower_back` on an anterior figure *is* the anatomical claim, made in pixels rather than in a reviewable table. Reframing `side` as "the view the user was looking at" does not avoid the claim — it relocates it into a later phase that has no way to know it was deferred.

**Shipping meanwhile (build-plan R-21):** v1 ships **one silhouette, no front/back control, and `side: null` on every point** — a value the server already defaults to. Nothing unratified is written and nothing is foreclosed.

**The question, per region:** for `lower_abdomen`, `pelvis`, `lower_back`, `legs`, `bowel_rectal`, `bladder`, `vaginal`, `chest_shoulder` — **front only, back only, both, or should the app not ask at all?** Note `chest_shoulder` is in the vocabulary precisely because of **phrenic-nerve referred shoulder pain** (C-14), which is neither cleanly anterior nor posterior; and a *referred* pain location is where the patient **feels** it, which may be a fourth answer ("record where she points, do not ask front or back").

**Second question, same item (added 2026-08-21 from T21a's review):** the 8 regions contain **no upper-abdomen / epigastric value**. The silhouette's torso is partitioned with no dead band, so a tap below the ribs and above the navel resolves to **`chest_shoulder`** — the nearest zone, not a claim we want to make silently. Should the vocabulary gain an upper-abdomen region, should that band be untappable (the user picks from the list instead), or is resolving it to `chest_shoulder` acceptable? Recorded rather than settled in geometry, per R10's *"no hit zone is always the safe answer"*.

**Source:** none — this is an open ask, not a cited default. **Sign-off:** **OPEN; no PO-interim value. Blocks the front/back control only, not v1.**

---

**Engineer's note:** none of the above is implemented until the relevant row is **clinician-signed** (PO-interim is not clinician sign-off). Until then the phase's gap-register blocker stays open. Seed all values via migration with `valid_from` + a provenance/citation field; Admin (P10) maintains them with `admin_audit_log` before/after.
