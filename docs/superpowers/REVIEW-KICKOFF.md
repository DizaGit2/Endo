# Lumen — Reviewer kickoff prompt (agent-runnable)

**Audience:** the human gate (you). This file gives you a prompt you paste, verbatim, into a **fresh** Claude session to have an agent review a phase PR against [`RUNBOOK.md`](RUNBOOK.md) §4 / §9 (and §5 for ⚠ phases). It is the review-side twin of the build kickoff prompts in the plan's §3.

**What the agent does:** checks out the branch, re-runs every verify command, verifies each claim in the STATUS block at HEAD, reads the diff, and posts one **COMMENT** review on the PR plus a report file. **What the agent never does:** approve, request changes, merge, flip the ledger, tag, or push. Accepting amendments, ruling on defects and bookings, and marking the phase `DONE` are yours (RUNBOOK §1: *you are the gate*; §8: the merge is a local ritual).

Fill the `{…}` placeholders from the plan's §1 ledger row, then paste §1 below. §2 is the P4b instance already filled in. §3 explains the GitHub rules the prompt enforces.

---

## 1. The prompt (generic — fill the placeholders)

```text
You are the REVIEWER for Lumen phase {PNN} ({phase name}). Read `CLAUDE.md`, then `docs/superpowers/RUNBOOK.md` §3 steps 5–7, §4, §9 {and §5 if the ledger marks the phase ⚠}, then the phase's subsection in `docs/superpowers/plans/lumen-build.md` §3 (its "Verify commands", "Exit criteria" and STATUS block) and the §1 ledger row. The ledger is the only authority on what the phase claims.

PR: {PR URL}   Branch: {phase/NN-slug}   Base: main   Plan revision under review: {rNN}

YOUR ROLE AND LIMITS
- You verify and report. You do NOT decide. Only the human marks a phase DONE.
- Never run: `gh pr merge`, `gh pr review --approve`, `gh pr review --request-changes`, `git merge`, `git tag`, `git push`, or any edit to the §1 ledger row / `NEXT PHASE TO RUN`. Do not edit any file on the branch. If a verify command needs a fix, that is a hand-back finding, not something you fix.
- Every verdict cites evidence you produced in this session: a command and its pasted output, or a file:line at branch HEAD. "The STATUS block says so" is not evidence (RUNBOOK §3 step 6: don't trust the pasted output — re-run it).
- Environment: run flutter/dart only with `$env:PUB_CACHE='C:\pub_cache'` set in the same PowerShell command, and read the LAST LINE of the output rather than the exit code — a mangled PUB_CACHE dies at "Failed to update packages" while the pipeline reports exit 0 (CLAUDE.md). If any command's output is truncated or ambiguous, re-run it with output redirected to a file and read the file.

STEP 0 — Set up (paste output of each)
  git fetch origin; git checkout {phase/NN-slug}; git pull --ff-only
  git rev-parse HEAD                                  # must equal the PR head SHA below
  gh pr view {N} --json headRefOid,baseRefName,mergeable,isDraft,statusCheckRollup
  gh pr checks {N}                                    # every required check SUCCESS at the PR head SHA
  git merge-base main HEAD; git log --oneline main..HEAD | wc -l   # commit count vs the ledger's claim
If HEAD ≠ headRefOid, stop and report: the branch moved since the PR was described.

STEP 1 — RUNBOOK §4 light checklist, item by item, with pasted output
  a. STATUS block contains PASTED command output, not prose. Quote the lines you checked.
  b. Re-run the phase's "Verify commands" block verbatim, plus the §4 minimum:
       docker compose -f deploy/docker-compose.yml ps
       dotnet build backend/Lumen.slnx -warnaserror --nologo
       dotnet test backend/Lumen.slnx --nologo
     Paste the final summary line of each. Count skips; every skip needs a named reason in the code or the plan.
  c. Exit criteria: for every checkbox in the phase's "Exit criteria", state MET / NOT MET / AMENDED and name the test file, golden, or command output that proves it. A criterion amended by an R-xx ruling is reported as AMENDED with the ruling id, never as MET.
  d. Diff review:
       git diff main...HEAD --stat
       git diff main...HEAD | Select-String -Pattern "password|secret|api[_-]?key|BEGIN .*PRIVATE KEY"
     Report scope creep (files outside the phase's stated surface) and any secret hit. Then read the diff itself, not just --stat: correctness, error/retry paths, anything the tests pin as correct that the plan calls a defect.
  e. Contract gate: `cmp backend/contract/openapi.json client/openapi/lumen.openapi.json` and `git diff {previous phase tag}..HEAD --stat -- backend/contract client/lib/api client/openapi`. If the phase claims "no contract change", this diff must be empty.
  f. Client phases: `flutter analyze`, `flutter test`, `flutter test --tags golden`, `flutter test --coverage; dart run tool/check_coverage.dart` — all under PUB_CACHE, all with the last line pasted.

STEP 2 — RUNBOOK §9 definition of done: one line per item 1–8, GREEN / RED / N-A with the evidence pointer. Item 6's "integration_test green" — say exactly what stands in for it if the phase amended it.

STEP 3 — Claims in STATUS that need a ruling (the human's, not yours)
  For every amendment (R-xx), every defect (D-x) and every booking table the STATUS block flags for the reviewer:
  - Verify its cited evidence exists at HEAD (open the file:line, run the test, or state that it cannot be verified from the repo).
  - Give a RECOMMENDATION (accept / reject / fix-before-merge / carry-to-{next phase}) with a one-sentence reason.
  - Never write "accepted". The decision column stays empty for the human.

STEP 4 — Report
  Write `docs/superpowers/reviews/{PNN}-review-{YYYY-MM-DD}.md` in your scratch area (NOT committed to the branch) with sections: Summary verdict (PASS-READY-FOR-HUMAN-RULING / HAND-BACK, with the single most important reason first); §4 checklist table; §9 table; exit-criteria table; rulings-needed table with your recommendations; findings (severity H/M/L, file:line, failure scenario); commands run (each with its last line).
  Then post it as ONE comment review on the PR — a COMMENT event, never approve/request-changes:
       gh pr review {N} --comment --body-file <report path>
  Optional inline notes on specific lines (max 10, H/M only):
       gh api repos/DizaGit2/Endo/pulls/{N}/comments -f body="…" -f commit_id="<HEAD SHA>" -f path="<file>" -F line=<n> -f side=RIGHT
  Stop. Do not flip the ledger, merge, tag or push. Your last message to the human is the Summary verdict plus the list of rulings they owe.

HAND-BACK RULE (RUNBOOK §7): if ANY verify command is red, or HEAD ≠ PR head, or a STATUS claim is contradicted by what you ran, the verdict is HAND-BACK and the report names the exact failing command and its output. Do not approve around a red test; do not soften it.
```

---

## 2. Filled instance — P4b, PR #4 (paste this one as-is)

```text
You are the REVIEWER for Lumen phase P4b (Flutter: screens 3–14, 32). Read `CLAUDE.md`, then `docs/superpowers/RUNBOOK.md` §3 steps 5–7, §4, §9 (P4b is NOT a ⚠ safety-critical phase, so §5 does not apply), then the "### Phase P4b" subsection in `docs/superpowers/plans/lumen-build.md` §3 — its "Verify commands", "Exit criteria", the STATUS block (the "FOUR AMENDMENTS THE REVIEWER MUST ACCEPT OR REJECT" heading comes first, then the pasted sweep, the WALK RESULT, exit criteria, the bookings table) — and the §1 ledger row for P4b. The ledger is the only authority on what the phase claims.

PR: https://github.com/DizaGit2/Endo/pull/4   Branch: phase/04b-logging-client   Base: main   Plan revision under review: r22
Previous phase tag (contract baseline): phase-04a

YOUR ROLE AND LIMITS
- You verify and report. You do NOT decide. Only the human marks a phase DONE.
- Never run: `gh pr merge`, `gh pr review --approve`, `gh pr review --request-changes`, `git merge`, `git tag`, `git push`, or any edit to the §1 ledger row / `NEXT PHASE TO RUN`. Do not edit any file on the branch. If a verify command needs a fix, that is a hand-back finding, not something you fix.
- Every verdict cites evidence you produced in this session: a command and its pasted output, or a file:line at branch HEAD. "The STATUS block says so" is not evidence.
- Environment: run flutter/dart only with `$env:PUB_CACHE='C:\pub_cache'` set in the same PowerShell command, and read the LAST LINE of the output rather than the exit code — a mangled PUB_CACHE dies at "Failed to update packages" while the pipeline reports exit 0. If output is truncated or ambiguous, redirect it to a file and read the file.

STEP 0 — Set up (paste output of each)
  git fetch origin; git checkout phase/04b-logging-client; git pull --ff-only
  git rev-parse HEAD
  gh pr view 4 --json headRefOid,baseRefName,mergeable,isDraft,statusCheckRollup
  gh pr checks 4                                      # openapi-contract, flutter, build-and-unit, integration — all SUCCESS at HEAD
  git merge-base main HEAD; git log --oneline main..HEAD | wc -l   # ledger claims 136 commits at r22; a higher count means docs commits landed after — list them
If HEAD ≠ headRefOid, stop and report.

STEP 1 — RUNBOOK §4 light checklist, with pasted output
  a. STATUS block: confirm the sweep is pasted output. Quote the flutter test summary, the coverage line, the dotnet test summary, and the `cmp` / `git diff phase-04a..HEAD` lines you checked.
  b. Re-run, pasting the last line of each:
       docker compose -f deploy/docker-compose.yml ps
       dotnet build backend/Lumen.slnx -warnaserror --nologo                     # expect 0 warnings
       dotnet test backend/Lumen.slnx --nologo                                   # ledger claims 1228: 1008 unit / 213 integration / 7 security, zero skips
       dotnet test backend/Lumen.slnx --filter "FullyQualifiedName~OpenApi"      # contract snapshot green
       cmp backend/contract/openapi.json client/openapi/lumen.openapi.json       # byte-identical
       git diff phase-04a..HEAD --stat -- backend/contract client/lib/api client/openapi   # must be EMPTY (no contract change)
       $env:PUB_CACHE='C:\pub_cache'; cd client; flutter analyze                 # clean
       $env:PUB_CACHE='C:\pub_cache'; cd client; flutter test                    # ledger claims 2286, zero skips
       $env:PUB_CACHE='C:\pub_cache'; cd client; flutter test --tags golden      # light+dark goldens
       $env:PUB_CACHE='C:\pub_cache'; cd client; flutter test --coverage; dart run tool/check_coverage.dart   # ledger claims 97.16% vs 60.0 floor
     The integration tests need the compose stack up and healthy; if the stack is stale, note RUNBOOK §7 and the plan's Trap C (a stale `api` container answers `/health` healthy while routes 404) and rebuild with `docker compose -f deploy/docker-compose.yml up -d --build` before judging a red run.
  c. Exit criteria (7 checkboxes in the P4b section): MET / NOT MET / AMENDED per line with the proving test, golden, or output. Note in particular:
       - the registry gate: name the test that fails when a screen ships without a golden or a Semantics test, and run it;
       - "error/retry state" for screens 9, 11, 12 and 3–7, 32 — screen 13 is struck by R-22, report it as AMENDED;
       - "integration_test green" is AMENDED by R-06 — report (i) `test/flows/` count and result, (ii) the on-device walk as recorded evidence you can only read, not re-run, and (iii) as booked by P4c-T0 (proposed);
       - every §C.0.1 write hazard has a named negative test — list the test names you found.
  d. Diff review:
       git diff main...HEAD --stat
       git diff main...HEAD | Select-String -Pattern "password|secret|api[_-]?key|BEGIN .*PRIVATE KEY"
     Surface expected: client/ (screens, routes, repositories, tests, goldens), docs/. Any backend/src or deploy/ change is scope creep to report. Then read the client diff: onboarding gate and route table (T1), the shell (T2), every repository's error path, the cache policy over reads, screen 36's `DELETE /me` wiring.
  e. Contract gate: covered by 1.b's `cmp` and `git diff phase-04a..HEAD`.
  f. Client checks: covered by 1.b.

STEP 2 — RUNBOOK §9 items 1–8: one line each, GREEN / RED / N-A, with the evidence pointer. Item 7 is N-A (not ⚠). Item 6: say exactly what stands in for integration_test.

STEP 3 — Claims that need the human's ruling (verify evidence, recommend, never decide)
  Amendments — verify each one's cited evidence at HEAD and recommend accept/reject:
    R-06 (three parts; (iii) booked as P4c-T0 proposed — confirm the booking text exists in the P4c section)
    R-08 (screen 14 ships phase-unavailable; `POST /cycle/phase-override` deferred to P6 — confirm no client code calls it)
    R-21 (Front/Back cut from screen 13; every body-map point carries `side: null` — confirm in the request builder and its test)
    R-22 (screen 13 is not a write screen — confirm it has no repository and no request)
  Defects — for each, locate the code path and the test that pins the current behaviour as correct, and recommend fix-before-merge or carry-to-P4c (B-49 / B-50):
    D1 — the client never sends the device timezone (D-12 ratified; check the account/registration request and `client/tool/tz_probe.dart`), so the one-row-per-day check-in upsert can lose data.
    D2 — a transport failure during token refresh signs the user out and purges the on-disk cache (auth spine; find the test that asserts it).
  Bookings — the STATUS table of 51 bookings: do NOT re-verify all 51. Verify the five the ledger ranks highest (LumenSectionLabel ALL-CAPS a11y defect, app-lock owner, C-15/L-04 exposure on the 10/10 pain surfaces, the amenorrhea onboarding dead end, screen 36's privacy copy) and for each say whether it needs a fix, an owner, or a PO decision.

STEP 4 — Report
  Write `P4b-review-<today>.md` in your scratchpad (not on the branch) with: Summary verdict (PASS-READY-FOR-HUMAN-RULING / HAND-BACK, most important reason first); §4 table; §9 table; exit-criteria table; rulings-needed table (R-06, R-08, R-21, R-22, D1, D2, top-5 bookings) with your recommendation and an empty "Human ruling" column; findings (H/M/L, file:line, failure scenario); commands run with last lines.
  Post it as ONE comment review — never approve/request-changes:
       gh pr review 4 --comment --body-file <report path>
  Optional inline notes (max 10, H/M only):
       gh api repos/DizaGit2/Endo/pulls/4/comments -f body="…" -f commit_id="<HEAD SHA>" -f path="<file>" -F line=<n> -f side=RIGHT
  Stop. Do not flip the ledger, merge, tag or push. Your last message is the Summary verdict plus the rulings the human owes: the four amendments, D1/D2, the bookings.

HAND-BACK RULE (RUNBOOK §7): any red verify command, HEAD ≠ PR head, or a STATUS claim contradicted by what you ran ⇒ verdict HAND-BACK, naming the exact failing command and its output. Do not approve around a red test.
```

---

## 3. GitHub rules the prompt enforces (and why)

All GitHub access goes through the authenticated `gh` CLI (`gh auth status` must show the `DizaGit2` account). Never paste a token into a prompt, a file, or a command.

| Need | Command | Notes |
|---|---|---|
| PR metadata | `gh pr view N --json headRefOid,baseRefName,mergeable,isDraft,statusCheckRollup` | `headRefOid` is the SHA the review is about; compare it to `git rev-parse HEAD` after checkout. Add `--jq` to pick fields. |
| CI status | `gh pr checks N` | Reads the check runs on the PR head. Every required check must be `SUCCESS`; `--watch` waits for pending ones. |
| Changed files | `gh pr diff N --name-only` or `gh api repos/DizaGit2/Endo/pulls/N/files --paginate --jq '.[].filename'` | The REST list is paginated at 30 per page; `--paginate` follows the `Link` header. Prefer the local `git diff main...HEAD` for content. |
| Commits on the PR | `gh api repos/DizaGit2/Endo/pulls/N/commits --paginate --jq 'length'` | Capped at 250 by the API; the local `git log main..HEAD` is authoritative. |
| Post the review | `gh pr review N --comment --body-file report.md` | This creates a pull-request review with `event=COMMENT`. It is the only review event an agent may use. `--approve` and `--request-changes` are the human's. |
| Inline comment | `gh api repos/DizaGit2/Endo/pulls/N/comments -f body=… -f commit_id=<sha> -f path=<file> -F line=<n> -f side=RIGHT` | `line` is a line in the **new** file (`side=RIGHT`) and must be inside a diff hunk; `commit_id` must be the PR head SHA or the API returns 422. `-F` sends a number, `-f` a string. Use `-f start_line=` + `-f start_side=` for a range. |
| Existing review comments | `gh api repos/DizaGit2/Endo/pulls/N/comments --paginate` and `gh pr view N --comments` | Read before posting so you do not duplicate an earlier review. |
| Rate limit | `gh api rate_limit --jq .resources.core` | Authenticated REST allows 5,000 requests/hour; a review uses a few dozen. Back off on HTTP 403 with `x-ratelimit-remaining: 0`, and on 429 or any `Retry-After` header. |

Never: `gh pr merge` (RUNBOOK §8 merges locally with `--no-ff`, never the GitHub button or its CLI twin), `gh pr edit` on the body, `gh pr close`, or any write to the ledger. A review that finds the PR unmergeable reports HAND-BACK; it does not request changes on GitHub, because the hand-back path in RUNBOOK §7 is a fresh build session with the kickoff prompt plus the failing command, not a GitHub state change.
