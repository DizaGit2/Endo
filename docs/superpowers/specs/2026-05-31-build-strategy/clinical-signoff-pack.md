# Lumen — Clinician Sign-off Pack (C-01 … C-16)

**For:** a reproductive endocrinologist / OB-GYN **and** a biostatistician (C-09/C-11).
**From:** Lumen product owner. **Prepared:** 2026-07-14.
**Status of every item below:** **PO-interim — approved by the product owner as a working default, pending your clinical sign-off.** None has yet been signed by a clinician.

> **Specialist-facing Spanish version (2026-08-20):** `lumen-revision-clinica-especialista.docx` in this folder — plain-language, no IT jargon, one page-block per item (title · how the app uses it · Carolina's PO-interim decision · direct question · response box). Regenerate with `python build_clinical_signoff_docx.py` (content in `clinical_signoff_content.py`; needs `python-docx`). Values must stay in sync with this pack.

---

## How to use this pack

Each item states (a) the clinical question, (b) the **PO-interim value** we propose to encode, (c) the **source(s)** we based it on, and (d) a **sign-off line**. For each, please mark **Agree / Modify / Reject**, add a citation where you change a value, and sign + date. We will encode only what you sign; until then each item stays an open blocker in our build plan.

**Ground rules we have already committed to (please sanity-check, don't re-derive):**

- **Bounds never block data entry.** Endometriosis cycles are irregular by nature and many users are on cycle-suppressing therapy (e.g. dienogest) or have no cycle at all. Every numeric bound below gates only *estimator inclusion* and *prediction confidence* — a user can always log any value. Please flag if any bound is nonetheless clinically unsafe.
- **Reference data is versioned.** Every value is seeded with a `valid_from` date + a source citation, so a future correction never retroactively invalidates a stored historical lab/cycle (a lab is judged against the range in effect at its measurement date).
- **The engine is deterministic** (no ML); all values are display/estimation outputs.

## ⚠️ Please look hardest at these

- **Safety-critical wording & values:** **C-15** (red-flag copy — also going to legal), **C-06** (hormone reference ranges), **C-13** (medication doses), **C-11** (mood/estrogen insight wording).
- **Two places the product owner chose *against* our researched default — your view especially wanted:**
  - **C-03** — PO chose a **mean** cycle-length estimator; we had recommended **median** (more robust to the outlier/anovulatory cycles common in endometriosis). Mitigation: the mean is computed only over in-bounds (21–45 d) cycles, so gross outliers are already excluded.
  - **C-02** — PO chose to **include a fertile-window overlay** in v1; we had recommended omitting it (Lumen is an endometriosis tracker, not a contraception product). It will carry a mandatory non-contraceptive disclaimer. Please confirm this is acceptable.
- **PO extensions to confirm:** C-12 pause reasons {pregnancy, hormonal_suppression, surgical, menopause, other}; C-13 category enum extended with {bleeding, metabolic}.

---

# A. Cycle phase model — gates the calendar (P4a) & inference engine (P6)

### C-01 — Phase-boundary rules (the 4 phases)
**PO-interim:** Deterministic, integer-day, 4 contiguous bands from logged `period_start`/`period_end` + one estimated ovulation day `Ov`, where **`Ov = next_period_start − 14`** (14-day luteal length as the stable back-count anchor).

| Phase | Starts | Ends |
|---|---|---|
| Menstrual | `period_start` | `period_end` |
| Follicular | `period_end + 1` | `Ov − 3` (day before ovulatory band) |
| Ovulatory | `Ov − 2` | `Ov + 1` (4-day band, a=2 / b=1) |
| Luteal | `Ov + 2` | `next_period_start − 1` |

When ovulation can't be estimated (irregular history, or cycle-suppressed/absent): show **Menstrual only**, mark the other three "unknown" at low confidence. (Worked example, 28-day cycle: `Ov` = day 15; luteal band ~12 d — `L=14` is the ovulation anchor, not the displayed luteal-band width.)
**Source:** Reed & Carr, *The Normal Menstrual Cycle* (Endotext, NBK279054, 2018); ACOG fertility-awareness guidance; Wilcox, Weinberg & Baird (BMJ 2000 / NEJM 1995).
**Sign-off (Agree / Modify / Reject): ______________________  Name / date: ______________**

### C-02 — Ovulation estimation
**PO-interim:** **Back-count** from predicted next period by a **fixed 14-day luteal length** (`ovulation_day = cycle_length − 14`) — *not* forward midpoint (biased for non-28-day cycles). Ovulatory display band = **ovulation ± 2 days**. **A fertile-window overlay is included** (per PO), rendered as **ovulation −5 … 0** (6 days, ending on the day of ovulation) — informational only, **with a mandatory non-contraceptive disclaimer** ("not for pregnancy prevention or timed conception").
**Source:** ACOG *Fertility Awareness-Based Methods*; Wilcox BMJ 2000 / NEJM 1995; ASRM *Optimizing Natural Fertility* (2022).
**Clinician note wanted:** is shipping any fertile-window surface acceptable for this population, given fertility-awareness typical-use failure rates?
**Sign-off: ______________________  Name / date: ______________**

### C-03 — Cycle- & period-length estimators + valid bounds
**PO-interim:** Estimator = **mean** cycle & period length *(PO override; we recommended median — please advise)* over the **last 6 completed cycles**; require **≥3 completed cycles** before the computed estimate overrides the onboarding self-report. **Clinical inclusion bounds (gate estimator + confidence only):** cycle **21–45 d**, period **1–10 d**; out-of-bounds cycles are excluded from the estimator but always logged. **Non-blocking sanity guard (soft typo hint, never blocks save):** cycle 10–120 d, period 1–30 d.
**Source:** FIGO 2018 (Munro et al., normal frequency 24–38 d, duration ≤8 d) widened toward ACOG (≈90% of cycles 21–45 d); ESHRE 2022 for the irregularity caveat.
**Sign-off: ______________________  Name / date: ______________**

### C-04 — Period vs spotting; auto-detect `period_start`
**PO-interim:** `flow_intensity` **1–4** {1 spotting, 2 light, 3 medium, 4 heavy}; **spotting = bleeding not needing sanitary protection** (FIGO 2018). **Period-qualifying = flow ≥ 2** (spotting alone is not). Auto-detect `period_start` = first `flow ≥ 2` day that opens a **new** episode (separated from prior menstrual bleeding by a **≥3 bleed-free-day** gap, endo-tolerant, configurable). Spotting never auto-creates a period; on suppression, breakthrough spotting stays silent; **manual override always wins**. Heavy (=4) maps to the HMB screening markers (saturation ≤1–2 h, clots ≥25 mm) — see C-15.
**Source:** FIGO 2018 (Munro et al.); Clue tracking conventions; Higham PBAC (1990).
**Sign-off: ______________________  Name / date: ______________**

### C-05 — Regularity definition
**PO-interim:** Metric = **shortest-to-longest cycle-length range** over the last 6 cycles (min 3 completed cycle-lengths). Tiers: **Regular ≤ 7 d** (FIGO), **Somewhat irregular 8–14 d** *(product-defined)*, **Irregular ≥ 15 d** *(product-defined)*. Regularity **modulates prediction confidence + forecast window**: Regular ×1.0 (±2 d) · Somewhat ×0.7 (±4 d) · Irregular ×0.4 (±7 d) · insufficient/suppressed → range-only. Flat ≤7 d ceiling in v1 (FIGO age-banding deferred). No reassuring copy attached to "somewhat irregular."
**Source:** FIGO 2018 (regularity = shortest-to-longest variation, ≤7 d for ages 26–41); ACOG CO 651. *(The 8–14/≥15 d cutoffs and the multipliers are product design, not guideline-derived — please bless or replace.)*
**Sign-off: ______________________  Name / date: ______________**

---

# B. Hormones & labs — gates lab parsing (P7b)

### C-06 — Hormone reference ranges (`ref_hormone_range`)
**PO-interim (source of record: Mayo Clinic Laboratories; assay-dependent; gate estimator/confidence only; not applied when phase unknown/suppressed):**

| Hormone | Phase | Low | High | Unit |
|---|---|---|---|---|
| Estradiol | menstrual/early-follicular | 25 | 120 | pg/mL |
| Estradiol | follicular | 25 | 120 | pg/mL |
| Estradiol | ovulatory (mid-cycle peak) | 30 | 520 | pg/mL |
| Estradiol | luteal | 35 | 250 | pg/mL |
| Progesterone | follicular | 0 | 0.89 | ng/mL |
| Progesterone | luteal | 1.8 | 24 | ng/mL |
| LH | follicular | 1.8 | 11.8 | mIU/mL |
| LH | mid-cycle peak | 7.6 | 89.1 | mIU/mL |
| LH | luteal | 0.6 | 14.0 | mIU/mL |
| FSH | follicular | 3.03 | 8.08 | mIU/mL |
| FSH | mid-cycle peak | 2.55 | 16.69 | mIU/mL |
| FSH | luteal | 1.38 | 5.47 | mIU/mL |
| Testosterone (total) | any (female ≥19 y) | 8 | 60 | ng/dL |
| Cortisol | AM (7–9 a.m.) | 7 | 25 | µg/dL |
| Cortisol | PM (3–5 p.m.) | 2 | 14 | µg/dL |
| GLP-1 | — | *no reference band — see C-08* | | pmol/L |

Estradiol low-phase lower bounds set to 25 pg/mL (the immunoassay's reporting floor). Testosterone total-only in v1 (free/bioavailable deferred).
**Source:** Mayo Clinic Laboratories test catalog (ESTS/EEST, PGSN, LH, FSH, TTST, CORT), 2025.
**Sign-off (please confirm each analyte or annotate your lab's ranges): ______________________  Name / date: ______________**

### C-07 — Accepted-unit whitelist + conversions
**PO-interim:** Canonical units — estradiol pg/mL, progesterone ng/mL, testosterone ng/dL, cortisol **µg/dL**, LH/FSH IU/L (≡ mIU/mL, 1:1), GLP-1 pmol/L. Conversion factors (MW-derived, verified): estradiol pmol/L ×0.2724; progesterone nmol/L ×0.3145; testosterone nmol/L ×28.84; cortisol nmol/L ×0.03625; GLP-1 pg/mL ×0.3032. Micro-sign `µ` (U+00B5), accept `mcg`/`ug` aliases. Unrecognized unit → logged + flagged, excluded from estimator only (never blocks entry).
**Source:** AMA Manual of Style 11th ed. §18; PubChem molecular weights; WHO International Standards (LH/FSH).
**Sign-off: ______________________  Name / date: ______________**

### C-08 — GLP-1 specifics
**PO-interim:** **Defer** endogenous GLP-1 as a reference/estimator hormone in v1 (no standardized clinical assay, no validated reference interval, special pre-analytics, no endo interpretation). Keep it **log-only** (value shown verbatim, "no standardized reference range," no flag). Canonical unit if ever stored = pmol/L (active/intact). **GLP-1 receptor-agonist *medications* are routed to the medication log** (see C-13), not the hormone chart.
**Source:** Bak et al. (Diabetes Obes Metab 2014); WHO ATC/DDD (A10BJ); absence of an orderable Mayo/LabCorp/Quest GLP-1 test.
**Sign-off: ______________________  Name / date: ______________**

---

# C. Inference outputs — gates the engine (P6); C-09/C-11 also need a biostatistician

### C-09 — Data-completeness score (0–100)
**PO-interim (named a "data-completeness" index, *not* a validated prediction-confidence probability):** additive, four capped factors — **Lab phase coverage 40 · Cycle history 30 · Check-ins 20 · Body-map 10**. Cycle-history curve (stepped): 0/8/15/22/26/28/30 for 0…≥6 cycles. Bands: Low 0–39 / Medium 40–69 / High 70–100; below 20 → suppress the numeric phase prediction and show a range. Cycle-suppressed users → waive the 30 cycle-history points, renormalize the rest 70→100.
**Source:** Clue (3-cycle prediction threshold); Bull et al. *npj Digital Medicine* 2019; Li et al. **JAMIA** 2022;29(1):3–11. *(Weights are a product+clinical judgment, not a validated instrument — please bless or replace; note there is no regularity term.)*
**Sign-off (clinical + product): ______________________  Name / date: ______________**

### C-10 — Missing-data card catalog (`ref_insight_rule`)
**PO-interim:** four cards, foundational-first priority — `start_checkins` (10) → `log_more_cycles` (20) → `start_body_map` (30) → `lab_phase_coverage` (40); one card at a time on the dashboard, full list on the explainer. Copy is plain-language, encouraging, **never pathologizing irregularity**; each card dismissible ("Maybe later" snoozes 7 days). Suppress `log_more_cycles` + `lab_phase_coverage` while cycle-tracking is paused (C-12) *or* when an active cycle-suppressing medication is logged.
**Source (copy-tone, not clinical numbers):** CDC Clear Communication Index; NHS content standard; thresholds inherit from C-03/C-09.
**Sign-off: ______________________  Name / date: ______________**

### C-11 — Insights methods + thresholds + claim wording
**PO-interim:** **"Pain" = daily worst (max) NRS 0–10** across endo pain symptoms (dysmenorrhea, non-menstrual pelvic pain, deep/superficial dyspareunia, dyschezia, low-back); excludes nausea/fatigue/mood/bloating/headache. Methods: **Spearman** (ordinal), phase-stratified means. **Surfacing gate:** n ≥ 10 paired (prefer ≥20) **and** |rho| ≥ 0.30 (a product noise-floor, *not* a "meaningful" threshold), or ≥ ~15% group difference; **never show p-values.** Mandatory non-causal wording ladder (allowed: *associated/linked/tends to*; forbidden: *causes/reduces/improves*) + persistent footer *"Patterns in your own data — associations, not medical advice or proof of cause."*
Per-insight: **strongest_link** (median peak-pain offset + ≥60% cycle consistency, ≥3 cycles; wording branches when the peak lands at/after period start); **pain_by_phase** (mean worst-pain per phase, ≥3 pain-days/phase); **activity_vs_pain** (next-day D→D+1 lag, ≥30 min as an *illustrative anchor*, not "dosing"); **mood_vs_estrogen** (**the "estrogen < 120 pg/mL" cutoff is dropped**; default = "% low-mood days by phase"; **gated to non-suppressed users**; the estrogen mechanism lives in the explainer, not the card headline).
**Source:** Schober 2018 (Spearman use); Haber et al. AJE 2022 + FTC 2023 (causal-language limits); ESHRE/ASRM pain scoring; Schmidt JAMA Psych 2015 (estrogen withdrawal, not level).
**Sign-off (clinical + biostatistics): ______________________  Name / date: ______________**

---

# D. Catalogs, population & safety

### C-12 — Eligible population & cycle-suppression handling
**PO-interim:** v1 population = **menstruating individuals of reproductive age**, framed as a **design target, not a data-entry/age gate** (any minimum-age rule is a separate legal decision); phenotype-driven and gender-inclusive; no upper age cutoff. **One cycle-tracking-pause mechanism** with **`pause_reason` {pregnancy, hormonal_suppression, surgical, menopause, other}** *(PO extension)*. While paused: no phase predictions, an explicit "phases unavailable" state, paused spans excluded from estimators, **entry never blocked**. **Resume is user-controlled and always available for every pause reason** *(PO)*; resume = fresh cycle start (no pre/post merge). The engine may *suggest* a pause but never auto-pauses silently. An **amenorrhea alternate onboarding branch** (reason → therapy/start → still-bleeding? → optional last-period → confirm) replaces the mandatory last-period date. **Safety rule:** for `pause_reason = pregnancy`, hormone-range interpretation is **disabled entirely** (labs still loggable) — non-pregnant ranges are *not* substituted.
**Source:** ESHRE 2022 & NICE NG73 (first-line hormonal therapy suppresses ovulation/menstruation); dienogest amenorrhea cohort (ENVISIOeN, Reprod Sci 2022 — normal bleeding 85.8%→17.5%, amenorrhea 3.5%→70.8% by month 24; Asian cohort — directional); WHO/ACOG menopause.
**Sign-off: ______________________  Name / date: ______________**

### C-13 — `ref_medication` starter catalog (endometriosis)
**PO-interim (doses *typical*, not prescriptive; pick-list never gates logging; free-text "other" always available; all ATC codes verified vs WHO ATC/DDD Index):**

| Name | Form | Typical dose | ATC | Category |
|---|---|---|---|---|
| Dienogest | tablet | 2 mg once daily, continuous | G03DB08 | hormonal |
| COC (levonorgestrel + ethinylestradiol) | tablet | EE 20–35 µg + LNG 100–150 µg daily; often continuous | G03AA07 | hormonal |
| Norethisterone acetate | tablet | 5 mg/day (2.5–15) | G03DC02 | hormonal |
| Medroxyprogesterone acetate | tablet / depot | oral 10 mg 1–3×/day; depot 104 mg SC / 150 mg IM q3mo | G03DA02 | hormonal |
| Levonorgestrel IUD (LNG-IUS) | IUD | 52 mg, ~20 µg/day, up to 5–8 y | G02BA03 | hormonal |
| Leuprorelin (leuprolide) | depot inj | 3.75 mg monthly / 11.25 mg q3mo; **≤6 mo w/o add-back** | L02AE02 | hormonal |
| Goserelin | SC implant | 3.6 mg monthly / 10.8 mg q3mo; **≤6 mo w/o add-back** | L02AE03 | hormonal |
| Elagolix | tablet | 150 mg QD, or 200 mg BID (**≤6 mo**) | H01CC03 | hormonal |
| Relugolix combination | tablet | relugolix 40 + estradiol 1 + NETA 0.5 mg, one tablet daily | H01CC54 | hormonal |
| Danazol | capsule | 200–800 mg/day divided *(androgenic SEs; less used)* | G03XA01 | hormonal |
| Letrozole | tablet | 2.5 mg once daily *(off-label; usually with a progestin/OCP)* | L02BG04 | hormonal |
| Drospirenone-only pill | tablet | 4 mg once daily (24/4 or continuous) | G03AC10 | hormonal |
| Naproxen | tablet | 250–500 mg BID (max ~1000–1250 mg/day) | M01AE02 | pain |
| Ibuprofen | tablet | 400 mg q6–8h (OTC max 1200; Rx max ~2400–3200, region-dependent) | M01AE01 | pain |
| Paracetamol (acetaminophen) | tablet | 500–1000 mg q4–6h (max 3–4 g/day) | N02BE01 | pain |
| Tranexamic acid | tablet | 1–1.3 g TID during menses (≤~4 days/cycle) | B02AA02 | **bleeding** |
| Omega-3 (EPA+DHA) | capsule | ~1–2 g/day | C10AX06 | supplement |
| Vitamin D3 (colecalciferol) | tablet/drops | 800–2000 IU/day | A11CC05 | supplement |
| Magnesium | tablet | ~200–400 mg elemental/day | A12CC10 | supplement |
| Semaglutide | inj/tablet | per product | A10BJ06 | **metabolic** |
| Dulaglutide | injection | per product | A10BJ05 | **metabolic** |
| Liraglutide | injection | per product | A10BJ02 | **metabolic** |
| Exenatide | injection | per product | A10BJ01 | **metabolic** |
| Lixisenatide | injection | per product | A10BJ03 | **metabolic** |
| Tirzepatide | injection | per product | A10BX16 | **metabolic** |

Category enum (PO): **{hormonal, pain, supplement, bleeding, metabolic}**. GLP-1 agonists included per the C-08 routing decision.
**Source:** WHO ATC/DDD Index (2025/26); ESHRE 2022; NICE NG73/NG88; product labels (Visanne, Lupron, Orilissa, Ryeqo).
**Sign-off: ______________________  Name / date: ______________**

### C-14 — Endometriosis staging & surgery vocabulary
**PO-interim:** **rASRM I–IV** — Stage I *minimal* (1–5), II *mild* (6–15), III *moderate* (16–40), IV *severe* (>40); **user-entered, nullable, never inferred; does not correlate with pain** (no "higher stage = worse" copy). #Enzian deferred to v2 (optional free-text). Surgery controlled list (multi-select + `other`): diagnostic_laparoscopy, excision, ablation/fulguration, endometrioma_cystectomy, adhesiolysis, hysterectomy, oophorectomy, bowel_resection, ureterolysis. Vocab review: keep **`chest_shoulder`** (thoracic/diaphragmatic endo is real); display **`depressed_mood` as "low mood"** (not a screener); triggers (weather etc.) = co-occurrence, never causation; **`heavy_menstrual_flow` = an independent FIGO-"HMB" flag** (not double-counted vs `flow_intensity=4`), its red-flag threshold authored jointly with C-15.
**Source:** ASRM revised classification 1996/1997 (Fertil Steril 67:817–21); ESHRE 2022; Keckstein #Enzian 2021; FIGO 2018; thoracic-endo literature (Nezhat 2024).
**Sign-off: ______________________  Name / date: ______________**

### C-15 — Red-flag / crisis symptom guidance (SAFETY-CRITICAL — also to legal, L-04)
**PO-interim:** **Yes** — surface a **passive, non-diagnostic, non-blocking** safety note *after* the entry saves; calm/neutral tone, dismissible, at most once per triggering entry, never names a condition. **Fixed safety-netting footer (verbatim):**
> Lumen isn't a medical or emergency service and can't assess your symptoms. If you're worried, contact your doctor or urgent care — and if it feels like an emergency, call your local emergency number right away.

**Triggers + opener wording:**
1. **Top-of-scale pain (10/10):** "You logged pain at the very top of the scale. Pain this severe — especially if it's sudden, or the worst you've ever felt — is worth getting checked soon."
2. **Very heavy bleeding** (highest flow option, or soaking ≥1 pad/tampon per hour for ≥2 h, or clots larger than a coin ≈2.5 cm): "You logged very heavy bleeding. Soaking through a pad or tampon every hour for a couple of hours in a row, or passing clots bigger than a coin, is worth getting checked."
3. **Fever ≥38.0 °C + pelvic pain:** "You logged a fever together with pelvic pain. That combination is worth getting checked promptly."
4. **Fainting / near-faint:** "You logged feeling faint or passing out. That's worth getting checked, especially alongside pain or heavy bleeding."
5. **Severe pain + pregnancy not excluded:** "You logged severe pain and there's a chance you could be pregnant. If you are pregnant, sudden or one-sided pain can be an emergency and needs to be checked urgently."
6. **Unable to urinate / pass stool:** "You logged being unable to pass urine (or stool). This can be serious — please get it checked right away."

Fever fires at the lower **38.0 °C** cutoff (the PID *urgent* marker is 38.3 °C). Footer stays locale-agnostic; keep the "≈2.5 cm" clot size in every locale.
**Source:** ACOG (HMB, AUB, PID FAQs); NHS/Mayo (ectopic); NIDDK (urinary retention); Mayo (bowel obstruction); NICE NG12 + BJGP (safety-netting).
**Sign-off (clinician) + legal review: ______________________  Name / date: ______________**

### C-16 — Body-map front/back membership (OPEN — the one item with **no** PO-interim value)
**Added 2026-08-21.** Every other item in this pack carries a PO-interim default for you to accept or amend. This one does not: the product owner judged it a clinical question and declined to invent an answer.

One screen asks the patient to mark **where** it hurts on a body outline. Each mark stores a **region** (the 8 you reviewed under C-14) *and* a **side** — front or back. The regions are ratified; the front/back assignment is not, and no published source we could find assigns one.

It matters more than it looks: the side value is **never shown back to the patient**, and version 1 has no way to edit or delete a logged symptom — so a wrong value is written once, invisibly, and cannot be corrected. A later version renders these marks as a **heatmap on a body figure**, which is where a wrong assignment would become a visible anatomical claim.

**Until you rule, version 1 ships one outline with no front/back control and records no side at all** — nothing unratified is stored.

**The question:** for each region — `lower_abdomen`, `pelvis`, `lower_back`, `legs`, `bowel_rectal`, `bladder`, `vaginal`, `chest_shoulder` — should the app offer it on the **front**, the **back**, **both**, or **not ask at all**? Please note `chest_shoulder` is in the vocabulary because of **phrenic-nerve referred shoulder pain**, which is neither cleanly anterior nor posterior; if "record where she points, don't ask front or back" is the better clinical answer, that is a valid reply and the control stays out.

**Source:** none — an open ask, not a cited default.
**Sign-off / your ruling: ______________________  Name / date: ______________**

---

**Return path:** please send the signed pack back to the product owner; each signed row is then encoded via migration with `valid_from` + your citation, and the corresponding build-plan blocker is closed. Thank you.
