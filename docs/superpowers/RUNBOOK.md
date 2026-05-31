# Lumen Build — Runbook (how to drive & review each phase)

**Audience:** the person running the Lumen build (you). This is the operational companion to the [build-strategy design](specs/2026-05-31-build-strategy-design.md) and the living plan at `docs/superpowers/plans/lumen-build.md` (created by `writing-plans`). It tells you exactly what to do each session — start a phase, supervise it, review it, approve it, and handle problems.

Keep this open while you work. The loop in §3 is the thing you repeat ~30–35 times.

---

## 1. The mental model (read once)

- The build is **19 phases** (P0a … P12b), in dependency order, starting from an empty repo and ending at a production-ready backend + Flutter client. Each phase is a small, shippable slice with its own tests and a clear "done".
- You run **one fresh Claude session per phase** ("Model C"). That session is an **orchestrator**: *it* dispatches subagents to do the per-task work, runs tests, and commits. **You never paste prompts per task** — only one short kickoff prompt per phase, then you review at the end.
- **The plan is the source of truth, not chat.** Everything a session needs is in `docs/superpowers/plans/lumen-build.md`. A session reconstructs state from the repo (the plan's status ledger + git), never from a previous conversation. That's why restarting between phases is safe.
- **You are the gate.** A session can mark its work `NEEDS_REVIEW`; only **you** mark a phase `DONE`. Four phases (P1, P2, P6, P7b) are **safety-critical** and get a deeper review (§5).

If you only remember one thing: **start session → paste kickoff → let it run → review against the checklist → approve & merge → next phase.**

---

## 2. Before you start the build (one-time)

1. **Repo state.** The design lives on branch `design/build-strategy`. Decide where the build happens:
   - Simplest: merge the design to `main`, then build from `main` (each phase still gets its own `phase/NN-*` branch).
   - Or keep building on `design/build-strategy`. Either works; just be consistent.
2. **Create the plan.** Run the `writing-plans` skill once to generate `docs/superpowers/plans/lumen-build.md` from the design spec. (If it already exists, skip.)
3. **Verify your environment.** Run the read-only checklist from the [environment companion](specs/2026-05-31-build-strategy/environment.md) §4. For the early phases you only need: .NET 10, Docker (daemon running), Git. **Do not install Flutter yet** — that happens inside P3a.
4. **Sanity-check Docker is running** before any phase that brings up infra:
   ```powershell
   docker version --format '{{.Server.Version}}'   # must respond
   ```
5. **Read the [gap register](specs/2026-05-31-build-strategy/gap-register.md)** and its resolution artifacts in the same folder: **[`decision-sheet.md`](specs/2026-05-31-build-strategy/decision-sheet.md)** (approve/adjust the product defaults — do this first; it unblocks P1/P3a/P4a), **[`clinical-asks.md`](specs/2026-05-31-build-strategy/clinical-asks.md)** and **[`legal-asks.md`](specs/2026-05-31-build-strategy/legal-asks.md)** (hand these to a clinician / lawyer **now** — they have lead time and gate P6/P7b and P1/P8/P9b), and **`definitions.md`** (the enums extracted from the screens). The cheap `formalize-from-screens` values need no decision.

You're ready when `writing-plans` has produced the plan, the environment checklist for P0a is green, and P0a/P0b/P1 have **no open blocker** in the gap register.

---

## 3. The per-phase loop (repeat for every phase)

### Step 1 — Start a fresh session
Open a **new** Claude Code session in the repo. Fresh context per phase is intentional.

### Step 2 — Find the next phase, and clear its gaps first
Open `docs/superpowers/plans/lumen-build.md`, read **§1 Status ledger**. The `NEXT PHASE TO RUN` pointer tells you which phase to run. Confirm its `dependsOn` phases are all `DONE`.

**Then open the [gap register](specs/2026-05-31-build-strategy/gap-register.md) and resolve every BLOCKER tagged to this phase before you start.** These are product/clinical/legal definitions the session must not invent (cycle-phase rules, hormone ranges, the intensity scale, consent/age-gate, etc.). Record each resolution in `ARCHITECTURE.md §A` and the plan's §4 decision log. If a blocker for this phase is still open, do **not** start the phase — a session that guesses a clinical or legal value is worse than a session that waits.

### Step 3 — Paste the kickoff prompt
Copy that phase's **kickoff prompt** verbatim from its subsection in the plan's §3 and paste it as your first message. It's ~6 lines; it points the session at the right plan phase, the relevant `ARCHITECTURE.md` sections, and `CLAUDE.md`, and tells it to execute via `subagent-driven-development` and stop at `NEEDS_REVIEW`. **Don't add anything** — the prompt is self-contained.

### Step 4 — Let it run (mostly hands-off)
The orchestrator will read its sources, then dispatch subagents task by task (write failing test → implement → pass → commit). You watch, but you don't steer task-to-task. Two things to watch for:
- **Interactive steps** the session asks you to do yourself — see §6. The big one is the **Flutter install in P3a**.
- A **`BLOCKED`** report — the session hit a decision it can't make (e.g. an unresolved choice). See §7.

### Step 5 — The session stops at `NEEDS_REVIEW`
When the phase is done, the session fills the phase's **STATUS block** (with *pasted* command output, not prose), sets the ledger row to `NEEDS_REVIEW`, opens/updates a `phase/NN-*` branch + PR, and stops. Now it's your turn.

### Step 6 — Review (§4 light / §5 deep)
Do the review checklist. **Don't trust the pasted output — re-run the verify commands yourself.**

### Step 7 — Approve & merge (or hand back)
- If it passes: §8.
- If it doesn't: §7 (hand back with the specific failure; do **not** approve).

### Step 8 — Next phase
Confirm the ledger advanced (`NEXT PHASE TO RUN` now points at the next phase). Start the loop again.

---

## 4. Reviewing a phase — the light checklist (EVERY phase)

Do all of these. They take a few minutes.

- [ ] **Read the STATUS block** in the phase's plan subsection. It must contain *pasted* command output (e.g. `Passed! Failed: 0, Passed: 41`), not "tests pass". If it only describes, reject.
- [ ] **Re-run the phase's verification commands yourself** (they're listed in the phase's "Verification commands" block). At minimum:
  ```powershell
  docker compose -f deploy/docker-compose.yml ps        # services for this phase healthy
  dotnet test backend/Lumen.sln --nologo                # 0 failed, 0 unexplained skips
  ```
  plus the phase-specific probe (a `curl`/`Invoke-RestMethod`, an encrypted-row check, etc.).
- [ ] **Confirm every exit-criterion checkbox** in the phase is genuinely ticked and you saw the proof.
- [ ] **Skim the diff** for scope creep and secrets:
  ```powershell
  git diff main...phase/NN-<slug> --stat        # is the surface area sane for this phase?
  git diff main...phase/NN-<slug> | Select-String -Pattern "password|secret|api[_-]?key|BEGIN .*PRIVATE KEY"
  ```
  No real secrets should ever be committed (they belong in the sops `.env`, later).
- [ ] **Contract gate** (any phase that added/changed endpoints): confirm `backend/contract/openapi.json` and the generated Dart client were regenerated and committed in the same PR (CI's drift guard should be green).
- [ ] **Client phases** (P3a onward where screens are wired): `flutter analyze` clean, `flutter test` green incl. light+dark goldens.

If all boxes are checked, go to §8 (approve). The **definition of done** for any phase is the universal gate in §9.

---

## 5. Reviewing a SAFETY-CRITICAL phase — the deep checklist (P1, P2, P6, P7b)

These four touch encryption, erasure, the inference engine, and the LLM trust boundary. Do **everything in §4, plus**:

- [ ] **Run the code-review skill on the diff:** `/code-review high` (P1, P2, P6) or `/code-review ultra` (P7b). Read the findings; don't rubber-stamp.
- [ ] **Mutation spot-check (prove the safety test has teeth):** deliberately break the guard and confirm a test goes red, then revert. Examples:
  - **P1:** confirm the DEK is never logged and its lifetime is request/job-scoped; tenant isolation holds (user A can't read user B).
  - **P2:** after `CryptoShredJob`, confirm the ciphertext is genuinely undecryptable (not just "row gone"); run the job twice (idempotent).
  - **P6:** break a confidence rule → a golden fixture test must fail; confirm sparse input yields an explicit low-confidence/"not enough data" state, never a confident wrong phase.
  - **P7b:** feed a known-good and a malformed/out-of-range lab fixture → out-of-range routes to `needs_manual` and **never** reaches `lab_results`, even on confirm; ClamAV rejects EICAR; the stored PDF is ciphertext in MinIO.
- [ ] **GDPR proofs green:** the `Lumen.Security.Tests` suite passes (envelope-at-rest, crypto-shred-unreadable, backup-unreadable, and — from P7a on — MinIO object deletion on erasure).

Only after these do you mark the phase `DONE`.

---

## 6. Steps only YOU can do (interactive — a subagent can't)

A subagent runs to completion and can't pause to click a wizard or accept a license. When a phase needs one of these, the session will tell you; do it, then let it continue.

- **P3a — Flutter install (the big one).** Install Flutter + Android Studio + Android SDK, add Flutter to PATH, and accept licenses. Follow the [environment companion](specs/2026-05-31-build-strategy/environment.md) §2 step by step. The gate is `flutter doctor -v` showing green for Flutter, Android toolchain (licenses accepted), and Android Studio:
  ```powershell
  flutter doctor -v
  flutter doctor --android-licenses    # interactive: answer y
  ```
  The session won't write any Dart until this is green. (iOS is macOS/CI-only — a red iOS check here is expected, not a blocker.)
- **Any GUI / external account step** (e.g. signing into a provider console, the Anthropic DPA paperwork referenced for P7b) is yours. Start the Anthropic DPA/zero-retention/EU-endpoint paperwork during P4–P6 so P7b isn't blocked waiting on contracting.

---

## 7. When something goes wrong

**The session reports `BLOCKED`.** It hit a decision it can't make. The blocker + context is written into the phase's STATUS block (in the repo, so it survives). You:
1. Resolve the decision.
2. Record it in the plan's **§4 decision log** and, if it answers an `ARCHITECTURE.md §I` open question, in `ARCHITECTURE.md §A` too (same commit).
3. Start a fresh session and re-paste the phase kickoff — it reads the resolved decision and continues.

**A partial / interrupted session (`IN_PROGRESS`).** No problem — state is in the repo. Start a fresh session, paste the same kickoff. It reads the ledger + STATUS (e.g. "tasks 1–4 of 6 done, DB at V07"), checks out the phase branch, **re-runs the tests to confirm the reported-green baseline is actually green**, and resumes at the first unchecked step.

**Tests fail / a verify command is red during your review.** The phase is **not** done. Hand it back: start a session, paste the kickoff, and add one line naming the exact failing command + output. Do not approve around a red test.

**Drift suspicion** (a later phase references a type/migration an earlier phase renamed). Run the 60-second drift scan from the [orchestration companion](specs/2026-05-31-build-strategy/orchestration.md) §5.3 before starting the next phase.

---

## 8. Approve & merge a phase

When the review passes:
1. **Flip the ledger:** set the phase's row in plan §1 to `DONE`, fill `Verified by` with today's date, and advance `NEXT PHASE TO RUN` to the next phase. Update the `Repo HEAD` SHA stamp.
2. **Merge the phase PR** into your build branch (`main` or `design/build-strategy`). Use a merge commit (keep the per-task history) and **tag it `phase-NN`** for an easy rollback point.
3. **Confirm CI is green** on the merge.
4. Move to the next phase (§3).

---

## 9. Definition of done (the universal gate)

A phase is approvable only when **all** are true and you've **seen the command output**:
1. `dotnet build` with warnings-as-errors → 0 warnings.
2. `dotnet test` (this phase + prior) → 0 failures, 0 unexplained skips.
3. Coverage ≥ the ratcheted floor (and any safety-module floor) — never down.
4. Contract gate green (committed spec + Dart client regen clean, no unapproved breaking change, live responses match the schema).
5. Architecture tests green (module boundaries intact).
6. Client phases: `flutter analyze` clean + `flutter test` + goldens (both themes) + integration_test green.
7. Safety-critical phases: the mutation spot-check confirms the safety test fails when the guard is removed.
8. The phase's `docker compose up` stack reaches healthy on a clean run.

If any item is red, it's not done.

---

## 10. Quick reference

**Commands**
```powershell
# verify environment (start of every phase) — see environment companion §4 for the full block
dotnet --version ; docker version --format '{{.Server.Version}}' ; git --version

# bring up only this phase's infra
docker compose -f deploy/docker-compose.yml up -d <services for this phase>
docker compose -f deploy/docker-compose.yml ps

# backend dev loop
dotnet watch --project backend/src/Lumen.Api run
dotnet test backend/Lumen.sln --nologo

# review a phase diff
git diff main...phase/NN-<slug> --stat

# deep review (safety-critical phases)
# /code-review high      (P1, P2, P6)
# /code-review ultra     (P7b)
```

**Key paths**
| What | Where |
|---|---|
| Living plan (start here each session) | `docs/superpowers/plans/lumen-build.md` |
| Build-strategy spec | `docs/superpowers/specs/2026-05-31-build-strategy-design.md` |
| Architecture (source of truth) | `docs/ARCHITECTURE.md` |
| Companions | `docs/superpowers/specs/2026-05-31-build-strategy/{orchestration,testing,environment,flutter}.md` |
| Backend | `backend/` (created in P1) |
| Flutter client | `client/` (created in P3a) |
| Infra / compose | `deploy/` |

**Phase order**
`P0a → P0b → P1⚠ → P2⚠ → P3a → P3b → P4a → P4b → P5 → P6⚠ → P7a → P7b⚠ → P8 → P9a → P9b → P10 → P11 → P12a → P12b`
(⚠ = deeper review per §5. Note P4b/P5/P6 can follow P4a in any order; P5+P6 gate P7a.)

---

## 11. Rhythm & expectations

- ~30–35 sessions total; most phases are 1–2 sessions, P4a and P7b are the heaviest.
- The work between sessions is **your review** — that's the safety net, especially on the four ⚠ phases. Don't skip it to go faster; the whole model is built around it.
- Each session is cheap to start (open, paste 6 lines) and self-documents its result in the repo, so you can stop and resume the build any time without losing your place.
