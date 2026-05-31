<!-- Companion reference to ../2026-05-31-build-strategy-design.md
     Produced by the build-strategy design workflow (2026-05-31). Faithful to docs/ARCHITECTURE.md.
     Note: this analysis predates final phase-number synthesis; phase IDs here are illustrative.
     The canonical phase numbering is in the main spec. -->

# Lumen — Session-Orchestration Mechanics

This is the operating manual for building Lumen across many fresh Claude sessions. It does NOT contain the build content itself (phases, tasks, code) — it defines the *machinery* that the build content lives inside: the plan document format, the kickoff prompt, the review protocol, git strategy, and the anti-drift discipline. Everything below is reusable across all phases.

The single living plan lives at:

```
C:\Proyectos\Endo\docs\superpowers\plans\lumen-build.md
```

This is the path the superpowers `writing-plans` skill expects (`docs/superpowers/plans/...`). It is one file, not one-per-phase, because a fresh session must be able to read the *whole* build state from a single document.

---

## 1. The living implementation-plan document

### 1.1 Why one file, and how it differs from a vanilla superpowers plan

The superpowers `writing-plans` skill produces a flat list of bite-sized tasks for *one* feature executed in *one* sitting. Lumen is bigger: 10+ phases, each its own fresh session, each shippable, with infra coming up incrementally. So the document is a **superset**: it keeps the superpowers task granularity *inside* each phase, but wraps the phases in an orchestration layer (status ledger, kickoff prompts, anti-drift rules) that the base skill doesn't provide.

### 1.2 Top-level document structure

```markdown
# Lumen Build — Living Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL — use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans. Execute exactly ONE phase per session.
> Read §0 (How to use this plan) before touching anything.

## §0  How to use this plan          <- meta: orchestration rules, read every session
## §1  Status ledger                 <- the single source of "what's done", top of file
## §2  Architecture invariants       <- pinned facts every session must honor (the spine)
## §3  Phase catalogue                <- one subsection per phase (the actual work)
## §4  Decision log (build-time)      <- resolves ARCHITECTURE.md §I open questions as they land
## §5  Glossary of paths & commands   <- canonical paths, the verify commands, ports
```

- **§0–§2 and §5 are read by every session.** They are short and stable.
- **§3 is the body.** A session reads only §0–§2, §5, and its *own* phase subsection from §3 (plus the two referenced docs). It does not read other phases' task bodies — that's context pollution.
- **§1 is the ledger** — it lives at the very top (after §0) so it's the first substantive thing a fresh session sees, and it's the *only* place "done/not-done" is authoritative.

### 1.3 The status ledger (§1) — literal format

The ledger is a single table plus a "current pointer". A fresh session reads this and immediately knows where to start. Nothing else in the file claims completion status — the ledger is canonical.

```markdown
## §1 Status ledger

**NEXT PHASE TO RUN: P2** — see §3 / Phase 2.
**Plan revision:** r14   **Repo HEAD when ledger last updated:** a706efc

| Phase | Name                                   | Status      | Branch              | PR   | Verified by | Notes |
|-------|----------------------------------------|-------------|---------------------|------|-------------|-------|
| P0    | Minimal infra (Caddy/PG/KC/Vault)      | DONE        | phase/00-infra      | #1   | 2026-05-22  | unseal=manual |
| P1    | Walking skeleton (auth+onboarding/start)| DONE        | phase/01-skeleton   | #2   | 2026-05-26  | /me green |
| P2    | Cycle + Symptoms modules               | IN_PROGRESS | phase/02-cycle-sx   | —    | —           | partial: see §3 P2 STATUS |
| P3    | Hangfire + matviews + inference engine | TODO        | —                   | —    | —           | SAFETY-CRITICAL |
| P4    | Lab-parse pipeline (+MinIO/ClamAV/LLM) | TODO        | —                   | —    | —           | SAFETY-CRITICAL |
| ...   | ...                                    | TODO        | —                   | —    | —           | |

Status values: TODO | IN_PROGRESS | BLOCKED | NEEDS_REVIEW | DONE
Safety-critical phases (deeper review): P1 (crypto spine), P3 (inference), P4 (lab parse).
```

Rationale for fields:
- `Branch` / `PR` — so a resuming session finds the in-flight work without guessing.
- `Verified by` (a date the *human* signed off, not the agent) — separates "agent says done" from "human accepted".
- `Notes` — carries the one-liner a future session needs (e.g. resolved open questions, the unseal mode).
- `NEXT PHASE TO RUN` pointer — removes all ambiguity for a cold start.

### 1.4 Per-phase fields in §3 — the exact template

Every phase in §3 uses this skeleton. The header block is orchestration metadata; the body is standard superpowers TDD tasks.

````markdown
### Phase P{N}: {Name}

<!-- ORCHESTRATION HEADER — keep in sync with §1 ledger -->
- **Status:** TODO | IN_PROGRESS | BLOCKED | NEEDS_REVIEW | DONE
- **Safety-critical:** no | yes (deeper review — see §0.4)
- **Goal (one sentence):** {what this phase makes work end-to-end}
- **Depends on:** P{n-1} DONE
- **Infra this phase adds:** {e.g. MinIO + ClamAV; or "none — uses P0 stack"}
- **Architecture refs:** ARCHITECTURE.md §C.4, §E, §F (read these sections only)
- **Screens touched (CLAUDE.md):** none | screens 18–21
- **Branch:** phase/{NN}-{slug}
- **Kickoff prompt:** see fenced block below — paste verbatim into the fresh session.

#### Exit criteria (binary, the human checks these)
- [ ] `cd backend && dotnet test` green (N new tests, names listed in tasks)
- [ ] `docker compose -f deploy/docker-compose.yml up -d` healthy; `{the curl/grpcurl probe}` returns {exact expected}
- [ ] {phase-specific observable, e.g. "row appears encrypted in `labs`; plaintext absent in `pg_dump`"}
- [ ] ARCHITECTURE.md / this plan updated for any decision made (§4 + the doc)

#### Verification commands (copy-paste; these ARE the proof, per verification-before-completion)
```bash
docker compose -f deploy/docker-compose.yml ps
cd backend && dotnet test --nologo
curl -fsS localhost:8080/health
{phase-specific probe with its expected output inline}
```

#### Kickoff prompt
```text
{the literal 4–6 line prompt — see §2 of this design for the template}
```

#### Tasks
<!-- standard superpowers bite-sized TDD tasks; checkbox per step -->
### Task 1: {component}
**Files:** Create: `backend/src/...`  Test: `backend/tests/...`
- [ ] Step 1: write failing test  ```csharp ...```
- [ ] Step 2: run `dotnet test --filter ...` — expect FAIL "..."
- [ ] Step 3: minimal implementation  ```csharp ...```
- [ ] Step 4: run `dotnet test --filter ...` — expect PASS
- [ ] Step 5: commit  ```bash git commit -m "feat(cycle): ..." ```
### Task 2: ...

#### STATUS  <!-- the live resume block; see §3 below for format -->
(empty until the phase starts)
````

**Two layers of "done" inside a phase, deliberately:**
- **Step checkboxes** (`- [ ]`) — fine-grained, ticked by the executing agent as it goes. These are how a *partial* session is resumed (you see exactly which step was last completed).
- **Exit criteria checkboxes** — coarse, ticked only when the corresponding verification command has actually been run with the expected output. The *human* confirms these at the checkpoint.

This split is the core anti-"it compiles therefore it's done" guard: step boxes track progress; exit-criteria boxes track *proven* behaviour.

---

## 2. The session kickoff-prompt template

One literal template, parameterised only by phase number/slug. The human copies the per-phase filled-in copy out of §3 of the plan (each phase stores its own filled-in version, so there's zero editing at paste time).

**The literal template (store this in §0 of the plan and a filled copy in every phase):**

```text
You are executing ONE phase of the Lumen build. Phase: P{N} — {Name}.
Read first, in order: docs/superpowers/plans/lumen-build.md (§0, §1, §2, §5, and Phase P{N} only),
then docs/ARCHITECTURE.md ({the §refs listed in this phase}), then CLAUDE.md.
Working agreement: execute Phase P{N} via superpowers:subagent-driven-development; strict TDD,
one commit per task; obey §2 architecture invariants and §0 anti-drift rules; .NET 10 only.
Do NOT start other phases. Branch: phase/{NN}-{slug} off main (worktree per §0.5).
When done: fill the Phase P{N} STATUS block, tick exit criteria you have PROVEN with the
verification commands, set §1 ledger to NEEDS_REVIEW, and STOP for human review. If blocked, write
BLOCKED + the exact failing command/output into the STATUS block and STOP.
```

Notes:
- It points at the plan, the *specific* architecture sections, and CLAUDE.md — the three sources, scoped.
- It names the execution skill (`subagent-driven-development` for normal phases). For the heavy infra phase P0, the per-phase copy swaps in `executing-plans` (infra steps are imperative shell, not TDD units — see §4.4).
- It encodes the stop condition (NEEDS_REVIEW, not auto-merge) so the human checkpoint is structural, not optional.
- It's 6 lines. Short enough to paste, complete enough that the session needs no further instruction.

---

## 3. Review-checkpoint protocol

### 3.1 What the session does at the end (the STATUS block)

Every phase has a `STATUS` block at its tail in §3. The executing session **must** fill it before stopping. This is the resume anchor and the completion report in one. Literal format:

```markdown
#### STATUS
- **State:** NEEDS_REVIEW            <!-- or IN_PROGRESS / BLOCKED -->
- **Last commit:** 7c1aa90 "feat(cycle): confirm-draft transaction"
- **Branch / worktree:** phase/02-cycle-sx  (../lumen-wt/phase-02)
- **Tasks done:** 1,2,3,4 of 6        <!-- mirrors the step checkboxes -->
- **Exit criteria proven:**
  - [x] dotnet test green — 41 passed (paste tail of output below)
  - [x] /cycle/day POST→GET round-trips encrypted notes
  - [ ] matview refresh — N/A this phase
- **Verification output (pasted, not described):**
  ```
  $ cd backend && dotnet test --nologo
  Passed!  - Failed: 0, Passed: 41, Skipped: 0
  $ curl -fsS localhost:8080/cycle/day/2026-05-30 ... -> 200 {...}
  ```
- **Decisions made / docs changed:** none | "Chose Anthropic; ARCHITECTURE.md §A row + §4 updated."
- **Deviations from plan:** none | "Task 4 split into 4a/4b; tasks rewritten in §3."
- **For next session / reviewer:** "Remaining: tasks 5–6 (phase-override endpoint). DB is migrated to V07."
- **If BLOCKED:** exact failing command + full output + hypothesis.
```

The rule (from `verification-before-completion`): **the STATUS block must contain pasted command output, not prose claims.** "Tests pass" without the pasted `Passed! Failed: 0` line is not acceptable and the reviewer rejects it.

### 3.2 What the human inspects at the checkpoint

A two-tier protocol — light for normal phases, deep for the three safety-critical ones (P1 crypto spine, P3 inference engine, P4 lab parse).

**Every phase (light checkpoint):**
1. Read the STATUS block. Re-run the phase's **Verification commands** yourself — don't trust the paste. (`docker compose ps`, `dotnet test`, the probe.)
2. Confirm the exit-criteria boxes are genuinely ticked and proven.
3. `git diff main...phase/NN` skim for scope creep / secrets committed.
4. If good: flip §1 ledger row to DONE, fill `Verified by` with today's date, advance `NEXT PHASE TO RUN`. Merge per §4.

**Safety-critical phases (deep checkpoint, adds):**
5. Invoke the `code-review` skill on the diff at `high` effort (P1/P3) or `ultra` (P4 — touches LLM trust boundary, ClamAV, crypto-at-rest).
6. Phase-specific adversarial checks, e.g.:
   - **P1:** crypto-shred a test user → confirm ciphertext rows become undecryptable; confirm DEK never logged (grep Loki/console for the key); confirm DEK lifetime is request/job-scoped.
   - **P3:** run the golden-fixture suite; eyeball that phase/confidence outputs match hand-computed expectations; confirm rules read `ref_insight_rule`, not hardcoded.
   - **P4:** feed a known-good and a malformed PDF; confirm out-of-range/whitelist-failing values route to `needs_manual` and never auto-persist; confirm ClamAV rejects EICAR; confirm PDF stored as ciphertext in MinIO.
7. Only then DONE.

### 3.3 How progress is recorded — the three-layer answer

The question "checkboxes? STATUS block? commits?" — the answer is **all three, each at a different granularity, with one canonical source per question:**

| Question | Canonical source | Mechanism |
|---|---|---|
| "Which step within a phase was last done?" | step checkboxes in §3 tasks | `- [x]` ticked by executing agent |
| "Is this phase reviewable / what's the resume state?" | the phase STATUS block | filled at stop time, has pasted proof |
| "Is this phase actually accepted?" | §1 ledger row | flipped to DONE by the *human* only |
| "What exactly changed?" | git history | one commit per task, branch per phase |

The ledger (`§1`) is the *single* authority for "done". The agent may write NEEDS_REVIEW; only the human writes DONE. This prevents an over-eager session from marking its own work complete and a later session building on unverified ground.

### 3.4 Resuming a partial or failed session — no context loss

A fresh session never inherits chat history; it reconstructs state from the repo. The resume procedure:

1. New session reads §1 ledger → sees `P2 = IN_PROGRESS, branch phase/02-cycle-sx`.
2. Reads the P2 STATUS block → "Tasks done: 1–4 of 6; DB at V07; remaining tasks 5–6."
3. `git checkout phase/02-cycle-sx` (or the worktree path in STATUS), `dotnet test` to confirm the reported-green baseline actually is green *before* adding anything. (Trust-but-verify; if it's not green, you're now debugging the handoff, which is itself a finding.)
4. Resume at the first unchecked step checkbox. The pasted verification output + "DB at V07" + "remaining tasks" give it everything chat history would have.

The kickoff prompt for a resume is identical — the session figures out it's a resume from the ledger/STATUS, not from a different prompt. That's the point of putting the resume state *in the repo*.

**BLOCKED handling:** if a session hits a wall it can't resolve (e.g. the open question "which LLM provider" isn't decided at P4), it writes `BLOCKED` + the exact blocker into STATUS and ledger, and stops. The human resolves the decision (records it in §4 + ARCHITECTURE.md §A), then re-dispatches. The block reason lives in the repo, so the resolving session has full context.

---

## 4. Git strategy and mapping onto superpowers

### 4.1 Branch model: branch-per-phase off `main`

- **Trunk = `main`.** Each phase gets one long-ish-lived branch `phase/{NN}-{slug}` (e.g. `phase/02-cycle-sx`) cut from `main`.
- **Why branch-per-phase, not pure trunk:** each phase is "a shippable PR" by the architecture's own §H framing, and the human checkpoint maps cleanly to "review + merge the PR". Pure trunk would erase the review gate. Per-task branches would be too granular (a phase is the reviewable unit).
- **Isolation via worktree.** Each phase runs in its own git worktree (superpowers `using-git-worktrees`), so an interrupted phase doesn't pollute the main checkout and parallel inspection is possible. Path convention: `../lumen-wt/phase-NN` (recorded in STATUS). On Windows, use the `EnterWorktree` tool / `git worktree add`.
- **Never start a phase on `main`.** The kickoff prompt and the executing-plans skill both forbid it.

### 4.2 Commit conventions

Conventional Commits, scope = module/phase. One commit per task (the superpowers task is the commit unit — matches the plan's "Commit" step).

```
feat(cycle):     add cycle_events entity + migration V07
test(cycle):     phase-override endpoint integration test
chore(infra):    add MinIO + ClamAV services to compose (P4)
fix(labs):       reject out-of-range hormone values to needs_manual
docs(plan):      P2 -> NEEDS_REVIEW; record V07 in STATUS
```

- Scopes track the module catalogue (ARCHITECTURE.md §C): `infra, api, crypto, onboarding, cycle, symptoms, hormones, labs, body, activity, treatment, reports, settings, admin, jobs, obs, plan, flutter`.
- Migrations are their own commit (`feat(cycle): migration V07`) so the schema timeline is greppable.
- The **plan/doc update is its own `docs(plan)` commit** at phase end — see anti-drift §5. The phase branch's *last* commit is always the docs/STATUS update.
- All commits end with the project's required trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

### 4.3 When PRs happen

- **One PR per phase**, opened when the phase hits NEEDS_REVIEW (not before — no draft-PR-per-task noise).
- PR body = the STATUS block, verbatim, plus the exit-criteria checklist and the pasted verification output. So the PR *is* the completion report; reviewing the PR and reviewing the phase are the same act.
- PR merges only after the human checkpoint (§3.2) flips the ledger. Safety-critical phases require the `code-review` skill pass attached to the PR.
- Merge strategy: **squash-free merge commit per phase** (keep the per-task history; the phase is a meaningful unit of history worth preserving for an auditable medical-data system). Tag merges `phase-NN` for easy rollback points.

### 4.4 Mapping onto the superpowers skills

The orchestration is a thin shell over the existing skills; it does not replace them.

```
writing-plans          -> produces/maintains docs/superpowers/plans/lumen-build.md.
                          Run ONCE up front to author §0–§5 and stub all phases; re-run its
                          self-review when a phase is re-planned. The per-phase task bodies
                          ARE writing-plans output (bite-sized TDD, exact paths, real code).

using-git-worktrees    -> first action of every phase session (isolated workspace).

subagent-driven-dev    -> the default per-phase executor: fresh implementer subagent per task,
                          spec-review then code-quality-review per task, final review at phase end.
                          This is why a phase = a self-contained set of independent-ish tasks.

executing-plans        -> the fallback executor for P0 (infra) and any phase that is imperative
                          shell rather than TDD units. Batch-execute with the human checkpoint.

test-driven-development -> every implementer subagent uses it (backend) — red/green/commit.

requesting/receiving-code-review + the code-review skill
                       -> the review checkpoint, escalated to high/ultra for P1/P3/P4.

finishing-a-development-branch
                       -> end-of-phase: verify tests, present merge/PR options, flip ledger.
verification-before-completion
                       -> gate before any NEEDS_REVIEW claim: paste real command output.
```

Concretely: a normal phase session runs `using-git-worktrees` → `subagent-driven-development` (which internally drives `test-driven-development` per task and the two review subagents) → `finishing-a-development-branch`, then writes STATUS + ledger and stops. The orchestration layer only adds the *plan format*, the *kickoff prompt*, the *STATUS/ledger bookkeeping*, and the *deep-review escalation* — all of which sit cleanly on top.

---

## 5. Anti-drift: keeping the plan in sync with the repo

The failure mode this prevents: session N+1 reads a phase description written against a repo state that session N already changed (renamed a type, bumped a migration, resolved an open question), and builds on a lie.

### 5.1 Rules (encoded in §0 of the plan, enforced at review)

1. **Docs change in the same branch as the code that invalidates them.** No "I'll update the plan later." The phase branch's final commit is always `docs(plan): ...`. The architecture doc already mandates this ("Where a future session disagrees with something here, update this file as part of the same change") — the plan inherits it.
2. **The ledger is updated with a repo SHA.** §1 carries `Repo HEAD when ledger last updated:`. A session whose `git rev-parse HEAD` predates that SHA on its base knows the ledger is ahead of its view and re-reads. Cheap staleness detector.
3. **Decisions resolve in two places atomically.** When a phase resolves an ARCHITECTURE.md §I open question (LLM provider, unseal mode, backup provider), it (a) adds a §A decision row in ARCHITECTURE.md and (b) logs it in plan §4 with the phase + date. Both in the same `docs` commit. The plan §4 is the build-time mirror of the architecture decision log.
4. **No content duplication between plan and architecture doc.** The plan *references* (`ARCHITECTURE.md §E step 9`), it does not paste. Pasted facts drift; references can't. The only facts the plan owns are: status, task breakdown, exact verify commands, and build-time decisions (§4).
5. **Future-facing task bodies are rewritten, not appended, when reality diverges.** If P2 renamed `clearLayers`→`resetLayers`, and P5's tasks referenced the old name, P2's `docs(plan)` commit fixes P5's task text too. Stale task text is a `writing-plans` "Type consistency" failure and is treated as a bug.
6. **§2 architecture invariants are the immutable spine.** A short, pinned list (Caddy→JWT→Vault DEK→envelope-encrypted Postgres; .NET 10; online-only cache; realm `lumen`; crypto-shred erasure). Sessions may extend modules but may not contradict §2 without a human-approved §A change. This is the "faithful to the docs" guard.

### 5.2 The plan-sync checklist (part of every phase's exit criteria)

```markdown
- [ ] §1 ledger row + NEXT PHASE pointer + Repo HEAD SHA updated
- [ ] This phase's STATUS block filled with pasted verification output
- [ ] Any new type/path/migration referenced by LATER phases corrected in their §3 task text
- [ ] Any resolved ARCHITECTURE.md §I question recorded in ARCHITECTURE.md §A AND plan §4
- [ ] No fact pasted from ARCHITECTURE.md into the plan (reference by § instead)
```

### 5.3 Periodic reconciliation (cheap, automatable)

At each checkpoint the human (or a quick subagent) runs a 60-second drift scan:
- `git rev-parse HEAD` vs the ledger's recorded SHA — must match after merge.
- `Glob` for migration files vs the highest migration named in STATUS — must match.
- `Grep` the plan's later-phase task text for type/endpoint names that the just-merged phase renamed — must find none stale.
- Confirm every `Status: DONE` row in §1 has a real merged `phase-NN` tag.

A mismatch is a blocker for starting the next phase, not a footnote.

---

## Summary of the moving parts

- **One file** (`docs/superpowers/plans/lumen-build.md`) with a **status ledger at the top** as the single authority for "done", **architecture invariants** as the immutable spine, **one subsection per phase** carrying its own kickoff prompt + exit criteria + verify commands + TDD tasks + a live STATUS block.
- **A 6-line kickoff prompt** (literal template in §2 above) the human pastes into each fresh session; it scopes reading to the plan + specific architecture sections + CLAUDE.md and pins the stop-at-NEEDS_REVIEW agreement.
- **Three-layer progress recording** (step checkboxes → STATUS block → ledger DONE), with the human owning the DONE flip and a deep `code-review`-skill checkpoint for P1/P3/P4.
- **Branch-per-phase off main, one PR per phase, conventional commits, worktree isolation**, mapping `writing-plans → subagent-driven-development (executing-plans for infra) → code-review → finishing-a-development-branch`.
- **Anti-drift by same-branch doc edits, a SHA-stamped ledger, reference-not-paste, and a per-phase plan-sync checklist**, so every fresh session works from a description the repo still backs.

Relevant files: the plan to be authored at `C:\Proyectos\Endo\docs\superpowers\plans\lumen-build.md`; sources it references are `C:\Proyectos\Endo\docs\ARCHITECTURE.md` and `C:\Proyectos\Endo\CLAUDE.md`.
