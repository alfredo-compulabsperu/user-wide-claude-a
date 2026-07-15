---
name: run-prd
description: >-
  Drive an entire PRD to a reviewed PR: generate and run a master orchestration
  runbook that produces an implementation plan per pending milestone, implements
  each, then commits, opens one PR, and runs a fast/normal/full code review
  (--review, default fast). Use this
  whenever the user wants to take a whole PRD (a .prd.md with a Delivery
  Milestones table) end-to-end — phrases like "run this PRD", "implement all of
  <prd>", "build out every milestone", "take <prd> to a PR", "finish the PRD",
  or "auto-implement <prd>". Trigger even if the user says "the PRD" without a
  path, or names milestones instead of the PRD. Do NOT trigger for a single
  plan already written (use execute-plan) or for authoring the PRD itself (use
  plan-prd).
---

# run-prd — PRD → plans → implementation → reviewed PR

## What this is (and what it is not)

`run-prd` is a **thin orchestrator**. It walks a PRD's **Delivery Milestones
table** and, per pending milestone, delegates the real work down to `/ecc:plan`
and the implementer. It owns *sequencing and gating across milestones* — nothing
milestone-specific. If you find yourself putting build logic here, it belongs in
a plan, not in this runbook.

The altitude split it respects:

| Layer | Artifact | Owns |
|---|---|---|
| Requirements | the **PRD** (`.prd.md`) | milestone table + `Status` column = backlog & state |
| Design (one milestone) | a **plan** (`.plan.md`) | how to build that milestone |
| Orchestration (whole PRD) | **this runbook** | loop milestones → plan → implement → PR → review, until done |

The **PRD `Status` column is the state machine.** A milestone is `pending`,
`in-progress`, or `complete`. That makes the whole run **resumable**: a rerun
skips `complete` milestones and picks up at the first `pending` one. Never track
run state anywhere else — the PRD is the single source of truth.

## Inputs & preconditions

- **Input:** a PRD path (`.claude/prds/<name>.prd.md`). If the user didn't give
  one, find the most recently modified `.prd.md` under `.claude/prds/` and
  confirm it.
- The PRD **must** have a `## Delivery Milestones` table with a `Status` column.
  If it doesn't, stop and point the user at `/ecc:plan-prd` — there's no backlog
  to walk.
- **`--review <mode>`** (optional; default `fast`): review rigor for Phase D —
  one of `fast` | `normal` | `full`. See *Review depth resolution*.
- **`--confirm`** (optional): ask one upfront "run this whole PRD end-to-end?
  (y/n)" before Phase 0 starts. Without it (the default), the run is fully
  unattended — see *Confirmation model*.
- **`-w`, `--worktree`** (optional, boolean): explicitly confirms the
  isolated-worktree default (see *Phase 0 — Isolate*). Harmless no-op if
  passed, since isolation already happens without it.
- **Existing-runbook check** (before anything else): look for
  `.claude/runbooks/<prd-slug>.runbook.md`. If it exists and its **Stop
  condition was already met** (all milestones complete, both review passes
  clean), stop and ask the user to choose — see *Resume / checkpoint*. A
  partial runbook (some milestones still pending) skips this prompt and
  resumes normally.

## What it produces

1. An isolated git worktree for the run (see *Phase 0 — Isolate*), unless
   already running inside one that matches this PRD.
2. A runbook file at `.claude/runbooks/<prd-slug>.runbook.md` (create the dir if
   missing) — the materialized, checkpointable plan of the run, including a
   running per-milestone log (isolate/inline + reason, STATUS, deviations)
   appended as Phase B completes each milestone — Phase E's retrospective
   reads this log, not a closed agent's context.
3. Per-milestone plans saved by `/ecc:plan` under `.claude/plans/`.
4. One branch, one PR, with the whole run's changes, reviewed twice.

## The runbook it generates and executes

Materialize this structure into the runbook file, then execute it top to bottom.
Keep it lean — it is a driver, not a design doc.

### Phase 0 — Isolate

Before Pre-flight, ensure the run executes in its own worktree:

- If the current session is already inside a worktree whose name matches the
  PRD slug (e.g. this session was opened for that purpose), skip — no nested
  worktree.
- Otherwise, call `EnterWorktree` with `name: "<prd-slug>"`. This is the
  harness's own worktree tool — it creates `.claude/worktrees/<prd-slug>` on a
  new branch and switches the session into it. Do not shell out to
  `git worktree add` directly; `EnterWorktree` also resets CWD-dependent
  session state correctly.
- `-w`/`--worktree` does not change this behavior — it is accepted purely as
  an explicit, no-op confirmation for users who want to state the intent.
- Log the worktree name/path in the runbook so Phase C's PR and the final
  report can reference it.

### Confirmation model

Two modes, chosen by the presence of `--confirm`:

- **Default (no `--confirm`): fully unattended.** Once Phase 0 and Pre-flight
  clear, the whole run — every milestone's plan, its implementation, the
  commit, the PR, and the review-fix cycle — proceeds without stopping to ask
  the user anything. This includes overriding `/ecc:plan`'s own built-in
  "wait for explicit yes/proceed before writing code" gate: when `run-prd`
  invokes `/ecc:plan` in this mode, it treats the generated plan as
  auto-confirmed and moves straight into Phase B. This override is
  intentional and scoped to `run-prd`'s own invocation of `/ecc:plan` — it is
  not a general instruction to skip that gate elsewhere.
- **`--confirm`: one upfront prompt, then still unattended.** Ask "run this
  whole PRD end-to-end? (y/n)" once, before Phase 0. If the user declines,
  stop. If they approve, the rest of the run proceeds exactly as the default
  mode — no further per-milestone or per-phase prompts.
- **What neither mode touches:** the Pre-flight gate (still a hard stop —
  Claude cannot perform human-only chores regardless of flags) and the
  **Safety gates** destructive-action tiering below (force-push, history
  rewrite, dropping data, live CI/CD). Auto-start waives the *planning*
  confirmation only; it is not a license to bypass the separate, more
  fundamental destructive-action gate.

### Pre-flight (human-only chores) — GATE

First section, always. Enumerate **only** tasks a human must do that Claude
cannot (credentials, access grants, external-system changes, UI clicks) — derive
them by scanning the PRD's milestones and risks. Apply the filter test: "Does
this need a human to act in an external system or supply info Claude can't read
from the filesystem/shell/env?" If no, omit it.

- If every Pre-flight box is `[x]`, proceed immediately — no prompt.
- If any box is `[ ]`, **stop** and wait for the user to reply "pre-flight done"
  (or equivalent). Do not begin Phase A until then.

### Phase A — Generate plans (loop over pending milestones)

For each milestone with `Status = pending`, in table order:

1. **Re-verify before building.** If the PRD carries prior "findings"/assumptions
   (e.g. a Verified-findings block), re-check the ones this milestone depends on
   against live disk/runtime — dispositions drift across sessions. Report drift
   before acting; don't build on a stale premise.
2. Run `/ecc:plan <prd>` — it picks the next pending milestone and writes
   `.claude/plans/<milestone-slug>.plan.md`. **Include any `## Deviations`
   logged by prior milestones in the prompt** — a deviation earlier in the
   run (an approach change, a discovered constraint) can change what the
   correct design is for this milestone; don't let `/ecc:plan` work from a
   stale assumption. Save the plan. Regardless of mode, do not pause here
   for `/ecc:plan`'s own confirmation gate — see *Confirmation model* (the
   only possible pause is the single upfront `--confirm` prompt, already
   resolved before Phase 0).
3. **Dependency-sequence check.** A plan that adds a shared dependency (schema,
   artifact, command, field) can silently mis-order: a consumer scheduled before
   the thing it consumes exists. Verify creation-before-first-write, and
   replacement-before-deletion. For non-trivial plans, verify with a cold-read
   planner agent ("assume no prior state") rather than self-review — see
   *Harness tool bindings* for the `planner` binding this relies on.
4. **Completeness gate for isolated dispatch.** If Phase B will isolate this
   milestone's implementation (per the isolation rubric), check whether the
   plan alone gives a fresh, zero-memory agent everything it needs: explicit
   files, the exact change, an inline verification command. Split any gap
   into two buckets — **resolvable via handoff** (an earlier phase/milestone
   will produce it; note as an expected input) is not a blocker; **not
   resolvable by anything in this run** (a human decision, missing
   requirement) is a **HALT** — surface it before Phase B runs. Skip this
   gate when Phase B runs inline (full conversation context already
   present).
5. Set the milestone `Status = in-progress` in the PRD.

Whether to run step 2/3 **inline or isolated** is decided by the **isolation
rubric** below.

> Sequencing note: generate a milestone's plan **immediately before** implementing
> it (A→B per milestone), not all plans up front — because an earlier milestone's
> implementation (especially a spike) can change a later milestone's correct
> design. Batch-planning up front bakes in stale assumptions.

### Phase B — Implement each plan

For the plan just generated:

1. **Classify the plan** (see *Code vs non-code* below).
   - **Touches code/scripts/tests** → implement test-first using the **project's
     TDD workflow** (the `tdd` binding — see *Harness tool bindings*; falls back
     to `/ecc:tdd-workflow`). Untested code is the expensive failure mode, so this is
     the default whenever a plan is code-bearing.
   - **No code** (docs, config values, content, research artifacts) → implement
     with the **general agent**. TDD ceremony on prose wastes turns.
   - **Mixed** → resolved TDD workflow for the code artifacts, general agent for
     the rest.
2. Decide **inline vs isolated** via the rubric. **If isolated**, the dispatch
   prompt must explicitly state: implement this plan directly via the TDD
   workflow — do not invoke `execute-plan` or treat this as its own
   end-to-end plan-to-PR run; this milestone's PR/review is owned by this
   run's Phase C/D, not by the dispatched call. This prevents a dispatched
   agent from re-triggering `execute-plan`'s own skill recognition on the
   same plan file and opening a second, conflicting PR.
3. **Require a structured report from isolated implementation calls**, last
   thing in the agent's response, enclosed for reliable extraction:
   ```
   --AGENT RESULT--
   STATUS: OK | WARN | ERROR
   SUMMARY: <one paragraph, what happened>
   DEVIATIONS: <what plan/PRD requirement wasn't honored and why, or "none">
   --END AGENT RESULT--
   ```
   Inline implementation skips this — the orchestrator already has full
   context and performs the fidelity check itself in step 4.
4. **Verify plan/PRD fidelity, not just the post-condition.** Before marking
   complete, check whether the implementation honored every requirement the
   *plan or PRD stated specifically for this milestone* — a named library,
   a required format, an explicit exclusion, a stated non-functional
   constraint — not just whether it passes its functional gate. (This is
   about this plan/PRD's own stated requirements; general repo/harness rules,
   if any, are a separate governance layer this skill does not police.) For
   an isolated call, this is the returned `DEVIATIONS` field, not a fresh
   self-review — the orchestrator has no other visibility into what happened
   inside that call. Log any deviation in the runbook's `## Deviations`
   section (milestone, what was required, what happened, why) **immediately
   on the call returning** — a deviation doesn't block `complete` by itself,
   but it must never be silent, and it cannot be recovered later once an
   isolated call's context is gone.
5. **Append this milestone's outcome to the runbook's running log**
   (isolate/inline decision + one-line reason, STATUS if isolated,
   deviations if any) regardless of step 4's outcome. Phase E's retrospective
   can only read what happened inside an isolated call from this log and
   from git history — it cannot reach back into a closed agent context.
6. On success (post-condition verified — see *Gates*), set the milestone
   `Status = complete` in the PRD.

**Writes must not race.** The whole run lands on **one branch / one working
tree**, so two isolated implementation agents writing concurrently will corrupt
each other. Default to **serial** implementation across milestones. Parallelize
only provably file-disjoint plans, and only via separate git worktrees merged
back — otherwise keep it serial.

Loop A→B until no milestone is `pending`.

### Phase C — Consolidate: commit + one PR

Once all milestones are `complete`:

1. **Reconcile the PRD's prose status.** The `Status` column is the state machine,
   but PRD templates often stamp a prose status footer (e.g. "*Status: DRAFT —
   requirements only…*"). If the PRD carries one, update it to the run's end state
   (e.g. "*Status: EXECUTED — all milestones complete; PR pending merge.*") before
   committing, so the file never ships with two contradictory status
   representations. Don't reference the PR number here — it doesn't exist yet.
2. Commit **every file touched by the run** with a message referencing the PRD
   and the milestones (`Refs`/`Closes` any linked issues).
3. Push and **create the PR** (or update the branch's existing PR). Target the
   integration branch (`develop` here; the repo's stated integration branch
   otherwise). One PR for the whole run.

### Phase D — Code review (depth = `--review` mode)

Resolve the reviewer for the chosen mode (the `review.<mode>` binding — see
*Harness tool bindings*), run it
over the run's PR/diff using the PRD as the spec, and **fix all non-LOW findings**
(CRITICAL / HIGH / MEDIUM) on every pass. File LOW + out-of-scope findings as a
tracked follow-up issue *before* merge so nothing floats. Scope each finding as
introduced-vs-preexisting — a large branch shows the whole accumulation, not just
this run's commits. Commit + push after each pass.

- **`fast` (default):** one pass with the resolved fast reviewer (fallback: the
  `ecc:code-reviewer` agent). A cheap, quick gate for the common case.
- **`normal`:** bounded convergence rounds with the resolved normal reviewer
  (fallback: `/ecc:code-review`) — round 1 always runs; round 2 always runs
  **isolated** (fresh agent, clean context, not anchored by round 1)
  regardless of what round 1 found; round 3+ only if the immediately prior
  round found any non-LOW issue, stopping at the first clean round.
- **`full`:** the resolved full reviewer (fallback: `/ecc:review-pr`), which is
  already a comprehensive multi-agent review. Run once; a light isolated re-check
  after fixes is optional, not required.

### Phase E — Retrospective

Once Phase D's review rounds leave no non-LOW findings, produce one combined
analysis from two sources:

1. **Rule violations** — review the whole run's changes against the repo's
   `CLAUDE.md`/`rules/*.md`: which rules were violated, in which milestone,
   when.
2. **Review findings** — every non-LOW finding any Phase D round surfaced,
   fixed or not.

For each item: **root cause** (why the process produced it, not just what
broke — a missing rule in a milestone's dispatch prompt? a gap Phase A's
completeness gate should have caught but didn't?), a **confidence level**
(High/Medium/Low) on that diagnosis, and a **remediation** framed through a
named principle (KISS/YAGNI/SRP/DRY/JIT) — a remediation with no named
principle is probably vague; tighten it.

File the whole analysis as one GH issue labeled `harness`. **Track only — do
not auto-fix.** If neither list has anything, skip the issue and say so
plainly in the final report.

This phase never blocks the Stop condition on its own findings, but it must
have run — see *Stop condition*.

### Stop condition

Done when **all milestones are `complete`** AND **the review depth's rounds
leave no non-LOW findings** on the PR AND **Phase E's retrospective has run**
(filed or explicitly skipped as empty) — the retrospective never blocks on
its own findings, but it must have executed before the run reports itself
ready for merge; don't declare done while it's still pending. Report and hand
back to the user for merge (respect branch protection; surface the approval
choice rather than bypassing silently).

## Harness tool bindings — how each chore's tool is chosen

run-prd delegates four chores: **implementation/TDD**, **code review**,
**isolation assessment**, and **sequencing verification**. It must not *guess*
which tool to use — searching the repo or your user-wide config could match an
unrelated agent, skill, or command and silently do the wrong thing. Instead it
reads an **explicit binding the harness declares**, and falls back only when a
chore is left unbound.

**Where it reads.** Look for an explicit run-prd tool-binding block the harness
provides, keyed by chore, in the repo `CLAUDE.md`, a `.claude/rules/*` file, or a
`.claude/run-prd.bindings.*` file. Match entries by their **exact chore key**,
never by keyword-matching prose. The harness declares, e.g.:

~~~
run-prd bindings:
  tdd:            <tool to implement code plans test-first>
  review.fast:    <tool>
  review.normal:  <tool>
  review.full:    <tool>
  isolation:      <tool>
  planner:        <agent to verify plan sequencing>
~~~

A binding's value may be any form the harness prefers — a raw instruction, a rule,
an agent, a skill, or a slash command. The point is that it is **stated**, not
inferred.

**Precedence, per chore independently:**

| Chore | If the harness binds it | Fallback (binding absent) |
|---|---|---|
| `tdd` | use exactly that | `/ecc:tdd-workflow` |
| `review.fast` (default) | use exactly that | `ecc:code-reviewer` agent |
| `review.normal` | use exactly that | `/ecc:code-review` |
| `review.full` | use exactly that | `/ecc:review-pr` |
| `isolation` | use exactly that | the *isolation inner rubric* below |
| `planner` | use exactly that | **HALT** — this is a precondition, not a runtime search: do not scan installed agents by name; ask the user which planner agent to use or to install one before Phase A step 3 runs |

An **unbound** chore takes its fallback — full stop. Do not substitute a tool
because something in the repo or user config merely *looks* like a
reviewer/tester/router. The whole point of the explicit binding is that the
operator, not the skill's guesswork, chooses; predictability beats cleverness.

**Headless note.** A `planner` HALT (or any other HALT in this skill) has no
one to ask in a headless or scheduled invocation — there, "HALT and ask" means
stop the run and surface the gap clearly in the final report, not block on a
prompt nothing will answer.

### Isolation inner rubric (fallback)

Isolation buys clean context (fewer tokens carried, no cross-talk) at the cost of
subagent spawn overhead and losing in-conversation context. Before a call,
**isolate if ANY** of these hold; else run inline:

- **Context is already large** — carrying the whole conversation into the call
  wastes tokens and risks the window; a fresh agent is cheaper.
- **The unit is self-contained** — its plan lists explicit files, the exact
  change, and an inline verification command, so a cold agent can execute it
  without prior-turn context. Isolation then loses nothing and saves tokens.
- **Independent siblings exist** — multiple file-disjoint plans that could run in
  parallel worktrees (throughput gain).
- **Estimated token/time gain exceeds spawn overhead** — a rough call, not a
  precise budget.

Rules of thumb: **plan generation** usually benefits from the shared PRD context
→ often inline (unless context is large). **TDD implementation** of a
self-contained plan is long and code-heavy → a strong isolate candidate. When you
isolate, say so in the runbook log with the one-line reason (which trigger
fired), so the choice is auditable.

## Code vs non-code classification

Read the generated plan's *Files to Change* / artifacts section:

| Plan changes… | Implement with |
|---|---|
| source, scripts, tests, config-as-code (build files) | resolved TDD workflow (repo pattern, else `/ecc:tdd-workflow`) |
| markdown docs, static config values, content, research notes | general agent |
| both | resolved TDD workflow for code artifacts + general agent for the rest |

When a plan is ambiguous or mixed, prefer the TDD path for anything executable —
the cost of skipping tests on real code is higher than a few wasted turns on
prose.

## Safety gates (apply throughout)

- **Destructive-action tiering.** Proceed on non-destructive (add file, update
  ref, in-repo rename) and recoverable (delete git-tracked file — log it). **HALT
  and ask** on non-recoverable: `git push --force`, history rewrite of pushed
  commits, dropping data, deleting untracked files with no history, touching
  CI/CD affecting live deploys. This tiering is unconditional — it applies the
  same whether the run is in `--confirm` mode or the fully-unattended default;
  *Confirmation model* governs planning pauses only, never this gate.
- **Never gate completion on parsed child stdout.** An isolated `claude -p` can
  exit 0 with empty output. Decide "done" only from **observable post-conditions**:
  the plan file exists, tests are green, the `Status` cell is written, the PR
  exists, the review reports no non-LOW. This is why the PRD `Status` column, not
  a captured string, is the state.
- **One PR discipline.** Do not split the run across PRs; do not merge silently.

## Resume / checkpoint

A rerun reads the PRD `Status` column and resumes at the first `pending`
milestone — completed ones are skipped, not rebuilt. If the run was interrupted
mid-implementation (a milestone left `in-progress`), re-verify that milestone's
partial state on disk before continuing rather than assuming it's untouched.

**A *complete* runbook is different from a partial one.** If
`.claude/runbooks/<prd-slug>.runbook.md` exists and its Stop condition was
already met (every milestone `complete`, both review passes clean), that's
not a resume case — the run already finished once. Before touching anything,
ask the user to choose:

- **Re-execute** — treat it as a fresh run: reset milestone `Status` cells the
  user wants rebuilt (confirm scope — all of them, or specific ones), and
  proceed through Phase 0 onward as normal.
- **Validate** — check whether the PRD or any resource its plans/milestones
  depend on (referenced files, external services, prior "Verified findings")
  has drifted since completion, without redoing the implementation work.
  Report drift found, if any, and stop — do not silently re-implement.

This prompt fires even in the default unattended mode — it is a one-time
disambiguation about *which* run this is, not a per-milestone planning pause,
so it is not something *Confirmation model* skips.

## Report at the end

```
run-prd: <prd-name>

Worktree:     <path> (created via EnterWorktree | reused existing)
Mode:         <unattended (default) | --confirm>
Milestones:   <n> complete / <total>
Plans:        <list of .plan.md written>
Implement:    TDD via <repo pattern | /ecc:tdd-workflow> · <x> code plans, <y> non-code
PR:           <url or number>
Review:       mode=<fast|normal|full> via <resolved reviewer> · non-LOW fixed: <k>[ +<j> isolated 2nd pass]
Deferred:     <follow-up issue # for LOW/out-of-scope, or none>
Deviations:   <none | n logged — see runbook `## Deviations`>
Isolation:    via <repo tool | inner rubric> · <count inline vs isolated, reasons logged in the runbook>

Stop condition met: <yes/no>.  Ready for merge: <yes — with caveats / no>.
```

## When NOT to use this

- A PRD with a single milestone, or milestones with no real dependency
  chain — the worktree isolation, runbook, and phased gating overhead isn't
  worth it. Just run `/ecc:plan` once and implement directly.
- The user wants to watch/direct each milestone live — this skill's model is
  autonomous progression through milestones; for live approval per step,
  don't invoke run-prd, drive it turn by turn instead.
