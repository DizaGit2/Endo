# Lumen — Legal / DPO Sourcing Asks

> Lumen processes **special-category health data** (GDPR Art. 9): menstrual cycle, symptoms, libido, sexual-activity triggers, fertility intent, hormone labs. EU-hosted, likely Spanish-primary; the only external data processor that sees content is **Anthropic** (lab-PDF text, US transfer under SCCs, zero-retention DPA). These items need legal text/decisions an engineer must not author. **Start now — legal text has lead time.** Each gates a phase as noted.
>
> Per item: provide the **text** (ES + EN) and/or the **decision**, plus an owner + date. Resolved items update the privacy posture in `ARCHITECTURE.md §F` and the relevant screens.

---

## Gates P1 (signup/consent spine)

### L-01 🔴 Minimum-age / eligibility gate + parental-consent posture
No age gate exists in onboarding today, yet the app processes minors' reproductive-health data. GDPR digital-consent age is 16 (Spain = 14). Decide:
- Minimum age for self-registration: ______
- Hard block below it, or a parental-consent flow? ______
- Tie the check to DOB (screen 4) at signup? ______
**Owner / date:** ____________

### L-02 🔴 Consent capture at signup — lawful basis, consents, text, versioning
- Lawful basis for Art. 9 processing (explicit consent? other?): ______
- The exact consent(s) the user must give (health-data processing; Anthropic lab-parsing transfer; any optional ones): ______
- Consent text (ES + EN): ______
- We store {policy_version, timestamp, locale, consents[]} per user. Confirm the record fields and the **re-consent trigger** on policy change: ______
**Owner / date:** ____________

---

## Gates P3a/P3b (copy shown before screens freeze)

### L-03 🟠 "Health info stays on your device" copy correction (screen 31)
This statement is **materially inaccurate** — data is server-stored (encrypted at rest) and lab text is sent to Anthropic. Provide accurate trust copy (ES + EN): ______
**Owner / date:** ____________

---

## Gates P8 (doctor report) & in-app surfaces (P6)

### L-04 🔴 Medical disclaimer — report PDF + in-app
- Disclaimer for the **doctor-report PDF** (it's a clinician-facing document; must not read as a diagnostic record): ______
- Persistent **in-app** "informational, not medical advice / consult a clinician" disclaimer for the surfaces that make health suggestions (dashboard tips, insights hub, confidence): where shown + text: ______
- Emergency/red-flag safety note (pairs with clinical-ask C-15): ______
**Owner / date:** ____________

---

## Gates P9b (export, deletion, policy) & launch

### L-05 🔴 Privacy policy + subprocessor disclosure
Full privacy policy (ES + EN) covering: special-category data (Arts. 9 & 13), the subprocessor table (FCM/APNs, Anthropic + US SCC transfer + zero-retention, off-site EU backup provider), the **crypto-shred** erasure model, data-subject rights (access/erasure/portability), DPO contact. ______
**Owner / date:** ____________

### L-06 🔴 Terms of Service
Full ToS (ES + EN), including the non-medical-service positioning. ______
**Owner / date:** ____________

### L-07 🟠 Data-retention periods + account-deletion UX
- Retention per category (active data, logs, backups, export zips): ______
- Inactive-account purge policy: ______
- Deletion UX: re-auth required? typed confirmation? grace period before crypto-shred? ______
- Confirm crypto-shred propagation to backups satisfies erasure obligations. ______
**Owner / date:** ____________

### L-08 🟠 Warrant-canary statement (screen 36 "never received a data request")
Confirm wording, who owns its accuracy, and the update/removal process if a request is ever received. ______
**Owner / date:** ____________

### L-09 🟠 (Only if social login / email-share kept) extra subprocessor & consent text
If D-01 keeps Apple/Google login, or D-20 keeps server-side email sharing: add the subprocessor entries + any extra consent. (Default recommendations defer both, making this N/A.) ______
**Owner / date:** ____________

---

**Engineer's note:** the consent gate (L-01/L-02), disclaimers (L-04), and policy/ToS (L-05/L-06) are hard blockers for their phases and for any public/beta launch. The privacy-policy subprocessor list must match what's actually integrated (Anthropic is now confirmed; FCM/APNs at P9a; backup provider at P11).
