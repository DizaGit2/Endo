# Lumen — Clinical Sourcing Asks (for a clinician / reproductive endocrinologist + biostatistician)

> These are the **clinically-loaded definitions an engineer must not invent.** Each is a fill-in template: the clinical reviewer supplies the values + a source citation + a sign-off; the engineer encodes them as `ref_*` seed data and `ref_insight_rule` parameters (never hard-coded). **Start this engagement during P3–P5** — it has lead time and gates P6 (inference engine) and P7b (lab parsing).
>
> For every row: **Source** = citation (guideline/literature/lab standard) and **Signed off by / date**. Reference data is versioned via `valid_from`/`valid_to` so edits never retroactively invalidate historical labs (a lab is validated against the range effective at its `measured_on`).
>
> Context: target population is **menstruating individuals of reproductive age** (see decision D-23); the app tracks endometriosis, so some users are on cycle-suppressing therapy — see C-12.

---

## A. Cycle phase model — gates P4a (calendar) & P6 (engine)

### C-01 Phase-boundary rules (the 4 phases)
Define how each phase is computed from logged `period_start`/`period_end` events + estimated ovulation. Fill the rule for each boundary (deterministic — no ML):

| Phase | Starts when | Ends when | Notes |
|---|---|---|---|
| Menstrual | ____ (e.g. period_start) | ____ (period_end) | |
| Follicular | ____ | ____ (ovulation − N) | |
| Ovulatory | ____ (ovulation − a) | ____ (ovulation + b); a=__ b=__ | window width |
| Luteal | ____ | ____ (next period_start) | luteal length convention = __ days |

**Source:** ____________ **Signed off / date:** ____________

### C-02 Ovulation estimation
Method (circle): back-count from predicted next period by fixed luteal length (___ d) · forward midpoint (round(cycle_len/2)) · other: ____. Ovulatory window width: ovulation ± ___ days.
**Source:** ____ **Sign-off:** ____

### C-03 Cycle- & period-length estimators + valid bounds
Average-cycle estimator (mean / median / other): ____ over the last ___ cycles; min history before overriding the onboarding self-report: ___ cycles. **Valid bounds** (for validation + outlier rejection): cycle length ___–___ days; period length ___–___ days. Outlier handling: ____.
**Source:** ____ **Sign-off:** ____

### C-04 Period vs spotting; auto-detect `period_start`
When does logged bleeding/flow become a `period_start` (vs spotting)? Flow-intensity threshold / duration rule: ____. `flow_intensity` scale: 1=____ 2=____ 3=____ 4=____.
**Source:** ____ **Sign-off:** ____

### C-05 Regularity definition
"Regular / somewhat / irregular" numeric definition (e.g. stddev of recent lengths thresholds): ____. Does regularity modulate the confidence score? ____.
**Source:** ____ **Sign-off:** ____

---

## B. Hormones & labs — gates P7b

### C-06 Hormone reference ranges (`ref_hormone_range`)
Fill low/high for **each** hormone, by sex and cycle-phase applicability, in the canonical unit. (Estrogen=estradiol; GLP-1=glp1.)

| hormone_code | sex | phase_applicability | unit | low | high | source citation |
|---|---|---|---|---|---|---|
| estradiol | female | menstrual | pg/mL | __ | __ | __ |
| estradiol | female | follicular | pg/mL | __ | __ | __ |
| estradiol | female | ovulatory | pg/mL | __ | __ | __ |
| estradiol | female | luteal | pg/mL | __ | __ | __ |
| progesterone | female | follicular/luteal | ng/mL | __ | __ | __ |
| lh | female | (by phase) | mIU/mL | __ | __ | __ |
| fsh | female | (by phase) | mIU/mL | __ | __ | __ |
| testosterone | female | any | ng/dL | __ | __ | __ |
| cortisol | any | any (AM/PM?) | µg/dL | __ | __ | __ |
| glp1 | any | any | pmol/L | __ | __ | __ |

**Signed off / date:** ____________

### C-07 Per-hormone accepted-unit whitelist + conversions
For each hormone, list accepted alternate units labs may report and the conversion factor to the canonical unit (e.g. estradiol: pmol/L → pg/mL × 0.272). Pin exact unit-string casing.
| hormone_code | canonical unit | accepted alt units | conversion to canonical |
|---|---|---|---|
| estradiol | pg/mL | pmol/L | × ____ |
| … | | | |
**Source:** ____ **Sign-off:** ____

### C-08 GLP-1 specifics
Is GLP-1 in scope for v1 (rarely on standard hormone panels)? Range, unit (pmol/L), common lab aliases: ____.
**Sign-off:** ____

---

## C. Inference outputs — gates P6 (with product owner on weights)

### C-09 Confidence score formula
Factors, point contributions, per-factor curve (linear/capped/stepped), and combination rule producing the 0–100 score. Screens suggest 4 factors as a starting taxonomy — confirm/replace and set the numbers:

| factor | max points | curve | notes |
|---|---|---|---|
| Cycle history (n cycles) | __ | __ | |
| Lab phase coverage (of 4) | __ | __ | |
| Daily check-ins (n days) | __ | __ | |
| Body-map points | __ | __ | |
"Full coverage" (for the "projected X%") definition: ____. Display bands (low/med/high cutoffs): ____.
**Sign-off (clinical + product):** ____

### C-10 Missing-data card catalog
For each card: trigger condition, priority, and the (clinically appropriate, non-alarming) copy + CTA. Seed as `ref_insight_rule` rows.
| card_code | trigger | priority | title/body/CTA |
|---|---|---|---|
| lab_phase_coverage | <4 phases have a confirmed lab | | (screen 20 gives copy) |
| __ log_more_cycles | <3 cycles logged | | |
| __ start_checkins | … | | |
| __ start_body_map | … | | |
**Sign-off:** ____

### C-11 Insights-hub methods + thresholds + claim wording
For each insight: the statistical method, minimum-data gate before showing, and **clinically acceptable wording** (avoid over-claiming causation). Screens show illustrative examples — confirm method & numbers or relabel.
| insight_code | method | min data | numeric threshold | approved copy template |
|---|---|---|---|---|
| strongest_link (pain vs period timing) | __ | __ | __ | __ |
| pain_by_phase | averaging method; which symptoms count as "pain" | __ | — | __ |
| activity_vs_pain | __ | __ | "30+ min" / "22% less"? | __ |
| mood_vs_estrogen | __ | __ | "estrogen < 120 pg/mL"? | __ |
**Sign-off (clinical + biostatistics):** ____

---

## D. Catalogs & population

### C-12 Eligible population & cycle-suppression handling
Confirm v1 population (recommend: menstruating, reproductive age). Define engine behavior for users with **no detectable cycle** — continuous hormonal suppression (e.g. **Dienogest**, which the app tracks), pregnancy, peri/post-menopause: should the cycle engine suppress phase output and show a "phases unavailable" state? ____.
**Sign-off:** ____

### C-13 `ref_medication` starter catalog (endometriosis)
Provide a vetted starter catalog. Mark dose ranges as *typical*, not prescriptive.
| name | form | typical dose (range) | ATC code | category (hormonal/pain/supplement) | source |
|---|---|---|---|---|---|
| Dienogest | tablet | __ | G03DB08 | hormonal | __ |
| Naproxen | tablet | __ | M01AE02 | pain | __ |
| … | | | | | |
**Signed off / date:** ____

### C-14 Endometriosis staging & surgery vocabulary
Staging system to use (recommend **rASRM I–IV**): confirm labels. Surgery-type controlled list (e.g. laparoscopy, excision, ablation, hysterectomy): ____.
**Sign-off:** ____

### C-15 Red-flag / crisis symptom guidance (safety)
Should logging an extreme value (e.g. 10/10 pain, heavy bleeding) surface a non-diagnostic safety note ("this isn't an emergency service; seek care if…")? Which values trigger it, and the exact wording: ____.
**Sign-off:** ____

---

**Engineer's note:** none of the above is implemented until the relevant row is filled + signed. Until then the phase's gap-register blocker stays open. Seed all values via migration with `valid_from` + a provenance/citation field; Admin (P10) maintains them with `admin_audit_log` before/after.
